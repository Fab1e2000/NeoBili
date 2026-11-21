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
        .onChange(of: castMediaID) { oldID, _ in
            guard let castSession else { return }
            Task { await castSession.stopIfCasting(mediaID: oldID) }
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

    private func startCasting(to device: CastDevice) {
        guard let castSession else { return }
        let mediaID = castMediaID
        let title = videoTitle.isEmpty ? viewModel.bvid : videoTitle
        let subtitle = videoSubtitle
        let startPosition = viewModel.currentTime
        let quality = viewModel.selectedVideoQuality ?? 80
        let offline = viewModel.offline
        let bvid = viewModel.bvid
        let cid = viewModel.cid

        Task {
            do {
                let request: CastMediaRequest
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
                        source: source
                    )
                } else {
                    let payload = try await services.video.castPlayURL(bvid: bvid, cid: cid, quality: quality)
                    guard let rawURL = payload.durl?.first?.url,
                          let mediaURL = URL.biliSecure(rawURL) else {
                        throw CastError.mediaUnavailable(String(localized: "未获取到可投屏的视频地址"))
                    }
                    let headers = [
                        "Referer": "https://www.bilibili.com",
                        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
                    ]
                    request = CastMediaRequest(
                        id: mediaID,
                        title: title,
                        subtitle: subtitle,
                        kind: .video,
                        startPosition: startPosition,
                        source: .remoteHTTP(url: mediaURL, headers: headers, mimeType: "video/mp4")
                    )
                }

                let started = await castSession.startCasting(device: device, media: request)
                if started {
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
