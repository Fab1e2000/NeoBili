#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// UP 主空间页。头图 + 名片在上，下面用分段控件在「投稿」和「动态」之间切换。
///
/// 排版参考 B 站客户端的空间页，但只保留看内容需要的部分：充电、大航海、
/// 特别关注这些和播放无关的入口都不做。
struct SpaceView: View {
    @Environment(\.appThemeColor) private var themeColor
    let up: FollowedUp

    @Environment(\.videoPreparation) private var preparation
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @State private var viewModel: SpaceViewModel
    @State private var tab: Tab = .videos
    @Namespace private var dynamicTransition
    @State private var detailEntry: DynamicEntry?
    @State private var headerHeight: CGFloat = 0
    /// 各分页的最新滚动位置。body 不读它，所以放进引用盒子保存：
    /// 消除此字典写入造成的状态失效；头部折叠等其它状态仍可能更新视图。
    @State private var pageOffsets = PageOffsetBox()
    @State private var headerMotion = SpaceHeaderMotion()
    @State private var pickerHeight: CGFloat = 0
    @State private var scrollingPages: Set<Tab> = []
    @State private var videoPosition = ScrollPosition(edge: .top)
    @State private var dynamicPosition = ScrollPosition(edge: .top)

    private enum Tab: String, CaseIterable, Identifiable {
        case videos = "投稿"
        case dynamics = "动态"

        var id: String { rawValue }
        var title: String { self == .videos ? String(localized: "投稿") : String(localized: "动态") }
    }

    /// 滚动位置的引用盒子，见 `pageOffsets` 的说明。
    private final class PageOffsetBox {
        var storage: [Tab: CGFloat] = [:]
    }

    init(up: FollowedUp, filtering: VideoFilterDependencies = .live,
         services: ApplicationServices = .live, likeStore: VideoLikeStore = .shared) {
        self.up = up
        _viewModel = State(initialValue: SpaceViewModel(mid: up.mid, services: services, filtering: filtering, likeStore: likeStore))
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Tab.allCases) { pageTab in
                        page(for: pageTab, viewportHeight: viewport.size.height)
                            .containerRelativeFrame(.horizontal)
                            .frame(height: viewport.size.height)
                            .id(pageTab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: Binding<Tab?>(get: { tab }, set: { if let value = $0 { tab = value } }))
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    SpaceCollapsingHeader(motion: headerMotion, height: headerHeight) {
                        header
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                headerHeight = height
                            }
                    }

