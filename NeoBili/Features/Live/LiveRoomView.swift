import SwiftUI

struct LiveRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    private var keepsPlaybackOnDismiss = false
    private var onReturn: (() -> Void)?
    @State private var player: LivePlayerModel
    @State private var following = LiveRoomFollowModel()
    @State private var isIntroductionExpanded = false
    @State private var detailsHeaderHeight: CGFloat = 160
    @State private var isFullScreen = false
    @State private var orientationOwner = UUID()
    @State private var controlsVisible = false
    @State private var controlsSafeArea = EdgeInsets()
    @State private var reloadID = 0
    @State private var requestedQuality: Int?
    @State private var hideTask: Task<Void, Never>?
    @State private var keepsControlsForMenu = false
    @State private var danmaku = LiveDanmakuModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DanmakuSettings.liveEnabledKey) private var liveDanmakuEnabled = DanmakuSettings.defaultValue

    init(room: LiveRoom) { _player = State(initialValue: LivePlayerModel(room: room)) }
    init(player: LivePlayerModel, keepsPlaybackOnDismiss: Bool = false,
         onReturn: (() -> Void)? = nil) {
        _player = State(initialValue: player)
        self.keepsPlaybackOnDismiss = keepsPlaybackOnDismiss
        self.onReturn = onReturn
    }

    private var followContext: LiveRoomFollowModel.Context {
        .init(mid: player.room.uid, sessionID: account.sessionID,
              isLoggedIn: account.isLoggedIn, accountID: account.accountID)
    }

    private var shareURL: URL { URL(string: "https://live.bilibili.com/\(player.room.roomID)")! }
    private var showsControls: Bool {
        controlsVisible || player.errorMessage != nil || player.isOffline
    }

    var body: some View {
        GeometryReader { geometry in
            let screenSize = CGSize(width: geometry.size.width,
                                    height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
            let ratio = player.errorMessage != nil || player.isOffline ? nil : player.displayAspectRatio
            let playerHeight = isFullScreen ? geometry.size.height : InlineVideoLayout.height(for: screenSize, aspectRatio: ratio)
            VStack(spacing: 0) {
                videoSurface
                    .frame(width: geometry.size.width, height: playerHeight)
                    .clipped()
                    .background {
                        PlayerReturnGestureGuard(enabled: true)
                            .allowsHitTesting(false)
                    }
                if !isFullScreen {
                    roomDetails(bottomInset: geometry.safeAreaInsets.bottom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            PlayerReturnGestureGuard(enabled: true, verticalOnly: true)
                                .allowsHitTesting(false)
                        }
                        .leftEdgeTapDeadZone()
                }
            }
            .frame(width: geometry.size.width,
                   height: geometry.size.height + (isFullScreen ? 0 : geometry.safeAreaInsets.bottom),
                   alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
        .statusBarHidden(isFullScreen)
        .background { PlayerSafeAreaReader { controlsSafeArea = $0 }.allowsHitTesting(false) }
        .task(id: reloadID) {
            if !keepsPlaybackOnDismiss || reloadID > 0 {
                await player.load(quality: requestedQuality)
            }
        }
        .task(id: followContext) { await following.load(followContext) }
        // 真实房间号在播放地址返回后才更新；跟着它（重）连弹幕服务器。
        // 列表常驻；飘幕开关只影响画面上的那层。
        .task(id: "\(player.danmakuRoomID)-\(player.hasRenderedFirstFrame)") {
            // Give the media request a short head start, but keep chat available if video stalls.
            if !player.hasRenderedFirstFrame {
                do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            danmaku.start(roomID: player.danmakuRoomID)
        }
        // 退后台后直播 WS 必断，回前台主动重连，不等心跳超时才暴露。
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            danmaku.stop()
            danmaku.start(roomID: player.danmakuRoomID)
        }
        .actionFeedbackOverlay()
        .onChange(of: player.isPlaying) { scheduleHide(afterInteraction: false) }
        .onChange(of: voiceOverEnabled) { scheduleHide(afterInteraction: false) }
        .onChange(of: player.displayAspectRatio) { if isFullScreen { applyFullScreenOrientation() } }
        .onDisappear {
            hideTask?.cancel()
            if !keepsPlaybackOnDismiss { player.stop() }
            danmaku.stop()
            OrientationController.endPlaybackOrientation(owner: orientationOwner)
        }
    }

    private var videoSurface: some View {
        ZStack {
            Color.black
            PlayerSurface(session: player.session)
                .allowsHitTesting(false)
            if !player.hasRenderedFirstFrame, let cover = player.room.coverURL {
                BiliImage(url: cover).aspectRatio(contentMode: .fit)
            }
            // 全屏时弹幕直接铺在画面上；非全屏改用播放器下方的独立容器。
            if isFullScreen, liveDanmakuEnabled {
                LiveDanmakuFlowView(model: danmaku)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Color.clear.contentShape(Rectangle())
                .onTapGesture {
                    controlsVisible.toggle()
                    scheduleHide()
                }
            if isFullScreen, liveDanmakuEnabled, let superChat = danmaku.superChats.first {
                SuperChatBanner(item: superChat) { danmaku.hideSuperChat(superChat.id) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 25)
                    .padding(.bottom, 64)
                    .allowsHitTesting(!showsControls)
            }
            if (player.isLoading || player.isBuffering), !showsControls {
                ProgressView().tint(.white).allowsHitTesting(false)
            }
            if player.isOffline || player.errorMessage != nil {
                VStack(spacing: 8) {
                    Label(player.isOffline ? "主播暂未开播" : "直播连接中断",
                          systemImage: player.isOffline ? "moon.zzz" : "wifi.exclamationmark")
                        .font(.headline)
                    Button("重新连接", systemImage: "arrow.clockwise", action: reconnect)
                        .modifier(PlayerClearGlassButtonStyle())
                        .controlSize(.regular)
                }
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
            }
            if showsControls {
                PlayerGlassChrome(
                    title: player.room.title, subtitle: player.room.username, shareURL: shareURL,
                    videoQualityControl: qualityControl,
                    isPlaying: player.isPlaying,
                    canControlPlayback: player.hasRenderedFirstFrame && player.errorMessage == nil && !player.isOffline,
                    isWaiting: player.isLoading || player.isBuffering,
                    isLive: true, isFullScreen: isFullScreen,
                    hasError: player.errorMessage != nil || player.isOffline,
                    safeAreaInsets: isFullScreen ? controlsSafeArea : EdgeInsets(),
                    isDanmakuEnabled: liveDanmakuEnabled, showsDanmakuToggle: true,
                    onToggleDanmaku: { liveDanmakuEnabled.toggle() },
                    onBack: { if isFullScreen { toggleFullScreen() } else { if let onReturn { onReturn() } else { dismiss() } } },
                    onTogglePlayback: { player.togglePlayback(); scheduleHide() },
                    onToggleFullScreen: toggleFullScreen,
                    onMenuInteraction: { hideTask?.cancel(); keepsControlsForMenu = true; controlsVisible = true }
                ) {
                    Button("重新连接", systemImage: "arrow.clockwise", action: reconnect)
                    ShareLink(item: shareURL) { Label("分享直播间", systemImage: "square.and.arrow.up") }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsControls)
        .accessibilityIdentifier("live.player")
    }

    private var qualityControl: PlayerQualityControl {
        PlayerQualityControl(
            title: player.qualities.first { $0.id == player.selectedQuality }?.name ?? String(localized: "清晰度"),
            accessibilityLabel: String(localized: "清晰度"),
            options: player.qualities.map { .init(id: $0.id, title: $0.name) },
            selectedID: player.selectedQuality,
            isEnabled: !player.qualities.isEmpty && !player.isLoading && !player.isOffline,
            onSelect: { requestedQuality = $0; reconnect() }
        )
    }

    private func roomDetails(bottomInset: CGFloat) -> some View {
        GeometryReader { geometry in
            let bottomPadding = max(8, bottomInset)
            // 用剩余高度承载弹幕；长简介或小屏幕仍可滚动，并保留可用的弹幕视口。
            let panelHeight = max(200, geometry.size.height - detailsHeaderHeight - 14 - 14 - bottomPadding)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        LiveRoomOwnerRow(room: player.room, card: following.card, isFollowing: following.isFollowing,
                                         isLoading: following.isLoading, isToggling: following.isToggling,
                                         isOwnAccount: followContext.isOwnAccount, onToggleFollow: toggleFollow)
                        LiveRoomIntroductionCard(room: player.room, isOffline: player.isOffline,
                                                 isExpanded: $isIntroductionExpanded)
                        if let error = player.errorMessage {
                            Label(error, systemImage: "wifi.exclamationmark")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        detailsHeaderHeight = $0
                    }
                    LiveDanmakuPanel(model: danmaku)
                        .frame(height: panelHeight)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(true, for: .bottom)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                .fill(Color(uiColor: .systemBackground))
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func toggleFollow() {
        let context = followContext
        Task {
            guard context.isLoggedIn else { feedback.show(String(localized: "请先登录")); return }
            if following.isFollowing == nil {
                await following.load(context, force: true)
                if let message = following.errorMessage { feedback.show(message) }
            } else if let message = await following.toggleFollow(context) {
                feedback.show(message)
            }
        }
    }

    private func reconnect() {
        keepsControlsForMenu = false
        controlsVisible = true
        reloadID += 1
    }

    private func toggleFullScreen() {
        isFullScreen.toggle()
        if isFullScreen { applyFullScreenOrientation() }
        else { OrientationController.endPlaybackOrientation(owner: orientationOwner) }
        controlsVisible = true
        scheduleHide()
    }

    private func applyFullScreenOrientation() {
        let orientation = VideoFullscreenOrientation.preferred(for: player.displayAspectRatio)
        OrientationController.setPlaybackOrientation(
            orientation == .portrait ? .portrait : .landscape, owner: orientationOwner)
    }

    private func scheduleHide(afterInteraction: Bool = true) {
        hideTask?.cancel()
        if afterInteraction { keepsControlsForMenu = false }
        guard !keepsControlsForMenu, controlsVisible, player.isPlaying, !voiceOverEnabled else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }

}

/// 直播画面上的按钮和播放器控件同时出现，跟着用透明变体，不和控件混用两种玻璃。
/// 带参数的玻璃按钮样式从 iOS 26.1 起才有，26.0 仍用默认样式。
private struct PlayerClearGlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.buttonStyle(.glass(.clear))
        } else {
            content.buttonStyle(.glass)
        }
    }
}
