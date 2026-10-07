import XCTest
@testable import NeoBili

@MainActor
final class LibraryBatchRemovalTests: XCTestCase {
    func testUndoDoesNotSendAnyDeletes() async {
        let result = await LibraryBatchRemoval.perform(ids: [1, 2], isCurrent: { true },
            confirm: { false }, remove: { _ in XCTFail("Undo must prevent writes") })
        XCTAssertTrue(result.succeeded.isEmpty)
        XCTAssertNil(result.error)
    }

    func testPartialFailureKeepsSuccessfulDeletesAndContinuesRemainingItems() async {
        var sent: [Int] = []
        var confirmations = 0
        let result = await LibraryBatchRemoval.perform(ids: [1, 2, 3], isCurrent: { true },
            confirm: { confirmations += 1; return true }, remove: { id in
                sent.append(id)
                if id == 2 { throw URLError(.notConnectedToInternet) }
            })
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(sent, [1, 2, 3])
        XCTAssertEqual(result.succeeded, [1, 3])
        XCTAssertNotNil(result.error)
    }

    func testAccountChangeStopsBatchAfterUndoOrInFlightWrite() async {
        var current = true
        let cancelled = await LibraryBatchRemoval.perform(ids: [1, 2], isCurrent: { current },
            confirm: { current = false; return true }, remove: { _ in XCTFail("Old account cannot write") })
        XCTAssertTrue(cancelled.succeeded.isEmpty)
        current = true
        var sent: [Int] = []
        let result = await LibraryBatchRemoval.perform(ids: [1, 2], isCurrent: { current },
            confirm: { true }, remove: { id in sent.append(id); current = false })
        XCTAssertEqual(sent, [1])
        XCTAssertEqual(result.succeeded, [1])
    }
}
