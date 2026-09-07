import SwiftUI

/// 搜索结果列表。
///
/// 它不含搜索框——搜索框是首页那个系统原生的 `.searchable`，这里只负责把
/// 结果画出来。首页在「搜过东西」时用它替换推荐流，取消搜索后再换回去。
struct SearchResultsView: View {
    /// 和首页共用同一个视图模型：搜索框、候选词、结果都挂在它上面。
    let viewModel: SearchViewModel

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(\.videoTransitionNamespace) private var videoTransition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.results) { item in
                    Button {
                        nowPlaying.open(
                            VideoDetailRoute(
                                bvid: item.bvid,
                                cover: item.pic,
                                title: item.plainTitle,
                                artist: item.author
                            ),
                            from: item.bvid
                        )
                    } label: {
                        VideoListCard(
                            coverURL: item.secureCoverURL,
                            title: item.plainTitle,
                            author: item.author,
                            playCount: item.play,
                            durationText: item.duration
                        )
                    }
                    .buttonStyle(.plain)
                    // 搜索结果没有 avid，稍后再看接口用 bvid 也能加。
                    .contextMenu {
                        WatchLaterMenuButton(bvid: item.bvid)
                    }
                    // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。
                    .videoTransitionSource(item.bvid, in: videoTransition)
                    .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                    .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                    // 搜索结果里没有 cid，所以预取要先取一次详情再取播放地址。
                    // 详情会一起缓存下来，进入视频页时不会重复请求。
                    .task { await VideoPreparationCache.shared.prefetch(bvid: item.bvid) }
                }
                if let message = viewModel.loadMoreError {
                    VStack(spacing: 8) {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                        Button("重试加载") { Task { await viewModel.loadMore() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else if viewModel.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .task(id: viewModel.pageNumber) { await viewModel.loadMore() }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView(
                    "搜索失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else if viewModel.results.isEmpty {
                ContentUnavailableView.search(text: viewModel.submittedKeyword)
            }
        }
    }
}
