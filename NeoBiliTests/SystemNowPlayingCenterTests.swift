import AVFAudio
import MediaPlayer
import XCTest
@testable import NeoBili

@MainActor
final class SystemNowPlayingCenterTests: XCTestCase {
    func testAudioInterruptionPausesActivePlayerWithoutAutomaticallyResuming() {
        let center = SystemNowPlayingCenter.shared
        let sessionID = UUID()
        var pauses = 0
        var plays = 0
        center.activate(
            sessionID: sessionID,
            metadata: SystemMediaMetadata(identifier: "interruption", title: "Video", artist: "", artworkURL: nil),
            onPlay: { plays += 1 }, onPause: { pauses += 1 }, onToggle: {}, onSeek: { _ in }
        )
        defer { center.deactivate(sessionID: sessionID) }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        XCTAssertEqual(pauses, 1)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]
        )
        XCTAssertEqual(pauses, 1)
        XCTAssertEqual(plays, 0)
        center.deactivate(sessionID: sessionID)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        XCTAssertEqual(pauses, 1)
    }

    func testNowPlayingInfoIdentifiesVideoAndPlaybackState() {
        let metadata = SystemMediaMetadata(
            identifier: "BV1test",
            title: "测试视频",
            artist: "测试作者",
            artworkURL: nil
        )

        let info = SystemNowPlayingCenter.makeInfo(
            metadata: metadata,
            duration: 120,
            elapsed: 35,
            playbackRate: 1
        )

        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "测试视频")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "测试作者")
        XCTAssertEqual(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String, "BV1test")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 120)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 35)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Float, 1)
        XCTAssertEqual(
            info[MPNowPlayingInfoPropertyMediaType] as? UInt,
            MPNowPlayingInfoMediaType.video.rawValue
        )
    }
}
