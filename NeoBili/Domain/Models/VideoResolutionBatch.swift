import Foundation

struct VideoResolutionBatch: Equatable {
    let ids: [String]
    let generation: Int
    let enabled: Bool
    let minimumSeconds: Int

    func resetsEntrance(comparedTo previous: Self?) -> Bool {
        guard let previous else { return true }
        // ID 增删仅影响对应卡片；只有主动刷新或过滤设置变化才重播整批。
        return generation != previous.generation
            || enabled != previous.enabled
            || minimumSeconds != previous.minimumSeconds
    }
}

