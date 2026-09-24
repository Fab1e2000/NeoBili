import XCTest
@testable import NeoBili

@MainActor
final class DynamicFeatureTests: XCTestCase {
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
