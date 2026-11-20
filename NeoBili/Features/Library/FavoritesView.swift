#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// 收藏夹列表（账号创建的全部收藏夹，含默认收藏夹）。
struct FavoritesView: View {
    /// 作为底部标签页的根页面挂载（不显示刷新按钮）。
    var isTabRoot = false
    @Environment(\.applicationServices) private var services
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animations = VideoCardAnimationPreferences(source: .favorites)
    @State private var refresh = ListRefreshController()
    /// 取回的收藏夹及取回时的移除状态；换入前若又发生过移除，这份快照已过期。
    @State private var stagedFolders: (folders: [FavFolder], revision: UUID)?
    @State private var folders: [FavFolder] = []
    @State private var folderRemovals = ListRemovalState<Int>()
    @State private var isLoading = false
    @State private var loadID = UUID()
    @State private var ownerSession: UUID?
    @State private var errorMessage: String?
    /// 待删除的收藏夹。提交后不可恢复，保留确认和短暂撤销窗口。
    @State private var folderPendingDeletion: FavFolder?
    @State private var showsCreator = false
    @State private var openedFolder: FavFolder?
    /// 列表铺满全屏后要避让的上下距离（状态栏、大标题、标签栏），量好交给列表。
    @State private var safeInsets = EdgeInsets()
    @Environment(RootToolbarAccessory.self) private var toolbarAccessory: RootToolbarAccessory?

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
                // 列表铺到标题栏和标签栏下面，边距用量出的安全区，标题栏才能随下滑收起。
                FavoriteFolderList(
                    folders: folders,
                    contentOpacity: animatesExit ? refresh.contentOpacity : 1,
                    animatesRemoval: animatesExit,
                    safeInsets: safeInsets,
                    refreshDistance: CGFloat(refreshDistance),
                    onRefresh: startRefresh,
                    onOpen: { openedFolder = $0 },
                    onDelete: { folderPendingDeletion = $0 }
                )
                .ignoresSafeArea()
                .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { safeInsets = $0 }
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触条目。
        .leftEdgeTapDeadZone()
        .navigationTitle("收藏")
        .navigationDestination(item: $openedFolder) { folder in
            FavoriteFolderView(folder: folder)
        }
        .toolbar {
            // 标签页的头像由根页统一画在最右侧。新建按钮交给它放在头像左边，避免把头像挤偏。
            if !isTabRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    createFolderButton
                }
            }
            // 从「我的服务」进入时右上角提供刷新。
            if !isTabRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise", action: startRefresh)
                        .labelStyle(.iconOnly)
                        .disabled(!canRefresh)
                        .accessibilityIdentifier("favorites.refresh")
                }
            }
        }
        .sheet(isPresented: $showsCreator) {
            NewFavoriteFolderSheet { title, intro, isPublic in
                try await createFolder(title: title, intro: intro, isPublic: isPublic)
            }
            .appTextSize()
        }
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
        .onAppear { publishCreateButton() }
        .onChange(of: isLoading || folders.isEmpty) { publishCreateButton() }
        .onDisappear {
            if isTabRoot { toolbarAccessory?.button = nil }
            refresh.reset(discard: { stagedFolders = nil })
        }
        .onChange(of: account.sessionID) { refresh.reset(discard: { stagedFolders = nil }) }
        // 居中提示。确认框会锚在来源上，从列表长按菜单弹出时会贴到标签栏。
        .alert(
            "删除收藏夹",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            presenting: folderPendingDeletion
        ) { folder in
            Button("删除收藏夹", role: .destructive) {
                Task { await delete(folder) }
                folderPendingDeletion = nil
            }
            Button("取消", role: .cancel) { folderPendingDeletion = nil }
        } message: { folder in
            Text(String(localized: "删除「\(folder.title)」？"))
        }
    }

    private func createFolder(title: String, intro: String, isPublic: Bool) async throws {
        guard account.accountID != nil else {
            throw FavoriteFolderEditError(message: String(localized: "登录状态已失效，请重新登录"))
        }
        let sessionID = account.sessionID
        let identitySession = services.session.currentID()
        let created = try await services.library.addFavoriteFolder(
            title: title, intro: intro, isPublic: isPublic, expectedSessionID: identitySession)
        guard account.sessionID == sessionID else { return }
        var next = folders.filter { $0.id != created.id }
        if next.first?.isDefaultFolder == true {
            next.insert(created, at: min(1, next.count))
        } else {
            next.insert(created, at: 0)
        }
        folders = next
    }

    private var createFolderButton: some View {
        Button("新建收藏夹", systemImage: "folder.badge.plus") { showsCreator = true }
            .labelStyle(.iconOnly)
            .disabled(isLoading && folders.isEmpty)
            .accessibilityIdentifier("favorites.create")
    }

    private func publishCreateButton() {
        guard isTabRoot, let toolbarAccessory else { return }
        toolbarAccessory.button = RootToolbarAccessory.ButtonSpec(
            title: "新建收藏夹",
            systemImage: "folder.badge.plus",
            identifier: "favorites.create",
            disabled: isLoading && folders.isEmpty,
            action: { showsCreator = true }
        )
    }

    private func delete(_ folder: FavFolder) async {
        guard !refresh.isRefreshing, folderRemovals.begin(folder.id) else { return }
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

    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance

    private var canRefresh: Bool { !refresh.isRefreshing && !isLoading && !folderRemovals.hasPending }

    /// 「我的」里的刷新按钮：旧内容淡出的同时重新取收藏夹，两者都结束后一次换入。
    private func startRefresh() {
        guard canRefresh else { return }
        refresh.start(hasContent: !folders.isEmpty, animatesExit: animatesExit, source: .favorites,
                      fetch: { await stageFolders() },
                      commit: {
                          guard let staged = stagedFolders else { return }
                          stagedFolders = nil
                          guard staged.revision == folderRemovals.revision, !folderRemovals.hasPending else { return }
                          folders = staged.folders
                      },
                      discard: { stagedFolders = nil })
    }

    private func stageFolders() async -> Bool {
        guard let mid = account.accountID else {
            feedback.show(String(localized: "登录状态已失效，请重新登录"))
            return false
        }
        let requestID = UUID()
        loadID = requestID
        let sessionID = account.sessionID
        let revision = folderRemovals.revision
        stagedFolders = nil
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            let result = try await services.library.favoriteFolders(ownerMid: mid)
            guard loadID == requestID, account.sessionID == sessionID, folderRemovals.revision == revision, !Task.isCancelled else { return false }
            stagedFolders = (LibraryPageRules.unique(result), revision)
            return true
        } catch {
            guard loadID == requestID, account.sessionID == sessionID, !error.isCancellation else { return false }
            feedback.show(error.localizedDescription)
            return false
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

private struct FavoriteFolderEditError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct NewFavoriteFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var intro = ""
    @State private var isPublic = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    let submit: (String, String, Bool) async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $title)
                TextField("简介", text: $intro, axis: .vertical)
                    .lineLimit(3...6)
                Toggle("公开", isOn: $isPublic)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.app(.footnote))
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("新建收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { Task { await commit() } }
                        .disabled(trimmedTitle.isEmpty || isSubmitting)
                }
            }
            .onChange(of: title) { _, value in
                if value.count > 20 { title = String(value.prefix(20)) }
            }
            .onChange(of: intro) { _, value in
                if value.count > 200 { intro = String(value.prefix(200)) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() async {
        let name = trimmedTitle
        guard !name.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await submit(name, intro, isPublic)
            dismiss()
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
        }
    }
}

