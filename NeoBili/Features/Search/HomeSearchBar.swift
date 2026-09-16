import SwiftUI
import UIKit

/// 原生搜索输入框，尾部删除与退出按钮共用一个布局动画。
struct HomeSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var canClearHistory = false
    var onClearHistory: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Container {
        let view = Container()
        let bar = view.bar
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
        view.cancel.addTarget(context.coordinator, action: #selector(Coordinator.cancel), for: .touchUpInside)
        view.delete.addTarget(context.coordinator, action: #selector(Coordinator.clearHistory), for: .touchUpInside)
        return view
    }

    func updateUIView(_ view: Container, context: Context) {
        context.coordinator.parent = self
        let bar = view.bar
        let field = bar.searchTextField
        // 不打断中文输入法的组合文字。
        if field.text != text, field.markedTextRange == nil || text.isEmpty { bar.text = text }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        field.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        view.tintColor = UIColor(AppTheme.selected(themeID).color)
        view.delete.isEnabled = canClearHistory
        view.setActions(focused: isFocused, empty: text.isEmpty,
                        animated: !reduceMotion && view.window != nil)
        guard field.isFirstResponder != isFocused else { return }
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator, view.window != nil else { return }
            let field = view.bar.searchTextField
            if coordinator.parent.isFocused {
                if !field.isFirstResponder { field.becomeFirstResponder() }
            } else if field.isFirstResponder {
                field.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Container, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 56)
    }

    final class Container: UIView {
        let bar = UISearchBar(frame: .zero)
        let cancel = UIButton(type: .system)
        let delete = UIButton(type: .system)
        private let actions = UIView()
        private var actionsWidth: NSLayoutConstraint!
        private var state: Int = -1

        override init(frame: CGRect) {
            super.init(frame: frame)
            var cancelStyle = UIButton.Configuration.glass()
            cancelStyle.image = UIImage(systemName: "xmark")
            cancelStyle.cornerStyle = .capsule
            cancelStyle.contentInsets = .zero
            cancelStyle.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            cancel.configuration = cancelStyle
            cancel.accessibilityLabel = "退出搜索"
            var deleteStyle = UIButton.Configuration.glass()
            deleteStyle.image = UIImage(systemName: "trash")
            deleteStyle.cornerStyle = .capsule
            deleteStyle.contentInsets = .zero
            deleteStyle.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            delete.configuration = deleteStyle
            delete.accessibilityLabel = "清空搜索历史"
            delete.accessibilityIdentifier = "search.clearHistory"
            actions.clipsToBounds = true
            for child in [bar, actions] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
            for child in [delete, cancel] { child.translatesAutoresizingMaskIntoConstraints = false; actions.addSubview(child) }
            actionsWidth = actions.widthAnchor.constraint(equalToConstant: 0)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.topAnchor.constraint(equalTo: topAnchor), bar.bottomAnchor.constraint(equalTo: bottomAnchor),
                bar.trailingAnchor.constraint(equalTo: actions.leadingAnchor),
                actions.trailingAnchor.constraint(equalTo: trailingAnchor),
                actions.topAnchor.constraint(equalTo: topAnchor), actions.bottomAnchor.constraint(equalTo: bottomAnchor), actionsWidth,
                cancel.trailingAnchor.constraint(equalTo: actions.trailingAnchor),
                cancel.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
                cancel.widthAnchor.constraint(equalToConstant: 44), cancel.heightAnchor.constraint(equalToConstant: 44),
                delete.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -8),
                delete.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
                delete.widthAnchor.constraint(equalToConstant: 44), delete.heightAnchor.constraint(equalToConstant: 44)
            ])
            cancel.alpha = 0; delete.alpha = 0
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setActions(focused: Bool, empty: Bool, animated: Bool) {
            let showsDelete = focused && empty
            let next = focused ? (showsDelete ? 2 : 1) : 0
            guard state != next else { return }
            state = next
            layoutIfNeeded()
            actionsWidth.constant = focused ? (showsDelete ? 96 : 44) : 0
            cancel.isUserInteractionEnabled = focused
            delete.isUserInteractionEnabled = showsDelete
            cancel.accessibilityElementsHidden = !focused
            delete.accessibilityElementsHidden = !showsDelete
            let changes = {
                self.cancel.alpha = focused ? 1 : 0
                self.delete.alpha = showsDelete ? 1 : 0
                self.layoutIfNeeded()
            }
            if animated {
                UIView.animate(withDuration: 0.25, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: changes)
            } else { UIView.performWithoutAnimation(changes) }
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: HomeSearchBar
        init(_ parent: HomeSearchBar) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { parent.text = searchText }
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { parent.isFocused = true }
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) { parent.isFocused = false }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { parent.onSubmit() }
        @objc func cancel() { parent.onCancel() }
        @objc func clearHistory() { parent.onClearHistory() }
    }
}
