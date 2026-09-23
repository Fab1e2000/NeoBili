import SwiftUI

extension View {
    /// 在根视图上统一呈现「我的」页面，从发起页的头像原位放大。
    /// 放在根部而不是各页：隐藏某个标签时那一页会被移除，挂在它上面的卡片也会被一并关掉。
    func mineSheetHost() -> some View { modifier(MineSheetHost()) }
}

private struct MineSheetHost: ViewModifier {
    private struct Presentation: Identifiable {
        let transitionID: String
        var id: String { transitionID }
    }

    @State private var presentation: Presentation?
    @State private var openAction = EnvironmentAction<String> { _ in }
    @Environment(\.videoTransitionNamespace) private var transition

    func body(content: Content) -> some View {
        openAction.setHandler { [presentation = $presentation] in
            presentation.wrappedValue = Presentation(transitionID: $0)
        }
        return content
            .environment(\.openMine, openAction)
            .sheet(item: $presentation) { presentation in
                MineView()
                    .appTextSize()
                    .tint(.primary)
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
                    .modifier(MineZoomTransition(transitionID: presentation.transitionID, namespace: transition))
            }
    }
}

private struct MineZoomTransition: ViewModifier {
    let transitionID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: transitionID, in: namespace))
        } else {
            content
        }
    }
}
