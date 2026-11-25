import Foundation

/// 会话内的点赞差量，动态列表、动态详情和视频详情共享。
@MainActor
@Observable
final class VideoLikeStore {
    enum Target: Hashable {
        case video(Int)
        case dynamic(String)
    }

    private(set) var sessionID = UUID()
    private var overrides: [Target: Bool] = [:]
    @ObservationIgnored private var dynamicFeedWrites: Set<Target> = []

    func resetSession() {
        sessionID = UUID()
        overrides.removeAll()
        dynamicFeedWrites.removeAll()
    }

    func isLiked(aid: Int, serverValue: Bool) -> Bool {
        isLiked(.video(aid), serverValue: serverValue)
    }

    func isLiked(_ target: Target, serverValue: Bool) -> Bool {
        overrideValue(for: target) ?? serverValue
    }

    func overrideValue(for target: Target) -> Bool? {
        overrides[target]
    }

    func setOverride(aid: Int, liked: Bool, sessionID: UUID? = nil) {
        setOverride(.video(aid), liked: liked, sessionID: sessionID)
    }

    func setOverride(_ target: Target, liked: Bool?, sessionID: UUID?) {
        if let sessionID, sessionID != self.sessionID { return }
        overrides[target] = liked
    }

    func beginDynamicFeedWrite(_ target: Target) -> Bool {
        dynamicFeedWrites.insert(target).inserted
    }

    func finishDynamicFeedWrite(_ target: Target, sessionID: UUID) {
        guard sessionID == self.sessionID else { return }
        dynamicFeedWrites.remove(target)
    }
}