                    tabPicker
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            pickerHeight = height
                        }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.card?.name ?? up.uname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        // 顶栏改成实底。半透明时内容从导航栏背后滑过去，会和吸顶的分段控件
        // 叠成两层深浅不一的模糊，看起来像没对齐。
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .secondarySystemGroupedBackground), for: .navigationBar)
        // 进了 UP 主页就把底部标签栏收起来，整屏都留给他的内容。
        .toolbarVisibility(.hidden, for: .tabBar)
        .environment(\.videoFiltering, viewModel.filtering)
        .imageViewerHost()
        .task { await viewModel.loadVideosIfNeeded() }
        .task(id: followContext) { await viewModel.loadCard(followContext) }
        .onChange(of: followContext) { _, context in viewModel.setFollowContext(context) }
        .onChange(of: tab) { _, selected in synchronizeHeader(in: selected) }
        .task(id: tab) {
            // 切到动态那一栏才去加载它，进页面时不白跑一次请求。
            if tab == .dynamics {
                await viewModel.dynamics.loadInitial()
            }
        }
        .onAppear { OrientationController.enterPortrait() }
        .fullScreenCover(item: $detailEntry) { entry in
            NavigationStack {
                    DynamicDetailView(entry: entry, feed: viewModel.dynamics)
                }
                .appTextSize()
                .actionFeedbackOverlay()
                .navigationTransition(.zoom(sourceID: "space-dynamic-\(entry.id)", in: dynamicTransition))
        }

    }

    /// 分页始终占据同一个视口；头部覆盖其上，列表预留完整头部的空间。
    /// 因此折叠只改变头部裁切，不会触发滚动容器高度与偏移的反馈循环。
    private func page(for pageTab: Tab, viewportHeight: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch pageTab {
                case .videos:
                    videoList
                        .resolvePortraitVideos(viewModel.videos, batchID: viewModel.videosGeneration) {
                            await viewModel.loadReplacementPage()
                            return viewModel.videos
                        }
                        .videoCardAnimationSource(.space)
                case .dynamics:
                    dynamicList
                        .resolvePortraitVideos(viewModel.dynamics.entries.compactMap(\.video),
                                               batchID: viewModel.dynamics.entriesGeneration, animationCategory: .dynamic) {
                            await viewModel.dynamics.loadReplacementPage()
                            return viewModel.dynamics.entries.compactMap(\.video)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            // 空列表、加载中和短列表也能完整收起头部。
            .frame(minHeight: max(viewportHeight - pickerHeight, 0), alignment: .top)
            .padding(.top, headerHeight + pickerHeight)
        }
        .scrollPosition(pageTab == .videos ? $videoPosition : $dynamicPosition)
        .scrollBounceBehavior(.always, axes: .vertical)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting || phase == .decelerating {
                scrollingPages.insert(pageTab)
            } else {
                scrollingPages.remove(pageTab)
                if pageTab == tab {
                    synchronizeHeader(in: pageTab == .videos ? .dynamics : .videos)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            pageOffsets.storage[pageTab] = max(offset, 0)
            // 只有纵向手势更新共享头部；分页切换和程序同步产生的回调不参与。
            guard pageTab == tab, scrollingPages.contains(pageTab) else { return }
            let collapse = min(max(offset, 0), headerHeight)
            guard collapse != headerMotion.collapse else { return }
            headerMotion.collapse = collapse
        }
        .onAppear {
            if pageTab != tab { synchronizeHeader(in: pageTab) }
        }
        .refreshable {
            if pageTab == .videos { await viewModel.reloadVideos() }
            else { await viewModel.dynamics.refresh() }
        }
        .leftEdgeTapDeadZone()
    }

    /// 横向手势开始前，另一页已处于相同的头部折叠位置。
    /// 头部完全收起时保留各页更深的阅读位置；展开时两页共同露出头部。
    private func synchronizeHeader(in pageTab: Tab) {
        let offset = SpaceHeaderLayout.synchronizedOffset(
            pageOffset: pageOffsets.storage[pageTab] ?? 0,
            collapse: headerMotion.collapse,
            headerHeight: headerHeight
        )
        pageOffsets.storage[pageTab] = offset
        if pageTab == .videos {
            videoPosition.scrollTo(y: offset)
        } else {
            dynamicPosition.scrollTo(y: offset)
        }
    }

    private var tabPicker: some View {
        Picker("内容", selection: $tab) {
            ForEach(Tab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, SpaceHeaderLayout.horizontalInset)
        .padding(.vertical, 8)
        // 固定在分页内容上方，横向切换时自身不参与动画。
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - 头部

    private var header: some View {
        SpaceProfileHeader(card: viewModel.card, up: up, themeColor: themeColor) { followButton }
    }

    private var followContext: SpaceViewModel.FollowContext {
        .init(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn, accountID: account.accountID)
    }

    @ViewBuilder
    private var followButton: some View {
        if !viewModel.isOwnAccount(followContext) {
            if viewModel.isFollowing == nil && account.isLoggedIn {
                if viewModel.isLoadingCard {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Button("重试") { Task { await viewModel.loadCard(followContext) } }
                            .controlSize(.small)
                            .accessibilityLabel("关注状态尚未加载，请重试")
                        if let error = viewModel.followError {
                            Text(error).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else {
                glassFollowStyle(
                    Button {
                        Task {
                            if let message = await viewModel.toggleFollow(followContext) {
                                feedback.show(message)
                            }
                        }
                    } label: {
                        Text(viewModel.isFollowing == true ? String(localized: "已关注") : String(localized: "follow.action", defaultValue: "关注"))
                            .font(.footnote.weight(.medium))
                            .frame(minWidth: 56)
                    },
                    isActive: viewModel.isFollowing == true
                )
                .controlSize(.small)
                .disabled(viewModel.isTogglingFollow)
            }
        }
    }

    /// 关注按钮用系统液态玻璃样式：未关注是实底玻璃（吸引点击），已关注退成
    /// 清透玻璃配灰字（不再抢注意力）。两种样式类型不同，没法用三目表达式
    /// 带过，和视频操作栏的按钮走同一个分支写法。
    @ViewBuilder
    private func glassFollowStyle(_ button: some View, isActive: Bool) -> some View {
        if isActive {
            button.buttonStyle(.glass).foregroundStyle(.secondary)
        } else {
            button.buttonStyle(.glassProminent).tint(themeColor)
        }
    }

    // MARK: - 投稿

    @ViewBuilder
    private var videoList: some View {
        let visibleVideos = viewModel.videos.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: viewModel.filtering)

        if let message = viewModel.videosError, !viewModel.videos.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("加载失败", systemImage: "wifi.slash")
                    Text(message).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("重试") { Task { await viewModel.reloadVideos() } }
                    .disabled(viewModel.isLoadingVideos)
            }
            .font(.footnote)
            .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
            .padding(.vertical, 12)
        }

        if visibleVideos.isEmpty, viewModel.videos.hasPendingVideoDimensions(hidesPortraitVideos, filtering: viewModel.filtering) {
            LoadingTaskAnchor().padding(.vertical, 40)
        } else if viewModel.isLoadingVideos, viewModel.videos.isEmpty {
            LoadingTaskAnchor().padding(.vertical, 40)
        } else if let message = viewModel.videosError, viewModel.videos.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await viewModel.reloadVideos() } }
            }
            .padding(.vertical, 20)
        } else if visibleVideos.isEmpty {
            ContentUnavailableView(
                viewModel.videos.isEmpty ? "没有投稿" : "没有可显示的视频",
                systemImage: "video.slash",
                description: Text(
                    viewModel.videos.isEmpty
                        ? "这位 UP 主还没有公开的视频稿件。"
                        : "当前加载的投稿都被内容过滤设置隐藏了。"
                )
            )
                .padding(.vertical, 20)
        } else {
            ForEach(visibleVideos) { video in
                Button {
                    nowPlaying.open(
                        VideoDetailRoute(
                            bvid: video.bvid,
                            cover: video.pic,
                            title: video.title,
                            artist: video.author, playbackEntry: .spaceVideo
                        ),
                        from: video.bvid
                    )
                } label: {
                    VideoListCard(
                        coverURL: URL.biliSecure(video.pic),
                        title: video.title,
                        // 整页都是同一个 UP 的稿件，作者名那一行改放发布时间更有用。
                        author: video.created > 0 ? video.created.biliRelativeTimeText : video.author,
                        playCount: video.play,
                        durationText: video.length
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
                }
                .videoEntranceIdentity(video.bvid)
                .videoTransitionSource(video.bvid, in: videoTransition)
                .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                .task {
                    await viewModel.loadMoreVideosIfNeeded(
                        current: video,
                        hidingKnownPortraitVideos: hidesPortraitVideos
                    )
                }
                // 空间投稿列表里没有 cid，预取要先取一次详情再取播放地址。
                .task { await preparation.prefetchWhenSettled(bvid: video.bvid) }
            }

            if viewModel.isLoadingMoreVideos {
                LoadingTaskAnchor().padding()
            }
        }
    }

    // MARK: - 动态

    @ViewBuilder
    private var dynamicList: some View {
        let feed = viewModel.dynamics

        if feed.isLoading, feed.entries.isEmpty {
            LoadingTaskAnchor().padding(.vertical, 40)
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await feed.refresh() } }
            }
            .padding(.vertical, 20)
        } else if feed.entries.isEmpty {
            ContentUnavailableView("还没有动态", systemImage: "bell.slash", description: Text("这位 UP 主还没有发过动态。"))
                .padding(.vertical, 20)
        } else {
            let visibleEntries = feed.entries.filter { $0.video?.canDisplayVideo(hidingPortrait: hidesPortraitVideos, filtering: viewModel.filtering) ?? true }
            if visibleEntries.isEmpty {
                if feed.entries.compactMap(\.video).hasPendingVideoDimensions(hidesPortraitVideos, filtering: viewModel.filtering) {
                    LoadingTaskAnchor().padding()
                } else {
                    Button("继续加载动态") { Task { await feed.loadReplacementPage() } }
                        .padding()
                }
            }
            ForEach(visibleEntries) { entry in
                DynamicFeedCard(
                    entry: entry,
                    feed: feed,
                    lastVisibleID: visibleEntries.last?.id,
                    onOpenVideo: { open(entry) },
                    // 已经在这个 UP 的空间里了，头像不再是入口。
                    onOpenAuthor: nil,
                    onLike: { like(entry) },
                    onOpenDetail: { detailEntry = entry }
                )
                .videoEntranceIdentity(entry.video?.bvid)
                .videoTransitionSource("space-dynamic-\(entry.id)", in: dynamicTransition)
                .contextMenu {
                    if let video = entry.video,
                       video.canDisplayVideo(hidingPortrait: hidesPortraitVideos, filtering: viewModel.filtering) {
                        WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
                    }
                }
                .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
            }

            if feed.isLoadingMore {
                LoadingTaskAnchor().padding()
            }
        }
    }

    private func open(_ entry: DynamicEntry) {
        guard let video = entry.video else { return }
        nowPlaying.open(
            VideoDetailRoute(
                bvid: video.bvid,
                cover: video.cover,
                title: video.title,
                artist: video.authorName, playbackEntry: .spaceDynamic
            ),
            from: video.bvid
        )
    }

    private func like(_ entry: DynamicEntry) {
        Task {
            if let message = await viewModel.dynamics.toggleLike(entry, isLoggedIn: account.isLoggedIn) {
                feedback.show(message)
            }
        }
    }
}

