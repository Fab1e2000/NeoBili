import AVFAudio
import MediaPlayer
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class SystemNowPlayingCenterTests: XCTestCase {
    func testIdleTimerFollowsCurrentMediaAndIgnoresOldSessionEvents() {
        let center = SystemNowPlayingCenter.shared
        let oldSession = UUID()
        let currentSession = UUID()
        let originalIdleTimer = UIApplication.shared.isIdleTimerDisabled
        defer {
            center.deactivate(sessionID: currentSession)
            center.deactivate(sessionID: oldSession)
            if UIApplication.shared.applicationState != .active {
                NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            }
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimer
        }
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let metadata = SystemMediaMetadata(identifier: "idle-timer", title: "Video", artist: "", artworkURL: nil)
        center.activate(sessionID: oldSession, metadata: metadata,
                        onPlay: {}, onPause: {}, onToggle: {}, onSeek: { _ in })
        center.updatePlaybackState(isPlaying: true, sessionID: oldSession)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)

        center.activate(sessionID: currentSession, metadata: metadata,
                        onPlay: {}, onPause: {}, onToggle: {}, onSeek: { _ in })
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        center.updatePlaybackState(isPlaying: true, sessionID: currentSession)
        center.updatePlaybackState(isPlaying: false, sessionID: oldSession)
        center.deactivate(sessionID: oldSession)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        center.updatePlaybackState(isPlaying: false, sessionID: currentSession)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        center.updatePlaybackState(isPlaying: true, sessionID: currentSession)
        center.deactivate(sessionID: currentSession)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

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
