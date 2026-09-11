import Foundation

@main struct InlineVideoLayoutRegression {
    static func main() {
        let portrait = CGSize(width: 393, height: 852)
        let landscape = CGSize(width: 852, height: 393)
        let examples: [(Double, CGFloat)] = [
            (16.0 / 9.0, 221), (4.0 / 3.0, 295), (2.35, 167),
            (1, 393), (0.8, 491), (9.0 / 16.0, 554), (0.1, 554)
        ]
        for (ratio, expectedHeight) in examples {
            precondition(InlineVideoLayout.height(for: portrait, aspectRatio: ratio) == expectedHeight)
            precondition(InlineVideoLayout.height(for: landscape, aspectRatio: ratio) == expectedHeight)
            precondition(InlineVideoLayout.height(for: portrait, aspectRatio: ratio, hidesPortraitVideos: true) == 221)
        }
        print("PASS  横屏、超宽、正方形及竖屏画幅动态调整，竖屏上限保留详情，旋转与隐藏设置回归通过")

        for ratio: Double? in [nil, 0, -1, .nan, .infinity] {
            precondition(InlineVideoLayout.height(for: portrait, aspectRatio: ratio) == 221)
        }
        precondition(InlineVideoLayout.height(for: CGSize(width: 0, height: 0)) == 0)
        precondition(InlineVideoLayout.aspectRatio(width: 0, height: 1920) == nil)
        for rotation in [90, 270, -90, 450] {
            precondition(InlineVideoLayout.aspectRatio(width: 1920, height: 1080, rotation: rotation) == 9.0 / 16.0)
        }
        precondition(InlineVideoLayout.aspectRatio(width: 1920, height: 1080, rotation: 180) == 16.0 / 9.0)
        print("PASS  尺寸缺失/无效的 16:9 回退及编码旋转元数据回归通过")
    }
}
