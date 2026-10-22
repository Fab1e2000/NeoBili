#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class CommentPerformanceTests: XCTestCase {
    private let emoteStore = CommentEmoteStore(loader: { _ in throw URLError(.notConnectedToInternet) })
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
        emoteStore.insertOriginalForTesting(image, for: url)
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
                            .frame(width: width).environment(\.dynamicTypeSize, size).environment(\.commentEmoteStore, emoteStore)
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

    func testEmptyInitialPageIsReusedWhenReturningToComments() async {
        var requests = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            requests += 1
            return CommentPage(page: .init(num: page, size: 20, count: 0), replies: [])
        })
        for _ in 0..<10 { await model.loadInitial() }
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoading)
    }

    func testSubmissionBeforeOpeningCommentsDoesNotHideServerComments() async throws {
        let submitted = try comment(1), existing = try comment(2)
        var requests = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            requests += 1
            return CommentPage(page: .init(num: page, size: 20, count: 2), replies: [submitted, existing])
        })
        model.acceptSubmission(submitted, root: nil)
        await model.loadInitial()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.comments.map(\.id), [1, 2])
    }

    func testCancelledInitialCommentsCanLoadOnNextAppearance() async {
        var requests = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            requests += 1
            if requests == 1 { throw CancellationError() }
            return CommentPage(page: .init(num: page, size: 20, count: 0), replies: [])
        })
        await model.loadInitial()
        await model.loadInitial()
        await model.loadInitial()
        XCTAssertEqual(requests, 2)
        XCTAssertNil(model.errorMessage)
    }

    func testCommentMessageLayoutCost() throws {
        let message = String(repeating: "中文 English 👨‍👩‍👧‍👦 混合正文 02:35 [表情] ", count: 40)
        let data = try JSONSerialization.data(withJSONObject: [
            "rpid": 88, "ctime": 1, "like": 0, "rcount": 0,
            "member": ["uname": "测试", "avatar": ""],
            "content": ["message": message, "emote": ["[表情]": ["url": "https://example.invalid/layout.png", "meta": ["size": 1]]]]
        ])
        let comment = try JSONDecoder().decode(Comment.self, from: data)
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        emoteStore.insertOriginalForTesting(bitmap, for: try XCTUnwrap(URL(string: "https://example.invalid/layout.png")))
        for size in [DynamicTypeSize.large, .accessibility3] {
            var durations: [Double] = []
            for iteration in 0..<45 {
                let start = CACurrentMediaTime()
                let renderer = ImageRenderer(content: ExpandableCommentMessage(comment: comment)
                    .frame(width: 316).environment(\.dynamicTypeSize, size).environment(\.commentEmoteStore, emoteStore))
                renderer.scale = 3
                XCTAssertGreaterThan(try XCTUnwrap(renderer.cgImage).height, 0)
                if iteration >= 5 { durations.append((CACurrentMediaTime() - start) * 1000) }
            }
            durations.sort()
            print("COMMENT_LAYOUT size=\(size) samples=\(durations.count) median_ms=\(durations[durations.count / 2]) p95_ms=\(durations[Int(Double(durations.count - 1) * 0.95)])")
        }
    }

    func testCommentOverflowForegroundLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.frame = scene.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for (name, message, width, size, style) in [
            ("short", "简短评论", CGFloat(316), DynamicTypeSize.large, UIUserInterfaceStyle.light),
            ("six-lines", (1...6).map { "第\($0)行" }.joined(separator: "\n"), 316, .large, .light),
            ("long", String(repeating: "中文 English 👨‍👩‍👧‍👦 02:35，完整评论内容。", count: 20), 316, .large, .light),
            ("large-dark", String(repeating: "中文 English 👨‍👩‍👧‍👦 02:35，完整评论内容。", count: 20), 260, .accessibility3, .dark)
        ] {
            let data = try JSONSerialization.data(withJSONObject: [
                "rpid": 99, "ctime": 1, "like": 0, "rcount": 0,
                "member": ["uname": "测试", "avatar": ""], "content": ["message": message]
            ])
            let comment = try JSONDecoder().decode(Comment.self, from: data)
            window.overrideUserInterfaceStyle = style
            host.rootView = AnyView(ExpandableCommentMessage(comment: comment).id(name)
                .environment(\.dynamicTypeSize, size).environment(\.commentEmoteStore, emoteStore)
                .environment(\.commentTimeJump, EnvironmentAction { _ in })
                .frame(width: width, alignment: .leading).padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(uiColor: .systemBackground)))
            try await Task.sleep(for: .milliseconds(250))
            window.layoutIfNeeded()
            XCTAssertTrue(host.view.window === window)
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            })
            attachment.name = "comment-overflow-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func comment(_ id: Int) throws -> Comment {
        let data = Data("""
        {"rpid":\(id),"ctime":1,"like":0,"rcount":2,"member":{"uname":"测试","avatar":""},"content":{"message":"正文"}}
        """.utf8)
        return try JSONDecoder().decode(Comment.self, from: data)
    }
}
