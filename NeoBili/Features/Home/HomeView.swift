import SwiftUI

struct HomeView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @State private var viewModel = HomeViewModel()
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    /// 刷新动画的快慢，设置页可调。
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    private var animations = VideoCardAnimationPreferences(source: .recommendation)
    @State private var refreshTask: Task<Void, Never>?
    @State private var feedController = HomeFeedScrollController()
    @State private var reselectCount = 0
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isRefreshing = false

    /// 刷新的三段式可视化：旧卡片原地淡出，新卡片按行落位。
    /// 参数集中在 FeedRefreshTuning 里。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 松手启动淡出；网络请求并行进行，新内容等淡出结束后再落位。
    /// 全程只有这一个量在变，卡片本身不位移，所以不会出现错位。
    @State private var listOpacity: Double = 1
    @State private var exitTiming: FeedRefreshExitTiming?
    /// 每次刷新加一，驱动每一行重新播落位动画。
    @State private var landingGeneration = 0

    private var animatesExit: Bool {
        !reduceMotion && animations.isEnabled(phase: .exit)
    }

    var body: some View {
        #if DEBUG
        let _ = SearchLatencyProbe.body("HomeView")
        #endif
        // 与「我的」页一致：顶部显示系统大标题，滚动后收起为居中导航标题。
        NavigationStack {
            feed
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("推荐")
                .navigationBarTitleDisplayMode(.large)
        }
            .task { await viewModel.loadInitial() }
            // 登录/退出后同一套推荐接口在服务端会切到个性化/通用推流，
            // 这里保留旧内容、后台换成新批次，跟 PiliPlus 的行为一致。
            .onChange(of: account.profile?.mid) {
                Task { await viewModel.refresh() }
            }
            .onAppear {
                // Returning to this tab always restores the app's portrait lock.
                OrientationController.enterPortrait()
            }
        .onReceive(NotificationCenter.default.publisher(for: .homeTabReselected)) { _ in
            guard !nowPlaying.isExpanded, !nowPlaying.isServiceSheetPresented else { return }
            reselectCount += 1
        }
        .resolvePortraitVideos(viewModel.videos, batchID: landingGeneration) {
            await viewModel.loadReplacementPage()
            return viewModel.videos
        }
        .videoCardAnimationSource(.recommendation)
        .onChange(of: animatesExit) { _, enabled in
            guard !enabled else { return }
            // A settings change must also restore an already fading feed while
            // its request remains in flight.
            withAnimation(nil) { listOpacity = 1; exitTiming = nil }
        }
    }

    private var feed: some View {
        ZStack {
            HomeFeedCollection(
                rows: viewModel.feedRows(hidingKnownPortraitVideos: hidesPortraitVideos),
                viewModel: viewModel,
                hidesPortraitVideos: hidesPortraitVideos,
                isRefreshing: isRefreshing,
                isInteractionEnabled: !(isRefreshing && listOpacity < 1),
                refreshDistance: refreshDistance,
                controller: feedController,
                onRefresh: { startRefresh() },
                onOpenLastSeen: { startRefresh(scrollToTop: true) }
            )
            .opacity(animatesExit ? listOpacity : 1)
            // 内容从导航栏和标签栏下面滑过；列表通过 adjustedContentInset 留出安全区。
            .ignoresSafeArea()

            // 加载、出错、全被过滤这些状态单独观察，isLoading 翻转时不重算整个列表。
            HomeFeedStatusOverlay(viewModel: viewModel, hidesPortraitVideos: hidesPortraitVideos) {
                startRefresh()
            }
        }
        .onChange(of: reselectCount) {
            guard shortcutTask == nil, !isRefreshing else { return }
            if feedController.isAwayFromTop {
                feedController.scrollToTop(animated: true)
                // 回顶动画结束前忽略重复点击，避免误触发刷新。
                shortcutTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    shortcutTask = nil
                }
            } else {
                startRefresh()
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
    }

    private func startRefresh(scrollToTop: Bool = false) {
        guard !isRefreshing else { return }
        beginRefresh()
        refreshTask = Task { @MainActor in
            defer {
                withAnimation(nil) { listOpacity = 1; exitTiming = nil; isRefreshing = false }
                refreshTask = nil
            }
            // Keep existing content until the request is ready, including when
            // animation settings change in the middle of the request.
            await viewModel.refresh(staged: true)
            guard !Task.isCancelled else { return }
            await finishRefresh(scrollToTop: scrollToTop)
            refreshTask = nil
        }
    }

    private func beginRefresh() {
        isRefreshing = true
        guard animatesExit else { listOpacity = 1; exitTiming = nil; return }
        let duration = FeedRefreshTuning.fadeExit(speed: exitSpeed)
        exitTiming = FeedRefreshExitTiming(start: ProcessInfo.processInfo.systemUptime, duration: duration)
        withAnimation(.easeOut(duration: duration)) { listOpacity = 0 }
    }

    private func finishRefresh(scrollToTop: Bool) async {
        guard viewModel.errorMessage == nil else {
            isRefreshing = false
            listOpacity = 1
            return
        }
        if animatesExit, let exitTiming {
            do {
                try await CardAnimationSettings.waitWhileEnabled(
                    for: exitTiming.remaining(at: ProcessInfo.processInfo.systemUptime), category: .video, phase: .exit, source: .recommendation
                )
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        // Commit data and restore opacity in one transaction. The individual
        // rows own their entry clocks; refreshing never waits for those clocks.
        withAnimation(nil) {
            if scrollToTop { feedController.scrollToTop(animated: false) }
            viewModel.commitStagedRefresh()
            listOpacity = 1
            landingGeneration += 1
            isRefreshing = false
        }
    }
}

/// 首次加载、加载失败、全部被过滤时盖在列表上的状态。
private struct HomeFeedStatusOverlay: View {
    let viewModel: HomeViewModel
    let hidesPortraitVideos: Bool
    let onRefresh: () -> Void

    var body: some View {
        if viewModel.videos.hasPendingVideoDimensions(hidesPortraitVideos),
           !viewModel.hasVisibleVideos(hidingKnownPortraitVideos: hidesPortraitVideos) {
            LoadingTaskAnchor()
        } else if viewModel.isLoading, viewModel.videos.isEmpty {
            LoadingTaskAnchor()
        } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
            ContentUnavailableView(
                "加载失败",
                systemImage: "wifi.slash",
                description: Text(message)
            )
        } else if !viewModel.videos.isEmpty,
                  !viewModel.hasVisibleVideos(hidingKnownPortraitVideos: hidesPortraitVideos) {
            ContentUnavailableView {
                Label("没有可显示的视频", systemImage: "rectangle.slash")
            } description: {
                Text("当前推荐中的视频都被内容过滤设置隐藏了。")
            } actions: {
                Button("刷新推荐", action: onRefresh)
            }
        }
    }
}

/// 首页双列视频卡片的尺寸参数。
enum HomeCardLayout {
    /// 页面左右留白。
    static let horizontalInset: CGFloat = 8
    /// 左右两列之间的距离。
    static let columnSpacing: CGFloat = 8
    /// 上下两行之间的距离。
    static let rowSpacing: CGFloat = 10
    /// 网格顶部和底部的留白。
    static let verticalInset: CGFloat = 10
    /// 推荐封面保持 4:3。
    static let coverAspectRatio: CGFloat = 4.0 / 3.0
    /// 封面上方两个角的圆角，和卡片本身的圆角一致。
    static let coverCornerRadius: CGFloat = 7
    /// 标题和 UP 主所在白色区域的固定高度。
    static let detailsHeight: CGFloat = 81
    /// UP 主头像的尺寸。
    static let avatarSize = CGSize(width: 16, height: 16)
    /// 文字区左右留白。
    static let detailsHorizontalPadding: CGFloat = 8

    /// 标题可用的宽度。
    static func titleWidth(for pageWidth: CGFloat) -> CGFloat {
        max(0, columnWidth(for: pageWidth) - detailsHorizontalPadding * 2)
    }

    /// 单列宽度，也是封面的宽度。
    static func columnWidth(for pageWidth: CGFloat) -> CGFloat {
        max(0, pageWidth - horizontalInset * 2 - columnSpacing) / 2
    }

    /// 封面的显示尺寸，列表预取按这个尺寸提前解码。
    static func coverSize(for pageWidth: CGFloat) -> CGSize {
        let width = columnWidth(for: pageWidth)
        return CGSize(width: width, height: width / coverAspectRatio)
    }

    /// 先根据屏幕宽度算出单列宽度，再加上 4:3 封面高度和文字区高度。
    static func cardHeight(for pageWidth: CGFloat) -> CGFloat {
        coverSize(for: pageWidth).height + detailsHeight
    }
}

/// 分隔本次刷新和上一次内容的扁平提示条，横跨两列。
struct LastSeenCard: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.subheadline.weight(.medium))

            Text("上次看到这里 · 点击刷新")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("上次看到这里，点击刷新")
    }
}

