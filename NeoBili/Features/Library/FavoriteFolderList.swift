#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 参考 Apple Music 资料库的极简原生列表：无封面、纯系统底色与细分隔线，
/// 长按非默认收藏夹支持编辑与删除，页面内直接提供新建收藏夹入口。
struct FavoriteFolderList: View {
    let folders: [FavFolder]
    let animatesChanges: Bool
    let onRefresh: () async -> Void
    let onCreate: () -> Void
    let onEdit: (FavFolder) -> Void
    let onDelete: (FavFolder) -> Void

    var body: some View {
        List {
            ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                folderRow(folder, isFirst: index == 0)
            }
            createRow
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .animation(animatesChanges ? RemovalFill.animation : nil, value: folders.map(\.id))
        .refreshable {
            await onRefresh()
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: FavFolder, isFirst: Bool) -> some View {
        let link = NavigationLink(value: folder) {
            HStack(spacing: FavoriteFolderRowMetrics.iconSpacing) {
                Image(systemName: folder.isDefaultFolder ? "star" : "folder")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: FavoriteFolderRowMetrics.iconWidth, alignment: .center)

                Text(folder.title)
                    .font(.app(.title3))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if folder.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("私密")
                }

                Spacer(minLength: 8)

                Text("\(folder.mediaCount)")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color(uiColor: .systemBackground))
        .listRowSeparator(isFirst ? .hidden : .visible, edges: .top)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + FavoriteFolderRowMetrics.separatorLeading
        }

        if folder.isDefaultFolder {
            link
        } else {
            link.contextMenu {
                Button("编辑收藏夹", systemImage: "pencil") { onEdit(folder) }
                Button("删除收藏夹", systemImage: "trash", role: .destructive) { onDelete(folder) }
            }
        }
    }

    private var createRow: some View {
        Button(action: onCreate) {
            HStack(spacing: FavoriteFolderRowMetrics.iconSpacing) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: FavoriteFolderRowMetrics.iconWidth, alignment: .center)

                Text("新建收藏夹")
                    .font(.app(.title3))
                    .foregroundStyle(.tint)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .listRowBackground(Color(uiColor: .systemBackground))
        .listRowSeparator(folders.isEmpty ? .hidden : .visible, edges: .top)
        .listRowSeparator(.hidden, edges: .bottom)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + FavoriteFolderRowMetrics.separatorLeading
        }
        .accessibilityIdentifier("favorites.create")
    }
}

private enum FavoriteFolderRowMetrics {
    static let iconWidth: CGFloat = 28
    static let iconSpacing: CGFloat = 14
    static let separatorLeading: CGFloat = iconWidth + iconSpacing
}
