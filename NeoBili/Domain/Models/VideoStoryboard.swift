import Foundation
import CoreGraphics

public struct VideoPreviewID: Hashable, Sendable {
    public let bvid: String
    public let cid: Int

    public init(
        bvid: String,
        cid: Int
    ) {
        self.bvid = bvid
        self.cid = cid
    }
}

/// Bilibili's storyboard tiles; the first two index entries precede tile zero.
/// Matches PiliPlus updatePreviewIndex, including the leading sentinel.
public struct VideoStoryboard: Decodable, Sendable {
    public let imgXLen: Int
    public let imgYLen: Int
    public let imgXSize: Double
    public let imgYSize: Double
    public let image: [String]
    public let index: [Double]

    enum CodingKeys: String, CodingKey {
        case imgXLen = "img_x_len", imgYLen = "img_y_len"
        case imgXSize = "img_x_size", imgYSize = "img_y_size"
        case image, index
    }

    public struct Tile: Equatable {
        public let url: URL
        public let rect: CGRect
    }

    public func tile(at seconds: Double) -> Tile? {
        guard seconds.isFinite, !index.isEmpty, imgXLen > 0, imgYLen > 0,
              imgXLen <= 100, imgYLen <= 100,
              imgXSize.isFinite, imgYSize.isFinite, imgXSize > 0, imgYSize > 0, !image.isEmpty else { return nil }
        let perImage = imgXLen * imgYLen
        let offset = min(max(0, index.reduce(0) { $0 + ($1 <= seconds ? 1 : 0) } - 2), image.count * perImage - 1)
        let raw = image[offset / perImage]
        guard let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw.replacingOccurrences(of: "http://", with: "https://")),
              url.scheme == "https" else { return nil }
        let local = offset % perImage
        return Tile(url: url, rect: CGRect(x: Double(local % imgXLen) * imgXSize,
                                          y: Double(local / imgXLen) * imgYSize,
                                          width: imgXSize, height: imgYSize))
    }
}
