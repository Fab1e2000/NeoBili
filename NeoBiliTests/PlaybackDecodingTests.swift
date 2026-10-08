import XCTest
@testable import NeoBili

final class PlaybackDecodingTests: XCTestCase {
    func testSilentPortraitManifestAllowsNullOrMissingAudio() throws {
        for audio in [",\"audio\":null", "", ",\"audio\":[]"] {
            let data = Data("""
            {"quality":80,"dash":{"duration":15,"video":[
            {"id":80,"base_url":"https://example.com/portrait.m4s","bandwidth":1000,
             "mime_type":"video/mp4","codecs":"avc1.640028","width":1080,"height":1920}
            ]\(audio)}}
            """.utf8)
            let manifest = try JSONDecoder().decode(PlayURLData.self, from: data)
            XCTAssertTrue(manifest.hasPlayableStream)
            XCTAssertEqual(manifest.dash?.audio, [])
            XCTAssertEqual(manifest.dash?.video.first?.height, 1920)
            let source = try PlaybackSourceBuilder.makeSource(from: manifest, configuration: .fastStart)
            XCTAssertNil(source.audio)
            XCTAssertTrue(source.isDASH)
            XCTAssertEqual(source.duration, 15)
            XCTAssertEqual(PlaybackSourceBuilder.edlURL(for: source), "https://example.com/portrait.m4s")
            XCTAssertTrue(source.candidates.allSatisfy(\.isDASH))
        }
    }

    @MainActor
    func testSilentDASHRetainsSelectedQualityAndPortraitDimensions() async throws {
        let manifest = try JSONDecoder().decode(PlayURLData.self, from: Data("""
        {"quality":80,"dash":{"duration":15,"audio":null,"video":[
         {"id":64,"base_url":"https://example.com/silent.m4s","bandwidth":1000,
          "mime_type":"video/mp4","codecs":"avc1.640028","width":1080,"height":1920}]}}
        """.utf8))
        var opened: PlaybackSource?
        let player = PlayerViewModel(bvid: "silent-portrait", cid: 1,
            playbackURLLoader: { _, _ in manifest }, sourceOpener: { _, source, _ in opened = source })
        defer { player.stop() }
        await player.load()
        XCTAssertNil(player.errorMessage)
        XCTAssertNotNil(opened)
        XCTAssertNil(opened?.audio)
        XCTAssertEqual(player.selectedVideoQuality, 64)
        XCTAssertEqual(player.selectedVideoWidth, 1080)
        XCTAssertEqual(player.selectedVideoHeight, 1920)
        XCTAssertNil(player.selectedAudioQuality)
    }

    func testMalformedAudioAndMissingVideoAreStillRejected() {
        for body in [#"{"duration":15,"video":[],"audio":{}}"#,
                     #"{"duration":15,"video":null,"audio":[]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(DashPayload.self, from: Data(body.utf8)))
        }
    }
}
