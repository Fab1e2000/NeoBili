import Foundation
import SwiftUI

/// 当前视频及其视频页状态。
///
/// 播放器由根视图持有，视频页和小窗共享同一份状态；显式关闭小窗或禁用小窗后
/// 退出视频页时，通过 `close()` 释放播放器和相关加载任务。
@MainActor
@Observable
final class NowPlayingStore {
    /// 播放配置每次新建播放器时从系统设置现读（见 `VideoPlaybackConfiguration.current`），
    /// 设置页改完清晰度，下一个打开的视频就生效。
    var playbackConfiguration: VideoPlaybackConfiguration {
        VideoPlaybackConfiguration.current
    }

    /// 当前视频。为 nil 表示当前没有打开的视频页。
    private(set) var route: VideoDetailRoute?
    private(set) var detailViewModel: VideoDetailViewModel?
    private(set) var commentsViewModel: CommentsViewModel?
    private(set) var player: PlayerViewModel?

    /// 全屏视频页是否正在显示。
    var isExpanded = false
    private(set) var isMiniPlayerPresented = false
    private(set) var isVideoPageDismissalInProgress = false
    private(set) var isVideoPageInteractionInProgress = false
    private(set) var dismissalPlaybackPhase: InlineVideoPlaybackPhase?
    /// 根页面和服务 sheet 共用停靠位置，切换承载页面时不跳回默认角落。
    var miniPlayerAnchor = CGPoint(x: 1, y: 1)
    private let defaults: UserDefaults

    /// 视频下方停在简介还是评论。
    var section: VideoPageSection = .description
    /// 简介是否已经展开。
    var isDescriptionExpanded = false
    /// 当前选中的分P。
    private(set) var selectedCid: Int?

    /// 两个列表各自的滚动位置，切换视频页内容时回到原处。
    var descriptionScroll = ScrollPosition(edge: .top)
    var commentsScroll = ScrollPosition(edge: .top)

    static let miniPlayerTransitionSourceID = "neobili.mini-player"

    /// 进入时从触发入口放大；页面呈现完成后，退出目标更新为同一小窗。
    private(set) var transitionSourceID = ""
    private var cardTransitionSourceID = ""

    /// 视频页里点相关视频是就地替换，这里记着来路，供左上角返回按钮逐级回退。
    private var history: [VideoDetailRoute] = []
    private var loadTasks: [Task<Void, Never>] = []
    private var playerLoadTask: Task<Void, Never>?

    init(configuration: VideoPlaybackConfiguration = .fastStart, defaults: UserDefaults = .standard) {
        // configuration 形参保留给测试注入使用；线上路径每次都读 `.current`。
        _ = configuration
        self.defaults = defaults
    }

    /// 服务 sheet 打开期间，由它承载视频模态，根 TabView 暂停呈现。
    var isServiceSheetPresented = false

    var canGoBack: Bool { !history.isEmpty }

    /// 正在播放的分P。入口已经给了 cid 时立刻有值，播放器不必等详情接口。
    var activeCid: Int? {
        selectedCid ?? detailViewModel?.detail?.cid
    }

    // MARK: - 打开与关闭

    /// 从推荐页或搜索页的卡片打开。
    /// 点的是正在播的那个视频时只重新显示，不重新加载，进度也不会丢。
    func open(_ newRoute: VideoDetailRoute, from sourceID: String) {
        let needsRestart = isVideoPageDismissalInProgress && !isMiniPlayerPresented
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        cardTransitionSourceID = sourceID
        transitionSourceID = sourceID
        if route?.bvid == newRoute.bvid, !needsRestart {
            player?.session.surfacePresentation = .page
            isMiniPlayerPresented = false
            isExpanded = true
            return
        }
        history.removeAll()
        start(newRoute)
        isExpanded = true
    }

    /// 视频页里点相关视频：就地换掉当前视频，旧的压进历史。
    func openRelated(_ video: VideoSummary) {
        if let route {
            history.append(route)
        }
        start(
            VideoDetailRoute(
                bvid: video.bvid,
                cid: video.cid,
                cover: video.pic,
                title: video.title,
                artist: video.owner.name
            )
        )
    }

    /// 合集里选另一集：和点相关视频一样就地换片，旧的压进历史，
    /// 所以左上角返回能一级级退回原来那一集。
    func openEpisode(_ episode: UgcSeasonEpisode) {
        guard let bvid = episode.bvid else { return }
        if let route {
            history.append(route)
        }
        start(
            VideoDetailRoute(
                bvid: bvid,
                cid: episode.cid,
                cover: episode.arc?.pic,
                title: episode.title,
                artist: detailViewModel?.detail?.owner.name
            )
        )
    }

    /// 左上角返回：先在历史里逐级回退，退到底了退出视频页并按设置继续小窗播放。
    func goBack() {
        if let previous = history.popLast() {
            start(previous)
        } else {
            dismissVideoPage()
        }
    }

    /// 等原生进入转场完成再换目标，保留从卡片打开的路径。
    func videoPageDidAppear() {
        guard isExpanded, route != nil, !isVideoPageInteractionInProgress else { return }
        transitionSourceID = PlaybackWindowSettings.isEnabled(in: defaults)
            ? Self.miniPlayerTransitionSourceID : cardTransitionSourceID
    }

