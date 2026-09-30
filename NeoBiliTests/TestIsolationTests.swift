import XCTest
@testable import NeoBili

final class TestIsolationTests: XCTestCase {
    func testRegressionUsesSeparateApplicationContainer() {
        XCTAssertTrue(AppNetwork.isRegression)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.elsterlee.NeoBili.regression")
    }

    func testDefaultTransportCannotContactLiveServices() async {
        do {
            _ = try await AppNetwork.session.data(from: URL(string: "https://api.bilibili.com/x/web-interface/nav")!)
            XCTFail("Regression transport allowed a live request")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertNil(AppNetwork.session.configuration.httpCookieStorage)
        XCTAssertNil(AppNetwork.session.configuration.urlCache)
    }

    func testIndependentCredentialStoresAndReload() async {
        let suite = "neobili.identity.isolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = CredentialStorage.memory()
        let first = DeviceIdentity(defaults: defaults, credentials: storage, allowsNetwork: false, purgeCookies: {})
        await first.setLoginCookies(sessdata: "fixture", biliJct: "csrf", dedeUserID: "42")
        let reloaded = DeviceIdentity(defaults: defaults, credentials: storage, allowsNetwork: false, purgeCookies: {})
        let other = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false, purgeCookies: {})
        let retained = await reloaded.isLoggedIn
        let unrelated = await other.isLoggedIn
        XCTAssertTrue(retained)
        XCTAssertFalse(unrelated)
        await other.clearLoginCookies()
        let final = DeviceIdentity(defaults: defaults, credentials: storage, allowsNetwork: false, purgeCookies: {})
        let stillRetained = await final.isLoggedIn
        XCTAssertTrue(stillRetained)
    }
}