/// 收藏夹视频使用 VideoListCard；转场源直接挂在卡片 Button 上。
struct FavoriteFolderView: View {
    @Environment(\.applicationServices) private var services
    let folder: FavFolder

    @Environment(AccountStore.self) private var account
    @Environment(\.videoPreparation) private var preparation
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.videoFiltering) private var filtering
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animations = VideoCardAnimationPreferences(source: .favorites)

    @State private var model = FavoriteFolderListModel()
    @State private var refresh = ListRefreshController()
    @State private var filterMemo = FilteredVideosMemo<FavMedia>()
    @State private var menuRegistry = ResolvedMenuRegistry<Int>()

    private var visibleVideos: [FavMedia] {
        filterMemo.videos(model.videos, revision: model.contentRevision,
                          hidesPortraitVideos: hidesPortraitVideos, filtering: filtering)
    }

    var body: some View {
        let visibleVideos = visibleVideos
        let paginationIDs = Set(visibleVideos.suffix(5).map(\.id))
        Group {
            if visibleVideos.isEmpty, model.videos.hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
                LoadingTaskAnchor()
            } else if let errorMessage = model.errorMessage, model.videos.isEmpty {
                ContentUnavailableView {
                    Label("内容加载失败", systemImage: "star.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await model.reload(services: services, folder: folder) } }
                }
            } else if !model.isLoading, !model.hasMore, visibleVideos.isEmpty {
                ContentUnavailableView(
                    model.videos.isEmpty ? "收藏夹是空的" : "没有可显示的视频",
                    systemImage: model.videos.isEmpty ? "star" : "rectangle.slash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleVideos) { media in
                            row(media, loadsNextPage: paginationIDs.contains(media.id))
                                .removalFillTransition()
                        }
                        if model.hasMore, !model.isLoadingMore {
                            Button("继续加载") { Task { await model.loadNextPage(services: services, folder: folder, refreshing: refresh.isRefreshing) } }
                                .padding(.vertical, 12)
                                .disabled(model.isLoading)
                        }
                        if model.isLoadingMore {
                            LoadingTaskAnchor()
                                .padding(.vertical, 12)
                        }
                        if let errorMessage = model.errorMessage, !model.videos.isEmpty {
                            VStack(spacing: 8) {
                                Text(errorMessage).font(.app(.footnote)).foregroundStyle(.secondary)
                                Button("重试加载") { Task { await model.loadNextPage(services: services, folder: folder, refreshing: refresh.isRefreshing) } }
                                    .disabled(model.isLoading || model.isLoadingMore)
                            }
                            .padding()
                        }
                    }
                    .background {
                        ResolvedMenuInstaller(registry: menuRegistry, menu: rowMenu)
                    }
                    // 删除看源列表的身份：过滤只改可见行，不触发补位。翻页是末尾追加，同样不动画。
                    .removalFill(ids: model.videos.map(\.id), enabled: animatesExit, scope: .removalAndInlineRestore)
                    // 与推荐页一致：松手后旧卡片淡出，新内容到了再换入。
                    .opacity(animatesExit ? refresh.contentOpacity : 1)
                    .allowsHitTesting(refresh.contentOpacity == 1)
                    .background {
                        ListPullRefresh(enabled: canRefresh, onRefresh: startRefresh)
                    }
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .accessibilityAction(named: "刷新收藏夹内容", startRefresh)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.isLoading, model.videos.isEmpty { LoadingTaskAnchor() }
        }
        .task { await model.loadIfNeeded(services: services, folder: folder) }
        .listEntrance(ids: visibleVideos.map { "favorite:\($0.id)" }, generation: model.entranceGeneration, source: .favorites)
        .onDisappear { refresh.reset(discard: model.discardStagedPage) }
        .resolvePortraitVideos(model.videos, batchID: model.entranceGeneration) {
            guard model.hasMore, model.errorMessage == nil else { return model.videos }
            await model.loadNextPage(services: services, folder: folder, refreshing: refresh.isRefreshing)
            return model.videos
        }
        .videoCardAnimationSource(.favorites)
        .safeAreaInset(edge: .bottom) {
            if model.isSelecting {
                LibrarySelectionBar(count: model.selectedIDs.count,
                    isBusy: model.isRemovingSelected || model.isLoading || model.isLoadingMore || refresh.isRefreshing,
                    done: { model.isSelecting = false; model.selectedIDs = [] }) {
                    Task { await model.removeSelected(services: services, account: account, feedback: feedback, folder: folder, refreshing: refresh.isRefreshing) }
                }
            }
        }
        .onChange(of: account.sessionID) { _, _ in
            model.reset()
            refresh.reset(discard: model.discardStagedPage)
            Task { await model.reload(services: services, folder: folder) }
        }
    }

    private func row(_ media: FavMedia, loadsNextPage: Bool) -> some View {
        let summary = media.asVideoSummary

        return LibraryVideoCardButton(
            id: media.id, registry: menuRegistry,
            isSelecting: model.isSelecting, isSelected: model.selectedIDs.contains(media.id)
        ) {
            if model.isSelecting {
                guard !model.isRemovingSelected else { return }
                if model.selectedIDs.contains(media.id) { model.selectedIDs.remove(media.id) }
                else { model.selectedIDs.insert(media.id) }
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
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: media.title,
                author: media.upper?.name ?? "",
                playCount: media.cntInfo?.play ?? -1,
                durationText: summary?.formattedDuration ?? ""
            )
            .videoEntranceIdentity("favorite:\(media.id)")
        }
        .videoTransitionSource("fav-\(summary?.bvid ?? "")", in: videoTransition)
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            if loadsNextPage { await model.loadMoreIfNeeded(services: services, folder: folder, refreshing: refresh.isRefreshing) }
            if !model.isSelecting, let summary {
                // 收藏没有 cid，预取会先取一次详情再取播放地址。
                await preparation.prefetchWhenSettled(bvid: summary.bvid)
            }
        }
    }

    private func rowMenu(for id: Int) -> UIMenu {
        let busy = model.isRemovingSelected || model.isLoading || model.isLoadingMore || model.removals.hasPending || refresh.isRefreshing
        var actions: [UIAction] = []
        if !model.isSelecting {
            actions.append(menuRegistry.action("多选", systemImage: "checkmark.circle", enabled: !busy, id: id) { target in
                model.isSelecting = true
                model.selectedIDs = [target]
            })
        }
        actions.append(menuRegistry.action("稍后再看", systemImage: "flag", id: id) { target in
            guard let media = model.videos.first(where: { $0.id == target }) else { return }
            WatchLaterAction.add(aid: media.id, bvid: media.bvid, services: services, account: account, feedback: feedback)
        })
        actions.append(menuRegistry.action("取消收藏", systemImage: "star.slash", destructive: true, enabled: !busy, id: id) { target in
            guard let media = model.videos.first(where: { $0.id == target }) else { return }
            Task { await model.remove(media, services: services, account: account, feedback: feedback, folder: folder, refreshing: refresh.isRefreshing) }
        })
        return UIMenu(children: actions)
    }

    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance

    private var canRefresh: Bool {
        !refresh.isRefreshing && !model.isLoading && !model.isLoadingMore && !model.removals.hasPending && !model.isRemovingSelected
    }

    /// 手动下拉刷新：旧卡片淡出的同时取第一页，两者都结束后一次换入。
    private func startRefresh() {
        guard canRefresh else { return }
        refresh.start(hasContent: !model.videos.isEmpty, animatesExit: animatesExit, source: .favorites,
                      fetch: { await model.stageReload(services: services, feedback: feedback, folder: folder) },
                      commit: model.commitStagedReload,
                      discard: model.discardStagedPage)
    }

}
