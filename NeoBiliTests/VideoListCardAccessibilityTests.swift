import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class VideoListCardAccessibilityTests: XCTestCase {
    func testSharedCardsGrowForLargeTextInLightAndDarkLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.frame = scene.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        for width in [CGFloat(320), 700] {
            for scheme in [ColorScheme.light, .dark] {
                var ordinaryHeight: CGFloat = 0
                for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                    let card = VideoListCard(coverURL: nil,
                        title: "旅行摄影记录：从山川湖海到城市街头，分享沿途遇见的每一处风景",
                        author: "记录生活的摄影师", playCount: 128_000, durationText: "12:34", animatesEntrance: false)
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.colorScheme, scheme)
                    host.rootView = AnyView(card.frame(width: width))
                    let measured = host.sizeThatFits(in: CGSize(width: width, height: 2000))
                    if size == .large { ordinaryHeight = measured.height }
                    else { XCTAssertGreaterThan(measured.height, ordinaryHeight + 10, "Large text must expand its card") }
                    XCTAssertEqual(measured.width, width, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(ordinaryHeight, 102)
                    host.rootView = AnyView(card.frame(width: width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(uiColor: .systemBackground)))
                    host.view.frame = CGRect(x: 0, y: 0, width: width, height: max(300, measured.height))
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(30))
                    let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "video-card-\(Int(width))-\(scheme)-\(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
