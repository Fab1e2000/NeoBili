import Foundation
import Observation

@MainActor
@Observable
final class LiveRoomFollowModel {
    struct Context: Hashable, Sendable {
        let mid: Int
        let sessionID: UUID
        let isLoggedIn: Bool
        let accountID: Int?
        var isOwnAccount: Bool { accountID == mid && isLoggedIn }
    }

    typealias CardLoader = @Sendable (Int) async throws -> SpaceCard
    typealias RelationWriter = @Sendable (Int, Bool) async throws -> Void

    private(set) var card: SpaceCard?
    private(set) var isFollowing: Bool?
    private(set) var isLoading = false
    private(set) var isToggling = false
    private(set) var errorMessage: String?
    private var context: Context?
    private var readID = UUID()
    private var writeID = UUID()
    private let cardLoader: CardLoader
    private let relationWriter: RelationWriter

    init(cardLoader: @escaping CardLoader = { try await BiliAPI.spaceCard(mid: $0) },
         relationWriter: @escaping RelationWriter = { try await BiliAPI.modifyRelation(mid: $0, follow: $1) }) {
        self.cardLoader = cardLoader
        self.relationWriter = relationWriter
    }

    func load(_ next: Context, force: Bool = false) async {
        let changed = context != next
        guard changed || force || card == nil && !isLoading else { return }
        if changed {
            if context?.mid != next.mid { card = nil }
            context = next
            writeID = UUID()
            isToggling = false
            isFollowing = next.isLoggedIn ? nil : false
        } else if isToggling { return }
        let request = UUID()
        readID = request
        errorMessage = nil
        guard next.mid > 0 else { isLoading = false; return }
        isLoading = true
        defer { if readID == request { isLoading = false } }
        do {
            let card = try await cardLoader(next.mid)
            guard context == next, readID == request, !Task.isCancelled else { return }
            self.card = card
            isFollowing = next.isLoggedIn ? card.isFollowing : false
        } catch {
            guard context == next, readID == request, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func toggleFollow(_ current: Context) async -> String? {
        guard current.isLoggedIn else { return "请先登录" }
        guard current.mid > 0 else { return "主播资料尚未加载" }
        guard !current.isOwnAccount else { return "不能关注自己" }
        guard context == current, let previous = isFollowing else { return "关注状态尚未加载，请重试" }
        guard !isToggling else { return nil }
        // 写入开始后旧名片响应不能把已关注状态覆盖回去。
        readID = UUID()
        isLoading = false
        let request = UUID()
        writeID = request
        isToggling = true
        isFollowing = !previous
        defer { if writeID == request { isToggling = false } }
        do {
            try await relationWriter(current.mid, !previous)
            guard context == current, writeID == request, !Task.isCancelled else { return nil }
            return previous ? "已取消关注" : "已关注"
        } catch {
            guard context == current, writeID == request else { return nil }
            isFollowing = previous
            return error.isCancellation ? nil : error.localizedDescription
        }
    }
}
