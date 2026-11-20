import SwiftUI

/// Shared selection controls, visible only while selecting library items.
struct LibrarySelectionBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let count: Int
    let isBusy: Bool
    var done: () -> Void
    var remove: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("已选择 \(count) 项").font(.app(.subheadline)).foregroundStyle(.secondary)
                Spacer()
                if isBusy { ProgressView() }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button(action: done) {
                    Text("完成").font(.app(.headline)).frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityIdentifier("library.selection.done")
                Button(role: .destructive, action: remove) {
                    Label("移出所选", systemImage: "trash")
                        .font(.app(.headline)).frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .disabled(count == 0 || isBusy)
                .accessibilityIdentifier("library.selection.remove")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
