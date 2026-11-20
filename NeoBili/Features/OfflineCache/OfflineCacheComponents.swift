import SwiftUI
import NeoBiliDomain

enum OfflineCacheStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let radius: CGFloat = 18

    static func duration(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct OfflineCover: View {
    let remoteURL: URL?
    var localURL: URL? = nil
    var badge: String? = nil
    var width: CGFloat = 108
    @State private var localImage: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let localURL {
                if let localImage { Image(uiImage: localImage).resizable().scaledToFill() }
                else { Image(systemName: "play.rectangle").foregroundStyle(.tertiary) }
                Color.clear.task(id: localURL) { localImage = UIImage(contentsOfFile: localURL.path) }
            } else if let remoteURL {
                BiliImage(url: remoteURL, targetSize: CGSize(width: width, height: width * 0.66)).scaledToFill()
            } else {
                Image(systemName: "play.rectangle").foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, height: width * 0.66)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Text(badge).font(.app(.caption2, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4)).padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

struct OfflineEpisodeRow: View {
    @Environment(\.appThemeColor) private var accent
    let number: Int
    let title: String
    let subtitle: String
    let selected: Bool
    var current = false
    var selectionControl = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if current && !selectionControl { Image(systemName: "waveform") }
                    else { Text(String(format: "%02d", number)).monospacedDigit() }
                }
                .font(.app(.caption)).foregroundStyle(.secondary).frame(minWidth: 22)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.app(.subheadline, weight: .medium)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(subtitle).font(.app(.caption)).foregroundStyle(.secondary)
                }
                if selectionControl {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(selected ? accent : Color.secondary.opacity(0.4))
                } else if current {
                    Text("当前").font(.app(.caption2)).foregroundStyle(accent)
                }
            }
            .padding(14).frame(minHeight: 64)
            .background(selected ? accent.opacity(0.1) : OfflineCacheStyle.card,
                        in: RoundedRectangle(cornerRadius: OfflineCacheStyle.radius))
            .contentShape(RoundedRectangle(cornerRadius: OfflineCacheStyle.radius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
