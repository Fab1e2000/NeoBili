import XCTest
@testable import NeoBili

@MainActor
final class AppPlayerBehaviorTests: XCTestCase {
    func testPlayerPayloadUsesPositionRateAndOfficialQualityMapping() throws {
        let data = try XCTUnwrap(AppPlayerBehavior.payload(aid: 1, cid: 2, position: 12.345,
            playbackSession: "playback", source: ["from_spmid": "main.my-history.0.0"],
            quality: 80, playbackRate: 1.25))
        let message = try AppProto(data)
        XCTAssertEqual(message.text(1), "main.my-history.0.0")
        XCTAssertEqual(message.text(6), "12345")
        XCTAssertEqual(message.text(15), "1.25")
        XCTAssertEqual(message.text(16), "80")
        XCTAssertEqual(message.number(17), 2)
    }

    func testUnknownQualityAndMissingOriginDoNotClaimSelectedQuality() throws {
        let data = try XCTUnwrap(AppPlayerBehavior.payload(aid: 1, cid: 2, position: 0,
            playbackSession: "playback", source: [:], quality: 127))
        let message = try AppProto(data)
        XCTAssertEqual(message.text(1), "default-value")
        XCTAssertEqual(message.text(15), "1.0")
        XCTAssertEqual(message.text(16), "0")
        let preview = try AppProto(XCTUnwrap(AppPlayerBehavior.payload(aid: 1, cid: 2, position: 0,
            playbackSession: "preview", source: [:], quality: nil, inlinePreview: true)))
        XCTAssertNil(preview.text(16))
        XCTAssertEqual(preview.number(17), 1)
    }

    func testInvalidPlaybackSamplesAreRejectedAndProgressIsBounded() throws {
        for value in [Double.nan, .infinity, -1] {
            XCTAssertNil(AppPlayerBehavior.payload(aid: 1, cid: 2, position: value,
                playbackSession: "playback", source: [:], quality: 80))
        }
        let data = try XCTUnwrap(AppPlayerBehavior.payload(aid: 1, cid: 2, position: Double.greatestFiniteMagnitude,
            playbackSession: "playback", source: [:], quality: 80))
        XCTAssertEqual(try AppProto(data).text(6), String(Int32.max))
    }
}
