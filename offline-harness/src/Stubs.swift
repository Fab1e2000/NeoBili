import Foundation

/// 离线测试桩：PortraitVideoStore 默认 loader 引用的播放预取缓存在 App 里
/// 依赖 mpv/SwiftUI。宿主机上它只需返回确定性的详情数据，让 shared store
/// 的补查路径可以在测试里真实走通。
actor VideoPreparationCache {
    static let shared = VideoPreparationCache()

    func detail(for bvid: String) async throws -> VideoDetail {
        VideoDetail(
            bvid: bvid,
            aid: 1,
            cid: 1,
            title: bvid,
            desc: "",
            pic: "",
            duration: 700,
            pubdate: 0,
            owner: VideoOwner(mid: 1, name: "UP", face: ""),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
            pages: [],
            dimension: VideoDimension(width: 1920, height: 1080),
            tname: nil,
            copyright: nil,
            ugcSeason: nil
        )
    }
}

/// AccountStore（依赖 SwiftUI/Network）里的凭据快照，测试只需要这个形状。
struct AccountCredentialsSnapshot: Sendable {
    let hasCredentials: Bool
    let accountID: Int?
}
