#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// 评论列表的集合视图容器。行由 `UIHostingConfiguration` 宿主，随滚动复用；
/// 只有值快照变化的行会重新配置。滚动位置、折叠距离、分页与下拉刷新都在这里衔接。
struct CommentCollectionView: UIViewRepresentable {
    let viewModel: CommentsViewModel
    /// 父级一次求值得到的行快照；用于比较变化并配置单元格内容。
    let rows: [CommentRowModel]
    let scrollRevision: Int
    var initialOffset: CGFloat = 0
    var onOffsetChanged: ((CGFloat) -> Void)? = nil
    var collapseConsume: ((CGFloat) -> CGFloat)? = nil
    var collapseEnd: (() -> Void)? = nil
    var canCollapse: ((CGFloat) -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(worker: self) }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let layout = UICollectionViewCompositionalLayout { [weak coordinator] _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                              heightDimension: .estimated(220))
            let item = NSCollectionLayoutItem(layoutSize: size)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            // 顶部预留放在内容里，而不是滚动视图的 contentInset：
            // 折叠观察器据此按「内容偏移 == 视频折叠距离」平移列表。
            section.contentInsets = NSDirectionalEdgeInsets(top: coordinator?.reservation ?? 0,
                                                            leading: 0, bottom: 0, trailing: 0)
            return section
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.selfSizingInvalidation = .enabledIncludingConstraints
        view.automaticallyAdjustsScrollIndicatorInsets = false
        view.delegate = coordinator
        view.prefetchDataSource = coordinator
        coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.update(worker: self, environment: context.environment)
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.detach()
    }

    enum ItemID: Hashable {
        case header
        case comment(Int)
        case footer
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        private var worker: CommentCollectionView
        private weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<Int, ItemID>?
        private var rowsByID: [Int: CommentRowModel] = [:]
        private var environment = EnvironmentValues()
        private var actions: CommentRowActions?
        private var lastScrollRevision = 0
        private var restoredOffset = false
        private var prefetches: [ItemID: Task<Void, Never>] = [:]
        var reservation: CGFloat = 0
        private var minimumContentHeight: CGFloat = 0
        let collapse = PausedVideoCollapseScroll.Observer()
        private lazy var refreshControl: UIRefreshControl = {
            let control = UIRefreshControl()
            control.addTarget(self, action: #selector(refreshPulled(_:)), for: .valueChanged)
            return control
        }()

        init(worker: CommentCollectionView) {
            self.worker = worker
        }

        func attach(_ view: UICollectionView) {
            collectionView = view
            view.refreshControl = refreshControl
            view.addSubview(collapse)
            collapse.isUserInteractionEnabled = false
            actions = CommentRowActions(viewModel: worker.viewModel)
            let registration = UICollectionView.CellRegistration<UICollectionViewCell, ItemID> { [weak self] cell, _, id in
                self?.configure(cell, id: id)
            }
            dataSource = UICollectionViewDiffableDataSource(collectionView: view) { view, indexPath, id in
                view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
        }

        func detach() {
            prefetches.values.forEach { $0.cancel() }
            prefetches.removeAll()
            collapse.detach()
        }

        func update(worker: CommentCollectionView, environment: EnvironmentValues) {
            self.worker = worker
            self.environment = environment
            actions = CommentRowActions(viewModel: worker.viewModel)
            let geometry = environment.videoScrollContext
            minimumContentHeight = geometry?.minimumContentHeight ?? 0
            let nextReservation = geometry?.reservation ?? 0
            if nextReservation != reservation {
                reservation = nextReservation
                collectionView?.collectionViewLayout.invalidateLayout()
            }
            apply(rows: worker.rows)
            updateMinimumHeightInset()
            configureCollapse()
            guard let collectionView else { return }
            if worker.scrollRevision != lastScrollRevision {
                lastScrollRevision = worker.scrollRevision
                collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top),
                                                animated: false)
            }
        }

        private func apply(rows: [CommentRowModel]) {
            guard let dataSource else { return }
            var newByID: [Int: CommentRowModel] = [:]
            newByID.reserveCapacity(rows.count)
            var ids: [ItemID] = [.header]
            ids.reserveCapacity(rows.count + 2)
            var changed: [ItemID] = []
            for row in rows {
                newByID[row.comment.id] = row
                ids.append(.comment(row.comment.id))
                if rowsByID[row.comment.id] != row { changed.append(.comment(row.comment.id)) }
            }
            ids.append(.footer)
            let previousIDs = Set(rowsByID.keys)
            rowsByID = newByID

            var snapshot = NSDiffableDataSourceSnapshot<Int, ItemID>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids, toSection: 0)
            // 新出现的行由 cell 配置自然补齐；已有行只有快照变化时才重新配置。
            let reconfigure = changed.filter { previousIDs.contains(reconfigureID($0)) }
            if !reconfigure.isEmpty { snapshot.reconfigureItems(reconfigure) }
            dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                self?.updateMinimumHeightInset()
            }

            if !restoredOffset, !rows.isEmpty {
                restoredOffset = true
                let offset = worker.initialOffset
                guard offset > 0 else { return }
                // 首次内容布局完成后再恢复，避免内容高度还是估算值时被限位。
                DispatchQueue.main.async { [weak self] in
                    guard let view = self?.collectionView else { return }
                    view.layoutIfNeeded()
                    view.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                }
            }
        }

        private func reconfigureID(_ id: ItemID) -> Int {
            switch id {
            case .comment(let id): return id
            default: return -1
            }
        }

        private func configureCollapse() {
            collapse.consume = worker.collapseConsume
            collapse.end = { [weak self] in self?.worker.collapseEnd?() }
            collapse.canConsume = { [weak self] distance in self?.worker.canCollapse?(distance) ?? false }
            collapse.configure(environment.videoScrollContext, page: .comments, ownsInsets: false)
            collapse.attach()
        }

        /// 评论区不足一屏时仍能完整收起头部：把差额补到内容底部。
        private func updateMinimumHeightInset() {
            guard let view = collectionView else { return }
            let needed = max(0, minimumContentHeight - view.contentSize.height)
            if abs(view.contentInset.bottom - needed) > 0.5 {
                view.contentInset.bottom = needed
            }
        }

        private func configure(_ cell: UICollectionViewCell, id: ItemID) {
            cell.contentConfiguration = UIHostingConfiguration {
                content(for: id)
                    .environment(\.self, environment)
            }
            .margins(.all, 0)
            .minSize(height: 0)
        }

        @ViewBuilder
        private func content(for id: ItemID) -> some View {
            switch id {
            case .header:
                CommentSortHeader(viewModel: worker.viewModel)
            case .comment(let commentID):
                if let model = rowsByID[commentID], let actions {
                    CommentRow(model: model, actions: actions)
                        .equatable()
                        .padding(.horizontal, CommentLayout.pageHorizontalInset)
                        .padding(.vertical, CommentLayout.rowVerticalPadding)
                }
            case .footer:
                CommentListFooter(viewModel: worker.viewModel)
            }
        }

        // MARK: 下拉刷新

        @objc private func refreshPulled(_ control: UIRefreshControl) {
            let viewModel = worker.viewModel
            Task {
                await viewModel.refresh()
                control.endRefreshing()
            }
        }

        // MARK: 滚动

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateMinimumHeightInset()
            worker.onOffsetChanged?(scrollView.contentOffset.y)
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                            forItemAt indexPath: IndexPath) {
            updateMinimumHeightInset()
            guard let id = dataSource?.itemIdentifier(for: indexPath),
                  case .comment(let commentID) = id,
                  let comment = worker.viewModel.comments.first(where: { $0.id == commentID }) else { return }
            let viewModel = worker.viewModel
            guard viewModel.comments.suffix(5).contains(where: { $0.id == commentID }) else { return }
            Task { await viewModel.loadMoreIfNeeded(current: comment) }
        }

        // MARK: 预取

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let scale = collectionView.traitCollection.displayScale
            let pipeline = environment.imagePipeline
            let emoteStore = environment.commentEmoteStore
            for indexPath in indexPaths {
                guard let id = dataSource?.itemIdentifier(for: indexPath),
                      case .comment(let commentID) = id,
                      prefetches[id] == nil,
                      let comment = worker.viewModel.comments.first(where: { $0.id == commentID }) else { continue }
                if let task = BiliImageLoader.prefetch(comment.member.secureAvatarURL,
                                                       pointSize: CGSize(width: CommentLayout.avatarSize,
                                                                         height: CommentLayout.avatarSize),
                                                       scale: scale, pipeline: pipeline) {
                    prefetches[id] = task
                }
                if !comment.emotes.isEmpty {
                    Task { await emoteStore.preload(Array(comment.emotes.values)) }
                }
            }
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            for indexPath in indexPaths {
                guard let id = dataSource?.itemIdentifier(for: indexPath) else { continue }
                prefetches.removeValue(forKey: id)?.cancel()
            }
        }
    }
}
