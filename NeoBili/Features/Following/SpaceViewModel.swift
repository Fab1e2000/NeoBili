import Foundation

/// UP 主空间页的数据：头部名片、投稿列表，以及他自己的动态流。
///
/// 动态那一栏交给共用的 `DynamicFeedModel`，这里只管名片、关注状态和投稿。
@MainActor
@Observable
final class SpaceViewModel {
    let mid: Int
    let dynamics: DynamicFeedModel

    private(set) var card: SpaceCard?
    /// 关注状态单独存一份：点了关注按钮要立刻变，不能等名片接口重拉。
    private(set) var isFollowing = false

    private(set) var videos: [SpaceVideo] = []
    private(set) var isLoadingVideos = false
    private(set) var isLoadingMoreVideos = false
    private(set) var videosError: String?

    private var page = 1
    private var hasMoreVideos = true
    private var isTogglingFollow = false

    init(mid: Int) {
        self.mid = mid
        dynamics = DynamicFeedModel(source: .space(hostMid: mid))
    }

    /// 进页面时先把名片和投稿一起要回来。动态那一栏等用户真的切过去再加载。
    func loadInitial() async {
        async let profile: Void = loadCardIfNeeded()
        await loadVideosIfNeeded()
        await profile
    }

    // MARK: - 名片

    private func loadCardIfNeeded() async {
        guard card == nil else { return }
        await loadCard()
    }

    func loadCard() async {
        guard let card = try? await BiliAPI.spaceCard(mid: mid), !Task.isCancelled else { return }
        self.card = card
        isFollowing = card.isFollowing
    }

    /// 关注 / 取消关注。界面先变，失败再改回去并把接口原话交给调用方提示。
    func toggleFollow(isLoggedIn: Bool) async -> String? {
        guard isLoggedIn else { return "请先登录" }
        guard !isTogglingFollow else { return nil }
        isTogglingFollow = true
        defer { isTogglingFollow = false }

        let wasFollowing = isFollowing
        isFollowing = !wasFollowing
        do {
            try await BiliAPI.modifyRelation(mid: mid, follow: !wasFollowing)
            return wasFollowing ? "已取消关注" : "已关注"
        } catch {
            isFollowing = wasFollowing
            return error.isCancellation ? nil : error.localizedDescription
        }
    }

    // MARK: - 投稿

    private func loadVideosIfNeeded() async {
        guard videos.isEmpty else { return }
        await reloadVideos()
    }

    func reloadVideos() async {
        isLoadingVideos = true
        videosError = nil
        defer { isLoadingVideos = false }

        do {
            let result = try await BiliAPI.spaceVideos(mid: mid, page: 1)
            guard !Task.isCancelled else { return }
            videos = Self.removingDuplicates(result.videos)
            page = 1
            hasMoreVideos = result.hasMore(after: videos.count)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            videos = []
            hasMoreVideos = false
            videosError = error.localizedDescription
        }
    }

    func loadMoreVideosIfNeeded(current video: SpaceVideo) async {
        guard hasMoreVideos, !isLoadingVideos, !isLoadingMoreVideos,
              let index = videos.firstIndex(of: video),
              index >= videos.count - 5
        else { return }

        isLoadingMoreVideos = true
        defer { isLoadingMoreVideos = false }

        do {
            let result = try await BiliAPI.spaceVideos(mid: mid, page: page + 1)
            guard !Task.isCancelled else { return }
            page += 1
            let existing = Set(videos.map(\.bvid))
            videos.append(contentsOf: Self.removingDuplicates(result.videos).filter { !existing.contains($0.bvid) })
            hasMoreVideos = result.hasMore(after: videos.count) && !result.videos.isEmpty
        } catch {
            // 翻页失败静默收手，再滚一次会重试。
        }
    }

    private static func removingDuplicates(_ videos: [SpaceVideo]) -> [SpaceVideo] {
        var seen = Set<String>()
        return videos.filter { !$0.bvid.isEmpty && seen.insert($0.bvid).inserted }
    }
}
