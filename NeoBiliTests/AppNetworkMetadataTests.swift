import XCTest
@testable import NeoBili

final class AppNetworkMetadataTests: XCTestCase {
    func testPathChangesReplaceBothQueryAndHeaderWithoutRetainingOldNetwork() throws {
        let metadata = AppNetworkMetadata()
        XCTAssertEqual(metadata.snapshot().queryNetwork, "")
        XCTAssertTrue(metadata.snapshot().headers.isEmpty)

        metadata.update(isSatisfied: true, usesWiFi: true, usesCellular: false)
        let wifi = metadata.snapshot()
        XCTAssertEqual(wifi.queryNetwork, "wifi")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(wifi.headers["x-bili-network-bin"])), Data([8, 1]))

        metadata.update(isSatisfied: true, usesWiFi: false, usesCellular: true)
        let cellular = metadata.snapshot()
        XCTAssertEqual(cellular.queryNetwork, "mobile")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(cellular.headers["x-bili-network-bin"])), Data([8, 2]))
        // Previously captured snapshots remain coherent across an interface switch.
        XCTAssertEqual(wifi.queryNetwork, "wifi")

        metadata.update(isSatisfied: false, usesWiFi: true, usesCellular: false)
        XCTAssertEqual(metadata.snapshot().queryNetwork, "")
        XCTAssertTrue(metadata.snapshot().headers.isEmpty)
    }

    func testUnknownOrWiredInterfaceDoesNotInventWiFiOrRegionMetadata() {
        let metadata = AppNetworkMetadata()
        metadata.update(isSatisfied: true, usesWiFi: false, usesCellular: false)
        XCTAssertEqual(metadata.snapshot().queryNetwork, "")
        XCTAssertTrue(metadata.snapshot().headers.isEmpty)
        metadata.update(isSatisfied: true, usesWiFi: true, usesCellular: false)
        XCTAssertEqual(Set(metadata.snapshot().headers.keys), ["x-bili-network-bin"])
    }

    func testRegressionSharedMonitorStartsWithNoLivePath() {
        guard AppNetwork.isRegression else { return }
        XCTAssertEqual(AppNetworkMetadata.shared.snapshot().connection, .unknown)
    }
}
