import SwiftUI

struct HomeView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @State private var viewModel = HomeViewModel()
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    /// 刷新动画的快慢，设置页可调。
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    private var animations = VideoCardAnimationPreferences(source: .recommendation)
    @State private var refreshTask: Task<Void, Never>?
    @State private var hasScrolledAwayFromTop = false
    @State private var feedPosition = ScrollPosition(edge: .top)
    @State private var reselectCount = 0
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isRefreshing = false
    @State private var isSearchFocused = false

    /// 刷新的三段式可视化：旧卡片原地淡出，新卡片按行落位。
    /// 参数集中在 FeedRefreshTuning 里。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 松手启动淡出；网络请求并行进行，新内容等淡出结束后再落位。
    /// 全程只有这一个量在变，卡片本身不位移，所以不会出现错位。
    @State private var listOpacity: Double = 1
    @State private var exitTiming: FeedRefreshExitTiming?
    /// 每次刷新加一，驱动每一行重新播落位动画。
    @State private var landingGeneration = 0

    /// 搜索就在首页完成，不跳页：搜索框固定在紧凑工具栏内，
    /// 回车后这一页的内容换成结果，清空后回到推荐流。
    @State private var search = SearchViewModel()
    @State private var searchHistory = SearchHistory.shared

    private var animatesExit: Bool {
        !reduceMotion && animations.isEnabled(phase: .exit)
    }

    var body: some View {
        #if DEBUG
        let _ = SearchLatencyProbe.body("HomeView")
        #endif
        NavigationStack {
            Group {
                if search.hasSubmittedSearch {
                    SearchResultsView(viewModel: search)
                } else {
                    feed
                        // The keyboard covers recommendations; it does not need to resize the grid.
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if isSearchFocused {
                    ZStack {
                        // Extend the backdrop behind the search bar, status bar, and keyboard.
                        // Keep suggestion content inside the safe area above the keyboard.
                        Color(uiColor: .systemGroupedBackground)
                            .ignoresSafeArea()
                        if search.query.isEmpty {
                            searchHistoryList
                        } else if search.isShowingSuggestions {
                            searchSuggestions
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbarVisibility(isSearchFocused ? .hidden : .automatic, for: .tabBar)
            // 用固定的安全区栏承载搜索，不再让 toolbarPrincipal 在滚动边缘恢复为双层高度。
            .safeAreaBar(edge: .top, spacing: 0) { homeSearchBar }
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
                if isSearchFocused || search.hasSubmittedSearch {
                    cancelSearch()
                } else {
                    reselectCount += 1
                }
            }
            .frame(width: 0, height: 0)
        }
        .resolvePortraitVideos(viewModel.videos, batchID: landingGeneration) {
            await viewModel.loadReplacementPage()
            return viewModel.videos
        }
        .videoCardAnimationSource(.recommendation)
        .onChange(of: animatesExit) { _, enabled in
            guard !enabled else { return }
            // A settings change must also restore an already fading feed while
            // its request remains in flight.
            withAnimation(nil) { listOpacity = 1; exitTiming = nil }
        }
        #if DEBUG
        .task {
            await SearchLatencyProbe.shared.run(focus: { isSearchFocused = $0 },
                                               query: { search.query },
                                               isSearching: { search.hasSubmittedSearch },
                                               cancel: { cancelSearch() })
        }
        .onChange(of: isSearchFocused) { _, focused in SearchLatencyProbe.focusChanged(focused) }
        #endif
    }

    private var homeSearchBar: some View {
        HomeSearchBar(text: $search.query, isFocused: $isSearchFocused,
                      onSubmit: { submitSearch() }, onCancel: { cancelSearch() },
                      canClearHistory: !searchHistory.keywords.isEmpty, onClearHistory: { searchHistory.clear() })
            // UISearchBar supplies its own icon and text padding; avoid doubling those insets.
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if isSearchFocused {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
    }

    private var searchHistoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("搜索历史")
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 16)
                if searchHistory.keywords.isEmpty {
                    Text("暂无搜索历史")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, 22)
                }
                ForEach(searchHistory.keywords, id: \.self) { keyword in
                    Button { submitSearch(keyword: keyword) } label: {
                        Label(keyword, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 22)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var searchSuggestions: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(search.suggestions) { suggestion in
                    Button {
                        submitSearch(keyword: suggestion.value)
                    } label: {
                        Text(suggestion.value)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 22)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submitSearch(keyword: String? = nil) {
        search.submit(keyword: keyword)
        guard search.hasSubmittedSearch else { return }
        isSearchFocused = false
    }

    private func cancelSearch() {
        isSearchFocused = false
        search.query = ""
        search.reset()
    }

    private var feed: some View {
        GeometryReader { geometry in
            #if DEBUG
            let _ = SearchLatencyProbe.body("HomeFeed")
            #endif
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .background {
                        ShortPullRefresh(threshold: refreshDistance, enabled: !isRefreshing,
                                         onProgress: { _, _ in }, onRefresh: { startRefresh() })
                    }

                LazyVStack(spacing: HomeCardLayout.rowSpacing) {
                    ForEach(Array(viewModel.feedRows(hidingKnownPortraitVideos: hidesPortraitVideos).enumerated()), id: \.element.id) { index, row in
                        Group {
                            switch row {
                            case .videos(let videos):
                                HStack(alignment: .top, spacing: HomeCardLayout.columnSpacing) {
                                    ForEach(videos) { video in
                                        FeedDropInRow(index: 0, generation: 0,
                                                      landing: viewModel.replacementAnimationIDs.contains(video.bvid),
                                                      speed: enterSpeed, reduceMotion: reduceMotion) {
                                            videoCard(video, pageWidth: geometry.size.width)
                                        }
                                        .videoEntranceIdentity(video.bvid)
                                        .onAppear { viewModel.didShowReplacement(video.bvid) }
                                        .frame(width: (geometry.size.width - HomeCardLayout.horizontalInset * 2 - HomeCardLayout.columnSpacing) / 2)
                                    }
                                    if videos.count == 1 { Spacer(minLength: 0) }
                                }
                            case .lastSeen:
                                Button {
                                    startRefresh(scrollToTop: true)
                                } label: {
                                    LastSeenCard()
                                }
                                .buttonStyle(.plain)
                                .videoBatchEntrance()
                                .disabled(isRefreshing)
                            }
                        }
                    }
                }
                .padding(.horizontal, HomeCardLayout.horizontalInset)
                .padding(.vertical, HomeCardLayout.verticalInset)
                .opacity(animatesExit ? listOpacity : 1)

                // 翻页进度放在列表底部。
                if viewModel.isLoadingMore {
                    LoadingTaskAnchor()
                        .padding()
                }
            }
            .scrollPosition($feedPosition)
            // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollDisabled(isRefreshing && listOpacity < 1)
            // 卡片从搜索框下面滑过去时，顶部给一层渐隐，让搜索框浮在内容之上
            // 而不是硬生生压着卡片（iOS 26 的 scroll edge effect）。
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // 只在「离开顶部 / 回到顶部」这两个瞬间更新状态：滚动过程中
                // 每帧都写 CGFloat 会让整个 body（含 feedRows 分组）跟着重算。
                (geometry.contentOffset.y + geometry.contentInsets.top) > 1
            } action: { _, away in hasScrolledAwayFromTop = away }
            .onChange(of: reselectCount) {
                guard shortcutTask == nil, !isRefreshing else { return }
                if hasScrolledAwayFromTop {
                    withAnimation(.easeOut(duration: 0.25)) {
                        feedPosition.scrollTo(edge: .top)
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
            .accessibilityAction(named: "刷新推荐") { startRefresh() }
            // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
            .leftEdgeTapDeadZone()
        }
        .overlay {
            if viewModel.videos.hasPendingVideoDimensions(hidesPortraitVideos),
               !viewModel.hasVisibleVideos(hidingKnownPortraitVideos: hidesPortraitVideos) {
                LoadingTaskAnchor()
            } else if viewModel.isLoading, viewModel.videos.isEmpty {
                LoadingTaskAnchor()
            } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "wifi.slash",
                    description: Text(message)
                )
            } else if !viewModel.videos.isEmpty,
                      !viewModel.hasVisibleVideos(hidingKnownPortraitVideos: hidesPortraitVideos) {
                ContentUnavailableView {
                    Label("没有可显示的视频", systemImage: "rectangle.slash")
                } description: {
                    Text("当前推荐中的视频都被内容过滤设置隐藏了。")
                } actions: {
                    Button("刷新推荐") { startRefresh() }
                }
            }
        }
    }
    private func startRefresh(scrollToTop: Bool = false) {
        guard !isRefreshing else { return }
        beginRefresh()
        refreshTask = Task { @MainActor in
            defer {
                withAnimation(nil) { listOpacity = 1; exitTiming = nil; isRefreshing = false }
                refreshTask = nil
            }
            // Keep existing content until the request is ready, including when
            // animation settings change in the middle of the request.
            await viewModel.refresh(staged: true)
            guard !Task.isCancelled else { return }
            await finishRefresh(scrollToTop: scrollToTop)
            refreshTask = nil
        }
    }

    private func beginRefresh() {
        isRefreshing = true
        guard animatesExit else { listOpacity = 1; exitTiming = nil; return }
        let duration = FeedRefreshTuning.fadeExit(speed: exitSpeed)
        exitTiming = FeedRefreshExitTiming(start: ProcessInfo.processInfo.systemUptime, duration: duration)
        withAnimation(.easeOut(duration: duration)) { listOpacity = 0 }
    }

    private func finishRefresh(scrollToTop: Bool) async {
        guard viewModel.errorMessage == nil else {
            isRefreshing = false
            listOpacity = 1
            return
        }
        if animatesExit, let exitTiming {
            do {
                try await CardAnimationSettings.waitWhileEnabled(
                    for: exitTiming.remaining(at: ProcessInfo.processInfo.systemUptime), category: .video, phase: .exit, source: .recommendation
                )
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        // Commit data and restore opacity in one transaction. The individual
        // rows own their entry clocks; refreshing never waits for those clocks.
        withAnimation(nil) {
            if scrollToTop { feedPosition.scrollTo(edge: .top) }
            viewModel.commitStagedRefresh()
            listOpacity = 1
            landingGeneration += 1
            isRefreshing = false
        }
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
                        LoadingTaskAnchor()
                    } else {
                        Image(systemName: "eye.slash").font(.title2)
                    }
                    Text("已提交不感兴趣").font(.subheadline)
                    if !viewModel.replacingIDs.contains(video.bvid) {
                        Text("点击重试换一条").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: HomeCardLayout.cardHeight(for: pageWidth))
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.replacingIDs.contains(video.bvid))
            .task { await viewModel.loadMoreIfNeeded(current: video, hidingKnownPortraitVideos: hidesPortraitVideos) }
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
            .task { await viewModel.loadMoreIfNeeded(current: video, hidingKnownPortraitVideos: hidesPortraitVideos) }
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
