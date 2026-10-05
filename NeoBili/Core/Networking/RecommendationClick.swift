import Foundation

/// A captured-at-click snapshot. No access key, Cookie or ticket is stored here.
struct RecommendationClick: Codable, Sendable {
    typealias Context = AppDeviceSnapshot
    static let event = "tm.recommend.main-card.0.click"
    // Fixed protocol tag in all decoded records, not a unique event counter.
    static let logID = "001538"
    let id: UUID
    let context: Context
    let timestamp: Int
    let accountSession: UUID
    let fields: [String: String]

    static func make(video: VideoSummary, context: Context, accountSession: UUID,
                     timestamp: Int) -> Self? {
        guard video.recommendationTarget == nil, video.playbackEntry.source == .recommendation,
              video.playbackEntry.loginSessionID == accountSession,
              let original = video.recommendationClickFields,
              let track = video.playbackEntry.trackID, !track.isEmpty else { return nil }
        var fields = original
        fields.merge(["track_id": track, "event": "card_click", "event_policy": "0", "page_from": "1"]) { _, new in new }
        // NeoBili has no inline autoplay; do not claim the official preview state.
        guard fields.count <= 40, fields.allSatisfy({ $0.key.utf8.count <= 100 && $0.value.utf8.count <= 4096 }) else { return nil }
        return .init(id: UUID(), context: context, timestamp: timestamp, accountSession: accountSession, fields: fields)
    }

    func payload(uploadTime: Int) -> Data {
        AppBehaviorEncoder.clickPayload(self, uploadTime: uploadTime)
    }

    func body(uploadTime: Int) throws -> Data {
        try AppBehaviorEncoder.clickBody(self, uploadTime: uploadTime)
    }
}

actor RecommendationClickReporter {
    static let shared = RecommendationClickReporter(directory: AppNetwork.isRegression ? nil :
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecommendationClickQueue", isDirectory: true))
    private let directory: URL?
    private let identity: DeviceIdentity
    private let client: APIClient
    private var queue: [RecommendationClick] = []
    private var sending = false

    init(directory: URL? = nil, identity: DeviceIdentity = .shared, client: APIClient = .shared) {
        self.directory = directory; self.identity = identity; self.client = client
        if let url = directory?.appendingPathComponent("pending.json"),
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int, size <= 1024 * 1024,
           let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([RecommendationClick].self, from: data) {
            queue = Array(saved.suffix(100))
        }
    }

    /// UI calls this only from the actual video Button action, never a preload.
    @MainActor static func record(_ video: VideoSummary) {
        let session = DeviceIdentity.shared.loginSessionID
        let time = Int(Date().timeIntervalSince1970 * 1000)
        Task { await shared.record(video, session: session, timestamp: time) }
    }
    func record(_ video: VideoSummary, session: UUID, timestamp: Int) async {
        guard let context = try? await identity.appDeviceSnapshot(expectedSessionID: session),
              let event = RecommendationClick.make(video: video, context: context, accountSession: session, timestamp: timestamp),
              identity.loginSessionID == session else { return }
        queue.append(event)
        trim(now: timestamp, context: context, session: session)
        persist()
        await flush()
    }
    func flush() async {
        guard !sending else { return }
        sending = true
        defer { sending = false }
        let session = identity.loginSessionID
        guard let account = try? await client.appAccount(expectedSessionID: session),
              let context = try? await identity.appDeviceSnapshot(expectedSessionID: session), account.mid == context.mid else { return }
        trim(now: Int(Date().timeIntervalSince1970 * 1000), context: context, session: session)
        persist()
        while let event = queue.first, identity.loginSessionID == session {
            do {
                let headers = try await identity.appRequestHeaders(expectedSessionID: session)
                let body = try event.body(uploadTime: Int(Date().timeIntervalSince1970 * 1000))
                try await client.postRecommendationClick(body: body, headers: headers, expectedSessionID: session)
                queue.removeAll { $0.id == event.id }; persist()
            } catch {
                // Retain only failures known to occur before a connection. A timeout
                // or HTTP rejection may already have counted the click: do not replay it.
                if let error = error as? URLError,
                   [.notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost].contains(error.code) { return }
                queue.removeAll { $0.id == event.id }; persist()
                return
            }
        }
    }
    private func trim(now: Int, context: RecommendationClick.Context, session: UUID) {
        queue.removeAll {
            $0.context.mid != context.mid || $0.context.accountEpoch != context.accountEpoch ||
            $0.timestamp < now - 24 * 60 * 60 * 1000 || $0.timestamp > now + 60_000 ||
            ($0.context.startSession == context.startSession && $0.accountSession != session)
        }
        if queue.count > 100 { queue.removeFirst(queue.count - 100) }
    }
    private func persist() {
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent("pending.json")
            try JSONEncoder().encode(queue).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Telemetry persistence must never interrupt navigation or playback.
        }
    }
}
