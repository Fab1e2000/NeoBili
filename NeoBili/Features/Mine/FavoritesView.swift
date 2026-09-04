import SwiftUI

/// 收藏夹列表（账号创建的全部收藏夹，含默认收藏夹）。
struct FavoritesView: View {
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @State private var folders: [FavFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// 待删除的收藏夹。删整个收藏夹是不可撤销的，所以要先确认一次。
    @State private var folderPendingDeletion: FavFolder?

    var body: some View {
        Group {
            if let errorMessage, folders.isEmpty {
                ContentUnavailableView {
                    Label("收藏加载失败", systemImage: "star.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else if !isLoading, folders.isEmpty {
                ContentUnavailableView("还没有收藏夹", systemImage: "star")
            } else {
                List {
                    ForEach(folders) { folder in
                        NavigationLink {
                            FavoriteFolderView(folder: folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.orange)
                                Text(folder.title)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(folder.mediaCount) 个内容")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // 和「取消收藏」同一种交互：长按弹菜单。
                        .contextMenu {
                            Button(role: .destructive) {
                                folderPendingDeletion = folder
                            } label: {
                                Label("删除收藏夹", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触条目。
        .leftEdgeTapDeadZone()
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        // 二级页面不该再顶着底部标签栏。系统会让它跟着导航转场一起滑走，
        // 返回时再滑回来，和 iOS 内置 App 的行为一致。
        .toolbar(.hidden, for: .tabBar)
        .overlay {
            if isLoading, folders.isEmpty { ProgressView() }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            // 删掉收藏夹会连同里面的内容一起没掉，而且没有撤销，所以问一句。
            "删除「\(folderPendingDeletion?.title ?? "")」后，里面的 \(folderPendingDeletion?.mediaCount ?? 0) 个内容也会一并消失，且无法恢复。",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除收藏夹", role: .destructive) {
                if let folder = folderPendingDeletion {
                    Task { await delete(folder) }
                }
                folderPendingDeletion = nil
            }
            Button("取消", role: .cancel) { folderPendingDeletion = nil }
        }
    }

    private func delete(_ folder: FavFolder) async {
        do {
            try await BiliAPI.deleteFavoriteFolders(folderIDs: [folder.id])
            withAnimation { folders.removeAll { $0.id == folder.id } }
            feedback.show("已删除收藏夹")
        } catch {
            feedback.show(error.localizedDescription)
        }
    }

    private func load() async {
        guard let mid = account.profile?.mid else {
            errorMessage = "登录状态已失效，请重新登录"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            folders = try await BiliAPI.favoriteFolders(ownerMid: mid)
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// 单个收藏夹里的内容。卡片沿用搜索页/相关视频页的 `VideoListCard`，
/// 结构与首页同构（ScrollView + Button + 转场源紧跟 buttonStyle），
/// 保证 zoom 动效和首页完全一致。
struct FavoriteFolderView: View {
    let folder: FavFolder

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var videos: [FavMedia] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    /// 正在走移除动效的条目。第一段淡出靠它驱动，见 `remove`。
    @State private var removingIDs: Set<Int> = []

    var body: some View {
        Group {
            if let errorMessage, videos.isEmpty {
                ContentUnavailableView {
                    Label("内容加载失败", systemImage: "star.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload() } }
                }
            } else if !isLoading, !hasMore, videos.isEmpty {
                ContentUnavailableView("收藏夹是空的", systemImage: "star")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(videos) { media in
                            row(media)
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
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay {
            if isLoading, videos.isEmpty { ProgressView() }
        }
        .refreshable { await reload() }
        .task { await loadIfNeeded() }
    }

    private func row(_ media: FavMedia) -> some View {
        let summary = media.asVideoSummary

        return Button {
            guard let summary else { return }
            // 收藏接口没有 cid，必须传 nil 让详情页去取（传 0 会让播放器拿空 cid 取流）。
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name
                ),
                from: "fav-\(summary.bvid)"
            )
        } label: {
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: media.title,
                author: media.upper?.name ?? "",
                playCount: media.cntInfo?.play ?? -1,
                durationText: summary?.formattedDuration ?? ""
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            WatchLaterMenuButton(aid: media.id, bvid: media.bvid)

            Button(role: .destructive) {
                Task { await remove(media) }
            } label: {
                Label("取消收藏", systemImage: "star.slash")
            }
        }
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        .videoTransitionSource("fav-\(summary?.bvid ?? "")", in: videoTransition)
        // 移除动效第一段：原地淡出、占位不变，列表此时不动。
        .cardFadeOut(isRemoving: removingIDs.contains(media.id))
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            await loadMoreIfNeeded(current: media)
            if let summary {
                // 收藏没有 cid，预取会先取一次详情再取播放地址。
                await VideoPreparationCache.shared.prefetch(bvid: summary.bvid)
            }
        }
    }

    private func loadIfNeeded() async {
        guard videos.isEmpty, !isLoading else { return }
        await reload()
    }


    /// 下拉刷新和「重试」都走这里。
    ///
    /// 注意**不要**先把 `videos` 清空再去请求：列表内容一变，下拉刷新那个由
    /// SwiftUI 持有的任务就会被取消，请求随之失败，页面弹出「加载失败」；
    /// 而点「重试」是另起一个不受牵连的任务，所以反而能成功。改成拿到数据
    /// 之后再整体替换，顺带也没有了刷新过程中的白屏。
    private func reload() async {
        isLoading = videos.isEmpty
        defer { isLoading = false }
        do {
            let payload = try await BiliAPI.favoriteVideos(folderID: folder.id, page: 1)
            let incoming = (payload.medias ?? []).filter(\.isVideo)
            videos = incoming
            page = 2
            hasMore = incoming.count >= 20
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            if videos.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func loadMoreIfNeeded(current media: FavMedia) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard videos.suffix(5).contains(where: { $0.id == media.id }) else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoadingMore else { return }
        isLoading = videos.isEmpty
        isLoadingMore = !videos.isEmpty
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let payload = try await BiliAPI.favoriteVideos(folderID: folder.id, page: page)
            let incoming = (payload.medias ?? []).filter(\.isVideo)
            let existing = Set(videos.map(\.id))
            videos.append(contentsOf: incoming.filter { !existing.contains($0.id) })
            // 不足一页说明到底了。
            hasMore = incoming.count >= 20
            page += 1
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            if videos.isEmpty { errorMessage = error.localizedDescription }
            hasMore = false
        }
    }

    /// 同 `HistoryView.delete`：先移走卡片再发请求，失败了放回原位。
    /// 成功时不弹提示——卡片消失本身就是反馈。
    ///
    /// 动效拆成两段顺序执行（`CardRemovalAnimation`）：先原地淡出，完全
    /// 看不见后空位才收拢、下方卡片上移补位——两段同时进行会出现叠影。
    private func remove(_ media: FavMedia) async {
        guard let index = videos.firstIndex(where: { $0.id == media.id }) else { return }

        withAnimation(CardRemovalAnimation.fade) { removingIDs.insert(media.id) }
        try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.fadeMilliseconds))

        withAnimation(CardRemovalAnimation.collapse) { videos.remove(at: index) }

        do {
            try await BiliAPI.removeFavorite(folderID: folder.id, aid: media.id)
            // 等退出转场走完再清标记，避免同 id 的卡片被残留标记隐藏。
            try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.collapseMilliseconds))
            removingIDs.remove(media.id)
        } catch {
            removingIDs.remove(media.id)
            withAnimation { videos.insert(media, at: min(index, videos.count)) }
            // 以前这里静默吞掉了错误，接口早就在报「参数错误」也看不出来。
            feedback.show(error.localizedDescription)
        }
    }
}
