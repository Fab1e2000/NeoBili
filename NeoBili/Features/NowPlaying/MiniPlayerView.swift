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

/// 系统附件负责背景，播放条仅显示标题与播放操作。
struct MiniPlayerBar: View {
    let transitionNamespace: Namespace.ID?
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isInline: Bool { placement == .inline }
    private var title: String { store.livePlayer?.room.title ?? store.detailViewModel?.detail?.title ?? store.route?.title ?? "视频加载中" }
    private var error: String? { store.livePlayer?.errorMessage ?? store.player?.errorMessage ?? store.detailViewModel?.errorMessage }
    var body: some View {
        if store.hasMedia {
            HStack(spacing: isInline ? 6 : 10) {
                Button(action: store.expandMiniPlayer) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开视频：\(title)")
                .accessibilityIdentifier("miniPlayer.expand")

                Button(action: store.togglePlayback) {
                    Group {
                        if error != nil {
                            Image(systemName: "exclamationmark.triangle")
                        } else if store.isLoading || (store.livePlayer?.isBuffering ?? store.player?.isBuffering ?? false) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.hasRenderedFirstFrame || error != nil)
                .accessibilityLabel(store.isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("miniPlayer.playPause")

                if !isInline {
                    Button(action: store.close) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭播放器")
                    .accessibilityIdentifier("miniPlayer.close")
                }
            }
            .padding(.horizontal, isInline ? 8 : 12)
            .padding(.vertical, isInline ? 2 : 6)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "关闭播放器", store.close)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22))
            .contextMenu {
                Button("关闭播放器", systemImage: "xmark", action: store.close)
            } preview: {
                // The accessory changes placement as the tab bar collapses.
                // A standalone preview must not inherit that layout or its zoom anchor.
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(width: 260, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22))
            }
            .background {
                // Keep the native page-transition anchor outside the menu preview.
                if let transitionNamespace {
                    MiniPlayerSourceReadiness(request: store.pendingPresentationID, onReady: store.miniPlayerSourceDidLayout)
                        .videoTransitionSource(NowPlayingStore.miniPlayerTransitionSourceID,
                                               in: transitionNamespace)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// A chrome-only view keeps player ownership and UIKit drag handling in the
/// existing container, and allows layout snapshots without starting playback.
struct MiniPlayerControls: View {
    let isPlaying: Bool
    let canControlPlayback: Bool
    var isLoading = false
    var hasError = false
    let onExpand: () -> Void
    let onTogglePlayback: () -> Void
    let onClose: () -> Void

    private var transportTitle: String {
        if hasError { return "无法播放，请展开视频查看详情" }
        if isLoading {
            return canControlPlayback ? (isPlaying ? "缓冲中，暂停" : "缓冲中，播放") : "视频正在加载"
        }
        return isPlaying ? "暂停" : "播放"
    }

    private var transportSymbol: String {
        hasError ? "exclamationmark.triangle" : (isPlaying ? "pause.fill" : "play.fill")
    }

    var body: some View {
        GeometryReader { geometry in
            GlassEffectContainer(spacing: 4) {
                if geometry.size.width >= 144, geometry.size.height >= 176 {
                    separatedControls
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        compactControls
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .tint(.white)
            .environment(\.colorScheme, .dark)
        }
    }

    private var separatedControls: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    glassButton("展开视频", symbol: "arrow.up.left.and.arrow.down.right",
                                identifier: "miniPlayer.expand", action: onExpand)
                    Spacer(minLength: 0)
                    glassButton("关闭小窗", symbol: "xmark",
                                identifier: "miniPlayer.close", action: onClose)
                }
                Spacer(minLength: 0)
            }
            .padding(8)

            Button(action: onTogglePlayback) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 56, height: 56)
                        .playerGlassSurface(in: Circle())
                } else {
                    PlayerGlassCircleLabel(symbol: transportSymbol, diameter: 56, symbolSize: 24)
                }
            }
            .disabled(!canControlPlayback)
            .opacity(hasError ? 0.7 : 1)
            .accessibilityLabel(transportTitle)
            .accessibilityIdentifier("miniPlayer.playPause")
        }
    }

    private var compactControls: some View {
        HStack(spacing: 0) {
            compactButton("展开视频", symbol: "arrow.up.left.and.arrow.down.right",
                          identifier: "miniPlayer.expand", action: onExpand)
            Button(action: onTogglePlayback) {
                Group {
                    if isLoading { ProgressView().tint(.white) }
                    else { Image(systemName: transportSymbol).font(.system(size: 20, weight: .semibold)) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .disabled(!canControlPlayback)
            .opacity(hasError ? 0.7 : 1)
            .accessibilityLabel(transportTitle)
            .accessibilityIdentifier("miniPlayer.playPause")
            compactButton("关闭小窗", symbol: "xmark", identifier: "miniPlayer.close", action: onClose)
        }
        .padding(.horizontal, 4)
        .playerGlassSurface(in: Capsule())
    }

    private func glassButton(_ title: String, symbol: String, identifier: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) { PlayerGlassCircleLabel(symbol: symbol) }
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
    }

    private func compactButton(_ title: String, symbol: String, identifier: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// Wait for a real window and nonempty geometry, then present on the next main
/// turn, after SwiftUI has registered the accessory's matched transition source.
private struct MiniPlayerSourceReadiness: UIViewRepresentable {
    let request: UUID?
    let onReady: (UUID) -> Void
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ view: AnchorView, context: Context) {
        view.request = request
        view.onReady = onReady
        view.setNeedsLayout()
    }
    final class AnchorView: UIView {
        var request: UUID?
        var onReady: ((UUID) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let request, window != nil, bounds.width > 0, bounds.height > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.request == request, self.window != nil else { return }
                self.request = nil
                self.onReady?(request)
            }
        }
    }
}
