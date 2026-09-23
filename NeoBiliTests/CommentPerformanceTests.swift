import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class CommentPerformanceTests: XCTestCase {
    func testEmoteCacheTracksMetadataAndPreservesUnknownText() {
        let small = CommentEmote(url: "https://example.invalid/a.png", meta: .init(size: 1))
        let large = CommentEmote(url: "https://example.invalid/b.png", meta: .init(size: 2))
        let message = "👨‍👩‍👧‍👦 [unknown] [[doge] 02:35 ["
        let first: [CommentEmoteSegments.Segment] = [.text("👨‍👩‍👧‍👦 [unknown] ["), .emote("[doge]", small), .text(" 02:35 [")]
        XCTAssertEqual(CommentEmoteSegments.prepared(message: message, emotes: ["[doge]": small]), first)
        XCTAssertEqual(CommentEmoteSegments.prepared(message: message, emotes: ["[doge]": small]), first)
        XCTAssertEqual(CommentEmoteSegments.prepared(message: message, emotes: ["[doge]": large]),
                       [.text("👨‍👩‍👧‍👦 [unknown] ["), .emote("[doge]", large), .text(" 02:35 [")])
        XCTAssertEqual(CommentEmoteSegments.prepared(message: message, emotes: [:]), [.text(message)])
        let unmatched = String(repeating: "[", count: 10_000)
        XCTAssertEqual(CommentEmoteSegments.prepared(message: unmatched, emotes: ["[doge]": small]), [.text(unmatched)])
    }

    func testBoundedTextProbeMatchesFullMeasurement() throws {
        let url = URL(string: "https://example.invalid/comment-measure.png")!
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        CommentEmoteStore.shared.insertOriginalForTesting(image, for: url)
        let emotes = ["[表情]": CommentEmote(url: url.absoluteString, meta: .init(size: 2))]
        let samples = [
            "简短评论 👨‍💻", String(repeating: "中文 English emoji😂 混合文字。", count: 50),
            (1...6).map { "第\($0)行" }.joined(separator: "\n"),
            (1...7).map { "第\($0)行" }.joined(separator: "\n"),
            String(repeating: "正文[表情]\n", count: 12)
        ]
        for width in [CGFloat(190), 316] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for message in samples {
                    func height(_ limit: Int?) throws -> Int {
                        let view = CommentEmoteText(message: message, emotes: emotes, font: .subheadline,
                                                    textStyle: .subheadline, loadsEmotes: false)
                            .lineLimit(limit).fixedSize(horizontal: false, vertical: true)
                            .frame(width: width).environment(\.dynamicTypeSize, size)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        return try XCTUnwrap(renderer.cgImage).height
                    }
                    let collapsed = try height(6)
                    let bounded = try height(7)
                    let full = try height(nil)
                    XCTAssertEqual(bounded > collapsed + 1, full > collapsed + 1,
                                   "宽度 \(width)、字号 \(size)：\(message.prefix(30))")
                }
            }
        }
    }

    func testRootPaginationDeduplicatesSubmissionsAndIncomingPages() async throws {
        let a = try comment(1), b = try comment(2), c = try comment(3)
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            CommentPage(page: .init(num: page, size: 2, count: 3), replies: page == 1 ? [a, a, b] : [b, c, c])
        })
        model.acceptSubmission(a, root: nil)
        await model.retry()
        XCTAssertEqual(model.comments.map(\.id), [1, 2])
        await model.loadMoreIfNeeded(current: b)
        XCTAssertEqual(model.comments.map(\.id), [1, 2, 3])
        XCTAssertFalse(model.hasMore)
    }

    func testRepliesDeduplicateWithinAndAcrossPagesAndStopAtEnd() async throws {
        let root = try comment(10), a = try comment(1), b = try comment(2), c = try comment(3)
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            return CommentReplyPage(page: .init(num: page, size: 2, count: 3), replies: page == 1 ? [a, a, b] : [b, c, c])
        })
        await model.loadRepliesIfNeeded(for: root)
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [1, 2])
        await model.loadMoreRepliesIfNeeded(current: b, root: root)
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [1, 2, 3])
        XCTAssertEqual(pages, [1, 2])
        XCTAssertFalse(model.hasMoreReplies(root))
    }

    func testReplyFailureRetriesSamePageAndCancellationIsNotAnError() async throws {
        let root = try comment(10), a = try comment(1), b = try comment(2)
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            if pages.count == 1 { throw CancellationError() }
            if pages.count == 3 { throw URLError(.timedOut) }
            return CommentReplyPage(page: .init(num: page, size: 1, count: 2), replies: page == 1 ? [a] : [b])
        })
        await model.loadRepliesIfNeeded(for: root)
        XCTAssertNil(model.replyErrors[root.id])
        await model.loadRepliesIfNeeded(for: root)
        await model.loadMoreRepliesIfNeeded(current: a, root: root)
        XCTAssertNotNil(model.replyErrors[root.id])
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(pages, [1, 1, 2, 2])
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [1, 2])
    }

    func testRootPageSurvivesTriggeringRowLeavingViewport() async throws {
        let a = try comment(1), b = try comment(2)
        var pending: CheckedContinuation<CommentPage, Never>?
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            if page == 1 { return CommentPage(page: .init(num: 1, size: 1, count: 2), replies: [a]) }
            return await withCheckedContinuation { pending = $0 }
        })
        await model.loadInitial()
        let row = Task { await model.loadMoreIfNeeded(current: a) }
        for _ in 0..<10_000 {
            if pending != nil { break }
            await Task.yield()
        }
        let continuation = try XCTUnwrap(pending)
        row.cancel()
        continuation.resume(returning: CommentPage(page: .init(num: 2, size: 1, count: 2), replies: [b]))
        await row.value
        XCTAssertEqual(model.comments.map(\.id), [1, 2])
        XCTAssertFalse(model.isLoadingMore)
    }

    func testReplyPageSurvivesTriggeringRowLeavingViewport() async throws {
        let root = try comment(10), a = try comment(1), b = try comment(2)
        var pending: CheckedContinuation<CommentReplyPage, Never>?
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            if page == 1 { return CommentReplyPage(page: .init(num: 1, size: 1, count: 2), replies: [a]) }
            return await withCheckedContinuation { pending = $0 }
        })
        await model.loadRepliesIfNeeded(for: root)
        let row = Task { await model.loadMoreRepliesIfNeeded(current: a, root: root) }
        for _ in 0..<10_000 {
            if pending != nil { break }
            await Task.yield()
        }
        let continuation = try XCTUnwrap(pending)
        row.cancel()
        continuation.resume(returning: CommentReplyPage(page: .init(num: 2, size: 1, count: 2), replies: [b]))
        await row.value
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [1, 2])
        XCTAssertFalse(model.isLoadingReplies(root))
    }

    private func comment(_ id: Int) throws -> Comment {
        let data = Data("""
        {"rpid":\(id),"ctime":1,"like":0,"rcount":2,"member":{"uname":"测试","avatar":""},"content":{"message":"正文"}}
        """.utf8)
        return try JSONDecoder().decode(Comment.self, from: data)
    }
}
