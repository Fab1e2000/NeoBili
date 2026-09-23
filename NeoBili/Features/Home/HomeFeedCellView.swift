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

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed

    var body: some View {
        switch item {
        case .video(let video):
            GeometryReader { geometry in
                videoSlot(video, size: geometry.size)
            }
        case .lastSeen:
            TimedFeedEntrance(start: entranceStart, speed: enterSpeed, reduceMotion: reduceMotion) {
                Button(action: onOpenLastSeen) {
                    LastSeenCard()
                }
                .buttonStyle(.plain)
                .disabled(state.isRefreshing)
            }
        }
    }

    private func videoSlot(_ video: VideoSummary, size: CGSize) -> some View {
        TimedFeedEntrance(start: entranceStart, speed: enterSpeed, reduceMotion: reduceMotion) {
            videoCard(video, size: size)
        }
        .onAppear { viewModel.didShowReplacement(video.bvid) }
        .onChange(of: video.bvid) { viewModel.didShowReplacement(video.bvid) }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder
    private func videoCard(_ video: VideoSummary, size: CGSize) -> some View {
        let titleWidth = max(0, size.width - HomeCardLayout.detailsHorizontalPadding * 2)
        if viewModel.uninterestedIDs.contains(video.bvid) {
            Button {
                Task {
                    if let message = await viewModel.replaceUninterested(video) { feedback.show(message) }
                }
            } label: {
                VStack(spacing: 10) {
                    if viewModel.replacingIDs.contains(video.bvid) {
                        LoadingTaskAnchor()
                    } else {
                        Image(systemName: "eye.slash").font(.title2)
                    }
                    Text("已提交不感兴趣").font(.subheadline)
                    if !viewModel.replacingIDs.contains(video.bvid) {
                        Text("点击重试换一条").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.replacingIDs.contains(video.bvid))
        } else {
            Button {
                nowPlaying.open(
                    VideoDetailRoute(bvid: video.bvid, cid: video.cid, cover: video.pic,
                                     title: video.title, artist: video.owner.name),
                    from: video.bvid
                )
            } label: {
                Group {
                    #if PERFORMANCE_DEMO
                    if !ProcessInfo.processInfo.arguments.contains("--swiftui-feed-cards") {
                        NativeHomeVideoCard(video: video, titleWidth: titleWidth)
                    } else {
                        HomeVideoCard(video: video, titleWidth: titleWidth)
                    }
                    #else
                    NativeHomeVideoCard(video: video, titleWidth: titleWidth)
                    #endif
                }
                .frame(width: size.width, height: size.height)
                // Both this source and its native hosting cell contain one card.
                .videoTransitionSource(video.bvid, in: videoTransition)
                .contentShape(.interaction, Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                WatchLaterMenuButton(aid: video.aid, bvid: video.bvid)
                Button("不感兴趣", systemImage: "eye.slash") {
                    Task {
                        guard account.isLoggedIn else { feedback.show("请先登录"); return }
                        if let message = await viewModel.markUninterested(video) { feedback.show(message) }
                    }
                }
                .disabled(viewModel.reportingIDs.contains(video.bvid))
            }
            .task(id: video.bvid) {
                // 快速滑过的卡片不预取：停留一会儿才请求播放地址，
                // 免得一次甩动排进几十个网络请求和解析。
                await VideoPreparationCache.shared.prefetchWhenSettled(bvid: video.bvid, cid: video.cid)
            }
        }
    }
}
