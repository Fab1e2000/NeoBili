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

/// 全屏的视频页。
///
/// 它本身不持有播放器；视频、详情、评论和滚动状态由 `NowPlayingStore` 管理。
/// 页面退出时根据小窗设置继续播放，播放器不会随页面销毁。
struct VideoPage: View {
    @Environment(NowPlayingStore.self) private var store
    /// 点赞、投币这些操作都要求登录，按钮点下去时据此决定是执行还是提示登录。
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.scenePhase) private var scenePhase

    /// 横屏全屏仍以实际方向为准；竖屏全屏不旋转，单独记录它的显示意图。
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isPortraitFullScreen = false
    @State private var controlsSafeArea = EdgeInsets()
    @State private var playerControlsVisible = false

    /// 收起状态下标题最多显示几行。展开后标题不再截断，简介正文也跟着铺开。

    private var viewModel: VideoDetailViewModel? { store.detailViewModel }

    private var isFullScreen: Bool { isPortraitFullScreen || verticalSizeClass == .compact }
    private var isPortraitVideo: Bool { VideoFullscreenOrientation.preferred(for: inlineAspectRatio) == .portrait }
    /// 首帧前以及重取播放地址期间属于加载，不能套用暂停后的隐藏／染色行为。
    private var collapsePhase: InlineVideoPlaybackPhase {
        store.dismissalPlaybackPhase ?? InlineVideoPlaybackPhase(
            isPlaying: store.player?.isPlaying == true,
            hasRenderedFirstFrame: store.player?.hasRenderedFirstFrame == true,
            isLoading: store.player?.isLoading ?? true
        )
    }

    /// 全屏按钮切换后，方向请求和旋转动画本身要花几百毫秒才能完成，这期间
    /// 按钮还停在原处。如果这时候又收到一次点击（不管是手误，还是屏幕边缘
    /// 的系统手势识别把同一次触摸判成了两次），会在动画走到一半时把方向
    /// 请求整个反过来——表现就是刚进全屏又立刻退出，画面停在切换中间的
    /// 尺寸上。这个时间窗内忽略掉多余的点击。
    @State private var lastFullScreenToggle = Date.distantPast
    private static let fullScreenToggleCooldown: TimeInterval = 0.6

    /// 简介区左右留白。tag 那一行要用同样的值才能和正文对齐。
    private static let contentInset: CGFloat = 16

    @State private var collapseLayout = InlineVideoCollapseLayout(expandedHeight: 0, standardHeight: 0, allowsCompact: false)
    /// 同一段滚动距离先缩小竖屏画面，暂停后才继续将画面收进 56pt 标题栏。
    @State private var videoCollapseDistance: CGFloat = 0
    @State private var isShowingSeason = false
    @State private var isShowingParts = false
    @State private var isShowingFavoriteFolders = false
    /// 头像点开的 UP 主空间页。视频页本身是 fullScreenCover，不在任何
    /// 导航栈里，所以自己带一个栈来推空间页。
    @State private var spacePath = NavigationPath()

    var body: some View {
        NavigationStack(path: $spacePath) {
            videoPageRoot
                // 视频页自己不显示导航栏；推入 UP 主空间页后由那一页显示。
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: FollowedUp.self) { up in
                    SpaceView(up: up)
                }
                .navigationDestination(for: VideoTagSearchRoute.self) { route in
                    VideoTagSearchPage(keyword: route.keyword)
                }
        }
        .onDisappear {
            // 播放画面由 cover 的 onDismiss 在原生缩小动画完成后交给小窗。
            OrientationController.enterPortrait()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.player?.savePlaybackProgress() }
        }
    }

    /// 视频页的完整内容：播放区、选项栏、简介与评论。
    private var videoPageRoot: some View {
        @Bindable var store = store

        return GeometryReader { geometry in
            // 相比原始位置上移最多 9pt，仅压缩较高的顶部安全区。
            let topOverlap: CGFloat = isFullScreen ? 0 : min(9, max(0, geometry.safeAreaInsets.top - 47))
            // 把安全区还原为整屏尺寸，竖屏高度上限不会在进出全屏时因安全区变化而跳动。
            let layoutSize = CGSize(
                width: geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing,
                height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            )
            let fullHeight = Self.inlineVideoHeight(
                for: layoutSize,
                aspectRatio: inlineAspectRatio,
                hidesPortraitVideos: hidesPortraitVideos
            )
            let layout = InlineVideoCollapseLayout(
                expandedHeight: fullHeight,
                standardHeight: Self.inlineVideoHeight(for: layoutSize),
                allowsCompact: isPortraitVideo
            )
            // 在渲染这一帧就重算画幅并限位，避免异步元数据／首帧与 onChange 不同拍时跳高或闪出隐藏画面。
            let inlineDistance = layout == collapseLayout
                ? layout.constrainedDistance(videoCollapseDistance, for: collapsePhase)
                : layout.rebasedDistance(videoCollapseDistance, from: collapseLayout, for: collapsePhase)
            let distance = isFullScreen ? 0 : inlineDistance
            let hidesVideo = !isFullScreen && layout.hidesVideo(for: distance)
            let videoHeight = isFullScreen ? geometry.size.height : layout.containerHeight(for: distance)
            let collapseProgress = isFullScreen ? 0 : layout.visualProgress(for: distance, phase: collapsePhase)
            VStack(spacing: 0) {
                ZStack {
                    videoArea
                        .frame(width: geometry.size.width,
                               height: videoHeight)
                        .allowsHitTesting(!hidesVideo)
                        .accessibilityHidden(hidesVideo)

                }
                .frame(width: geometry.size.width,
                       height: videoHeight)
                .clipped()
                .contentShape(Rectangle())
                .background {
                    PlayerReturnGestureGuard(enabled: spacePath.isEmpty)
                        .allowsHitTesting(false)
                }

                if !isFullScreen {
                    Color.clear.frame(height: 10)
                }

                if !isFullScreen {
                    // 选择器固定在播放器下方，简介和评论在其下方切页。
                    VStack(spacing: 0) {
                        VideoSectionBar(
                            selection: $store.section,
                            commentCount: viewModel?.detail?.stat.reply ?? 0
                        )

                        sectionPages
                            .environment(\.commentBottomInset, geometry.safeAreaInsets.bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                    .background {
                        // 延续内容底色，圆角外侧由下方的同步染色背景填充。
                        UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                            .fill(Color(uiColor: .systemBackground))
                    }
                    .background(alignment: .top) {
                        Color.accentColor.opacity(collapseProgress)
                            .frame(height: 12)
                            .allowsHitTesting(false)
                    }
                    .background {
                        PlayerReturnGestureGuard(enabled: spacePath.isEmpty,
                                                 verticalOnly: true)
                            .allowsHitTesting(false)
                    }
                    // 简介和相关视频、评论区与视频画面盖同一条左缘死区，
                    // 防止边缘误触点开相关视频。
                    .leftEdgeTapDeadZone()
                }
            }
            // 内容真正延伸到下边缘；输入栏用实测安全区抬高，不留整条不透明底栏。
            .frame(width: geometry.size.width,
                   height: geometry.size.height + topOverlap + (isFullScreen ? 0 : geometry.safeAreaInsets.bottom),
                   alignment: .top)
            .overlay(alignment: .top) {
                if !isFullScreen {
                    InlineVideoCollapseOverlay(progress: collapseProgress, videoHeight: videoHeight,
                                               topInset: geometry.safeAreaInsets.top, isCollapsed: hidesVideo) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            videoCollapseDistance = 0
                            store.player?.play()
                        }
                    }
                }
            }
            .offset(y: -topOverlap)
            .onChange(of: layout, initial: true) { _, layout in
                videoCollapseDistance = layout.rebasedDistance(videoCollapseDistance, from: collapseLayout, for: collapsePhase)
                collapseLayout = layout
            }
        }
        // 顶部导航栏隐藏后，状态栏安全区会露出最外层背景。设为黑色后，它会和视频画面连成一体。
        .background(Color.black.ignoresSafeArea(edges: .top))
        // 竖屏保留底部安全区，评论输入栏位于 Home 指示条和屏幕圆角上方。
        .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
        .statusBarHidden(isFullScreen)
        .background {
            PlayerSafeAreaReader { controlsSafeArea = $0 }
                .allowsHitTesting(false)
        }
        .onChange(of: store.route?.id) {
            videoCollapseDistance = 0
            playerControlsVisible = false
            spacePath = NavigationPath()
        }
        .onChange(of: store.activeCid) { old, _ in
            if old != nil { videoCollapseDistance = 0; playerControlsVisible = false }
        }
        .onChange(of: collapsePhase) { _, phase in
            if phase == .loading {
                // 换源／重试时立即恢复完整画面，不能残留暂停时的粉色栏。
                clampVideoCollapse()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { clampVideoCollapse() }
            }
        }
        .onChange(of: inlineAspectRatio) { updateFullScreenOrientation() }
        .onChange(of: verticalSizeClass) { _, sizeClass in
            if sizeClass == .compact, !isPortraitVideo { isPortraitFullScreen = false }
        }
        // 评论里的配图点开看大图。视频页本身就是 fullScreenCover，
        // 查看器挂在它内部而不是根视图上。
        .imageViewerHost()
        .sheet(isPresented: $isShowingSeason) {
            if let season = viewModel?.detail?.ugcSeason {
                UgcSeasonSheet(
                    season: season,
                    currentBvid: store.route?.bvid,
                    onSelect: store.openEpisode
                )
                .appTextSize()
            }
        }
        .sheet(isPresented: $isShowingParts) {
            if let detail = viewModel?.detail, detail.pages.count > 1 {
                VideoPartsSheet(
                    parts: detail.pages,
                    currentCid: store.activeCid ?? detail.cid,
                    onSelect: { part in store.selectPart(cid: part.cid) }
                )
                .appTextSize()
            }
        }
        .sheet(isPresented: $isShowingFavoriteFolders) {
            if let mid = account.profile?.mid, let aid = viewModel?.detail?.aid {
                FavoriteFolderSheet(ownerMid: mid, videoAid: aid) { add, remove in
                    Task {
                        await viewModel?.updateFavorites(
                            add: add,
                            remove: remove,
                            isLoggedIn: account.isLoggedIn
                        )
                    }
                }
                .appTextSize()
            }
        }
        // 操作结果统一交给那个非模态浮层。用 alert 的话，视频页本身是
        // fullScreenCover，弹窗会和它抢 present，页面会被弹走。
        .onChange(of: viewModel?.actionMessage) { _, message in
            guard let message else { return }
            feedback.show(message)
            viewModel?.actionMessage = nil
        }
        // 视频页盖在根视图上面，根视图那层浮层在它下面看不见，得自己再挂一层。
        .actionFeedbackOverlay()
    }

    @ViewBuilder
    private var videoArea: some View {
        if let player = store.player {
            InlineVideoPlayer(
                viewModel: player,
                controlsVisible: $playerControlsVisible,
                coverURL: store.route?.secureCoverURL,
                isFullScreen: isFullScreen,
                onToggleFullScreen: toggleFullScreen,
                onToggleCompact: compactVideoAction,
                isCompact: videoCollapseDistance > 0,
                controlsSafeAreaInsets: isFullScreen ? controlsSafeArea : EdgeInsets(),
                onDismiss: store.goBack,
                videoTitle: viewModel?.detail?.title ?? store.route?.title ?? "",
                videoSubtitle: viewModel?.detail?.owner.name ?? store.route?.artist ?? "",
                shareURL: store.route.flatMap { URL(string: "https://www.bilibili.com/video/\($0.bvid)") }
            )
        } else {
            // 播放器可能先于详情建好，所以只要还没出错就一直显示等待状态。
            // 先铺上列表里那张封面，比一整块黑屏更接近最终画面。
            ZStack {
                Color.black

                if let coverURL = store.route?.secureCoverURL {
                    BiliImage(url: coverURL)
                        .aspectRatio(contentMode: .fit)
                }

                if let message = viewModel?.errorMessage {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
                if viewModel?.errorMessage == nil {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { playerControlsVisible.toggle() }
                    if !playerControlsVisible {
                        ProgressView().tint(.white).allowsHitTesting(false)
                    }
                }
            }
            .overlay {
                if playerControlsVisible || viewModel?.errorMessage != nil {
                    PlayerGlassChrome(
                        title: viewModel?.detail?.title ?? store.route?.title ?? "",
                        subtitle: viewModel?.detail?.owner.name ?? store.route?.artist ?? "",
                        videoQualityControl: PlayerQualityControl(title: "分辨率", accessibilityLabel: "分辨率", options: [],
                                                                 selectedID: 0, isEnabled: false, onSelect: { _ in }),
                        audioQualityControl: PlayerQualityControl(title: "音质", accessibilityLabel: "音质", options: [],
                                                                 selectedID: 0, isEnabled: false, onSelect: { _ in }),
                        canControlPlayback: false,
                        isWaiting: viewModel?.errorMessage == nil,
                        isFullScreen: isFullScreen, isCompact: videoCollapseDistance > 0,
                        hasError: viewModel?.errorMessage != nil,
                        safeAreaInsets: isFullScreen ? controlsSafeArea : EdgeInsets(),
                        onBack: { if isFullScreen { toggleFullScreen() } else { store.goBack() } },
                        onToggleFullScreen: toggleFullScreen, onToggleCompact: compactVideoAction
                    ) {
                        if let bvid = store.route?.bvid { WatchLaterMenuButton(bvid: bvid) }
                    }
                }
            }
        }
    }

    private func canConsumeVideoScroll(_ distance: CGFloat) -> Bool {
        guard canInteractWithVideoCollapse else { return false }
        return distance < 0 ? videoCollapseDistance > 0
            : videoCollapseDistance < collapseLayout.maximumDistance(for: collapsePhase)
    }

    private func canContinueCollapseMomentum() -> Bool {
        guard canInteractWithVideoCollapse else { return false }
        return collapseLayout.maximumDistance(for: collapsePhase) > 0 && videoCollapseDistance > 0
    }

    private var canInteractWithVideoCollapse: Bool {
        store.isExpanded && !store.isVideoPageInteractionInProgress
            && spacePath.isEmpty && !isFullScreen && store.route != nil
            && store.player?.errorMessage == nil && viewModel?.errorMessage == nil
    }

    private func consumeVideoScroll(_ distance: CGFloat) -> CGFloat {
        guard canConsumeVideoScroll(distance) else { return 0 }
        let old = videoCollapseDistance
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            videoCollapseDistance = collapseLayout.constrainedDistance(old + distance, for: collapsePhase)
        }
        return videoCollapseDistance - old
    }

    private func clampVideoCollapse() {
        videoCollapseDistance = collapseLayout.constrainedDistance(videoCollapseDistance, for: collapsePhase)
    }

    private func toggleCompactVideo() {
        guard canInteractWithVideoCollapse else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            videoCollapseDistance = videoCollapseDistance > 0 ? 0 : collapseLayout.compactTravel
        }
    }

    private var compactVideoAction: (() -> Void)? {
        guard canInteractWithVideoCollapse, isPortraitVideo, collapseLayout.compactTravel > 0 else { return nil }
        return { toggleCompactVideo() }
    }

    private func finishVideoCollapse() {
        // 松手后的距离由滚动桥接器按列表减速率继续消费，不做端点吸附。
    }

    /// 简介和评论并排放在一个横向分页容器里。
    ///
    /// 这里特意不用 `.page` 样式的 TabView：`indexDisplayMode` 设成 `.never`
    /// 只是隐藏圆点，系统仍然在底部保留着它们原来占的那份空间，视频页最下面
    /// 因此始终留着一条空白。改成手动分页的 ScrollView 就没有这份保留区域。
    /// 上面那条选项栏和它共用同一个选中状态，所以滑动内容时指示条跟着滑，
    /// 点选项栏时内容也滑过去；`.scrollTargetBehavior(.paging)` 负责手指按住
    /// 时内容跟走、松手回弹或翻页、边界阻尼这些原来 `.page` 样式自带的手感。
    private var sectionPages: some View {
        @Bindable var store = store

        let position = Binding<VideoPageSection?>(
            get: { store.section },
            set: { if let newValue = $0 { store.section = newValue } }
        )

        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                descriptionSection
                    .frame(maxHeight: .infinity)
                    .containerRelativeFrame(.horizontal)
                    .id(VideoPageSection.description)

                commentsSection
                    .frame(maxHeight: .infinity)
                    .containerRelativeFrame(.horizontal)
                    .id(VideoPageSection.comments)
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: position)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var commentsSection: some View {
        @Bindable var store = store

        if let commentsViewModel = store.commentsViewModel {
            CommentsView(viewModel: commentsViewModel, scrollPosition: $store.commentsScroll,
                         collapseConsume: consumeVideoScroll, collapseEnd: finishVideoCollapse,
                         canCollapse: canConsumeVideoScroll, collapseCanContinue: canContinueCollapseMomentum)
        } else {
            GeometryReader { geometry in
                ScrollView {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                        .background {
                            PausedVideoCollapseScroll(consume: consumeVideoScroll, end: finishVideoCollapse,
                                                      canConsume: canConsumeVideoScroll, canContinue: canContinueCollapseMomentum)
                                .allowsHitTesting(false)
                        }
                }
                .scrollBounceBehavior(.always, axes: .vertical)
            }
        }
    }

    private var descriptionSection: some View {
        @Bindable var store = store

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let detail = viewModel?.detail {
                    infoBlock(detail)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                RelatedVideosSection(
                    videos: viewModel?.related ?? [],
                    isLoading: viewModel?.isLoadingRelated ?? false,
                    onSelect: store.openRelated
                )
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .background {
                PausedVideoCollapseScroll(consume: consumeVideoScroll, end: finishVideoCollapse, canConsume: canConsumeVideoScroll,
                                          canContinue: canContinueCollapseMomentum)
                    .allowsHitTesting(false)
            }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        // 收起再展开时回到原来的滚动位置。
        .scrollPosition($store.descriptionScroll)
        // 简介和相关视频共用普通页面底色。
        .background(Color(uiColor: .systemBackground))
    }

    /// 简介区。顺序照官方客户端：先「谁发的」，再标题和元信息，
    /// 然后是标签、操作栏、合集，最后才是分P。
    private func infoBlock(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 14) {
                    VideoOwnerRow(
                        owner: detail.owner,
                        avatarURL: detail.secureAvatarURL,
                        card: viewModel?.ownerCard,
                        isFollowing: viewModel?.relation?.isFollowing ?? false,
                        onToggleFollow: {
                            Task { await viewModel?.toggleFollow(isLoggedIn: account.isLoggedIn) }
                        },
                        onOpenSpace: {
                            spacePath.append(FollowedUp(
                                mid: detail.owner.mid,
                                uname: detail.owner.name,
                                face: detail.owner.face,
                                hasUpdate: false
                            ))
                        }
                    )
                    VideoIntroductionCard(
                        title: detail.title, stat: detail.stat, pubdate: detail.pubdate, desc: detail.desc,
                        isExpanded: Binding(get: { store.isDescriptionExpanded },
                                            set: { store.isDescriptionExpanded = $0 })
                    )
                }
            }
            .padding(.horizontal, Self.contentInset)

            if let tags = viewModel?.tags, !tags.isEmpty {
                VideoTagsRow(tags: tags, horizontalInset: Self.contentInset) { tag in
                    spacePath.append(VideoTagSearchRoute(keyword: tag.tagName))
                }
            }

            actionBar(detail)
                .padding(.horizontal, Self.contentInset)

            if let season = detail.ugcSeason, !season.episodes.isEmpty {
                UgcSeasonRow(
                    season: season,
                    currentIndex: currentEpisodeIndex(in: season),
                    onTap: { isShowingSeason = true }
                )
                .padding(.horizontal, Self.contentInset)
            }

            if detail.pages.count > 1 {
                VideoPartsRow(
                    parts: detail.pages,
                    currentIndex: currentPartIndex(in: detail),
                    onTap: { isShowingParts = true }
                )
                .padding(.horizontal, Self.contentInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionBar(_ detail: VideoDetail) -> some View {
        let relation = viewModel?.relation

        return VideoActionBar(
            likeCount: viewModel?.likeCount ?? detail.stat.like,
            coinCount: viewModel?.coinCount ?? detail.stat.coin,
            favoriteCount: viewModel?.favoriteCount ?? detail.stat.favorite,
            shareCount: detail.stat.share,
            isLiked: viewModel?.displayedIsLiked ?? (relation?.isLiked ?? false),
            isDisliked: relation?.isDisliked ?? false,
            isCoined: relation?.isCoined ?? false,
            isFavorited: relation?.isFavorited ?? false,
            shareURL: URL(string: "https://www.bilibili.com/video/\(detail.bvid)"),
            onLike: { Task { await viewModel?.toggleLike(isLoggedIn: account.isLoggedIn) } },
            onTriple: { Task { await viewModel?.tripleAction(isLoggedIn: account.isLoggedIn) } },
            onDislike: { Task { await viewModel?.toggleDislike(isLoggedIn: account.isLoggedIn) } },
            onCoin: { Task { await viewModel?.addCoin(isLoggedIn: account.isLoggedIn) } },
            onFavorite: {
                // 还没收藏时要先问收进哪个收藏夹；已经收藏了再点就是撤销，
                // 直接从所有收藏夹里移除，不必再弹一次窗让用户挨个取消勾选。
                if relation?.isFavorited == true {
                    Task { await viewModel?.unfavoriteEverywhere(isLoggedIn: account.isLoggedIn) }
                } else {
                    presentFavoriteFolders()
                }
            },
            onPickFavoriteFolder: presentFavoriteFolders
        )
    }

    /// 收藏夹选择弹窗要用当前账号的 mid 去查收藏夹，未登录时没有可查的东西。
    private func presentFavoriteFolders() {
        guard account.isLoggedIn else {
            viewModel?.actionMessage = "请先登录"
            return
        }
        isShowingFavoriteFolders = true
    }

    /// 当前这一集在合集里排第几，用于折叠行右侧的「12/41」。
    private func currentEpisodeIndex(in season: UgcSeason) -> Int? {
        guard let bvid = store.route?.bvid,
              let index = season.episodes.firstIndex(where: { $0.bvid == bvid })
        else { return nil }
        return index + 1
    }

    /// 当前播放的分P排第几（从 1 开始），用于折叠行右侧的「P3/12」。
    private func currentPartIndex(in detail: VideoDetail) -> Int? {
        let cid = store.activeCid ?? detail.cid
        guard let index = detail.pages.firstIndex(where: { $0.cid == cid }) else { return nil }
        return index + 1
    }

    /// 播放内核给出的实际画幅优先；首帧前用当前分P尺寸，避免切到竖屏P仍显示横屏画幅。
    private var inlineAspectRatio: Double? {
        if let ratio = store.player?.displayAspectRatio, ratio.isFinite, ratio > 0 {
            return ratio
        }
        guard let detail = viewModel?.detail else { return nil }
        let cid = store.activeCid ?? detail.cid
        let dimensions = [
            detail.pages.first(where: { $0.cid == cid })?.dimension,
            cid == detail.cid ? detail.dimension : nil
        ]
        for case let dimension? in dimensions {
            if let ratio = InlineVideoLayout.aspectRatio(
                width: dimension.width,
                height: dimension.height,
                rotation: dimension.rotate
            ) {
                return ratio
            }
        }
        return nil
    }

    static func inlineVideoHeight(
        for size: CGSize,
        aspectRatio: Double? = nil,
        hidesPortraitVideos: Bool = false
    ) -> CGFloat {
        InlineVideoLayout.height(for: size, aspectRatio: aspectRatio, hidesPortraitVideos: hidesPortraitVideos)
    }

    private func toggleFullScreen() {
        let now = Date()
        guard now.timeIntervalSince(lastFullScreenToggle) > Self.fullScreenToggleCooldown else { return }
        lastFullScreenToggle = now

        if isFullScreen {
            withAnimation(.easeInOut(duration: 0.25)) { isPortraitFullScreen = false }
            OrientationController.enterPortrait()
        } else if isPortraitVideo {
            withAnimation(.easeInOut(duration: 0.25)) { isPortraitFullScreen = true }
            OrientationController.enterPortrait()
        } else {
            OrientationController.enterLandscape()
        }
    }

    /// 播放内核补齐旋转元数据或切换分P后，让全屏方向跟随当前画幅。
    private func updateFullScreenOrientation() {
        guard isFullScreen, let ratio = inlineAspectRatio, ratio.isFinite, ratio > 0 else { return }
        if isPortraitVideo {
            guard !isPortraitFullScreen else { return }
            isPortraitFullScreen = true
            OrientationController.enterPortrait()
        } else if isPortraitFullScreen {
            // 等实际横屏后再清除竖屏全屏标记，方向请求失败时仍保留完整播放器。
            OrientationController.enterLandscape()
        }
    }
}


#Preview {
    VideoPage()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
