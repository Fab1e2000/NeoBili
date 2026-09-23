import SwiftUI

struct LiveView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recommended: LiveFeedModel
    @State private var following: LiveFeedModel
    @State private var source: LiveFeedModel.Source = .recommended
    let onOpenRoom: (LiveRoom, String) -> Void

    init(model: LiveFeedModel = LiveFeedModel(), onOpenRoom: @escaping (LiveRoom, String) -> Void) {
        _recommended = State(initialValue: model)
        let followed = LiveFeedModel()
        followed.select(.following)
        _following = State(initialValue: followed)
        self.onOpenRoom = onOpenRoom
    }

    var body: some View {
        NavigationStack {
            // 和视频页共用原生横向分页行为，每页保留自己的列表和滚动位置。
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    page(recommended)
                        .id(LiveFeedModel.Source.recommended)
                    if account.isLoggedIn {
                        page(following)
                            .id(LiveFeedModel.Source.following)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: Binding<LiveFeedModel.Source?>(
                get: { source },
                set: { if let value = $0 { source = value } }
            ))
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            // 标题和下方的切换器常驻顶部栏，不受「标题栏」设置影响：两页左右翻页，
            // 标题放进列表会随页面横移或被切换器隔开，固定在顶部最稳定。
            // 两页各用系统原生的顶部模糊，翻页时跟着各自的页面走。
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    PageHeader(title: "直播", transitionID: "mine-avatar-live")
                        .padding(.horizontal, 20)
                    sourcePicker
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: account.sessionID) {
            source = .recommended
            following.select(.following)
        }
        .onChange(of: account.isLoggedIn) { _, loggedIn in
            if !loggedIn { source = .recommended }
            else { following.select(.following) }
        }
    }

    private var sourcePicker: LiveSourcePicker {
        LiveSourcePicker(selection: selection, showsFollowing: account.isLoggedIn)
    }

    private var selection: Binding<LiveFeedModel.Source> {
        Binding(get: { source }, set: { value in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { source = value }
        })
    }

    private func page(_ model: LiveFeedModel) -> some View {
        LiveFeedPage(model: model, isActive: model.source == source,
                     onSelectRecommended: { selection.wrappedValue = .recommended },
                     onOpenRoom: onOpenRoom)
            .frame(maxHeight: .infinity)
            .containerRelativeFrame(.horizontal)
    }
}

private struct LiveFeedPage: View {
    /// 当前显示的那一页才响应标签栏的重复点击。
    let isActive: Bool
    let onSelectRecommended: () -> Void
    let onOpenRoom: (LiveRoom, String) -> Void

