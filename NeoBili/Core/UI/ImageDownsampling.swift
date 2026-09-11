import CoreGraphics
import Foundation
import ImageIO

/// Physical pixels, rounded up so small layout changes reuse the same bitmap.
struct ImagePixelSize: Hashable, Sendable {
    let width: Int
    let height: Int

    init?(points: CGSize, scale: CGFloat) {
        guard points.width.isFinite, points.height.isFinite, scale.isFinite,
              points.width > 0, points.height > 0, scale > 0 else { return nil }
        width = Int(ceil(min(points.width * scale, 16_384) / 64)) * 64
        height = Int(ceil(min(points.height * scale, 16_384) / 64)) * 64
    }
}

/// ImageIO decodes only the pixels needed by a card, rather than first expanding
/// the full photograph. This Foundation/ImageIO helper also runs in host tests.
enum ImageDownsampling {
    static func decode(_ data: Data, fitting target: ImagePixelSize?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return nil }
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let displayWidth = rotated ? height : width
        let displayHeight = rotated ? width : height
        // Fill is the most demanding caller: preserve enough pixels even when
        // a tall image is cropped into a wide cover or a circular avatar.
        let ratio = target.map {
            min(1, max(Double($0.width) / displayWidth, Double($0.height) / displayHeight))
        } ?? 1
        let maximumPixelSize = max(1, Int(ceil(max(width, height) * ratio)))
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}
