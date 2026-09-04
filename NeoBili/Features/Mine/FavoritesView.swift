import SwiftUI

/// 收藏夹列表（账号创建的全部收藏夹，含默认收藏夹）。
struct FavoritesView: View {
    @Environment(AccountStore.self) private var account
    @State private var folders: [FavFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    }
                }
            }
        }
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, folders.isEmpty { ProgressView() }
        }
        .task { await load() }
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
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var videos: [FavMedia] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?

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
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
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
            .contextMenu {
                Button(role: .destructive) {
                    Task { await remove(media) }
                } label: {
                    Label("取消收藏", systemImage: "star.slash")
                }
            }
        }
        .buttonStyle(.plain)
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        .videoTransitionSource("fav-\(summary?.bvid ?? "")", in: videoTransition)
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

    private func reload() async {
        page = 1
        hasMore = true
        videos = []
        await loadNextPage()
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
            if videos.isEmpty { errorMessage = error.localizedDescription }
            hasMore = false
        }
    }

    private func remove(_ media: FavMedia) async {
        do {
            try await BiliAPI.removeFavorite(folderID: folder.id, aid: media.id)
            withAnimation { videos.removeAll { $0.id == media.id } }
        } catch {
            // 失败保持原样。
        }
    }
}
