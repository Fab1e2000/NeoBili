import CoreGraphics
import Foundation
import ImageIO

@main
struct ImagePerformanceRegression {
    static func main() throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 4_000, height: 3_000,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for row in 0..<30 {
            context.setFillColor(CGColor(red: CGFloat(row) / 30, green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: row * 100, width: 4_000, height: 100))
        }
        let original = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, original, nil)
        precondition(CGImageDestinationFinalize(destination))
        let encoded = data as Data
        let target = ImagePixelSize(points: CGSize(width: 160, height: 90), scale: 3)!
        let full = ImageDownsampling.decode(encoded, fitting: nil)!
        let thumbnail = ImageDownsampling.decode(encoded, fitting: target)!
        precondition(full.width == 4_000 && full.height == 3_000)
        precondition(thumbnail.width >= target.width && thumbnail.height >= target.height,
                     "The crop must retain enough physical pixels on both axes")
        precondition(thumbnail.width <= 512 && thumbnail.height <= 384)
        precondition(ImageDownsampling.decode(Data([1, 2, 3]), fitting: target) == nil)
        precondition(ImagePixelSize(points: .zero, scale: 3) == nil)
        precondition(ImagePixelSize(points: CGSize(width: 160.1, height: 90.1), scale: 3) == target,
                     "Subpoint relayout must not start another image request")

        let rotatedData = NSMutableData()
        let rotatedDestination = CGImageDestinationCreateWithData(rotatedData, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(rotatedDestination, original, [kCGImagePropertyOrientation: 6] as CFDictionary)
        precondition(CGImageDestinationFinalize(rotatedDestination))
        let portraitTarget = ImagePixelSize(points: CGSize(width: 100, height: 200), scale: 1)!
        let rotated = ImageDownsampling.decode(rotatedData as Data, fitting: portraitTarget)!
        precondition(rotated.width < rotated.height && rotated.width >= portraitTarget.width
                     && rotated.height >= portraitTarget.height, "Honor EXIF rotation before crop sizing")

        func medianDecodeMilliseconds(target: ImagePixelSize?) -> Double {
            var times: [Double] = []
            for _ in 0..<9 {
                autoreleasepool {
                    let start = ProcessInfo.processInfo.systemUptime
                    let image = ImageDownsampling.decode(encoded, fitting: target)!
                    precondition(image.bytesPerRow > 0)
                    times.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                }
            }
            return times.sorted()[times.count / 2]
        }
        let fullCost = full.bytesPerRow * full.height
        let thumbnailCost = thumbnail.bytesPerRow * thumbnail.height
        print("PASS  Downsampling retains physical pixels for crop, handles rotation and rejects invalid input")
        print("BITMAP_BYTES original=\(fullCost) thumbnail=\(thumbnailCost)")
        print(String(format: "HOST_MEDIAN_DECODE_MS original=%.3f thumbnail=%.3f (9 runs, 4000x3000 JPEG, 160x90 pt @3x)",
                     medianDecodeMilliseconds(target: nil), medianDecodeMilliseconds(target: target)))
        print("ALL IMAGE PERFORMANCE CHECKS PASS")
    }
}
