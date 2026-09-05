import SwiftUI

/// 稍后再看列表。接口一次性返回全部内容，不需要分页。
/// 卡片沿用搜索页/相关视频页的 `VideoListCard`，结构与首页同构
/// （ScrollView + Button + 转场源紧跟 buttonStyle），zoom 动效和首页一致。
struct WatchLaterView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var items: [WatchLaterItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 正在走移除动效的条目。第一段淡出靠它驱动，见 `remove`。
    @State private var removingIDs: Set<Int> = []

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
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
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
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await remove(item) }
            } label: {
                Label("移出稍后再看", systemImage: "flag.slash")
            }
        }
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        //
        // 已知系统问题（iOS 26/27，摘掉转场源也复现）：A 的长按菜单还在
        // 退场时立刻长按 B，弹出的胶囊还是 A 的菜单项，点「移出」删掉的是
        // A。应用侧无法分辨菜单归属，只能等菜单完全收起再长按下一张卡。
        .videoTransitionSource("wl-\(summary?.bvid ?? "")", in: videoTransition)
        // 移除动效第一段：原地淡出、占位不变，列表此时不动。
        .cardFadeOut(isRemoving: removingIDs.contains(item.id))
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
            guard !error.isCancellation else { return }
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    /// 同 `HistoryView.delete`：先移走卡片再发请求，失败了放回原位。
    ///
    /// 动效拆成两段顺序执行（`CardRemovalAnimation`）：先原地淡出，完全
    /// 看不见后空位才收拢、下方卡片上移补位——两段同时进行会出现叠影。
    private func remove(_ item: WatchLaterItem) async {
        guard let aid = item.aid,
              let index = items.firstIndex(where: { $0.id == item.id })
        else { return }

        // 先等长按菜单退场快照掀开，否则淡出被盖在快照后面看不见。
        try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.menuDismissWaitMilliseconds))
        withAnimation(CardRemovalAnimation.fade) { removingIDs.insert(item.id) }
        try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.fadeMilliseconds))

        withAnimation(CardRemovalAnimation.collapse) { items.remove(at: index) }

        do {
            try await BiliAPI.removeWatchLater(aid: aid)
            // 等退出转场走完再清标记，避免同 id 的卡片被残留标记隐藏。
            try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.collapseMilliseconds))
            removingIDs.remove(item.id)
        } catch {
            removingIDs.remove(item.id)
            withAnimation { items.insert(item, at: min(index, items.count)) }
            feedback.show(error.localizedDescription)
        }
    }
}
