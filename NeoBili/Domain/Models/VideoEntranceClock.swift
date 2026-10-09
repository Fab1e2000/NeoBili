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

/// 单张卡片的起点。卡片只观察自己这一格，翻页往时钟里加新卡时，
/// 已经在屏幕上的卡片不会被连带重算。
@MainActor @Observable
private final class VideoEntranceSlot {
    var start: TimeInterval?
}

/// 每个列表独立保存已通过判断的卡片起点，不依赖卡片视图是否存在。
@MainActor @Observable
final class VideoEntranceClock {
    /// 整批快照。读它会观察整批起点，只给测试和刷新分隔条这类需要整批结果的地方用；
    /// 卡片自己用 `start(for:)`。
    private(set) var starts: [String: TimeInterval] = [:]
    /// 加载占位只关心有没有起点，不跟着每次入列重算。
    private(set) var hasStarts = false
    /// 整批判断是否仍在进行，由列表外层的占位单独观察。
    var isPreparing = false
    private(set) var generation = 0
    @ObservationIgnored private var slots: [String: VideoEntranceSlot] = [:]
    func start(for id: String) -> TimeInterval? {
        if let slot = slots[id] { return slot.start }
        // 卡片可能比起点先出现：先建好空格子让它观察，入列时只通知它自己。
        let slot = VideoEntranceSlot()
        slots[id] = slot
        return slot.start
    }

    func prepare(ids: Set<String>, generation: Int, reset: Bool) {
        if self.generation != generation { self.generation = generation }
        publish(reset ? [:] : starts.filter { ids.contains($0.key) })
        slots = slots.filter { ids.contains($0.key) }
    }

    func admit(_ ids: [String], animated: Bool = true) {
        let active = Set(ids)
        // A completed monotonic origin keeps skipped entries settled even if
        // their lazy views are recycled and animations are enabled afterward.
        let now = animated ? ProcessInfo.processInfo.systemUptime : 0
        var updated = starts.filter { active.contains($0.key) }
        for id in ids where updated[id] == nil { updated[id] = now }
        publish(updated)
    }

    func finishAnimations() {
        guard starts.values.contains(where: { $0 != 0 }) else { return }
        publish(starts.mapValues { _ in 0 })
    }

    /// 只写真正变化的格子；@Observable 不比较新旧值，写入相同的值也会通知观察者。
    private func publish(_ updated: [String: TimeInterval]) {
        for (id, slot) in slots where updated[id] == nil && slot.start != nil {
            slot.start = nil
        }
        for (id, start) in updated {
            let slot = slots[id] ?? VideoEntranceSlot()
            slots[id] = slot
            if slot.start != start { slot.start = start }
        }
        if updated != starts { starts = updated }
        if hasStarts == updated.isEmpty { hasStarts = !updated.isEmpty }
    }
}
