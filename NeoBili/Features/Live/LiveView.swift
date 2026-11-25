import NeoBiliDomain
import SwiftUI

/// 「直播」Tab：导航栏下方常驻关注中正在直播的主播头像条，下方纵向滚动推荐直播。
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
            LiveFeedPage(model: model, directory: directory, onOpenRoom: onOpenRoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .safeAreaBar(edge: .top, spacing: 0) {
                    if account.isLoggedIn && !directory.rooms.isEmpty {
                        LiveFollowedStrip(rooms: directory.rooms, onOpen: onOpenRoom)
                    }
                }
                .scrollEdgeEffectStyle(.hard, for: .top)
                .rootPageChrome(title: String(localized: "直播"), barFollowsCollapse: true)
        }
        .onChange(of: account.sessionID) { directory.reset() }
        .onChange(of: account.isLoggedIn) { _, loggedIn in
            if !loggedIn { directory.reset() }
        }
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
    private var animations = VideoCardAnimationPreferences(source: .live)

    /// 暂存刷新由统一控制器持有任务；页面只提供取回、提交与丢弃。
    @State private var refresh = ListRefreshController()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isAwayFromTop = false
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isVisible = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private struct LoadContext: Hashable {
        let source: LiveFeedModel.Source
        let sessionID: UUID
        let isLoggedIn: Bool
    }

    private struct DirectoryContext: Hashable {
        let isVisible: Bool
        let isActive: Bool
        let sessionID: UUID
        let isLoggedIn: Bool
    }

    private var entranceIDs: [String] {
        model.rooms.map { "live:\($0.roomID)" }
    }

    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    var body: some View {
        feed
        .background(Color(uiColor: .systemGroupedBackground))
        .task(id: LoadContext(source: model.source, sessionID: account.sessionID,
                              isLoggedIn: account.isLoggedIn)) {
            let previousSource = model.source
            model.synchronizeAccount(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)
            guard previousSource == model.source else { return }
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
        .listEntrance(ids: entranceIDs, generation: model.entranceGeneration, source: .live)
        .videoCardAnimationSource(.live)
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
            LazyVStack(alignment: .leading, spacing: 0) {
                recommendedSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
            // 切换标签只淡入内容；列表本身保持不透明，顶部模糊立即出现。
            .opacity(tabContentOpacity)
            .background {
                ListPullRefresh(enabled: !refresh.isRefreshing && !model.isLoading,
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
    private var recommendedSection: some View {
        if model.rooms.isEmpty {
            initialState
                .frame(maxWidth: .infinity, minHeight: 330)
                .padding(.horizontal, 8)
        } else {
            if let message = model.errorMessage, !refresh.isRefreshing {
                InlineLoadFailure(title: "直播列表未能刷新", message: message, onRetry: startRefresh)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.rooms) { room in
                    Button { onOpenRoom(room, "live-\(model.source.rawValue)-card-\(room.roomID)") } label: { LiveRoomCard(room: room) }
                        .buttonStyle(.plain)
                        .videoTransitionSource("live-\(model.source.rawValue)-card-\(room.roomID)", in: videoTransition)
                        .videoEntranceIdentity("live:\(room.roomID)")
                        .accessibilityIdentifier("live.room.\(room.roomID)")
                        .task { await model.loadMoreIfNeeded(current: room) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .opacity(refresh.contentOpacity)
            .allowsHitTesting(refresh.contentOpacity == 1)
            pagination
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
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
            }
        }
    }

    @ViewBuilder
    private var pagination: some View {
        if model.isLoadingMore {
            ProgressView().padding(.vertical, 12)
        } else if let message = model.paginationError {
            InlineLoadFailure(title: "无法加载更多直播", message: message) {
                Task { await model.loadMore() }
            }
        } else if model.hasMore {
            Button("加载更多") { Task { await model.loadMore() } }
                .font(.app(.subheadline))
                .frame(minHeight: 44)
                .disabled(model.isLoading || refresh.isRefreshing)
        } else {
            Text("已经到底了").font(.app(.footnote)).foregroundStyle(.secondary).padding(.vertical, 12)
        }
    }

    /// 与推荐页一致：松手即开始淡出，请求并行进行，两者都结束后再换上新内容；全程不显示提示。
    /// 关注直播目录单独刷新：它要扫完关注列表的全部页，不应拖慢可见的推荐内容。
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

/// 关注中正在直播的主播，头像尺寸与间距沿用关注页顶部的头像条。
private struct LiveFollowedStrip: View {
    let rooms: [LiveRoom]
    let onOpen: (LiveRoom, String) -> Void

    @Environment(\.videoTransitionNamespace) private var videoTransition
    private static let cellWidth: CGFloat = 64

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(rooms) { room in
                    let sourceID = "live-followed-avatar-\(room.roomID)"
                    Button { onOpen(room, sourceID) } label: {
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
                    .videoTransitionSource(sourceID, in: videoTransition)
                    .accessibilityLabel(Text("\(room.username)，正在直播"))
                    .accessibilityHint("进入直播间")
                    .accessibilityIdentifier("live.followed.\(room.roomID)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("live.followed.strip")
    }
}

/// 头像条里的主播均在直播，沿用历史设计的圆形头像与细边框。
private struct LiveFollowedAvatar: View {
    let url: URL?

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
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .padding(3)
    }
}
