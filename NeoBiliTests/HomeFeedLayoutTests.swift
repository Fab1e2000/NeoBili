import XCTest
@testable import NeoBili

@MainActor
final class HomeFeedLayoutTests: XCTestCase {
    func testRefreshRestartsPageIndexAndPaginationContinuesWithinSession() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(1234, forKey: "neobili.recommendFreshIndex")
        var requested: [Int] = []
        let model = HomeViewModel(defaults: defaults, fetchRecommendations: { request in
            let index = request.pageIndex
            requested.append(index)
            return RecommendationBatch(videos: [self.video(requested.count)], nextRequest: request.next(appCursor: request.pageIndex + 1))
        })
        await model.loadInitial()
        await model.loadMoreIfNeeded(current: model.videos.last!)
        await model.refresh()
        await model.loadMoreIfNeeded(current: model.videos.last!)
        XCTAssertEqual(requested, [0, 1, 0, 1])
    }

    func testFailedRefreshKeepsContentAndRetriesRecommendationFirstBatch() async {
        var requested: [Int] = []
        let model = HomeViewModel(fetchRecommendations: { request in
            let index = request.pageIndex
            requested.append(index)
            if requested.count == 2 { throw URLError(.notConnectedToInternet) }
            return RecommendationBatch(videos: [self.video(requested.count)], nextRequest: request.next(appCursor: request.pageIndex + 1))
        })
        await model.loadInitial()
        await model.refresh()
        XCTAssertEqual(model.videos.map(\.aid), [1])
        XCTAssertNotNil(model.errorMessage)
        await model.refresh()
        XCTAssertEqual(requested, [0, 0, 0])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.videos.first?.aid, 3)
    }

    func testStagedRefreshDoesNotReplaceCardsBeforeExitCompletes() async {
        var requests = 0
        let model = HomeViewModel(fetchRecommendations: { request in
            requests += 1
            return RecommendationBatch(videos: [self.video(requests)], nextRequest: request.next(appCursor: request.pageIndex + 1))
        })
        await model.loadInitial()
        await model.refresh(staged: true)
        XCTAssertEqual(model.videos.first?.aid, 1)
        model.commitStagedRefresh()
        XCTAssertEqual(model.videos.first?.aid, 2)
    }

    func testAppPaginationUsesServerCursorAcrossRetryFilteredAndDuplicatePages() async {
        var requested: [RecommendationRequest] = []
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, fetchRecommendations: { request in
            requested.append(request)
            switch requested.count {
            case 1: return RecommendationBatch(videos: [self.video(1)], nextRequest: request.next(appCursor: 1745482992))
            case 2: throw URLError(.notConnectedToInternet)
            case 3: return RecommendationBatch(videos: [], nextRequest: request.next(appCursor: 1745482980))
            case 4: return RecommendationBatch(videos: [self.video(1)], nextRequest: request.next(appCursor: 1745482970))
            default: return RecommendationBatch(videos: [self.video(2)], nextRequest: nil)
            }
        })
        await model.loadInitial()
        await model.loadReplacementPage()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.videos.map(\.aid), [1])
        await model.loadReplacementPage()
        await model.loadReplacementPage()
        await model.loadReplacementPage()
        await model.loadReplacementPage() // No cursor: no extra request.
        XCTAssertEqual(requested.map(\.appCursor), [0, 1745482992, 1745482992, 1745482980, 1745482970])
        XCTAssertEqual(requested.map(\.pageIndex), [0, 1, 1, 2, 3])
        XCTAssertEqual(requested.map { AppRecommendationProtocol.parameters(for: $0)["flush"] }, ["0", "8", "8", "8", "8"])
        XCTAssertEqual(requested[1], requested[2], "Retry preserves the complete request")
        XCTAssertEqual(model.videos.map(\.aid), [1, 2])
        XCTAssertNil(model.errorMessage)
    }

    func testSourceChangeRefreshAndAccountChangeResetAppCursorAndWebPage() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var account = HomeFeedAccount(accountID: 1, hasAppCredential: true)
        var requested: [RecommendationRequest] = []
        let model = HomeViewModel(defaults: defaults, currentAccount: { account }, fetchRecommendations: { request in
            requested.append(request)
            return RecommendationBatch(videos: [self.video(requested.count)],
                nextRequest: request.next(appCursor: request.source == .app ? 1745482992 : 0))
        })
        await model.loadInitial()
        await model.loadReplacementPage()
        defaults.set(false, forKey: RecommendationFilter.appRecommendKey)
        await model.refresh()
        await model.loadReplacementPage()
        defaults.set(true, forKey: RecommendationFilter.appRecommendKey)
        await model.refresh(staged: true)
        await model.loadReplacementPage()
        XCTAssertEqual(requested.count, 5, "Pending animation blocks pagination")
        model.commitStagedRefresh()
        await model.loadReplacementPage()
        account = HomeFeedAccount(accountID: 2, hasAppCredential: true)
        await model.refreshIfAccountChanged(to: account)
        XCTAssertEqual(requested.map(\.source), [.app, .app, .web, .web, .app, .app, .app])
        XCTAssertEqual(requested.map(\.pageIndex), [0, 1, 0, 1, 0, 1, 0])
        XCTAssertEqual(requested.map(\.appCursor), [0, 1745482992, 0, 0, 0, 1745482992, 0])
        XCTAssertEqual(requested.map(\.isRefresh), [false, false, true, false, true, false, true])
    }

    func testLateCancelledPageCannotOverwriteRefreshedCursor() async {
        var requested: [RecommendationRequest] = []
        var pending: CheckedContinuation<RecommendationBatch, Never>?
        let suspended = expectation(description: "Old pagination suspended")
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, fetchRecommendations: { request in
            requested.append(request)
            if requested.count == 2 {
                return await withCheckedContinuation {
                    pending = $0
                    suspended.fulfill()
                }
            }
            return RecommendationBatch(videos: [self.video(requested.count)],
                nextRequest: request.next(appCursor: requested.count == 1 ? 111 : 222))
        })
        await model.loadInitial()
        let oldPage = Task { await model.loadReplacementPage() }
        await fulfillment(of: [suspended], timeout: 2)
        await model.refresh()
        pending?.resume(returning: RecommendationBatch(videos: [video(99)],
            nextRequest: RecommendationRequest(source: .app, pageIndex: 2, appCursor: 999)))
        await oldPage.value
        await model.loadReplacementPage()
        XCTAssertEqual(requested.map(\.appCursor), [0, 111, 111, 222])
        XCTAssertFalse(model.videos.contains { $0.aid == 99 })
        XCTAssertNil(model.errorMessage)
    }

    func testExitStartsWithRefreshAndOnlyWaitsForRemainingTime() {
        let exit = FeedRefreshExitTiming(start: 10, duration: FeedRefreshTuning.fadeExit)
        XCTAssertEqual(exit.remaining(at: 10), 0.225, accuracy: 0.001)
        XCTAssertEqual(exit.remaining(at: 10.1), 0.125, accuracy: 0.001)
        XCTAssertEqual(exit.remaining(at: 12), 0)
    }

    private func video(_ id: Int) -> VideoSummary {
        VideoSummary(bvid: "BV\(id)", aid: id, cid: id, title: "视频", pic: "", desc: "", duration: 1,
                     pubdate: 1, owner: VideoOwner(mid: 42, name: "UP", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                     recommendationFeedback: RecommendationFeedbackOptions(
                        goto: "av", param: id, dislikeReasons: [reason], feedbacks: nil))
    }

    func testOddRefreshBoundaryFinishesRowBeforeMarkerWithoutLosingVideos() {
        let rows = HomeFeedRow.group([.video(video(1)), .video(video(2)), .video(video(3)),
                                      .lastSeen, .video(video(4)), .video(video(5))])
        XCTAssertEqual(rows.map(\.id), ["row-BV1", "row-BV3", "last-seen-row", "row-BV5"])
        let videos = rows.flatMap { row -> [VideoSummary] in
            if case .videos(let videos) = row { return videos }
            return []
        }
        XCTAssertEqual(videos.map(\.aid), [1, 2, 3, 4, 5])
        guard case .videos(let before) = rows[1] else { return XCTFail("Expected complete row") }
        XCTAssertEqual(before.map(\.aid), [3, 4])
    }

    func testEvenRefreshBoundaryKeepsMarkerInPlace() {
        let rows = HomeFeedRow.group([.video(video(1)), .video(video(2)), .lastSeen,
                                      .video(video(3)), .video(video(4))])
        XCTAssertEqual(rows.map(\.id), ["row-BV1", "last-seen-row", "row-BV3"])
    }

    func testOddBoundaryWithNoVisibleOldVideosDoesNotLeaveMarkerUnderHalfRow() {
        let rows = HomeFeedRow.group([.video(video(1)), .lastSeen])
        XCTAssertEqual(rows.map(\.id), ["row-BV1"])
    }

    private let reason = RecommendationFeedbackOptions.Reason(id: 17, name: "不感兴趣", toast: "将减少相似内容推荐")

    func testFeedbackUsesCardGotoAndParam() {
        let params = BiliAPI.feedbackParameters(video(123).recommendationFeedback!)
        XCTAssertEqual(params["goto"], "av")
        XCTAssertEqual(params["id"], "123")
        for (key, value) in AppClientIdentity.parameters { XCTAssertEqual(params[key], value) }
    }

    func testSuccessfulFeedbackRemovesCardAndShiftsLastSeenMarker() async {
        var requests = 0
        var reported: [Int] = []
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                  reportUninterested: { options, reason in reported.append(options.param + reason.id) },
                                  fetchRecommendations: { request in
            requests += 1
            return RecommendationBatch(videos: requests == 1 ? [self.video(1), self.video(2)] : [self.video(3), self.video(4)], nextRequest: request.next(appCursor: request.pageIndex + 1))
        })
        await model.loadInitial()
        await model.refresh()
        XCTAssertEqual(model.lastRefreshAt, 2)
        let message = await model.markUninterested(model.videos[0], reason: reason)
        XCTAssertEqual(message, "将减少相似内容推荐")
        XCTAssertEqual(reported, [3 + 17])
        XCTAssertEqual(model.videos.map(\.aid), [4, 1, 2])
        XCTAssertEqual(model.lastRefreshAt, 1)
        XCTAssertTrue(model.reportingIDs.isEmpty)
    }

    func testFailedFeedbackKeepsCard() async {
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                  reportUninterested: { _, _ in throw URLError(.notConnectedToInternet) },
                                  fetchRecommendations: { request in RecommendationBatch(videos: [self.video(1)], nextRequest: request.next(appCursor: 1)) })
        await model.loadInitial()
        let error = await model.markUninterested(model.videos[0], reason: reason)
        XCTAssertNotNil(error)
        XCTAssertEqual(model.videos.map(\.aid), [1])
        XCTAssertTrue(model.reportingIDs.isEmpty)
    }

    func testWebDislikeRemovesCardButUndoKeepsIt() async {
        var calls: [Bool] = []
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                  dislikeVideo: { _, dislike in calls.append(dislike) },
                                  fetchRecommendations: { request in RecommendationBatch(videos: [self.video(1), self.video(2)], nextRequest: request.next(appCursor: 1)) })
        await model.loadInitial()
        let undo = await model.dislikeWebRecommendation(model.videos[1], dislike: false)
        XCTAssertEqual(undo, "取消踩")
        XCTAssertEqual(model.videos.count, 2)
        let done = await model.dislikeWebRecommendation(model.videos[0], dislike: true)
        XCTAssertEqual(done, "点踩成功")
        XCTAssertEqual(model.videos.map(\.aid), [2])
        XCTAssertEqual(calls, [false, true])
    }

    func testAccountRestoreDoesNotRefetchButRealChangeDoes() async {
        var requests: [Int] = []
        var account = HomeFeedAccount(accountID: 42, hasAppCredential: true)
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                  currentAccount: { account },
                                  fetchRecommendations: { request in
            let index = request.pageIndex
            requests.append(index)
            return RecommendationBatch(videos: [self.video(requests.count)], nextRequest: request.next(appCursor: request.pageIndex + 1))
        })
        await model.loadInitial()
        // 启动时恢复账号：界面上的账号从空变成 42，但第一页本来就是用 42 取的。
        await model.refreshIfAccountChanged(to: HomeFeedAccount(accountID: 42, hasAppCredential: true))
        XCTAssertEqual(requests, [0])
        account = HomeFeedAccount(accountID: 42, hasAppCredential: false)
        await model.refreshIfAccountChanged(to: account)
        XCTAssertEqual(requests, [0, 0])
    }

    func testBlockingRemovesAllCardsOfThatOwnerAndRemembersHim() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var blocked: [Int] = []
        let model = HomeViewModel(defaults: defaults, blockUser: { blocked.append($0) },
                                  fetchRecommendations: { request in RecommendationBatch(videos: [self.video(1), self.video(2)], nextRequest: request.next(appCursor: 1)) })
        await model.loadInitial()
        let message = await model.block(VideoOwner(mid: 42, name: "UP", face: ""))
        XCTAssertEqual(message, "已拉黑 UP")
        XCTAssertEqual(blocked, [42])
        XCTAssertTrue(model.videos.isEmpty)
        XCTAssertEqual(RecommendationFilter.current(defaults).blockedMids, [42])
    }

    func testRefreshWithoutKeepingLastDataReplacesFeed() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: RecommendationFilter.keepLastDataKey)
        var requests = 0
        let model = HomeViewModel(defaults: defaults, fetchRecommendations: { request in
            requests += 1
            return RecommendationBatch(videos: [self.video(requests)], nextRequest: request.next(appCursor: request.pageIndex + 1))
        })
        await model.loadInitial()
        await model.refresh()
        XCTAssertEqual(model.videos.map(\.aid), [2])
        XCTAssertNil(model.lastRefreshAt)
    }
}
