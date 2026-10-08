import SwiftUI
import UIKit

/// 格子共享的页面状态。只有分隔条读它，刷新开始、结束时只有分隔条重算。
@MainActor @Observable
final class HomeFeedCellState {
    private(set) var isRefreshing = false

    func setRefreshing(_ value: Bool) {
        if isRefreshing != value { isRefreshing = value }
    }
}

/// One SwiftUI root per native cell: one video or the full-width marker.
struct HomeFeedCellView: View {
    let item: HomeFeedItem
    let viewModel: HomeViewModel
    let state: HomeFeedCellState
    let entranceStart: TimeInterval?
    let onOpenLastSeen: () -> Void
    var preview: HomeInlinePreview? = nil

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch item {
        case .video(let video):
            GeometryReader { geometry in
                videoSlot(video, size: geometry.size)
            }
        case .lastSeen:
            TimedFeedEntrance(start: entranceStart, reduceMotion: reduceMotion) {
                Button(action: onOpenLastSeen) {
                    LastSeenCard()
                }
                .buttonStyle(.plain)
                .disabled(state.isRefreshing)
            }
        }
    }

    private func videoSlot(_ video: VideoSummary, size: CGSize) -> some View {
        TimedFeedEntrance(start: entranceStart, reduceMotion: reduceMotion) {
            videoCard(video, size: size)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder
    private func videoCard(_ video: VideoSummary, size: CGSize) -> some View {
        let titleWidth = max(0, size.width - HomeCardLayout.detailsHorizontalPadding * 2)
        Button {
            switch video.recommendationTarget {
            case .live(let room):
                nowPlaying.openLive(room, from: video.bvid)
            case .dynamic(let id):
                viewModel.sheet = .dynamic(id: id)
            case nil:
                ApplicationServices.live.telemetry.click(video)
                nowPlaying.open(
                    VideoDetailRoute(bvid: video.bvid, cid: video.cid > 0 ? video.cid : nil, cover: video.pic,
                                     title: video.title, artist: video.owner.name, aid: video.aid, playbackEntry: video.playbackEntry),
                    from: video.bvid
                )
            }
        } label: {
            Group {
                #if PERFORMANCE_DEMO
                if !ProcessInfo.processInfo.arguments.contains("--swiftui-feed-cards") {
                    NativeHomeVideoCard(video: video, titleWidth: titleWidth)
                } else {
                    HomeVideoCard(video: video, titleWidth: titleWidth)
                }
                #else
                NativeHomeVideoCard(video: video, titleWidth: titleWidth,
                    coverAspectRatio: video.isLargeRecommendationCard ? HomeCardLayout.largeCoverAspectRatio : HomeCardLayout.coverAspectRatio)
                #endif
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                if video.isLargeRecommendationCard {
                    ZStack(alignment: .bottom) {
                        if let preview, preview.videoID == video.bvid, let session = preview.session {
                            PlayerSurface(session: session)
                                .opacity(preview.hasFirstFrame ? 1 : 0)
                        }
                        HomeLargeCoverOverlay(video: video,
                            isPlaying: preview?.videoID == video.bvid && preview?.hasFirstFrame == true)
                        if let preview { HomeInlinePreviewProgress(videoID: video.bvid, preview: preview) }
                    }
                    .frame(width: size.width, height: size.width / HomeCardLayout.largeCoverAspectRatio)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7))
                    .allowsHitTesting(false)
                }
            }
            // Both this source and its native hosting cell contain one card.
            .videoTransitionSource(video.bvid, in: videoTransition)
            .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            // 和 PiliPlus 一样，只有视频卡有菜单；直播、图文卡没有这些操作。
            // 菜单项顺序照 PiliPlus：BV 号、稍后再看、访问 UP、不感兴趣、拉黑。
            if video.recommendationTarget == nil {
                Button("复制 \(video.bvid)", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = video.bvid
                    feedback.show(String(localized: "已复制"))
                }
                WatchLaterMenuButton(aid: video.aid, bvid: video.bvid)
                if video.owner.mid > 0 {
                    Button("访问：\(video.owner.name)", systemImage: "person.crop.circle") {
                        viewModel.sheet = .space(FollowedUp(mid: video.owner.mid, uname: video.owner.name,
                                                            face: video.owner.face, hasUpdate: false))
                    }
                }
                uninterestedMenu(video)
                if video.owner.mid > 0 {
                    Button("拉黑：\(video.owner.name)", systemImage: "nosign", role: .destructive) {
                        if account.isLoggedIn {
                            viewModel.pendingBlock = video.owner
                        } else {
                            feedback.show(String(localized: "请先登录"))
                        }
                    }
                }
            }
        }
        .task(id: video.bvid) {
            guard video.recommendationTarget == nil else { return }
            // 快速滑过的卡片不预取：停留一会儿才请求播放地址，
            // 免得一次甩动排进几十个网络请求和解析。
            await VideoPreparationCache.shared.prefetchWhenSettled(bvid: video.bvid, cid: video.cid > 0 ? video.cid : nil)
        }
    }

    /// 照 PiliPlus：列出卡片自带的「我不想看」和「反馈」原因，选一个提交；末尾可撤销。
    @ViewBuilder
    private func uninterestedMenu(_ video: VideoSummary) -> some View {
        if account.isLoggedIn, let options = video.recommendationFeedback, options.hasReasons {
            Menu("不感兴趣", systemImage: "hand.thumbsdown") {
                if let reasons = options.dislikeReasons {
                    Section("我不想看") { reasonButtons(reasons, video: video) }
                }
                if let reasons = options.feedbacks {
                    Section("反馈") { reasonButtons(reasons, video: video) }
                }
                Section {
                    Button("撤销", systemImage: "arrow.uturn.backward") {
                        Task {
                            if let message = await viewModel.cancelUninterested(video) { feedback.show(message) }
                        }
                    }
                }
            }
            .disabled(viewModel.reportingIDs.contains(video.bvid))
        } else if account.isLoggedIn, video.isWebRecommendation {
            Menu("不感兴趣", systemImage: "hand.thumbsdown") {
                Section("网页端暂不支持精细选择") {
                    Button("点踩", systemImage: "hand.thumbsdown") { dislikeWeb(video, dislike: true) }
                    Button("撤销", systemImage: "arrow.uturn.backward") { dislikeWeb(video, dislike: false) }
                }
            }
            .disabled(viewModel.reportingIDs.contains(video.bvid))
        } else {
            Button("不感兴趣", systemImage: "hand.thumbsdown") {
                feedback.show(account.isLoggedIn ? String(localized: "这条推荐没有提供不感兴趣选项")
                              : String(localized: "账号未登录"))
            }
        }
    }

    private func dislikeWeb(_ video: VideoSummary, dislike: Bool) {
        Task {
            if let message = await viewModel.dislikeWebRecommendation(video, dislike: dislike) { feedback.show(message) }
        }
    }

    private func reasonButtons(_ reasons: [RecommendationFeedbackOptions.Reason], video: VideoSummary) -> some View {
        ForEach(reasons, id: \.self) { reason in
            Button(reason.name ?? String(localized: "未知")) {
                Task {
                    if let message = await viewModel.markUninterested(video, reason: reason) { feedback.show(message) }
                }
            }
        }
    }
}

