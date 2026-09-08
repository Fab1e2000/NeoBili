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
    @State private var hasScrolledAwayFromTop = false
    @State private var feedPosition = ScrollPosition(edge: .top)
    @State private var reselectCount = 0
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isRefreshing = false
    @State private var isSearchFocused = false

    /// 刷新的三段式可视化：旧卡片原地淡出，新卡片按行落位。
    /// 参数集中在 FeedRefreshTuning 里。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 列表整体的浓度。下拉时先淡一点，松手后接着往下淡，数据到达后淡尽再让新卡落位。
    /// 全程只有这一个量在变，卡片本身不位移，所以不会出现错位。
    @State private var listOpacity: Double = 1
    /// 每次刷新加一，驱动每一行重新播落位动画。
    @State private var landingGeneration = 0
    /// 落位窗口。开着时新建出来的行才播动画，关掉后滚动新建的行保持原样。
    @State private var landingWindow = false
    /// 这一轮淡出的起点。数据回得比淡出还快时，靠它算出还要等多久才轮到落位。
    @State private var exitStartedAt: Date?

    /// 搜索就在首页完成，不跳页：搜索框固定在紧凑工具栏内，
    /// 回车后这一页的内容换成结果，清空后回到推荐流。
    @State private var search = SearchViewModel()

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
                        if search.isShowingSuggestions {
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
                      onSubmit: { submitSearch() }, onCancel: { cancelSearch() })
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
                                         onProgress: { distance, _ in
                                             updatePullFade(distance)
                                         }, onRefresh: { startRefresh() })
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
                .opacity(listOpacity)

                // 刷新进度在顶部浮层显示，翻页进度单独放在列表底部。
                if viewModel.isLoadingMore {
                    LoadingTaskAnchor()
                        .padding()
                }
            }
            .scrollPosition($feedPosition)
            // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollDisabled(isRefreshing)
            // 卡片从搜索框下面滑过去时，顶部给一层渐隐，让搜索框浮在内容之上
            // 而不是硬生生压着卡片（iOS 26 的 scroll edge effect）。
            .scrollEdgeEffectStyle(.soft, for: .top)
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
            .onChange(of: isRefreshing) { _, refreshing in
                if refreshing {
                    withAnimation(.easeOut(duration: 0.25)) {
                        feedPosition.scrollTo(edge: .top)
                    }
                }
            }
            // Reduce Motion 下不做位移和 3D，只留一颗系统转圈。
            .overlay(alignment: .top) {
                if reduceMotion, isRefreshing {
                    LoadingTaskAnchor().controlSize(.small).padding(.top, 12)
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
    /// 下拉过程中列表先淡一点，作为退出动画的预告。
    ///
    /// ShortPullRefresh 在真的要刷新时不会把距离清零，所以松手那一帧
    /// 浓度就停在这里的值上，接着由 beginRefresh 往下淡，中间没有跳变。
    private func updatePullFade(_ distance: CGFloat) {
        guard !isRefreshing, !reduceMotion else { return }
        let threshold = CGFloat(HomeRefreshSettings.clamped(refreshDistance))
        let progress = Double(min(max(distance, 0) / threshold, 1))
        let faded = 1 - FeedRefreshTuning.pullFade * progress
        // 值没变就不写状态：写 @State 会让整页 body 重算。
        if listOpacity != faded { listOpacity = faded }
    }

    private func startRefresh(scrollToTop: Bool = false) {
        guard !isRefreshing else { return }
        // 同步锁住入口，防止同一帧内连续点击开启多个请求。
        beginRefresh()
        Task {
            await viewModel.refresh(staged: !reduceMotion)
            finishRefresh(scrollToTop: scrollToTop)
        }
    }

    /// 退出段：旧卡片原地淡尽。不等网络，跑完就是跑完。
    private func beginRefresh() {
        isRefreshing = true
        guard !reduceMotion else { return }
        exitStartedAt = .now
        withAnimation(.easeOut(duration: FeedRefreshTuning.fadeExit(speed: exitSpeed))) {
            listOpacity = 0
        }
    }

    /// 第三段：残影淡尽，新卡逐行落位。
    ///
    /// 刷新失败或没有新内容时列表不变，这里仍然会重播落位——用户看到的是
    /// "重新发了一次牌"，而不是卡在半途。
    private func finishRefresh(scrollToTop: Bool = false) {
        guard !reduceMotion else {
            if scrollToTop { feedPosition.scrollTo(edge: .top) }
            viewModel.commitStagedRefresh()
            listOpacity = 1
            landingGeneration += 1
            isRefreshing = false
            return
        }

        // 数据回得比淡出还快时，先把淡出走完再落位，不然旧卡片是被硬切掉的。
        let total = FeedRefreshTuning.fadeExit(speed: exitSpeed)
        let elapsed = exitStartedAt.map { Date.now.timeIntervalSince($0) } ?? total
        let remaining = max(total - elapsed, 0)

        Task { @MainActor in
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            // 退出完成前继续锁住刷新入口，避免重复点击打断这一批。
            guard isRefreshing else { return }

            // 以下几句必须同一帧生效。新数据到这一刻才合并进列表——旧卡片已经
            // 淡尽，所以看不到"半透明的旧卡突然变成新卡"。合并后首屏几行都是
            // 全新的视图，它们出生就是全透明的起始态，浓度恢复成 1 也不会闪。
            // 旧列表完全淡出后回顶，不再让回顶与退出动画抢占同一段画面。
            if scrollToTop {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { feedPosition.scrollTo(edge: .top) }
            }
            landingWindow = true
            viewModel.commitStagedRefresh()
            listOpacity = 1
            landingGeneration += 1
            isRefreshing = false

            try? await Task.sleep(for: .seconds(FeedRefreshTuning.landingWindow(speed: enterSpeed)))
            landingWindow = false
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
