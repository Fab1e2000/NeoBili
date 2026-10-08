import SwiftUI

/// 收藏夹列表（账号创建的全部收藏夹，含默认收藏夹）。
struct FavoritesView: View {
    @Environment(\.applicationServices) private var services
    @Environment(AccountStore.self) private var account
    @Environment(\.scrollingPageHeader) private var scrollingPageHeader
    @Environment(ActionFeedback.self) private var feedback
    @State private var folders: [FavFolder] = []
    @State private var folderRemovals = ListRemovalState<Int>()
    @State private var isLoading = false
    @State private var loadID = UUID()
    @State private var ownerSession: UUID?
    @State private var errorMessage: String?
    /// 待删除的收藏夹。提交后不可恢复，保留确认和短暂撤销窗口。
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
                .scrollingPageHeaderAbove()
            } else if !isLoading, folders.isEmpty {
                ContentUnavailableView("还没有收藏夹", systemImage: "star")
                    .scrollingPageHeaderAbove()
            } else {
                List {
                    // List 会给空内容也留一行，只在确实有页头时插入。
                    if scrollingPageHeader != nil {
                        ScrollingPageHeaderRow()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
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
                                Text(String(localized: "\(folder.mediaCount) 个内容"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // 和「取消收藏」同一种交互：长按弹菜单。
                        .buttonStyle(.plain)
        .contextMenu {
                            Button(role: .destructive) {
                                folderPendingDeletion = folder
                            } label: {
                                Label("删除收藏夹", systemImage: "trash")
                            }
                        }
                    }
                }
                .tracksPageHeaderPull()
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触条目。
        .leftEdgeTapDeadZone()
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, folders.isEmpty { LoadingTaskAnchor() }
        }
        .task(id: account.sessionID) {
            if ownerSession != account.sessionID {
                ownerSession = account.sessionID
                loadID = UUID()
                folders = []
                folderPendingDeletion = nil
                folderRemovals = ListRemovalState<Int>()
                isLoading = false
            }
            await load()
        }
        .refreshable { await load() }
        .confirmationDialog(
            // 整个收藏夹的删除提交后不可恢复，先说明影响范围。
            String(localized: "删除「\(folderPendingDeletion?.title ?? "")」后，里面的 \(folderPendingDeletion?.mediaCount ?? 0) 个内容也会一并消失。可在提示中撤销，提交后无法恢复。"),
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
        guard folderRemovals.begin(folder.id) else { return }
        let sessionID = account.sessionID
        let identitySession = services.session.currentID()
        defer { if account.sessionID == sessionID { folderRemovals.finish(folder.id) } }
        let removedIndex = folderRemovals.remove(folder.id, from: &folders)
        do {
            guard await feedback.confirmRemoval(String(localized: "已移除收藏夹")),
                  account.sessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
            try await services.library.deleteFavoriteFolders(folderIDs: [folder.id], expectedSessionID: identitySession)
        } catch {
            if account.sessionID == sessionID, let removedIndex {
                folderRemovals.restore(folder, at: removedIndex, in: &folders)
            }
            if account.sessionID == sessionID, !error.isCancellation { feedback.show(error.localizedDescription) }
        }
    }

    private func load() async {
        guard !folderRemovals.hasPending, !isLoading else { return }
        let requestID = UUID()
        loadID = requestID
        let sessionID = account.sessionID
        let revision = folderRemovals.revision
        guard let mid = account.accountID else {
            errorMessage = String(localized: "登录状态已失效，请重新登录")
            return
        }
        isLoading = true
        errorMessage = nil
        defer { if loadID == requestID { isLoading = false } }
        do {
            let result = try await services.library.favoriteFolders(ownerMid: mid)
            guard loadID == requestID, account.sessionID == sessionID, folderRemovals.revision == revision, !Task.isCancelled else { return }
            folders = LibraryPageRules.unique(result)
        } catch {
            guard loadID == requestID, account.sessionID == sessionID, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }
}

/// 单个收藏夹里的内容。卡片沿用搜索页/相关视频页的 `VideoListCard`，
/// 结构与首页同构（ScrollView + Button + 转场源紧跟 buttonStyle），
/// 保证 zoom 动效和首页完全一致。
struct FavoriteFolderView: View {
    @Environment(\.applicationServices) private var services
    let folder: FavFolder

    @Environment(AccountStore.self) private var account
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    @State private var videos: [FavMedia] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    /// 正在走移除动效的条目。第一段淡出靠它驱动，见 `remove`。
    @State private var removals = ListRemovalState<Int>()
    @State private var loadID = UUID()
    @State private var entranceGeneration = 0
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @State private var isRemovingSelected = false

    private var visibleVideos: [FavMedia] {
        videos.hidingKnownPortraitVideos(hidesPortraitVideos)
    }

    var body: some View {
        let visibleVideos = visibleVideos
        let paginationIDs = Set(visibleVideos.suffix(5).map(\.id))
        Group {
            if visibleVideos.isEmpty, videos.hasPendingVideoDimensions(hidesPortraitVideos) {
                LoadingTaskAnchor()
            } else if let errorMessage, videos.isEmpty {
                ContentUnavailableView {
                    Label("内容加载失败", systemImage: "star.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload() } }
                }
            } else if !isLoading, !hasMore, visibleVideos.isEmpty {
                ContentUnavailableView(
                    videos.isEmpty ? "收藏夹是空的" : "没有可显示的视频",
                    systemImage: videos.isEmpty ? "star" : "rectangle.slash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleVideos) { media in
                            row(media, loadsNextPage: paginationIDs.contains(media.id))
                        }
                        if hasMore, !isLoadingMore {
                            Button("继续加载") { Task { await loadNextPage() } }
                                .padding(.vertical, 12)
                                .disabled(isLoading)
                        }
                        if isLoadingMore {
                            LoadingTaskAnchor()
                                .padding(.vertical, 12)
                        }
                        if let errorMessage, !videos.isEmpty {
                            VStack(spacing: 8) {
                                Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                                Button("重试加载") { Task { await loadNextPage() } }
                                    .disabled(isLoading || isLoadingMore)
                            }
                            .padding()
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
        .overlay {
            if isLoading, videos.isEmpty { LoadingTaskAnchor() }
        }
        .refreshable { await reload() }
        .task { await loadIfNeeded() }
        .resolvePortraitVideos(videos, batchID: entranceGeneration) {
            guard hasMore, errorMessage == nil else { return videos }
            await loadNextPage()
            return videos
        }
        .videoCardAnimationSource(.favorites)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                LibrarySelectionBar(count: selectedIDs.count,
                    isBusy: isRemovingSelected || isLoading || isLoadingMore,
                    done: { isSelecting = false; selectedIDs = [] }) {
                    Task { await removeSelected() }
                }
            }
        }
        .onChange(of: account.sessionID) { _, _ in
            loadID = UUID()
            videos = []; selectedIDs = []; isSelecting = false
            isLoading = false; isLoadingMore = false
            isRemovingSelected = false
            removals = ListRemovalState()
            hasMore = true
            errorMessage = nil
            Task { await reload() }
        }
    }

    private func row(_ media: FavMedia, loadsNextPage: Bool) -> some View {
        let summary = media.asVideoSummary

        return Button {
            if isSelecting {
                guard !isRemovingSelected else { return }
                if selectedIDs.contains(media.id) { selectedIDs.remove(media.id) }
                else { selectedIDs.insert(media.id) }
                return
            }
            guard let summary else { return }
            // 收藏接口没有 cid，必须传 nil 让详情页去取（传 0 会让播放器拿空 cid 取流）。
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name, aid: summary.aid, playbackEntry: .favorites
                ),
                from: "fav-\(summary.bvid)"
            )
        } label: {
            HStack(spacing: 8) {
                if isSelecting {
                    Image(systemName: selectedIDs.contains(media.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selectedIDs.contains(media.id) ? Color.accentColor : .secondary)
                }
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: media.title,
                author: media.upper?.name ?? "",
                playCount: media.cntInfo?.play ?? -1,
                durationText: summary?.formattedDuration ?? "",
                animatesEntrance: false
            )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedIDs.contains(media.id) ? .isSelected : [])
        .contextMenu {
            if !isSelecting {
                Button {
                    isSelecting = true; selectedIDs = [media.id]
                } label: { Label("多选", systemImage: "checkmark.circle") }
                .disabled(isRemovingSelected || isLoading || isLoadingMore || removals.hasPending)
            }
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
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            if loadsNextPage { await loadMoreIfNeeded() }
            if !isSelecting, let summary {
                // 收藏没有 cid，预取会先取一次详情再取播放地址。
                await VideoPreparationCache.shared.prefetchWhenSettled(bvid: summary.bvid)
            }
        }
    }

    private func removeSelected() async {
        guard !isRemovingSelected, !isLoading, !isLoadingMore, !removals.hasPending else { return }
        let snapshot = videos
        let targets = snapshot.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        isRemovingSelected = true
        loadID = UUID()
        for target in targets { _ = removals.begin(target.id); removals.hide(target.id) }
        defer {
            if account.sessionID == owner {
                for target in targets { removals.finish(target.id) }
                isRemovingSelected = false
            }
        }
        let lookup = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(targets.map(\.id))
        videos.removeAll { ids.contains($0.id) }
        let result = await LibraryBatchRemoval.perform(ids: targets.map(\.id),
            isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移出收藏夹")) },
            remove: { id in
                guard let target = lookup[id] else { return }
                try await services.library.removeFavorite(folderID: folder.id, aid: target.id, expectedSessionID: identitySession)
            })
        guard account.sessionID == owner else { return }
        videos = snapshot.filter { !result.succeeded.contains($0.id) }
        selectedIDs.subtract(result.succeeded)
        if selectedIDs.isEmpty { isSelecting = false }
        if let error = result.error { feedback.show(error) }
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
        guard !removals.hasPending, !isRemovingSelected else { return }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        isLoading = true
        isLoadingMore = false
        defer { if loadID == requestID { isLoading = false } }
        do {
            let payload = try await services.library.favoriteVideos(folderID: folder.id, page: 1)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = (payload.medias ?? []).filter(\.isVideo)
            entranceGeneration += 1
            videos = LibraryPageRules.unique(incoming, excluding: removals.hiddenIDs)
            selectedIDs.formIntersection(Set(videos.map(\.id)))
            page = 2
            hasMore = LibraryPageRules.hasMoreFavorites(rawCount: payload.medias?.count ?? 0)
            errorMessage = nil
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            if videos.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func loadMoreIfNeeded() async {
        guard !isSelecting, hasMore, !isLoadingMore, !isLoading, errorMessage == nil else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !removals.hasPending, !isRemovingSelected else { return }
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        errorMessage = nil
        isLoading = videos.isEmpty
        isLoadingMore = !videos.isEmpty
        defer {
            if loadID == requestID {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let payload = try await services.library.favoriteVideos(folderID: folder.id, page: page)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = (payload.medias ?? []).filter(\.isVideo)
            let existing = Set(videos.map(\.id))
            videos.append(contentsOf: LibraryPageRules.unique(incoming, excluding: existing.union(removals.hiddenIDs)))
            // 不足一页说明到底了。
            hasMore = LibraryPageRules.hasMoreFavorites(rawCount: payload.medias?.count ?? 0)
            page += 1
            errorMessage = nil
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 同 `HistoryView.delete`：先移走卡片再发请求，失败了放回原位。
    /// 移除后提供短暂撤销入口，超时再提交请求。
    ///
    /// 直接更新列表，保留撤销确认、账号校验和失败回滚。
    private func remove(_ media: FavMedia) async {
        guard !isRemovingSelected, videos.contains(where: { $0.id == media.id }), removals.begin(media.id) else { return }
        let sessionID = account.sessionID
        defer { if account.sessionID == sessionID { removals.finish(media.id) } }
        let identitySession = services.session.currentID()
        var removedIndex: Int?
        do {
            removals.hide(media.id)
            removedIndex = removals.remove(media.id, from: &videos)
            guard await feedback.confirmRemoval(String(localized: "已移出收藏夹")),
                  account.sessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
            try await services.library.removeFavorite(folderID: folder.id, aid: media.id, expectedSessionID: identitySession)
            guard account.sessionID == sessionID else { return }
            // 同时完成的刷新也不能留下同 ID 的旧条目。
            videos.removeAll { $0.id == media.id }
            selectedIDs.remove(media.id)
            if selectedIDs.isEmpty { isSelecting = false }
        } catch {
            if account.sessionID == sessionID, let removedIndex {
                removals.restore(media, at: removedIndex, in: &videos)
            }
            if account.sessionID == sessionID, !error.isCancellation { feedback.show(error.localizedDescription) }
        }
    }
}
