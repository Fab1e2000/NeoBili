import XCTest

@MainActor
final class MenuTrackingTests: XCTestCase {
    func testContinuousSelectionMatrix() throws {
        let app = XCUIApplication()
        // No simulator clones or parallel tests. A cold app launch per trial
        // avoids a previous menu's dismissal affecting the next gesture.
        for mode in ["paused", "updating", "isolated"] {
            for (identifier, option, result) in [
                ("player.videoQuality", "360P", "video-0"),
                ("player.audioQuality", "Standard", "audio-0"),
                ("player.more", "Watch later", "more-selected")
            ] {
                for trial in 0..<6 {
                    app.launchArguments = mode == "paused" ? ["--paused"] : (mode == "isolated" ? ["--isolate"] : [])
                    app.launch()
                    let button = app.buttons[identifier]
                    XCTAssertTrue(button.waitForExistence(timeout: 10))
                    // Observe an actual open menu to obtain its row coordinates.
                    button.tap()
                    let row = app.buttons[option]
                    XCTAssertTrue(row.waitForExistence(timeout: 3))
                    let destination = row.frame
                    let attachment = XCTAttachment(screenshot: app.screenshot())
                    attachment.name = "\(mode)-\(identifier)-\(trial)-menu"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    app.terminate()
                    app.launch()
                    XCTAssertTrue(button.waitForExistence(timeout: 10))
                    let target = app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: destination.midX, dy: destination.midY))
                    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        .press(forDuration: 0.7, thenDragTo: target,
                               withVelocity: .slow, thenHoldForDuration: 0.8)
                    let selected = app.staticTexts["probe.selection"].label
                    print("MENU_PROBE mode=\(mode) control=\(identifier) trial=\(trial) selected=\(selected) expected=\(result)")
                    let after = XCTAttachment(screenshot: app.screenshot())
                    after.name = "\(mode)-\(identifier)-\(trial)-released-\(selected)"
                    after.lifetime = .keepAlways
                    add(after)
                    // Report each outcome; failure frequency is the experiment.
                    app.terminate()
                }
            }
        }
    }
}
