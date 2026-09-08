import Foundation
import Observation

/// 全列表共用的画幅判断。详情沿用播放预取的请求合并，过滤本身不请求播放地址。
@MainActor @Observable
final class PortraitVideoStore {
    static let shared = PortraitVideoStore(metadataLoader: loadMetadata)
    private static let maximumConcurrentRequests = 50

    struct Request: Sendable {
        let bvid: String
        let requiringDuration: Bool
    }

    struct Metadata {
        let dimension: VideoDimension?
        let durationSeconds: Int?
    }

    private static func loadMetadata(_ bvid: String) async throws -> Metadata {
        let detail = try await VideoPreparationCache.shared.detail(for: bvid)
        return Metadata(dimension: detail.dimension, durationSeconds: detail.duration)
    }

    private struct Entry: Codable {
        let portrait: Bool?
        var durationSeconds: Int? = nil
        var durationChecked: Bool? = nil
        let expiresAt: Date
    }

    private static let storageKey = "neobili.portraitVideoCache.v1"
    private var entries: [String: Entry]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let loader: @MainActor (String) async throws -> Metadata
    /// 取消标志由 cancellation handler 同步设置，排队出列时不会错过取消信号。
    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private struct Subscriber {
        let flag: CancellationFlag
        let continuation: CheckedContinuation<Void, Never>
    }

    private final class SharedRequest {
        var subscribers: [UUID: Subscriber] = [:]
        var task: Task<Void, Never>?
    }

    @ObservationIgnored private var requests: [String: SharedRequest] = [:]
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var activeRequests = 0

    var queuedRequestCount: Int { requests.values.filter { $0.task == nil }.count }
    func subscriberCount(for bvid: String) -> Int { requests[bvid]?.subscribers.count ?? 0 }

    convenience init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
                     loader: @escaping @MainActor (String) async throws -> VideoDimension?) {
        self.init(defaults: defaults, now: now, metadataLoader: { bvid in
            Metadata(dimension: try await loader(bvid), durationSeconds: nil)
        })
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         metadataLoader: @escaping @MainActor (String) async throws -> Metadata) {
        self.defaults = defaults
        self.now = now
        self.loader = metadataLoader
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = saved.filter { $0.value.expiresAt > now() }
    }

    func hasFreshAttempt(bvid: String, requiringDuration: Bool = false) -> Bool {
        guard let entry = entries[bvid] else { return false }
        return entry.expiresAt > now() && (!requiringDuration || entry.durationChecked == true)
    }

    func durationSeconds(bvid: String) -> Int? {
        guard let entry = entries[bvid], entry.expiresAt > now(),
              let duration = entry.durationSeconds, duration > 0 else { return nil }
        return duration
    }

    func isPortrait(bvid: String) -> Bool? {
        guard let entry = entries[bvid], entry.expiresAt > now() else { return nil }
        return entry.portrait
    }

    /// 页面离开、开关关闭或列表变化时，停止继续排入新请求。
    /// 已开始的共享请求完成后仍保存结果，其他页面可继续复用。
    func resolve(_ bvids: [String], requiringDuration: Bool = false) async {
        await resolveRequests(bvids.map { Request(bvid: $0, requiringDuration: requiringDuration) })
    }

    func resolveRequests(_ requests: [Request]) async {
        var requirements: [String: Bool] = [:]
        var order: [String] = []
        for request in requests where !request.bvid.isEmpty {
            if requirements[request.bvid] == nil { order.append(request.bvid) }
            requirements[request.bvid] = (requirements[request.bvid] ?? false) || request.requiringDuration
        }
        let pending = order.compactMap { bvid -> Request? in
            let duration = requirements[bvid] == true
            guard !hasFreshAttempt(bvid: bvid, requiringDuration: duration) else { return nil }
            return Request(bvid: bvid, requiringDuration: duration)
        }
        var iterator = pending.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<Self.maximumConcurrentRequests {
                guard !Task.isCancelled, let request = iterator.next() else { break }
                group.addTask { await self.resolveOne(request.bvid, requiringDuration: request.requiringDuration) }
            }
            for await _ in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let request = iterator.next() {
                    group.addTask { await self.resolveOne(request.bvid, requiringDuration: request.requiringDuration) }
                }
            }
        }
    }

    private func resolveOne(_ bvid: String, requiringDuration: Bool) async {
        guard !Task.isCancelled, !hasFreshAttempt(bvid: bvid, requiringDuration: requiringDuration) else { return }
        let subscriberID = UUID()
        let flag = CancellationFlag()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !flag.isCancelled, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                let request: SharedRequest
                if let existing = requests[bvid] { request = existing }
                else {
                    request = SharedRequest()
                    requests[bvid] = request
                    queue.append(bvid)
                }
                request.subscribers[subscriberID] = Subscriber(flag: flag, continuation: continuation)
                startQueuedRequests()
            }
        } onCancel: {
            flag.cancel()
            Task { @MainActor in self.cancelSubscriber(subscriberID, bvid: bvid) }
        }
    }

    private func cancelSubscriber(_ id: UUID, bvid: String) {
        guard let request = requests[bvid], let subscriber = request.subscribers.removeValue(forKey: id) else { return }
        subscriber.continuation.resume()
        // 已开始的共享请求照常缓存结果；还在排队且无人等待的请求直接移除。
        if request.task == nil, request.subscribers.isEmpty {
            requests[bvid] = nil
            queue.removeAll { $0 == bvid }
        }
    }

    private func startQueuedRequests() {
        while activeRequests < Self.maximumConcurrentRequests, !queue.isEmpty {
            let bvid = queue.removeFirst()
            guard let request = requests[bvid], request.task == nil else { continue }
            let cancelled = request.subscribers.filter { $0.value.flag.isCancelled }.map(\.key)
            for id in cancelled {
                request.subscribers.removeValue(forKey: id)?.continuation.resume()
            }
            guard !request.subscribers.isEmpty else {
                requests[bvid] = nil
                continue
            }
            activeRequests += 1
            request.task = Task {
                await self.fetch(bvid)
                let subscribers = request.subscribers.values
                request.subscribers.removeAll()
                self.requests[bvid] = nil
                request.task = nil
                self.activeRequests -= 1
                subscribers.forEach { $0.continuation.resume() }
                self.startQueuedRequests()
            }
        }
    }

    private func fetch(_ bvid: String) async {
        let metadata = try? await loader(bvid)
        let portrait = metadata?.dimension.flatMap { $0.isValid ? $0.isPortrait : nil }
        // 已知结果保留七天；失败或详情也无尺寸时冷却五分钟，不能永久当作横屏。
        entries[bvid] = Entry(portrait: portrait,
                              durationSeconds: metadata?.durationSeconds,
                              durationChecked: true,
                              expiresAt: now().addingTimeInterval(portrait == nil ? 300 : 7 * 86_400))
        entries = entries.filter { $0.value.expiresAt > now() }
        if entries.count > 2_000 {
            entries = Dictionary(uniqueKeysWithValues: entries.sorted {
                $0.value.expiresAt > $1.value.expiresAt
            }.prefix(2_000).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
