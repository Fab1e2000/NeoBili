#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
import WebKit
@testable import NeoBili

@MainActor
final class SecurityWebIsolationTests: XCTestCase {
    #if NEOBILI_REGRESSION
    func testRegressionRejectsRemoteSecurityNavigationWithoutLoading() {
        let context = SMSLoginModels.Context(accountSession: UUID(), headers: [:], buvid: "fixture",
                                             deviceID: "fixture", loginSession: "fixture")
        let coordinator = SMSSecurityView.Coordinator(loginContext: context,
            authentication: AuthenticationService(), onCode: { _ in }, onError: {})
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        let action = SecurityNavigationAction()
        var policy: WKNavigationActionPolicy?
        coordinator.webView(web, decidePolicyFor: action) { policy = $0 }
        XCTAssertEqual(policy, .cancel)
        XCTAssertNil(web.url)
    }
    #endif
}

private final class SecurityNavigationAction: WKNavigationAction {
    override var request: URLRequest { URLRequest(url: URL(string: "https://passport.bilibili.com/fixture")!) }
}
