import NeoBiliDomain
import SwiftUI
import UIKit

/// 推荐列表由 UICollectionView 承载，每张卡独占原生 cell 和 SwiftUI 宿主，
/// 隔离系统 zoom 对来源宿主的变换。普通卡双列排列，大卡和分隔条跨两列。
struct HomeFeedCollection: UIViewRepresentable {
    let rows: [HomeFeedRow]
    let viewModel: HomeViewModel
    let hidesPortraitVideos: Bool
    let isRefreshing: Bool
    /// 刷新淡出期间列表不接收触摸。
    let isInteractionEnabled: Bool
    var exposureEnabled: Bool = false
    var inlinePlaybackEnabled: Bool = false
    let refreshDistance: Double
    let controller: HomeFeedScrollController
    let onRefresh: () -> Void
    let onOpenLastSeen: () -> Void
    /// 列表忽略安全区铺满全屏，状态栏（+ 固定标题栏）和标签栏的高度由外层量好传入。
    var safeInsets = EdgeInsets()
    /// 切换标签时卡片的淡入进度。只作用在格子内容上，列表本身保持不透明。
    var contentOpacity: Double = 1
    /// 移除卡片（不感兴趣、点踩、拉黑）时，后面的卡片挪过来补位的动画时长；nil 表示不做动画
    /// （卡片动画关闭或系统开启了「减弱动态效果」）。
    var removalAnimationDuration: Double? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = HomeCardLayout.rowSpacing
        let layout = HomeFeedLayout(sectionProvider: { [weak coordinator] index, environment in
            coordinator?.layoutSection(at: index, environment: environment)
        }, configuration: configuration)

