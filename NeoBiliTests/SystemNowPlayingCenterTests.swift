#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import AVFAudio
import MediaPlayer
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class SystemNowPlayingCenterTests: XCTestCase {
    func testIdleTimerFollowsCurrentMediaAndIgnoresOldSessionEvents() {
        let notifications = NotificationCenter()
        var idleDisabled = false
        let center = SystemNowPlayingCenter(output: .init(), notifications: notifications,
            interruptionObject: nil,
            idleTimer: PlaybackIdleTimer(isApplicationActive: true, setDisabled: { idleDisabled = $0 }),
            artworkLoader: { _ in throw URLError(.notConnectedToInternet) })
        let oldSession = UUID()
        let currentSession = UUID()
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let metadata = SystemMediaMetadata(identifier: "idle-timer", title: "Video", artist: "", artworkURL: nil)
        center.activate(sessionID: oldSession, metadata: metadata,
                        onPlay: {}, onPause: {}, onToggle: {}, onSeek: { _ in })
        center.updatePlaybackState(isPlaying: true, sessionID: oldSession)
        XCTAssertTrue(idleDisabled)

        center.activate(sessionID: currentSession, metadata: metadata,
                        onPlay: {}, onPause: {}, onToggle: {}, onSeek: { _ in })
        XCTAssertFalse(idleDisabled)
        center.updatePlaybackState(isPlaying: true, sessionID: currentSession)
        center.updatePlaybackState(isPlaying: false, sessionID: oldSession)
        center.deactivate(sessionID: oldSession)
        XCTAssertTrue(idleDisabled)

        notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(idleDisabled)
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(idleDisabled)
        center.updatePlaybackState(isPlaying: false, sessionID: currentSession)
        XCTAssertFalse(idleDisabled)
        center.updatePlaybackState(isPlaying: true, sessionID: currentSession)
        center.deactivate(sessionID: currentSession)
        XCTAssertFalse(idleDisabled)
    }

    func testAudioInterruptionPausesActivePlayerWithoutAutomaticallyResuming() {
        let notifications = NotificationCenter()
        var idleDisabled = false
        let center = SystemNowPlayingCenter(output: .init(), notifications: notifications,
            interruptionObject: nil,
            idleTimer: PlaybackIdleTimer(isApplicationActive: true, setDisabled: { idleDisabled = $0 }),
            artworkLoader: { _ in throw URLError(.notConnectedToInternet) })
        let sessionID = UUID()
        var pauses = 0
        var plays = 0
        center.activate(
            sessionID: sessionID,
            metadata: SystemMediaMetadata(identifier: "interruption", title: "Video", artist: "", artworkURL: nil),
            onPlay: { plays += 1 }, onPause: { pauses += 1 }, onToggle: {}, onSeek: { _ in }
        )
        defer { center.deactivate(sessionID: sessionID) }
        notifications.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        XCTAssertEqual(pauses, 1)
        notifications.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]
        )
        XCTAssertEqual(pauses, 1)
        XCTAssertEqual(plays, 0)
        center.deactivate(sessionID: sessionID)
        notifications.post(
            name: AVAudioSession.interruptionNotification, object: nil,
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
