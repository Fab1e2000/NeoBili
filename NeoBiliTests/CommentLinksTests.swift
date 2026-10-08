import SwiftUI
import XCTest
@testable import NeoBili

final class CommentLinksTests: XCTestCase {
    func testMetadataReplacesAllOccurrencesWithoutLinkingTitleTimestamps() throws {
        let metadata = try JSONDecoder().decode([String: CommentJumpLink].self, from: Data(#"{"https://b23.tv/demo":{"title":"视频 02:35 &amp; 更多","appUrlSchema":"bilibili://video/170001"}}"#.utf8))
        let text = "👨‍👩‍👧‍👦 https://b23.tv/demo 和 https://b23.tv/demo 03:10"
        let rich = CommentLinks.attributed(text, metadata: metadata, includesTimes: true)
        XCTAssertEqual(String(rich.characters), "👨‍👩‍👧‍👦 视频 02:35 & 更多 和 视频 02:35 & 更多 03:10")
        let urls = rich.runs.compactMap(\.link)
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(urls.compactMap(CommentTimeLinks.seconds), [190])
        XCTAssertEqual(CommentLinks.videoRoute(urls[0])?.bvid, "BV17x411w7KC")
    }

    func testPlainURLsAndVideoIDsDoNotOverlapTimestamps() {
        let text = "https://example.com/12:34 BV17x411w7KC av170001 02：35"
        let links = CommentLinks.links(in: text, metadata: [:], includesTimes: true)
        XCTAssertEqual(links.count, 4)
        XCTAssertEqual(links.compactMap { CommentTimeLinks.seconds(from: $0.url) }, [155])
        XCTAssertEqual(links.compactMap { CommentLinks.videoRoute($0.url)?.bvid }, ["BV17x411w7KC", "BV17x411w7KC"])
        XCTAssertEqual(CommentLinks.links(in: text, metadata: [:], includesTimes: false).count, 3)
    }

    func testUnsafeSchemesAndLookalikeHostsDoNotRouteInternally() throws {
        for value in ["javascript:alert(1)", "file:///tmp/test", "https://user:password@example.com"] {
            XCTAssertNil(CommentLinks.webURL(value))
        }
        for value in ["https://www.bilibili.com.evil.example/video/BV17x411w7KC", "https://example.com/video/BV17x411w7KC", "https://www.bilibili.com/video/BV17x411w7KC?p=2"] {
            XCTAssertNil(CommentLinks.videoRoute(try XCTUnwrap(URL(string: value))))
        }
        XCTAssertNotNil(CommentLinks.videoRoute(URL(string: "https://m.bilibili.com/video/av170001")!))
    }

    func testOptionalMetadataIsLenientAndLocationIsServerText() throws {
        let comment = try decode(#"""
        {"rpid":1,"ctime":1,"like":0,"rcount":0,"member":{"uname":"甲","avatar":""},
         "content":{"message":"链接 &amp; 时间 01:23","jump_url":{"bad":false,"good":{"title":"标题"}}},
         "reply_control":{"location":"  IP属地：上海  "}}
        """#)
        XCTAssertEqual(comment.location, "IP属地：上海")
        XCTAssertEqual(comment.content.jumpURLs.count, 1)
        XCTAssertEqual(comment.message, "链接 & 时间 01:23")
        let malformed = try decode(#"{"rpid":1,"ctime":1,"like":0,"rcount":0,"member":{"uname":"甲","avatar":""},"content":{"message":"正文","jump_url":[]},"reply_control":false}"#)
        XCTAssertNil(malformed.location)
        XCTAssertTrue(malformed.content.jumpURLs.isEmpty)
    }

    private func decode(_ json: String) throws -> Comment {
        try JSONDecoder().decode(Comment.self, from: Data(json.utf8))
    }
}

@MainActor
final class CommentLinksLayoutTests: XCTestCase {
    func testForegroundCommentLinksAndLocationAtDifferentSizes() async throws {
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
        let comment = try JSONDecoder().decode(Comment.self, from: Data(#"""
        {"rpid":1,"ctime":1,"like":12,"rcount":2,"member":{"uname":"评论用户","avatar":""},
        "content":{"message":"精彩片段 02:35，完整视频 https://b23.tv/demo 👨‍👩‍👧‍👦","jump_url":{"https://b23.tv/demo":{"title":"查看完整视频","appUrlSchema":"bilibili://video/170001"}}},
        "reply_control":{"location":"IP属地：上海"},"replies":[
        {"rpid":2,"ctime":1,"like":0,"rcount":0,"member":{"uname":"回复用户","avatar":""},
        "content":{"message":"从 01:20 开始看，参考 https://example.com"},"reply_control":{"location":"IP属地：中国香港"}}]}
        """#.utf8))
        let action = EnvironmentAction<Double> { _ in }
        for width in [CGFloat(390), 700] {
            for scheme in [ColorScheme.light, .dark] {
                for size in [DynamicTypeSize.large, .accessibility3] {
                    let content = CommentRow(comment: comment, viewModel: CommentsViewModel(aid: 1))
                        .padding(16).frame(width: width)
                        .environment(AccountStore())
                        .environment(\.commentTimeJump, action)
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, size)
                    host.rootView = AnyView(content)
                    let measured = host.sizeThatFits(in: CGSize(width: width, height: 2000))
                    XCTAssertEqual(measured.width, width, accuracy: 1)
                    XCTAssertGreaterThan(measured.height, 100)
                    host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                    host.rootView = AnyView(content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(scheme == .dark ? Color.black : Color.white))
                    host.view.frame = CGRect(x: 0, y: 0, width: width, height: max(400, measured.height))
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(80))
                    let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "comment-links-\(Int(width))-\(scheme)-\(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
