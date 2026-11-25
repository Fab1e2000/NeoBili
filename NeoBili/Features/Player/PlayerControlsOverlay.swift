import NeoBiliDomain
import SwiftUI

/// 原生按钮、菜单与滑杆组成媒体控制层；手势区域与稳定的视频渲染层分别管理。
struct PlayerControlsOverlay: View {
    @Environment(\.applicationServices) private var services
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.playbackModePreferences) private var modePreferences
    let viewModel: PlayerViewModel
    @Binding var controlsVisible: Bool
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    /// 全屏控件里的「发弹幕」。
    var onSendDanmaku: (() -> Void)? = nil
    var onToggleCompact: (() -> Void)? = nil
    var isCompact = false
    var controlsSafeAreaInsets = EdgeInsets()
    var onDismiss: (() -> Void)? = nil
    var videoTitle = ""
    var videoSubtitle = ""
    var shareURL: URL?
    var onCache: (() -> Void)? = nil
    var onCast: (() -> Void)? = nil
    var hasEpisodes = false

    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var isGestureSeeking = false
    @State private var seekTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?
    @State private var keepsControlsForMenu = false
    @State private var isAddingWatchLater = false
    @AppStorage(DanmakuSettings.videoEnabledKey) private var danmakuEnabled = DanmakuSettings.defaultValue

    private var isWaiting: Bool { !viewModel.hasRenderedFirstFrame || viewModel.isLoading || viewModel.isBuffering }
    private var showsControls: Bool { controlsVisible || viewModel.errorMessage != nil }
    private var canControlPlayback: Bool { viewModel.hasRenderedFirstFrame && viewModel.errorMessage == nil && !viewModel.isLoading }
    // Defer observable reads until the timeline/gesture leaf evaluates its body.
    // Reading currentTime here in the overlay body would invalidate all menus at 10Hz.
    private var progressSource: PlayerProgressSource {
        PlayerProgressSource {
            .init(position: isScrubbing ? scrubTime : viewModel.currentTime,
                  duration: viewModel.duration, buffered: viewModel.bufferedTime,
                  previewStore: viewModel.storyboardStore,
                  previewVideo: viewModel.isOffline ? nil : VideoPreviewID(bvid: viewModel.bvid, cid: viewModel.cid),
                  chapters: viewModel.chapters)
        }
    }

    var body: some View {
        ZStack {
            if viewModel.errorMessage == nil {
                PlayerProgressGestureLayer(
                    progressSource: progressSource, isFullScreen: isFullScreen, canSeek: canControlPlayback,
                    canLongPress: canControlPlayback && viewModel.isPlaying,
                    feedbackTopInset: controlsSafeAreaInsets.top,
                    onDoubleTap: togglePlayback,
                    onLongPressChanged: { active in
                        if active { viewModel.beginTemporaryDoubleSpeed() }
                        else { viewModel.endTemporaryDoubleSpeed() }
                    },
                    onTap: toggleControls, onToggleFullScreen: onToggleFullScreen,
                    onSeekChanged: { time in
                        guard canControlPlayback else { return }
                        isGestureSeeking = true
                        scrub(to: time)
                    },
                    onSeekEnded: { time in
                        isGestureSeeking = false
                        endScrub(at: time)
                    }, onSeekCancelled: {
                        isGestureSeeking = false
                        cancelScrub()
                    }
                )
                .id(ObjectIdentifier(viewModel))
            }
            if isWaiting, !showsControls {
                ProgressView().tint(.white)
                    .allowsHitTesting(false)
                    .accessibilityLabel("视频正在加载")
            }
            if showsControls {
                PlayerGlassChrome(
                    title: videoTitle, subtitle: videoSubtitle, shareURL: shareURL,
                    videoQualityControl: videoQualityControl, hiResControl: hiResControl,
                    playbackModeControl: playbackModeControl,
                    progressSource: progressSource,
                    isPlaying: viewModel.isPlaying, canControlPlayback: canControlPlayback, isWaiting: isWaiting,
                    isFullScreen: isFullScreen, isCompact: isCompact,
                    hasError: viewModel.errorMessage != nil, safeAreaInsets: controlsSafeAreaInsets,
                    isDanmakuEnabled: danmakuEnabled, showsDanmakuToggle: true,
                    onToggleDanmaku: { danmakuEnabled.toggle() },
                    onBack: { if isFullScreen { onToggleFullScreen() } else { onDismiss?() } },
                    onTogglePlayback: togglePlayback,
                    onToggleFullScreen: { onToggleFullScreen(); scheduleAutoHide() },
                    onSendDanmaku: onSendDanmaku,
                    onToggleCompact: compactAction,
                    onScrub: scrub(to:), onScrubEnd: endScrub(at:), onMenuInteraction: keepControlsForMenu
                ) { playbackMenuContent }
                .opacity(isGestureSeeking ? 0 : 1)
                .allowsHitTesting(!isGestureSeeking)
                .transition(.opacity)
            }
        }
        .task(id: canControlPlayback) {
            guard canControlPlayback, !viewModel.isOffline else { return }
            await viewModel.storyboardStore.load(VideoPreviewID(bvid: viewModel.bvid, cid: viewModel.cid))
            await viewModel.storyboardStore.prepare(at: viewModel.currentTime)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: showsControls)
        .onChange(of: isFullScreen) { scheduleAutoHide(afterInteraction: false) }
        .onChange(of: viewModel.isPlaying) { scheduleAutoHide(afterInteraction: false) }
        .onDisappear {
            seekTask?.cancel()
            hideTask?.cancel()
        }
    }

    @ViewBuilder
    private var playbackMenuContent: some View {
        if let onCast {
            Button("投屏", systemImage: "tv.badge.wifi") {
                onCast()
                scheduleAutoHide()
            }
        }
        PlayerSpeedMenu(rate: viewModel.playbackRate) { rate in
            viewModel.selectPlaybackRate(rate)
            scheduleAutoHide()
        }

        if !viewModel.isOffline {
            Button(isAddingWatchLater ? "正在加入稍后再看…" : "稍后再看", systemImage: "flag", action: addToWatchLater)
                .disabled(isAddingWatchLater || viewModel.bvid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let onCache { Button("缓存", systemImage: "arrow.down.circle", action: onCache) }
        } else if viewModel.offline?.subtitles.isEmpty == false {
            OfflineSubtitleMenu(player: viewModel)
        }
        Menu("定时休眠", systemImage: "moon.zzz") {
            ForEach(PlayerViewModel.sleepOptions, id: \.self) { sleepMenuButton($0) }
            sleepMenuButton(.afterVideoEnd)
            if viewModel.isSleepTimerActive {
                Divider()
                Button("取消定时", role: .destructive) { viewModel.cancelSleepTimer(); scheduleAutoHide() }
            }
        }
    }

    private var playbackModeControl: PlayerPlaybackModeControl {
        PlayerPlaybackModeControl(
            loopEnabled: modePreferences.loopEnabled,
            autoAdvanceEnabled: modePreferences.autoAdvanceEnabled,
            autoAdvanceTitle: PlaybackModeSettings.autoAdvanceTitle(hasEpisodes: hasEpisodes),
            onToggleLoop: {
                modePreferences.toggleLoop()
                scheduleAutoHide()
            },
            onSetAutoAdvance: { enabled in
                modePreferences.setAutoAdvanceEnabled(enabled)
                scheduleAutoHide()
            }
        )
    }

    private var videoQualityControl: PlayerQualityControl {
        PlayerQualityControl(
            title: viewModel.selectedVideoQuality.map(PlaybackQuality.videoTitle) ?? String(localized: "分辨率"),
            accessibilityLabel: String(localized: "分辨率"),
            options: viewModel.availableVideoQualities.map { .init(id: $0, title: viewModel.videoQualityTitle($0)) },
            selectedID: viewModel.selectedVideoQuality ?? 0,
            isEnabled: !viewModel.availableVideoQualities.isEmpty && canControlPlayback && !isScrubbing,
            onSelect: { changeQuality(video: $0) }
        )
    }

    private var hiResControl: PlayerHiResControl? {
        guard !viewModel.isOffline,
              viewModel.availableAudioQualities.contains(PlaybackQuality.hiResAudioQuality) else {
            return nil
        }
        let isActive = viewModel.selectedAudioQuality == PlaybackQuality.hiResAudioQuality
        let fallbackAudio = viewModel.availableAudioQualities.first(where: { $0 != PlaybackQuality.hiResAudioQuality })
        return PlayerHiResControl(
            isActive: isActive,
            isEnabled: canControlPlayback && !isScrubbing && (isActive ? fallbackAudio != nil : true),
            onToggle: {
                if isActive {
                    guard let fallbackAudio else { return }
                    PlaybackQuality.setHiResEnabled(false)
                    changeQuality(audio: fallbackAudio)
                } else {
                    PlaybackQuality.setHiResEnabled(true)
                    changeQuality(audio: PlaybackQuality.hiResAudioQuality)
                }
            }
        )
    }

    private func addToWatchLater() {
        guard !isAddingWatchLater else { return }
        scheduleAutoHide()
        guard account.isLoggedIn else {
            feedback.show(String(localized: "请先登录"))
            return
        }
        let bvid = viewModel.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bvid.isEmpty else { return }
        // 锁保留在控制层，菜单关闭或控制层自动隐藏后再次打开也不会重复提交。
        isAddingWatchLater = true
        let session = account.sessionID
        Task {
            defer { isAddingWatchLater = false }
            guard account.isLoggedIn, account.sessionID == session else { return }
            do {
                try await services.library.addWatchLater(aid: nil, bvid: bvid)
                guard account.sessionID == session else { return }
                feedback.show(String(localized: "已加入稍后再看"))
            } catch {
                guard account.sessionID == session, !error.isCancellation else { return }
                feedback.show(error.localizedDescription)
            }
        }
    }

    private func keepControlsForMenu() {
        hideTask?.cancel()
        keepsControlsForMenu = true
        controlsVisible = true
    }

    private var compactAction: (() -> Void)? {
        guard let onToggleCompact else { return nil }
        return { onToggleCompact(); scheduleAutoHide() }
    }

    private func togglePlayback() {
        viewModel.togglePlayPause()
        scheduleAutoHide()
    }

    private func changeQuality(video: Int? = nil, audio: Int? = nil) {
        guard canControlPlayback, !isScrubbing else { return }
        hideTask?.cancel()
        Task {
            if let message = await viewModel.selectQuality(video: video, audio: audio) { feedback.show(message) }
            scheduleAutoHide()
        }
    }

    private func sleepMenuButton(_ option: PlayerViewModel.SleepOption) -> some View {
        Button { viewModel.setSleepTimer(option); scheduleAutoHide() } label: {
            if viewModel.selectedSleepOption == option {
                Label(title(for: option), systemImage: "checkmark")
            } else { Text(title(for: option)) }
        }
    }

    private func title(for option: PlayerViewModel.SleepOption) -> String {
        switch option {
        case .afterVideoEnd: return String(localized: "本视频播完")
        case .minutes(let minutes):
            return minutes >= 60 && minutes % 60 == 0 ? String(localized: "\(minutes / 60) 小时") : String(localized: "\(minutes) 分钟")
        }
    }

    private func scrub(to time: Double) {
        guard canControlPlayback else { return }
        keepsControlsForMenu = false
        hideTask?.cancel()
        seekTask?.cancel()
        isScrubbing = true
        scrubTime = time
    }

    private func endScrub(at time: Double) {
        guard canControlPlayback else { return }
        isScrubbing = true
        scrubTime = time
        seekTask?.cancel()
        seekTask = Task {
            await viewModel.seek(to: time)
            guard !Task.isCancelled else { return }
            isScrubbing = false
            scheduleAutoHide()
        }
    }

    private func cancelScrub() {
        seekTask?.cancel()
        isScrubbing = false
        scheduleAutoHide()
    }

    private func toggleControls() {
        controlsVisible.toggle()
        scheduleAutoHide()
    }

    private func scheduleAutoHide(afterInteraction: Bool = true) {
        hideTask?.cancel()
        if afterInteraction { keepsControlsForMenu = false }
        guard !keepsControlsForMenu, controlsVisible, viewModel.isPlaying, !isScrubbing, !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }
}

/// Native menu keeps the player uncluttered and exposes the selected rate to VoiceOver.
struct PlayerSpeedMenu: View {
    let rate: Double
    let onSelect: (Double) -> Void

    var body: some View {
        Menu {
            ForEach(PlaybackSpeed.options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    if option == rate { Label(PlaybackSpeed.title(option), systemImage: "checkmark") }
                    else { Text(PlaybackSpeed.title(option)) }
                }
                .accessibilityIdentifier("player.speed.\(option)")
            }
        } label: {
            HStack {
                Label("播放倍速", systemImage: "speedometer")
                Text(PlaybackSpeed.title(rate))
            }
        }
        .accessibilityLabel("播放倍速")
        .accessibilityValue(PlaybackSpeed.title(rate))
        .accessibilityIdentifier("player.speed")
    }
}
