#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 视频渲染层与自绘控件。VideoPage 在内联和全屏布局间保留同一播放会话。
struct InlineVideoPlayer: View {
    @Environment(\.applicationServices) private var services
    @Environment(\.castSession) private var castSession
    @Environment(ActionFeedback.self) private var feedback
    let viewModel: PlayerViewModel
    @Binding var controlsVisible: Bool
    /// 列表卡片上那张封面。播放器拿到首帧之前先显示它，代替一整块黑屏。
    let coverURL: URL?
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    /// 全屏控件里的「发弹幕」。
    var onSendDanmaku: (() -> Void)? = nil
    var onToggleCompact: (() -> Void)? = nil
    var isCompact = false
    var isDanmakuSuppressed = false
    var controlsSafeAreaInsets = EdgeInsets()
    var onDismiss: (() -> Void)? = nil
    var videoTitle = ""
    var videoSubtitle = ""
    var shareURL: URL?
    var onCache: (() -> Void)? = nil

    @AppStorage(DanmakuSettings.videoEnabledKey) private var danmakuEnabled = DanmakuSettings.defaultValue
    @State private var isCastPickerPresented = false
    @State private var castVideoPayload: PlayURLData?
    @State private var castSelectedVideoQuality: Int?
    @State private var castSelectedAudioQuality: Int?

    private var castMediaID: String {
        viewModel.isOffline ? "offline:\(viewModel.bvid):\(viewModel.cid)" : "video:\(viewModel.bvid):\(viewModel.cid)"
    }

    private var isCastingCurrentVideo: Bool {
        castSession?.isCasting(mediaID: castMediaID) == true
    }

