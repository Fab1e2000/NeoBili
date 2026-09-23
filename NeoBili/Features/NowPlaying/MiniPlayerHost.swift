import SwiftUI

extension View {
    /// 主 TabView 使用原生底部附件，随导航栏在展开和紧凑布局之间切换。
    func tabMiniPlayerHost(isActive: @escaping () -> Bool = { true }, transitionNamespace: Namespace.ID? = nil) -> some View {
        modifier(TabMiniPlayerHost(isActive: isActive, transitionNamespace: transitionNamespace))
    }

    /// 收藏、历史等独立 sheet 没有 TabView，用安全区栏承载同一个播放条。
    func miniPlayerHost(isActive: @escaping () -> Bool = { true }, transitionNamespace: Namespace.ID? = nil) -> some View {
        modifier(SheetMiniPlayerHost(isActive: isActive, transitionNamespace: transitionNamespace))
    }
}

private struct TabMiniPlayerHost: ViewModifier {
    let isActive: () -> Bool
    let transitionNamespace: Namespace.ID?
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @Environment(NowPlayingStore.self) private var store

    @ViewBuilder
    func body(content: Content) -> some View {
        // 保留全屏页下方的附件，使 zoom 退出始终有稳定的标题栏目标。
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: miniPlayerEnabled && store.hasMedia && isActive()) {
                MiniPlayerBar(transitionNamespace: transitionNamespace)
            }
        } else {
            content.tabViewBottomAccessory {
                if miniPlayerEnabled && store.hasMedia && isActive() {
                    MiniPlayerBar(transitionNamespace: transitionNamespace)
                }
            }
        }
    }
}

private struct SheetMiniPlayerHost: ViewModifier {
    let isActive: () -> Bool
    let transitionNamespace: Namespace.ID?
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @Environment(NowPlayingStore.self) private var store

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if miniPlayerEnabled && store.hasMedia && isActive() {
                MiniPlayerBar(transitionNamespace: transitionNamespace)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }
}
