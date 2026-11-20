#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// 收藏夹通栏列表。视图本身就是滚动视图，标题栏才能像首页一样跟着下滑收起。
/// 安全区由外层量好后写进内容边距，不再让系统重复叠加。
struct FavoriteFolderList: UIViewRepresentable {
    var folders: [FavFolder]
    var contentOpacity: Double
    /// 收藏页的卡片退出开关。删除和撤销时后面的行补位；关掉或减弱动态效果时直接重排。
    var animatesRemoval: Bool
    var safeInsets: EdgeInsets
    var onOpen: (FavFolder) -> Void
    var onDelete: (FavFolder) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .systemBackground
        let coordinator = context.coordinator
        configuration.itemSeparatorHandler = { [weak coordinator] indexPath, separator in
            coordinator?.separator(at: indexPath, base: separator) ?? separator
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: RemovalFillLayout(list: configuration))
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        // 内容和滚动条边距使用外层量出的安全区，关闭 UIKit 的再次叠加。
        view.contentInsetAdjustmentBehavior = .never
        view.automaticallyAdjustsScrollIndicatorInsets = false
        view.topEdgeEffect.isHidden = false
        view.bottomEdgeEffect.isHidden = true
        view.delegate = coordinator
        coordinator.attach(view)
        applyInsets(to: view)
        coordinator.update(
            folders: folders,
            contentOpacity: contentOpacity,
            onOpen: onOpen,
            onDelete: onDelete,
            environment: context.environment,
            animatesRemoval: animatesRemoval
        )
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        applyInsets(to: view)
        context.coordinator.update(
            folders: folders,
            contentOpacity: contentOpacity,
            onOpen: onOpen,
            onDelete: onDelete,
            environment: context.environment,
            animatesRemoval: animatesRemoval
        )
    }

    /// 安全区量出来之前列表可能已停在顶部；边距变了要把它一并移到新的顶部，避免第一行被标题栏挡住。
    private func applyInsets(to view: UICollectionView) {
        let inset = UIEdgeInsets(top: safeInsets.top, left: 0, bottom: safeInsets.bottom, right: 0)
        guard view.contentInset != inset else { return }
        let wasAtTop = view.contentOffset.y <= -view.adjustedContentInset.top + 1
        view.contentInset = inset
        view.verticalScrollIndicatorInsets = inset
        if wasAtTop {
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        private var dataSource: UICollectionViewDiffableDataSource<Int, Int>?
        private var foldersByID: [Int: FavFolder] = [:]
        private var applied: [FavFolder] = []
        private var hasApplied = false
        private var environment = EnvironmentValues()
        private var configuredColorScheme: ColorScheme?
        private var configuredDynamicTypeSize: DynamicTypeSize?
        private var configuredLocale: Locale?
        private var contentOpacity: CGFloat = 1
        private var onOpen: (FavFolder) -> Void = { _ in }
        private var onDelete: (FavFolder) -> Void = { _ in }
        private weak var collectionView: UICollectionView?
        /// 分隔线回调不在主演员隔离里，只读这个数量。
        private nonisolated(unsafe) var itemCount = 0

        func attach(_ collectionView: UICollectionView) {
            self.collectionView = collectionView
            let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { [weak self] cell, _, id in
                self?.configure(cell, id: id)
            }
            dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
                collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
            }
        }

        func update(
            folders: [FavFolder],
            contentOpacity: Double,
            onOpen: @escaping (FavFolder) -> Void,
            onDelete: @escaping (FavFolder) -> Void,
            environment: EnvironmentValues,
            animatesRemoval: Bool
        ) {
            self.environment = environment
            self.onOpen = onOpen
            self.onDelete = onDelete
            collectionView?.isUserInteractionEnabled = contentOpacity > 0.99
            let opacity = CGFloat(contentOpacity)
            if self.contentOpacity != opacity {
                self.contentOpacity = opacity
                applyOpacityToVisibleCells()
            }
            let appearanceChanged = configuredColorScheme != environment.colorScheme
                || configuredDynamicTypeSize != environment.dynamicTypeSize
                || configuredLocale != environment.locale
            configuredColorScheme = environment.colorScheme
            configuredDynamicTypeSize = environment.dynamicTypeSize
            configuredLocale = environment.locale
            guard folders != applied || appearanceChanged else { return }
            let previousIDs = applied.map(\.id)
            let previous = Dictionary(applied.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            applied = folders
            itemCount = folders.count
            foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard let dataSource else { return }
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            snapshot.appendItems(folders.map(\.id))
            // 只重新配置已经在列表里的行。新插入的行由单元格注册自己配置。
            let changed = folders.compactMap { folder -> Int? in
                guard let old = previous[folder.id] else { return nil }
                return appearanceChanged || old != folder ? folder.id : nil
            }
            if hasApplied, !changed.isEmpty { snapshot.reconfigureItems(changed) }
            let currentIDs = folders.map(\.id)
            let removal = RemovalFill.isRemovalOnly(previousIDs, currentIDs)
            let insertion = RemovalFill.isOrderPreservingInsertion(previousIDs, currentIDs)
            if hasApplied, animatesRemoval, removal || insertion,
               let layout = collectionView?.collectionViewLayout as? RemovalFillLayout {
                layout.shrinksDeletedItems = removal
                RemovalFill.perform {
                    dataSource.apply(snapshot, animatingDifferences: true)
                } completion: { _ in
                    layout.shrinksDeletedItems = false
                }
            } else {
                dataSource.apply(snapshot, animatingDifferences: false)
            }
            hasApplied = true
        }

        nonisolated func separator(at indexPath: IndexPath, base: UIListSeparatorConfiguration) -> UIListSeparatorConfiguration {
            var separator = base
            separator.topSeparatorVisibility = .hidden
            separator.bottomSeparatorVisibility = indexPath.item == itemCount - 1 ? .hidden : .visible
            separator.bottomSeparatorInsets = NSDirectionalEdgeInsets(top: 0, leading: FavoriteFolderListMetrics.separatorLeading, bottom: 0, trailing: 20)
            return separator
        }

        private func configure(_ cell: UICollectionViewListCell, id: Int) {
            guard let folder = foldersByID[id] else { return }
            let environment = environment
            cell.contentConfiguration = UIHostingConfiguration {
                FavoriteFolderRow(folder: folder)
                    .environment(\.self, environment)
            }
            .margins(.leading, 20)
            .margins(.trailing, 8)
            .margins(.vertical, 0)
            .minSize(height: FavoriteFolderListMetrics.rowHeight)
            cell.accessories = [.disclosureIndicator()]
            cell.contentView.alpha = contentOpacity
            cell.accessibilityTraits = .button
        }

        private func applyOpacityToVisibleCells() {
            guard let collectionView else { return }
            for indexPath in collectionView.indexPathsForVisibleItems {
                collectionView.cellForItem(at: indexPath)?.contentView.alpha = contentOpacity
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)
            guard let id = dataSource?.itemIdentifier(for: indexPath), let folder = foldersByID[id] else { return }
            onOpen(folder)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard indexPaths.count == 1, let indexPath = indexPaths.first,
                  let id = dataSource?.itemIdentifier(for: indexPath),
                  let folder = foldersByID[id], !folder.isDefaultFolder else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [onDelete] _ in
                UIMenu(children: [
                    UIAction(title: String(localized: "删除收藏夹"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                        onDelete(folder)
                    }
                ])
            }
        }
    }
}

private enum FavoriteFolderListMetrics {
    static let rowHeight: CGFloat = 80
    static let separatorLeading: CGFloat = 20 + 64 + 12
}

/// 播放列表式的一行：64pt 封面或文件夹图标，标题和内容数量。
private struct FavoriteFolderRow: View {
    let folder: FavFolder

    var body: some View {
        HStack(spacing: 12) {
            cover
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                    .font(.app(.callout))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(String(localized: "\(folder.mediaCount) 个内容"))
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 80, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var cover: some View {
        if let url = folder.secureCoverURL {
            BiliImage(url: url, targetSize: CGSize(width: 64, height: 64))
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.orange.opacity(0.16)
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
