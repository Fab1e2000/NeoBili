import XCTest
@testable import NeoBili

@MainActor
final class DynamicFeatureTests: XCTestCase {
    private func entry(mid: Int, timestamp: Int, vote: String = "null") throws -> DynamicEntry {
        let json = """
        {"id_str":"1000", "type":"DYNAMIC_TYPE_WORD", "modules":{
          "module_author":{"mid":\(mid),"pub_ts":\(timestamp)},
          "module_dynamic":{"additional":{"type":"ADDITIONAL_TYPE_VOTE","vote":\(vote)}}
        }}
        """
        // 添加正文，使非投票的浏览状态样本也能正常进入列表。
        let withText = json.replacingOccurrences(of: "\"module_dynamic\":{", with: "\"module_dynamic\":{\"desc\":{\"text\":\"动态\"},")
        return try XCTUnwrap(JSONDecoder().decode(DynamicItem.self, from: Data(withText.utf8)).asEntry)
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

    func testReadingRestoresDefaultOrderAndNewUpdateMovesLeftAgain() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        var date = Date(timeIntervalSince1970: 1000)
        let store = FollowingReadStore(defaults: defaults, now: { date })
        store.configure(accountID: 1)
        let model = FollowingViewModel(readStore: store)
        let first = FollowedUp(mid: 1, uname: "一", face: "", hasUpdate: false)
        let second = FollowedUp(mid: 2, uname: "二", face: "", hasUpdate: true)
        model.replaceUps([first, second])
        model.select(.up(second))
        XCTAssertEqual(model.carouselItems.map(\.id), [.all, .up(2), .up(1)])
        let old = try entry(mid: 2, timestamp: 100)
        store.observe([old])
        store.markViewed(old)
        model.replaceUps([second, first])
        XCTAssertFalse(store.hasUpdate(second), "红点即时清除")
        XCTAssertEqual(model.carouselItems.map(\.id), [.all, .up(2), .up(1)])
        date = date.addingTimeInterval(299)
        store.expirePriority()
        XCTAssertEqual(model.carouselItems.map(\.id), [.all, .up(2), .up(1)])
        let pendingRestore = FollowingReadStore(defaults: defaults, now: { date })
        pendingRestore.configure(accountID: 1)
        XCTAssertTrue(pendingRestore.keepsPriority(second), "重启后保留剩余延时")
        date = date.addingTimeInterval(1)
        store.expirePriority()
        XCTAssertEqual(model.carouselItems.map(\.id), [.all, .up(1), .up(2)])
        XCTAssertEqual(model.selectedTarget.id, .up(2))
        store.observe([try entry(mid: 2, timestamp: 200)])
        XCTAssertEqual(model.carouselItems.map(\.id), [.all, .up(2), .up(1)])
        store.markViewed(old)
        XCTAssertTrue(store.hasUpdate(second), "浏览旧动态不能清除较新的更新")
        let restored = FollowingReadStore(defaults: defaults)
        restored.configure(accountID: 1)
        XCTAssertEqual(restored.readThrough["2"], 100)
        restored.configure(accountID: 2)
        XCTAssertTrue(restored.readThrough.isEmpty)
    }

    func testExpandedRepliesCannotBeCollapsedByOpeningAgain() async throws {
        let json = """
        {"rpid":1,"ctime":1,"like":0,"rcount":1,"member":{"uname":"作者","avatar":""},"content":{"message":"正文"}}
        """
        let comment = try JSONDecoder().decode(Comment.self, from: Data(json.utf8))
        let model = CommentsViewModel(aid: 1)
        model.setExpandedForTesting(rootId: 1, replies: [comment])
        await model.expandReplies(for: comment)
        XCTAssertTrue(model.isExpanded(comment))
        XCTAssertEqual(model.replies(for: comment).count, 1)
    }
}
