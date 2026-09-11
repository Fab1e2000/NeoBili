import Foundation
import Observation

/// 开播信息独立加载，慢直播接口不阻塞动态首屏、刷新或 UP 切换。
@MainActor
@Observable
final class FollowedLiveDirectory {
    typealias Loader = @Sendable (Int) async throws -> LiveRoomPage
    private(set) var rooms: [LiveRoom] = []
    private var generation = UUID()
    private var activeRefresh: UUID?
    private var lastSuccess: Date?
    private let loader: Loader
    private let now: () -> Date

    init(loader: @escaping Loader = { try await LiveAPI.followed(page: $0) }, now: @escaping () -> Date = Date.init) {
        self.loader = loader
        self.now = now
    }

    func refresh(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        if !force {
            guard activeRefresh == nil else { return }
            if let lastSuccess {
                let age = now().timeIntervalSince(lastSuccess)
                if age >= 0, age < 60 { return }
            }
        }
        let request = UUID()
        generation = request
        activeRefresh = request
        defer {
            if generation == request { activeRefresh = nil }
        }
        let previous = rooms
        var incoming: [LiveRoom] = []
        var seen = Set<Int>()
        var pageSignatures = Set<Set<Int>>()
        do {
            // 服务端分页按全部关注计算，某页没有正在直播的 UP 时仍须继续。
            for page in 1...100 {
                try Task.checkCancellation()
                let result = try await loader(page)
                guard generation == request, !Task.isCancelled else { return }
                // The API may filter every offline room from its visible result.
                // Compare raw room IDs instead of interpreting an empty live
                // addition as a repeated page or as everybody going offline.
                let signature = Set((result.sourceRoomIDs ?? result.rooms.map(\.roomID)).filter { $0 > 0 })
                if !signature.isEmpty, !pageSignatures.insert(signature).inserted { return }
                let additions = result.rooms.filter {
                    $0.isLive && $0.uid > 0 && $0.roomID > 0 && seen.insert($0.uid).inserted
                }
                incoming.append(contentsOf: additions)
                if !additions.isEmpty {
                    // Publish confirmed live UPs page by page. Keep unmatched
                    // cached UPs until a complete scan proves they went offline.
                    rooms = incoming + previous.filter { !seen.contains($0.uid) }
                }
                if !result.hasMore {
                    rooms = incoming
                    lastSuccess = now()
                    return
                }
            }
        } catch {
            // Keep both previously known rooms and any newly confirmed live UPs.
            // A failed/cancelled scan is not a complete offline snapshot and is
            // intentionally not cached as a successful refresh.
        }
    }

    func reset() {
        generation = UUID()
        activeRefresh = nil
        rooms = []
        lastSuccess = nil
    }
}
