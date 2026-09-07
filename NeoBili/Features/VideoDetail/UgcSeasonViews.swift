import SwiftUI

/// 简介里的合集入口：折叠成一行，点开才列出全部分集。
///
/// 合集动辄几十上百集，直接铺在简介里会把相关视频推到很远的地方；官方也是
/// 折叠一行的做法，右侧标出「当前第几集 / 共几集」。
struct UgcSeasonRow: View {
    let season: UgcSeason
    /// 当前正在播放的分集在合集里的序号（从 1 开始）。找不到时不显示序号。
    let currentIndex: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label("合集 · \(season.title ?? "")", systemImage: "rectangle.stack")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(progressText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel("合集 \(season.title ?? "")，\(progressText)，展开分集列表")
    }

    private var progressText: String {
        let total = season.episodes.count
        guard let currentIndex else { return "\(total)" }
        return "\(currentIndex)/\(total)"
    }
}

/// 合集分集列表。当前这一集由原生 Picker 显示选中标记，点其它集就地换片。
struct UgcSeasonSheet: View {
    let season: UgcSeason
    /// 当前播放的稿件 bvid，用来高亮。
    let currentBvid: String?
    let onSelect: (UgcSeasonEpisode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Picker("选择分集", selection: selection) {
                    ForEach(season.episodes) { episode in
                        row(episode)
                            .tag(Optional(episode.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .listStyle(.insetGrouped)
            // 左缘触控死区：防止边缘误触直接切了分集。
            .leftEdgeTapDeadZone()
            .navigationTitle(season.title ?? "合集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selection: Binding<String?> {
        Binding(get: {
            guard let currentBvid else { return nil }
            return season.episodes.first(where: { $0.bvid == currentBvid })?.id
        }, set: { id in
            guard let id, let episode = season.episodes.first(where: { $0.id == id }) else { return }
            onSelect(episode)
            dismiss()
        })
    }

    private func row(_ episode: UgcSeasonEpisode) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                BiliImage(url: episode.secureCoverURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if !episode.formattedDuration.isEmpty {
                    Text(episode.formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }

            Text(episode.title ?? "")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        }
        .contentShape(Rectangle())
    }
}
