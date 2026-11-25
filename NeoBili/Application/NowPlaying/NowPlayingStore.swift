#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import SwiftUI

/// 评论列表滚动偏移的非观察盒子，见 `NowPlayingStore.commentScrollBox`。
@MainActor
final class CommentScrollBox {
    var offset: CGFloat = 0
}

/// 视频、直播及详情页面的持久状态。
/// 开启缩略播放器时，退出详情后继续播放；关闭时在退出转场完成后释放。
@MainActor
@Observable
final class NowPlayingStore {
    /// 播放配置每次新建播放器时从系统设置现读（见 `VideoPlaybackConfiguration.current`），
    /// 设置页改完清晰度，下一个打开的视频就生效。
    var playbackConfiguration: VideoPlaybackConfiguration {
        VideoPlaybackConfiguration.current
    }

    /// 当前点播路由；收起到缩略播放器时仍保留。直播使用 livePlayer。
    private(set) var route: VideoDetailRoute?
    private(set) var detailViewModel: VideoDetailViewModel?
    private(set) var commentsViewModel: CommentsViewModel?
    private(set) var player: PlayerViewModel?
    private(set) var livePlayer: LivePlayerModel?
    private(set) var offline: OfflinePlaybackDescriptor?
    private var offlineService: OfflineCacheService?
    private var offlineOpenRequest = UUID()
    private var hasRequestedPlayback = false
    var isWaitingForPlayback: Bool { route != nil && !hasRequestedPlayback }

    var hasMedia: Bool { route != nil || livePlayer != nil }
    var activeSession: MPVPlayerSession? { livePlayer?.session ?? player?.session }
    var hasRenderedFirstFrame: Bool { livePlayer?.hasRenderedFirstFrame ?? player?.hasRenderedFirstFrame ?? false }
    var isPlaying: Bool { livePlayer?.isPlaying ?? player?.isPlaying ?? false }
    var isLoading: Bool { livePlayer?.isLoading ?? player?.isLoading ?? true }

    func togglePlayback() {
        if let livePlayer { livePlayer.togglePlayback() }
        else if let player { player.togglePlayPause() }
        else { requestPlayback() }
    }

    func requestPlayback() {
        guard route != nil, !hasRequestedPlayback else { return }
        hasRequestedPlayback = true
        startPlayerIfPossible()
    }

    func openLive(_ room: LiveRoom, from sourceID: String) {
        if livePlayer?.room.roomID != room.roomID {
            close()
            let services = dependencies.services
            let model = LivePlayerModel(room: room,
                roomLoader: { try await services.streaming.roomInfo(roomID: $0) },
                playbackLoader: { try await services.streaming.playback(roomID: $0, quality: $1) },
                systemMedia: dependencies.systemMedia)
            livePlayer = model
            model.requestLoad()
        }
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        requestPageExpansion(from: sourceID)
    }

    private var presentationState = MediaPresentationState()
    var videoPresentation: MediaPresentationState.Destination? { presentationState.destination }

    /// The native cover's item is the single source of presentation state.
    var isExpanded: Bool {
        get { presentationState.destination != nil }
        set { presentationState.destination = newValue ? .player : nil }
    }
    private(set) var pendingPresentationID: UUID?
    private(set) var isMiniPlayerPresented = false
    /// 视频页缩放退出到底部附件后的短时间内，标签栏收缩时 UIKit 重建玻璃变形的位置会算错，
    /// 缩略播放器整体偏向右下方压住搜索按钮。退出开始时暂停收缩，转场结束 0.5 秒后再恢复。
    private(set) var holdsTabBarMinimize = false
    @ObservationIgnored private var minimizeReleaseTask: Task<Void, Never>?
    private(set) var isVideoPageDismissalInProgress = false
    private(set) var isVideoPageInteractionInProgress = false
    private(set) var dismissalPlaybackPhase: InlineVideoPlaybackPhase?

    var section: VideoPageSection = .description
    var isDescriptionExpanded = false
    private(set) var selectedCid: Int?

    /// 两个列表各自的滚动位置，切换视频页内容时回到原处。
    var descriptionScroll = VideoDescriptionScrollState()
    var commentsScroll = ScrollPosition(edge: .top)
    /// 评论集合视图的实际滚动偏移。逐帧写入，放在不参与观察的盒子里，
    /// 避免滚动本身触发整页 body 重算。
    @ObservationIgnored let commentScrollBox = CommentScrollBox()

