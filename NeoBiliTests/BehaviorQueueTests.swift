import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class BehaviorQueueTests: XCTestCase {
    private func fixture() async -> (DeviceIdentity, UserDefaults, CredentialStorage, URL) {
        let name = "queue.tests.\(UUID())", settings = UserDefaults(suiteName: name)!
        let credentials = CredentialStorage.memory()
        let identity = DeviceIdentity(defaults: settings, credentials: credentials, allowsNetwork: false, purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "secret-cookie", biliJct: "secret-csrf", dedeUserID: "42"), accessKey: "secret-token")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { settings.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        return (identity, settings, credentials, directory)
    }
    private func record(_ queue: AppBehaviorReporter, _ identity: DeviceIdentity, count: Int = 1) async {
        for index in 0..<count {
            await queue.record(name: "player.player.pause.all.player", category: 9, fields: ["ordinal": String(index)],
                session: identity.loginSessionID, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        }
    }

    func testOfflinePersistsBoundedQueueAndCooldownPreventsRequestStorm() async throws {
        let (identity, _, _, directory) = await fixture()
        let sends = Mutex(0)
        let queue = AppBehaviorReporter(identity: identity, directory: directory, automaticScheduling: false, sender: { _ in
            sends.withLock { $0 += 1 }; throw URLError(.notConnectedToInternet)
        })
        await record(queue, identity, count: 125)
        await queue.flush()
        for _ in 0..<10 { await record(queue, identity); await queue.flush() }
        XCTAssertEqual(sends.withLock { $0 }, 1)
        let data = try Data(contentsOf: directory.appendingPathComponent("pending.json"))
        let saved = try JSONDecoder().decode([AppBehaviorEvent].self, from: data)
        XCTAssertEqual(saved.count, 100)
        XCTAssertLessThanOrEqual(data.count, 1024 * 1024)
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["secret-cookie", "secret-csrf", "secret-token"] { XCTAssertFalse(text.contains(secret)) }
    }

    func testRestartDeliversOriginalEventsOnceAndReloginDiscardsThem() async throws {
        let (identity, settings, credentials, directory) = await fixture()
        let first = AppBehaviorReporter(identity: identity, directory: directory, automaticScheduling: false)
        await record(first, identity, count: 2); await first.checkpoint()
        let saved = try JSONDecoder().decode([AppBehaviorEvent].self, from: Data(contentsOf: directory.appendingPathComponent("pending.json")))
        let restarted = DeviceIdentity(defaults: settings, credentials: credentials, allowsNetwork: false, purgeCookies: {})
        let delivered = Mutex<[UUID]>([])
        let second = AppBehaviorReporter(identity: restarted, directory: directory, automaticScheduling: false, sender: { batch in
            delivered.withLock { $0 += batch.map(\.id) }
        })
        await second.flush(); await second.flush()
        XCTAssertEqual(delivered.withLock { $0 }, saved.map(\.id))
        await record(second, restarted); await second.checkpoint()
        await restarted.saveLogin(.init(sessdata: "new", biliJct: "new", dedeUserID: "42"), accessKey: "new")
        await second.flush()
        XCTAssertEqual(delivered.withLock { $0.count }, 2)
    }

    func testAmbiguousTimeoutIsNotReplayed() async throws {
        let (identity, _, _, directory) = await fixture()
        let sends = Mutex(0)
        let queue = AppBehaviorReporter(identity: identity, directory: directory, automaticScheduling: false, sender: { _ in
            sends.withLock { $0 += 1 }; throw URLError(.timedOut)
        })
        await record(queue, identity); await queue.flush(); await queue.flush()
        XCTAssertEqual(sends.withLock { $0 }, 1)
        let saved = try JSONDecoder().decode([AppBehaviorEvent].self, from: Data(contentsOf: directory.appendingPathComponent("pending.json")))
        XCTAssertTrue(saved.isEmpty)
    }

    func testLateOldSnapshotCannotDeleteNewLoginEvents() async throws {
        let (identity, _, _, directory) = await fixture()
        let gate = QueueSnapshotGate()
        let first = Mutex(true)
        let delivered = Mutex<[AppBehaviorEvent]>([])
        let queue = AppBehaviorReporter(identity: identity, directory: directory, automaticScheduling: false,
            sender: { batch in delivered.withLock { $0 += batch } }, snapshotProvider: { session in
                let value = try await identity.appDeviceSnapshot(expectedSessionID: session)
                if first.withLock({ value in let old = value; value = false; return old }) { await gate.wait() }
                return value
            })
        await record(queue, identity)
        let task = Task { await queue.checkpoint() }
        for _ in 0..<200 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let started = await gate.started
        XCTAssertTrue(started)
        await identity.saveLogin(.init(sessdata: "new", biliJct: "new", dedeUserID: "43"), accessKey: "new")
        await record(queue, identity)
        await gate.release(); await task.value
        await queue.flush()
        XCTAssertEqual(delivered.withLock { $0.map(\.context.mid) }, [43])
    }

    func testFailedDurableRemovalDoesNotSendPersistedBatch() async throws {
        let (identity, _, _, directory) = await fixture()
        let sends = Mutex(0)
        let queue = AppBehaviorReporter(identity: identity, directory: directory, automaticScheduling: false,
            sender: { _ in sends.withLock { $0 += 1 } })
        await record(queue, identity); await queue.checkpoint()
        let file = directory.appendingPathComponent("pending.json")
        // A directory at the file path deterministically makes atomic replacement fail.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        await queue.flush()
        XCTAssertEqual(sends.withLock { $0 }, 0)
    }

    func testIdleAndBackgroundHaveNoNetworkAndBurstBatchesTwenty() async {
        let (identity, _, _, directory) = await fixture()
        let sizes = Mutex<[Int]>([])
        let queue = AppBehaviorReporter(identity: identity, directory: directory, automaticScheduling: false, sender: { batch in
            sizes.withLock { $0.append(batch.count) }
        })
        await queue.flush()
        for _ in 0..<45 {
            await queue.record(name: "tm.recommend.feed-card.0.show", category: 3, fields: [:],
                session: identity.loginSessionID, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        }
        await queue.setBackground(true); await queue.flush()
        XCTAssertTrue(sizes.withLock { $0.isEmpty })
        await queue.setBackground(false)
        XCTAssertEqual(sizes.withLock { $0 }, [20, 20, 5])
    }
}

private actor QueueSnapshotGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