struct HomeVideoCard: View {
    let video: VideoSummary
    /// 标题可用的宽度，用来取后台预排好的标题图（见 `PreparedTitle`）。
    let titleWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoCoverThumbnail(
                url: video.secureCoverURL,
                duration: video.formattedDuration,
                playCount: video.stat.view,
                aspectRatio: HomeCardLayout.coverAspectRatio,
                cornerRadius: HomeCardLayout.coverCornerRadius,
                // 封面下缘紧贴着文字区，那两个角再圆就会割出一道缺口。
                bottomCornerRadius: 0
            )

            VStack(alignment: .leading, spacing: 7) {
                PreparedCardTitle(title: video.title, width: titleWidth)

                HStack(spacing: 4) {
                    BiliImage(url: video.secureAvatarURL, targetSize: HomeCardLayout.avatarSize)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: HomeCardLayout.avatarSize.width, height: HomeCardLayout.avatarSize.height)
                        .clipShape(Circle())

                    Text(video.owner.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, HomeCardLayout.detailsHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(height: HomeCardLayout.detailsHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 白底直接画成圆角矩形，不裁剪整张卡：裁剪会让封面、文字、头像一起走
        // 离屏渲染。封面上面两个角由封面自己的圆角负责。
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

#Preview {
    HomeView()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
