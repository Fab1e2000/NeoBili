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
/// 页面退出时会关闭 store，播放器和相关加载任务随之停止并释放。
struct VideoPage: View {
    @Environment(NowPlayingStore.self) private var store
    /// 点赞、投币这些操作都要求登录，按钮点下去时据此决定是执行还是提示登录。
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback

    /// iPhone 上横屏就等于全屏：App 平时锁着竖屏，只有点全屏按钮才会去请求
    /// 横屏，所以真实方向本身就是全屏状态最可靠的来源。
    ///
    /// 这里之前是一个自己维护的 `@State` 布尔值，它会和屏幕方向脱钩：方向
    /// 请求被系统驳回、或者旋转还没走完时，它已经是 true，界面于是按全屏排
    /// 版而屏幕还立着——这正是「全屏显示异常」。改成读方向后，两者不可能再
    /// 不一致，也不需要用 sleep 去等旋转。
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 收起状态下标题最多显示几行。展开后标题不再截断，简介正文也跟着铺开。
    private static let collapsedDescriptionLines = 2

    private var viewModel: VideoDetailViewModel? { store.detailViewModel }

    /// iPhone 横屏时纵向尺寸类一定是 compact，竖屏时是 regular。
    private var isFullScreen: Bool { verticalSizeClass == .compact }

    /// 全屏按钮切换后，方向请求和旋转动画本身要花几百毫秒才能完成，这期间
    /// 按钮还停在原处。如果这时候又收到一次点击（不管是手误，还是屏幕边缘
    /// 的系统手势识别把同一次触摸判成了两次），会在动画走到一半时把方向
    /// 请求整个反过来——表现就是刚进全屏又立刻退出，画面停在切换中间的
    /// 尺寸上。这个时间窗内忽略掉多余的点击。
    @State private var lastFullScreenToggle = Date.distantPast
    private static let fullScreenToggleCooldown: TimeInterval = 0.6

    /// 简介区左右留白。tag 那一行要用同样的值才能和正文对齐。
    private static let contentInset: CGFloat = 16

    @State private var isShowingSeason = false
    @State private var isShowingParts = false
    @State private var isShowingFavoriteFolders = false