    @Environment(AccountStore.self) private var account
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.tabContentOpacity) private var tabContentOpacity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    private var animations = VideoCardAnimationPreferences(source: .live)

    @State private var model: LiveFeedModel
    @State private var entranceClock = VideoEntranceClock()
    @State private var previousEntranceGeneration: Int?
    @State private var refreshTask: Task<Void, Never>?
    @State private var isRefreshing = false
    @State private var refreshID = UUID()
    @State private var listOpacity = 1.0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isAwayFromTop = false
    @State private var shortcutTask: Task<Void, Never>?

    init(model: LiveFeedModel, isActive: Bool,
         onSelectRecommended: @escaping () -> Void, onOpenRoom: @escaping (LiveRoom, String) -> Void) {
        _model = State(initialValue: model)
        self.isActive = isActive
        self.onSelectRecommended = onSelectRecommended
        self.onOpenRoom = onOpenRoom
    }

    private struct LoadContext: Hashable {
        let source: LiveFeedModel.Source
        let sessionID: UUID
        let isLoggedIn: Bool
    }

    private struct EntranceBatch: Hashable {
        let ids: [String]
        let generation: Int
    }

    private var entranceBatch: EntranceBatch {
        EntranceBatch(ids: model.rooms.map { "live:\($0.roomID)" }, generation: model.entranceGeneration)
    }

    private var animatesEnter: Bool { !reduceMotion && animations.isEnabled(phase: .enter) }
    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    var body: some View {
        feed
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: LoadContext(source: model.source, sessionID: account.sessionID,
                              isLoggedIn: account.isLoggedIn)) {
            let previousSource = model.source
            model.synchronizeAccount(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)
            // Signing out starts a new Recommended task; that task owns its request.
            guard previousSource == model.source else { return }
            await model.loadInitial()
        }
        .onAppear { OrientationController.enterPortrait() }
        .transformEnvironment(\.videoEntranceClocks) {
            $0.append(VideoEntranceScope(ids: Set(entranceBatch.ids),
                                        generation: entranceBatch.generation, clock: entranceClock))
        }
        .videoCardAnimationSource(.live)
        .task(id: entranceBatch) {
            let batch = entranceBatch
            entranceClock.prepare(ids: Set(batch.ids), generation: batch.generation,
                                  reset: previousEntranceGeneration != batch.generation)
            entranceClock.admit(batch.ids, animated: animatesEnter)
            previousEntranceGeneration = batch.generation
        }
        .onChange(of: animatesEnter) { _, enabled in
            if !enabled { entranceClock.finishAnimations() }
        }
        .onChange(of: animatesExit) { _, enabled in
            if !enabled { withAnimation(nil) { listOpacity = 1 } }
        }
        // 与推荐页一致：重复点「直播」标签，不在顶部时回到顶部，已在顶部时刷新。
        .onTabReselected(.live) {
            guard isActive, shortcutTask == nil, !isRefreshing else { return }
            if isAwayFromTop {
                withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .top) }
                // 回顶动画结束前忽略重复点击，避免误触发刷新。
                shortcutTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    shortcutTask = nil
                }
            } else {
                startRefresh()
            }
        }
        .onDisappear { resetRefreshPresentation() }
        .onChange(of: model.source) { resetRefreshPresentation() }
        .onChange(of: account.sessionID) { resetRefreshPresentation() }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if model.rooms.isEmpty {
                    initialState
                        .frame(maxWidth: .infinity, minHeight: 330)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 10) {
                        ForEach(model.rooms) { room in
                            Button { onOpenRoom(room, "live-\(model.source.rawValue)-card-\(room.roomID)") } label: { LiveRoomCard(room: room) }
                                .buttonStyle(.plain)
                                .videoTransitionSource("live-\(model.source.rawValue)-card-\(room.roomID)", in: videoTransition)
                                .videoEntranceIdentity("live:\(room.roomID)")
                                .accessibilityIdentifier("live.room.\(room.roomID)")
                                .task { await model.loadMoreIfNeeded(current: room) }
                        }
                    }
                    .opacity(animatesExit ? listOpacity : 1)
                    .allowsHitTesting(listOpacity == 1)
                    pagination
                }
            }
            // 切换标签只淡入卡片；列表本身保持不透明，顶部模糊立即出现。
            .opacity(tabContentOpacity)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background {
                ShortPullRefresh(threshold: refreshDistance, enabled: !isRefreshing && !model.isLoading,
                                 onProgress: { _, _ in },
                                 onRefresh: startRefresh)
            }
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, away in
            isAwayFromTop = away
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .accessibilityAction(named: "刷新直播", startRefresh)
    }

    @ViewBuilder
    private var initialState: some View {
        if model.isLoading || (model.loadedPage == 0 && model.errorMessage == nil) {
            ProgressView("正在加载直播")
        } else if let message = model.errorMessage {
            ContentUnavailableView {
                Label("直播加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重新加载") { Task { await refreshFeed() } }
            }
        } else {
            ContentUnavailableView {
                Label(model.source == .following ? "关注的主播暂未开播" : "暂时没有直播",
                      systemImage: "dot.radiowaves.left.and.right")
            } description: {
                Text(model.source == .following ? "开播后会显示在这里，也可以看看推荐直播。" : "稍后下拉刷新。")
            } actions: {
                if model.source == .following {
                    Button("看看推荐", action: onSelectRecommended)
                }
            }
        }
    }

    @ViewBuilder
    private var pagination: some View {
        if model.isLoadingMore {
            ProgressView().padding(.vertical, 12)
        } else if let message = model.paginationError {
            retryMessage(message) { await model.loadMore() }
        } else if model.hasMore {
            Button("加载更多") { Task { await model.loadMore() } }
                .font(.subheadline)
                .frame(minHeight: 44)
                .disabled(model.isLoading || isRefreshing)
        } else {
            Text("已经到底了").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 12)
        }
    }

    private func retryMessage(_ message: String, action: @escaping @MainActor () async -> Void) -> some View {
        VStack(spacing: 6) {
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("重试") { Task { await action() } }.frame(minHeight: 44)
        }
    }

    private func refreshFeed() async {
        guard !isRefreshing, !model.isLoading else { return }
        let requestID = UUID()
        refreshID = requestID
        isRefreshing = true
        let duration = animatesExit && !model.rooms.isEmpty ? FeedRefreshTuning.fadeExit(speed: exitSpeed) : 0
        // 与推荐页一致：松手即开始淡出，请求并行进行，两者都结束后再换上新内容；全程不显示提示。
        let exitStart = ProcessInfo.processInfo.systemUptime
        if duration > 0 { withAnimation(.easeOut(duration: duration)) { listOpacity = 0 } }
        defer {
            if refreshID == requestID {
                model.discardStagedRefresh()
                withAnimation(nil) {
                    listOpacity = 1
                    isRefreshing = false
                }
            }
        }
        await model.refresh(staged: true)
        guard !Task.isCancelled, refreshID == requestID else { return }
        // 刷新失败时 defer 直接恢复旧内容。
        guard model.errorMessage == nil else { return }
        if duration > 0 {
            let remaining = max(0, duration - (ProcessInfo.processInfo.systemUptime - exitStart))
            do {
                try await CardAnimationSettings.waitWhileEnabled(
                    for: remaining,
                    category: .video, phase: .exit, source: .live
                )
            } catch { return }
        }
        guard !Task.isCancelled, refreshID == requestID else { return }
        withAnimation(nil) {
            model.commitStagedRefresh()
            listOpacity = 1
        }
    }

    private func startRefresh() {
        guard !isRefreshing, !model.isLoading else { return }
        refreshTask = Task { await refreshFeed() }
    }

    private func resetRefreshPresentation() {
        refreshTask?.cancel()
        refreshTask = nil
        model.discardStagedRefresh()
        refreshID = UUID()
        withAnimation(nil) {
            listOpacity = 1
            isRefreshing = false
        }
    }
}

/// 直播的推荐/关注切换器。
struct LiveSourcePicker: View {
    let selection: Binding<LiveFeedModel.Source>
    let showsFollowing: Bool

    var body: some View {
        Picker("直播内容", selection: selection) {
            Text("推荐").tag(LiveFeedModel.Source.recommended)
            if showsFollowing { Text("关注").tag(LiveFeedModel.Source.following) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("live.feedSource")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
