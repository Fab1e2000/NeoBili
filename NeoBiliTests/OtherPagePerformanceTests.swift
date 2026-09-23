import XCTest
import Observation
import UIKit
import Synchronization
@testable import NeoBili

@MainActor
final class OtherPagePerformanceTests: XCTestCase {
    func testShortLivedCardNeverStartsPlaybackPreparation() async throws {
        let calls = PreparationCalls()
        let cache = VideoPreparationCache(detailLoader: { _ in
            await calls.record()
            throw URLError(.cancelled)
        })
        let transient = Task { await cache.prefetchWhenSettled(bvid: "transient") }
        try await Task.sleep(for: .milliseconds(30))
        let beforeDwell = await calls.count
        XCTAssertEqual(beforeDwell, 0)
        transient.cancel()
        await transient.value
        let afterCancel = await calls.count
        XCTAssertEqual(afterCancel, 0)
        await cache.prefetchWhenSettled(bvid: "settled")
        let afterDwell = await calls.count
        XCTAssertEqual(afterDwell, 1)
    }

    func testUnrelatedEmoteDoesNotInvalidateWaitingComment() async {
        let store = CommentEmoteStore()
        let needed = URL(string: "https://example.invalid/needed.png")!
        let unrelated = URL(string: "https://example.invalid/unrelated.png")!
        let changes = ObservationChanges()
        withObservationTracking {
            XCTAssertNil(store.image(for: needed, height: 16))
        } onChange: { changes.increment() }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
            UIColor.red.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
        }
        store.insertOriginalForTesting(image, for: unrelated)
        XCTAssertEqual(changes.count, 0)
        store.insertOriginalForTesting(image, for: needed)
        XCTAssertEqual(changes.count, 1)
        XCTAssertNotNil(store.image(for: needed, height: 16))
    }

    func testCommentTimeCachePreservesLinksAndValueIsolation() {
        let text = "👨‍👩‍👧‍👦精彩片段 02:35 https://example.com/12:34"
        let first = CommentTimeLinks.attributed(text)
        XCTAssertEqual(first, CommentTimeLinks.attributed(text))
        var edited = first
        edited.append(AttributedString("changed"))
        XCTAssertEqual(String(CommentTimeLinks.attributed(text).characters), text)
        XCTAssertEqual(CommentTimeLinks.attributed(text).runs.compactMap(\.link).count, 1)
        XCTAssertEqual(CommentTimeLinks.attributed("纯文本🙂").runs.compactMap(\.link).count, 0)
    }

    func testLiveBurstPublishesOnceInArrivalOrderAndStaysBounded() {
        let model = LiveDanmakuModel()
        defer { model.stop() }
        for index in 0..<20 { model.append(message: message(index)) }
        XCTAssertTrue(model.messages.isEmpty)
        model.flushMessages()
        XCTAssertEqual(model.messages.map(\.id), (0..<20).map(String.init))
        for index in 20..<1_020 { model.append(message: message(index)) }
        model.flushMessages()
        XCTAssertLessThanOrEqual(model.messages.count, LiveDanmakuModel.messageLimit)
        XCTAssertEqual(model.messages.last?.id, "1019")
        let ids = model.messages.compactMap { Int($0.id) }
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLiveStopCancelsPendingMessagesAndRoomSwitchStartsClean() async throws {
        let model = LiveDanmakuModel()
        defer { model.stop() }
        model.append(message: message(1))
        model.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(model.messages.isEmpty)
        model.append(message: message(2))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.messages.map(\.id), ["2"])
    }

    private func message(_ id: Int) -> LiveDanmakuModel.Message {
        .init(id: String(id), name: "测试", text: "弹幕 \(id)", color: nil,
              emoteURL: nil, emoteSize: nil, medal: nil)
    }
}

private actor PreparationCalls {
    private(set) var count = 0
    func record() { count += 1 }
}

private final class ObservationChanges: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func increment() { value.withLock { $0 += 1 } }
}
