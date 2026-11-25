import NeoBiliDomain
import SwiftUI

/// Content only: the parent retains its scroll container, navigation and refresh tasks.
struct FollowingFeedContent: View {
    enum PlaceholderLayout {
        case centered
        case padded
    }

    let feed: DynamicFeedModel
    let showsAuthor: Bool
    let hidesPortraitVideos: Bool
    let filtering: VideoFilterDependencies
    let dynamicTransition: Namespace.ID
    let transitionPrefix: String
    let emptyTitle: LocalizedStringKey
    var placeholderLayout: PlaceholderLayout = .centered
    let onRetry: () -> Void
    let onLoadReplacement: () -> Void
    let onOpenVideo: (DynamicEntry) -> Void
    let onOpenAuthor: ((DynamicEntry) -> Void)?
    let onLike: (DynamicEntry) -> Void
    let onOpenDetail: (DynamicEntry) -> Void

    @ViewBuilder
    var body: some View {
        if feed.isLoading, feed.entries.isEmpty {
            LoadingTaskAnchor()
                .padding(.vertical, placeholderLayout == .padded ? 40 : 0)
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView {
                Label("动态加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                if placeholderLayout == .padded {
                    Button("重试", action: onRetry)
                } else {
                    Button("重试", action: onRetry).buttonStyle(.borderedProminent)
                }
            }
            .modifier(placeholderSpacing)
        } else if feed.entries.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "bell.slash")
                .modifier(placeholderSpacing)
        } else {
            if let message = feed.errorMessage {
                InlineLoadFailure(title: "动态未能刷新", message: message, onRetry: onRetry)
            }
            let visibleEntries = feed.entries.filter { $0.video?.canDisplayVideo(hidingPortrait: hidesPortraitVideos, filtering: filtering) ?? true }
            if visibleEntries.isEmpty {
                if feed.entries.compactMap(\.video).hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
                    LoadingTaskAnchor().padding()
                } else {
                    Button("继续加载动态") { onLoadReplacement() }
                        .padding()
                }
            }
            ForEach(visibleEntries) { entry in
                card(for: entry, lastVisibleID: visibleEntries.last?.id)
                    .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                    .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
            }

            if feed.isLoadingMore {
                LoadingTaskAnchor()
                    .padding()
            }
        }
    }

    private var placeholderSpacing: PlaceholderSpacing { .init(layout: placeholderLayout) }

    private struct PlaceholderSpacing: ViewModifier {
        let layout: PlaceholderLayout

        func body(content: Content) -> some View {
            if layout == .padded {
                content.padding(.vertical, 20)
            } else {
                content.frame(maxWidth: .infinity).frame(minHeight: 300)
            }
        }
    }

    private func card(for entry: DynamicEntry, lastVisibleID: String?) -> some View {
        DynamicFeedCard(
            entry: entry,
            feed: feed,
            lastVisibleID: lastVisibleID,
            onOpenVideo: { onOpenVideo(entry) },
            onOpenAuthor: onOpenAuthor.map { open in { open(entry) } },
            onLike: { onLike(entry) },
            onOpenDetail: { onOpenDetail(entry) },
            showsAuthor: showsAuthor
        )
        .videoTransitionSource(transitionPrefix + entry.id, in: dynamicTransition)
    }
}
