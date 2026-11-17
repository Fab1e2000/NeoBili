import XCTest
import SwiftUI
@testable import NeoBili
@testable import NeoBiliDomain

@MainActor
final class OfflinePlaybackIntegrationTests: XCTestCase {
    func testLocalDualTrackPlaybackSubtitleSeekAndEnd() async throws {
        guard ProcessInfo.processInfo.environment["NEOBILI_OFFLINE_PLAYBACK_SMOKE"] == "1" else {
            throw XCTSkip("Run the OfflinePlayback test plan explicitly")
        }
        let bundle = Bundle(for: Self.self)
        let video = try XCTUnwrap(bundle.url(forResource: "offline-video", withExtension: "mp4"))
        let audio = try XCTUnwrap(bundle.url(forResource: "offline-audio", withExtension: "m4a"))
        let name = "offline-runtime-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let player = PlayerViewModel(bvid: "BV-offline", cid: 1,
            offline: OfflinePlaybackTests.descriptor(video: video, audio: audio),
            dependencies: .isolated(defaults: defaults))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow, window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: InlineVideoPlayer(viewModel: player, controlsVisible: .constant(true),
            coverURL: nil, isFullScreen: false, onToggleFullScreen: {}, videoTitle: "离线播放测试")
            .frame(height: 300).environment(AccountStore()).environment(ActionFeedback()))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        defer { player.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        await player.load()
        for _ in 0..<600 {
            if player.hasRenderedFirstFrame && player.currentTime > 0.2 { break }
            if player.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(player.errorMessage)
        guard player.hasRenderedFirstFrame else { XCTFail("Local player did not render a frame"); return }
        XCTAssertGreaterThan(player.currentTime, 0)
        player.ensureDanmaku()
        await player.seek(to: 2)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertGreaterThanOrEqual(player.currentTime, 1.8)
        XCTAssertEqual(player.offline?.subtitles.first?.text(at: player.currentTime), "离线字幕同步测试")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "offline-native-playback"
        attachment.lifetime = .keepAlways; add(attachment)
        for _ in 0..<90 {
            if player.isPlaybackCompleted { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(player.isPlaybackCompleted)
        XCTAssertFalse(player.isPlaying)
    }
}
