import NeoBiliDomain
import SwiftUI

/// 全屏的视频页。
///
/// 视频、详情、评论和滚动状态由 NowPlayingStore 管理。
/// 退出转场结束后，按缩略播放器设置继续或结束播放。
struct VideoPage: View {
    @Environment(\.appThemeColor) private var themeColor
    @Environment(NowPlayingStore.self) private var store
    /// 点赞、投币这些操作都要求登录，按钮点下去时据此决定是执行还是提示登录。
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.castSession) private var castSession
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.scenePhase) private var scenePhase

    /// 横屏全屏仍以实际方向为准；竖屏全屏不旋转，单独记录它的显示意图。
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isPortraitFullScreen = false
    @State private var orientationOwner = UUID()
    @State private var requestsFullscreenOrientation = false
    @State private var controlsSafeArea = EdgeInsets()
    @State private var playerControlsVisible = false
    @State private var commentTimeJump = EnvironmentAction<Double> { _ in }
    @State private var commentAuthor = EnvironmentAction<CommentMember> { _ in }

    /// 收起状态下标题最多显示几行。展开后标题不再截断，简介正文也跟着铺开。

    private let offlineCache: OfflineCacheStore
    @State private var offlinePartsPicker: VideoPickerPresentation<[OfflineCacheEntry]>?

    init(offlineCache: OfflineCacheStore = .shared) { self.offlineCache = offlineCache }

    private var viewModel: VideoDetailViewModel? { store.detailViewModel }

    private var isFullScreen: Bool { isPortraitFullScreen || verticalSizeClass == .compact }
    private var isPortraitVideo: Bool { VideoFullscreenOrientation.preferred(for: inlineAspectRatio) == .portrait }
    private var isCastingCurrentVideo: Bool {
        guard let player = store.player else { return false }
        let mediaID = player.isOffline ? "offline:\(player.bvid):\(player.cid)" : "video:\(player.bvid):\(player.cid)"
        return castSession?.isCasting(mediaID: mediaID) == true
    }

    /// 首帧前以及重取播放地址期间属于加载，不能套用暂停后的隐藏／染色行为；
    /// 投屏期间按播放态约束：横屏视频保持固定展开，竖屏视频最多收缩至默认横视频尺寸，绝不收进标题栏。
    private var collapsePhase: InlineVideoPlaybackPhase {
        if isCastingCurrentVideo { return .playing }
        return store.dismissalPlaybackPhase ?? InlineVideoPlaybackPhase(
            isPlaying: store.player?.isPlaying == true,
            hasRenderedFirstFrame: store.player?.hasRenderedFirstFrame == true,
            isLoading: store.player?.isLoading ?? true
        )
    }

    /// 方向请求完成前忽略重复全屏点击，避免旋转中途反向切换。
    @State private var lastFullScreenToggle = Date.distantPast
    private static let fullScreenToggleCooldown: TimeInterval = 0.6

    /// 简介区左右留白。tag 那一行要用同样的值才能和正文对齐。
    private static let contentInset: CGFloat = 16

    @State private var collapseLayout = InlineVideoCollapseLayout(expandedHeight: 0, standardHeight: 0, allowsCompact: false)
    /// 同一段滚动距离先缩小竖屏画面，暂停后才继续将画面收进 56pt 标题栏。
    /// 放在独立观察盒子里：滚动逐帧只失效依赖它的子视图，不重建整页。
    @State private var collapseMotion = VideoCollapseMotion()
    @State private var sectionBarHeight: CGFloat = 44
    @State private var detailErrorHeight: CGFloat = 0
    /// 内容区顶部的圆角半径（连续曲率），在预览页里调定。
    private let contentCornerRadius: CGFloat = 21
    /// 合集、分P 面板以「要展示的内容」作为弹出条件：点击时一次性取好，
    /// 面板第一次弹出也不会读到空数据。见 `VideoPickerPresentation`。
    @State private var seasonPicker: VideoPickerPresentation<UgcSeason>?
    @State private var partsPicker: VideoPickerPresentation<VideoPartsPickerContent>?
    @State private var isShowingFavoriteFolders = false
    @State private var cacheSelection: VideoDetailRoute?
    @State private var isShowingDanmakuComposer = false
    @State private var isShowingFullScreenDanmakuInput = false
    /// 发弹幕面板的草稿和位置：没发出去就关掉时保留。
    @State private var danmakuDraft = ""
    @State private var danmakuMode = DanmakuMode.scroll
    /// 打开面板前视频在播放，关闭后恢复。
    @State private var resumesAfterDanmaku = false
    /// 头像点开的 UP 主空间页。视频页本身是 fullScreenCover，不在任何
    /// 导航栈里，所以自己带一个栈来推空间页。
    @State private var spacePath = NavigationPath()

    var body: some View {
        NavigationStack(path: $spacePath) {
            withSheets(videoPageRoot)
                .environment(\.openCommentAuthor, commentAuthor)
                // 视频页自己不显示导航栏；推入 UP 主空间页后由那一页显示。
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: FollowedUp.self) { up in
                    SpaceView(up: up)
                }
                .navigationDestination(for: VideoTagSearchRoute.self) { route in
                    VideoTagSearchPage(keyword: route.keyword)
                }
        }
        .task { if store.offline != nil { offlineCache.connect() } }
        .onAppear {
            installCommentTimeJump()
            if let session = castSession {
                session.onPlaybackEnded = { [store, weak session] mediaID in
                    guard let session else { return }
                    store.handleCastPlaybackEnded(mediaID: mediaID, castSession: session)
                }
            }
            commentAuthor.setHandler { [path = $spacePath] member in
                guard let mid = member.mid else { return }
                path.wrappedValue.append(FollowedUp(mid: mid, uname: member.uname, face: member.avatar, hasUpdate: false))
            }
        }
        .onDisappear {
            // 播放画面由 cover 的 onDismiss 在原生缩小动画完成后交给小窗。
            endFullScreenOrientation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.player?.savePlaybackProgress() }
        }
    }

    /// 评论里的时间链接跳到对应进度。只用到全局的 store 和提示浮层，页面出现时装一次即可。
    private func installCommentTimeJump() {
        commentTimeJump.setHandler { [store, feedback] seconds in
            guard let player = store.player, player.hasRenderedFirstFrame,
                  !player.isLoading, player.duration.isFinite, player.duration > 0 else {
                feedback.show(String(localized: "视频尚未准备好，请稍后重试"))
                return
            }
            guard seconds.isFinite, seconds >= 0, seconds <= player.duration else {
                feedback.show(String(localized: "该时间点超出当前视频时长"))
                return
            }
            Task {
                guard store.player === player else { return }
                await player.seek(to: seconds)
            }
        }
    }

    /// 视频页上弹出的面板：合集、分 P、发弹幕、收藏夹。单独拆出来以减轻主体的类型推断负担。
    private func withSheets(_ content: some View) -> some View {
        content
        .sheet(item: $cacheSelection) { route in
            OfflineDownloadSheet(bvid: route.bvid, cid: route.cid).appTextSize()
        }
        .sheet(item: $seasonPicker) { picker in
            UgcSeasonPlaybackSheet(season: picker.content)
                .appTextSize()
        }
        .sheet(item: $offlinePartsPicker) { picker in
            OfflinePartsPlaybackSheet(entries: picker.content, cache: offlineCache).appTextSize()
        }
        .sheet(item: $partsPicker) { picker in
            VideoPartsPlaybackSheet(parts: picker.content.parts, coverURL: picker.content.coverURL)
                .appTextSize()
        }
        .modifier(DanmakuComposerPresentation(
            isPresented: $isShowingDanmakuComposer,
            isFullScreenInputPresented: $isShowingFullScreenDanmakuInput,
            isFullScreen: isFullScreen,
            draft: $danmakuDraft, mode: $danmakuMode,
            send: sendDanmaku,
            onDismiss: {
                if resumesAfterDanmaku { store.player?.play() }
                resumesAfterDanmaku = false
            }
        ))
        .sheet(isPresented: $isShowingFavoriteFolders) {
            if let mid = account.profile?.mid, let aid = viewModel?.detail?.aid {
                FavoriteFolderSheet(ownerMid: mid, videoAid: aid) { add, remove, willBeFavorited in
                    Task {
                        await viewModel?.updateFavorites(
                            add: add,
                            remove: remove,
                            willBeFavorited: willBeFavorited,
                            isLoggedIn: account.isLoggedIn
                        )
                    }
                }
                .appTextSize()
            }
        }
    }

    /// 视频页的完整内容：播放区、选项栏、简介与评论。
    private var videoPageRoot: some View {
        GeometryReader { geometry in
            // 竖屏播放区从顶部安全区下沿开始，避免画面进入屏幕圆角。
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
            VStack(spacing: 0) {
                CollapsibleVideoSlot(
                    motion: collapseMotion,
                    layout: layout,
                    previousLayout: collapseLayout,
                    phase: collapsePhase,
                    isFullScreen: isFullScreen,
                    size: CGSize(width: geometry.size.width, height: geometry.size.height)
                ) { isVideoHidden in
                    videoArea(isVideoHidden: isVideoHidden, expandedHeight: layout.expandedHeight)
                }
                .background {
                    PlayerReturnGestureGuard(enabled: spacePath.isEmpty)
                        .allowsHitTesting(false)
                }

                if !isFullScreen {
                    // 选择器固定在播放器下方，作为简介和评论两页的顶部栏：内容从它下面滑过，
                    // 由系统给出与主页一致的原生顶部模糊。
                    if store.player != nil, let message = viewModel?.errorMessage {
                        InlineLoadFailure(title: "视频详情加载失败", message: message, onRetry: store.retryDetail)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailErrorHeight = $0 }
                    }
                    VStack(spacing: 0) {
                        VideoSectionBar(selection: Binding(get: { store.section }, set: { store.section = $0 }),
                                        commentCount: store.commentsViewModel?.displayCount ?? viewModel?.detail?.stat.reply ?? 0,
                                        showsComments: store.offline == nil,
                                        onSendDanmaku: sendDanmakuAction)
                            .background(.bar)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sectionBarHeight = $0 }
                        let canvasHeight = max(0, geometry.size.height + geometry.safeAreaInsets.bottom
                                               - layout.minimumHeight - sectionBarHeight
                                               - (store.player != nil && viewModel?.errorMessage != nil ? detailErrorHeight : 0))
                        VideoSectionCanvas(height: canvasHeight,
                            minimumHeight: max(0, canvasHeight - (layout.expandedHeight - layout.minimumHeight)
                                               + layout.maximumDistance(for: collapsePhase)),
                            reservation: layout.expandedHeight - layout.minimumHeight,
                            enabled: canInteractWithVideoCollapse, store: store, motion: collapseMotion) {
                                sectionPages.environment(\.commentBottomInset, geometry.safeAreaInsets.bottom)
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: contentCornerRadius,
                                                      topTrailingRadius: contentCornerRadius, style: .continuous))
                    .background {
                        // 延续内容底色，圆角外侧由下方的同步染色背景填充。
                        UnevenRoundedRectangle(topLeadingRadius: contentCornerRadius,
                                               topTrailingRadius: contentCornerRadius, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    }
                    .background(alignment: .top) {
                        CollapsedThemeStrip(motion: collapseMotion, layout: layout,
                                            previousLayout: collapseLayout, phase: collapsePhase,
                                            color: themeColor, height: contentCornerRadius)
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
                   height: geometry.size.height + (isFullScreen ? 0 : geometry.safeAreaInsets.bottom),
                   alignment: .top)
            .overlay(alignment: .top) {
                if !isFullScreen {
                    CollapseChromeSlot(motion: collapseMotion, layout: layout,
                                       previousLayout: collapseLayout, phase: collapsePhase,
                                       topInset: geometry.safeAreaInsets.top,
                                       player: store.player, onBack: store.goBack) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            collapseMotion.distance = 0
                            store.player?.play()
                        }
                    }
                }
            }
            .onChange(of: layout, initial: true) { _, layout in
                collapseMotion.distance = layout.rebasedDistance(collapseMotion.distance, from: collapseLayout, for: collapsePhase)
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
            collapseMotion.distance = 0
            playerControlsVisible = false
            spacePath = NavigationPath()
        }
        .onChange(of: store.activeCid) { old, _ in
            if old != nil { collapseMotion.distance = 0; playerControlsVisible = false }
        }
        .onChange(of: collapsePhase) { _, phase in
            if phase == .loading {
                // 换源／重试时立即恢复完整画面，不能残留暂停时的粉色栏。
                clampVideoCollapse()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    collapseMotion.distance = collapseLayout.distanceAfterPlaybackChange(collapseMotion.distance, to: phase)
                }
            }
        }
        .onChange(of: isCastingCurrentVideo) { _, casting in
            if casting {
                withAnimation(.easeInOut(duration: 0.2)) {
                    collapseMotion.distance = collapseLayout.constrainedDistance(collapseMotion.distance, for: .playing)
                }
            }
        }
        .onChange(of: inlineAspectRatio) { updateFullScreenOrientation() }
        .onChange(of: verticalSizeClass) { _, sizeClass in
            if sizeClass == .compact, !isPortraitVideo { isPortraitFullScreen = false }
        }
        // 评论里的配图点开看大图。视频页本身就是 fullScreenCover，
        // 查看器挂在它内部而不是根视图上。
        .imageViewerHost()
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
    private func videoArea(isVideoHidden: Bool, expandedHeight: CGFloat) -> some View {
        if let player = store.player {
            InlineVideoPlayer(
                viewModel: player,
                controlsVisible: $playerControlsVisible,
                coverURL: store.offline?.coverURL ?? viewModel?.detail?.secureCoverURL ?? store.route?.secureCoverURL,
                isFullScreen: isFullScreen,
                onToggleFullScreen: toggleFullScreen,
                onSendDanmaku: sendDanmakuAction,
                onToggleCompact: compactVideoAction,
                isCompact: collapseMotion.distance > 0,
                isDanmakuSuppressed: isVideoHidden,
                expandedSurfaceHeight: expandedHeight,
                controlsSafeAreaInsets: isFullScreen ? controlsSafeArea : EdgeInsets(),
                onDismiss: store.goBack,
                videoTitle: viewModel?.detail?.title ?? store.route?.title ?? "",
                videoSubtitle: viewModel?.detail?.owner.name ?? store.route?.artist ?? "",
                shareURL: onlineShareURL,
                onCache: onlineCacheAction,
                hasEpisodes: store.hasCurrentEpisodes
            )
        } else {
            // 等待详情或等待用户点播放时都保留列表封面。
            ZStack {
                Color.black

                if let coverURL = viewModel?.detail?.secureCoverURL ?? store.route?.secureCoverURL {
                    BiliImage(url: coverURL)
                        .aspectRatio(contentMode: .fit)
                }

                if let message = viewModel?.errorMessage {
                    ContentUnavailableView {
                        Label("视频详情加载失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试", systemImage: "arrow.clockwise", action: store.retryDetail)
                    }
                }
                if viewModel?.errorMessage == nil {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { playerControlsVisible.toggle() }
                    if !playerControlsVisible && !store.isWaitingForPlayback {
                        ProgressView().tint(.white).allowsHitTesting(false)
                    }
                }
            }
            .overlay {
                if playerControlsVisible || store.isWaitingForPlayback || viewModel?.errorMessage != nil {
                    PlayerGlassChrome(
                        title: viewModel?.detail?.title ?? store.route?.title ?? "",
                        subtitle: viewModel?.detail?.owner.name ?? store.route?.artist ?? "",
                        videoQualityControl: PlayerQualityControl(title: String(localized: "分辨率"), accessibilityLabel: String(localized: "分辨率"), options: [],
                                                                 selectedID: 0, isEnabled: false, onSelect: { _ in }),
                        canControlPlayback: store.isWaitingForPlayback && viewModel?.errorMessage == nil,
                        isWaiting: !store.isWaitingForPlayback && viewModel?.errorMessage == nil,
                        isFullScreen: isFullScreen, isCompact: collapseMotion.distance > 0,
                        hasError: viewModel?.errorMessage != nil,
                        safeAreaInsets: isFullScreen ? controlsSafeArea : EdgeInsets(),
                        onBack: { if isFullScreen { toggleFullScreen() } else { store.goBack() } },
                        onTogglePlayback: store.requestPlayback,
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
        return distance < 0 ? collapseMotion.distance > 0
            : collapseMotion.distance < collapseLayout.maximumDistance(for: collapsePhase)
    }

    private func canContinueCollapseMomentum() -> Bool {
        guard canInteractWithVideoCollapse else { return false }
        return collapseLayout.maximumDistance(for: collapsePhase) > 0 && collapseMotion.distance > 0
    }

    private var canInteractWithVideoCollapse: Bool {
        store.isExpanded && !store.isVideoPageInteractionInProgress
            && spacePath.isEmpty && !isFullScreen && store.route != nil
            && store.player?.errorMessage == nil && viewModel?.errorMessage == nil
    }

    private func consumeVideoScroll(_ distance: CGFloat) -> CGFloat {
        guard canConsumeVideoScroll(distance) else { return 0 }
        let old = collapseMotion.distance
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            collapseMotion.distance = collapseLayout.constrainedDistance(old + distance, for: collapsePhase)
        }
        return collapseMotion.distance - old
    }

    private func clampVideoCollapse() {
        collapseMotion.distance = collapseLayout.constrainedDistance(collapseMotion.distance, for: collapsePhase)
    }

    private func toggleCompactVideo() {
        guard canInteractWithVideoCollapse else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            collapseMotion.distance = collapseMotion.distance > 0 ? 0 : collapseLayout.compactTravel
        }
    }

    private var compactVideoAction: (() -> Void)? {
        guard canInteractWithVideoCollapse, isPortraitVideo, collapseLayout.compactTravel > 0 else { return nil }
        return { toggleCompactVideo() }
    }

    private func finishVideoCollapse() {
        // 松手后继续读取原生列表的减速偏移，不额外驱动减速或端点吸附。
    }

    /// 简介和评论使用原生横向 ScrollView 分页，与选项栏共享选中状态。
    /// 容器不预留页码指示器区域，纵向滚动仍由各自列表持有。
    private var sectionPages: some View {
        VideoSectionPager(selection: Binding(get: { store.section }, set: { store.section = $0 }),
                          showsComments: store.offline == nil, description: descriptionSection, comments: commentsSection)
    }

    @ViewBuilder
    private var commentsSection: some View {
        @Bindable var store = store

        if let commentsViewModel = store.commentsViewModel {
            CommentsView(viewModel: commentsViewModel, scrollPosition: $store.commentsScroll,
                         initialOffset: store.commentScrollBox.offset,
                         onOffsetChanged: { store.commentScrollBox.offset = $0 },
                         collapseConsume: consumeVideoScroll, collapseEnd: finishVideoCollapse,
                         canCollapse: canConsumeVideoScroll, collapseCanContinue: canContinueCollapseMomentum)
                .environment(\.commentTimeJump, commentTimeJump)
        } else {
            VideoCommentsLoadingView(consume: consumeVideoScroll, canConsume: canConsumeVideoScroll,
                                     showsSkeleton: viewModel?.errorMessage == nil)
        }
    }

    private var descriptionSection: some View {
        VideoDescriptionContent(store: store, viewModel: viewModel,
                                components: store.offline.map(offlineInfoComponents)
                                    ?? viewModel?.detail.map(infoComponents)
                                    ?? loadingDescriptionComponents,
                                showsRelated: store.offline == nil,
                                consume: consumeVideoScroll, end: finishVideoCollapse,
                                canConsume: canConsumeVideoScroll, canContinue: canContinueCollapseMomentum)
    }

    private var loadingDescriptionComponents: [VideoDescriptionComponent] {
        guard viewModel != nil, viewModel?.errorMessage == nil else { return [] }
        return [VideoDescriptionComponent("introduction-loading", revision: []) {
            VideoIntroductionSkeleton()
        }]
    }

    private func offlineInfoComponents(_ descriptor: OfflinePlaybackDescriptor) -> [VideoDescriptionComponent] {
        let entries = offlineCache.entries(in: descriptor.entry.video.groupID)
        return OfflineDescriptionComponents.make(descriptor, entries: entries, contentInset: Self.contentInset,
            descriptionExpanded: Binding(get: { store.isDescriptionExpanded }, set: { store.isDescriptionExpanded = $0 }),
            onShowParts: { offlinePartsPicker = VideoPickerPresentation(content: entries) })
    }

    private func infoComponents(_ detail: VideoDetail) -> [VideoDescriptionComponent] {
        VideoDescriptionComponents(viewModel: viewModel, contentInset: Self.contentInset,
            descriptionExpanded: Binding(get: { store.isDescriptionExpanded }, set: { store.isDescriptionExpanded = $0 }),
            currentEpisodeIndex: currentEpisodeIndex, currentPartIndex: currentPartIndex,
            onToggleFollow: { Task { await viewModel?.toggleFollow(isLoggedIn: account.isLoggedIn) } },
            onOpenSpace: {
                spacePath.append(FollowedUp(mid: detail.owner.mid, uname: detail.owner.name,
                    face: detail.owner.face, hasUpdate: false))
            },
            onOpenTag: { spacePath.append(VideoTagSearchRoute(keyword: $0.tagName)) },
            onShowSeason: {
                guard let season = detail.ugcSeason else { return }
                seasonPicker = VideoPickerPresentation(content: season)
            }, onShowParts: {
                guard detail.pages.count > 1 else { return }
                partsPicker = VideoPickerPresentation(content: VideoPartsPickerContent(
                    parts: detail.pages, coverURL: store.route?.secureCoverURL))
            },
            actionBar: actionBar).make(detail)
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
            onPickFavoriteFolder: presentFavoriteFolders,
            onCache: showCacheSelection
        )
    }

    private func showCacheSelection() {
        guard var route = store.route else { return }
        route.cid = store.activeCid
        cacheSelection = route
    }

    private var onlineShareURL: URL? {
        guard store.offline == nil, let route = store.route else { return nil }
        return URL(string: "https://www.bilibili.com/video/\(route.bvid)")
    }

    private var onlineCacheAction: (() -> Void)? {
        guard store.offline == nil else { return nil }
        return showCacheSelection
    }

    /// 详情加载好之后才显示「发弹幕」。
    private var sendDanmakuAction: (() -> Void)? {
        guard viewModel?.detail != nil else { return nil }
        return openDanmakuComposer
    }

    /// 与 PiliPlus 一致：打开发弹幕面板时暂停，弹幕出现在暂停的那一刻，关掉面板后继续播放。
    private func openDanmakuComposer() {
        guard account.isLoggedIn else {
            viewModel?.actionMessage = String(localized: "请先登录")
            return
        }
        resumesAfterDanmaku = store.player?.isPlaying == true
        store.player?.pause()
        // 全屏横屏时浮在画面上输入，竖屏用系统卡片。
        if isFullScreen {
            isShowingFullScreenDanmakuInput = true
        } else {
            isShowingDanmakuComposer = true
        }
    }

    private func sendDanmaku(_ text: String, mode: DanmakuMode) async throws {
        guard let detail = viewModel?.detail else { return }
        let player = store.player
        try await viewModel?.sendDanmaku(text, cid: store.activeCid ?? detail.cid,
                                        progress: player?.currentTime ?? 0, mode: mode.rawValue)
        player?.danmaku?.appendSent(text: text, mode: mode)
        feedback.show(String(localized: "弹幕已发送"))
    }

    /// 收藏夹选择弹窗要用当前账号的 mid 去查收藏夹，未登录时没有可查的东西。
    private func presentFavoriteFolders() {
        guard account.isLoggedIn else {
            viewModel?.actionMessage = String(localized: "请先登录")
            return
        }
        isShowingFavoriteFolders = true
    }

    /// 当前这一集在合集里排第几，用于折叠行右侧的「12/41」。
    private func currentEpisodeIndex(in season: UgcSeason) -> Int? {
        guard let bvid = store.route?.bvid else { return nil }
        var offset = 0
        for section in season.sections ?? [] {
            let episodes = section.episodes ?? []
            if let index = episodes.firstIndex(where: { $0.bvid == bvid }) {
                return offset + index + 1
            }
            offset += episodes.count
        }
        return nil
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

        if isFullScreen || requestsFullscreenOrientation {
            withAnimation(.easeInOut(duration: 0.25)) { endFullScreenOrientation() }
        } else {
            requestsFullscreenOrientation = true
            if isPortraitVideo {
                withAnimation(.easeInOut(duration: 0.25)) { isPortraitFullScreen = true }
            }
            OrientationController.setPlaybackOrientation(isPortraitVideo ? .portrait : .landscape, owner: orientationOwner)
        }
    }

    private func endFullScreenOrientation() {
        // Aspect-ratio updates may arrive before UIKit finishes the return to portrait.
        requestsFullscreenOrientation = false
        isPortraitFullScreen = false
        OrientationController.endPlaybackOrientation(owner: orientationOwner)
    }

    /// 播放内核补齐旋转元数据或切换分P后，让全屏方向跟随当前画幅。
    private func updateFullScreenOrientation() {
        guard requestsFullscreenOrientation, let ratio = inlineAspectRatio, ratio.isFinite, ratio > 0 else { return }
        if isPortraitVideo {
            guard !isPortraitFullScreen else { return }
            isPortraitFullScreen = true
            OrientationController.setPlaybackOrientation(.portrait, owner: orientationOwner)
        } else {
            // 等实际横屏后再清除竖屏全屏标记，方向请求失败时仍保留完整播放器。
            OrientationController.setPlaybackOrientation(.landscape, owner: orientationOwner)
        }
    }
}

