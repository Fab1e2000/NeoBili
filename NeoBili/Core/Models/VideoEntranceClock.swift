import Foundation
import Observation

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

/// 每个列表独立保存已通过判断的卡片起点，不依赖卡片视图是否存在。
@MainActor @Observable
final class VideoEntranceClock {
    private(set) var starts: [String: TimeInterval] = [:]
    private(set) var generation = 0

    func prepare(ids: Set<String>, generation: Int, reset: Bool) {
        self.generation = generation
        starts = reset ? [:] : starts.filter { ids.contains($0.key) }
    }

    func admit(_ ids: [String]) {
        let active = Set(ids)
        let now = ProcessInfo.processInfo.systemUptime
        var updated = starts.filter { active.contains($0.key) }
        for id in ids where updated[id] == nil { updated[id] = now }
        if updated != starts { starts = updated }
    }
}