        let view = HomeFeedCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
        view.alwaysBounceVertical = true
        view.showsHorizontalScrollIndicator = false
        // 内容和滚动条边距统一使用外层量出的 safeInsets，关闭 UIKit 的安全区叠加。
        view.contentInsetAdjustmentBehavior = .never
        view.automaticallyAdjustsScrollIndicatorInsets = false
        applyInsets(to: view)
        // 顶部沿用系统默认的 scroll edge effect，与历史、收藏等原生列表一致；底部不加。
        view.topEdgeEffect.isHidden = false
        view.bottomEdgeEffect.isHidden = true
        view.delegate = coordinator
        view.prefetchDataSource = coordinator
        coordinator.attach(view)
        view.onWindowChanged = { [weak coordinator] in coordinator?.updateExposure() }
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
        coordinator.exposureEnabled = exposureEnabled
        coordinator.inlinePlaybackEnabled = inlinePlaybackEnabled
        coordinator.removalAnimationDuration = removalAnimationDuration
        applyInsets(to: view)
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
        coordinator.scheduleExposureUpdate()
    }

    private func applyInsets(to view: UICollectionView) {
        let inset = UIEdgeInsets(top: safeInsets.top + HomeCardLayout.verticalInset, left: 0,
                                 bottom: safeInsets.bottom + HomeCardLayout.verticalInset, right: 0)
        guard view.contentInset != inset else { return }
        // 安全区量出来之前列表可能已按旧边距停在顶部；边距变了要把它一并移到新的顶部，
        // 否则第一排卡片会被状态栏或标题栏挡住。
        let wasAtTop = view.contentOffset.y <= -view.adjustedContentInset.top + 1
        view.contentInset = inset
        view.verticalScrollIndicatorInsets = UIEdgeInsets(top: safeInsets.top, left: 0, bottom: safeInsets.bottom, right: 0)
        if wasAtTop {
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: false)
        }
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.pull.detach()
        coordinator.cancelImagePrefetches()
        coordinator.exposureEnabled = false
        coordinator.inlinePlaybackEnabled = false
        coordinator.updateExposure()
        #if PERFORMANCE_DEMO
        coordinator.scrollProbe.stop()
        #endif
    }

    enum Section: Hashable {
        /// 连续的普通卡共用一节；全宽大卡单独成节。首张卡提供稳定标识。
        case cards(String)
        /// 「上次看到这里」独立成节，高度由 HomeCardLayout 按文字与字号计算。
        case marker
    }

    /// 格子里的 SwiftUI 内容和列表所在的视图树不相连，App 级的依赖要显式带过去。
    fileprivate struct CellEnvironment {
        var nowPlaying: NowPlayingStore?
        var account: AccountStore?
        var feedback: ActionFeedback?
        var namespace: Namespace.ID?
        var animationSource: VideoCardAnimationSource?
        var animationOverrides = VideoCardAnimationOverrides()
        var services: ApplicationServices = .live
        var imagePipeline: BiliImagePipeline = .live
        var hidesPortraitVideos = false

        /// 格子的环境快照；账号、外观、过滤或依赖变化时重新配置已显示格子。
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
        var exposureEnabled = false
        var inlinePlaybackEnabled = false {
            didSet {
                // A pending dwell can expire before the next visibility sample.
                if oldValue && !inlinePlaybackEnabled { preview.stop() }
            }
        }
        let preview = HomeInlinePreview()
        private let exposure = RecommendationExposureTracker()
        let state = HomeFeedCellState()
        let pull = ShortPullRefresh.ObserverView()
        #if PERFORMANCE_DEMO
        let scrollProbe = FeedScrollProbe()
        #endif

        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Section, String>?
        private var itemsByID: [String: HomeFeedItem] = [:]
        // Retain the value-semantic input so unrelated page updates can skip
        // flattening, deduplication, dictionary construction and snapshot reads.
        private var appliedRows: [HomeFeedRow]?
        #if NEOBILI_REGRESSION
        private(set) var rowPreparationCount = 0
        #endif
        private var latestIDs: [String] = []
        private var earlierIDs: [String] = []
        private var hasMarker = false
        /// Layout callbacks must not materialize a diffable snapshot per section.
        private var largeSections: Set<Section> = []
        private var paginationTriggerIDs: Set<String> = []
        private var environment = CellEnvironment()
        private var needsReconfigureAll = false
        /// 推荐页的入场时钟。格子不直接观察它（见 `TimedFeedEntrance`），由这里监听后
        /// 把起点推给格子。
        private weak var clock: VideoEntranceClock?
        /// 每一行配置时拿到的入场起点，用来判断哪些行需要重新配置。
        private var configuredStarts: [String: [TimeInterval?]] = [:]
        private let imagePrefetcher = HomeFeedImagePrefetcher()
        /// App 的文字档位，决定标题预排版用的字号。
        private var dynamicTypeSize: DynamicTypeSize = .large
        var removalAnimationDuration: Double?
        /// 滚动回调里的曝光与内联预览采样按固定间隔合并；滚动停止时再补一次最终位置。
        private var lastObservationSample: CFTimeInterval = 0
        private var pendingObservationSample: Task<Void, Never>?
        private static let observationInterval: CFTimeInterval = 0.1
        #if NEOBILI_REGRESSION
        private(set) var observationSampleCount = 0
        #endif

        func attach(_ view: UICollectionView) {
            collectionView = view
            #if PERFORMANCE_DEMO
            scrollProbe.attach(view)
            #endif
            let persistentRegistration = UICollectionView.CellRegistration<PersistentFeedHostingCell, String> { [weak self] cell, _, id in
                self?.configure(cell, id: id)
            }
            #if PERFORMANCE_DEMO
            let usesConfiguration = ProcessInfo.processInfo.arguments.contains("--configuration-feed-hosts")
            let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
                self?.configure(cell, id: id)
            }
            #endif
            dataSource = UICollectionViewDiffableDataSource(collectionView: view) { view, indexPath, id in
                #if PERFORMANCE_DEMO
                if usesConfiguration {
                    return view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
                }
                #endif
                return view.dequeueConfiguredReusableCell(using: persistentRegistration, for: indexPath, item: id)
            }
            view.addSubview(pull)
            view.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: String(localized: "刷新推荐")) { [weak self] _ in
                    self?.onRefresh()
                    return true
                }
            ]
        }

        func layoutSection(at index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
            let sectionID = dataSource?.sectionIdentifier(for: index)
            let isMarker = sectionID == .marker
            let isLarge = sectionID.map(largeSections.contains) ?? false
            let width = environment.container.effectiveContentSize.width
            // 卡片行高度固定（4:3 封面加文字区），不必逐个测量。分隔条的高度也由布局直接给定
            // （见 `HomeCardLayout.lastSeenHeight`）：让格子自己量高度，会在它进出屏幕和安全区时
            // 重新测量，布局反复失效，最终被 UIKit 断言终止。
            let height: NSCollectionLayoutDimension = isMarker
                ? .absolute(HomeCardLayout.lastSeenHeight(for: width, dynamicTypeSize: dynamicTypeSize))
                : .absolute(isLarge ? HomeCardLayout.largeCardHeight(for: width) : HomeCardLayout.cardHeight(for: width))
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height)
            let group: NSCollectionLayoutGroup
            if isMarker || isLarge {
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
                services: values.applicationServices,
                imagePipeline: values.imagePipeline,
                hidesPortraitVideos: hidesPortraitVideos
            )
            if updated.signature != environment.signature { needsReconfigureAll = true }
            environment = updated
            if dynamicTypeSize != values.dynamicTypeSize, hasMarker {
                // 分隔条的高度随字号变化，字号变了要让布局重新取高度。
                collectionView?.collectionViewLayout.invalidateLayout()
            }
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
            guard appliedRows != rows || needsReconfigureAll else { return }
            appliedRows = rows
            #if NEOBILI_REGRESSION
            rowPreparationCount += 1
            #endif
            let items = HomeFeedRow.collectionItems(rows)
            var seen = Set<String>()
            var byID: [String: HomeFeedItem] = [:]
            var latest: [String] = []
            var earlier: [String] = []
            var marker = false
            var orderedItems: [HomeFeedItem] = []
            for row in items where seen.insert(row.id).inserted {
                orderedItems.append(row)
                byID[row.id] = row
            }
            // Deduplication can leave another half row. Use the packed order for
            // the snapshot, refresh boundary, removal comparison and pagination.
            let packedRows = HomeFeedRow.group(orderedItems)
            for row in HomeFeedRow.collectionItems(packedRows) {
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
            // 只是移除了几张卡（其余卡片、分隔条都还在，先后顺序不变）时，才用补位动画；
            // 翻页、刷新、设置变化仍然直接套用，不引入额外的动画。
            let previous = latestIDs + earlierIDs
            let current = latest + earlier
            let isRemovalOnly = RemovalFill.isRemovalOnly(previous, current) && marker == hasMarker
                && changed.isEmpty && !needsReconfigureAll
            // 没有变化时直接返回：刷新淡出、滚动开关这些状态也会触发这里。
            guard structureChanged || !changed.isEmpty || needsReconfigureAll else { return }
            // Index paths can point at different cards after refresh/removal.
            // Their old prefetch handles must not survive the snapshot change.
            cancelImagePrefetches()

            // 只有原本就在列表里的行需要重配；新插入的行出现时自然会配置。
            let existing = Set(itemsByID.keys)
            // 按显示顺序后台预排标题，优先准备即将可见的卡片。
            let changedIDs = Set(changed)
            prepareTitles(for: items.filter { !existing.contains($0.id) || changedIDs.contains($0.id) })
            itemsByID = byID
            configuredStarts = configuredStarts.filter { byID[$0.key] != nil }
            latestIDs = latest
            earlierIDs = earlier
            hasMarker = marker
            paginationTriggerIDs = Set(current.suffix(6))

            var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
            var updatedLargeSections: Set<Section> = []
            var normalIDs: [String] = []
            func appendNormalSection() {
                guard let first = normalIDs.first else { return }
                let section = Section.cards(first)
                snapshot.appendSections([section])
                snapshot.appendItems(normalIDs, toSection: section)
                normalIDs.removeAll(keepingCapacity: true)
            }
            for row in packedRows {
                switch row {
                case .lastSeen:
                    appendNormalSection()
                    snapshot.appendSections([.marker])
                    snapshot.appendItems([HomeFeedItem.lastSeen.id], toSection: .marker)
                case .videos(let videos):
                    let ids = videos.map { HomeFeedItem.video($0).id }
                    if videos[0].isLargeRecommendationCard {
                        appendNormalSection()
                        let section = Section.cards(ids[0])
                        updatedLargeSections.insert(section)
                        snapshot.appendSections([section])
                        snapshot.appendItems(ids, toSection: section)
                    } else {
                        normalIDs.append(contentsOf: ids)
                    }
                }
            }
            appendNormalSection()
            let layoutKindsChanged = largeSections != updatedLargeSections
            largeSections = updatedLargeSections
            if needsReconfigureAll {
                snapshot.reconfigureItems(snapshot.itemIdentifiers.filter(existing.contains))
            } else if !changed.isEmpty {
                // 同一行里换了视频（例如「不感兴趣」换一条）只重配这一行。
                snapshot.reconfigureItems(changed)
            }
            needsReconfigureAll = false
            if isRemovalOnly, removalAnimationDuration != nil,
               let collectionView, let layout = collectionView.collectionViewLayout as? HomeFeedLayout {
                // 被移除的卡缩小淡出，后面的卡用略带回弹的曲线移到新位置。
                layout.shrinksDeletedItems = true
                RemovalFill.perform {
                    dataSource.apply(snapshot, animatingDifferences: true)
                } completion: { _ in
                    layout.shrinksDeletedItems = false
                }
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)
                if layoutKindsChanged { collectionView?.collectionViewLayout.invalidateLayout() }
            }
        }

        private static func sameContent(_ lhs: HomeFeedItem, _ rhs: HomeFeedItem) -> Bool {
            switch (lhs, rhs) {
            case (.video(let a), .video(let b)): a == b
            case (.lastSeen, .lastSeen): true
            default: false
            }
        }

        private func configure(_ cell: UICollectionViewCell, id: String) {
            let environment = environment
            guard let row = itemsByID[id], let viewModel else { return }
            let starts = entranceStarts(for: row)
            configuredStarts[id] = starts
            let content = HomeFeedCellView(
                    item: row,
                    viewModel: viewModel,
                    state: state,
                    entranceStart: starts.first ?? nil,
                    onOpenLastSeen: { [weak self] in self?.onOpenLastSeen() }, preview: preview
                )
                .environment(environment.nowPlaying)
                .environment(environment.account)
                .environment(environment.feedback)
                .environment(\.videoTransitionNamespace, environment.namespace)
                .environment(\.videoCardAnimationSource, environment.animationSource)
                .environment(\.videoCardAnimationOverrides, environment.animationOverrides)
                .environment(\.hidesPortraitVideos, environment.hidesPortraitVideos)
                .environment(\.imagePipeline, environment.imagePipeline)
                .environment(\.applicationServices, environment.services)
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
            let fontSize = PreparedTitle.fontSize(for: dynamicTypeSize)
            let scale = collectionView.traitCollection.displayScale
            for row in rows {
                guard case .video(let video) = row else { continue }
                let width = video.isLargeRecommendationCard
                    ? max(0, collectionView.bounds.width - HomeCardLayout.horizontalInset * 2 - HomeCardLayout.detailsHorizontalPadding * 2)
                    : HomeCardLayout.titleWidth(for: collectionView.bounds.width)
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
            prepareTitles(for: indexPaths.compactMap { dataSource.itemIdentifier(for: $0).flatMap { itemsByID[$0] } })
            for indexPath in indexPaths {
                guard let id = dataSource.itemIdentifier(for: indexPath),
                      case .video(let video)? = itemsByID[id] else { continue }
                imagePrefetcher.prefetch(indexPath: indexPath, video: video,
                    width: collectionView.bounds.width, scale: scale, pipeline: environment.imagePipeline)
            }
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            imagePrefetcher.cancel(indexPaths: indexPaths)
        }

        func cancelImagePrefetches() { imagePrefetcher.cancelAll() }

        // MARK: 切换淡入

        func applyContentOpacityToVisibleCells() {
            collectionView?.visibleCells.forEach { applyContentOpacity(to: $0) }
        }

        private func applyContentOpacity(to cell: UICollectionViewCell) {
            if cell.contentView.alpha != contentOpacity { cell.contentView.alpha = contentOpacity }
        }

        // MARK: UICollectionViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if CACurrentMediaTime() - lastObservationSample >= Self.observationInterval {
                updateExposure()
            } else {
                scheduleExposureUpdate()
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { updateExposure() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateExposure()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateExposure()
        }

        func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
            scrollViewDidScroll(scrollView)
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            scheduleExposureUpdate()
            // Keep the prefetch consumer cancellable until this cell leaves.
            // Key visible handles by cell identity: a snapshot may reuse the
            // old index path for a different card before didEndDisplaying.
            imagePrefetcher.willDisplay(cellID: ObjectIdentifier(cell), indexPath: indexPath)
            applyContentOpacity(to: cell)
            // 提前准备好的格子可能错过了重新配置：显示前核对一次入场起点。
            if let id = dataSource?.itemIdentifier(for: indexPath), let row = itemsByID[id],
               configuredStarts[id] != entranceStarts(for: row) {
                configure(cell, id: id)
            }
            // 显示到最后几行时翻页；是否真的需要加载仍由 ViewModel 按末尾可见视频判断。
            guard let dataSource, let viewModel,
                  let id = dataSource.itemIdentifier(for: indexPath),
                  case .video(let video)? = itemsByID[id] else { return }
            guard paginationTriggerIDs.contains(id) else { return }
            let hides = hidesPortraitVideos
            Task { await viewModel.loadMoreIfNeeded(current: video, hidingKnownPortraitVideos: hides) }
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            imagePrefetcher.didEndDisplaying(cellID: ObjectIdentifier(cell))
            scheduleExposureUpdate()
        }

        func scheduleExposureUpdate() {
            guard pendingObservationSample == nil else { return }
            let delay = max(0, Self.observationInterval - (CACurrentMediaTime() - lastObservationSample))
            // Cell callbacks can precede UIKit's visible-item update. Sample after layout yields.
            pendingObservationSample = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, let self else { return }
                pendingObservationSample = nil
                updateExposure()
            }
        }

        func updateExposure() {
            pendingObservationSample?.cancel()
            pendingObservationSample = nil
            lastObservationSample = CACurrentMediaTime()
            #if NEOBILI_REGRESSION
            observationSampleCount += 1
            #endif
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            updateInlinePreview()
            guard exposureEnabled, contentOpacity > 0.99, let collectionView,
                  collectionView.window != nil, let dataSource else {
                exposure.update([], timestamp: timestamp); return
            }
            var viewport = collectionView.bounds
            viewport.origin.y += collectionView.adjustedContentInset.top
            viewport.size.height = max(0, viewport.height - collectionView.adjustedContentInset.top - collectionView.adjustedContentInset.bottom)
            let cards: [RecommendationExposureTracker.Card] = collectionView.indexPathsForVisibleItems.compactMap { index in
                guard let id = dataSource.itemIdentifier(for: index), case .video(let video)? = itemsByID[id],
                      video.playbackEntry.source == .recommendation,
                      let position = video.recommendationPosition,
                      let cell = collectionView.cellForItem(at: index), !cell.isHidden, cell.alpha > 0,
                      cell.frame.height > 0, cell.frame.width > 0 else { return nil }
                let intersection = viewport.intersection(cell.frame)
                guard !intersection.isNull, !intersection.isEmpty else { return nil }
                let ratio = Double((intersection.width / cell.frame.width) * (intersection.height / cell.frame.height))
                return .init(video: video, position: position, visibleRatio: ratio)
            }
            exposure.update(cards, timestamp: timestamp, policy: viewModel?.exposurePolicy ?? .init())
        }

        private func updateInlinePreview() {
            guard inlinePlaybackEnabled, let collectionView, collectionView.window != nil, let dataSource else {
                preview.stop(); return
            }
            var viewport = collectionView.bounds
            viewport.origin.y += collectionView.adjustedContentInset.top
            viewport.size.height = max(0, viewport.height - collectionView.adjustedContentInset.top - collectionView.adjustedContentInset.bottom)
            let candidates = collectionView.indexPathsForVisibleItems.sorted().compactMap { index -> VideoSummary? in
                guard let id = dataSource.itemIdentifier(for: index), case .video(let video)? = itemsByID[id],
                      video.isLargeRecommendationCard, let cell = collectionView.cellForItem(at: index),
                      cell.frame.height > 0, viewport.intersection(cell.frame).height >= min(cell.frame.height,viewport.height) * 0.8 else { return nil }
                return video
            }
            if let video = candidates.first { preview.select(video) } else { preview.stop() }
        }
    }
}
