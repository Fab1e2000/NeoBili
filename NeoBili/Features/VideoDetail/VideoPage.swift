import SwiftUI

/// 全屏的视频页。
///
/// 它本身不持有播放器；视频、详情、评论和滚动状态由 `NowPlayingStore` 管理。
/// 页面退出时根据小窗设置继续播放，播放器不会随页面销毁。
struct VideoPage: View {
    @Environment(\.appThemeColor) private var themeColor
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
    @State private var commentTimeJump = EnvironmentAction<Double> { _ in }

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
    @State private var isShowingDanmakuComposer = false
    /// 发弹幕面板的草稿和位置：没发出去就关掉时保留。
    @State private var danmakuDraft = ""
    @State private var danmakuMode = DanmakuMode.scroll
    /// 打开面板前视频在播放，关闭后恢复。
    @State private var resumesAfterDanmaku = false
    /// 头像点开的 UP 主空间页。视频页本身是 fullScreenCover，不在任何
    /// 导航栈里，所以自己带一个栈来推空间页。
    @State private var spacePath = NavigationPath()

    var body: some View {
        commentTimeJump.setHandler { [store, feedback] seconds in
            guard let player = store.player, player.hasRenderedFirstFrame,
                  !player.isLoading, player.duration.isFinite, player.duration > 0 else {
                feedback.show("视频尚未准备好，请稍后重试")
                return
            }
            guard seconds.isFinite, seconds >= 0, seconds <= player.duration else {
                feedback.show("该时间点超出当前视频时长")
                return
            }
            Task {
                guard store.player === player else { return }
                await player.seek(to: seconds)
            }
        }
        return NavigationStack(path: $spacePath) {
            withSheets(videoPageRoot)
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

    /// 视频页上弹出的面板：合集、分 P、发弹幕、收藏夹。单独拆出来以减轻主体的类型推断负担。
    private func withSheets(_ content: some View) -> some View {
        content
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
                    coverURL: store.route?.secureCoverURL,
                    onSelect: { part in store.selectPart(cid: part.cid) }
                )
                .appTextSize()
            }
        }
        .modifier(DanmakuComposerPresentation(
            isPresented: $isShowingDanmakuComposer, draft: $danmakuDraft, mode: $danmakuMode,
            send: sendDanmaku,
            onDismiss: {
                if resumesAfterDanmaku { store.player?.play() }
                resumesAfterDanmaku = false
            }
        ))
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
                    videoArea(isVideoHidden: hidesVideo)
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
                    // 选择器固定在播放器下方，作为简介和评论两页的顶部栏：内容从它下面滑过，
                    // 由系统给出与主页一致的原生顶部模糊。
                    sectionPages
                        .environment(\.commentBottomInset, geometry.safeAreaInsets.bottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaBar(edge: .top, spacing: 0) {
                            VideoSectionBar(
                                selection: $store.section,
                                commentCount: viewModel?.detail?.stat.reply ?? 0,
                                onSendDanmaku: sendDanmakuAction
                            )
                        }
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                    .background {
                        // 延续内容底色，圆角外侧由下方的同步染色背景填充。
                        UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                            .fill(Color(uiColor: .systemBackground))
                    }
                    .background(alignment: .top) {
                        themeColor.opacity(collapseProgress)
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
                                               topInset: geometry.safeAreaInsets.top, isCollapsed: hidesVideo,
                                               player: store.player, onBack: store.goBack) {
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    if phase == .playing {
                        videoCollapseDistance = 0
                    } else {
                        clampVideoCollapse()
                    }
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
    private func videoArea(isVideoHidden: Bool) -> some View {
        if let player = store.player {
            InlineVideoPlayer(
                viewModel: player,
                controlsVisible: $playerControlsVisible,
                coverURL: store.route?.secureCoverURL,
                isFullScreen: isFullScreen,
                onToggleFullScreen: toggleFullScreen,
                onToggleCompact: compactVideoAction,
                isCompact: videoCollapseDistance > 0,
                isDanmakuSuppressed: isVideoHidden,
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
                .environment(\.commentTimeJump, commentTimeJump)
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
        VideoDescriptionContent(store: store, viewModel: viewModel,
                                components: viewModel?.detail.map(infoComponents) ?? [],
                                consume: consumeVideoScroll, end: finishVideoCollapse,
                                canConsume: canConsumeVideoScroll, canContinue: canContinueCollapseMomentum)
    }

    /// Each component owns one stable cell. Expanding the introduction never
    /// resizes or rebinds the owner row above it.
    private func infoComponents(_ detail: VideoDetail) -> [VideoDescriptionComponent] {
        var result: [VideoDescriptionComponent] = []
        result.append(VideoDescriptionComponent("owner", revision: [AnyHashable(detail.owner), AnyHashable(viewModel?.ownerCard), viewModel?.relation?.isFollowing ?? false]) {
            VideoOwnerRow(owner: detail.owner, avatarURL: detail.secureAvatarURL,
                          card: viewModel?.ownerCard,
                          isFollowing: viewModel?.relation?.isFollowing ?? false,
                          onToggleFollow: { Task { await viewModel?.toggleFollow(isLoggedIn: account.isLoggedIn) } },
                          onOpenSpace: {
                              spacePath.append(FollowedUp(mid: detail.owner.mid, uname: detail.owner.name,
                                                          face: detail.owner.face, hasUpdate: false))
                          })
                .padding(.horizontal, Self.contentInset)
                .padding(.top, 14)

        })
        result.append(VideoDescriptionComponent(introduction:
            VideoIntroductionCard(title: detail.title, stat: detail.stat, pubdate: detail.pubdate, desc: detail.desc,
                                  isExpanded: Binding(get: { store.isDescriptionExpanded }, set: { store.isDescriptionExpanded = $0 }))))
        if let tags = viewModel?.tags, !tags.isEmpty {
            result.append(VideoDescriptionComponent("tags", revision: [AnyHashable(tags)]) {
                VideoTagsRow(tags: tags, horizontalInset: Self.contentInset) { tag in
                    spacePath.append(VideoTagSearchRoute(keyword: tag.tagName))
                }
            })
        }
        result.append(VideoDescriptionComponent("actions", revision: [AnyHashable(viewModel?.relation),
                               viewModel?.likeCount ?? 0, viewModel?.coinCount ?? 0, viewModel?.favoriteCount ?? 0,
                               viewModel?.displayedIsLiked ?? false, detail.stat.share]) {
            actionBar(detail).padding(.horizontal, Self.contentInset)
        })
        if let season = detail.ugcSeason, !season.episodes.isEmpty {
            result.append(VideoDescriptionComponent("season", revision: [AnyHashable(season), AnyHashable(currentEpisodeIndex(in: season))]) {
                UgcSeasonRow(season: season, currentIndex: currentEpisodeIndex(in: season), onTap: { isShowingSeason = true })
                    .padding(.horizontal, Self.contentInset)
            })
        }
        if detail.pages.count > 1 {
            result.append(VideoDescriptionComponent("parts", revision: [AnyHashable(detail.pages), AnyHashable(currentPartIndex(in: detail))]) {
                VideoPartsRow(parts: detail.pages, currentIndex: currentPartIndex(in: detail), onTap: { isShowingParts = true })
                    .padding(.horizontal, Self.contentInset)
            })
        }
        return result.enumerated().map { index, component in
            if component.introduction != nil { return component }
            return VideoDescriptionComponent(component.id, revision: component.revision) {
                component.content.padding(.bottom, index == result.count - 1 ? 6 : 14)
            }
        }
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

    /// 详情加载好之后才显示「发弹幕」。
    private var sendDanmakuAction: (() -> Void)? {
        guard viewModel?.detail != nil else { return nil }
        return openDanmakuComposer
    }

    /// 与 PiliPlus 一致：打开发弹幕面板时暂停，弹幕出现在暂停的那一刻，关掉面板后继续播放。
    private func openDanmakuComposer() {
        guard account.isLoggedIn else {
            viewModel?.actionMessage = "请先登录"
            return
        }
        resumesAfterDanmaku = store.player?.isPlaying == true
        store.player?.pause()
        isShowingDanmakuComposer = true
    }

    private func sendDanmaku(_ text: String, mode: DanmakuMode) async throws {
        guard let detail = viewModel?.detail else { return }
        let player = store.player
        try await BiliAPI.shootDanmaku(cid: store.activeCid ?? detail.cid, bvid: detail.bvid, message: text,
                                       progress: player?.currentTime ?? 0, mode: mode.rawValue)
        player?.danmaku?.appendSent(text: text, mode: mode)
        feedback.show("弹幕已发送")
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
