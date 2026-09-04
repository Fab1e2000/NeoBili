import SwiftUI

/// 简介里的分P入口。和合集（`UgcSeasonRow`）同一套显示与交互：
/// 折叠成一行，右侧标「当前第几P / 共几P」，点开弹分P列表。
struct VideoPartsRow: View {
    let parts: [VideoPart]
    /// 当前正在播放的分P序号（从 1 开始）。找不到时不显示序号。
    let currentIndex: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("分P · \(currentPartName)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "list.bullet")
                    .font(.caption)

                Text(progressText)
                    .font(.caption)

                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("分P，\(progressText)，展开分P列表")
    }

    private var currentPartName: String {
        guard let currentIndex, parts.indices.contains(currentIndex - 1) else {
            return "视频分集"
        }
        return parts[currentIndex - 1].part
    }

    private var progressText: String {
        let total = parts.count
        guard let currentIndex else { return "\(total)" }
        return "P\(currentIndex)/\(total)"
    }
}

/// 分P列表弹层。当前这一P高亮并带播放标记，点其它P就地切换，
/// 和合集分集列表（`UgcSeasonSheet`）一个交互。
struct VideoPartsSheet: View {
    let parts: [VideoPart]
    /// 当前播放的分P cid，用来高亮。
    let currentCid: Int?
    let onSelect: (VideoPart) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(parts) { part in
                let isCurrent = part.cid == currentCid
                Button {
                    onSelect(part)
                    dismiss()
                } label: {
                    row(part, isCurrent: isCurrent)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listStyle(.plain)
            // 左缘触控死区：防止边缘误触直接切了分P。
            .leftEdgeTapDeadZone()
            .navigationTitle("分P")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ part: VideoPart, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Text(part.part)
                .font(.subheadline)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !part.formattedDuration.isEmpty {
                Text(part.formattedDuration)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
