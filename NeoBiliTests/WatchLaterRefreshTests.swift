#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class WatchLaterRefreshTests: XCTestCase {
    private func item(_ id: Int) throws -> WatchLaterItem {
        try JSONDecoder().decode(WatchLaterItem.self, from: Data("""
        {"aid":\(id),"bvid":"BVfixture\(id)","cid":\(id),"title":"稍后再看测试视频 \(id)","duration":120,"owner":{"mid":1,"name":"测试作者"}}
        """.utf8))
    }

    func testStagedRefreshKeepsOldListUntilCommitThenShowsNewVideoFirst() async throws {
        let session = UUID(); let old = try [item(1), item(2)], added = try [item(3), item(1), item(2)]
        var serverItems = old
        let model = WatchLaterModel(client: .init(load: { _, _, _ in .init(items: serverItems) },
                                                  remove: { _, _ in }, session: { session }))
        await model.load()
        XCTAssertEqual(model.items.map(\.id), [1, 2])
        let generation = model.entranceGeneration

        serverItems = added
        let staged = await model.stageRefresh()
        XCTAssertTrue(staged)
        XCTAssertEqual(model.items.map(\.id), [1, 2], "the old list stays until the fade-out ends")
        model.commitStagedRefresh()
        XCTAssertEqual(model.items.map(\.id), [3, 1, 2])
        XCTAssertGreaterThan(model.entranceGeneration, generation, "cards re-time their entrance after a refresh")
    }

    func testFailedStagedRefreshKeepsListAndReportsError() async throws {
        let session = UUID(); let old = try [item(1), item(2)]
        var fail = false
        let model = WatchLaterModel(client: .init(load: { _, _, _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return .init(items: old)
        }, remove: { _, _ in }, session: { session }))
        await model.load()
        fail = true
        let staged = await model.stageRefresh()
        XCTAssertFalse(staged)
        model.commitStagedRefresh()
        XCTAssertEqual(model.items.map(\.id), [1, 2])
        XCTAssertNotNil(model.errorMessage)
    }

    func testRemovalInvalidatesTheStagedRefresh() async throws {
        let session = UUID(); let items = try [item(1), item(2), item(3)]
        let model = WatchLaterModel(client: .init(load: { _, _, _ in .init(items: items) },
                                                  remove: { _, _ in }, session: { session }))
        await model.load()
        let staged = await model.stageRefresh()
        XCTAssertTrue(staged)
        let failure = await model.remove(ids: [1], confirm: { true })
        XCTAssertNil(failure)
        XCTAssertEqual(model.items.map(\.id), [2, 3])
        model.commitStagedRefresh()
        XCTAssertEqual(model.items.map(\.id), [2, 3], "a snapshot taken before the removal must not bring the item back")
    }

    func testControllerCommitsOnlyAfterSuccessfulFetchAndAlwaysRestoresOpacity() async throws {
        let controller = ListRefreshController()
        var events: [String] = []
        controller.start(hasContent: true, animatesExit: false, source: .watchLater,
                         fetch: { events.append("fetch"); return true },
                         commit: { events.append("commit") }, discard: { events.append("discard") })
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(events, ["fetch", "commit", "discard"])
        XCTAssertFalse(controller.isRefreshing)
        XCTAssertEqual(controller.contentOpacity, 1)

        events = []
        controller.start(hasContent: true, animatesExit: false, source: .watchLater,
                         fetch: { events.append("fetch"); return false },
                         commit: { events.append("commit") }, discard: { events.append("discard") })
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(events, ["fetch", "discard"], "a failed request restores the old content without committing")
        XCTAssertFalse(controller.isRefreshing)
    }

    func testControllerResetCancelsInFlightRefresh() async throws {
        let controller = ListRefreshController()
        var committed = false
        controller.start(hasContent: true, animatesExit: false, source: .watchLater,
                         fetch: { try? await Task.sleep(for: .milliseconds(300)); return true },
                         commit: { committed = true }, discard: {})
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.isRefreshing)
        controller.reset()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertFalse(committed)
        XCTAssertFalse(controller.isRefreshing)
    }
}
