import NeoBiliDomain
import SwiftUI

/// UP 主空间页。头图 + 名片在上，下面用分段控件在「投稿」「合集」「动态」之间切换。
///
/// 排版参考 B 站客户端的空间页，但只保留看内容需要的部分：充电、大航海、
/// 特别关注这些和播放无关的入口都不做。
struct SpaceView: View {
    let up: FollowedUp
    @Environment(\.applicationServices) private var services
    @Environment(\.applicationStores) private var stores
    @Environment(\.videoFiltering) private var filtering

    var body: some View {
        SpacePage(up: up, services: services, filtering: filtering, likeStore: stores.likes)
    }
}

private struct SpacePage: View {
    @Environment(\.appThemeColor) private var themeColor
    let up: FollowedUp
    private let services: ApplicationServices

    @Environment(\.videoPreparation) private var preparation
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var videoAnimations = VideoCardAnimationPreferences(source: .space)
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicExitKey) private var dynamicExitEnabled = CardAnimationSettings.defaultValue
    /// 每个分页单独管理刷新。
    @State private var videoRefresh = ListRefreshController()
    @State private var collectionRefresh = ListRefreshController()
    @State private var dynamicRefresh = ListRefreshController()
    @State private var viewModel: SpaceViewModel
    @State private var tab: Tab = .videos
    @State private var hasVisitedCollections = false
    private let dynamicTransitionPrefix = "space-dynamic-"
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
    @State private var collectionPosition = ScrollPosition(edge: .top)
    @State private var dynamicPosition = ScrollPosition(edge: .top)

    private enum Tab: String, CaseIterable, Identifiable {
        case videos, collections, dynamics

        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .videos: "投稿"
            case .collections: "合集"
            case .dynamics: "动态"
            }
        }
    }

    /// 滚动位置的引用盒子，见 `pageOffsets` 的说明。
    private final class PageOffsetBox {
        var storage: [Tab: CGFloat] = [:]
    }

    init(up: FollowedUp, services: ApplicationServices, filtering: VideoFilterDependencies, likeStore: VideoLikeStore) {
        self.up = up
        self.services = services
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
            .scrollIndicators(.hidden, axes: .horizontal)
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
        .onChange(of: tab) { _, selected in
            synchronizeHeader(in: selected)
            if selected == .collections { hasVisitedCollections = true }
        }
        .task(id: hasVisitedCollections) {
            if hasVisitedCollections { await viewModel.collections.loadIfNeeded() }
        }
        .task(id: tab) {
            // 切到动态那一栏才去加载它，进页面时不白跑一次请求。
            if tab == .dynamics {
                await viewModel.dynamics.loadInitial()
            }
        }
        .onAppear { OrientationController.enterPortrait() }
        .onDisappear {
            videoRefresh.reset(discard: viewModel.discardVideosRefresh)
            collectionRefresh.reset(discard: viewModel.collections.discardRefresh)
            dynamicRefresh.reset(discard: viewModel.dynamics.discardStagedRefresh)
        }
        .fullScreenCover(item: $detailEntry) { entry in
            NavigationStack {
                    DynamicDetailView(entry: entry, feed: viewModel.dynamics, services: services)
                }
                .appTextSize()
                .actionFeedbackOverlay()
                .navigationTransition(.zoom(sourceID: dynamicTransitionPrefix + entry.id, in: dynamicTransition))
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
                case .collections:
                    collectionList
                case .dynamics:
                    dynamicList
                        .resolvePortraitVideos(viewModel.dynamics.entries.compactMap(\.video),
                                               batchID: viewModel.dynamics.entriesGeneration, providesEntrance: false) {
                            await viewModel.dynamics.loadReplacementPage()
                            return viewModel.dynamics.entries.compactMap(\.video)
                        }
                }
            }
            // 与推荐页一致：松手后旧内容淡出，新内容到了再换入。
            .opacity(animatesExit(in: pageTab) ? refreshController(for: pageTab).contentOpacity : 1)
            .allowsHitTesting(refreshController(for: pageTab).contentOpacity == 1)
            .frame(maxWidth: .infinity)
            .background {
                ListPullRefresh(enabled: !refreshController(for: pageTab).isRefreshing && canRefresh(pageTab),
                                onRefresh: { startRefresh(pageTab) })
            }
            // 空列表、加载中和短列表也能完整收起头部。
            .frame(minHeight: max(viewportHeight - pickerHeight, 0), alignment: .top)
            .padding(.top, headerHeight + pickerHeight)
        }
        .modifier(SpaceScrollIndicators(motion: headerMotion, headerHeight: headerHeight, pickerHeight: pickerHeight))
        .scrollPosition(position(for: pageTab))
        .scrollBounceBehavior(.always, axes: .vertical)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting || phase == .decelerating {
                scrollingPages.insert(pageTab)
            } else {
                scrollingPages.remove(pageTab)
                if pageTab == tab {
                    for other in Tab.allCases where other != pageTab {
                        synchronizeHeader(in: other)
                    }
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
            synchronizeHeader(in: pageTab)
        }
        .leftEdgeTapDeadZone()
    }

    private func refreshController(for pageTab: Tab) -> ListRefreshController {
        switch pageTab {
        case .videos: videoRefresh
        case .collections: collectionRefresh
        case .dynamics: dynamicRefresh
        }
    }

    private func animatesExit(in pageTab: Tab) -> Bool {
        guard !reduceMotion else { return false }
        switch pageTab {
        case .videos: return videoAnimations.isEnabled(phase: .exit)
        case .collections: return false
        case .dynamics: return cardAnimationsEnabled && dynamicExitEnabled
        }
    }

    private func canRefresh(_ pageTab: Tab) -> Bool {
        switch pageTab {
        case .videos: !viewModel.isLoadingVideos
        case .collections: !viewModel.collections.list.isLoading
        case .dynamics: !viewModel.dynamics.isLoading
        }
    }

    /// 手动下拉刷新：旧内容淡出的同时重新取第一页，两者都结束后一次换入。
    private func startRefresh(_ pageTab: Tab) {
        guard canRefresh(pageTab), !refreshController(for: pageTab).isRefreshing else { return }
        switch pageTab {
        case .videos:
            videoRefresh.start(hasContent: !viewModel.videos.isEmpty, animatesExit: animatesExit(in: .videos), source: .space,
                               fetch: { await viewModel.stageVideosRefresh() },
                               commit: viewModel.commitVideosRefresh,
                               discard: viewModel.discardVideosRefresh)
        case .collections:
            let model = viewModel.collections
            collectionRefresh.start(hasContent: !model.collections.isEmpty, animatesExit: false, source: .space,
                                    fetch: model.stageRefresh, commit: model.commitRefresh,
                                    discard: model.discardRefresh)
        case .dynamics:
            let stagingID = UUID()
            dynamicRefresh.start(hasContent: !viewModel.dynamics.entries.isEmpty, animatesExit: animatesExit(in: .dynamics),
                                 source: .space, category: .dynamic,
                                 fetch: {
                                     await viewModel.dynamics.refresh(staged: true, stagingID: stagingID)
                                     return viewModel.dynamics.hasStagedRefresh(id: stagingID)
                                 },
                                 commit: { viewModel.dynamics.commitStagedRefresh(id: stagingID) },
                                 discard: viewModel.dynamics.discardStagedRefresh)
        }
    }

    /// 横向手势开始前，其他页已处于相同的头部折叠位置。
    /// 头部完全收起时保留各页更深的阅读位置。
    private func synchronizeHeader(in pageTab: Tab) {
        let offset = SpaceHeaderLayout.synchronizedOffset(
            pageOffset: pageOffsets.storage[pageTab] ?? 0,
            collapse: headerMotion.collapse,
            headerHeight: headerHeight
        )
        pageOffsets.storage[pageTab] = offset
        let position = position(for: pageTab)
        position.wrappedValue.scrollTo(y: offset)
    }

    private func position(for pageTab: Tab) -> Binding<ScrollPosition> {
        switch pageTab {
        case .videos: $videoPosition
        case .collections: $collectionPosition
        case .dynamics: $dynamicPosition
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
                            Text(error).font(.app(.caption2)).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } else {
                FollowCapsuleButton(
                    title: viewModel.isFollowing == true ? String(localized: "已关注") : String(localized: "follow.action", defaultValue: "关注"),
                    isActive: viewModel.isFollowing == true, compact: true
                ) {
                    Task {
                        if let message = await viewModel.toggleFollow(followContext) {
                            feedback.show(message)
                        }
                    }
                }
                .controlSize(.small)
                .disabled(viewModel.isTogglingFollow)
            }
        }
    }

    // MARK: - 投稿

    @ViewBuilder
    private var videoList: some View {
        let visibleVideos = viewModel.videos.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: viewModel.filtering)

        if let message = viewModel.videosError, !viewModel.videos.isEmpty {
            InlineLoadFailure(title: "投稿加载失败", message: message,
                              isRetryDisabled: viewModel.isLoadingVideos) {
                Task { await viewModel.reloadVideos() }
            }
        }

        if visibleVideos.isEmpty, viewModel.videos.hasPendingVideoDimensions(hidesPortraitVideos, filtering: viewModel.filtering) {
            LoadingTaskAnchor().padding(.vertical, 40)
        } else if viewModel.isLoadingVideos, viewModel.videos.isEmpty {
            LoadingTaskAnchor().padding(.vertical, 40)
        } else if let message = viewModel.videosError, viewModel.videos.isEmpty {
            ContentUnavailableView {
                Label("投稿加载失败", systemImage: "video.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await viewModel.reloadVideos() } }
            }
            .padding(.vertical, 20)
        } else if visibleVideos.isEmpty {
            ContentUnavailableView(
                viewModel.videos.isEmpty ? "没有投稿" : "没有可显示的视频",
                systemImage: "video.slash"
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
                .buttonStyle(CardPressStyle(cornerRadius: VideoListCardLayout.cardCornerRadius))
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

    // MARK: - 合集和系列

    @ViewBuilder
    private var collectionList: some View {
        let model = viewModel.collections
        let list = model.list

        if let message = list.errorMessage {
            InlineLoadFailure(title: "合集和系列加载失败", message: message, isRetryDisabled: list.isLoading) {
                Task { await model.reload() }
            }
        } else if model.collections.isEmpty {
            if list.hasLoadedCurrentOrder && !list.isLoading {
                ContentUnavailableView("没有合集和系列", systemImage: "rectangle.stack")
                    .padding(.vertical, 20)
            } else {
                LoadingTaskAnchor().padding(.vertical, 40)
            }
        }

        ForEach(model.collections) { collection in
            NavigationLink {
                SpaceCollectionDetailView(collection: collection, hostMID: up.mid,
                                          authorName: viewModel.card?.name ?? up.uname,
                                          services: services, filtering: viewModel.filtering)
            } label: {
                let description = collection.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let badge = collection.kind == .season
                    ? String(localized: "合集 · \(collection.total) 集")
                    : String(localized: "系列 · \(collection.total) 集")
                VideoListCard(
                    coverURL: URL.biliSecure(collection.cover),
                    title: collection.name,
                    author: description.isEmpty
                        ? (collection.updatedAt > 0 ? collection.updatedAt.biliRelativeTimeText : "")
                        : description,
                    playCount: -1,
                    durationText: badge,
                    animatesEntrance: false,
                    showsDurationOnCover: true
                )
            }
            .buttonStyle(CardPressStyle(cornerRadius: VideoListCardLayout.cardCornerRadius))
            .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
            .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
            .task(id: list.generation) { await model.loadMoreIfNeeded(current: collection) }
        }

        if list.isLoadingMore {
            LoadingTaskAnchor().padding()
        } else if let message = list.paginationError {
            InlineLoadFailure(title: "更多合集和系列加载失败", message: message, isRetryDisabled: list.isLoading) {
                Task { await model.loadMore() }
            }
        } else if model.collections.isEmpty && list.canLoadMore {
            Button("加载更多") { Task { await model.loadMore() } }
                .padding()
        }
    }

    // MARK: - 动态

    private var dynamicList: some View {
        let feed = viewModel.dynamics
        return FollowingFeedContent(feed: feed, showsAuthor: true,
            hidesPortraitVideos: hidesPortraitVideos, filtering: viewModel.filtering,
            dynamicTransition: dynamicTransition, transitionPrefix: dynamicTransitionPrefix, emptyTitle: "还没有动态",
            placeholderLayout: .padded,
            onRetry: { Task { await feed.refresh() } },
            onLoadReplacement: { Task { await feed.loadReplacementPage() } },
            onOpenVideo: open, onOpenAuthor: nil, onLike: like, onOpenDetail: { detailEntry = $0 })
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

/// Only header clipping and indicator margins observe this per-frame value.
@MainActor @Observable
private final class SpaceHeaderMotion {
    var collapse: CGFloat = 0
}

private struct SpaceScrollIndicators: ViewModifier {
    let motion: SpaceHeaderMotion
    let headerHeight: CGFloat
    let pickerHeight: CGFloat

    func body(content: Content) -> some View {
        content.contentMargins(.top, max(0, headerHeight - motion.collapse) + pickerHeight, for: .scrollIndicators)
    }
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

enum SpaceHeaderLayout {
    static func synchronizedOffset(pageOffset: CGFloat, collapse: CGFloat, headerHeight: CGFloat) -> CGFloat {
        let collapse = min(max(collapse, 0), max(headerHeight, 0))
        return collapse < headerHeight ? collapse : max(pageOffset, collapse)
    }

    static let horizontalInset: CGFloat = 16
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
