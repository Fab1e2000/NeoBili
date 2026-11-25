import NeoBiliDomain
import SwiftUI

struct SpaceCollectionDetailView: View {
    @Environment(\.videoPreparation) private var preparation
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @State private var model: SpaceCollectionDetailModel
    @State private var refresh = ListRefreshController()
    private let authorName: String
    @State private var position = ScrollPosition(edge: .top)

    init(collection: SpaceCollectionSummary, hostMID: Int, authorName: String, services: ApplicationServices,
         filtering: VideoFilterDependencies) {
        self.authorName = authorName
        _model = State(initialValue: SpaceCollectionDetailModel(collection: collection, hostMID: hostMID,
                                                               services: services, filtering: filtering))
    }

    var body: some View {
        let orderTitle: LocalizedStringKey = model.sortReverse ? "倒序" : "正序"
        ScrollView {
            LazyVStack(spacing: 0) { archiveList }
                .resolvePortraitVideos(model.archives, batchID: model.list.generation, providesEntrance: false) {
                    await model.loadReplacementPage()
                    return model.archives
                }
                .frame(maxWidth: .infinity)
                .background {
                    ListPullRefresh(enabled: !refresh.isRefreshing && !model.list.isLoading, onRefresh: startRefresh)
                }
        }
        .scrollPosition($position)
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(model.collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refresh.reset(discard: model.discardRefresh)
                    model.toggleSort()
                    position.scrollTo(edge: .top)
                } label: {
                    Text(orderTitle)
                }
                .accessibilityLabel("分集排序")
                .accessibilityValue(Text(orderTitle))
            }
        }
        .environment(\.videoFiltering, model.filtering)
        .task(id: model.sortReverse) { await model.loadIfNeeded() }
        .onDisappear { refresh.reset(discard: model.discardRefresh) }
        .leftEdgeTapDeadZone()
    }

    @ViewBuilder
    private var archiveList: some View {
        let list = model.list
        let visible = model.archives.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: model.filtering)

        if let message = list.errorMessage {
            InlineLoadFailure(title: "分集加载失败", message: message, isRetryDisabled: list.isLoading) {
                Task { await model.reload() }
            }
        } else if visible.isEmpty {
            if !list.hasLoadedCurrentOrder || list.isLoading || list.isLoadingMore
                || model.archives.hasPendingVideoDimensions(hidesPortraitVideos, filtering: model.filtering) {
                LoadingTaskAnchor().padding(.vertical, 40)
            } else {
                ContentUnavailableView(model.archives.isEmpty ? "没有分集" : "没有可显示的视频", systemImage: "video.slash")
                    .padding(.vertical, 20)
            }
        }

        ForEach(visible) { video in
            Button {
                nowPlaying.open(
                    VideoDetailRoute(bvid: video.bvid, cover: video.pic, title: video.title,
                                     artist: authorName, playbackEntry: .spaceVideo),
                    from: video.bvid
                )
            } label: {
                VideoListCard(coverURL: URL.biliSecure(video.pic), title: video.title,
                              author: video.pubdate > 0 ? video.pubdate.biliRelativeTimeText : "",
                              playCount: video.viewCount, durationText: video.durationText, animatesEntrance: false)
            }
            .buttonStyle(CardPressStyle(cornerRadius: VideoListCardLayout.cardCornerRadius))
            .contextMenu {
                WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
            }
            .videoTransitionSource(video.bvid, in: videoTransition)
            .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
            .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
            .task(id: list.generation) {
                await model.loadMoreIfNeeded(current: video, hidingKnownPortraitVideos: hidesPortraitVideos)
            }
            .task { await preparation.prefetchWhenSettled(bvid: video.bvid) }
        }

        if list.isLoadingMore, !visible.isEmpty {
            LoadingTaskAnchor().padding()
        } else if let message = list.paginationError {
            InlineLoadFailure(title: "更多分集加载失败", message: message, isRetryDisabled: list.isLoading) {
                Task { await model.loadReplacementPage() }
            }
        } else if list.canLoadMore {
            Button("加载更多") { Task { await model.loadReplacementPage() } }
                .padding()
        }
    }

    private func startRefresh() {
        refresh.start(hasContent: !model.archives.isEmpty, animatesExit: false, source: .space,
                      fetch: model.stageRefresh, commit: model.commitRefresh, discard: model.discardRefresh)
    }
}
