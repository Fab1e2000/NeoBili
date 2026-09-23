import SwiftUI
import XCTest
@testable import NeoBili

/// 评论行的竖向间距实测。
///
/// 渲染真实 CommentRow，用测试专属的锚点标记测量容器下边缘与分隔线，
/// 不再依赖某种背景颜色，也不会把液态玻璃阴影误认作布局边界。
#if DEBUG
@MainActor
final class CommentSpacingTests: XCTestCase {
    private static let width: CGFloat = 390

    func testReplyBlockToDividerGapIsIdenticalAcrossComments() throws {
        // 两条结构不同的评论：回复条数、行数、是否有「查看全部」按钮都不一样。
        // 灰块本身高度当然不同，但它到下面那条分隔线的距离必须一样。
        let short = try makeComment(
            rpid: 1,
            message: "烧卖不就是面皮里面包米饭吗，只是米饭调味了",
            rcount: 27,
            replies: ["你求我求你啊：但那是糯米，不是大米", "连西盛：南方烧麦"]
        )
        let tall = try makeComment(
            rpid: 2,
            message: "这不是我们江苏的烧麦吗",
            rcount: 8,
            replies: [
                "数值怪卡卡罗：这是馒头包大米饭，烧麦好吃多了",
                "Xattacker：比燒賣不如多了 沒味道可言，再补一行让它换行",
                "无败林冲：烧麦里包的是糯米饭吧，糯米饭本身就很鲜香，这个直接包白米饭"
            ]
        )

        let gaps = try [short, tall].map { try measureGapBelowReplyBlock(for: $0) }
        XCTAssertEqual(
            gaps[0],
            gaps[1],
            accuracy: 1,
            "灰块到分隔线的距离在两条评论上不一致：\(gaps[0]) vs \(gaps[1])"
        )
    }

    /// 布局边界固定为 12pt，不再根据文字墨迹或辅助功能字号补偿。
    func testReplyBlockBottomPaddingIsFixedAcrossTextSizes() throws {
        let comment = try makeComment(rpid: 1, message: "主评论", rcount: 3, replies: ["楼中楼内容"])
        for size in [DynamicTypeSize.small, .large, .xxxLarge, .accessibility3] {
            let gap = try measureGapBelowReplyBlock(for: comment, dynamicTypeSize: size)
            XCTAssertEqual(gap, CommentLayout.rowVerticalPadding + 1, accuracy: 1,
                           "字号 \(size) 下灰块与分隔线的固定间距不正确")
        }
    }

    func testSingleLongReplyIsFullyVisibleWithoutExtraBottomSpacing() throws {
        let short = try makeComment(rpid: 10, message: "正文", rcount: 1, replies: ["简短回复"])
        let long = try makeComment(rpid: 11, message: "正文", rcount: 1,
                                   replies: [String(repeating: "这是一条需要完整显示的很长的楼中楼回复。", count: 30)])
        let model = CommentsViewModel(aid: 1)
        XCTAssertFalse(model.shouldShowAllReplies(short))
        XCTAssertFalse(model.shouldShowAllReplies(long), "已拿到唯一回复时不显示查看全部")
        let heightDifference = try render(long).height - render(short).height
        XCTAssertGreaterThan(heightDifference, 200, "长回复不能仍被截成三行")
        let gap = try measureGapBelowReplyBlock(for: long)
        XCTAssertEqual(gap, CommentLayout.rowVerticalPadding + 1, accuracy: 1)
        XCTAssertEqual(gap, try measureGapBelowReplyBlock(for: short), accuracy: 1)
    }

    func testAllRepliesControlOnlyAppearsForMissingReplies() async throws {
        let comment = try makeComment(rpid: 12, message: "正文", rcount: 2, replies: ["预览回复"])
        let model = CommentsViewModel(aid: 1)
        XCTAssertTrue(model.shouldShowAllReplies(comment))
    }

    // MARK: - 渲染与取样

    /// 按 `CommentsView` 里那一段的结构渲染：评论行 + 上下留白 + 分隔线。
    private func render(_ comment: Comment, viewModel: CommentsViewModel? = nil, dynamicTypeSize: DynamicTypeSize = .large) throws -> CGImage {
        let viewModel = viewModel ?? CommentsViewModel(aid: 1)
        let content = VStack(alignment: .leading, spacing: 0) {
            CommentRow(comment: comment, viewModel: viewModel)
                .padding(.horizontal, CommentLayout.pageHorizontalInset)
                .padding(.vertical, CommentLayout.rowVerticalPadding)

            Divider()
                .padding(.leading, CommentLayout.pageHorizontalInset)
                .anchorPreference(key: CommentReplyLayoutBoundsKey.self, value: .bounds) { [.divider: $0] }

            // 分隔线后面留一段白，方便扫描时确认线的位置。
            Color.white.frame(height: 40)
        }
        .frame(width: Self.width)
        .background(Color.white)
        .environment(AccountStore())
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .commentReplyLayoutMarkers()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage, "渲染失败")
    }

    /// 容器最后一个布局像素到分隔线的距离，沿用原来 +1 像素的约定。
    private func measureGapBelowReplyBlock(
        for comment: Comment,
        viewModel: CommentsViewModel? = nil,
        dynamicTypeSize: DynamicTypeSize = .large
    ) throws -> CGFloat {
        try CommentReplyLayoutSnapshot(image: render(comment, viewModel: viewModel, dynamicTypeSize: dynamicTypeSize)).blockGap
    }

    private func makeComment(
        rpid: Int,
        message: String,
        rcount: Int,
        replies: [String]
    ) throws -> Comment {
        let replyJSON = replies.enumerated().map { index, text in
            """
            {"rpid":\(rpid * 1000 + index),"ctime":1700000000,"like":0,"rcount":0,
            "member":{"uname":"回复者","avatar":""},"content":{"message":"\(text)"}}
            """
        }.joined(separator: ",")

        let json = """
        {"rpid":\(rpid),"ctime":1700000000,"like":108,"rcount":\(rcount),
        "member":{"uname":"某位用户","avatar":""},"content":{"message":"\(message)"},
        "replies":[\(replyJSON)]}
        """
        return try JSONDecoder().decode(Comment.self, from: Data(json.utf8))
    }
}
#endif
