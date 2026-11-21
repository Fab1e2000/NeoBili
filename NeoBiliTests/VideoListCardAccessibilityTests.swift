import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class VideoListCardAccessibilityTests: XCTestCase {
    func testPressChangesCardSurfaceWithoutColoringItsCornersOrGutter() throws {
        for radius in [VideoListCardLayout.cardCornerRadius, OfflineCacheStyle.radius] {
            for scheme in [ColorScheme.light, .dark] {
                let style = CardPressStyle(cornerRadius: radius)
                func render(pressed: Bool) throws -> CGImage {
                    let label = Color(uiColor: .secondarySystemGroupedBackground).frame(width: 80, height: 52)
                    let view = style.surface(label, isPressed: pressed)
                        .padding(4)
                        .background(Color(uiColor: .systemGroupedBackground))
                        .environment(\.colorScheme, scheme)
                    return try XCTUnwrap(ImageRenderer(content: view).cgImage)
                }
                let normal = try render(pressed: false)
                let pressed = try render(pressed: true)
                func pixel(_ image: CGImage, x: Int, y: Int) throws -> Data {
                    let crop = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
                    return try XCTUnwrap(UIImage(cgImage: crop).pngData())
                }
                XCTAssertNotEqual(try pixel(normal, x: 44, y: 30), try pixel(pressed, x: 44, y: 30))
                XCTAssertEqual(try pixel(normal, x: 4, y: 4), try pixel(pressed, x: 4, y: 4))
                XCTAssertEqual(try pixel(normal, x: 2, y: 30), try pixel(pressed, x: 2, y: 30))
            }
        }
    }

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
                    let card = Button { } label: {
                        VideoListCard(coverURL: nil,
                            title: "旅行摄影记录：从山川湖海到城市街头，分享沿途遇见的每一处风景",
                            author: "记录生活的摄影师", playCount: 128_000, durationText: "12:34", animatesEntrance: false)
                    }
                        .buttonStyle(CardPressStyle(cornerRadius: VideoListCardLayout.cardCornerRadius))
                        .contextMenu { Button("稍后再看") { } }
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
