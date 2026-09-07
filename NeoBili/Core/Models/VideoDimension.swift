import Foundation

/// 服务端明确给出的视频画面尺寸。`rotate` 是编码画面的旋转元数据；90/270 度时
/// 要交换宽高后再判断用户最终看到的画幅。
struct VideoDimension: Decodable, Hashable, Sendable {
    let width: Int
    let height: Int
    let rotate: Int

    private enum CodingKeys: String, CodingKey {
        case width, height, rotate
    }

    init(width: Int, height: Int, rotate: Int = 0) {
        self.width = width
        self.height = height
        self.rotate = rotate
    }

    init(from decoder: Decoder) throws {
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

    var isValid: Bool { width > 0 && height > 0 }

    /// 只有宽高都有效且最终呈现高度严格大于宽度时才算竖屏。
    var isPortrait: Bool {
        guard width > 0, height > 0 else { return false }
        let normalizedRotation = ((rotate % 360) + 360) % 360
        let swapsAxes = normalizedRotation == 90 || normalizedRotation == 270
        let displayWidth = swapsAxes ? height : width
        let displayHeight = swapsAxes ? width : height
        return displayHeight > displayWidth
    }
}

protocol VideoDimensionProviding {
    var dimension: VideoDimension? { get }
    var dimensionLookupBVID: String? { get }
    var videoDurationSeconds: Int? { get }
}

extension Sequence where Element: VideoDimensionProviding {
    @MainActor
    func hasPendingVideoDimensions(_ enabled: Bool) -> Bool {
        let minimum = VideoDurationFilterSettings.shared.minimumSeconds
        return contains { $0.metadataRequest(hidingPortrait: enabled, minimumSeconds: minimum) != nil }
    }

    /// 使用列表尺寸或详情缓存；开启过滤时，仅放行已确认非竖屏的视频。
    @MainActor
    func hidingKnownPortraitVideos(_ enabled: Bool) -> [Element] {
        return filter { $0.canDisplayVideo(hidingPortrait: enabled) }
    }
}

enum PortraitVideoFilterSettings {
    static let storageKey = "neobili.hidesPortraitVideos"
    static let defaultValue = false
}

extension VideoDimensionProviding {
    var videoDurationSeconds: Int? { nil }

    /// 列表值优先，缓存补齐；任何一个已知过滤条件成立，就不再查询其它字段。
    @MainActor
    func metadataRequest(hidingPortrait enabled: Bool, minimumSeconds: Int) -> PortraitVideoStore.Request? {
        guard enabled || minimumSeconds > 0,
              let bvid = dimensionLookupBVID, !bvid.isEmpty else { return nil }
        let store = PortraitVideoStore.shared
        let portrait = dimension.flatMap { $0.isValid ? $0.isPortrait : nil }
            ?? store.isPortrait(bvid: bvid)
        let duration = videoDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
            ?? store.durationSeconds(bvid: bvid)
        if enabled, portrait == true { return nil }
        if minimumSeconds > 0, let duration, duration < minimumSeconds { return nil }

        let needsDimension = enabled && portrait == nil
        let needsDuration = minimumSeconds > 0 && duration == nil
        guard needsDimension || needsDuration,
              !store.hasFreshAttempt(bvid: bvid, requiringDuration: needsDuration) else { return nil }
        return PortraitVideoStore.Request(bvid: bvid, requiringDuration: needsDuration)
    }

    @MainActor
    func canDisplayVideo(hidingPortrait enabled: Bool) -> Bool {
        let minimum = VideoDurationFilterSettings.shared.minimumSeconds
        if minimum > 0 {
            let duration = videoDurationSeconds.flatMap { $0 > 0 ? $0 : nil }
                ?? dimensionLookupBVID.flatMap { PortraitVideoStore.shared.durationSeconds(bvid: $0) }
            guard let duration, duration >= minimum else { return false }
        }
        guard enabled else { return true }
        if let dimension, dimension.isValid { return !dimension.isPortrait }
        guard let bvid = dimensionLookupBVID, !bvid.isEmpty else { return false }
        return PortraitVideoStore.shared.isPortrait(bvid: bvid) == false
    }

    @MainActor
    var isKnownPortraitVideo: Bool {
        if let dimension, dimension.isValid { return dimension.isPortrait }
        guard let bvid = dimensionLookupBVID else { return false }
        return PortraitVideoStore.shared.isPortrait(bvid: bvid) == true
    }
}