    var body: some View {
        @Bindable var store = store

        return GeometryReader { geometry in
            VStack(spacing: 0) {
                videoArea
                    // 左缘触控死区先盖在视频画面上；关闭按钮的 overlay 挂在
                    // 它后面、层级更高，视频页唯一的出口不会被死区挡住。
                    .leftEdgeTapDeadZone()
                    // 全屏时这个按钮让位给播放控件里的缩小按钮。
                    .overlay(alignment: .topLeading) {
                        if !isFullScreen {
                            closeButton
                        }
                    }
                    // `.aspectRatio(nil, .fit)` asks the child for its ideal
                    // ratio; it does not remove the aspect-ratio constraint. A
                    // pause changes the controls' intrinsic content and caused
                    // that ratio to be measured again, briefly resizing the
                    // fullscreen video. Explicit bounds keep playback updates
                    // from participating in the outer layout.
                    .frame(
                        width: geometry.size.width,
                        height: isFullScreen
                            ? geometry.size.height
                            : Self.inlineVideoHeight(for: geometry.size)
                    )

                if !isFullScreen {
                    VStack(spacing: 0) {
                        VideoSectionBar(
                            selection: $store.section,
                            // 用详情里的 `stat.reply`，而不是评论列表的总数：后者要等
                            // 用户真的划到评论页、列表发出第一次请求之后才有值，
                            // 于是标签上的数字迟迟不出现。详情一回来这里就有了。
                            commentCount: viewModel?.detail?.stat.reply ?? 0
                        )

                        sectionPages
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // 黑色只属于上方视频区域；下面的内容用普通页面底色。
                            // 详情还没返回时也先铺好，否则进入视频页会闪一下黑。
                            .background(Color(uiColor: .systemBackground))
                    }
                    // 简介和相关视频、评论区与视频画面盖同一条左缘死区，
                    // 防止边缘误触点开相关视频。
                    .leftEdgeTapDeadZone()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // 顶部导航栏隐藏后，状态栏安全区会露出最外层背景。设为黑色后，它会和视频画面连成一体。
        .background(Color.black)
        .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
        .statusBarHidden(isFullScreen)
        .onDisappear {
            // 系统手势关闭时负责清理；若用户已点开下一张卡片，则不能让旧页面
            // 延迟到达的 onDisappear 把新页面的 route 和 player 一起清掉。
            store.finishDismissal()
            OrientationController.enterPortrait()
        }
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

    /// 视频页没有导航栏，所以关闭入口自己画在画面左上角。
    /// 它不跟着播放控件一起隐藏——控件默认是收起的，藏起来就没有出口了。
    private var closeButton: some View {
        Button {
            store.goBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.35)))
                .contentShape(Circle())
        }
        .padding(.leading, 6)
        .padding(.top, 6)
        .accessibilityLabel(store.canGoBack ? "上一个视频" : "关闭视频")
    }

    @ViewBuilder
    private var videoArea: some View {
        if let player = store.player {
            InlineVideoPlayer(
                viewModel: player,
                coverURL: store.route?.secureCoverURL,
                isFullScreen: isFullScreen,
                onToggleFullScreen: toggleFullScreen
            )
        } else if let message = viewModel?.errorMessage {
            ContentUnavailableView(
                "加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
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

                ProgressView().tint(.white)
            }
        }
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
            CommentsView(viewModel: commentsViewModel, scrollPosition: $store.commentsScroll)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    // 简介和推流之间用一条分隔线分段，代替原来的换底色。
                    Divider()
                }

                RelatedVideosSection(
                    videos: viewModel?.related ?? [],
                    isLoading: viewModel?.isLoadingRelated ?? false,
                    onSelect: store.openRelated
                )
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
        }
        // 收起再展开时回到原来的滚动位置。
        .scrollPosition($store.descriptionScroll)
        // 整页统一用普通页面底色。相关视频那段已经改成白底 + 分隔线，
        // 不再需要靠一层分组灰底去衬托白卡片；两段同色之后，
        // 简介和推流之间也就没有那道生硬的色块交界了。
        .background(Color(uiColor: .systemBackground))
    }

    /// 简介区。顺序照官方客户端：先「谁发的」，再标题和元信息，
    /// 然后是标签、操作栏、合集，最后才是分P。
    private func infoBlock(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VideoOwnerRow(
                owner: detail.owner,
                avatarURL: detail.secureAvatarURL,
                card: viewModel?.ownerCard,
                isFollowing: viewModel?.relation?.isFollowing ?? false,
                onToggleFollow: {
                    Task { await viewModel?.toggleFollow(isLoggedIn: account.isLoggedIn) }
                }
            )
            .padding(.horizontal, Self.contentInset)

            titleBlock(detail)
                .padding(.horizontal, Self.contentInset)

            if let tags = viewModel?.tags, !tags.isEmpty {
                VideoTagsRow(tags: tags, horizontalInset: Self.contentInset)
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

    /// 标题 + 元信息 + 简介正文。
    ///
    /// 官方把简介折叠进标题右边那个箭头里：收起时只看到标题和一行数据，
    /// 展开后才在下面铺开简介全文。这样不管简介多长，进页面时操作栏的位置
    /// 都是固定的。
    private func titleBlock(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    store.isDescriptionExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Text(detail.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(store.isDescriptionExpanded ? nil : Self.collapsedDescriptionLines)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(store.isDescriptionExpanded ? 180 : 0))
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detail.title)
            .accessibilityHint(store.isDescriptionExpanded ? "收起简介" : "展开简介")

            metadataLine(detail)

            if store.isDescriptionExpanded, !detail.desc.isEmpty {
                Text(detail.desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    /// 播放量、弹幕数、发布时间那一行，以及下面的 BV 号与转载声明。
    private func metadataLine(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                [
                    "\(detail.stat.view.biliCountText)播放",
                    "\(detail.stat.danmaku.biliCountText)弹幕",
                    detail.pubdate.biliPubdateText
                ].joined(separator: "  ")
            )

            HStack(spacing: 6) {
                Text(detail.bvid)

                // copyright 为 1 是自制稿件，只有它才带这条声明；2 是转载。
                if detail.copyright == 1 {
                    Label("未经作者授权禁止转载", systemImage: "nosign")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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

    /// 内联状态下 16:9 视频区的高度。
    ///
    /// 用短边算而不是用当前宽度：退出全屏的那一瞬间容器还是横屏尺寸，按宽度
    /// 算会得到一个比屏幕还高的视频区，于是画面先撑满一下再弹回 16:9。取短边
    /// 之后这个高度在旋转前后是同一个值，中间那一下跳动就没有了。
    static func inlineVideoHeight(for size: CGSize) -> CGFloat {
        let shortEdge = min(size.width, size.height)
        guard shortEdge > 0 else { return 0 }
        return (shortEdge * 9.0 / 16.0).rounded()
    }

    /// 只负责请求方向，界面全屏与否由真实方向推导。
    ///
    /// 所以这里不再需要先改布尔值、再 sleep 等旋转，也没有「已经全屏了但屏幕
    /// 还没转过来」的中间状态可言。
    private func toggleFullScreen() {
        let now = Date()
        guard now.timeIntervalSince(lastFullScreenToggle) > Self.fullScreenToggleCooldown else { return }
        lastFullScreenToggle = now

        if isFullScreen {
            OrientationController.enterPortrait()
        } else {
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
