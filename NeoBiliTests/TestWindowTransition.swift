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

@MainActor
func accessibilityItem(in root: UIView, matching: (NSObject) -> Bool) -> NSObject? {
    var visited = Set<ObjectIdentifier>()
    var pending: [NSObject] = [root]
    while let object = pending.popLast() {
        guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
        if matching(object) {
            return object
        }
        if let view = object as? UIView { pending.append(contentsOf: view.subviews) }
        pending.append(contentsOf: (object.accessibilityElements ?? []).compactMap { $0 as? NSObject })
        let count = object.accessibilityElementCount()
        if count > 0, count != NSNotFound {
            for index in 0..<min(count, 1024) {
                if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
            }
        }
    }
    return nil
}
