import SwiftUI
import XCTest
@testable import NeoBili

/// 评论行的竖向间距实测。
///
/// 「楼中楼灰块到分隔线的距离不一致」这个问题靠读代码判断已经错过两次，
/// 所以这里把真实的 `CommentRow` 渲染成位图，直接数像素：找到灰块的下边缘，
/// 再找到下面那条分隔线，量出两者之间的空白，然后比较不同评论之间是否一致。
@MainActor
final class CommentSpacingTests: XCTestCase {
    private static let width: CGFloat = 390

    /// 灰块（secondarySystemBackground，浅色下约 242/242/247）。
    private func isReplyBlock(_ pixel: (r: Int, g: Int, b: Int)) -> Bool {
        abs(pixel.r - 242) <= 3 && abs(pixel.g - 242) <= 3 && abs(pixel.b - 247) <= 3
    }

    /// 分隔线：明显比白底暗，又不是灰块那个色。
    private func isDivider(_ pixel: (r: Int, g: Int, b: Int)) -> Bool {
        pixel.r < 235 && !isReplyBlock(pixel)
    }

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

    /// 有楼中楼的评论 vs 没有楼中楼的评论：两者「最后一点内容 → 分隔线」的
    /// 空白必须看起来一样。灰块是硬边缘，文字下面还带着行高留白，所以哪怕
    /// padding 数值相同，肉眼看到的空白也会差一截——这正是「间距不一致」。
    func testInkToDividerGapMatchesBetweenRepliedAndPlainComments() throws {
        let replied = try makeComment(
            rpid: 1,
            message: "烧卖不就是面皮里面包米饭吗",
            rcount: 27,
            replies: ["你求我求你啊：但那是糯米，不是大米"]
        )
        let plain = try makeComment(rpid: 2, message: "大饼卷馒头揪着米饭吃", rcount: 0, replies: [])

        let withBlock = try measureInkToDivider(replied)
        let withoutBlock = try measureInkToDivider(plain)

        XCTAssertEqual(
            withBlock,
            withoutBlock,
            accuracy: 3,
            "有楼中楼时空白 \(withBlock)，没有时 \(withoutBlock)——两种评论之间看起来不一样宽"
        )
    }

    /// 同一条评论「展开」和「收起」两种状态下，灰块底部到分隔线的距离必须一样。
    /// 以前只测过收起状态，展开后最后一行从按钮换成了别的内容时会露出不一致。
    func testReplyBlockToDividerGapMatchesBetweenExpandedAndCollapsed() throws {
        let replies = [
            "用户甲：第一层",
            "用户乙：第二层",
            "用户丙：第三层",
            "用户丁：第四层",
            "用户戊：第五层",
            "用户己：第六层"
        ]
        let collapsed = try makeComment(rpid: 1, message: "主评论内容", rcount: 6, replies: replies)

        let expandedVM = CommentsViewModel(aid: 1)
        expandedVM.setExpandedForTesting(
            rootId: collapsed.id,
            replies: try makeComment(rpid: 1, message: "主评论内容", rcount: 6, replies: replies).replies ?? []
        )
        let collapsedVM = CommentsViewModel(aid: 1)

        let collapsedGap = try measureGapBelowReplyBlock(for: collapsed, viewModel: collapsedVM)
        let expandedGap = try measureGapBelowReplyBlock(for: collapsed, viewModel: expandedVM)
        XCTAssertEqual(
            collapsedGap,
            expandedGap,
            accuracy: 1,
            "收起时灰块到分隔线 \(collapsedGap)，展开时 \(expandedGap)——两种状态不一致"
        )
    }

    // MARK: - 渲染与取样

    /// 按 `CommentsView` 里那一段的结构渲染：评论行 + 上下留白 + 分隔线。
    private func render(_ comment: Comment, viewModel: CommentsViewModel? = nil) throws -> CGImage {
        let viewModel = viewModel ?? CommentsViewModel(aid: 1)
        let content = VStack(alignment: .leading, spacing: 0) {
            CommentRow(comment: comment, viewModel: viewModel)
                .padding(.horizontal, CommentLayout.pageHorizontalInset)
                .padding(.vertical, CommentLayout.rowVerticalPadding)

            Divider()
                .padding(.leading, CommentLayout.pageHorizontalInset)

            // 分隔线后面留一段白，方便扫描时确认线的位置。
            Color.white.frame(height: 40)
        }
        .frame(width: Self.width)
        .background(Color.white)
        .environment(AccountStore())
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage, "渲染失败")
    }

    /// 把整张图取成灰度行摘要：每一行记下「这一行有没有墨迹」和「是不是灰块」。
    ///
    /// 只取一列会踩空——点赞行的文字很短，在靠右的列上根本没有像素，
    /// 量出来的就不是它到灰块的距离了。
    private func rowSummaries(of image: CGImage) throws -> [(hasInk: Bool, isBlock: Bool)] {
        let width = image.width
        let height = image.height

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (0..<height).map { y in
            var hasInk = false
            var isBlock = false
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let pixel = (r: Int(buffer[offset]), g: Int(buffer[offset + 1]), b: Int(buffer[offset + 2]))
                if isReplyBlock(pixel) { isBlock = true }
                // 250 这个门限把抗锯齿的浅灰边也算成墨迹，量的才是肉眼看到的边界。
                if pixel.r < 250 || pixel.g < 250 || pixel.b < 250 { hasInk = true }
            }
            return (hasInk, isBlock)
        }
    }

    /// 灰块下边缘到分隔线的距离。
    private func measureGapBelowReplyBlock(
        for comment: Comment,
        viewModel: CommentsViewModel? = nil
    ) throws -> CGFloat {
        let rows = try rowSummaries(of: render(comment, viewModel: viewModel))
        let blockBottom = try XCTUnwrap(rows.indices.last { rows[$0].isBlock }, "没找到灰块")
        let dividerRow = try XCTUnwrap(
            rows.indices.first { $0 > blockBottom && rows[$0].hasInk },
            "灰块下面没找到分隔线"
        )
        return CGFloat(dividerRow - blockBottom)
    }

    /// 这条评论「最后一点内容」到分隔线之间的空白。
    ///
    /// 分隔线是整张图里最靠下的那段墨迹（后面只剩纯白），倒着找它最省事。
    private func measureInkToDivider(_ comment: Comment) throws -> CGFloat {
        let rows = try rowSummaries(of: render(comment))
        let lastInk = try XCTUnwrap(rows.indices.last { rows[$0].hasInk }, "整张图是空的")
        // 分隔线本身是连续几行墨迹，先退到它的上边缘。
        var dividerTop = lastInk
        while dividerTop > 0, rows[dividerTop - 1].hasInk { dividerTop -= 1 }
        let contentBottom = try XCTUnwrap(
            rows.indices.last { $0 < dividerTop && rows[$0].hasInk },
            "分隔线上面没有内容"
        )
        return CGFloat(dividerTop - contentBottom - 1)
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
