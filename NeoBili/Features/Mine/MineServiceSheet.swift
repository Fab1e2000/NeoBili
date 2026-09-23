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
        .videoPagePresenter(namespace: videoTransition)
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
