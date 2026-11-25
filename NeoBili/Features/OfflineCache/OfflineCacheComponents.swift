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

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let localURL {
                BiliImage(url: localURL, targetSize: CGSize(width: width, height: width * 0.66),
                          placeholder: .symbol("play.rectangle"))
                    .scaledToFill()
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
