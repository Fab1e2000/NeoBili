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
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeRequests = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

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
        if let task = tasks[bvid] {
            await task.value
            return
        }
        // MainActor 上原子登记，跨列表同一个 BV 仍只补查一次。
        let task = Task {
            await self.fetch(bvid)
            self.tasks[bvid] = nil
        }
        tasks[bvid] = task
        await task.value
    }

    private func fetch(_ bvid: String) async {
        if activeRequests >= Self.maximumConcurrentRequests {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            activeRequests += 1
        }
        defer {
            if waiters.isEmpty { activeRequests -= 1 }
            else { waiters.removeFirst().resume() }
        }

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
