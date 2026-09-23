import SwiftUI

extension View {
    /// 以全屏模态呈现当前的视频页或直播间，从 `.player` 转场源 zoom 展开。
    ///
    /// 根视图和「我的」服务卡片各挂一份：服务卡片打开时由它承载视频页，
    /// 根视图让出（`isActive` 返回 false），关闭播放器后仍回到卡片里的列表。
    func videoPagePresenter(isActive: @escaping () -> Bool = { true }, namespace: Namespace.ID) -> some View {
        modifier(VideoPagePresenter(isActive: isActive, namespace: namespace))
    }
}

private struct VideoPagePresenter: ViewModifier {
    let isActive: () -> Bool
    let namespace: Namespace.ID
    @Environment(NowPlayingStore.self) private var nowPlaying

    func body(content: Content) -> some View {
        content.fullScreenCover(item: Binding(
            get: { isActive() ? nowPlaying.videoPresentation : nil },
            set: { destination in
                guard isActive() else { return }
                if destination != nil { nowPlaying.isExpanded = true }
                else { nowPlaying.dismissVideoPage() }
            }
        ), onDismiss: nowPlaying.finishDismissal) { _ in
            Group {
                if let player = nowPlaying.livePlayer {
                    LiveRoomView(player: player, keepsPlaybackOnDismiss: true,
                                 onReturn: nowPlaying.dismissVideoPage)
                } else {
                    VideoPage()
                }
            }
            .appTextSize()
            .presentationBackground(.clear)
            .presentationContentInteraction(.resizes)
            .navigationTransition(.zoom(sourceID: MediaPresentationState.Source.player, in: namespace))
            .environment(\.videoTransitionNamespace, namespace)
            .background {
                VideoPagePresentationObserver(
                    onDidAppear: nowPlaying.videoPageDidAppear,
                    onInteractionBegan: nowPlaying.videoPageInteractionBegan,
                    onInteractionEnded: nowPlaying.videoPageInteractionEnded
                )
            }
        }
    }
}
