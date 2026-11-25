import NeoBiliDomain
import Foundation

/// 列表页的过滤结果缓存。body 会在刷新淡入、选择模式等无关状态变化时反复求值，
/// 列表内容、过滤开关、最低时长和元数据版本不变时直接复用上次的结果。
@MainActor
final class FilteredVideosMemo<Element: VideoDimensionProviding> {
    private struct Key: Equatable {
        let revision: Int
        let hidesPortraitVideos: Bool
        let minimumSeconds: Int
        let metadataRevision: Int
    }

    private var cache: (key: Key, videos: [Element])?
#if NEOBILI_REGRESSION
    private(set) var recomputationCount = 0
#endif

    /// 读取过滤设置和元数据版本会登记观察；调用方每次内容变化时递增 `revision`。
    func videos(_ videos: [Element], revision: Int, hidesPortraitVideos: Bool,
                filtering: VideoFilterDependencies) -> [Element] {
        let key = Key(revision: revision,
                      hidesPortraitVideos: hidesPortraitVideos,
                      minimumSeconds: filtering.duration.minimumSeconds,
                      metadataRevision: filtering.metadata.metadataRevision)
        if let cache, cache.key == key { return cache.videos }
        let filtered = videos.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: filtering)
#if NEOBILI_REGRESSION
        recomputationCount += 1
#endif
        cache = (key, filtered)
        return filtered
    }
}
