import Foundation

/// Immutable event-time facts. Credentials are acquired only when sending.
struct AppBehaviorEvent: Codable, Sendable {
    let id: UUID
    let context: AppDeviceSnapshot
    let accountSession: UUID
    let timestamp: Int
    let name: String
    let category: Int
    let fields: [String: String]
    let player: Data?
    var realtime: Bool { category == 3 }
    var estimatedBytes: Int {
        1024 + name.utf8.count + (player?.count ?? 0) * 2 + 6 * fields.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
    }
}

actor AppBehaviorReporter {
    static let shared = AppBehaviorReporter(directory: AppNetwork.isRegression ? nil :
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BehaviorQueue", isDirectory: true))
    typealias Sender = @Sendable ([AppBehaviorEvent]) async throws -> Void
    private let identity: DeviceIdentity
    private let client: APIClient
    private let directory: URL?
    private let sender: Sender?
    private let snapshotProvider: (@Sendable (UUID) async throws -> AppDeviceSnapshot)?
    private let now: @Sendable () -> TimeInterval
    private let automaticScheduling: Bool
    private var pending: [AppBehaviorEvent] = []
    private var savedIDs: [UUID] = []
    private var scheduled: Task<Void, Never>?
    private var scheduleID: UUID?
    private var sending = false
    private var background = false
    private var retryAfter: TimeInterval = 0

    init(identity: DeviceIdentity = .shared, client: APIClient = .shared, directory: URL? = nil,
         automaticScheduling: Bool = true, now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
         sender: Sender? = nil,
         snapshotProvider: (@Sendable (UUID) async throws -> AppDeviceSnapshot)? = nil) {
        self.identity = identity; self.client = client; self.directory = directory
        self.automaticScheduling = automaticScheduling; self.now = now; self.sender = sender
        self.snapshotProvider = snapshotProvider
        if let url = directory?.appendingPathComponent("pending.json"),
           let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
           size <= 1024 * 1024, let data = try? Data(contentsOf: url),
           let events = try? JSONDecoder().decode([AppBehaviorEvent].self, from: data) {
            pending = Array(events.suffix(100)); savedIDs = pending.map(\.id)
        }
    }

    func record(name: String, category: Int, fields: [String: String], player: Data? = nil,
                session: UUID, timestamp: Int) async {
        guard name.utf8.count <= 256, (player?.count ?? 0) <= 16_384, fields.count <= 40,
              fields.allSatisfy({ $0.key.utf8.count <= 100 && $0.value.utf8.count <= 4096 }),
              fields.reduce(0, { $0 + $1.key.utf8.count + $1.value.utf8.count }) <= 16_384,
              let snapshot = try? await identity.nextBehaviorSnapshot(expectedSessionID: session),
              identity.loginSessionID == session else { return }
        pending.append(.init(id: UUID(), context: snapshot, accountSession: session, timestamp: timestamp,
                             name: name, category: category, fields: fields, player: player))
        trim(context: snapshot, session: session)
        if background { persist(); return }
        schedule()
    }

    /// One coalesced wake-up per burst, not a repeating timer. Offline records only persist.
    private func schedule() {
        guard automaticScheduling, scheduled == nil, !pending.isEmpty, !background else { return }
        let id = UUID(); scheduleID = id
        let delay = now() >= retryAfter && pending.contains(where: \.realtime) ? 0.25 : 3.0
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.scheduledFlush(id)
        }
    }
    private func scheduledFlush(_ id: UUID) async {
        guard scheduleID == id else { return }
        await flush()
        guard scheduleID == id else { return }
        scheduled = nil; scheduleID = nil
        // An offline queue sleeps until a new real event or activation, never polls.
        if now() >= retryAfter { schedule() }
    }

    func setBackground(_ value: Bool) async {
        background = value
        scheduled?.cancel(); scheduled = nil; scheduleID = nil
        if value { await checkpoint() } else { await flush() }
    }

    private func snapshot(_ session: UUID) async throws -> AppDeviceSnapshot {
        if let snapshotProvider { return try await snapshotProvider(session) }
        return try await identity.appDeviceSnapshot(expectedSessionID: session)
    }

    func checkpoint() async {
        let session = identity.loginSessionID
        guard let context = try? await snapshot(session), identity.loginSessionID == session else { return }
        trim(context: context, session: session)
        persist()
    }

    func flush() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        while !pending.isEmpty {
            let session = identity.loginSessionID
            guard let context = try? await snapshot(session), identity.loginSessionID == session else { return }
            trim(context: context, session: session)
            guard persist() else { retryAfter = now() + 60; return }
            guard !background, now() >= retryAfter, let first = pending.first else { return }
            let batch = Array(pending.prefix(20).prefix { $0.realtime == first.realtime })
            let ids = Set(batch.map(\.id))
            // Remove durably before sending: crash/timeout after server acceptance cannot replay it.
            pending.removeAll { ids.contains($0.id) }
            guard persist() else {
                pending.insert(contentsOf: batch, at: 0)
                retryAfter = now() + 60
                return
            }
            do {
                if let sender { try await sender(batch) }
                else {
                    let body = try AppBehaviorEncoder.behaviorBody(batch, uploadTime: Int(now() * 1000))
                    let headers = try await identity.appRequestHeaders(expectedSessionID: session)
                    try await client.postRecommendationClick(body: body, eventCount: batch.count, headers: headers,
                        expectedSessionID: session, realtime: first.realtime)
                }
            } catch {
                retryAfter = now() + 60
                if let error = error as? URLError,
                   [.notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost].contains(error.code),
                   identity.loginSessionID == session {
                    pending.insert(contentsOf: batch, at: 0)
                    trim(context: context, session: session); persist()
                }
                // Ambiguous writes are not replayed; all failures stop this burst.
                return
            }
        }
    }

    private func trim(context: AppDeviceSnapshot, session: UUID) {
        let time = Int(now() * 1000)
        pending.removeAll {
            $0.context.mid != context.mid || $0.context.accountEpoch != context.accountEpoch ||
            $0.context.buvid != context.buvid || $0.timestamp < time - 86_400_000 || $0.timestamp > time + 60_000 ||
            ($0.context.startSession == context.startSession && $0.accountSession != session)
        }
        if pending.count > 100 { pending.removeFirst(pending.count - 100) }
        var bytes = pending.reduce(0) { $0 + $1.estimatedBytes }
        while bytes > 512 * 1024, !pending.isEmpty { bytes -= pending.removeFirst().estimatedBytes }
    }

    @discardableResult
    private func persist() -> Bool {
        guard let directory, savedIDs != pending.map(\.id) else { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(pending)
            guard data.count <= 1024 * 1024 else { return false }
            let url = directory.appendingPathComponent("pending.json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            savedIDs = pending.map(\.id)
            return true
        } catch { return false }
    }
}
