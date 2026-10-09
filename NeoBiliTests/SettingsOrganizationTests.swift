import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class SettingsOrganizationTests: XCTestCase {
    func testSettingsAndSharedFilterKeepExistingPreferencesAcrossPresentation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let suite = "settings-organization.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); previous?.makeKey() }
        defaults.set(5, forKey: RecommendationFilter.minLikeRatioKey)
        defaults.set("test|sample", forKey: RecommendationFilter.titleBanWordKey)
        defaults.set(false, forKey: CardAnimationSettings.masterKey)
        for (name, scheme, size, frame) in [
            ("light-portrait", ColorScheme.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 390, height: 844)),
            ("dark-large-landscape", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 844, height: 390))
        ] {
            for (page, content) in [("root", AnyView(SettingsView())), ("filter", AnyView(RecommendationFilterSettingsView()))] {
                let window = UIWindow(windowScene: scene)
                let host = UIHostingController(rootView: NavigationStack { content }
                    .defaultAppStorage(defaults).preferredColorScheme(scheme).environment(\.dynamicTypeSize, size))
                window.frame = frame; window.rootViewController = host; window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                try await Task.sleep(for: .milliseconds(250))
                window.layoutIfNeeded()
                XCTAssertTrue(window.isKeyWindow)
                XCTAssertFalse(host.view.hasAmbiguousLayout)
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "settings-\(page)-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
                if let data = image.pngData() {
                    try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("neobili-settings-\(page)-\(name).png"))
                }
                XCTAssertEqual(defaults.integer(forKey: RecommendationFilter.minLikeRatioKey), 5)
                XCTAssertEqual(defaults.string(forKey: RecommendationFilter.titleBanWordKey), "test|sample")
                XCTAssertFalse(defaults.bool(forKey: CardAnimationSettings.masterKey))
            }
        }
    }
}
