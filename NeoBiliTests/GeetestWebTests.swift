import SwiftUI
import WebKit
import XCTest
@testable import NeoBili

@MainActor
final class GeetestWebTests: XCTestCase {
    func testBindWaitsForReadyAndForwardsSDKResultFieldsExactlyOnce() async throws {
        var states: [GeetestView.LoadState] = []
        var results: [GeetestView.Result?] = []
        let coordinator = GeetestView.Coordinator(onState: { states.append($0) }, onFinish: { results.append($0) })
        let web = makeWeb(coordinator: coordinator)
        defer { release(web, coordinator) }
        let gt = "server'gt</script>\nvalue"
        web.loadHTMLString(GeetestView.html(gt: gt, challenge: "server-challenge", language: "en"), baseURL: nil)
        try await wait { (try? await web.evaluateJavaScript("!!window.fixture?.options")) as? Bool == true }
        let beforeReady = try await integer(web, "fixture.verifications")
        XCTAssertEqual(beforeReady, 0, "bind must not verify before onReady")
        XCTAssertTrue(states.isEmpty)
        let actualGT = try await web.evaluateJavaScript("fixture.options.gt") as? String
        let language = try await web.evaluateJavaScript("fixture.options.lang") as? String
        let https = try await web.evaluateJavaScript("fixture.options.https") as? Bool
        XCTAssertEqual(actualGT, gt)
        XCTAssertEqual(language, "en")
        XCTAssertEqual(https, true)
        _ = try await web.evaluateJavaScript("fixture.ready(); fixture.ready()")
        try await wait { states.contains(.ready) }
        let verifications = try await integer(web, "fixture.verifications")
        let appendCalls = try await integer(web, "fixture.appendCalls")
        XCTAssertEqual(verifications, 1)
        XCTAssertEqual(appendCalls, 0, "appendTo is invalid for bind mode")
        _ = try await web.evaluateJavaScript("fixture.success(); fixture.close()")
        try await wait { !results.isEmpty }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], .init(challenge: "verified-challenge", validate: "verified-value", seccode: "verified-code"))
    }

    func testSDKFailureKeepsPageOpenAndRetryUsesANewAttempt() async throws {
        var states: [GeetestView.LoadState] = []
        var completions = 0
        let first = GeetestView.Coordinator(onState: { states.append($0) }, onFinish: { _ in completions += 1 })
        let web = makeWeb(coordinator: first)
        defer { release(web, first) }
        web.loadHTMLString(GeetestView.html(gt: "fixture", challenge: "fixture"), baseURL: nil)
        try await wait { (try? await web.evaluateJavaScript("!!window.fixture?.options")) as? Bool == true }
        _ = try await web.evaluateJavaScript("fixture.error(); fixture.ready(); fixture.success()")
        try await wait { states.contains(.failed) }
        XCTAssertEqual(completions, 0, "Failure must offer retry without submitting or dismissing")
        XCTAssertEqual(states, [.failed])
        let verifications = try await integer(web, "fixture.verifications")
        XCTAssertEqual(verifications, 0)

        let retry = GeetestView.Coordinator(onState: { states.append($0) }, onFinish: { _ in completions += 1 })
        let retryWeb = makeWeb(coordinator: retry)
        defer { release(retryWeb, retry) }
        retryWeb.loadHTMLString(GeetestView.html(gt: "fixture", challenge: "fixture"), baseURL: nil)
        try await wait { (try? await retryWeb.evaluateJavaScript("!!window.fixture?.options")) as? Bool == true }
        _ = try await retryWeb.evaluateJavaScript("fixture.ready(); fixture.success()")
        try await wait { completions == 1 }
        XCTAssertEqual(states, [.failed, .ready])
    }

    func testMissingSDKShowsFailureAndRegressionHTMLNeverContactsCaptchaServer() async throws {
        #if NEOBILI_REGRESSION
        let html = GeetestView.html(gt: "fixture", challenge: "fixture")
        XCTAssertFalse(html.contains("https://static.geetest.com"))
        var state: GeetestView.LoadState = .loading
        let coordinator = GeetestView.Coordinator(onState: { state = $0 }, onFinish: { _ in XCTFail("No verification occurred") })
        let web = coordinator.makeWebView()
        defer { release(web, coordinator) }
        web.loadHTMLString(html, baseURL: nil)
        try await wait { state == .failed }
        #endif
    }

    func testIncompleteSuccessDoesNotSubmitLogin() async throws {
        var state: GeetestView.LoadState = .loading
        let coordinator = GeetestView.Coordinator(onState: { state = $0 }, onFinish: { _ in XCTFail("Incomplete result cannot log in") })
        let web = makeWeb(coordinator: coordinator)
        defer { release(web, coordinator) }
        web.loadHTMLString(GeetestView.html(gt: "fixture", challenge: "fixture"), baseURL: nil)
        try await wait { (try? await web.evaluateJavaScript("!!window.fixture?.options")) as? Bool == true }
        _ = try await web.evaluateJavaScript("fixture.result = {challenge:'wrong-field'}; fixture.success()")
        try await wait { state == .failed }
    }

    func testStartupTimeoutAndWebProcessFailureDoNotBecomeSilentBlankPages() async throws {
        var states: [GeetestView.LoadState] = []
        let coordinator = GeetestView.Coordinator(onState: { states.append($0) }, onFinish: { _ in XCTFail() })
        coordinator.beginLoading(timeout: .milliseconds(10))
        try await wait { states == [.failed] }
        coordinator.receive(["type": "ready"])
        XCTAssertEqual(states, [.failed])
        coordinator.cancel()

        let crashed = GeetestView.Coordinator(onState: { states.append($0) }, onFinish: { _ in XCTFail() })
        let web = crashed.makeWebView()
        defer { release(web, crashed) }
        crashed.webView(web, didFailProvisionalNavigation: nil, withError: URLError(.cancelled))
        XCTAssertEqual(states, [.failed])
        crashed.webViewWebContentProcessDidTerminate(web)
        XCTAssertEqual(states, [.failed, .failed])
    }

    func testDismissingPageCancelsLoadingTimeoutAndLateReady() async throws {
        let coordinator = GeetestView.Coordinator(onState: { _ in XCTFail("Dismissed page must not update") }, onFinish: { _ in XCTFail() })
        coordinator.beginLoading(timeout: .milliseconds(10))
        coordinator.cancel()
        coordinator.receive(["type": "ready"])
        coordinator.receive(["type": "success", "challenge": "c", "validate": "v", "seccode": "s"])
        try await Task.sleep(for: .milliseconds(30))
    }

    func testFailedCaptchaShowsRetryInLightAndDarkMode() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        defer { previous?.makeKey() }
        for scheme in [ColorScheme.light, .dark] {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: NavigationStack {
                GeetestView(gt: "fixture", challenge: "fixture", onFinish: { _ in })
                    .navigationTitle("安全验证")
            }.environment(\.colorScheme, scheme))
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await wait { self.descendants(host.view).contains { $0 is WKWebView } }
            let web = try XCTUnwrap(descendants(host.view).compactMap { $0 as? WKWebView }.first)
            // A new WKWebView initially reports a completed about:blank document.
            // Wait for our HTML's bootstrap before capturing the native error UI.
            try await wait {
                (try? await web.evaluateJavaScript("typeof window.neobiliCaptchaFailure === 'function' && document.readyState === 'complete'")) as? Bool == true
            }
            try await Task.sleep(for: .milliseconds(150))
            window.layoutIfNeeded()
            XCTAssertGreaterThan(web.bounds.height, 300)
            XCTAssertGreaterThan(web.bounds.width, 300)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "captcha-retry-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func makeWeb(coordinator: GeetestView.Coordinator) -> WKWebView {
        let web = coordinator.makeWebView()
        web.configuration.userContentController.addUserScript(WKUserScript(source: Self.sdkFixture,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        return web
    }
    private func release(_ web: WKWebView, _ coordinator: GeetestView.Coordinator) {
        coordinator.cancel()
        web.stopLoading()
        web.navigationDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: "geetest")
    }
    private func integer(_ web: WKWebView, _ script: String) async throws -> Int {
        let value = try await web.evaluateJavaScript(script)
        return try XCTUnwrap(value as? Int)
    }
    private func wait(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<200 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for local CAPTCHA fixture")
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    /// Exercises the GT3 contract without networking, phone numbers or real CAPTCHA results.
    private static let sdkFixture = #"""
    window.fixture = {verifications: 0, appendCalls: 0,
      result: {geetest_challenge: 'verified-challenge', geetest_validate: 'verified-value', geetest_seccode: 'verified-code'}};
    window.initGeetest = (options, handler) => {
      fixture.options = options;
      let isReady = false;
      const captcha = {
        onSuccess(fn) { fixture.success = fn; return this; },
        onClose(fn) { fixture.close = fn; return this; },
        onError(fn) { fixture.error = fn; return this; },
        onReady(fn) { fixture.ready = () => { isReady = true; fn(); }; return this; },
        appendTo() { fixture.appendCalls++; throw Error('appendTo is not valid in bind mode'); },
        verify() { if (!isReady) throw Error('SDK is not ready'); fixture.verifications++; },
        getValidate() { return fixture.result; }
      };
      handler(captcha);
    };
    """#
}
