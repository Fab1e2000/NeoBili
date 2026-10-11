import XCTest
@testable import NeoBili

final class CustomBuvidSettingsTests: XCTestCase {
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
