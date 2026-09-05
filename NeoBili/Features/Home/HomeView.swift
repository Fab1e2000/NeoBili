import SwiftUI

struct HomeView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @State private var viewModel = HomeViewModel()
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @State private var pullDistance: CGFloat = 0
    @State private var pullArmed = false
    @State private var feedOffset: CGFloat = 0
    @State private var reselectCount = 0
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isRefreshing = false
    @State private var refreshHoldingHeight: CGFloat = 0
    private static let topAnchor = "home-feed-top"

    /// 搜索就在首页完成，不跳页：系统搜索框跟随大标题一起收放，
    /// 回车后这一页的内容换成结果，清空后回到推荐流。
    @State private var search = SearchViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if search.hasSubmittedSearch {
                    SearchResultsView(viewModel: search)
                } else {
                    feed
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // 搜索框直接占据导航工具栏，不再为已移除的大标题保留空白行。
            // 导航栏自己的 Liquid Glass 会承接从下面滑过的内容。
            // （退出搜索后偶发下坠不归位是 iOS 26 系统动画的 bug，官方
            // App 也复现，这里维持 toolbarPrincipal 的紧凑形态不绕路。）
            .searchable(
                text: $search.query,
                placement: .toolbarPrincipal,
                prompt: "搜索视频"
            )
            // 系统原生的候选词浮层。点中一条由 searchCompletion 填回输入框
            // 并触发下面的 onSubmit，不需要自己处理点击。
            .searchSuggestions {
                if search.isShowingSuggestions {
                    ForEach(search.suggestions) { suggestion in
                        // 就是一行黑字：放大镜图标去掉，只留一点左边距。
                        Text(suggestion.value)
                            .foregroundStyle(.primary)
                            .padding(.leading, 6)
                            .searchCompletion(suggestion.value)
                    }
                }
            }
            .onSubmit(of: .search) { search.submit() }
            // 输入一变就重新取候选词。上一次的任务会被 SwiftUI 取消，
            // 所以视图模型里那个 250 毫秒的等待就等于防抖。
            .task(id: search.trimmedQuery) { await search.loadSuggestions() }
            // 清空输入（点「取消」或点叉）就回到推荐流。
            .onChange(of: search.trimmedQuery) {
                if search.trimmedQuery.isEmpty { search.reset() }
            }
            .task { await viewModel.loadInitial() }
            // 登录/退出后同一套推荐接口在服务端会切到个性化/通用推流，
            // 这里保留旧内容、后台换成新批次，跟 PiliPlus 的行为一致。
            .onChange(of: account.profile?.mid) {
                Task { await viewModel.refresh() }
            }
            .onAppear {
                // Popping back here always restores the app's portrait lock.
                OrientationController.enterPortrait()
            }
        }
        .background {
            HomeTabReselectionObserver {
                guard !nowPlaying.isExpanded, !nowPlaying.isServiceSheetPresented else { return }
                if search.hasSubmittedSearch {
                    search.query = ""
                    search.reset()
                } else {
                    reselectCount += 1
                }
            }
            .frame(width: 0, height: 0)
        }
    }

    private var feed: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    // 这是一个看不见的定位点。“上次看到这里”卡片被点击时，页面会回到这里再刷新。
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchor)
                        .background {
                            ShortPullRefresh(threshold: refreshDistance, enabled: !isRefreshing,
                                             onProgress: { distance, armed in
                                                 pullDistance = distance
                                                 pullArmed = armed
                                             }, onRefresh: { startRefresh() })
                        }

                    LazyVStack(spacing: HomeCardLayout.rowSpacing) {
                        ForEach(viewModel.feedRows) { row in
                            switch row {
                            case .videos(let videos):
                                HStack(alignment: .top, spacing: HomeCardLayout.columnSpacing) {
                                    ForEach(videos) { video in
                                        videoCard(video, pageWidth: geometry.size.width)
                                            .frame(width: (geometry.size.width - HomeCardLayout.horizontalInset * 2 - HomeCardLayout.columnSpacing) / 2)
                                    }
                                    if videos.count == 1 { Spacer(minLength: 0) }
                                }
                            case .lastSeen:
                                Button {
                                    Task {
                                        // 与 PiliPlus 一致：点击提示卡先回到顶部，再请求一批新推荐。
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            proxy.scrollTo(Self.topAnchor, anchor: .top)
                                        }
                                        await refreshFeed()
                                    }
                                } label: {
                                    LastSeenCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, HomeCardLayout.horizontalInset)
                    .padding(.vertical, HomeCardLayout.verticalInset)

                // 刷新进度在顶部浮层显示，翻页进度单独放在列表底部。
                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }
                }
                // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollDisabled(isRefreshing)
                // 卡片从搜索框下面滑过去时，顶部给一层渐隐，让搜索框浮在内容之上
                // 而不是硬生生压着卡片（iOS 26 的 scroll edge effect）。
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in feedOffset = offset }
                .onChange(of: reselectCount) {
                    guard shortcutTask == nil, !isRefreshing else { return }
                    if feedOffset > 1 {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(Self.topAnchor, anchor: .top)
                        }
                        // 回顶动画结束前忽略重复点击，避免误触发刷新。
                        shortcutTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            shortcutTask = nil
                        }
                    } else {
                        startRefresh()
                    }
                }
                .onChange(of: isRefreshing) { _, refreshing in
                    if refreshing {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(Self.topAnchor, anchor: .top)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if isRefreshing || pullDistance > 10 {
                        HStack(spacing: 8) {
                            if isRefreshing { ProgressView().controlSize(.small) }
                            else { Image(systemName: pullArmed ? "arrow.up" : "arrow.down") }
                            Text(isRefreshing ? "正在刷新…" : pullArmed ? "松开刷新" : "下拉刷新")
                                .font(.caption)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                        .frame(height: isRefreshing ? refreshHoldingHeight : max(-feedOffset, 40))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: isRefreshing)
                .accessibilityAction(named: "刷新推荐") { startRefresh() }
                // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
                .leftEdgeTapDeadZone()
            }
        }
        .overlay {
            if viewModel.isLoading, viewModel.videos.isEmpty {
                ProgressView("正在加载推荐…")
            } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "wifi.slash",
                    description: Text(message)
                )
            }
        }
    }
    private func startRefresh() {
        guard !isRefreshing else { return }
        // 同步锁住入口，防止同一帧内连续点击开启多个请求。
        refreshHoldingHeight = CGFloat(HomeRefreshSettings.clamped(refreshDistance))
        isRefreshing = true
        Task {
            await viewModel.refresh()
            isRefreshing = false
        }
    }

    private func refreshFeed() async {
        guard !isRefreshing else { return }
        refreshHoldingHeight = CGFloat(HomeRefreshSettings.clamped(refreshDistance))
        isRefreshing = true
        await viewModel.refresh()
        isRefreshing = false
    }

    @ViewBuilder
    private func videoCard(_ video: VideoSummary, pageWidth: CGFloat) -> some View {
        if viewModel.uninterestedIDs.contains(video.bvid) {
            Button {
                Task {
                    if let message = await viewModel.replaceUninterested(video) { feedback.show(message) }
                }
            } label: {
                VStack(spacing: 10) {
                    if viewModel.replacingIDs.contains(video.bvid) {
                        ProgressView()
                    } else {
                        Image(systemName: "eye.slash").font(.title2)
                    }
                    Text("已提交不感兴趣").font(.subheadline)
                    Text("点击换一条").font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: HomeCardLayout.cardHeight(for: pageWidth))
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.replacingIDs.isEmpty)
            .task { await viewModel.loadMoreIfNeeded(current: video) }
        } else {
            Button {
                nowPlaying.open(
                    VideoDetailRoute(bvid: video.bvid, cid: video.cid, cover: video.pic,
                                     title: video.title, artist: video.owner.name),
                    from: video.bvid
                )
            } label: {
                VideoCard(video: video)
                    .frame(height: HomeCardLayout.cardHeight(for: pageWidth))
            }
            .buttonStyle(.plain)
            .contextMenu {
                WatchLaterMenuButton(aid: video.aid, bvid: video.bvid)
                Button("不感兴趣", systemImage: "eye.slash") {
                    Task {
                        guard account.isLoggedIn else { feedback.show("请先登录"); return }
                        if let message = await viewModel.markUninterested(video) { feedback.show(message) }
                    }
                }
                .disabled(viewModel.reportingIDs.contains(video.bvid))
            }
            .videoTransitionSource(video.bvid, in: videoTransition)
            .task { await viewModel.loadMoreIfNeeded(current: video) }
            .task {
                await VideoPreparationCache.shared.prefetch(bvid: video.bvid, cid: video.cid)
            }
        }
    }

}

/// 首页双列视频卡片的尺寸参数。
private enum HomeCardLayout {
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

    /// 先根据屏幕宽度算出单列宽度，再加上 4:3 封面高度和文字区高度。
    static func cardHeight(for pageWidth: CGFloat) -> CGFloat {
        let availableWidth = max(0, pageWidth - horizontalInset * 2 - columnSpacing)
        let cardWidth = availableWidth / 2
        return cardWidth / coverAspectRatio + detailsHeight
    }
}

/// 分隔本次刷新和上一次内容的扁平提示条，横跨两列。
private struct LastSeenCard: View {
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

private struct VideoCard: View {
    let video: VideoSummary

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
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    BiliImage(url: video.secureAvatarURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())

                    Text(video.owner.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(height: HomeCardLayout.detailsHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
