import SwiftUI

/// The video surface plus our own `PlayerControlsOverlay` — no system
/// transport chrome. `VideoDetailView` reuses this same instance for both the
/// inline and fullscreen states, just resizing it —
/// that's what keeps playback uninterrupted across the transition.
struct InlineVideoPlayer: View {
    let viewModel: PlayerViewModel
    @Binding var controlsVisible: Bool
    /// 列表卡片上那张封面。播放器拿到首帧之前先显示它，代替一整块黑屏。
    let coverURL: URL?
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    var onToggleCompact: (() -> Void)? = nil
    var isCompact = false
    var controlsSafeAreaInsets = EdgeInsets()
    var onDismiss: (() -> Void)? = nil
    var videoTitle = ""
    var videoSubtitle = ""
    var shareURL: URL?

    @AppStorage(DanmakuSettings.videoEnabledKey) private var danmakuEnabled = DanmakuSettings.defaultValue

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
                DanmakuView(controller: danmaku, isFullScreen: isFullScreen, isSuppressed: isCompact)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if !viewModel.hasRenderedFirstFrame, let coverURL {
                BiliImage(url: coverURL)
                    .aspectRatio(contentMode: .fit)
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
            PlayerControlsOverlay(
                viewModel: viewModel,
                controlsVisible: $controlsVisible,
                isFullScreen: isFullScreen,
                onToggleFullScreen: onToggleFullScreen,
                onToggleCompact: onToggleCompact,
                isCompact: isCompact,
                controlsSafeAreaInsets: controlsSafeAreaInsets,
                onDismiss: onDismiss,
                videoTitle: videoTitle,
                videoSubtitle: videoSubtitle,
                shareURL: shareURL
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { syncDanmaku() }
        .onChange(of: viewModel.hasRenderedFirstFrame) { syncDanmaku() }
        .onChange(of: danmakuEnabled) { syncDanmaku() }
        // 换视频（相关视频、换P）会换掉整个 PlayerViewModel，但本视图身份
        // 不变——onAppear 和 onChange 都不会再触发，必须跟着播放器实例走。
        .task(id: ObjectIdentifier(viewModel)) { syncDanmaku() }
    }

    /// 开关状态与控制器保持一致：打开时确保已创建并加载，关闭时立即释放。
    private func syncDanmaku() {
        if !danmakuEnabled { viewModel.disableDanmaku() }
        else if viewModel.hasRenderedFirstFrame { viewModel.ensureDanmaku() }
    }
}
