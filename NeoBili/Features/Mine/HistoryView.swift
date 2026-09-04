import SwiftUI

/// 观看历史，游标翻页。
///
/// 结构与首页保持同构（ScrollView + 卡片 Button + 转场源直接挂在
/// Button 上），这样点开/退出视频页的 zoom 动效和首页完全一致。
struct HistoryView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var items: [HistoryItem] = []
    @State private var cursorMax = 0
    @State private var cursorViewAt = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("历史加载失败", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload() } }
                }
            } else if !hasMore, items.isEmpty {
                ContentUnavailableView("还没有观看记录", systemImage: "clock.arrow.circlepath")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                        }
                        if isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 12)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, items.isEmpty { ProgressView() }
        }
        .refreshable { await reload() }
        .task { await loadIfNeeded() }
    }

    private func row(_ item: HistoryItem) -> some View {
        let summary = item.asVideoSummary

        return Button {
            guard let summary else { return }
            // 历史自带 cid，可直接并行取详情和播放地址；缺 cid 的条目传 nil 让详情页补。
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name
                ),
                from: "history-\(summary.bvid)"
            )
        } label: {
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: item.displayTitle,
                author: item.authorName ?? "",
                playCount: -1,
                durationText: summary?.formattedDuration ?? ""
            )
            .contextMenu {
                Button(role: .destructive) {
                    Task { await delete(item) }
                } label: {
                    Label("删除这条历史", systemImage: "trash")
                }
            }
        }
        .buttonStyle(.plain)
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        .videoTransitionSource("history-\(summary?.bvid ?? "")", in: videoTransition)
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            await loadMoreIfNeeded(current: item)
            if let summary {
                await VideoPreparationCache.shared.prefetch(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil
                )
            }
        }
    }

    private func loadIfNeeded() async {
        guard items.isEmpty, !isLoading else { return }
        await reload()
    }

    private func reload() async {
        cursorMax = 0
        cursorViewAt = 0
        hasMore = true
        items = []
        await loadNextPage()
    }

    private func loadMoreIfNeeded(current item: HistoryItem) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoadingMore else { return }
        isLoading = items.isEmpty
        isLoadingMore = !items.isEmpty
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let payload = try await BiliAPI.historyPage(max: cursorMax, viewAt: cursorViewAt)
            let incoming = payload.allItems.filter(\.isVideo)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: incoming.filter { !existing.contains($0.id) })

            if let cursor = payload.cursor, let nextMax = cursor.max, nextMax > 0 {
                cursorMax = nextMax
                cursorViewAt = cursor.resolvedViewAt ?? 0
            } else {
                hasMore = false
            }
            if incoming.isEmpty {
                hasMore = false
            }
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
            hasMore = false
        }
    }

    private func delete(_ item: HistoryItem) async {
        do {
            try await BiliAPI.deleteHistory(kid: item.kidParam)
            withAnimation { items.removeAll { $0.id == item.id } }
        } catch {
            // 失败保持原样。
        }
    }
}
