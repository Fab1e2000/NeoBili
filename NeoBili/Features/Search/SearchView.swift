import SwiftUI

struct SearchView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @State private var viewModel = SearchViewModel()
    @State private var isSearchPresented = false
    @State private var isOpeningVideo = false

    var body: some View {
        NavigationStack {
            List(viewModel.results) { item in
                Button {
                    Task { @MainActor in
                        // 搜索栏收起期间禁止再次点卡片，避免同一个视频被连续推入两次。
                        guard !isOpeningVideo else { return }
                        isOpeningVideo = true
                        defer { isOpeningVideo = false }

                        // 先结束系统搜索状态，再使用和首页完全相同的视频路由进入详情页。
                        // 系统搜索栏有自己的收起动画；必须等动画结束，导航栏占用的高度才真正释放。
                        if isSearchPresented {
                            isSearchPresented = false
                            try? await Task.sleep(for: .milliseconds(300))
                        }

                        guard !Task.isCancelled else { return }
                        nowPlaying.open(
                            VideoDetailRoute(
                                bvid: item.bvid,
                                cover: item.pic,
                                title: item.plainTitle,
                                artist: item.author
                            ),
                            from: item.bvid
                        )
                    }
                } label: {
                    VideoListCard(
                        coverURL: item.secureCoverURL,
                        title: item.plainTitle,
                        author: item.author,
                        playCount: item.play,
                        durationText: item.duration
                    )
                }
                .disabled(isOpeningVideo)
                .buttonStyle(.plain)
                .videoTransitionSource(item.bvid, in: videoTransition)
                // 搜索结果里没有 cid，所以预取要先取一次详情再取播放地址。
                // 详情会一起缓存下来，进入视频页时不会重复请求。
                .task { await VideoPreparationCache.shared.prefetch(bvid: item.bvid) }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(
                        top: VideoListCardLayout.cardVerticalSpacing,
                        leading: VideoListCardLayout.pageHorizontalInset,
                        bottom: VideoListCardLayout.cardVerticalSpacing,
                        trailing: VideoListCardLayout.pageHorizontalInset
                    )
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if let message = viewModel.errorMessage {
                    ContentUnavailableView("搜索失败", systemImage: "exclamationmark.triangle", description: Text(message))
                } else if viewModel.results.isEmpty && !viewModel.query.isEmpty {
                    ContentUnavailableView.search
                }
            }
            // 不显示“搜索”标题。空标题加 inline 模式后，导航栏只剩下搜索框需要的那一行高度。
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.query,
                isPresented: $isSearchPresented,
                prompt: "搜索视频"
            )
            .onSubmit(of: .search) {
                // 按下键盘上的“搜索”后立即收起键盘并释放搜索焦点。
                // 如果不主动关闭，系统会吞掉用户对第一张视频卡片的第一次点击。
                isSearchPresented = false
                viewModel.submit()
            }
            .onAppear {
                OrientationController.enterPortrait()
            }
        }
    }
}

#Preview {
    SearchView()
        .environment(NowPlayingStore())
}
