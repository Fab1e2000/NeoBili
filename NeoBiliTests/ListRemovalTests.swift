@testable import NeoBiliData
@testable import NeoBiliDomain
import XCTest
@testable import NeoBili

@MainActor
final class ListRemovalTests: XCTestCase {
    private struct Row: Identifiable { let id: Int }

    func testConcurrentRemovalUsesIdentityAfterIndicesShift() {
        let state = ListRemovalState<Int>()
        var rows = [Row(id: 1), Row(id: 2)]
        XCTAssertTrue(state.begin(1))
        XCTAssertTrue(state.begin(2))
        XCTAssertFalse(state.begin(2), "重复点击不能发出第二次删除")
        state.hide(1)
        state.hide(2)
        state.remove(1, from: &rows)
        state.remove(2, from: &rows)
        XCTAssertTrue(rows.isEmpty, "第二次删除不能再用旧下标 1")
        state.finish(1)
        state.finish(2)
        XCTAssertTrue(state.hiddenIDs.isEmpty)
    }

    func testRemovalHandlesRefreshAndDeduplicatesRollback() {
        let state = ListRemovalState<Int>()
        var rows = [Row(id: 1), Row(id: 2)]
        let snapshot = state.revision
        XCTAssertTrue(state.begin(2))
        XCTAssertNotEqual(snapshot, state.revision)
        rows = [Row(id: 2), Row(id: 3)] // 动画期间刷新/排序
        let index = state.remove(2, from: &rows)
        XCTAssertEqual(rows.map(\.id), [3])
        rows.insert(Row(id: 2), at: 0) // 失败前刷新已经恢复了同 ID
        state.restore(Row(id: 2), at: index ?? 0, in: &rows)
        XCTAssertEqual(rows.map(\.id), [2, 3])
        rows = []
        XCTAssertNil(state.remove(2, from: &rows))
        state.restore(Row(id: 2), at: 99, in: &rows)
        XCTAssertEqual(rows.map(\.id), [2])
    }
}
