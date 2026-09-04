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
    /// 轮盘拖动时的视觉焦点；只有停稳后才提交给 ViewModel。
    @State private var focusedTargetID: FollowingSelection.ID = .all
    @State private var listPosition = ScrollPosition(edge: .top)
    @State private var feedOpacity = 1.0
    @State private var selectionTransitionTask: Task<Void, Never>?

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
                DynamicDetailView(entry: entry, feed: viewModel.activeFeed)
            }
            // 顶部不要标题栏：头像行直接从安全区下面开始，省掉一整行高度。
            // 标题本身留着，推入 UP 主页时返回按钮才有「关注」这两个字。
            .toolbarVisibility(.hidden, for: .navigationBar)
            // 关注流滚动时底部标签栏始终保留；进入子页面后由子页面自行隐藏。
            .tabBarMinimizeBehavior(.never)
            .onAppear {
                OrientationController.enterPortrait()
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
                selectionTransitionTask?.cancel()
                feedOpacity = 1
                listPosition.scrollTo(edge: .top)
                viewModel.resetForAccountChange()
                Task { await viewModel.loadInitial() }
            }
    }

    /// 轮盘是纵向列表的第一块内容，所以往下浏览时会自然滚出屏幕。
    /// 它放在普通 VStack 中以保留横向滚动位置；只有下方长动态流使用
    /// LazyVStack，避免轮盘离屏后被回收并视觉重置到「全部动态」。
    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                FollowingCarousel(
                    items: viewModel.carouselItems,
                    focusedID: $focusedTargetID,
                    onSettled: settleSelection,
                    onOpenUp: { path.append($0) }
                )
                .padding(.top, 4)

                LazyVStack(spacing: 0) {
                    feedContent
                        .opacity(feedOpacity)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(alignment: .top) {
                    FollowingFeedPointer()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .frame(width: 20, height: 10)
                        .offset(y: -10)
                        .accessibilityHidden(true)
                }
                // 给昵称留出完整空间：箭头尖从轮盘底边开始，底边再接白色区域。
                .padding(.top, 10)
            }
        }
        .scrollPosition($listPosition)
        // 即使内容不足一屏也允许下拉刷新。
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable { await viewModel.refresh() }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .onDisappear {
            selectionTransitionTask?.cancel()
            feedOpacity = 1
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        let feed = viewModel.activeFeed

        if feed.isLoading, feed.entries.isEmpty {
            loadingPlaceholder
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await viewModel.activeFeed.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
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
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
        } else {
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
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 7) {
                            Capsule().frame(width: 96, height: 10)
                            Capsule().frame(width: 60, height: 8)
                        }
                    }

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(height: 138)
                }
                .foregroundStyle(.quaternary)
                .padding(12)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载动态")
    }

    private func card(for entry: DynamicEntry) -> some View {
        DynamicCard(
            entry: entry,
            isLiked: viewModel.activeFeed.isLiked(entry),
            likeCount: viewModel.activeFeed.likeCount(entry),
            onOpenVideo: { open(entry) },
            // 卡片头像和轮盘中央头像都可以进入 UP 主页。
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

    private func settleSelection(_ id: FollowingSelection.ID) {
        guard let target = viewModel.carouselItems.first(where: { $0.id == id }) else { return }
        guard target.id != viewModel.selectedTarget.id else { return }

        selectionTransitionTask?.cancel()
        selectionTransitionTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.07)) {
                feedOpacity = 0
            }

            do {
                try await Task.sleep(for: .milliseconds(70))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            viewModel.select(target)
            listPosition.scrollTo(edge: .top)

            withAnimation(.easeIn(duration: 0.11)) {
                feedOpacity = 1
            }
            await viewModel.loadSelectedIfNeeded()
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

/// 白色动态区域向轮盘中央伸出的指示角，替代生硬的分割线。
private struct FollowingFeedPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    FollowingView()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
