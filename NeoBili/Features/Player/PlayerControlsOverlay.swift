import SwiftUI

/// 原生按钮、菜单与滑杆组成媒体控制层；手势区域与稳定的视频渲染层分别管理。
struct PlayerControlsOverlay: View {
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let viewModel: PlayerViewModel
    @Binding var controlsVisible: Bool
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    var onToggleCompact: (() -> Void)? = nil
    var isCompact = false
    var controlsSafeAreaInsets = EdgeInsets()
    var onDismiss: (() -> Void)? = nil
    var videoTitle = ""
    var videoSubtitle = ""
    var shareURL: URL?

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
                  previewVideo: VideoPreviewID(bvid: viewModel.bvid, cid: viewModel.cid))
        }
    }

    var body: some View {
        ZStack {
            if viewModel.errorMessage == nil {
                PlayerProgressGestureLayer(
                    progressSource: progressSource, isFullScreen: isFullScreen, canSeek: canControlPlayback,
                    feedbackTopInset: controlsSafeAreaInsets.top,
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
            }
            if isWaiting, !showsControls {
                ProgressView().tint(.white)
                    .allowsHitTesting(false)
                    .accessibilityLabel("视频正在加载")
            }
            if showsControls {
                PlayerGlassChrome(
                    title: videoTitle, subtitle: videoSubtitle, shareURL: shareURL,
                    videoQualityControl: videoQualityControl, audioQualityControl: audioQualityControl,
                    progressSource: progressSource,
                    isPlaying: viewModel.isPlaying, canControlPlayback: canControlPlayback, isWaiting: isWaiting,
                    isFullScreen: isFullScreen, isCompact: isCompact,
                    hasError: viewModel.errorMessage != nil, safeAreaInsets: controlsSafeAreaInsets,
                    isDanmakuEnabled: danmakuEnabled, showsDanmakuToggle: true,
                    onToggleDanmaku: { danmakuEnabled.toggle() },
                    onBack: { if isFullScreen { onToggleFullScreen() } else { onDismiss?() } },
                    onTogglePlayback: togglePlayback,
                    onToggleFullScreen: { onToggleFullScreen(); scheduleAutoHide() },
                    onToggleCompact: compactAction,
                    onScrub: scrub(to:), onScrubEnd: endScrub(at:), onMenuInteraction: keepControlsForMenu
                ) { playbackMenuContent }
                .opacity(isGestureSeeking ? 0 : 1)
                .allowsHitTesting(!isGestureSeeking)
                .transition(.opacity)
            }
        }
        .task(id: canControlPlayback) {
            guard canControlPlayback else { return }
            await viewModel.storyboardStore.load(VideoPreviewID(bvid: viewModel.bvid, cid: viewModel.cid))
            await viewModel.storyboardStore.prepare(at: viewModel.currentTime)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsControls)
        .onChange(of: isFullScreen) { scheduleAutoHide(afterInteraction: false) }
        .onChange(of: viewModel.isPlaying) { scheduleAutoHide(afterInteraction: false) }
        .onDisappear {
            seekTask?.cancel()
            hideTask?.cancel()
        }
    }

    @ViewBuilder
    private var playbackMenuContent: some View {
        Button(isAddingWatchLater ? "正在加入稍后再看…" : "稍后再看", systemImage: "flag", action: addToWatchLater)
            .disabled(isAddingWatchLater || viewModel.bvid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Menu("定时休眠", systemImage: "moon.zzz") {
            ForEach(PlayerViewModel.sleepOptions, id: \.self) { sleepMenuButton($0) }
            sleepMenuButton(.afterVideoEnd)
            if viewModel.isSleepTimerActive {
                Divider()
                Button("取消定时", role: .destructive) { viewModel.cancelSleepTimer(); scheduleAutoHide() }
            }
        }
    }

    private var videoQualityControl: PlayerQualityControl {
        PlayerQualityControl(
            title: viewModel.selectedVideoQuality.map(PlaybackQuality.videoTitle) ?? "分辨率",
            accessibilityLabel: "分辨率",
            options: viewModel.availableVideoQualities.map { .init(id: $0, title: viewModel.videoQualityTitle($0)) },
            selectedID: viewModel.selectedVideoQuality ?? 0,
            isEnabled: !viewModel.availableVideoQualities.isEmpty && canControlPlayback && !isScrubbing,
            onSelect: { changeQuality(video: $0) }
        )
    }

    private var audioQualityControl: PlayerQualityControl {
        PlayerQualityControl(
            title: viewModel.selectedAudioQuality.map(PlaybackQuality.audioTitle) ?? "音质",
            accessibilityLabel: "音质",
            options: viewModel.availableAudioQualities.map { .init(id: $0, title: PlaybackQuality.audioTitle($0)) },
            selectedID: viewModel.selectedAudioQuality ?? 0,
            isEnabled: !viewModel.availableAudioQualities.isEmpty && canControlPlayback && !isScrubbing,
            onSelect: { changeQuality(audio: $0) }
        )
    }

    private func addToWatchLater() {
        guard !isAddingWatchLater else { return }
        scheduleAutoHide()
        guard account.isLoggedIn else {
            feedback.show("请先登录")
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
                try await BiliAPI.addWatchLater(aid: nil, bvid: bvid)
                guard account.sessionID == session else { return }
                feedback.show("已加入稍后再看")
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
        case .afterVideoEnd: return "本视频播完"
        case .minutes(let minutes):
            return minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
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
