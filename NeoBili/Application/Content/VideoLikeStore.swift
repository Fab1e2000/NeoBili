import Foundation

/// 按 aid 保存会话内的点赞差量，视频详情和关注动态共享。
/// 差量优先于接口快照，避免延迟回读覆盖刚完成的操作。
@MainActor
@Observable
final class VideoLikeStore {
    private(set) var sessionID = UUID()

    func resetSession() {
        sessionID = UUID()
        overrides.removeAll()
    }

    private var overrides: [Int: Bool] = [:]

    /// 展示用状态：本地差量优先，没有差量时用接口快照。
    func isLiked(aid: Int, serverValue: Bool) -> Bool {
        overrides[aid] ?? serverValue
    }

    /// 乐观更新。请求失败时用同一方法把旧值写回去。
    func setOverride(aid: Int, liked: Bool, sessionID: UUID? = nil) {
        if let sessionID, sessionID != self.sessionID { return }
        overrides[aid] = liked
    }

}
