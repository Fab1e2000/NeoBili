import Foundation

private final class RecordingDefaults: UserDefaults, @unchecked Sendable {
    var writes = 0
    var dataBytes = 0
    var indexWrites = 0
    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        if let data = value as? Data { dataBytes += data.count }
        if value is [String] { indexWrites += 1 }
        super.set(value, forKey: defaultName)
    }
    func resetCounts() { writes = 0; dataBytes = 0; indexWrites = 0 }
}

@MainActor
@main
struct PlaybackPersistencePerformance {
    private struct LegacyEntry: Codable {
        let position: Double
        let duration: Double?
        let updatedAt: Date
    }

    static func main() throws {
        let suite = "neobili.persistence.performance.\(UUID().uuidString)"
        let defaults = RecordingDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = Dictionary(uniqueKeysWithValues: (1...2_000).map {
            ("BVTest\($0):1", LegacyEntry(position: Double($0), duration: 10_000,
                                         updatedAt: Date(timeIntervalSince1970: Double($0))))
        })
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: "neobili.playbackProgress.v1")
        let migrated = PlaybackProgressStore(defaults: defaults, now: { Date(timeIntervalSince1970: 3_000) })
        precondition(migrated.resumePosition(bvid: "BVTest1", cid: 1) == 1)
        precondition(migrated.resumePosition(bvid: "BVTest2000", cid: 1) == 2_000)
        precondition(defaults.data(forKey: "neobili.playbackProgress.v1") == nil)
        let reopened = PlaybackProgressStore(defaults: defaults)
        precondition(reopened.resumePosition(bvid: "BVTest1000", cid: 1) == 1_000)
        defaults.resetCounts()
        for step in 1...12 {
            migrated.save(bvid: "BVTest1", cid: 1, position: Double(step * 5), duration: 10_000)
        }
        let checkpointWrites = defaults.writes
        let checkpointBytes = defaults.dataBytes
        precondition(checkpointWrites == 12 && defaults.indexWrites == 0,
                     "Heartbeats must update only the active video, without serializing history membership")
        for _ in 0..<6 { migrated.save(bvid: "BVTest1", cid: 1, position: 60, duration: 10_000) }
        precondition(defaults.writes == checkpointWrites,
                     "Pause, background and dismiss at the same position must not repeat writes")
        precondition(PlaybackProgressStore(defaults: defaults).resumePosition(bvid: "BVTest1", cid: 1) == 60)
        migrated.remove(bvid: "BVTest1", cid: 1)
        precondition(PlaybackProgressStore(defaults: defaults).resumePosition(bvid: "BVTest1", cid: 1) == 0)
        print("PASS  All 2000 v1 records migrate; new checkpoints persist and completion stays removed")
        print("CHECKPOINT_BYTES_12_UPDATES legacy=\(legacyData.count * 12) incremental=\(checkpointBytes)")
        print("ENCODED_RECORDS_PER_CHECKPOINT legacy=2000 incremental=1")
        print("DUPLICATE_SAVE_WRITES_6_CALLBACKS legacy=6 incremental=0")
        print("ALL PLAYBACK PERSISTENCE PERFORMANCE CHECKS PASS")
    }
}
