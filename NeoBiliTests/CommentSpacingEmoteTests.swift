import SwiftUI
import XCTest
@testable import NeoBili

/// 带表情的评论行竖向间距实测。
///
/// 纯文字场景由 `CommentSpacingTests` 覆盖；这里的场景是**末行带行内表情**：
/// 表情图探到基线以下多深，决定了含表情的行是否比纯文字行更高——一旦更高，
/// 楼中楼展开/收起时末行内容在「表情行」和「按钮行」之间切换，灰块底部到
/// 分隔线的视觉间距就会漂移。这里直接注入表情缓存，以布局标记定位边界，
/// 仅在正文锚点内部测墨迹，排除玻璃轮廓和阴影。
#if DEBUG
@MainActor
final class CommentSpacingEmoteTests: XCTestCase {
    private static let width: CGFloat = 390
    /// 与注入的表情图同一个 URL。
    private static let emoteURLString = "https://i0.hdslb.com/bfs/emote/test-emote.png"

    override func setUp() {
        super.setUp()
        // 一张不透明的红色方块当表情。红色保证既不是灰块底色也不算纯白，
        // 像素扫描时能当成「墨迹」找到。
        let size = CGSize(width: 48, height: 48)
        let renderer = UIGraphicsImageRenderer(size: size)
        let square = renderer.image { context in
            UIColor(red: 1, green: 0.2, blue: 0.15, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let url = try! XCTUnwrap(URL(string: Self.emoteURLString))
        CommentEmoteStore.shared.insertOriginalForTesting(square, for: url)
    }

    private func render(_ comment: Comment, viewModel: CommentsViewModel) throws -> CGImage {
        let content = VStack(alignment: .leading, spacing: 0) {
            CommentRow(comment: comment, viewModel: viewModel)
                .padding(.horizontal, CommentLayout.pageHorizontalInset)
                .padding(.vertical, CommentLayout.rowVerticalPadding)

            Divider()
                .padding(.leading, CommentLayout.pageHorizontalInset)
                .anchorPreference(key: CommentReplyLayoutBoundsKey.self, value: .bounds) { [.divider: $0] }

            Color.white.frame(height: 40)
        }
        .frame(width: Self.width)
        .background(Color.white)
        .environment(AccountStore())
        .environment(\.colorScheme, .light)
        .commentReplyLayoutMarkers()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage, "渲染失败")
    }

    /// 返回（容器底 → 分隔线，末行正文墨迹 → 分隔线）。
    private func measure(comment: Comment, viewModel: CommentsViewModel) throws -> (blockGap: CGFloat, inkGap: CGFloat) {
        let snapshot = try CommentReplyLayoutSnapshot(image: render(comment, viewModel: viewModel))
        let lastInk = try XCTUnwrap(snapshot.lastContentInk, "回复正文内没有墨迹")
        return (snapshot.blockGap, CGFloat(snapshot.dividerTop - lastInk - 1))
    }

    /// rcount 与预览条数相等的小楼中楼：收起时没有「查看全部」按钮，
    /// 灰块以**表情行**收尾；展开后以「收起回复」**按钮**收尾。
    /// 两种状态的底部间距必须一致。
    func testBottomGapMatchesBetweenEmoteEndingAndButtonEnding() throws {
        let emoteJSON = """
        {"[doge]":{"url":"\(Self.emoteURLString)","meta":{"size":1}}}
        """
        let json = """
        {"rpid":1,"ctime":1700000000,"like":108,"rcount":2,
        "member":{"uname":"某位用户","avatar":""},"content":{"message":"主评论内容"},
        "replies":[
        {"rpid":1001,"ctime":1700000000,"like":0,"rcount":0,"member":{"uname":"甲","avatar":""},"content":{"message":"甲：第一层"}},
        {"rpid":1002,"ctime":1700000000,"like":0,"rcount":0,"member":{"uname":"乙","avatar":""},"content":{"message":"乙：看这个[doge]","emote":\(emoteJSON)}}
        ]}
        """
        let comment = try JSONDecoder().decode(Comment.self, from: Data(json.utf8))

        let collapsed = try measure(comment: comment, viewModel: CommentsViewModel(aid: 1))
        let expandedVM = CommentsViewModel(aid: 1)
        expandedVM.setExpandedForTesting(rootId: comment.id, replies: comment.replies ?? [])
        let expanded = try measure(comment: comment, viewModel: expandedVM)

        XCTAssertEqual(
            collapsed.blockGap,
            expanded.blockGap,
            accuracy: 1,
            "收起（表情行收尾）灰块底到分隔线 \(collapsed.blockGap)，展开（按钮收尾）\(expanded.blockGap)"
        )
        // 表情底边贴基线，与中文字墨迹底边平齐：墨迹差应接近 0。
        // 超过 1pt 说明表情又偏离了基线（或含表情的行被撑高了）。
        XCTAssertEqual(
            collapsed.inkGap,
            expanded.inkGap,
            accuracy: 1,
            "收起（表情行收尾）末行墨迹到分隔线 \(collapsed.inkGap)，展开（按钮收尾）\(expanded.inkGap)"
        )
    }

    /// 末行带表情的楼中楼 vs 末行纯文字的楼中楼：墨迹到分隔线的空白也必须一致，
    /// 否则不同评论之间会一松一紧。
    func testInkGapMatchesBetweenEmoteAndPlainTextEndings() throws {
        let emoteJSON = """
        {"[doge]":{"url":"\(Self.emoteURLString)","meta":{"size":1}}}
        """
        func makeComment(rpid: Int, lastMessage: String, emote: Bool) throws -> Comment {
            let json = """
            {"rpid":\(rpid),"ctime":1700000000,"like":108,"rcount":2,
            "member":{"uname":"某位用户","avatar":""},"content":{"message":"主评论内容"},
            "replies":[
            {"rpid":\(rpid * 1000 + 1),"ctime":1700000000,"like":0,"rcount":0,"member":{"uname":"甲","avatar":""},"content":{"message":"甲：第一层"}},
            {"rpid":\(rpid * 1000 + 2),"ctime":1700000000,"like":0,"rcount":0,"member":{"uname":"乙","avatar":""},"content":{"message":"\(lastMessage)"\(emote ? ",\"emote\":\(emoteJSON)" : "")}}
            ]}
            """
            return try JSONDecoder().decode(Comment.self, from: Data(json.utf8))
        }

        let withEmote = try makeComment(rpid: 1, lastMessage: "乙：看这个[doge]", emote: true)
        let plain = try makeComment(rpid: 2, lastMessage: "乙：就是普通的一句话", emote: false)

        let a = try measure(comment: withEmote, viewModel: CommentsViewModel(aid: 1))
        let b = try measure(comment: plain, viewModel: CommentsViewModel(aid: 1))

        // 同上：表情底边与文字墨迹平齐，差值应接近 0。
        XCTAssertEqual(
            a.inkGap,
            b.inkGap,
            accuracy: 1,
            "末行带表情时空白 \(a.inkGap)，纯文字 \(b.inkGap)——含表情的行被撑高了"
        )
    }
}
#endif
