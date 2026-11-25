import SwiftUI

struct FollowCapsuleButton: View {
    @Environment(\.appThemeColor) private var themeColor
    let title: String
    let isActive: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        if isActive {
            button.buttonStyle(.glass).foregroundStyle(.secondary)
        } else {
            button.buttonStyle(.glassProminent).tint(themeColor)
        }
    }

    private var button: some View {
        Button(action: action) {
            if compact {
                Text(title)
                    .font(.app(.footnote, weight: .medium))
                    .frame(minWidth: 56)
            } else {
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 4)
            }
        }
        .buttonBorderShape(.capsule)
    }
}
