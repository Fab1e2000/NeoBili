import SwiftUI

extension View {
    func miniPlayerHost(isActive: @escaping () -> Bool = { true }, transitionNamespace: Namespace.ID? = nil) -> some View {
        modifier(MiniPlayerHost(isActive: isActive, transitionNamespace: transitionNamespace))
    }
}

private struct MiniPlayerHost: ViewModifier {
    let isActive: () -> Bool
    let transitionNamespace: Namespace.ID?
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @AppStorage(MiniPlayerMovementSettings.topKey) private var topLimit = 0.0
    @AppStorage(MiniPlayerMovementSettings.bottomKey) private var bottomLimit = 1.0
    @Environment(NowPlayingStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.overlay {
            if isActive(), MiniPlayerBoundsPreviewState.shared.isVisible {
                MiniPlayerBoundsPreview(top: topLimit, bottom: bottomLimit)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            // Keep the source alive underneath the full-screen page. Removing it
            // on expansion leaves the system zoom with only the old feed card.
            if isActive(), miniPlayerEnabled, store.route != nil {
                MiniPlayerContainer(
                    content: FloatingMiniPlayer(
                        player: store.player,
                        coverURL: store.route?.secureCoverURL,
                        errorMessage: store.player?.errorMessage ?? store.detailViewModel?.errorMessage,
                        showsTransitionCover: store.isExpanded || store.isVideoPageDismissalInProgress,
                        isHostActive: isActive,
                        onExpand: store.expandMiniPlayer,
                        onClose: store.close
                    )
                    .environment(\.dynamicTypeSize, typeSize)
                    .videoTransitionSource(NowPlayingStore.miniPlayerTransitionSourceID, in: transitionNamespace)
                    .opacity(store.transitionSourceID == NowPlayingStore.miniPlayerTransitionSourceID || store.isMiniPlayerPresented ? 1 : 0),
                    aspectRatio: store.player?.displayAspectRatio,
                    anchor: store.miniPlayerAnchor,
                    reduceMotion: reduceMotion,
                    topLimit: topLimit, bottomLimit: bottomLimit,
                    onAnchorChange: { store.miniPlayerAnchor = $0 }
                )
                .allowsHitTesting(store.isMiniPlayerPresented && !store.isExpanded)
                .accessibilityHidden(!store.isMiniPlayerPresented || store.isExpanded)
            }
        }
    }
}

private struct FloatingMiniPlayer: View {
    let player: PlayerViewModel?
    let coverURL: URL?
    let errorMessage: String?
    let showsTransitionCover: Bool
    let isHostActive: () -> Bool
    let onExpand: () -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var controlsVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerSurface(session: player.session, presentation: .mini, isHostActive: isHostActive)
                    .allowsHitTesting(false)
            }
            if player?.hasRenderedFirstFrame != true || showsTransitionCover, let coverURL {
                BiliImage(url: coverURL).aspectRatio(contentMode: .fit)
            }
            if !controlsVisible, isLoading {
                ProgressView().tint(.white).allowsHitTesting(false)
            }
            if !controlsVisible, errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(controlsAnimation) { controlsVisible.toggle() }
                    scheduleHide()
                }
            if controlsVisible {
                MiniPlayerControls(
                    isPlaying: player?.isPlaying == true,
                    canControlPlayback: player?.hasRenderedFirstFrame == true && errorMessage == nil,
                    isLoading: isLoading,
                    hasError: errorMessage != nil,
                    onExpand: onExpand,
                    onTogglePlayback: {
                        player?.togglePlayPause()
                        scheduleHide()
                    },
                    onClose: onClose
                )
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("视频小窗")
        .accessibilityAction(named: "展开视频", onExpand)
        .accessibilityAction(named: "播放或暂停") { player?.togglePlayPause() }
        .accessibilityAction(named: "关闭小窗", onClose)
        .onChange(of: player?.isPlaying) { scheduleHide() }
        .onChange(of: voiceOverEnabled) { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
    }

    private var isLoading: Bool {
        errorMessage == nil && (player == nil || player?.isLoading == true || player?.isBuffering == true)
    }

    private var controlsAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.15) }

    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible, player?.isPlaying == true, !voiceOverEnabled else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(controlsAnimation) { controlsVisible = false }
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
