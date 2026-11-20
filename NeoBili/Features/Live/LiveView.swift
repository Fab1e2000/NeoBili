#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 「直播」Tab：导航栏下方是关注中正在直播的主播头像条，下面是推荐直播。
/// 两个来源不再分成两页，页面只有一条纵向滚动视图。
struct LiveView: View {
    @Environment(AccountStore.self) private var account
    @State private var model: LiveFeedModel
    @State private var directory: FollowedLiveDirectory
    let onOpenRoom: (LiveRoom, String) -> Void

    init(model: LiveFeedModel = LiveFeedModel(),
         liveDirectory: FollowedLiveDirectory? = nil,
         onOpenRoom: @escaping (LiveRoom, String) -> Void) {
        _model = State(initialValue: model)
        _directory = State(initialValue: liveDirectory ?? FollowedLiveDirectory())
        self.onOpenRoom = onOpenRoom
    }

    var body: some View {
        NavigationStack {
            // 与关注页一致：单一纵向列表，头像条常驻导航栏下方并跟着导航栏收起。
            LiveFeedPage(model: model, directory: directory, onOpenRoom: onOpenRoom)
                .safeAreaBar(edge: .top, spacing: 0) {
                    if showsFollowedLive {
                        LiveFollowedStrip(rooms: directory.rooms) { room in
                            onOpenRoom(room, "live-followed-avatar-\(room.roomID)")
                        }
                    }
                }
                .scrollEdgeEffectStyle(.hard, for: .top)
                .background(Color(uiColor: .systemGroupedBackground))
                .rootPageChrome(title: String(localized: "直播"), barFollowsCollapse: true)
        }
        .onChange(of: account.sessionID) { directory.reset() }
        .onChange(of: account.isLoggedIn) { _, loggedIn in
            if !loggedIn { directory.reset() }
        }
    }

    private var showsFollowedLive: Bool {
        account.isLoggedIn && !directory.rooms.isEmpty
    }
}

private struct LiveFeedPage: View {
    let model: LiveFeedModel
    let directory: FollowedLiveDirectory
    let onOpenRoom: (LiveRoom, String) -> Void

    @Environment(AccountStore.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.tabContentOpacity) private var tabContentOpacity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    private var animations = VideoCardAnimationPreferences(source: .live)

    @State private var entranceClock = VideoEntranceClock()
    @State private var previousEntranceGeneration: Int?
    /// 暂存刷新由统一控制器持有任务；页面只提供取回、提交与丢弃。
    @State private var refresh = ListRefreshController()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isAwayFromTop = false
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isVisible = false

    private struct LoadContext: Hashable {
        let sessionID: UUID
        let isLoggedIn: Bool
    }

    private struct DirectoryContext: Hashable {
        let isVisible: Bool
        let isActive: Bool
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
        .task(id: LoadContext(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)) {
            model.synchronizeAccount(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)
            await model.loadInitial()
        }
        // 关注直播目录只在页面可见时刷新；回到前台或再次进入本页都会重试。
        .task(id: DirectoryContext(isVisible: isVisible, isActive: scenePhase == .active,
                                   sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)) {
            guard isVisible, scenePhase == .active, account.isLoggedIn else { return }
            await directory.refresh(force: true)
        }
        .onAppear {
            OrientationController.enterPortrait()
            isVisible = true
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
            if !enabled { refresh.restoreContent() }
        }
        // 与推荐页一致：重复点「直播」标签，不在顶部时回到顶部，已在顶部时刷新。
        .onTabReselected(.live) {
            guard shortcutTask == nil, !refresh.isRefreshing else { return }
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
        .onDisappear {
            isVisible = false
            resetRefreshPresentation()
        }
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
                    .opacity(refresh.contentOpacity)
                    .allowsHitTesting(refresh.contentOpacity == 1)
                    pagination
                }
            }
            // 切换标签只淡入卡片；列表本身保持不透明，顶部模糊立即出现。
            .opacity(tabContentOpacity)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background {
                ShortPullRefresh(threshold: refreshDistance, enabled: !refresh.isRefreshing && !model.isLoading,
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
                Button("重新加载") { startRefresh() }
            }
        } else {
            ContentUnavailableView {
                Label("暂时没有直播", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                Text("稍后下拉刷新。")
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
                .font(.app(.subheadline))
                .frame(minHeight: 44)
                .disabled(model.isLoading || refresh.isRefreshing)
        } else {
            Text("已经到底了").font(.app(.footnote)).foregroundStyle(.secondary).padding(.vertical, 12)
        }
    }

    private func retryMessage(_ message: String, action: @escaping @MainActor () async -> Void) -> some View {
        VStack(spacing: 6) {
            Text(message).font(.app(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("重试") { Task { await action() } }.frame(minHeight: 44)
        }
    }

    /// 与推荐页一致：松手即开始淡出，请求并行进行，两者都结束后再换上新内容；全程不显示提示。
    /// 关注直播目录单独刷新：它要扫完关注列表的全部页，不拖慢可见的推荐内容。
    private func startRefresh() {
        guard !refresh.isRefreshing, !model.isLoading else { return }
        let refreshesFollowed = account.isLoggedIn
        refresh.start(
            hasContent: !model.rooms.isEmpty,
            animatesExit: animatesExit,
            source: .live,
            fetch: {
                if refreshesFollowed {
                    Task { await directory.refresh(force: true) }
                }
                await model.refresh(staged: true)
                // 刷新失败时控制器直接恢复旧内容。
                return !Task.isCancelled && model.errorMessage == nil
            },
            commit: { model.commitStagedRefresh() },
            discard: { model.discardStagedRefresh() }
        )
    }

    private func resetRefreshPresentation() {
        refresh.reset(discard: model.discardStagedRefresh)
    }
}

/// 关注中正在直播的主播，横向头像条；尺寸与间距沿用关注页顶部的头像条。
private struct LiveFollowedStrip: View {
    let rooms: [LiveRoom]
    let onOpen: (LiveRoom) -> Void

    private static let cellWidth: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(rooms) { room in
                    Button { onOpen(room) } label: {
                        VStack(spacing: 4) {
                            LiveFollowedAvatar(url: room.faceURL)
                            Text(room.username)
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: Self.cellWidth)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(room.username)，正在直播"))
                    .accessibilityHint("进入直播间")
                    .accessibilityIdentifier("live.followed.\(room.roomID)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("live.followed.strip")
    }
}

/// 与关注页头像同尺寸；这一条里的每个头像都代表正在直播的主播，所以不再叠「LIVE」角标。
private struct LiveFollowedAvatar: View {
    let url: URL?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let url {
                BiliImage(url: url).aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .padding(3)
    }
}