    static let miniPlayerTransitionSourceID = "neobili.mini-player"

    /// Keep the entry identity for diagnostics; only the matching source moves.
    var transitionSourceID: String { presentationState.entrySourceID }

    func matchedTransitionSource(for id: String) -> MediaPresentationState.Source {
        presentationState.source(for: id)
    }

    /// Mount the accessory before presenting so UIKit can resolve its zoom geometry.
    private func requestPageExpansion(from cardID: String) {
        let usesMini = PlaybackWindowSettings.isEnabled(in: defaults)
        presentationState.prepareSource(usesMini ? Self.miniPlayerTransitionSourceID : cardID)
        if usesMini && !isExpanded {
            isMiniPlayerPresented = true
            activeSession?.surfacePresentation = .mini
            pendingPresentationID = UUID()
        } else {
            pendingPresentationID = nil
            activeSession?.surfacePresentation = .page
            isMiniPlayerPresented = false
            isExpanded = true
        }
    }

    func miniPlayerSourceDidLayout(request: UUID) {
        guard pendingPresentationID == request, hasMedia else { return }
        pendingPresentationID = nil
        activeSession?.surfacePresentation = .page
        isMiniPlayerPresented = false
        isExpanded = true
    }

    /// 视频页里点相关视频是就地替换，这里记着来路，供左上角返回按钮逐级回退。
    private var history = PlaybackNavigationHistory()
    /// 当前会话已播过的稿件，用于自动连播跳过重复推荐。
    private var visitedBvids: Set<String> = []
    private var loadTasks: [Task<Void, Never>] = []
    private var playerLoadTask: Task<Void, Never>?
    private var detailLoadTask: Task<Void, Never>?
    private let detailModelFactory: @MainActor (VideoDetailRoute) -> VideoDetailViewModel
    private let offlineGroupEntryIDsProvider: @MainActor (String) -> [String]

    var preparationCache: VideoPreparationCache { dependencies.preparation }
    private let dependencies: PlaybackDependencies
    private let defaults: UserDefaults

    init(configuration: VideoPlaybackConfiguration = .fastStart, defaults: UserDefaults = .standard,
         detailModelFactory: (@MainActor (VideoDetailRoute) -> VideoDetailViewModel)? = nil,
         offlineGroupEntryIDsProvider: (@MainActor (String) -> [String])? = nil,
         dependencies: PlaybackDependencies = .live) {
        // configuration 形参保留给测试注入使用；线上路径每次都读 `.current`。
        _ = configuration
        self.defaults = defaults
        self.dependencies = dependencies
        self.offlineGroupEntryIDsProvider = offlineGroupEntryIDsProvider ?? { groupID in
            OfflineCacheStore.shared.entries(in: groupID).map(\.id)
        }
        self.detailModelFactory = detailModelFactory ?? { route in
            VideoDetailViewModel(bvid: route.bvid, aid: route.aid ?? 0, playbackEntry: route.playbackEntry,
                likeStore: dependencies.likes, services: dependencies.services,
                fetchDetail: { try await dependencies.preparation.detail(for: $0) })
        }
    }

    /// 服务 sheet 打开期间，由它承载视频模态，根 TabView 暂停呈现。
    var isServiceSheetPresented = false

    var canGoBack: Bool { history.canGoBack }

    /// 正在播放的分P。入口已经给了 cid 时立刻有值，播放器不必等详情接口。
    var activeCid: Int? {
        selectedCid ?? detailViewModel?.detail?.cid
    }

    // MARK: - 打开与关闭

    /// 从推荐页或搜索页的卡片打开。
    /// 点的是正在播的那个视频时只重新显示，不重新加载，进度也不会丢。
    func open(_ newRoute: VideoDetailRoute, from sourceID: String) {
        if livePlayer != nil || offline != nil { close() }
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        if route?.bvid == newRoute.bvid {
            requestPageExpansion(from: sourceID)
            return
        }
        history.reset()
        visitedBvids.removeAll()
        start(newRoute)
        requestPageExpansion(from: sourceID)
    }

