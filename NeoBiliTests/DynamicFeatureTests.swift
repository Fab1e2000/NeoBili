#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class DynamicFeatureTests: XCTestCase {
    func testWatchLaterMenuBelongsToEmbeddedVideo() async throws {
        let video = FollowedVideo(id: "v", bvid: "BVfixture", aid: 17, title: "视频标题", cover: "",
                                  durationText: "", playText: "", authorMid: 42, authorName: "UP", authorFace: "", publishedText: "")
        let entry = DynamicEntry(id: "d", authorMid: 42, authorName: "UP", authorFace: "", publishedText: "",
                                 text: "正文", images: [], video: video, likeCount: 2, commentCount: 5,
                                 forwardCount: 0, isLikedByServer: false, commentOid: 17, commentType: 1)
        let card = DynamicCard(entry: entry, isLiked: false, likeCount: 2, onOpenVideo: {}, onOpenAuthor: {},
                               onLike: {}, onOpenDetail: {})
            .environment(\.hidesPortraitVideos, false)
            .environment(AccountStore(monitorNetwork: false))
            .environment(ActionFeedback())
            .dynamicTypeSize(.large)
            .frame(width: 320)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: card)
        host.safeAreaRegions = []
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 1_000))
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(120))
        window.layoutIfNeeded()

        func offersMenu(_ x: CGFloat, _ y: CGFloat) -> Bool {
            let point = CGPoint(x: x, y: y)
            var view = window.hitTest(point, with: nil)
            while let current = view {
                for case let menu as UIContextMenuInteraction in current.interactions {
                    let location = current.convert(point, from: window)
                    if menu.delegate?.contextMenuInteraction(menu, configurationForMenuAtLocation: location) != nil {
                        return true
                    }
                }
                view = current.superview
            }
            return false
        }
        XCTAssertTrue(offersMenu(160, size.height / 2), "视频封面可加入稍后再看")
        XCTAssertTrue(offersMenu(40, size.height - 44), "视频标题可加入稍后再看")
        XCTAssertFalse(offersMenu(24, 24), "作者头像有独立入口")
        XCTAssertFalse(offersMenu(4, size.height / 2), "视频以外的留白不显示视频菜单")
        XCTAssertFalse(offersMenu(270, size.height - 12), "点赞区不显示视频菜单")
    }

    func testVoteCardSurvivesDecodingWithoutTextOrImages() throws {
        let json = """
        {"id_str":"123", "type":"DYNAMIC_TYPE_WORD", "modules":{"module_dynamic":{
        "additional":{"type":"ADDITIONAL_TYPE_VOTE","vote":{"vote_id":"42","title":"选择一个","desc":"","join_num":"12"}}}}}
        """
        let result = try XCTUnwrap(JSONDecoder().decode(DynamicItem.self, from: Data(json.utf8)).asEntry)
        XCTAssertEqual(result.vote?.id, 42)
        XCTAssertEqual(result.vote?.title, "选择一个")
        XCTAssertEqual(result.vote?.participantCount, 12)
    }

    func testVoteInfoDecodesSelectionAndImageOptions() throws {
        let json = """
        {"vote_info":{"title":"图片投票","choice_cnt":"2","end_time":1,"join_num":"30",
        "options":[{"opt_idx":0,"opt_desc":"选项","cnt":12,"img_url":"https://example.com/a.png"}]},"my_votes":[0]}
        """
        let result = try JSONDecoder().decode(DynamicVoteResponse.self, from: Data(json.utf8))
        XCTAssertEqual(result.myVotes, [0])
        XCTAssertEqual(result.voteInfo.choiceCount, 2)
        XCTAssertTrue(result.voteInfo.hasEnded)
        XCTAssertEqual(result.voteInfo.options.first?.count, 12)
    }

    func testSelectingClearsServerDotAndHoldsPositionUntilPortalConfirms() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        var date = Date(timeIntervalSince1970: 1000)
        let store = FollowingReadStore(defaults: defaults, now: { date })
        store.configure(accountID: 1)
        let model = FollowingViewModel(readStore: store)
        let first = FollowedUp(mid: 1, uname: "一", face: "", hasUpdate: false)
        let second = FollowedUp(mid: 2, uname: "二", face: "", hasUpdate: true)
        model.replaceUps([first, second])
        XCTAssertEqual(model.selectionItems.map(\.id), [.all, .up(2), .up(1)])

        let target = try XCTUnwrap(model.selectionItems.first { $0.id == .up(2) })
        XCTAssertTrue(model.beginSelection(target), "有更新的 UP 主需要重新拉取")
        XCTAssertFalse(store.hasUpdate(second), "红点在点选时立即清除")
        XCTAssertFalse(model.beginSelection(target), "已清除的不再重复拉取")
        XCTAssertEqual(model.selectionItems.map(\.id), [.all, .up(2), .up(1)], "保位期内不跳走")

        // 清除请求尚未生效时，服务端仍报更新，不应让红点复活。
        date = date.addingTimeInterval(10)
        model.replaceUps([second, first])
        XCTAssertFalse(store.hasUpdate(second))

        // 服务端确认清除后撤掉本地覆盖；保位期结束回到默认顺序。
        model.replaceUps([FollowedUp(mid: 2, uname: "二", face: "", hasUpdate: false), first])
        XCTAssertTrue(store.cleared.isEmpty)
        let pendingRestore = FollowingReadStore(defaults: defaults, now: { date })
        pendingRestore.configure(accountID: 1)
        XCTAssertTrue(pendingRestore.keepsPriority(second), "重启后保留剩余保位时间")
        date = date.addingTimeInterval(300)
        store.expirePriority()
        XCTAssertEqual(model.selectionItems.map(\.id), [.all, .up(1), .up(2)])

        // 之后服务端再报更新，是真正的新动态，红点重新出现并排到前面。
        model.replaceUps([second, first])
        XCTAssertTrue(store.hasUpdate(second))
        XCTAssertEqual(model.selectionItems.map(\.id), [.all, .up(2), .up(1)])
    }

}

