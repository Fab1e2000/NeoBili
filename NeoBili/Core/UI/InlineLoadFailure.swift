import SwiftUI

/// A recoverable error that belongs to a section or the end of a loaded list.
struct InlineLoadFailure: View {
    let title: LocalizedStringKey
    let message: String
    var retryTitle: LocalizedStringKey = "重试"
    var retryIdentifier: String? = nil
    var isRetryDisabled = false
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
            Text(message)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)

            Button(retryTitle, action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isRetryDisabled)
                .accessibilityIdentifier(retryIdentifier ?? "", isEnabled: retryIdentifier != nil)
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .frame(maxWidth: .infinity)
    }
}