private struct VideoSectionCanvas<Content: View>: View {
    let height: CGFloat
    let minimumHeight: CGFloat
    let reservation: CGFloat
    let enabled: Bool
    let content: Content
    private let context: VideoScrollContext

    init(height: CGFloat, minimumHeight: CGFloat, reservation: CGFloat, enabled: Bool,
         store: NowPlayingStore, motion: VideoCollapseMotion, @ViewBuilder content: () -> Content) {
        self.height = height
        self.minimumHeight = minimumHeight
        self.reservation = reservation
        self.enabled = enabled
        self.content = content()
        context = motion.scrollContext(store: store, minimumHeight: minimumHeight, reservation: reservation)
    }

    var body: some View {
        VideoScrollCanvas(height: height, content: content.environment(\.videoScrollContext, context))
            .onChange(of: enabled, initial: true) { _, value in context.enabled = value }
            .onChange(of: minimumHeight, initial: true) { _, value in context.minimumContentHeight = value }
            .onChange(of: reservation, initial: true) { _, value in context.reservation = value }
    }
}

struct VideoSectionPager<Description: View, Comments: View>: View {
    @Binding var selection: VideoPageSection
    let showsComments: Bool
    let description: Description
    let comments: Comments

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                description.frame(maxHeight: .infinity).containerRelativeFrame(.horizontal)
                    .id(VideoPageSection.description)
                if showsComments {
                    comments.frame(maxHeight: .infinity).containerRelativeFrame(.horizontal)
                        .id(VideoPageSection.comments)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: Binding(get: { selection }, set: {
            if let section = $0, section != selection { selection = section }
        }))
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden, axes: .horizontal)
    }
}

#Preview {
    VideoPage()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
