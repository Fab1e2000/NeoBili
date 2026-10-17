import Foundation

/// 服务端明确给出的视频画面尺寸。`rotate` 是编码画面的旋转元数据；90/270 度时
/// 要交换宽高后再判断用户最终看到的画幅。
public struct VideoDimension: Decodable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let rotate: Int

    private enum CodingKeys: String, CodingKey {
        case width, height, rotate
    }

    public init(width: Int, height: Int, rotate: Int = 0) {
        self.width = width
        self.height = height
        self.rotate = rotate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func integer(for key: CodingKeys) -> Int? {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int(value) }
            return nil
        }

        width = integer(for: .width) ?? 0
        height = integer(for: .height) ?? 0
        rotate = integer(for: .rotate) ?? 0
    }

    public var isValid: Bool { width > 0 && height > 0 }

    /// 只有宽高都有效且最终呈现高度严格大于宽度时才算竖屏。
    public var isPortrait: Bool {
        guard width > 0, height > 0 else { return false }
        let normalizedRotation = ((rotate % 360) + 360) % 360
        let swapsAxes = normalizedRotation == 90 || normalizedRotation == 270
        let displayWidth = swapsAxes ? height : width
        let displayHeight = swapsAxes ? width : height
        return displayHeight > displayWidth
    }
}

public protocol VideoDimensionProviding {
    var dimension: VideoDimension? { get }
    var dimensionLookupBVID: String? { get }
    var videoDurationSeconds: Int? { get }
    /// 不是视频的条目（推荐里的直播、图文卡）：画幅和时长过滤直接放行。
    var skipsVideoFilters: Bool { get }
}

public enum PortraitVideoFilterSettings {
    public static let storageKey = "neobili.hidesPortraitVideos"
    public static let defaultValue = false
}

extension VideoDimensionProviding {
    public var videoDurationSeconds: Int? { nil }
    public var skipsVideoFilters: Bool { false }
}
