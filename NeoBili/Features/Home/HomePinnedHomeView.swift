import SwiftUI
import UIKit

/// 推荐页标题栏的两套实现，设置里切换：
/// - 随内容滚动 · 模糊（默认）：HomeView + HomeFeedCollection，标题是列表第一行；
/// - 固定 · 切边：本文件的 HomePinnedHomeView + HomePinnedFeedCollection，
///   标题固定为顶部栏，卡片从它下面滑过，下缘是清晰切边（与直播、关注页一致）。
enum HomeTitleBarSettings {
    static let storageKey = "neobili.homePinnedTitleBar"
    static let defaultValue = false
}

/// 固定标题栏版列表的滚动控制，给标签栏「回顶 / 刷新」和刷新后回顶使用。
@MainActor
final class HomePinnedScrollController {
    fileprivate weak var collectionView: UICollectionView?

    var isAwayFromTop: Bool {
        guard let collectionView else { return false }
        return collectionView.contentOffset.y + collectionView.adjustedContentInset.top > 1
    }

    func scrollToTop(animated: Bool) {
        guard let collectionView else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: -collectionView.adjustedContentInset.top),
            animated: animated
        )
    }
}

struct HomePinnedHomeView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @State private var showsMine = false
    @Environment(\.tabContentOpacity) private var tabContentOpacity
    /// 列表要避让的上下距离（状态栏 + 标题栏、标签栏）。
    /// 挂上固定标题栏后 UIKit 列表拿不到系统安全区，只能由这里量好交给它。
    @State private var safeInsets = EdgeInsets()
    @Environment(AccountStore.self) private var account
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @State private var viewModel = HomeViewModel()
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    /// 刷新动画的快慢，设置页可调。
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    private var animations = VideoCardAnimationPreferences(source: .recommendation)
    @State private var refreshTask: Task<Void, Never>?
    @State private var feedController = HomePinnedScrollController()
    @State private var reselectCount = 0
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isRefreshing = false

    /// 刷新的三段式可视化：旧卡片原地淡出，新卡片按行落位。
    /// 参数集中在 FeedRefreshTuning 里。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 松手启动淡出；网络请求并行进行，新内容等淡出结束后再落位。
    /// 全程只有这一个量在变，卡片本身不位移，所以不会出现错位。
    @State private var listOpacity: Double = 1
    @State private var exitTiming: FeedRefreshExitTiming?
    /// 每次刷新加一，驱动每一行重新播落位动画。
    @State private var landingGeneration = 0

    private var animatesExit: Bool {
        !reduceMotion && animations.isEnabled(phase: .exit)
    }

    var body: some View {
        #if DEBUG
        let _ = SearchLatencyProbe.body("HomePinnedHomeView")
        #endif
        // 标题栏固定在顶部，卡片从它下面滑过，下缘是清晰切边。
        feed
            .safeAreaBar(edge: .top, spacing: 0) {
                PageHeader(title: "推荐", transitionID: "mine-avatar-home", onOpenMine: { showsMine = true })
                    .padding(.horizontal, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task { await viewModel.loadInitial() }
            // 登录/退出后同一套推荐接口在服务端会切到个性化/通用推流，
            // 这里保留旧内容、后台换成新批次，跟 PiliPlus 的行为一致。
            .onChange(of: account.profile?.mid) {
                Task { await viewModel.refresh() }
            }
            .onAppear {
                // Returning to this tab always restores the app's portrait lock.
                OrientationController.enterPortrait()
            }
        .onReceive(NotificationCenter.default.publisher(for: .homeTabReselected)) { _ in
            guard !nowPlaying.isExpanded, !nowPlaying.isServiceSheetPresented else { return }
            reselectCount += 1
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
        .mineSheet(isPresented: $showsMine, transitionID: "mine-avatar-home")
    }

    private var feed: some View {
        ZStack {
            HomePinnedFeedCollection(
                rows: viewModel.feedRows(hidingKnownPortraitVideos: hidesPortraitVideos),
                viewModel: viewModel,
                hidesPortraitVideos: hidesPortraitVideos,
                isRefreshing: isRefreshing,
                isInteractionEnabled: !(isRefreshing && listOpacity < 1),
                refreshDistance: refreshDistance,
                controller: feedController,
                onRefresh: { startRefresh() },
                onOpenLastSeen: { startRefresh(scrollToTop: true) },
                safeInsets: safeInsets,
                contentOpacity: tabContentOpacity
            )
            .opacity(animatesExit ? listOpacity : 1)
            // 内容从状态栏、标题栏和标签栏下面滑过；被忽略的这段安全区量出来补进列表边距。
            .ignoresSafeArea()
            .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { safeInsets = $0 }

            // 加载、出错、全被过滤这些状态单独观察，isLoading 翻转时不重算整个列表。
            HomeFeedStatusOverlay(viewModel: viewModel, hidesPortraitVideos: hidesPortraitVideos) {
                startRefresh()
            }
        }
        .onChange(of: reselectCount) {
            guard shortcutTask == nil, !isRefreshing else { return }
            if feedController.isAwayFromTop {
                feedController.scrollToTop(animated: true)
                // 回顶动画结束前忽略重复点击，避免误触发刷新。
                shortcutTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    shortcutTask = nil
                }
            } else {
                startRefresh()
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
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
            if scrollToTop { feedController.scrollToTop(animated: false) }
            viewModel.commitStagedRefresh()
            listOpacity = 1
            landingGeneration += 1
            isRefreshing = false
        }
    }
}

/// 首次加载、加载失败、全部被过滤时盖在列表上的状态。
private struct HomeFeedStatusOverlay: View {
    let viewModel: HomeViewModel
    let hidesPortraitVideos: Bool
    let onRefresh: () -> Void

    var body: some View {
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
                Button("刷新推荐", action: onRefresh)
            }
        }
    }
}


