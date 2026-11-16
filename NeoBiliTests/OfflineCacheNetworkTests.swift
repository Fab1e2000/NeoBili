import XCTest
@testable import NeoBili
@testable import NeoBiliDomain
@testable import NeoBiliData

final class OfflineCacheNetworkTests: XCTestCase {
    @MainActor func testPublicVideoDownloadsAllResourcesAndReopensLocally() async throws {
        guard ProcessInfo.processInfo.environment["NEOBILI_NETWORK_SMOKE"] == "1" else {
            throw XCTSkip("Run the Network plan explicitly")
        }
        let client = APIClient.shared, identity = DeviceIdentity.shared
        let detail = try await BiliAPI.videoDetail(bvid: "BV1po4y177z8", client: client)
        let video = try XCTUnwrap(OfflineSelectionModel.items(detail, collection: nil, offset: 0).first)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-network-\(UUID())")
        let transport = BackgroundCacheTransport(directory: root, enabled: true)
        let repository = OfflineCacheRepository(directory: root, transport: transport,
            prepare: { try await OfflineCachePreparation.prepare($0, client: client, identity: identity) },
            accountID: { await identity.appAccount().mid.map(String.init) })
        addTeardownBlock {
            try? await repository.service.cancel(video.id)
            try? await repository.service.delete([video.id])
            try? FileManager.default.removeItem(at: root)
        }
        try await repository.service.enqueue([video], 16, 30216, false)
        for _ in 0..<1_800 {
            let snapshot = await repository.snapshot()
            if snapshot.completed.count == 1 {
                let playback = try await repository.service.playback(video.id)
                XCTAssertTrue(playback.videoURLs.allSatisfy(\.isFileURL))
                XCTAssertNotNil(playback.coverURL)
                XCTAssertTrue(playback.entry.resources.allSatisfy(\.isComplete))
                XCTAssertGreaterThan(playback.entry.receivedBytes, 0)
                await repository.service.releasePlayback(playback.leaseID)
                return
            }
            if let failure = snapshot.tasks.first(where: { $0.state == .failed }) {
                XCTFail(failure.message ?? "Cache download failed"); return
            }
            if snapshot.occupiedBytes > 30_000_000 {
                XCTFail("Network smoke exceeded its 30 MB download budget"); return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Cache download did not complete within 180 seconds")
    }
}
