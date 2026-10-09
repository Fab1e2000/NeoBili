import Foundation

/// 本机续播记录不依赖登录或历史记录接口；分 P 用 cid 分开保存。
@MainActor
final class PlaybackProgressStore {
    static let shared = PlaybackProgressStore()
    private static let legacyStorageKey = "neobili.playbackProgress.v1"
    private static let indexKey = "neobili.playbackProgress.v2.keys"
    private static let entryPrefix = "neobili.playbackProgress.v2.entry."

    private struct Entry: Codable {
        let position: TimeInterval
        let duration: TimeInterval?
        let updatedAt: Date
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let maximumEntries: Int
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard, maximumEntries: Int = 2_000,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.maximumEntries = max(maximumEntries, 1)
        self.now = now
        let decoder = JSONDecoder()
        if let keys = defaults.stringArray(forKey: Self.indexKey) {
            entries = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                guard let data = defaults.data(forKey: Self.entryPrefix + key),
                      let entry = try? decoder.decode(Entry.self, from: data) else { return nil }
                return (key, entry)
            })
        } else {
            entries = defaults.data(forKey: Self.legacyStorageKey)
                .flatMap { try? decoder.decode([String: Entry].self, from: $0) } ?? [:]
            // Commit the index after every old record has been copied. A process
            // interruption before this point safely retries the v1 migration.
            for key in entries.keys { persistEntry(for: key) }
            persistIndex()
            defaults.removeObject(forKey: Self.legacyStorageKey)
        }
    }

    func resumePosition(bvid: String, cid: Int, duration: TimeInterval? = nil) -> TimeInterval {
        let key = key(bvid: bvid, cid: cid)
        guard let entry = entries[key] else { return 0 }
        let effectiveDuration = validDuration(duration) ?? entry.duration
        guard entry.position.isFinite, entry.position > 0,
              !Self.isNearEnd(position: entry.position, duration: effectiveDuration) else {
            remove(bvid: bvid, cid: cid)
            return 0
        }
        return entry.position
    }

    func save(bvid: String, cid: Int, position: TimeInterval, duration: TimeInterval) {
        guard !bvid.isEmpty, cid > 0, position.isFinite, position >= 0 else { return }
        let duration = validDuration(duration)
        // 拖回开头和已接近片尾都从头重播。短视频仅舍弃最后 2%，最多 5 秒。
        guard position > 0, !Self.isNearEnd(position: position, duration: duration) else {
            remove(bvid: bvid, cid: cid)
            return
        }
        let key = key(bvid: bvid, cid: cid)
        let previous = entries[key]
        guard previous?.position != position || previous?.duration != duration else { return }
        let isNewEntry = previous == nil
        entries[key] = Entry(position: position, duration: duration, updatedAt: now())
        persistEntry(for: key)
        let needsTrimming = entries.count > maximumEntries
        if needsTrimming {
            let expiredKeys = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }
                .dropFirst(maximumEntries).map(\.key)
            for expiredKey in expiredKeys {
                entries[expiredKey] = nil
                defaults.removeObject(forKey: Self.entryPrefix + expiredKey)
            }
        }
        if isNewEntry || needsTrimming { persistIndex() }
    }

    func remove(bvid: String, cid: Int) {
        let key = key(bvid: bvid, cid: cid)
        guard entries.removeValue(forKey: key) != nil else { return }
        persistIndex()
        defaults.removeObject(forKey: Self.entryPrefix + key)
    }

    private func key(bvid: String, cid: Int) -> String { "\(bvid):\(cid)" }

    private func validDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    private static func isNearEnd(position: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration, duration.isFinite, duration > 0 else { return false }
        return position >= duration - min(5, duration * 0.02)
    }

    /// Playback checkpoints touch only one small record. Re-encoding every
    /// saved video on the main actor every five seconds scales with history.
    private func persistEntry(for key: String) {
        guard let entry = entries[key], let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: Self.entryPrefix + key)
    }

    /// Membership changes only when a new video is watched or a record removed;
    /// ordinary progress updates and repeated pause/exit callbacks skip this.
    private func persistIndex() {
        defaults.set(Array(entries.keys), forKey: Self.indexKey)
    }
}

/// 开流/拖动完成前会收到旧位置或短暂的 0；只有抵达请求位置才接管进度。
/// 独立于播放器内核，便于在 macOS 上验证事件次序和退出时的保存规则。
struct PlaybackResumeState {
    private(set) var position: TimeInterval
    private(set) var hasUpdatedPosition = false
    private(set) var isCompleted = false
    private var pendingPosition: TimeInterval?

    init(position: TimeInterval) {
        self.position = position.isFinite ? max(position, 0) : 0
        self.pendingPosition = self.position > 0 ? self.position : nil
    }

    mutating func prepareForOpen(at position: TimeInterval) {
        self.position = position
        pendingPosition = position > 0 ? position : nil
    }

    mutating func seek(to position: TimeInterval) {
        self.position = position
        pendingPosition = position
        hasUpdatedPosition = true
        isCompleted = false
    }

    @discardableResult
    mutating func accept(position: TimeInterval) -> Bool {
        guard !isCompleted, position.isFinite, position >= 0 else { return false }
        if let target = pendingPosition {
            guard !(target > 0 && position == 0), abs(position - target) <= 2 else { return false }
            pendingPosition = nil
        }
        self.position = position
        hasUpdatedPosition = true
        return true
    }

    /// mpv 的 PLAYBACK_RESTART 携带解码器确认的位置。即使关键帧、时间戳
    /// 或调度延迟使它偏离目标，也必须解除等待，不能把进度永久锁在目标上。
    @discardableResult
    mutating func confirm(position: TimeInterval) -> Bool {
        guard !isCompleted, position.isFinite, position >= 0 else { return false }
        pendingPosition = nil
        self.position = position
        hasUpdatedPosition = true
        return true
    }

    mutating func complete() {
        isCompleted = true
        pendingPosition = nil
    }
}
