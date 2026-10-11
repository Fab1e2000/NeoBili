import XCTest
@testable import NeoBili

@MainActor
final class PlaybackIdleTimerTests: XCTestCase {
    func testPlaybackKeepsScreenAwakeAndPauseOrEndRestoresIdleTimer() {
        var writes: [Bool] = []
        let timer = PlaybackIdleTimer(isApplicationActive: true) { writes.append($0) }
        timer.update(isPlaying: false)
        timer.update(isPlaying: true)
        timer.update(isPlaying: false)
        timer.update(isPlaying: true)
        timer.update(isPlaying: false)
        XCTAssertEqual(writes, [false, true, false, true, false])
    }

    func testBackgroundPlaybackRestoresIdleTimerAndForegroundResumesProtection() {
        var writes: [Bool] = []
        let timer = PlaybackIdleTimer(isApplicationActive: true) { writes.append($0) }
        timer.update(isPlaying: true)
        timer.setApplicationActive(false)
        timer.update(isPlaying: true)
        timer.setApplicationActive(true)
        XCTAssertEqual(writes, [true, false, true])
    }

    func testPausingInBackgroundDoesNotKeepScreenAwakeOnReturn() {
        var writes: [Bool] = []
        let timer = PlaybackIdleTimer(isApplicationActive: false) { writes.append($0) }
        timer.update(isPlaying: true)
        timer.update(isPlaying: false)
        timer.setApplicationActive(true)
        XCTAssertEqual(writes, [false])
    }

    func testRepeatedPlaybackUpdatesDoNotRewriteSystemSetting() {
        var writes: [Bool] = []
        let timer = PlaybackIdleTimer(isApplicationActive: true) { writes.append($0) }
        for _ in 0..<100 { timer.update(isPlaying: true) }
        for _ in 0..<100 { timer.setApplicationActive(true) }
        XCTAssertEqual(writes, [true])
    }
}