    /// UIKit begins the interactive transition before SwiftUI changes its binding.
    /// Freeze page layout now, without committing dismissal or pausing playback.
    func videoPageInteractionBegan() {
        guard isExpanded, route != nil else { return }
        isVideoPageInteractionInProgress = true
        dismissalPlaybackPhase = InlineVideoPlaybackPhase(
            isPlaying: player?.isPlaying == true,
            hasRenderedFirstFrame: player?.hasRenderedFirstFrame == true,
            isLoading: player?.isLoading ?? true
        )
    }

    func videoPageInteractionEnded(cancelled: Bool) {
        guard isVideoPageInteractionInProgress else { return }
        isVideoPageInteractionInProgress = false
        if cancelled, route != nil {
            let resume = isVideoPageDismissalInProgress && dismissalPlaybackPhase == .playing
            isExpanded = true
            isMiniPlayerPresented = false
            isVideoPageDismissalInProgress = false
            dismissalPlaybackPhase = nil
            player?.session.surfacePresentation = .page
            if resume { player?.play() }
        }
    }

    /// 小窗已提前位于停靠点，原生 zoom 退出时可以直接找到稳定的目标。
    func dismissVideoPage() {
        guard !isVideoPageDismissalInProgress else { return }
        player?.savePlaybackProgress()
        guard route != nil else { close(); return }
        dismissalPlaybackPhase = InlineVideoPlaybackPhase(
            isPlaying: player?.isPlaying == true,
            hasRenderedFirstFrame: player?.hasRenderedFirstFrame == true,
            isLoading: player?.isLoading ?? true
        )
        isVideoPageDismissalInProgress = true
        if PlaybackWindowSettings.isEnabled(in: defaults), route != nil {
            // Keep rendering into the shrinking page until UIKit has finished
            // its transition. The mini's cover fills its source in the meantime.
            isMiniPlayerPresented = true
            isExpanded = false
        } else {
            // Keep the shrinking page intact. Destroying mpv synchronously and
            // clearing its models here interrupts UIKit's native zoom animation.
            player?.pauseForDismissal()
            isMiniPlayerPresented = false
            isExpanded = false
        }
    }

    func expandMiniPlayer() {
        guard route != nil else { return }
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        transitionSourceID = Self.miniPlayerTransitionSourceID
        player?.session.surfacePresentation = .page
        isMiniPlayerPresented = false
        isExpanded = true
    }

    func applyMiniPlayerSetting() {
        if !PlaybackWindowSettings.isEnabled(in: defaults), isMiniPlayerPresented { close() }
        else if isExpanded { videoPageDidAppear() }
    }

    /// 关闭视频页并彻底停止播放。
    func close() {
        cancelLoads()
        player?.stop()
        player = nil
        detailViewModel = nil
        commentsViewModel = nil
        route = nil
        history.removeAll()
        isExpanded = false
        isMiniPlayerPresented = false
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
    }

    /// Called by fullScreenCover's onDismiss after the system animation ends.
    /// The old dismissal callback may arrive after the user has tapped another
    /// card. In that case `open` has made the new page expanded again, so the
    /// stale callback must not tear down the new route and player.
    func finishDismissal() {
        guard !isExpanded else { return }
        isVideoPageDismissalInProgress = false
        isVideoPageInteractionInProgress = false
        dismissalPlaybackPhase = nil
        if PlaybackWindowSettings.isEnabled(in: defaults), route != nil {
            player?.session.surfacePresentation = .mini
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
    private func start(_ newRoute: VideoDetailRoute) {
        cancelLoads()
        player?.stop()
        player = nil
        isMiniPlayerPresented = false

        route = newRoute
        selectedCid = newRoute.cid
        section = .description
        isDescriptionExpanded = false
        descriptionScroll = ScrollPosition(edge: .top)
        commentsScroll = ScrollPosition(edge: .top)
        commentsViewModel = nil

        let viewModel = VideoDetailViewModel(bvid: newRoute.bvid)
        detailViewModel = viewModel

        loadTasks = [
            Task { [weak self] in
                guard !Task.isCancelled else { return }
                await viewModel.load()
                guard !Task.isCancelled, self?.detailViewModel === viewModel else { return }
                self?.startPlayerIfPossible()
                self?.refreshSystemMediaMetadata()
                self?.buildCommentsIfNeeded()
                // 标签、互动状态、UP 主名片都要用详情里的 aid / mid，
                // 所以只能排在详情之后；三者内部仍然是并行发出的。
                await viewModel.loadExtras()
            },
            // 相关视频和详情各自独立请求，互不等待。
            Task {
                guard !Task.isCancelled else { return }
                await viewModel.loadRelated()
            }
        ]

        // 入口带了 cid 的话这里就能直接开始取流，不用等上面的详情接口。
        startPlayerIfPossible()
    }

    private func startPlayerIfPossible() {
        guard let route, let cid = activeCid else { return }
        // 已经在放这一个了就不要重建，否则会打断正在进行的播放。
        if let player, player.bvid == route.bvid, player.cid == cid { return }

        playerLoadTask?.cancel()
        playerLoadTask = nil
        player?.stop()
        let newPlayer = PlayerViewModel(
            bvid: route.bvid,
            cid: cid,
            configuration: playbackConfiguration
        )
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
        var title = detail?.title ?? route.title ?? "Bilibili 视频"
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
            commentsViewModel = CommentsViewModel(aid: aid)
        }
    }

    private func cancelLoads() {
        playerLoadTask?.cancel()
        playerLoadTask = nil
        for task in loadTasks {
            task.cancel()
        }
        loadTasks.removeAll()
    }
}