@MainActor
extension DynamicFeatureTests {
    func testOldDynamicPageCannotReplaceRefreshedCursor() async throws {
        let initial = try feed(id: "old", offset: "old-cursor")
        let refreshed = try feed(id: "new", offset: "new-cursor")
        let stale = try feed(id: "stale", offset: "stale-cursor")
        let next = try feed(id: "next", offset: "next-cursor")
        let pending = PendingModelResult<DynamicFeedPage>()
        var requests: [(Int, String?)] = []
        let model = DynamicFeedModel(source: .following, fetchFeed: { _, page, offset in
            requests.append((page, offset))
            switch requests.count {
            case 1: return initial
            case 2: return await pending.value()
            case 3: return refreshed
            default: return next
            }
        })
        await model.loadInitial()
        let oldPage = Task { await model.loadMoreIfNeeded(current: initial.entries[0]) }
        await waitForPendingRequest { pending.isWaiting }
        await model.refresh()
        pending.resolve(stale)
        await oldPage.value
        XCTAssertEqual(model.entries.map(\.id), ["new"])
        await model.loadMoreIfNeeded(current: refreshed.entries[0])
        XCTAssertEqual(requests.last?.0, 2)
        XCTAssertEqual(requests.last?.1, "new-cursor")
        XCTAssertEqual(model.entries.map(\.id), ["new", "next"])
    }

    func testOldRefreshCannotClearNewLoadingFlag() async throws {
        let old = PendingModelResult<DynamicFeedPage>(), new = PendingModelResult<DynamicFeedPage>()
        var calls = 0
        let model = DynamicFeedModel(source: .following, fetchFeed: { _, _, _ in
            calls += 1
            return await (calls == 1 ? old : new).value()
        })
        let first = Task { await model.refresh() }
        await waitForPendingRequest { old.isWaiting }
        let second = Task { await model.refresh() }
        await waitForPendingRequest { new.isWaiting }
        old.resolve(try feed(id: "old", offset: "old"))
        await first.value
        XCTAssertTrue(model.isLoading)
        new.resolve(try feed(id: "new", offset: "new"))
        await second.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.entries.map(\.id), ["new"])
    }

    func testOldAccountDynamicResponseIsDiscarded() async throws {
        let likes = VideoLikeStore()
        let pending = PendingModelResult<DynamicFeedPage>()
        let model = DynamicFeedModel(source: .following, likeStore: likes,
                                     fetchFeed: { _, _, _ in await pending.value() })
        let request = Task { await model.loadInitial() }
        await waitForPendingRequest { pending.isWaiting }
        likes.resetSession()
        pending.resolve(try feed(id: "old-account", offset: "old"))
        await request.value
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testStagedDynamicRefreshKeepsOldCardsAndBlocksPaginationUntilCommit() async throws {
        let first = try feed(id: "1", offset: "old")
        let second = try feed(id: "2", offset: "new")
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore(), fetchFeed: { _, _, _ in
            calls += 1
            return calls == 1 ? first : second
        })
        await model.loadInitial()
        let stagingID = UUID()
        await model.refresh(staged: true, stagingID: stagingID)
        model.commitStagedRefresh(id: UUID())
        XCTAssertEqual(model.entries.map(\.id), ["1"], "旧任务不能提交新一轮暂存结果")
        await model.loadMoreIfNeeded(current: first.entries[0])
        XCTAssertEqual(calls, 2)
        model.commitStagedRefresh()
        XCTAssertEqual(model.entries.map(\.id), ["2"])
        model.commitStagedRefresh()
        XCTAssertEqual(model.entries.map(\.id), ["2"])
    }

    func testFailedStagedDynamicRefreshPreservesExistingCards() async throws {
        let first = try feed(id: "1", offset: "old")
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore(), fetchFeed: { _, _, _ in
            calls += 1
            if calls > 1 { throw URLError(.notConnectedToInternet) }
            return first
        })
        await model.loadInitial()
        await model.refresh(staged: true)
        model.commitStagedRefresh()
        XCTAssertEqual(model.entries.map(\.id), ["1"])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    private func feed(id: String, offset: String) throws -> DynamicFeedPage {
        try decode("""
        {"has_more":true,"offset":"\(offset)","items":[{"id_str":"\(id)","type":"DYNAMIC_TYPE_WORD",
        "modules":{"module_dynamic":{"desc":{"text":"test"}}}}]}
        """)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
