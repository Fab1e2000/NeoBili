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

    /// iPhone 上横屏就等于全屏：App 平时锁着竖屏，只有点全屏按钮才会去请求
    /// 横屏，所以真实方向本身就是全屏状态最可靠的来源。
    ///
    /// 这里之前是一个自己维护的 `@State` 布尔值，它会和屏幕方向脱钩：方向
    /// 请求被系统驳回、或者旋转还没走完时，它已经是 true，界面于是按全屏排
    /// 版而屏幕还立着——这正是「全屏显示异常」。改成读方向后，两者不可能再
    /// 不一致，也不需要用 sleep 去等旋转。
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 简介收起时显示几行。想让收起状态更高或更矮，改这个数字即可。
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

    var body: some View {
        @Bindable var store = store

        return GeometryReader { geometry in
            VStack(spacing: 0) {
                videoArea
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
                    VideoSectionBar(selection: $store.section)

                    sectionPages
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // 黑色只属于上方视频区域；下面的内容用普通页面底色。
                        // 详情还没返回时也先铺好，否则进入视频页会闪一下黑。
                        .background(Color(uiColor: .systemBackground))
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
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 上半段是普通页面底色，和下面的卡片区自然分开，不需要再画分隔线。
                        .background(Color(uiColor: .systemBackground))
                }

                RelatedVideosSection(
                    videos: viewModel?.related ?? [],
                    isLoading: viewModel?.isLoadingRelated ?? false,
                    onSelect: store.openRelated
                )
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
        }
        // 收起再展开时回到原来的滚动位置。
        .scrollPosition($store.descriptionScroll)
        // 卡片本身是 secondarySystemGroupedBackground，必须铺在分组灰底上才有对比。
        // 搜索页就是这么配的；之前这里是纯白底，白卡片贴白背景所以看起来不一样。
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func infoBlock(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(detail.title)
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                BiliImage(url: detail.secureAvatarURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                Text(detail.owner.name)
                    .font(.subheadline.weight(.medium))
                    // UP 主名字是这一行里唯一允许被压缩的部分，
                    // 右边的播放量数字则保持完整宽度。
                    .lineLimit(1)

                Spacer(minLength: 8)

                statLabel(systemImage: "play.fill", value: detail.stat.view)
                statLabel(systemImage: "hand.thumbsup.fill", value: detail.stat.like)
                statLabel(systemImage: "b.circle.fill", value: detail.stat.coin)
            }

            if !detail.desc.isEmpty {
                descriptionText(detail.desc)
            }

            if detail.pages.count > 1 {
                partList(detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    /// 简介默认只显示 `collapsedDescriptionLines` 行，点文字或“展开”都能张开。
    private func descriptionText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(store.isDescriptionExpanded ? nil : Self.collapsedDescriptionLines)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canExpand(text) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.isDescriptionExpanded.toggle()
                    }
                }

            if canExpand(text) {
                Button(store.isDescriptionExpanded ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        store.isDescriptionExpanded.toggle()
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// 简介短到一眼看完时就没必要显示“展开”。
    /// 这里按字数和换行做粗略判断；想让更多简介带上展开按钮，把字数调小即可。
    private func canExpand(_ text: String) -> Bool {
        text.count > 50 || text.contains("\n")
    }

    private func partList(_ detail: VideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分P (\(detail.pages.count))")
                .font(.headline)

            ForEach(detail.pages) { part in
                let isSelected = (store.activeCid ?? detail.cid) == part.cid
                Button {
                    store.selectPart(cid: part.cid)
                } label: {
                    HStack {
                        Text("P\(part.page) · \(part.part)")
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? .white : .primary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background.secondary),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
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

    private func statLabel(systemImage: String, value: Int) -> some View {
        Label(value.biliCountText, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            // 播放量上百万后文字变长，不加这两行的话「123.4万」会被折成两行。
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}


#Preview {
    VideoPage()
        .environment(NowPlayingStore())
}
