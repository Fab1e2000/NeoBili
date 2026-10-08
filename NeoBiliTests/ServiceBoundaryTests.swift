import XCTest
@testable import NeoBili

@MainActor
final class ServiceBoundaryTests: XCTestCase {
    func testInjectedCommentServiceOwnsReadsAndWrites() async throws {
        let requests = Requests()
        let comment = try JSONDecoder().decode(Comment.self, from: Data(#"{"rpid":7,"ctime":1,"like":0,"rcount":0,"action":0,"member":{"uname":"test","avatar":""},"content":{"message":"test"}}"#.utf8))
        var services = ApplicationServices(session: .init(currentID: { UUID() }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        services.comment.commentsOperation = { oid, type, page in
            await requests.append("read:\(oid):\(type):\(page)")
            return CommentPage(page: .init(num: 1, size: 20, count: 1), replies: [comment])
        }
        services.comment.likeCommentOperation = { oid, type, id, like in
            await requests.append("like:\(oid):\(type):\(id):\(like)")
        }
        let model = CommentsViewModel(oid: 42, type: 1, services: services)
        await model.loadInitial()
        await model.toggleLike(comment, isLoggedIn: true)
        let received = await requests.values
        XCTAssertEqual(received, ["read:42:1:1", "like:42:1:7:true"])
        XCTAssertTrue(model.isLiked(comment))
    }

    func testUnconfiguredOperationFailsInsteadOfUsingLiveNetwork() async {
        do {
            _ = try await SearchService().searchSuggestions(term: "offline")
            XCTFail("An unconfigured dependency must fail explicitly")
        } catch {
            guard case ServiceError.unconfigured = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testLiveModelUsesInjectedStreamAndStopsIt() {
        let stream = Stream()
        let model = LiveDanmakuModel(stream: stream, superChatLoader: { _ in [] })
        model.start(roomID: 123)
        XCTAssertEqual(stream.room, 123)
        stream.emit?(.connection(.connected))
        stream.emit?(.popularity(99))
        XCTAssertEqual(model.connection, .connected)
        XCTAssertEqual(model.popularity, 99)
        model.stop()
        XCTAssertNil(stream.emit)
        XCTAssertEqual(model.connection, .idle)
        XCTAssertNil(model.popularity)
    }
}

private actor Requests {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

@MainActor
private final class Stream: LiveDanmakuStreaming {
    var room: Int?
    var emit: (@MainActor (LiveDanmakuEvent) -> Void)?
    func start(roomID: Int, onEvent: @escaping @MainActor (LiveDanmakuEvent) -> Void) {
        room = roomID
        emit = onEvent
    }
    func stop() { emit = nil }
}
