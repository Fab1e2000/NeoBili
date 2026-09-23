import SwiftUI

extension View {
    /// 在根视图上统一呈现「我的」页面：各页头像点按后以卡片从底部弹出。
    /// 放在根部而不是各页：隐藏某个标签时那一页会被移除，挂在它上面的卡片也会被一并关掉。
    func mineSheetHost() -> some View { modifier(MineSheetHost()) }
}

private struct MineSheetHost: ViewModifier {
    @State private var isPresented = false
    @State private var openAction = EnvironmentAction<Void> { _ in }

    func body(content: Content) -> some View {
        openAction.setHandler { [isPresented = $isPresented] in
            isPresented.wrappedValue = true
        }
        return content
            .environment(\.openMine, openAction)
            .sheet(isPresented: $isPresented) {
                MineView()
                    .appTextSize()
                    .tint(.primary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
    }
}
