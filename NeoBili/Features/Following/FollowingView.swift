import SwiftUI

/// 「关注」Tab。顶上一排关注的 UP 主头像，下面是他们的动态：视频投稿、
/// 纯文字、图文。排版参考 B 站客户端的动态页。
struct FollowingView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @State private var viewModel = FollowingViewModel()
    @State private var path: [FollowedUp] = []
    /// 正在看哪条动态的详情。有值时推入详情页。
    @State private var detailEntry: DynamicEntry?
    /// 往下滑时把底部标签栏收起来，往上滑再放回来（PiliPlus 的做法：
    /// 头像行本身常驻不动，让路的是系统栏）。顶部标题栏则一直是收起状态。
    @State private var isTabBarHidden = false
    /// 头像行的高度。跟着文字档位缩放，字调大时昵称不会被切掉。
    @ScaledMetric(relativeTo: .caption2) private var avatarRowHeight = FollowingLayout.avatarRowHeight

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if account.isLoggedIn {
                    feed
                } else if account.isRestoringSession {
                    ProgressView("正在检查登录状态…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    loggedOutView
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("关注")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FollowedUp.self) { up in
                SpaceView(up: up)
            }
            .navigationDestination(item: $detailEntry) { entry in
                DynamicDetailView(entry: entry)
            }
            // 顶部不要标题栏：头像行直接从安全区下面开始，省掉一整行高度。
            // 标题本身留着，推入 UP 主页时返回按钮才有「关注」这两个字。
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbarVisibility(isTabBarHidden ? .hidden : .visible, for: .tabBar)
            .onAppear {
                OrientationController.enterPortrait()
                // 从 UP 主页退回来、或者从别的标签切过来时，标签栏一律先恢复。
                isTabBarHidden = false
            }
        }
    }

    private var loggedOutView: some View {
        ContentUnavailableView {
            Label("尚未登录", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("登录后这里会显示你关注的 UP 主的最新动态。\n登录入口在「我的」页。")
        }
    }

    // MARK: - 已登录

    private var feed: some View {
        list
            .task { await viewModel.loadInitial() }
            // 换账号后关注的人整个变了，重新取一遍。
            .onChange(of: account.profile?.mid) {
                Task { await viewModel.refresh() }
            }
    }

    /// 头像行常驻在列表之外，怎么滚都在——和 PiliPlus 的动态页一样。
    /// 选中某个 UP 时它下面再多一条「XX 的动态」。
    private var list: some View {
        VStack(spacing: 0) {
            if !viewModel.ups.isEmpty {
                upsRow

                if viewModel.selectedUp != nil {
                    selectionBar
                }

                Divider()
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    cards
                }
                .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
            }
            // 即使内容不足一屏也允许下拉刷新。
            .scrollBounceBehavior(.always, axes: .vertical)
            // 往下滑收起底部标签栏，往上滑放回来。按方向判断，不看绝对位置，
            // 这样长列表里随时往回滑一点就能把标签栏找回来。
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { oldOffset, newOffset in
                let delta = newOffset - oldOffset
                guard abs(delta) > FollowingLayout.chromeScrollThreshold else { return }
                let shouldHide = delta > 0 && newOffset > FollowingLayout.chromeHideOffset
                guard shouldHide != isTabBarHidden else { return }
                withAnimation(.easeInOut(duration: 0.22)) { isTabBarHidden = shouldHide }
            }
            .refreshable { await viewModel.refresh() }
            // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
            .leftEdgeTapDeadZone()
            .overlay { listState }
        }
    }

    @ViewBuilder
    private var cards: some View {
        let feed = viewModel.activeFeed

        ForEach(feed.entries) { entry in
            card(for: entry)
                .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
                .task { await feed.loadMoreIfNeeded(current: entry) }
                .task {
                    // 视频动态露面就先把播放地址取回来，点开时通常已经有结果了。
                    if let video = entry.video {
                        await VideoPreparationCache.shared.prefetch(bvid: video.bvid)
                    }
                }
        }

        if feed.isLoadingMore {
            ProgressView()
                .padding()
        }
    }

    /// 顶部那排头像。点一下就在下面看他一个人的动态，不跳页；
    /// 长按直接进他的主页（卡片里的头像也是入口）。
    private var upsRow: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(viewModel.ups) { up in
                    Button {
                        Task { await viewModel.select(up) }
                    } label: {
                        avatarCell(up)
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture {
                        path.append(up)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
        .scrollIndicators(.hidden)
        // 横向 ScrollView 在竖直方向是「有多少给多少」，不给高度的话它会和
        // 下面的列表平分整屏，头像行就被撑成一大块空白。
        .frame(height: avatarRowHeight)
    }

    private func avatarCell(_ up: FollowedUp) -> some View {
        let isSelected = viewModel.selectedUp?.mid == up.mid
        // 选了人之后，其它人压暗——比只给选中项描边更容易一眼找到当前是谁。
        let isDimmed = viewModel.selectedUp != nil && !isSelected

        return VStack(spacing: 4) {
            BiliImage(url: up.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: FollowingLayout.avatarSize, height: FollowingLayout.avatarSize)
                .clipShape(Circle())
                .overlay {
                    if isSelected {
                        Circle().stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if up.hasUpdate {
                        // 有更新的小红点。描一圈页面底色，红点才不会糊在头像边上。
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle().stroke(
                                    Color(uiColor: .systemGroupedBackground),
                                    lineWidth: 1.5
                                )
                            }
                    }
                }

            Text(up.uname)
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .lineLimit(1)
        }
        .frame(width: FollowingLayout.avatarCellWidth)
        .opacity(isDimmed ? 0.6 : 1)
        .contentShape(Rectangle())
    }

    /// 选中某个 UP 之后，头像行下面那条「XX 的动态」。
    private var selectionBar: some View {
        HStack {
            Text("\(viewModel.selectedUp?.uname ?? "")的动态")
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { viewModel.clearSelection() }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出这个 UP 主的动态")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
    }

    private func card(for entry: DynamicEntry) -> some View {
        DynamicCard(
            entry: entry,
            isLiked: viewModel.activeFeed.isLiked(entry),
            likeCount: viewModel.activeFeed.likeCount(entry),
            onOpenVideo: { open(entry) },
            // 卡片里的头像才是 UP 主页的入口；顶部那排头像只切换下面的内容。
            onOpenAuthor: {
                path.append(
                    FollowedUp(
                        mid: entry.authorMid,
                        uname: entry.authorName,
                        face: entry.authorFace,
                        hasUpdate: false
                    )
                )
            },
            onLike: { like(entry) },
            onOpenDetail: { detailEntry = entry }
        )
        .contextMenu {
            if let video = entry.video {
                WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
            }
        }
    }

    @ViewBuilder
    private var listState: some View {
        let feed = viewModel.activeFeed

        if feed.isLoading, feed.entries.isEmpty {
            ProgressView("正在加载动态…")
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView(
                "加载失败",
                systemImage: "wifi.slash",
                description: Text(message)
            )
        } else if !feed.isLoading, feed.entries.isEmpty {
            ContentUnavailableView(
                "还没有新动态",
                systemImage: "bell.slash",
                description: Text(
                    viewModel.selectedUp == nil
                        ? "你关注的 UP 主最近没有更新。"
                        : "这位 UP 主最近没有更新。"
                )
            )
        }
    }

    private func open(_ entry: DynamicEntry) {
        guard let video = entry.video else { return }
        // 动态流不带 cid，进详情页后再取，和搜索结果的路径一样。
        nowPlaying.open(
            VideoDetailRoute(
                bvid: video.bvid,
                cover: video.cover,
                title: video.title,
                artist: video.authorName
            ),
            from: video.bvid
        )
    }

    private func like(_ entry: DynamicEntry) {
        Task {
            if let message = await viewModel.activeFeed.toggleLike(entry, isLoggedIn: account.isLoggedIn) {
                feedback.show(message)
            }
        }
    }
}

/// 关注页的排版参数。头像行这几个数字取自 PiliPlus 的动态页。
enum FollowingLayout {
    /// 卡片与屏幕左右边缘的距离。
    static let horizontalInset: CGFloat = 8
    /// 顶部头像的直径。
    static let avatarSize: CGFloat = 38
    /// 每个头像格子的宽度（头像 + 昵称共用）。
    static let avatarCellWidth: CGFloat = 70
    /// 整条头像行的高度。
    static let avatarRowHeight: CGFloat = 76
    /// 一次滚动超过这个距离才判定方向，免得指头抖一下标签栏就闪。
    static let chromeScrollThreshold: CGFloat = 4
    /// 列表滚过这个位置之后才允许收起标签栏，顶部附近一律保持显示。
    static let chromeHideOffset: CGFloat = 24
}

#Preview {
    FollowingView()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