    /// 评论视频链接保留返回路径；同一视频不重建播放会话。
    func openCommentVideo(_ newRoute: VideoDetailRoute) {
        guard isExpanded, route != nil, livePlayer == nil else {
            open(newRoute, from: "comment-link")
            return
        }
        guard route?.bvid != newRoute.bvid else { return }
        if let route { history.record(route, activeCid: activeCid) }
        start(newRoute)
    }

    /// 视频页里点相关视频：就地换掉当前视频，旧的压进历史。
    func openRelated(_ video: VideoSummary) {
        openRelated(video, forceAutoPlay: false)
    }

    func openRelated(_ video: VideoSummary, forceAutoPlay: Bool) {
        if let route {
            history.record(route, activeCid: activeCid)
        }
        start(
            VideoDetailRoute(
                bvid: video.bvid,
                cid: video.cid,
                cover: video.pic,
                title: video.title,
                artist: video.owner.name, aid: video.aid, playbackEntry: video.playbackEntry.source == .other ? .related : video.playbackEntry
            ),
            forceAutoPlay: forceAutoPlay
        )
    }

    /// 合集里选另一集：和点相关视频一样就地换片，旧的压进历史，
    /// 所以左上角返回能一级级退回原来那一集。
    func openEpisode(_ episode: UgcSeasonEpisode) {
        openEpisode(episode, forceAutoPlay: false)
    }

    func openEpisode(_ episode: UgcSeasonEpisode, forceAutoPlay: Bool) {
        guard let bvid = episode.bvid else { return }
        if let route {
            history.record(route, activeCid: activeCid)
        }
        start(
            VideoDetailRoute(
                bvid: bvid,
                cid: episode.cid,
                cover: episode.arc?.pic,
                title: episode.title,
                artist: detailViewModel?.detail?.owner.name, playbackEntry: .collection
            ),
            forceAutoPlay: forceAutoPlay
        )
    }

    /// 沿视频返回栈回退；到达栈底后按缩略播放器设置退出详情。
    func goBack() {
        if let previous = history.pop() {
            start(previous)
        } else {
            dismissVideoPage()
        }
    }

    /// Move the matched source only after entrance finishes. The cover's native
    /// navigationTransition and its source ID remain unchanged throughout.
    func videoPageDidAppear() {
        guard isExpanded, hasMedia, !isVideoPageInteractionInProgress,
              !isVideoPageDismissalInProgress else { return }
        presentationState.completeEntrance(returningTo: PlaybackWindowSettings.isEnabled(in: defaults)
            ? Self.miniPlayerTransitionSourceID : presentationState.entrySourceID)
    }

    /// UIKit begins the interactive transition before SwiftUI changes its binding.
    /// Freeze page layout now, without committing dismissal or pausing playback.
    func videoPageInteractionBegan() {
        guard isExpanded, hasMedia else { return }
        isVideoPageInteractionInProgress = true
        dismissalPlaybackPhase = InlineVideoPlaybackPhase(
            isPlaying: isPlaying,
            hasRenderedFirstFrame: hasRenderedFirstFrame,
            isLoading: isLoading
        )
    }

    func videoPageInteractionEnded(cancelled: Bool) {
        guard isVideoPageInteractionInProgress else { return }
        isVideoPageInteractionInProgress = false
        if cancelled, hasMedia {
            let resume = isVideoPageDismissalInProgress && dismissalPlaybackPhase == .playing
            isExpanded = true
            isMiniPlayerPresented = false
            isVideoPageDismissalInProgress = false
            dismissalPlaybackPhase = nil
            activeSession?.surfacePresentation = .page
            if resume {
                if let livePlayer { livePlayer.play() } else { player?.play() }
            }
        }
    }

    /// 小窗已提前位于停靠点，原生 zoom 退出时可以直接找到稳定的目标。
    func dismissVideoPage() {
        guard !isVideoPageDismissalInProgress else { return }
        player?.savePlaybackProgress()
        guard hasMedia else { close(); return }
        dismissalPlaybackPhase = InlineVideoPlaybackPhase(
            isPlaying: isPlaying,
            hasRenderedFirstFrame: hasRenderedFirstFrame,
            isLoading: isLoading
        )
        isVideoPageDismissalInProgress = true
        minimizeReleaseTask?.cancel()
        holdsTabBarMinimize = true
        // 缩放退出完成前，视频像素仍留在原页面，底部缩略图提供转场目标。
        isMiniPlayerPresented = PlaybackWindowSettings.isEnabled(in: defaults)
        isExpanded = false
    }

