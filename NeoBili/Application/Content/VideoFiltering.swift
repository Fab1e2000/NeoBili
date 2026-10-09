import Foundation

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

extension VideoDimensionProviding {

    /// 列表值优先，缓存补齐；任何一个已知过滤条件成立，就不再查询其它字段。
    @MainActor
    func metadataRequest(hidingPortrait enabled: Bool, minimumSeconds: Int) -> PortraitVideoStore.Request? {
        guard !skipsVideoFilters, enabled || minimumSeconds > 0,
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
        if skipsVideoFilters { return true }
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

}

