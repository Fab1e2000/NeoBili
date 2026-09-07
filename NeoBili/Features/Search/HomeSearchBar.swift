import SwiftUI
import UIKit

/// A stable native search bar owns its search icon, text insets, clear button,
/// and the system cancel-button transition.
struct HomeSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar(frame: .zero)
        bar.searchBarStyle = .minimal
        bar.placeholder = "搜索视频"
        bar.delegate = context.coordinator
        let field = bar.searchTextField
        field.accessibilityLabel = "搜索视频"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.keyboardType = .webSearch
        field.returnKeyType = .search
        field.textContentType = nil
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        let field = bar.searchTextField
        // Preserve Chinese input method composition while SwiftUI refreshes.
        if field.text != text, field.markedTextRange == nil || text.isEmpty { bar.text = text }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        field.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        if bar.showsCancelButton != isFocused {
            bar.setShowsCancelButton(isFocused, animated: !reduceMotion && bar.window != nil)
        }
        guard field.isFirstResponder != isFocused else { return }
        DispatchQueue.main.async { [weak bar, weak coordinator = context.coordinator] in
            guard let bar, let coordinator, bar.window != nil else { return }
            let field = bar.searchTextField
            if coordinator.parent.isFocused {
                if !field.isFirstResponder { field.becomeFirstResponder() }
            } else if field.isFirstResponder {
                field.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISearchBar, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 56)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: HomeSearchBar
        init(_ parent: HomeSearchBar) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: !parent.reduceMotion)
            if !parent.isFocused { parent.isFocused = true }
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(false, animated: !parent.reduceMotion)
            if parent.isFocused { parent.isFocused = false }
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.onSubmit()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.onCancel()
            searchBar.searchTextField.resignFirstResponder()
            searchBar.setShowsCancelButton(false, animated: !parent.reduceMotion)
        }
    }
}
