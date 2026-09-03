import SwiftUI

/// The video surface plus our own `PlayerControlsOverlay` — no system
/// transport chrome. `VideoDetailView` reuses this same instance for both the
/// inline (portrait) and fullscreen (landscape) states, just resizing it —
/// that's what keeps playback uninterrupted across the transition.
struct InlineVideoPlayer: View {
    let viewModel: PlayerViewModel
    /// 列表卡片上那张封面。播放器拿到首帧之前先显示它，代替一整块黑屏。
    let coverURL: URL?
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

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

            if !viewModel.hasRenderedFirstFrame, let coverURL {
                BiliImage(url: coverURL)
                    .aspectRatio(contentMode: .fit)
            }

            if viewModel.hasRenderedFirstFrame {
                PlayerControlsOverlay(
                    viewModel: viewModel,
                    isFullScreen: isFullScreen,
                    onToggleFullScreen: onToggleFullScreen
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isLoading {
                ProgressView().tint(.white)
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView(
                    "无法播放",
                    systemImage: "play.slash",
                    description: Text(message)
                )
                .foregroundStyle(.white)
            }
        }
    }
}