    var body: some View {
        ZStack {
            Color.black

            // 渲染容器要在取流前挂载好，避免播放内核已经打开流而渲染层
            // 还没就绪。首帧前仍用封面遮住空白画面。
            // 这里刻意不加 `.id(session)`：换 session 由 `PlayerSurface` 的容器
            // 自己接管（见 PlayerSurfaceContainerController）。用 id 强制重建
            // 反而会让 SwiftUI 拆掉正在渲染的那一层，出现有声音没画面。
            PlayerSurface(session: viewModel.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let danmaku = viewModel.danmaku {
                DanmakuView(controller: danmaku, isFullScreen: isFullScreen, isSuppressed: isDanmakuSuppressed)
                    // 视频保持铺满屏幕，只有弹幕画布从灵动岛下方开始。
                    .padding(.top, isFullScreen ? controlsSafeAreaInsets.top : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if !viewModel.hasRenderedFirstFrame, let coverURL {
                if coverURL.isFileURL { OfflineArtwork(url: coverURL).aspectRatio(contentMode: .fit) }
                else { BiliImage(url: coverURL).aspectRatio(contentMode: .fit) }
            }

            if viewModel.isOffline {
                VStack { Spacer(); OfflineSubtitleOverlay(player: viewModel, controlsVisible: controlsVisible) }
            }

            if let message = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("无法播放", systemImage: "play.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试播放") { Task { await viewModel.retry() } }
                        .disabled(viewModel.isLoading)
                }
                .foregroundStyle(.white)
            }
            // 载入和失败阶段仍保留返回、全屏、收缩入口。
            if isCastingCurrentVideo, let castSession {
                CastPlaybackOverlay(
                    castSession: castSession,
                    isFullScreen: isFullScreen,
                    safeAreaInsets: controlsSafeAreaInsets,
                    videoQualityControl: castVideoQualityControl,
                    audioQualityControl: castAudioQualityControl,
                    onBack: { if isFullScreen { onToggleFullScreen() } else { onDismiss?() } },
                    onSwitchDevice: { isCastPickerPresented = true },
                    onExitCast: exitCasting
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlayerControlsOverlay(
                    viewModel: viewModel,
                    controlsVisible: $controlsVisible,
                    isFullScreen: isFullScreen,
                    onToggleFullScreen: onToggleFullScreen,
                    onSendDanmaku: onSendDanmaku,
                    onToggleCompact: onToggleCompact,
                    isCompact: isCompact,
                    controlsSafeAreaInsets: controlsSafeAreaInsets,
                    onDismiss: onDismiss,
                    videoTitle: videoTitle,
                    videoSubtitle: videoSubtitle,
                    shareURL: shareURL,
                    onCache: onCache,
                    onCast: castSession == nil ? nil : { isCastPickerPresented = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isCastPickerPresented) {
            if let castSession {
                CastDevicePickerSheet(
                    castSession: castSession,
                    mediaTitle: videoTitle.isEmpty ? viewModel.bvid : videoTitle,
                    onSelectDevice: startCasting(to:)
                )
            }
        }
        .onAppear { syncDanmaku() }
        .onChange(of: viewModel.hasRenderedFirstFrame) { syncDanmaku() }
        .onChange(of: danmakuEnabled) { syncDanmaku() }
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing, isCastingCurrentVideo || castSession?.isCastModeActive == true {
                viewModel.pause()
            }
        }
        // 投屏模式下打开新视频、切换分P或打开离线缓存时，自动把新内容切换到当前投屏设备。
        .task(id: "\(castMediaID)-\(castSession?.activeDevice?.id ?? "")") {
            castVideoPayload = nil
            castSelectedVideoQuality = nil
            castSelectedAudioQuality = nil
            guard let castSession,
                  castSession.isCastModeActive,
                  let device = castSession.activeDevice,
                  castSession.activeMedia?.id != castMediaID else { return }
            viewModel.pause()
            startCasting(to: device)
        }
        // 换视频（相关视频、换P）会换掉整个 PlayerViewModel，但本视图身份
        // 不变——onAppear 和 onChange 都不会再触发，必须跟着播放器实例走。
        .task(id: ObjectIdentifier(viewModel)) { syncDanmaku() }
    }

    /// 开关状态与控制器保持一致：打开时确保已创建并加载，关闭时立即释放。
    private func syncDanmaku() {
        if !danmakuEnabled { viewModel.disableDanmaku() }
        else if viewModel.hasRenderedFirstFrame { viewModel.ensureDanmaku() }
    }

    private var castVideoQualityControl: PlayerQualityControl? {
        guard !viewModel.isOffline else { return nil }
        let qualities = castVideoPayload?.declaredVideoQualities ?? viewModel.availableVideoQualities
        guard !qualities.isEmpty else { return nil }
        let selected = castSelectedVideoQuality ?? castVideoPayload?.quality ?? viewModel.selectedVideoQuality ?? qualities.first ?? 80
        return PlayerQualityControl(
            title: PlaybackQuality.videoTitle(selected),
            accessibilityLabel: String(localized: "投屏画质"),
            options: qualities.map { qn in
                .init(id: qn, title: castVideoQualityTitle(qn))
            },
            selectedID: selected,
            isEnabled: !qualities.isEmpty,
            onSelect: { switchCastVideoQuality(to: $0) }
        )
    }

    private var castAudioQualityControl: PlayerQualityControl? {
        guard !viewModel.isOffline else { return nil }
        let dashAudios = castVideoPayload?.dash?.allAudio.filter { URL.biliSecure($0.baseUrl) != nil } ?? []
        let audioIDs = Array(Set(dashAudios.map(\.id)))
            .sorted { PlaybackQuality.audioRank($0) > PlaybackQuality.audioRank($1) }
        guard !audioIDs.isEmpty else { return nil }
        let selected = castSelectedAudioQuality ?? viewModel.selectedAudioQuality ?? audioIDs.first ?? 0
        return PlayerQualityControl(
            title: PlaybackQuality.audioTitle(selected),
            accessibilityLabel: String(localized: "投屏音质"),
            options: audioIDs.map { .init(id: $0, title: PlaybackQuality.audioTitle($0)) },
            selectedID: selected,
            isEnabled: !audioIDs.isEmpty,
            onSelect: { switchCastQuality(video: nil, audio: $0) }
        )
    }

    private func castVideoQualityTitle(_ quality: Int) -> String {
        let title = PlaybackQuality.videoTitle(quality)
        guard castVideoPayload?.hasVideoStream(quality: quality) != true,
              let format = castVideoPayload?.supportFormats?.first(where: { $0.quality == quality }) else {
            return title
        }
        if format.needsVIP == true { return title + String(localized: "（需大会员）") }
        if format.needsLogin == true { return title + String(localized: "（需登录）") }
        return title
    }

    private func switchCastVideoQuality(to targetQuality: Int) {
        switchCastQuality(video: targetQuality, audio: nil)
    }

    private func switchCastQuality(video targetVideo: Int?, audio targetAudio: Int?) {
        guard let castSession,
              castSession.isCastModeActive,
              !castSession.isSwitchingStream,
              !viewModel.isOffline else { return }
        if let targetVideo, targetVideo == castSelectedVideoQuality, targetAudio == nil { return }
        if let targetAudio, targetAudio == castSelectedAudioQuality, targetVideo == nil { return }

        let mediaID = castMediaID
        let title = videoTitle.isEmpty ? viewModel.bvid : videoTitle
        let subtitle = videoSubtitle
        let resumePosition = castSession.currentTime
        let bvid = viewModel.bvid
        let cid = viewModel.cid
        let desiredVideo = targetVideo ?? castSelectedVideoQuality ?? viewModel.selectedVideoQuality ?? 80
        let desiredAudio = targetAudio ?? castSelectedAudioQuality ?? viewModel.selectedAudioQuality ?? 0
        let existingPayload = castVideoPayload

        Task {
            do {
                var payload: PlayURLData
                if let existingPayload,
                   targetVideo == nil || existingPayload.hasVideoStream(quality: desiredVideo) {
                    payload = existingPayload
                } else {
                    let fetched = try await services.video.playURL(bvid: bvid, cid: cid, quality: desiredVideo)
                    payload = existingPayload.map { fetched.preservingDeclaredQualities(from: $0) } ?? fetched
                }

                let resolved = try buildOnlineCastRequest(
                    payload: payload,
                    mediaID: mediaID,
                    title: title,
                    subtitle: subtitle,
                    startPosition: resumePosition,
                    desiredVideoQuality: desiredVideo,
                    desiredAudioQuality: desiredAudio
                )
                let updated = await castSession.hotUpdateMedia(resolved.request)
                if updated {
                    castVideoPayload = payload
                    castSelectedVideoQuality = resolved.actualVideoQuality
                    castSelectedAudioQuality = resolved.actualAudioQuality
                    if let targetVideo, resolved.actualVideoQuality != targetVideo {
                        feedback.show(String(localized: "已切换至 \(PlaybackQuality.videoTitle(resolved.actualVideoQuality))（原档位需更高权限）"))
                    } else if targetAudio != nil, let actualAudio = resolved.actualAudioQuality {
                        feedback.show(String(localized: "音质已切换至 \(PlaybackQuality.audioTitle(actualAudio))"))
                    } else {
                        feedback.show(String(localized: "已切换至 \(PlaybackQuality.videoTitle(resolved.actualVideoQuality))"))
                    }
                } else if let err = castSession.controlError {
                    feedback.show(err)
                }
            } catch {
                if !error.isCancellation {
                    feedback.show(error.localizedDescription)
                }
            }
        }
    }

    private func startCasting(to device: CastDevice) {
        guard let castSession else { return }
        let mediaID = castMediaID
        let title = videoTitle.isEmpty ? viewModel.bvid : videoTitle
        let subtitle = videoSubtitle
        let startPosition = viewModel.currentTime
        let desiredVideo = castSelectedVideoQuality ?? viewModel.selectedVideoQuality ?? 116
        let desiredAudio = castSelectedAudioQuality ?? viewModel.selectedAudioQuality ?? 0
        let offline = viewModel.offline
        let bvid = viewModel.bvid
        let cid = viewModel.cid

        Task {
            do {
                let request: CastMediaRequest
                var fetchedPayload: PlayURLData?
                var resolvedVideoQuality: Int?
                var resolvedAudioQuality: Int?

                if let offline {
                    guard let videoURL = offline.videoURLs.first else {
                        throw CastError.mediaUnavailable(String(localized: "离线缓存文件不可用"))
                    }
                    let source: CastMediaSource
                    if let audioURL = offline.audioURL {
                        source = .localDualTrack(videoURL: videoURL, audioURL: audioURL)
                    } else {
                        source = .localFile(url: videoURL, mimeType: "video/mp4")
                    }
                    request = CastMediaRequest(
                        id: mediaID,
                        title: title,
                        subtitle: subtitle,
                        kind: .offlineVideo,
                        startPosition: startPosition,
                        duration: viewModel.duration,
                        source: source
                    )
                } else {
                    let payload = try await services.video.playURL(bvid: bvid, cid: cid, quality: desiredVideo)
                    let resolved = try buildOnlineCastRequest(
                        payload: payload,
                        mediaID: mediaID,
                        title: title,
                        subtitle: subtitle,
                        startPosition: startPosition,
                        desiredVideoQuality: desiredVideo,
                        desiredAudioQuality: desiredAudio
                    )
                    request = resolved.request
                    fetchedPayload = payload
                    resolvedVideoQuality = resolved.actualVideoQuality
                    resolvedAudioQuality = resolved.actualAudioQuality
                }

                let started = await castSession.startCasting(device: device, media: request)
                if started {
                    if let fetchedPayload {
                        castVideoPayload = castVideoPayload.map { fetchedPayload.preservingDeclaredQualities(from: $0) } ?? fetchedPayload
                        castSelectedVideoQuality = resolvedVideoQuality
                        castSelectedAudioQuality = resolvedAudioQuality
                    }
                    viewModel.pause()
                    feedback.show(String(localized: "已投屏到 \(device.name)"))
                } else if case .error(let message) = castSession.phase {
                    feedback.show(message)
                }
            } catch {
                if !error.isCancellation {
                    feedback.show(error.localizedDescription)
                }
            }
        }
    }

    private struct ResolvedOnlineCast {
        let request: CastMediaRequest
        let actualVideoQuality: Int
        let actualAudioQuality: Int?
    }

    private func buildOnlineCastRequest(
        payload: PlayURLData,
        mediaID: String,
        title: String,
        subtitle: String,
        startPosition: TimeInterval,
        desiredVideoQuality: Int,
        desiredAudioQuality: Int
    ) throws -> ResolvedOnlineCast {
        let headers = [
            "Referer": "https://www.bilibili.com",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]

        // 优先走 DASH 实时无损混流，支持 1080P60/4K 全画质与独立音质切换。
        if let dash = payload.dash, !dash.video.isEmpty {
            let validVideos = dash.video.filter { URL.biliSecure($0.baseUrl) != nil }
            let pickedVideo = pickDashVideo(from: validVideos, preferredQuality: desiredVideoQuality)
            if let pickedVideo, let videoURL = URL.biliSecure(pickedVideo.baseUrl) {
                let validAudios = dash.allAudio.filter { URL.biliSecure($0.baseUrl) != nil }
                let pickedAudio = validAudios.first(where: { $0.id == desiredAudioQuality })
                    ?? validAudios.max { PlaybackQuality.audioRank($0.id) < PlaybackQuality.audioRank($1.id) }
                let audioURL = pickedAudio.flatMap { URL.biliSecure($0.baseUrl) }
                let totalDuration = dash.duration > 0 ? Double(dash.duration) : viewModel.duration
                let request = CastMediaRequest(
                    id: mediaID,
                    title: title,
                    subtitle: subtitle,
                    kind: .video,
                    startPosition: startPosition,
                    duration: totalDuration,
                    source: .remoteDualTrack(videoURL: videoURL, audioURL: audioURL, headers: headers)
                )
                return ResolvedOnlineCast(
                    request: request,
                    actualVideoQuality: pickedVideo.id,
                    actualAudioQuality: pickedAudio?.id
                )
            }
        }

        // 无 DASH 时回退单文件 durl。
        guard let rawURL = payload.durl?.first?.url,
              let mediaURL = URL.biliSecure(rawURL) else {
            throw CastError.mediaUnavailable(String(localized: "未获取到可投屏的视频地址"))
        }
        let durlDuration = payload.durl.map { Double($0.reduce(0) { $0 + ($1.length ?? 0) }) / 1_000 } ?? viewModel.duration
        let request = CastMediaRequest(
            id: mediaID,
            title: title,
            subtitle: subtitle,
            kind: .video,
            startPosition: startPosition,
            duration: durlDuration > 0 ? durlDuration : viewModel.duration,
            source: .remoteHTTP(url: mediaURL, headers: headers, mimeType: "video/mp4")
        )
        return ResolvedOnlineCast(
            request: request,
            actualVideoQuality: payload.quality ?? desiredVideoQuality,
            actualAudioQuality: nil
        )
    }

    private func pickDashVideo(from streams: [DashStream], preferredQuality: Int) -> DashStream? {
        guard !streams.isEmpty else { return nil }
        let matching = streams.filter { $0.id == preferredQuality }
        let pool: [DashStream]
        if !matching.isEmpty {
            pool = matching
        } else {
            let maxAvailable = streams.map(\.id).max() ?? preferredQuality
            pool = streams.filter { $0.id == maxAvailable }
        }
        // 优先 AVC > HEVC > AV1（电视硬件解码兼容性最佳），同编码选最高码率。
        return pool.sorted { lhs, rhs in
            let leftRank = castCodecRank(lhs.codecs)
            let rightRank = castCodecRank(rhs.codecs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.bandwidth > rhs.bandwidth
        }.first
    }

    private func castCodecRank(_ codec: String) -> Int {
        ["avc", "hvc", "hev", "av01"].firstIndex { codec.lowercased().hasPrefix($0) } ?? 4
    }

    private func exitCasting() {
        guard let castSession else { return }
        Task {
            let resumeTime = await castSession.stopCasting()
            if resumeTime > 0 {
                await viewModel.seek(to: resumeTime)
            }
            viewModel.play()
        }
    }
}