/// 推荐页的双列列表，由 UICollectionView 承载，卡片内容仍是 SwiftUI。
///
/// SwiftUI 的 LazyVStack 每进来一页新数据都要把整个列表重新整理一遍，
/// 卡片也要等进入屏幕的那一帧才现场创建，真机录到最重的掉帧（25–50ms）
/// 都出在翻页那一刻。这里改成 UIKit：翻页只插入新增的行，已在屏幕上的行
/// 不重算；格子会提前准备，滑出屏幕后复用。每张卡独占原生格子和宿主，
/// 避免系统 zoom 对来源宿主施加的变换牵连同排卡片。分隔条仍横跨两列。
struct HomePinnedFeedCollection: UIViewRepresentable {
    let rows: [HomeFeedRow]
    let viewModel: HomeViewModel
    let hidesPortraitVideos: Bool
    let isRefreshing: Bool
    /// 刷新淡出期间列表不接收触摸。
    let isInteractionEnabled: Bool
    let refreshDistance: Double
    let controller: HomePinnedScrollController
    let onRefresh: () -> Void
    let onOpenLastSeen: () -> Void
    /// 列表铺满全屏，状态栏 + 标题栏、标签栏这两段要自己补进上下边距。
    let safeInsets: EdgeInsets
    /// 切换标签时卡片的淡入进度。只作用在格子内容上，列表本身不透明，顶部模糊不受影响。
    var contentOpacity: Double = 1

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = HomeCardLayout.rowSpacing
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak coordinator] index, environment in
            coordinator?.layoutSection(at: index, environment: environment)
        }, configuration: configuration)

        let view = HomePinnedFeedCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
        view.alwaysBounceVertical = true
        view.showsHorizontalScrollIndicator = false
        // 挂上固定标题栏后列表拿不到系统安全区（始终为 0），边距全部由 safeInsets 给出，
        // 不再让 UIKit 自动叠加，也避免刷新暂停滚动时边距跳变。
        view.contentInsetAdjustmentBehavior = .never
        view.contentInset = contentInset
        view.verticalScrollIndicatorInsets = scrollIndicatorInsets
        // 卡片从标题栏下面滑过时给一层清晰切边（iOS 26 的 scroll edge effect），底部不加。
        view.topEdgeEffect.style = .hard
        view.bottomEdgeEffect.isHidden = true
        view.delegate = coordinator
        view.prefetchDataSource = coordinator
        coordinator.attach(view)
        controller.collectionView = view
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.viewModel = viewModel
        coordinator.hidesPortraitVideos = hidesPortraitVideos
        coordinator.onRefresh = onRefresh
        coordinator.onOpenLastSeen = onOpenLastSeen
        let opacity = CGFloat(contentOpacity)
        if coordinator.contentOpacity != opacity {
            coordinator.contentOpacity = opacity
            context.animate { coordinator.applyContentOpacityToVisibleCells() }
        }
        if view.contentInset != contentInset {
            // 安全区量出来之前列表可能已按旧边距停在顶部；边距变了要把它一并移到新的顶部，
            // 否则第一排卡片会被标题栏挡住。
            let wasAtTop = view.contentOffset.y <= -view.adjustedContentInset.top + 1
            view.contentInset = contentInset
            view.verticalScrollIndicatorInsets = scrollIndicatorInsets
            if wasAtTop {
                view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: false)
            }
        }
        coordinator.state.setRefreshing(isRefreshing)
        coordinator.pull.threshold = CGFloat(HomeRefreshSettings.clamped(refreshDistance))
        coordinator.pull.enabled = !isRefreshing
        coordinator.pull.onRefresh = { [weak coordinator] in coordinator?.onRefresh() }
        // 淡出期间只屏蔽触摸，不关闭滚动：下拉松手时列表还在回弹，这时关掉滚动会打断
        // 回弹、改由 UIKit 用另一套动画把位置拉回去，途中更新的图层（例如封面图）会被
        // 带进那段动画，出现一缩一放。
        if view.isUserInteractionEnabled != isInteractionEnabled { view.isUserInteractionEnabled = isInteractionEnabled }
        controller.collectionView = view
        coordinator.update(environment: context.environment, hidesPortraitVideos: hidesPortraitVideos)
        coordinator.apply(rows)
    }

    private var contentInset: UIEdgeInsets {
        UIEdgeInsets(top: safeInsets.top + HomeCardLayout.verticalInset, left: 0,
                     bottom: safeInsets.bottom + HomeCardLayout.verticalInset, right: 0)
    }

    private var scrollIndicatorInsets: UIEdgeInsets {
        UIEdgeInsets(top: safeInsets.top, left: 0, bottom: safeInsets.bottom, right: 0)
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.pull.detach()
        #if PERFORMANCE_DEMO
        coordinator.scrollProbe.stop()
        #endif
    }

    enum Section: Hashable {
        /// 本次刷新的内容；没有分隔条时就是全部内容。
        case latest
        /// 「上次看到这里」分隔条，单独一节，高度按内容自适应。
        case marker
        /// 分隔条之后的上一批内容。
        case earlier
    }

    /// 格子里的 SwiftUI 内容和列表所在的视图树不相连，App 级的依赖要显式带过去。
    fileprivate struct CellEnvironment {
        var nowPlaying: NowPlayingStore?
        var account: AccountStore?
        var feedback: ActionFeedback?
        var namespace: Namespace.ID?
        var animationSource: VideoCardAnimationSource?
        var animationOverrides = VideoCardAnimationOverrides()
        var hidesPortraitVideos = false

        /// 这些值变了，已显示的格子要重新配置；只有设置改变时才会变。
        struct Signature: Equatable {
            var nowPlaying: ObjectIdentifier?
            var account: ObjectIdentifier?
            var feedback: ObjectIdentifier?
            var namespace: Namespace.ID?
            var animationSource: VideoCardAnimationSource?
            var animationOverrides: VideoCardAnimationOverrides
            var hidesPortraitVideos: Bool
        }

        var signature: Signature {
            Signature(nowPlaying: nowPlaying.map(ObjectIdentifier.init),
                      account: account.map(ObjectIdentifier.init),
                      feedback: feedback.map(ObjectIdentifier.init),
                      namespace: namespace,
                      animationSource: animationSource,
                      animationOverrides: animationOverrides,
                      hidesPortraitVideos: hidesPortraitVideos)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        var viewModel: HomeViewModel?
        var hidesPortraitVideos = false
        var onRefresh: () -> Void = {}
        var onOpenLastSeen: () -> Void = {}
        var contentOpacity: CGFloat = 1
        let state = HomeFeedCellState()
        let pull = ShortPullRefresh.ObserverView()
        #if PERFORMANCE_DEMO
        let scrollProbe = FeedScrollProbe()
        #endif

        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Section, String>?
        private var itemsByID: [String: HomeFeedItem] = [:]
        private var latestIDs: [String] = []
        private var earlierIDs: [String] = []
        private var hasMarker = false
        private var environment = CellEnvironment()
        private var needsReconfigureAll = false
        /// 推荐页的入场时钟。格子不直接观察它（见 `TimedFeedEntrance`），由这里监听后
        /// 把起点推给格子。
        private weak var clock: VideoEntranceClock?
        /// 每一行配置时拿到的入场起点，用来判断哪些行需要重新配置。
        private var configuredStarts: [String: [TimeInterval?]] = [:]
        /// App 的文字档位，决定标题预排版用的字号。
        private var dynamicTypeSize: DynamicTypeSize = .large

        func attach(_ view: UICollectionView) {
            collectionView = view
            #if PERFORMANCE_DEMO
            scrollProbe.attach(view)
            #endif
            let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
                self?.configure(cell, id: id)
            }
            let persistentRegistration = UICollectionView.CellRegistration<PersistentFeedHostingCell, String> { [weak self] cell, _, id in
                self?.configure(cell, id: id)
            }
            #if PERFORMANCE_DEMO
            let persistentHosts = !ProcessInfo.processInfo.arguments.contains("--configuration-feed-hosts")
            #else
            let persistentHosts = true
            #endif
            dataSource = UICollectionViewDiffableDataSource(collectionView: view) { view, indexPath, id in
                if persistentHosts && id != HomeFeedItem.lastSeen.id {
                    return view.dequeueConfiguredReusableCell(using: persistentRegistration, for: indexPath, item: id)
                }
                return view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
            view.addSubview(pull)
            view.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "刷新推荐") { [weak self] _ in
                    self?.onRefresh()
                    return true
                }
            ]
        }

        func layoutSection(at index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
            let isMarker = dataSource?.sectionIdentifier(for: index) == .marker
            let width = environment.container.effectiveContentSize.width
            // 卡片行高度固定（4:3 封面加文字区），不必逐个测量；分隔条随字号变化，按内容自适应。
            let height: NSCollectionLayoutDimension = isMarker
                ? .estimated(44)
                : .absolute(HomeCardLayout.cardHeight(for: width))
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height)
            let group: NSCollectionLayoutGroup
            if isMarker {
                group = .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            } else {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(0.5), heightDimension: .fractionalHeight(1)))
                group = .horizontal(layoutSize: size, repeatingSubitem: item, count: 2)
                group.interItemSpacing = .fixed(HomeCardLayout.columnSpacing)
            }
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = HomeCardLayout.rowSpacing
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: HomeCardLayout.horizontalInset,
                                                            bottom: 0, trailing: HomeCardLayout.horizontalInset)
            return section
        }

        func update(environment values: EnvironmentValues, hidesPortraitVideos: Bool) {
            let updated = CellEnvironment(
                nowPlaying: values[NowPlayingStore.self],
                account: values[AccountStore.self],
                feedback: values[ActionFeedback.self],
                namespace: values.videoTransitionNamespace,
                animationSource: values.videoCardAnimationSource,
                animationOverrides: values.videoCardAnimationOverrides,
                hidesPortraitVideos: hidesPortraitVideos
            )
            if updated.signature != environment.signature { needsReconfigureAll = true }
            environment = updated
            dynamicTypeSize = values.dynamicTypeSize
            let clock = values.videoEntranceClocks.first?.clock
            if clock !== self.clock {
                self.clock = clock
                // 换了时钟（首次出现）先对齐一次，之后跟着时钟的变化走。
                Task { @MainActor [weak self] in self?.entranceChanged() }
            }
        }

        func apply(_ rows: [HomeFeedRow]) {
            guard let dataSource else { return }
            let items = HomeFeedRow.collectionItems(rows)
            var seen = Set<String>()
            var byID: [String: HomeFeedItem] = [:]
            var latest: [String] = []
            var earlier: [String] = []
            var marker = false
            for row in items where seen.insert(row.id).inserted {
                byID[row.id] = row
                switch row {
                case .lastSeen: marker = true
                case .video: if marker { earlier.append(row.id) } else { latest.append(row.id) }
                }
            }

            let changed = byID.compactMap { id, row -> String? in
                guard let old = itemsByID[id] else { return nil }
                return Self.sameContent(old, row) ? nil : id
            }
            let structureChanged = dataSource.snapshot().sectionIdentifiers.isEmpty || latest != latestIDs || earlier != earlierIDs || marker != hasMarker
            // 没有变化时直接返回：刷新淡出、滚动开关这些状态也会触发这里。
            guard structureChanged || !changed.isEmpty || needsReconfigureAll else { return }

            // 只有原本就在列表里的行需要重配；新插入的行出现时自然会配置。
            let existing = Set(itemsByID.keys)
            // 新进来的行立刻在后台排好标题，等它们滑进屏幕时通常已经就绪。
            // Preserve display order: dictionary iteration can queue off-screen titles
            // before the next visible row, forcing synchronous layout during scrolling.
            let changedIDs = Set(changed)
            prepareTitles(for: items.filter { !existing.contains($0.id) || changedIDs.contains($0.id) })
            itemsByID = byID
            latestIDs = latest
            earlierIDs = earlier
            hasMarker = marker

            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            snapshot.appendSections([.latest])
            snapshot.appendItems(latest, toSection: .latest)
            if marker {
                snapshot.appendSections([.marker])
                snapshot.appendItems([HomeFeedItem.lastSeen.id], toSection: .marker)
                if !earlier.isEmpty {
                    snapshot.appendSections([.earlier])
                    snapshot.appendItems(earlier, toSection: .earlier)
                }
            }
            if needsReconfigureAll {
                snapshot.reconfigureItems(snapshot.itemIdentifiers.filter(existing.contains))
            } else if !changed.isEmpty {
                // 同一行里换了视频（例如「不感兴趣」换一条）只重配这一行。
                snapshot.reconfigureItems(changed)
            }
            needsReconfigureAll = false
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        private static func sameContent(_ lhs: HomeFeedItem, _ rhs: HomeFeedItem) -> Bool {
            switch (lhs, rhs) {
            case (.video(let a), .video(let b)): a == b
            case (.lastSeen, .lastSeen): true
            default: false
            }
        }

        private func configure(_ cell: UICollectionViewCell, id: String) {
            guard let row = itemsByID[id], let viewModel else { return }
            let environment = environment
            let starts = entranceStarts(for: row)
            configuredStarts[id] = starts
            let content = HomeFeedCellView(
                    item: row,
                    viewModel: viewModel,
                    state: state,
                    entranceStart: starts.first ?? nil,
                    onOpenLastSeen: { [weak self] in self?.onOpenLastSeen() }
                )
                .environment(environment.nowPlaying)
                .environment(environment.account)
                .environment(environment.feedback)
                .environment(\.videoTransitionNamespace, environment.namespace)
                .environment(\.videoCardAnimationSource, environment.animationSource)
                .environment(\.videoCardAnimationOverrides, environment.animationOverrides)
                .environment(\.hidesPortraitVideos, environment.hidesPortraitVideos)
                .appTextSize()
            if let cell = cell as? PersistentFeedHostingCell {
                cell.setContent(AnyView(content))
            } else {
                cell.contentConfiguration = UIHostingConfiguration { content }.margins(.all, 0)
            }
            cell.backgroundConfiguration = .clear()
            // 不要在这里强制布局（layoutIfNeeded）：配置可能发生在 SwiftUI 更新外层
            // 页面的过程中，嵌套渲染格子里的 SwiftUI 内容会丢失它对入场时钟的观察，
            // 卡片会一直停在入场动画的起点（透明），表现为刷新后出现空白行。
        }

        // MARK: 入场起点

        /// 一行里每张卡的入场起点；分隔条跟随整批最早的起点。
        private func entranceStarts(for row: HomeFeedItem) -> [TimeInterval?] {
            guard let clock else {
                return [nil]
            }
            switch row {
            case .video(let video): return [clock.starts[video.bvid]]
            case .lastSeen: return [clock.starts.values.min()]
            }
        }

        /// 时钟每次变化（刷新重置、整批放行、翻页加入新卡）后，只重新配置起点变了的行。
        /// 这一步在 SwiftUI 的更新之外、由 UIKit 执行，已显示和提前准备的格子都会拿到新值。
        private func entranceChanged() {
            guard let clock, let dataSource else { return }
            withObservationTracking {
                _ = clock.starts
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.entranceChanged() }
            }
            var snapshot = dataSource.snapshot()
            let stale = snapshot.itemIdentifiers.filter { id in
                guard let configured = configuredStarts[id], let row = itemsByID[id] else { return false }
                return configured != entranceStarts(for: row)
            }
            guard !stale.isEmpty else { return }
            snapshot.reconfigureItems(stale)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        /// 在后台排好这些行的标题；宽度要和卡片显示时一致才能命中。
        private func prepareTitles(for rows: [HomeFeedItem]) {
            guard let collectionView else { return }
            let width = HomeCardLayout.titleWidth(for: collectionView.bounds.width)
            let fontSize = PreparedTitle.fontSize(for: dynamicTypeSize)
            let scale = collectionView.traitCollection.displayScale
            for row in rows {
                guard case .video(let video) = row else { continue }
                if let key = PreparedTitle.Key(title: video.title, width: width, fontSize: fontSize, scale: scale) {
                    PreparedTitle.prepare(key)
                }
            }
        }

        // MARK: UICollectionViewDataSourcePrefetching

        /// 行快要进入屏幕时提前下载、解码封面和头像；尺寸和卡片显示时请求的一致，
        /// 卡片出现的第一帧就能直接画出来。
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let dataSource else { return }
            let scale = collectionView.traitCollection.displayScale
            let cover = HomeCardLayout.coverSize(for: collectionView.bounds.width)
            prepareTitles(for: indexPaths.compactMap { dataSource.itemIdentifier(for: $0).flatMap { itemsByID[$0] } })
            for indexPath in indexPaths {
                guard let id = dataSource.itemIdentifier(for: indexPath),
                      case .video(let video)? = itemsByID[id] else { continue }
                BiliImageLoader.prefetch(video.secureCoverURL, pointSize: cover, scale: scale)
                BiliImageLoader.prefetch(video.secureAvatarURL, pointSize: HomeCardLayout.avatarSize, scale: scale)
            }
        }

        // MARK: 切换淡入

        func applyContentOpacityToVisibleCells() {
            guard let collectionView, let dataSource else { return }
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) else { continue }
                applyContentOpacity(to: cell, id: dataSource.itemIdentifier(for: indexPath))
            }
        }

        private func applyContentOpacity(to cell: UICollectionViewCell, id: String?) {
            let alpha = contentOpacity
            if cell.contentView.alpha != alpha { cell.contentView.alpha = alpha }
        }

        // MARK: UICollectionViewDelegate

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            applyContentOpacity(to: cell, id: dataSource?.itemIdentifier(for: indexPath))
            // 提前准备好的格子可能错过了重新配置：显示前核对一次入场起点。
            if let id = dataSource?.itemIdentifier(for: indexPath), let row = itemsByID[id],
               configuredStarts[id] != entranceStarts(for: row) {
                configure(cell, id: id)
            }
            // 显示到最后几行时翻页；是否真的需要加载仍由 ViewModel 按末尾可见视频判断。
            guard let dataSource, let viewModel,
                  let id = dataSource.itemIdentifier(for: indexPath),
                  case .video(let video)? = itemsByID[id] else { return }
            let lastSection = collectionView.numberOfSections - 1
            guard indexPath.section == lastSection,
                  indexPath.item >= collectionView.numberOfItems(inSection: lastSection) - 6 else { return }
            let hides = hidesPortraitVideos
            Task { await viewModel.loadMoreIfNeeded(current: video, hidingKnownPortraitVideos: hides) }
        }
    }
}

/// 标签栏「下滑收起」要知道页面的主滚动视图。推荐页外面没有导航栈替它登记，
/// 放进窗口时由列表自己登记给所在的视图控制器。
private final class HomePinnedFeedCollectionView: UICollectionView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                if controller.contentScrollView(for: .bottom) !== self {
                    controller.setContentScrollView(self)
                }
                return
            }
            responder = current.next
        }
    }
}