/// Only the clipping view observes this per-frame value. The page lists do not.
@MainActor @Observable
private final class SpaceHeaderMotion {
    var collapse: CGFloat = 0
}

private struct SpaceCollapsingHeader<Content: View>: View {
    let motion: SpaceHeaderMotion
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(height: height > 0 ? max(height - motion.collapse, 0) : nil, alignment: .bottom)
            .clipped()
    }
}

/// UP 主页头部的尺寸。
enum SpaceHeaderLayout {
    static func synchronizedOffset(pageOffset: CGFloat, collapse: CGFloat, headerHeight: CGFloat) -> CGFloat {
        let collapse = min(max(collapse, 0), max(headerHeight, 0))
        return collapse < headerHeight ? collapse : max(pageOffset, collapse)
    }

    /// 头部内容与屏幕左右边缘的距离。
    static let horizontalInset: CGFloat = 16
    /// 头像直径。
    static let avatarSize: CGFloat = 72
    /// 头图的宽高比。B 站的空间头图本身就是这个比例。
    static let bannerAspectRatio: CGFloat = 3.0
}

#Preview {
    NavigationStack {
        SpaceView(up: FollowedUp(mid: 946974, uname: "影视飓风", face: "", hasUpdate: true))
            .environment(NowPlayingStore())
            .environment(AccountStore())
            .environment(ActionFeedback())
    }
}
