#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class CommentFeatureLayoutTests: XCTestCase {
    func testLightweightBadgePinAndInteractionsAtLargeTextSizes() async throws {
        let root = try comment(1, replies: true)
        let model = CommentsViewModel(oid: 1, type: 1, uploaderID: 42, fetchComments: { _, _, _, _ in
            .init(page: .init(num: 1, size: 20, count: 1), replies: [root], pinnedReplies: [root])
        })
        await model.loadInitial()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        defer { previous?.makeKey() }
        var heights: [CGFloat] = []
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let content = VStack(alignment: .leading, spacing: 0) {
                    CommentSortHeader(viewModel: model)
                    CommentRow(comment: root, viewModel: model)
                        .padding(16)
                    Divider()
                    CommentRow(comment: root.replies![0], viewModel: model, showsReplies: false, root: root)
                        .padding(16)
                }
                .frame(width: 390)
                .background(Color(uiColor: .systemBackground))
                .environment(AccountStore())
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, size)
                // Menu is UIKit-backed and cannot be captured by ImageRenderer.
                let window = UIWindow(windowScene: scene)
                let host = UIHostingController(rootView: content)
                host.safeAreaRegions = []
                let fitting = host.sizeThatFits(in: CGSize(width: 390, height: 5000))
                window.frame = CGRect(x: 0, y: 0, width: 390, height: fitting.height)
                window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                window.rootViewController = host
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(150))
                window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                window.isHidden = true
                window.rootViewController = nil
                XCTAssertEqual(image.size.width, 390, "Long names and badges must fit the viewport")
                XCTAssertGreaterThan(image.size.height, 350)
                heights.append(image.size.height)
                let attachment = XCTAttachment(image: image)
                attachment.name = "comment-A-\(scheme)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
                let badge = try XCTUnwrap(CommentUPBadge.inlineImage(size: size, scale: 2, color: .pink, scheme: scheme))
                let badgeRenderer = ImageRenderer(content: badge)
                XCTAssertNotNil(badgeRenderer.uiImage, "Inline preview must use the same rendered badge")
            }
        }
        XCTAssertGreaterThan(heights[1], heights[0])
        XCTAssertGreaterThan(heights[3], heights[2])
    }

    func testProfileNavigationReturnsToSameCommentsAndDraft() async throws {
        let rows = try (1...35).map { try comment($0) }
        let session = UUID()
        let services = ApplicationServices(session: .init(currentID: { session }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        let model = CommentsViewModel(oid: 1, type: 1, uploaderID: 42, services: services,
            fetchComments: { _, _, _, _ in .init(page: .init(num: 1, size: 35, count: 35), replies: rows) })
        await model.loadInitial()
        model.commentDraft(root: 0).text = "主页返回后继续写 [doge]"
        let probe = AuthorNavigationProbe()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AuthorNavigationFixture(model: model, probe: probe)
            .environment(AccountStore()).environment(ActionFeedback()).environment(NowPlayingStore())
            .environment(\.applicationServices, services))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300))
        let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > 1500 })
        XCTAssertNotNil(scroll.refreshControl, "The real comment list needs native pull to refresh")
        scroll.setContentOffset(CGPoint(x: 0, y: 350), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        let offset = scroll.contentOffset.y
        try XCTUnwrap(probe.open)(rows[0].member)
        try await Task.sleep(for: .milliseconds(450))
        let navigation = try XCTUnwrap(controllers(host).compactMap { $0 as? UINavigationController }.first)
        XCTAssertEqual(navigation.viewControllers.count, 2, "Author routing must push the existing SpaceView")
        XCTAssertTrue(navigation.topViewController?.navigationItem.title?.contains("很长") == true)
        navigation.popViewController(animated: false)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertEqual(model.commentDraft(root: 0).text, "主页返回后继续写 [doge]")
        XCTAssertEqual(model.comments.map(\.id), rows.map(\.id))
        XCTAssertEqual(scroll.contentOffset.y, offset, accuracy: 1)
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func controllers(_ controller: UIViewController) -> [UIViewController] {
        [controller] + controller.children.flatMap(controllers)
    }
    private func comment(_ id: Int, replies: Bool = false) throws -> Comment {
        let reply: [[String: Any]] = replies ? [["rpid": 100, "ctime": 1, "like": 0, "rcount": 0,
            "member": ["mid": "42", "uname": "一个很长很长的UP主昵称🌿", "avatar": ""],
            "content": ["message": "谢谢分享！这里是 UP 主的回复 [doge]。"]]] : []
        let data: [String: Any] = ["rpid": id, "ctime": 1, "like": 12, "rcount": reply.count,
            "member": ["mid": 42, "uname": "一个很长很长的UP主昵称🌿", "avatar": ""],
            "content": ["message": "这是一条评论，展示轻量 UP 标识、置顶和互动信息。\n原始链接 https://example.invalid/video [doge]"],
            "up_action": ["like": true, "reply": true], "replies": reply]
        return try JSONDecoder().decode(Comment.self, from: JSONSerialization.data(withJSONObject: data))
    }
}

@MainActor private final class AuthorNavigationProbe { var open: EnvironmentAction<CommentMember>? }
private struct AuthorNavigationFixture: View {
    let model: CommentsViewModel
    let probe: AuthorNavigationProbe
    @State private var position = ScrollPosition(edge: .top)
    var body: some View {
        NavigationStack {
            CommentsView(viewModel: model, scrollPosition: $position)
                .background(AuthorActionProbe(probe: probe))
                .commentAuthorHost()
                .navigationTitle("评论")
        }
    }
}
private struct AuthorActionProbe: View {
    let probe: AuthorNavigationProbe
    @Environment(\.openCommentAuthor) private var open
    var body: some View { Color.clear.onAppear { probe.open = open } }
}
