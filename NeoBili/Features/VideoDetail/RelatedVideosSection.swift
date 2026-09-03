import SwiftUI

/// 简介下方的官方相关视频推流。
///
/// 数据来自 `x/web-interface/archive/related`，是 B 站针对当前这个视频算出来的
/// 关联稿件，和首页那条按整体兴趣出内容的推荐流不是一回事。
///
/// 卡片直接用搜索页那一套 `VideoListCard`，两处样式始终保持一致。
struct RelatedVideosSection: View {
    let videos: [VideoSummary]
    let isLoading: Bool
    let onSelect: (VideoSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VideoListCardLayout.cardVerticalSpacing * 2) {
            if videos.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    Text("暂时没有相关视频")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
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
                            durationText: video.formattedDuration
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                    // 出现在屏幕上就先把播放地址取回来，点开时通常已经有结果了。
                    .task {
                        await VideoPreparationCache.shared.prefetch(
                            bvid: video.bvid,
                            cid: video.cid
                        )
                    }
                }
            }
        }
    }
}
