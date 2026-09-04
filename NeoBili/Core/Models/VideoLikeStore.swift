import Foundation

/// 全 App 共享的视频点赞差量状态：aid -> 是否已赞。
///
/// 视频的「已赞」会在多个界面同时出现：关注流里的视频动态卡片、视频
/// 详情页的操作栏，之后可能还有搜索、相关视频等。它们各自的接口快照
/// 互不相通，本地乐观更新又只写自己那份，于是同一个稿件在不同页面显
/// 示的点赞状态会打架。这里按 aid 记一份会话级差量，所有界面读写同
/// 一份，接口快照只作为没有差量时的回退值。
///
/// 点赞写入成功后接口的回读有延迟（立刻查多半还是旧值），所以差量
/// 一旦写入就保留到会话结束，不被新到的快照覆盖。
@MainActor
@Observable
final class VideoLikeStore {
    private var overrides: [Int: Bool] = [:]

    /// 展示用状态：本地差量优先，没有差量时用接口快照。
    func isLiked(aid: Int, serverValue: Bool) -> Bool {
        overrides[aid] ?? serverValue
    }

    /// 乐观更新。请求失败时用同一方法把旧值写回去。
    func setOverride(aid: Int, liked: Bool) {
        overrides[aid] = liked
    }

    /// 拿到可信的新快照（比如成功写入后的接口回包）时清掉差量。
    /// 普通列表刷新拿到的快照不算——它可能是写入前的旧值。
    func clearOverride(aid: Int) {
        overrides[aid] = nil
    }

    /// 会话级单例：持有它的模型（动态流、视频页）都创建在拿不到
    /// SwiftUI 环境的位置，注入反而要穿透好几层构造链。
    static let shared = VideoLikeStore()
}
