import SwiftUI

/// 首页和搜索页都使用同一种视频路由，避免不同入口给详情页带入不同的导航样式。
struct VideoDetailRoute: Hashable {
    let bvid: String
    /// 推荐列表的卡片本身就带着 cid，可以不等详情接口返回就开始取播放地址，
    /// 详情和播放地址两个请求因此变成并行。搜索结果没有这个值，仍然先取详情。
    var cid: Int?
    /// 列表卡片上那张封面。播放器还没出画面时先显示它，代替一整块黑屏。
    var cover: String?
    /// 列表已知的标题和作者先交给系统媒体中心；详情返回后会再用完整信息更新。
    var title: String?
    var artist: String?

    init(
        bvid: String,
        cid: Int? = nil,
        cover: String? = nil,
        title: String? = nil,
        artist: String? = nil
    ) {
        self.bvid = bvid
        self.cid = cid
        self.cover = cover
        self.title = title
        self.artist = artist
    }

    var secureCoverURL: URL? {
        cover.flatMap { URL.biliSecure($0) }
    }
}

extension VideoDetailRoute: Identifiable {
    var id: String { cid.map { "\(bvid)#\($0)" } ?? bvid }
}
