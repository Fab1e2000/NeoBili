#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

/// UP 主空间页的数据：头部名片、投稿列表，以及他自己的动态流。
///
/// 动态那一栏交给共用的 `DynamicFeedModel`，这里只管名片、关注状态和投稿。
@MainActor
@Observable
final class SpaceViewModel {
    @ObservationIgnored let filtering: VideoFilterDependencies
    @ObservationIgnored private let services: ApplicationServices
    let mid: Int
    let dynamics: DynamicFeedModel

    private(set) var card: SpaceCard?
    struct FollowContext: Hashable {
        let sessionID: UUID
        let isLoggedIn: Bool
        let accountID: Int?
    }

    /// nil 表示关系尚未确认，不能把它当成“未关注”来选择写入方向。
    private(set) var isFollowing: Bool?
    private(set) var followError: String?
    private(set) var isLoadingCard = false
    private(set) var isTogglingFollow = false
    private var followContext: FollowContext?
    private var cardRequestID = UUID()
    private var relationRevision = UUID()
    private var followWriteID = UUID()

    private(set) var videosGeneration = 0
    private(set) var videos: [SpaceVideo] = []
    private(set) var isLoadingVideos = false
    private(set) var isLoadingMoreVideos = false
    private(set) var videosError: String?

    private var videosRequestID = UUID()
    private var page = 1
    private var hasMoreVideos = true

    init(mid: Int, services: ApplicationServices = .live, filtering: VideoFilterDependencies = .live,
         likeStore: VideoLikeStore = .shared) {
        self.filtering = filtering
        self.services = services
        self.mid = mid
        dynamics = DynamicFeedModel(source: .space(hostMid: mid), likeStore: likeStore, services: services)
    }

    // MARK: - 名片

    func setFollowContext(_ next: FollowContext) {
        guard followContext != next else { return }
        followContext = next
        cardRequestID = UUID()
        relationRevision = UUID()
        followWriteID = UUID()
        isFollowing = nil
        followError = nil
        isLoadingCard = false
        isTogglingFollow = false
    }

    func isOwnAccount(_ context: FollowContext) -> Bool {
        context.isLoggedIn && context.accountID == mid
    }

    func loadCard(_ context: FollowContext) async {
        setFollowContext(context)
        guard !isTogglingFollow else { return }
        let request = UUID()
        let revision = relationRevision
        cardRequestID = request
        isLoadingCard = true
        followError = nil
        defer { if cardRequestID == request { isLoadingCard = false } }
        do {
            let card = try await services.community.spaceProfile(mid: mid)
            guard followContext == context, cardRequestID == request, !Task.isCancelled else { return }
            self.card = card
            // 旧名片可以更新公开资料，但不能覆盖读取之后刚完成的关注操作。
            if relationRevision == revision {
                isFollowing = context.isLoggedIn ? card.isFollowing : false
            }
        } catch {
            guard followContext == context, cardRequestID == request,
                  relationRevision == revision, !Task.isCancelled, !error.isCancellation else { return }
            followError = error.localizedDescription
        }
    }

    /// 仅对已知关系写入。失败回滚；旧登录会话的回调不能更新当前会话。
    func toggleFollow(_ context: FollowContext) async -> String? {
        guard context.isLoggedIn else { return String(localized: "请先登录") }
        guard !isOwnAccount(context) else { return String(localized: "不能关注自己") }
        guard followContext == context, let wasFollowing = isFollowing else {
            return String(localized: "关注状态尚未加载，请重试")
        }
        guard !isTogglingFollow else { return nil }
        relationRevision = UUID()
        let request = UUID()
        followWriteID = request
        isTogglingFollow = true
        isFollowing = !wasFollowing
        defer { if followWriteID == request { isTogglingFollow = false } }
        do {
            try await services.video.modifyRelation(mid: mid, follow: !wasFollowing)
            guard followContext == context, followWriteID == request, !Task.isCancelled else { return nil }
            return wasFollowing ? String(localized: "已取消关注") : String(localized: "toast.followed", defaultValue: "已关注")
        } catch {
            guard followContext == context, followWriteID == request else { return nil }
            isFollowing = wasFollowing
            return error.isCancellation ? nil : error.localizedDescription
        }
    }

    // MARK: - 投稿

    func loadVideosIfNeeded() async {
        guard videos.isEmpty else { return }
        await reloadVideos()
    }

    func reloadVideos() async {
        guard !isLoadingVideos else { return }
        let request = UUID()
        videosRequestID = request
        isLoadingMoreVideos = false
        isLoadingVideos = true
        videosError = nil
        defer { isLoadingVideos = false }

        do {
            let result = try await services.community.spaceVideos(mid: mid, page: 1)
            guard videosRequestID == request, !Task.isCancelled else { return }
            videosGeneration += 1
            videos = Self.removingDuplicates(result.videos)
            page = 1
            hasMoreVideos = result.hasMore(after: videos.count)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            // 刷新失败保留已可读的投稿和分页游标；首屏失败仍展示错误页。
            if videos.isEmpty { hasMoreVideos = false }
            videosError = error.localizedDescription
        }
    }

    func loadMoreVideosIfNeeded(
        current video: SpaceVideo,
        hidingKnownPortraitVideos hidesPortraitVideos: Bool = false
    ) async {
        let visibleVideos = videos.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: filtering)
        guard hasMoreVideos, !isLoadingVideos, !isLoadingMoreVideos,
              let index = visibleVideos.firstIndex(of: video),
              index >= visibleVideos.count - 5
        else { return }

        await loadReplacementPage()
    }

    func loadReplacementPage() async {
        guard hasMoreVideos, !isLoadingVideos, !isLoadingMoreVideos else { return }
        let request = videosRequestID
        isLoadingMoreVideos = true
        defer { if videosRequestID == request { isLoadingMoreVideos = false } }

        do {
            let result = try await services.community.spaceVideos(mid: mid, page: page + 1)
            guard videosRequestID == request, !Task.isCancelled else { return }
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
