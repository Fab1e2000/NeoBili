import SwiftUI

/// 简介下方的官方相关视频推流。
///
/// 数据来自 `x/web-interface/archive/related`，是 B 站针对当前这个视频算出来的
/// 关联稿件，和首页那条按整体兴趣出内容的推荐流不是一回事。
///
/// 排版上和搜索页那一套卡片不同：这一页整体是白底 + 细分隔线，卡片不再画
/// 浅色底和圆角边框。视频页上半部分本来就是白底，如果下面接一片灰底卡片区，
/// 两者之间会出现一道生硬的直角色块交界，像两个页面拼在一起。
struct RelatedVideosSection: View {
    /// 和简介正文一致的左右留白，两段内容才对得齐。
    private static let horizontalInset: CGFloat = 16

    let videos: [VideoSummary]
    let isLoading: Bool
    let onSelect: (VideoSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if videos.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    Text("暂时没有相关视频")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Self.horizontalInset)
                }
            } else {
                ForEach(videos) { video in
                    // 相关视频自带 cid，所以点进去时和推荐页一样可以并行加载。
                    Button {
                        onSelect(video)
                    } label: {
                        VideoListCard(
                            coverURL: video.secureCoverURL,
                            title: video.title,
                            author: video.owner.name,
                            playCount: video.stat.view,
                            durationText: video.formattedDuration,
                            showsCardChrome: false
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        WatchLaterMenuButton(aid: video.aid, bvid: video.bvid)
                    }
                    .padding(.horizontal, Self.horizontalInset)
                    .padding(.vertical, 4)
                    // 出现在屏幕上就先把播放地址取回来，点开时通常已经有结果了。
                    .task {
                        await VideoPreparationCache.shared.prefetch(
                            bvid: video.bvid,
                            cid: video.cid
                        )
                    }

                    // 分隔线从封面右边起画，和评论列表那边的处理一致；
                    // 最后一条不画，列表末尾不该悬着一根线。
                    if video.id != videos.last?.id {
                        Divider()
                            .padding(.leading, Self.horizontalInset)
                    }
                }
            }
        }
    }
}
