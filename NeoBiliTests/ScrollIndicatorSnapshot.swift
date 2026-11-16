import UIKit
import XCTest

@MainActor
enum ScrollIndicatorSnapshot {
    static func frame(in scroll: UIScrollView, window: UIWindow,
                      file: StaticString = #filePath, line: UInt = #line) async throws -> CGRect {
        XCTAssertTrue(scroll.showsVerticalScrollIndicator, file: file, line: line)
        scroll.flashScrollIndicators()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        // Inspect UIKit's rendered thumb only in tests; production uses public inset APIs.
        let indicator = try XCTUnwrap(scroll.subviews.first {
            String(describing: type(of: $0)).contains("ScrollIndicator") && $0.bounds.height > $0.bounds.width
        }, "A scrollable page must render its vertical indicator", file: file, line: line)
        let frame = indicator.convert(indicator.bounds, to: window)
        let viewport = scroll.convert(scroll.bounds, to: window)
        XCTAssertEqual(frame.maxX, viewport.maxX - 3, accuracy: 1, file: file, line: line)
        return frame
    }

    static func attachment(window: UIWindow, name: String) -> XCTAttachment {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
