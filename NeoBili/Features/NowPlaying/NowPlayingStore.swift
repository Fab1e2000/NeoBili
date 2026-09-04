import Foundation
import SwiftUI

/// 当前视频及其视频页状态。
///
/// 播放器由根视图持有，便于视频页的展示和关闭共享同一份状态；视频页退出时会通过
/// `close()` 释放播放器和相关加载任务。
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

    /// 视频下方停在简介还是评论。
    var section: VideoPageSection = .description
    /// 简介是否已经展开。
    var isDescriptionExpanded = false
    /// 当前选中的分P。
    private(set) var selectedCid: Int?

    /// 两个列表各自的滚动位置，切换视频页内容时回到原处。
    var descriptionScroll = ScrollPosition(edge: .top)
    var commentsScroll = ScrollPosition(edge: .top)

    /// zoom 转场从哪里放大。现在只从列表卡片打开视频页。
    private(set) var transitionSourceID = ""

    /// 视频页里点相关视频是就地替换，这里记着来路，供左上角返回按钮逐级回退。
    private var history: [VideoDetailRoute] = []
    private var loadTasks: [Task<Void, Never>] = []
    private var playerLoadTask: Task<Void, Never>?

    init(configuration: VideoPlaybackConfiguration = .fastStart) {
        // configuration 形参保留给测试注入使用；线上路径每次都读 `.current`。
        _ = configuration
    }

    var canGoBack: Bool { !history.isEmpty }

    /// 正在播放的分P。入口已经给了 cid 时立刻有值，播放器不必等详情接口。
    var activeCid: Int? {
        selectedCid ?? detailViewModel?.detail?.cid
    }

    // MARK: - 打开与关闭

    /// 从推荐页或搜索页的卡片打开。
    /// 点的是正在播的那个视频时只重新显示，不重新加载，进度也不会丢。
    func open(_ newRoute: VideoDetailRoute, from sourceID: String) {
        transitionSourceID = sourceID
        if route?.bvid == newRoute.bvid {
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

    /// 左上角返回：先在历史里逐级回退，退到底了就关闭视频并停止播放。
    func goBack() {
        if let previous = history.popLast() {
            start(previous)
        } else {
            close()
        }
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
    }

    /// Called by the disappearing full-screen page. SwiftUI may deliver the
    /// old page's `onDisappear` after the user has already tapped another
    /// card. In that case `open` has made the new page expanded again, so the
    /// stale callback must not tear down the new route and player.
    func finishDismissal() {
        guard !isExpanded else { return }
        close()
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
                await viewModel.load()
                self?.startPlayerIfPossible()
                self?.refreshSystemMediaMetadata()
                self?.buildCommentsIfNeeded()
                // 标签、互动状态、UP 主名片都要用详情里的 aid / mid，
                // 所以只能排在详情之后；三者内部仍然是并行发出的。
                await viewModel.loadExtras()
            },
            // 相关视频和详情各自独立请求，互不等待。
            Task { await viewModel.loadRelated() }
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
        player = newPlayer
        refreshSystemMediaMetadata()
        playerLoadTask = Task { await newPlayer.load() }
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
        if commentsViewModel?.aid != aid {
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
