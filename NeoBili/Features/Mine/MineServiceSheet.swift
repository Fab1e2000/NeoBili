import SwiftUI

enum MineService: String, Identifiable {
    case favorites, history, watchLater, settings
    var id: String { rawValue }
}

/// 原生卡片式呈现。导航和视频页都由卡片承载，关闭播放器后仍回到原列表。
struct MineServiceSheet: View {
    let service: MineService
    @Environment(\.dismiss) private var dismiss
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Namespace private var videoTransition

    var body: some View {
        @Bindable var nowPlaying = nowPlaying

        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
        .environment(\.videoTransitionNamespace, videoTransition)
        .actionFeedbackOverlay()
        .miniPlayerHost(isActive: { nowPlaying.isServiceSheetPresented }, transitionNamespace: videoTransition)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .mediaZoomCover(isPresented: Binding(
            get: { nowPlaying.isExpanded },
            set: { if $0 { nowPlaying.isExpanded = true } else { nowPlaying.dismissVideoPage() } }
        ), entrySourceID: nowPlaying.transitionSourceID, namespace: videoTransition,
           onDismiss: nowPlaying.finishDismissal) {
            Group {
                if let player = nowPlaying.livePlayer {
                    LiveRoomView(player: player, keepsPlaybackOnDismiss: true,
                                 onReturn: nowPlaying.dismissVideoPage)
                } else {
                    VideoPage()
                }
            }
                .appTextSize()
                .environment(\.videoTransitionNamespace, videoTransition)
                .background { VideoPagePresentationObserver(
                    onDidAppear: nowPlaying.videoPageDidAppear,
                    onInteractionBegan: nowPlaying.videoPageInteractionBegan,
                    onInteractionEnded: nowPlaying.videoPageInteractionEnded
                ) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service {
        case .favorites: FavoritesView()
        case .history: HistoryView()
        case .watchLater: WatchLaterView()
        case .settings: SettingsView()
        }
    }
}