/// Playback ticks update only this bar, not the card's hosting tree and native cover.
private struct HomeInlinePreviewProgress: View {
    let videoID: String
    let preview: HomeInlinePreview

    var body: some View {
        if preview.videoID == videoID, preview.duration > 0 {
            ProgressView(value: min(preview.progress / preview.duration, 1))
                .tint(.accentColor).frame(height: 2)
        }
    }
}

/// The same foreground remains in place when cover pixels switch to video pixels.
struct HomeLargeCoverOverlay: View {
    let video: VideoSummary
    var isPlaying: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black.opacity(0.2), location: 0.4),
                                   .init(color: .black.opacity(0.6), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 52)
            HStack(spacing: 8) {
                stat(video.stat.view.biliCountText, icon: "play.rectangle")
                stat(video.stat.danmaku.biliCountText, icon: "text.bubble")
                Spacer(minLength: 8)
                ZStack(alignment: .trailing) {
                    Text(video.coverCornerText).opacity(isPlaying ? 0 : 1)
                    Image(systemName: "speaker.slash.fill").opacity(isPlaying ? 1 : 0)
                        .accessibilityLabel("静音预览")
                }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func stat(_ value: String, icon: String) -> some View {
        HStack(spacing: 2) { Image(systemName: icon); Text(value) }
    }
}
