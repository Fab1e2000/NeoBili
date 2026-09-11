import SwiftUI
import XCTest
@testable import NeoBili

#if DEBUG
extension View {
    /// Draw only in the test snapshot: magenta marks the block's last layout
    /// pixel, cyan the divider, green surrounds (never covers) the text area.
    func commentReplyLayoutMarkers() -> some View {
        overlayPreferenceValue(CommentReplyLayoutBoundsKey.self) { anchors in
            GeometryReader { geometry in
                let block = anchors[.block].map { geometry[$0] }
                let content = anchors[.content].map { geometry[$0] }
                let divider = anchors[.divider].map { geometry[$0] }
                Canvas { context, _ in
                    if let block {
                        context.fill(Path(CGRect(x: 2, y: floor(block.maxY) - 1, width: 6, height: 1)), with: .color(.init(red: 1, green: 0, blue: 1)))
                    }
                    if let divider {
                        context.fill(Path(CGRect(x: 2, y: floor(divider.minY), width: 6, height: 1)), with: .color(.init(red: 0, green: 1, blue: 1)))
                    }
                    if let content {
                        let left = floor(content.minX) - 1
                        let right = ceil(content.maxX)
                        let top = floor(content.minY) - 1
                        let bottom = ceil(content.maxY)
                        let paint = GraphicsContext.Shading.color(Color(red: 0, green: 1, blue: 0))
                        for line in [CGRect(x: left, y: top, width: right - left + 1, height: 1),
                                     CGRect(x: left, y: bottom, width: right - left + 1, height: 1),
                                     CGRect(x: left, y: top, width: 1, height: bottom - top + 1),
                                     CGRect(x: right, y: top, width: 1, height: bottom - top + 1)] {
                            context.fill(Path(line), with: paint)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct CommentReplyLayoutSnapshot {
    let blockBottom: Int
    let dividerTop: Int
    let lastContentInk: Int?

    var blockGap: CGFloat { CGFloat(dividerTop - blockBottom) }

    init(image: CGImage) throws {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var blockY: Int?, dividerY: Int?
        var left = width, right = -1, top = height, bottom = -1
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let r = buffer[index], g = buffer[index + 1], b = buffer[index + 2]
                if x >= 2 && x < 8 {
                    if r > 245 && g < 10 && b > 245 { blockY = y }
                    if r < 10 && g > 245 && b > 245 { dividerY = y }
                }
                if r < 10 && g > 245 && b < 10 {
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
        }
        let measuredBlockBottom = try XCTUnwrap(blockY, "Missing reply-block layout marker")
        let measuredDividerTop = try XCTUnwrap(dividerY, "Missing divider layout marker")
        XCTAssertGreaterThan(measuredDividerTop, measuredBlockBottom)
        blockBottom = measuredBlockBottom
        dividerTop = measuredDividerTop
        guard right > left + 1, bottom > top + 1 else {
            throw SnapshotError.missingContentBounds
        }
        var lastInk: Int?
        // Only inspect inside the anchored content area. Glass rims/shadows and
        // the diagnostic markers live outside it and cannot become text ink.
        for y in (top + 1)..<bottom {
            for x in (left + 1)..<right {
                let index = (y * width + x) * 4
                if buffer[index] < 235 || buffer[index + 1] < 235 || buffer[index + 2] < 235 {
                    lastInk = y
                    break
                }
            }
        }
        lastContentInk = lastInk
    }

    private enum SnapshotError: Error { case missingContentBounds }
}
#endif
