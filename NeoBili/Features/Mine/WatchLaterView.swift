import SwiftUI

/// 稍后再看列表。接口一次性返回全部内容，不需要分页。
/// 卡片沿用搜索页/相关视频页的 `VideoListCard`，结构与首页同构
/// （ScrollView + Button + 转场源紧跟 buttonStyle），zoom 动效和首页一致。
struct WatchLaterView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var items: [WatchLaterItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("稍后再看加载失败", systemImage: "flag.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload() } }
                }
            } else if !isLoading, items.isEmpty {
                ContentUnavailableView("稍后再看是空的", systemImage: "flag.checkered")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle("稍后再看")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, items.isEmpty { ProgressView() }
        }
        .refreshable { await reload() }
        .task { await loadIfNeeded() }
    }

    private func row(_ item: WatchLaterItem) -> some View {
        let summary = item.asVideoSummary

        return Button {
            guard let summary else { return }
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name
                ),
                from: "wl-\(summary.bvid)"
            )
        } label: {
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: item.title,
                author: item.upper?.name ?? "",
                playCount: -1,
                durationText: summary?.formattedDuration ?? ""
            )
            .contextMenu {
                Button(role: .destructive) {
                    Task { await remove(item) }
                } label: {
                    Label("移出稍后再看", systemImage: "flag.slash")
                }
            }
        }
        .buttonStyle(.plain)
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        .videoTransitionSource("wl-\(summary?.bvid ?? "")", in: videoTransition)
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
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
        isLoading = true
        defer { isLoading = false }
        do {
            let payload = try await BiliAPI.watchLaterList()
            items = (payload.list ?? []).filter { $0.bvid?.isEmpty == false }
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func remove(_ item: WatchLaterItem) async {
        guard let aid = item.aid else { return }
        do {
            try await BiliAPI.removeWatchLater(aid: aid)
            withAnimation { items.removeAll { $0.id == item.id } }
        } catch {
            // 失败保持原样。
        }
    }
}
