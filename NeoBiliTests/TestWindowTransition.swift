import UIKit
import XCTest

/// Test hosts must finish rotation before measuring or snapshotting their roots.
@MainActor
enum TestWindowTransition {
    static func wait(for controller: UIViewController,
                     file: StaticString = #filePath, line: UInt = #line) async throws {
        // UIKit documents that an alongside completion may run even when the
        // registration returns false. Never resume a continuation from both.
        // Polling is confined to tests and bounded; no callback can resume twice.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while controller.transitionCoordinator != nil {
            guard ContinuousClock.now < deadline else {
                XCTFail("Test window transition did not finish: frame=\(controller.view.frame)", file: file, line: line)
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
