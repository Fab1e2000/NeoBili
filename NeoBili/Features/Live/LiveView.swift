import SwiftUI

struct LiveView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @State private var model: LiveFeedModel
    @State private var showsRoomEntry = false
    @State private var pendingRoom: LiveRoom?
    @State private var entranceClock = VideoEntranceClock()
    @State private var previousEntranceGeneration: Int?
    @State private var isRefreshing = false
    @State private var refreshID = UUID()
    @State private var listOpacity = 1.0
    private var animations = VideoCardAnimationPreferences(source: .live)
    let onOpenRoom: (LiveRoom) -> Void

    init(model: LiveFeedModel = LiveFeedModel(), onOpenRoom: @escaping (LiveRoom) -> Void) {
        _model = State(initialValue: model)
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
        NavigationStack {
            feed
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("直播")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("打开直播间", systemImage: "link") { showsRoomEntry = true }
                            .accessibilityIdentifier("live.openRoom")
                    }
                }
                .safeAreaBar(edge: .top, spacing: 0) { selector }
                .task(id: LoadContext(source: model.source, sessionID: account.sessionID,
                                      isLoggedIn: account.isLoggedIn)) {
                    let previousSource = model.source
                    model.synchronizeAccount(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)
                    // Signing out starts a new Recommended task; that task owns its request.
                    guard previousSource == model.source else { return }
                    await model.loadInitial()
                }
                .sheet(isPresented: $showsRoomEntry, onDismiss: {
                    if let room = pendingRoom {
                        pendingRoom = nil
                        onOpenRoom(room)
                    }
                }) {
                    LiveRoomEntrySheet { pendingRoom = $0 }
                }
                .onAppear { OrientationController.enterPortrait() }
        }
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
        .onChange(of: model.source) { resetRefreshPresentation() }
        .onChange(of: account.sessionID) { resetRefreshPresentation() }
    }

    private var selector: some View {
        Picker("直播内容", selection: Binding(get: { model.source }, set: { model.select($0) })) {
            Text("推荐").tag(LiveFeedModel.Source.recommended)
            if account.isLoggedIn { Text("关注").tag(LiveFeedModel.Source.following) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("live.feedSource")
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if model.rooms.isEmpty {
                    initialState
                        .frame(maxWidth: .infinity, minHeight: 330)
                } else {
                    if let message = model.errorMessage {
                        retryMessage(message) { await refreshFeed() }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)], spacing: 16) {
                        ForEach(model.rooms) { room in
                            Button { onOpenRoom(room) } label: { LiveRoomCard(room: room) }
                                .buttonStyle(.plain)
                                .videoEntranceIdentity("live:\(room.roomID)")
                                .accessibilityIdentifier("live.room.\(room.roomID)")
                                .task { await model.loadMoreIfNeeded(current: room) }
                        }
                    }
                    .opacity(animatesExit ? listOpacity : 1)
                    .allowsHitTesting(!isRefreshing)
                    pagination
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .refreshable { await refreshFeed() }
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
                    Button("看看推荐") { model.select(.recommended) }
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
        let startedAt = ProcessInfo.processInfo.systemUptime
        let duration = animatesExit && !model.rooms.isEmpty ? FeedRefreshTuning.fadeExit(speed: exitSpeed) : 0
        if duration > 0 {
            withAnimation(.easeOut(duration: duration)) { listOpacity = 0 }
        }
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
        if animatesExit {
            do {
                try await CardAnimationSettings.waitWhileEnabled(
                    for: max(0, duration - (ProcessInfo.processInfo.systemUptime - startedAt)),
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

    private func resetRefreshPresentation() {
        refreshID = UUID()
        withAnimation(nil) {
            listOpacity = 1
            isRefreshing = false
        }
    }
}
