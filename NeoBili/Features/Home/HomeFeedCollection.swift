import SwiftUI
import UIKit

/// 推荐页列表的滚动控制，给标签栏「回顶 / 刷新」和刷新后回顶使用。
@MainActor
final class HomeFeedScrollController {
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

/// 推荐页的双列列表，由 UICollectionView 承载，卡片内容仍是 SwiftUI。
///
/// SwiftUI 的 LazyVStack 每进来一页新数据都要把整个列表重新整理一遍，
/// 卡片也要等进入屏幕的那一帧才现场创建，真机录到最重的掉帧（25–50ms）
/// 都出在翻页那一刻。这里改成 UIKit：翻页只插入新增的行，已在屏幕上的行
/// 不重算；格子会提前准备，滑出屏幕后复用。每张卡独占原生格子和宿主，
/// 避免系统 zoom 对来源宿主施加的变换牵连同排卡片。分隔条仍横跨两列。
struct HomeFeedCollection: UIViewRepresentable {
    let rows: [HomeFeedRow]
    let viewModel: HomeViewModel
    let hidesPortraitVideos: Bool
    let isRefreshing: Bool
    /// 刷新淡出期间列表不接收触摸。
    let isInteractionEnabled: Bool
    let refreshDistance: Double
    let controller: HomeFeedScrollController
    let onRefresh: () -> Void
    let onOpenLastSeen: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = HomeCardLayout.rowSpacing
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak coordinator] index, environment in
            coordinator?.layoutSection(at: index, environment: environment)
        }, configuration: configuration)

        let view = HomeFeedCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
        view.alwaysBounceVertical = true
        view.showsHorizontalScrollIndicator = false
        // 不在导航控制器里时，默认的 .automatic 只在「能滚动」时才把安全区算进边距。
        // 刷新淡出期间会暂停滚动，那一刻顶部边距少了状态栏的高度，列表会跳上去，
        // 恢复滚动后位置也回不来。这里始终计入安全区。
        view.contentInsetAdjustmentBehavior = .always
        // 原来 ScrollView 里下拉观察视图和列表之间有 8pt 默认间距，再加列表自身 10pt 留白。
        view.contentInset = UIEdgeInsets(top: HomeCardLayout.verticalInset + 8, left: 0,
                                         bottom: HomeCardLayout.verticalInset, right: 0)
        // 卡片从顶部滑过时给一层渐隐（iOS 26 的 scroll edge effect），底部不加。
        view.topEdgeEffect.style = .soft
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
            let structureChanged = latest != latestIDs || earlier != earlierIDs || marker != hasMarker
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

        // MARK: UICollectionViewDelegate

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
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
private final class HomeFeedCollectionView: UICollectionView {
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

/// 格子共享的页面状态。只有分隔条读它，刷新开始、结束时只有分隔条重算。
@MainActor @Observable
final class HomeFeedCellState {
    private(set) var isRefreshing = false

    func setRefreshing(_ value: Bool) {
        if isRefreshing != value { isRefreshing = value }
    }
}

/// One SwiftUI root per native cell: one video or the full-width marker.
struct HomeFeedCellView: View {
    let item: HomeFeedItem
    let viewModel: HomeViewModel
    let state: HomeFeedCellState
    let entranceStart: TimeInterval?
    let onOpenLastSeen: () -> Void

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed

    var body: some View {
        switch item {
        case .video(let video):
            GeometryReader { geometry in
                videoSlot(video, size: geometry.size)
            }
        case .lastSeen:
            TimedFeedEntrance(start: entranceStart, speed: enterSpeed, reduceMotion: reduceMotion) {
                Button(action: onOpenLastSeen) {
                    LastSeenCard()
                }
                .buttonStyle(.plain)
                .disabled(state.isRefreshing)
            }
        }
    }

    private func videoSlot(_ video: VideoSummary, size: CGSize) -> some View {
        TimedFeedEntrance(start: entranceStart, speed: enterSpeed, reduceMotion: reduceMotion) {
            videoCard(video, size: size)
        }
        .onAppear { viewModel.didShowReplacement(video.bvid) }
        .onChange(of: video.bvid) { viewModel.didShowReplacement(video.bvid) }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    @ViewBuilder
    private func videoCard(_ video: VideoSummary, size: CGSize) -> some View {
        let titleWidth = max(0, size.width - HomeCardLayout.detailsHorizontalPadding * 2)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.replacingIDs.contains(video.bvid))
        } else {
            Button {
                nowPlaying.open(
                    VideoDetailRoute(bvid: video.bvid, cid: video.cid, cover: video.pic,
                                     title: video.title, artist: video.owner.name),
                    from: video.bvid
                )
            } label: {
                Group {
                    #if PERFORMANCE_DEMO
                    if !ProcessInfo.processInfo.arguments.contains("--swiftui-feed-cards") {
                        NativeHomeVideoCard(video: video, titleWidth: titleWidth)
                    } else {
                        HomeVideoCard(video: video, titleWidth: titleWidth)
                    }
                    #else
                    NativeHomeVideoCard(video: video, titleWidth: titleWidth)
                    #endif
                }
                .frame(width: size.width, height: size.height)
                // Both this source and its native hosting cell contain one card.
                .videoTransitionSource(video.bvid, in: videoTransition)
                .contentShape(.interaction, Rectangle())
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
            .task(id: video.bvid) {
                // 快速滑过的卡片不预取：停留一会儿才请求播放地址，
                // 免得一次甩动排进几十个网络请求和解析。
                await VideoPreparationCache.shared.prefetchWhenSettled(bvid: video.bvid, cid: video.cid)
            }
        }
    }
}
