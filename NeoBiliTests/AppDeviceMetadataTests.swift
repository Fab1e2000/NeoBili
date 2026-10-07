import XCTest
@testable import NeoBili

final class AppDeviceMetadataTests: XCTestCase {
    func testNetworkDescriptorUsesOwnDeviceGuestAndFingerprint() throws {
        let bytes = AppDeviceMetadata.encode(
            local: .init(device: "pad", model: "fixture-model", osVersion: "27.0"),
            buvid: "own-buvid", guestID: 123456789012345, fingerprint: "own-server-device",
            firstTrackTime: 1700000000)
        let message = try AppProto(bytes)
        XCTAssertEqual(Set(message.fields.keys), Set(1...16))
        XCTAssertEqual(message.number(1), 1)
        XCTAssertEqual(message.number(2), Int(AppClientIdentity.build))
        XCTAssertEqual(message.text(3), "own-buvid")
        XCTAssertEqual(message.text(4), AppClientIdentity.mobiApp)
        XCTAssertEqual(message.text(5), "ios")
        XCTAssertEqual(message.text(6), "pad")
        XCTAssertEqual(message.text(7), "pink_overseas")
        XCTAssertEqual(message.text(8), "Apple")
        XCTAssertEqual(message.text(9), "fixture-model")
        XCTAssertEqual(message.text(10), "27.0")
        XCTAssertEqual(message.text(11), "")
        XCTAssertEqual(message.text(12), "")
        XCTAssertEqual(message.text(13), AppClientIdentity.version)
        XCTAssertEqual(message.text(14), "own-server-device")
        XCTAssertEqual(message.number(15), 1700000000)
        XCTAssertEqual(message.text(16), "123456789012345")
        XCTAssertEqual(Data(base64Encoded: bytes.base64EncodedString()), bytes)
    }

    func testMissingRegistrationDoesNotFabricateIdentityOrTimestamp() throws {
        let local = AppDeviceMetadata.LocalSnapshot(device: "phone", model: "local-model", osVersion: "26.0")
        let message = try AppProto(AppDeviceMetadata.encode(local: local, buvid: "own", guestID: nil,
                                                            fingerprint: nil))
        XCTAssertEqual(message.text(14), "")
        XCTAssertNil(message.fields[15])
        XCTAssertNil(message.fields[16])
        XCTAssertEqual(message.text(3), "own")
    }

    func testGuestIdentifierUsesStringWireTypeIncludingSignedCachedValues() throws {
        let message = try AppProto(AppDeviceMetadata.encode(
            local: .init(device: "phone", model: "local", osVersion: "26"),
            buvid: "own", guestID: -1, fingerprint: nil))
        XCTAssertEqual(message.text(16), "-1")
        XCTAssertNotNil(message.data(16))
    }
}