    func expandMiniPlayer() {
        pendingPresentationID = nil
        guard hasMedia else { return }
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        presentationState.prepareSource(Self.miniPlayerTransitionSourceID)
        activeSession?.surfacePresentation = .page
        isMiniPlayerPresented = false
        isExpanded = true
    }

    func applyMiniPlayerSetting() {
        if !PlaybackWindowSettings.isEnabled(in: defaults), !isExpanded, !isVideoPageDismissalInProgress { close() }
    }

    /// 关闭视频页并彻底停止播放。
    func close() {
        releaseOffline()
        minimizeReleaseTask?.cancel()
        holdsTabBarMinimize = false
        pendingPresentationID = nil
        livePlayer?.stop()
        livePlayer = nil
        cancelLoads()
        player?.stop()
        player = nil
        hasRequestedPlayback = false
        detailViewModel = nil
        commentsViewModel = nil
        route = nil
        history.reset()
        visitedBvids.removeAll()
        isExpanded = false
        isMiniPlayerPresented = false
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
    }

    private func releaseTabBarMinimize(after delay: Duration) {
        minimizeReleaseTask?.cancel()
        minimizeReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.holdsTabBarMinimize = false
        }
    }

    /// Called by fullScreenCover's onDismiss after the system animation ends.
    /// The old dismissal callback may arrive after the user has tapped another
    /// card. In that case `open` has made the new page expanded again, so the
    /// stale callback must not tear down the new route and player.
    func finishDismissal() {
        guard !isExpanded, pendingPresentationID == nil else { return }
        releaseTabBarMinimize(after: .milliseconds(500))
        guard PlaybackWindowSettings.isEnabled(in: defaults) else { close(); return }
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        if hasMedia {
            activeSession?.surfacePresentation = .mini
            isMiniPlayerPresented = true
        } else {
            close()
        }
    }

    // MARK: - 分P

    func selectPart(cid: Int) {
        guard selectedCid != cid else { return }
        selectedCid = cid
        startPlayerIfPossible()
    }

    // MARK: - 内部

    /// 换一个视频。整份状态归零后重新开始加载。
    private func start(_ newRoute: VideoDetailRoute, forceAutoPlay: Bool = false) {
        releaseOffline()
        cancelLoads()
        player?.stop()
        player = nil
        isMiniPlayerPresented = false

        route = newRoute
        visitedBvids.insert(newRoute.bvid)
        hasRequestedPlayback = forceAutoPlay || DetailPlaybackSettings.isAutoPlayEnabled(in: defaults)
        selectedCid = newRoute.cid
        section = .description
        isDescriptionExpanded = false
        descriptionScroll = VideoDescriptionScrollState()
        commentsScroll = ScrollPosition(edge: .top)
        commentScrollBox.offset = 0
        commentsViewModel = nil

        let viewModel = detailModelFactory(newRoute)
        detailViewModel = viewModel

        loadDetail(viewModel)
        // 相关视频和详情各自独立请求，互不等待。
        loadTasks = [Task {
            guard !Task.isCancelled else { return }
            await viewModel.loadRelated()
        }]

        // 自动播放且入口带了 cid 时直接取流；手动播放只加载页面数据。
        startPlayerIfPossible()
    }

    /// 页面退回小窗后仍由会话持有请求；重试补齐全部依赖详情的数据。
    func retryDetail() {
        guard let viewModel = detailViewModel, viewModel.detail == nil,
              detailLoadTask == nil else { return }
        loadDetail(viewModel)
    }

    private func loadDetail(_ viewModel: VideoDetailViewModel) {
        detailLoadTask = Task { [weak self] in
            await viewModel.load()
            guard !Task.isCancelled, let self, self.detailViewModel === viewModel else { return }
            defer {
                if self.detailViewModel === viewModel { self.detailLoadTask = nil }
            }
            guard viewModel.detail != nil else { return }
            self.startPlayerIfPossible()
            self.refreshSystemMediaMetadata()
            self.buildCommentsIfNeeded()
            await viewModel.loadExtras()
        }
    }

    private func startPlayerIfPossible() {
        guard offline == nil else { return }
        guard hasRequestedPlayback, let route, let cid = activeCid else { return }
        // 已经在放这一个了就不要重建，否则会打断正在进行的播放。
        if let player, player.bvid == route.bvid, player.cid == cid {
            player.updateWatchAid(route.aid ?? detailViewModel?.detail?.aid ?? 0)
            return
        }

        playerLoadTask?.cancel()
        playerLoadTask = nil
        player?.stop()
        let newPlayer = PlayerViewModel(
            bvid: route.bvid,
            cid: cid,
            aid: route.aid ?? detailViewModel?.detail?.aid ?? 0, playbackEntry: route.playbackEntry,
            configuration: playbackConfiguration, dependencies: dependencies
        )
        newPlayer.onPlaybackEnded = { [weak self, weak newPlayer] in
            guard let self, let newPlayer else { return }
            self.handlePlaybackEnded(for: newPlayer)
        }
        newPlayer.session.surfacePresentation = isMiniPlayerPresented && !isVideoPageDismissalInProgress ? .mini : .page
        player = newPlayer
        refreshSystemMediaMetadata()
        playerLoadTask = Task {
            guard !Task.isCancelled else { return }
            await newPlayer.load()
        }
    }

    /// 列表信息足够让锁屏界面立即识别媒体；详情回来后再补上准确标题、作者、
    /// 封面以及分P名称，不让系统媒体卡片一直显示占位内容。
    private func refreshSystemMediaMetadata() {
        guard let route, let player else { return }
        let detail = detailViewModel?.detail
        var title = detail?.title ?? route.title ?? String(localized: "Bilibili 视频")
        if let detail,
           detail.pages.count > 1,
           let part = detail.pages.first(where: { $0.cid == player.cid })?.part,
           !part.isEmpty {
            title += " · \(part)"
        }
        player.updateSystemMediaMetadata(
            title: title,
            artist: detail?.owner.name ?? route.artist ?? "",
            artworkURL: detail?.secureCoverURL ?? route.secureCoverURL
        )
    }

    private func buildCommentsIfNeeded() {
        guard let aid = detailViewModel?.detail?.aid else { return }
        // 评论接口要用 av 号，所以只能等详情回来才能建这个视图模型。
        if commentsViewModel?.oid != aid {
            commentsViewModel = CommentsViewModel(oid: aid, type: 1, uploaderID: detailViewModel?.detail?.owner.mid,
                                                 initialCount: detailViewModel?.detail?.stat.reply,
                                                 services: dependencies.services)
        }
    }

    private func cancelLoads() {
        detailLoadTask?.cancel()
        detailLoadTask = nil
        playerLoadTask?.cancel()
        playerLoadTask = nil
        for task in loadTasks {
            task.cancel()
        }
        loadTasks.removeAll()
    }

    func openOffline(_ id: String, service: OfflineCacheService, from sourceID: String) async throws {
        let request = UUID(); offlineOpenRequest = request
        if offline?.entry.id == id { requestPageExpansion(from: sourceID); return }
        let descriptor = try await service.playback(id)
        guard offlineOpenRequest == request, !Task.isCancelled else {
            await service.releasePlayback(descriptor.leaseID); return
        }
        close()
        offline = descriptor; offlineService = service
        section = .description
        isDescriptionExpanded = false
        descriptionScroll = VideoDescriptionScrollState()
        let video = descriptor.entry.video
        route = VideoDetailRoute(bvid: video.bvid, cid: video.cid, cover: descriptor.coverURL?.absoluteString,
                                 title: video.displayTitle, artist: video.author, aid: video.aid)
        selectedCid = video.cid; hasRequestedPlayback = true
        let model = PlayerViewModel(bvid: video.bvid, cid: video.cid, offline: descriptor,
            configuration: playbackConfiguration,
            progressStore: dependencies.offlineProgress ?? PlaybackProgressStore(defaults: defaults, storageNamespace: "offline"),
            dependencies: dependencies)
        model.onPlaybackEnded = { [weak self, weak model] in
            guard let self, let model else { return }
            self.handlePlaybackEnded(for: model)
        }
        player = model
        model.updateSystemMediaMetadata(title: video.displayTitle, artist: video.author, artworkURL: descriptor.coverURL)
        playerLoadTask = Task { await model.load() }
        requestPageExpansion(from: sourceID)
    }

    // MARK: - 播放模式与播完切换

    /// 当前视频是否存在分 P / 合集（或离线多 P），用于区分「自动切集」与「自动连播」。
    var hasCurrentEpisodes: Bool {
        if let offline {
            return offlineGroupEntryIDsProvider(offline.entry.video.groupID).count > 1
        }
        let partsCount = detailViewModel?.detail?.pages.count ?? 0
        if partsCount > 1 { return true }
        return detailViewModel?.detail?.ugcSeason?.episodes.isEmpty == false
    }

    func handlePlaybackEnded(for endedPlayer: PlayerViewModel) {
        guard player === endedPlayer else { return }
        let action = resolveEndAction(sleepsAfterVideoEnd: endedPlayer.sleepsAfterVideoEnd, player: endedPlayer)
        switch action {
        case .sleep, .pause:
            break
        case .loop:
            endedPlayer.play()
        case .nextPart(let cid):
            hasRequestedPlayback = true
            selectPart(cid: cid)
        case .nextSeasonEpisode(let episode):
            openEpisode(episode, forceAutoPlay: true)
        case .nextOfflineEntry(let id):
            switchOfflineEntry(to: id)
        case .nextRelated(let video):
            openRelated(video, forceAutoPlay: true)
        }
    }

    func handleCastPlaybackEnded(mediaID: String, castSession: CastSessionModel) {
        guard let player else { return }
        let expectedID = player.isOffline ? "offline:\(player.bvid):\(player.cid)" : "video:\(player.bvid):\(player.cid)"
        guard expectedID == mediaID else { return }
        let action = resolveEndAction(sleepsAfterVideoEnd: player.sleepsAfterVideoEnd, player: player)
        switch action {
        case .sleep:
            player.cancelSleepTimer()
        case .pause:
            break
        case .loop:
            Task { await castSession.replayCurrentMedia() }
        case .nextPart(let cid):
            hasRequestedPlayback = true
            selectPart(cid: cid)
        case .nextSeasonEpisode(let episode):
            openEpisode(episode, forceAutoPlay: true)
        case .nextOfflineEntry(let id):
            switchOfflineEntry(to: id)
        case .nextRelated(let video):
            openRelated(video, forceAutoPlay: true)
        }
    }

    private func resolveEndAction(sleepsAfterVideoEnd: Bool, player: PlayerViewModel) -> PlaybackModeSettings.EndAction {
        let offlineIDs = offline.map { offlineGroupEntryIDsProvider($0.entry.video.groupID) } ?? []
        return PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: sleepsAfterVideoEnd,
            loopEnabled: PlaybackModeSettings.isLoopEnabled(in: defaults),
            autoAdvanceEnabled: PlaybackModeSettings.isAutoAdvanceEnabled(in: defaults),
            isOffline: player.isOffline,
            currentBvid: player.bvid,
            currentCid: player.cid,
            parts: detailViewModel?.detail?.pages ?? [],
            season: detailViewModel?.detail?.ugcSeason,
            related: detailViewModel?.related ?? [],
            visitedBvids: visitedBvids,
            offlineEntryIDs: offlineIDs,
            currentOfflineEntryID: offline?.entry.id
        )
    }

    private func switchOfflineEntry(to id: String) {
        guard let service = offlineService else { return }
        let sourceID = presentationState.entrySourceID
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.openOffline(id, service: service, from: sourceID)
        }
    }

    private func releaseOffline() {
        offlineOpenRequest = UUID()
        if let offline, let offlineService {
            if let player {
                player.stop { Task { await offlineService.releasePlayback(offline.leaseID) } }
            } else { Task { await offlineService.releasePlayback(offline.leaseID) } }
        }
        offline = nil; offlineService = nil
    }

    func removeOfflineProgress(for entry: OfflineCacheEntry) {
        let progress = dependencies.offlineProgress ?? PlaybackProgressStore(defaults: defaults, storageNamespace: "offline")
        progress.remove(bvid: entry.video.bvid, cid: entry.video.cid)
    }
}
