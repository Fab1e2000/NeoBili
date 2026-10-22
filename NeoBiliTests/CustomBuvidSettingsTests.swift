#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

final class CustomBuvidSettingsTests: XCTestCase {
    @MainActor
    func testIntroductionOnlyAppearsBeforeAcknowledgement() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let suite = "buvid-introduction.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); previous?.makeKey() }
        for acknowledged in [false, true] {
            defaults.set(acknowledged, forKey: DeviceIdentitySettingsView.introductionSeenKey)
            defaults.set("fixture-device-123456", forKey: DeviceIdentityPreferences.customKey)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: NavigationStack { DeviceIdentitySettingsView() }
                .defaultAppStorage(defaults))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(500))
            if acknowledged {
                XCTAssertNil(host.presentedViewController)
            } else {
                let alert = try XCTUnwrap(host.presentedViewController as? UIAlertController)
                XCTAssertEqual(alert.title, "设备编号与推荐")
                XCTAssertEqual(alert.actions.compactMap(\.title), ["知道了"])
                XCTAssertTrue(alert.message?.contains("请求头中的 buvid") == true)
                XCTAssertTrue(alert.message?.contains("不能保证推荐完全一致") == true)
                XCTAssertFalse(defaults.bool(forKey: DeviceIdentitySettingsView.introductionSeenKey),
                               "Merely presenting the notice must not acknowledge it")
                let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                })
                attachment.name = "device-identity-introduction"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertEqual(defaults.string(forKey: DeviceIdentityPreferences.customKey), "fixture-device-123456")
        }
    }

    func testInputValidationAndSavedPreference() throws {
        let suite = "custom-buvid.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(DeviceIdentityPreferences.customBuvid(defaults: defaults))
        for invalid in ["", "short", "https://example.com/device", String(repeating: "x", count: 129)] {
            XCTAssertNil(DeviceIdentityPreferences.normalizedCustomBuvid(invalid))
        }
        defaults.set("  fixture-device-123456\n", forKey: DeviceIdentityPreferences.customKey)
        XCTAssertEqual(DeviceIdentityPreferences.customBuvid(defaults: defaults), "fixture-device-123456")
    }

    func testSavedCustomIdentityAppliesOnRestartAndBlankRestoresStableRandom() async throws {
        let suite = "custom-buvid.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = CredentialStorage.memory()
        let random = DeviceIdentity(defaults: defaults, randomBuvidExperiment: true, credentials: storage, allowsNetwork: false)
        let original = await random.appBuvid()
        defaults.set("fixture-device-123456", forKey: DeviceIdentityPreferences.customKey)
        let running = await random.appBuvid()
        XCTAssertEqual(running, original)
        let custom = DeviceIdentity(defaults: defaults, customBuvid: DeviceIdentityPreferences.customBuvid(defaults: defaults), credentials: storage, allowsNetwork: false)
        let imported = await custom.appBuvid()
        XCTAssertEqual(imported, "fixture-device-123456")
        defaults.set("", forKey: DeviceIdentityPreferences.customKey)
        let restarted = DeviceIdentity(defaults: defaults, randomBuvidExperiment: true, credentials: storage, allowsNetwork: false)
        let restored = await restarted.appBuvid()
        XCTAssertEqual(restored, original)
    }

    func testCustomDeviceCachesAreIsolatedAndReusable() {
        let storage = CredentialStorage.memory()
        storage.write("own-ticket", "neobili.app.ticket")
        let a = AppBuvid.customRegistrationStorage(storage, buvid: "fixture-device-123456")
        let b = AppBuvid.customRegistrationStorage(storage, buvid: "fixture-device-654321")
        a.write("custom-ticket", "neobili.app.ticket")
        XCTAssertNil(b.read("neobili.app.ticket"))
        XCTAssertEqual(storage.read("neobili.app.ticket"), "own-ticket")
        XCTAssertEqual(AppBuvid.customRegistrationStorage(storage, buvid: "fixture-device-123456").read("neobili.app.ticket"), "custom-ticket")
    }
}
