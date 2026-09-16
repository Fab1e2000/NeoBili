import XCTest
@testable import NeoBili

@MainActor
final class InteractionFeedbackTests: XCTestCase {
    func testUndoPreventsCommitAndRestoresTheOriginalPosition() async throws {
        struct Item: Identifiable { let id: Int }
        let feedback = ActionFeedback()
        let removals = ListRemovalState<Int>()
        var items = [Item(id: 1), Item(id: 2), Item(id: 3)]
        XCTAssertTrue(removals.begin(2))
        let index = try XCTUnwrap(removals.remove(2, from: &items))
        let decision = Task { await feedback.confirmRemoval("已移除", duration: .seconds(30)) }
        try await waitUntil { feedback.canUndo }
        XCTAssertTrue(removals.hasPending, "撤销期间不允许刷新覆盖列表")
        feedback.undo()
        let shouldCommit = await decision.value
        XCTAssertFalse(shouldCommit)
        if !shouldCommit { removals.restore(Item(id: 2), at: index, in: &items) }
        removals.finish(2)
        XCTAssertEqual(items.map(\.id), [1, 2, 3])
        XCTAssertFalse(removals.hasPending)
        XCTAssertNil(feedback.message)
    }

    func testExpiryCommitsAndNewFeedbackSurvivesOldExpiry() async throws {
        let feedback = ActionFeedback()
        let decision = Task { await feedback.confirmRemoval("已移除", duration: .milliseconds(15)) }
        let shouldCommit = await decision.value
        XCTAssertTrue(shouldCommit)
        feedback.show("新提示")
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(feedback.message, "新提示")
    }

    func testCancelledRemovalNeverCommits() async throws {
        let feedback = ActionFeedback()
        let decision = Task { await feedback.confirmRemoval("已移除", duration: .seconds(30)) }
        try await waitUntil { feedback.canUndo }
        decision.cancel()
        let shouldCommit = await decision.value
        XCTAssertFalse(shouldCommit)
        XCTAssertNil(feedback.message)
    }

    func testSecondRemovalSettlesFirstWithoutOldTimerClearingItsUndo() async throws {
        let feedback = ActionFeedback()
        let first = Task { await feedback.confirmRemoval("第一张", duration: .milliseconds(50)) }
        try await waitUntil { feedback.message == "第一张" }
        let second = Task { await feedback.confirmRemoval("第二张", duration: .seconds(30)) }
        try await waitUntil { feedback.message == "第二张" }
        let firstCommits = await first.value
        XCTAssertTrue(firstCommits)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertTrue(feedback.canUndo)
        XCTAssertEqual(feedback.message, "第二张")
        feedback.undo()
        let secondCommits = await second.value
        XCTAssertFalse(secondCommits)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("等待反馈超时")
    }
}
