import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class AccountRecoveryUIRepairTests: XCTestCase {
    func testMineSettingsAvailableDuringRestorationAsGuestAndAfterProfileFailure() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        defer { previous?.makeKey() }
        for state in ["restoring", "guest", "profile-failed"] {
            let suite = "account-recovery-ui.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let account = AccountStore(client: .init(credentials: {
                .init(hasCredentials: state == "profile-failed", accountID: state == "profile-failed" ? 42 : nil)
            }, save: { _, _ in XCTFail("UI must not save credentials") }, clear: { XCTFail("Browsing settings must not log out") },
            profile: { throw URLError(.notConnectedToInternet) }), defaults: defaults, monitorNetwork: false)
            if state != "restoring" { await account.restoreSessionIfNeeded() }
            for (appearance, scheme, size) in [("light", ColorScheme.light, DynamicTypeSize.large),
                                               ("dark-large", .dark, .accessibility3)] {
                let window = UIWindow(windowScene: scene)
                let host = UIHostingController(rootView: MineView().environment(account)
                    .environment(NowPlayingStore(defaults: defaults)).environment(ActionFeedback())
                    .defaultAppStorage(defaults)
                    .preferredColorScheme(scheme).environment(\.dynamicTypeSize, size))
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                try await Task.sleep(for: .milliseconds(300))
                window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "mine-\(state)-\(appearance)"; attachment.lifetime = .keepAlways
                add(attachment)
                let bars = descendants(window).compactMap { $0 as? UINavigationBar }
                let diagnostic = XCTAttachment(string: navigationDiagnostic(bars, in: window))
                diagnostic.name = "mine-\(state)-\(appearance)-navigation"; diagnostic.lifetime = .keepAlways
                add(diagnostic)
                let bar = try XCTUnwrap(bars.first {
                    $0.topItem?.title == "我的" && !$0.isHidden && $0.alpha > 0 &&
                    !$0.convert($0.bounds, to: window).intersection(window.bounds).isEmpty
                })
                XCTAssertFalse(bar.isHidden)
                XCTAssertGreaterThan(bar.alpha, 0)
                XCTAssertFalse(bar.convert(bar.bounds, to: window).intersection(window.bounds).isEmpty)
                // UIKit's leading groups replace, rather than mirror, the older
                // leftBarButtonItems array. SwiftUI uses this newer bridge.
                let groupedItems = bar.topItem?.leadingItemGroups.flatMap(\.barButtonItems) ?? []
                let leadingItems = groupedItems.isEmpty ? (bar.topItem?.leftBarButtonItems ?? []) : groupedItems
                let settingsItem = try XCTUnwrap(leadingItems.onlyElement,
                                                "Mine must expose its settings item for \(state)")
                XCTAssertTrue(settingsItem.isEnabled)
                XCTAssertFalse(host.view.hasAmbiguousLayout)
                XCTAssertTrue(activate(settingsItem, in: bar), "Visible settings item must be actionable")
                try await Task.sleep(for: .milliseconds(350))
                window.layoutIfNeeded()
                let presented = try XCTUnwrap(host.presentedViewController, "Settings action must present its service sheet")
                XCTAssertTrue(descendants(presented.view).compactMap { $0 as? UINavigationBar }
                    .contains { $0.topItem?.title == "系统设置" }, "Settings action must open the actual settings page")
                XCTAssertEqual(account.isLoggedIn, state == "profile-failed")
                await withCheckedContinuation { continuation in
                    host.dismiss(animated: false) { continuation.resume() }
                }
            }
        }
    }

    func testCancellingSharedLogoutConfirmationKeepsFailedProfileSession() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let suite = "account-logout-ui.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); previous?.makeKey() }
        var clears = 0
        let account = AccountStore(client: .init(credentials: { .init(hasCredentials: true, accountID: 42) },
            save: { _, _ in XCTFail() }, clear: { clears += 1 }, profile: { throw URLError(.notConnectedToInternet) }),
            defaults: defaults, monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        let session = account.sessionID
        let driver = ConfirmationDriver()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ConfirmationHarness(driver: driver).environment(account))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(200))
        driver.isPresented = true
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNotNil(host.presentedViewController, "Shared logout confirmation must actually be presented")
        XCTAssertEqual(clears, 0)
        driver.isPresented = false
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(clears, 0)
        XCTAssertEqual(account.sessionID, session)
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertEqual(account.accountID, 42)
    }

    func testRevokedAppAuthorizationIsVisibleOnEntryWithoutDeletingWebLogin() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let suite = "revoked-authorization-ui.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); previous?.makeKey() }
        for webExpired in [false, true] {
        var clears = 0
        let account = AccountStore(client: .init(credentials: {
            .init(hasCredentials: true, needsAppReauthorization: true, accountID: 42)
        }, save: { _, _ in XCTFail() }, clear: { clears += 1 },
        profile: {
            if webExpired { throw BiliAPIError.apiError(code: -101, message: "expired") }
            throw URLError(.notConnectedToInternet)
        }), defaults: defaults, monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Text("首页").modifier(AppAuthorizationRecovery(account: account))
            .environment(account).environment(ActionFeedback()))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(350))
        let alert = try XCTUnwrap(host.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, webExpired ? "登录已失效" : "App 登录授权已失效")
        XCTAssertEqual(Set(alert.actions.compactMap(\.title)), [webExpired ? "重新登录" : "重新授权", "稍后"])
        XCTAssertEqual(account.isLoggedIn, !webExpired)
        XCTAssertEqual(clears, webExpired ? 1 : 0)
        XCTAssertEqual(account.sessionExpired, webExpired)
        XCTAssertFalse(account.hasAppCredential)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func navigationDiagnostic(_ bars: [UINavigationBar], in window: UIWindow) -> String {
        bars.enumerated().map { index, bar in
            let item = bar.topItem
            let controls = descendants(bar).map { view in
                "\(type(of: view)) hidden=\(view.isHidden) alpha=\(view.alpha) frame=\(view.convert(view.bounds, to: window)) id=\(view.accessibilityIdentifier ?? "nil") label=\(view.accessibilityLabel ?? "nil")"
            }.joined(separator: "\n")
            @MainActor func items(_ entries: [UIBarButtonItem]) -> String {
                entries.map {
                    "title=\($0.title ?? "nil") label=\($0.accessibilityLabel ?? "nil") id=\($0.accessibilityIdentifier ?? "nil") enabled=\($0.isEnabled) action=\($0.action.map(NSStringFromSelector) ?? "nil") primary=\($0.primaryAction != nil) customView=\($0.customView.map { String(describing: type(of: $0)) } ?? "nil")"
                }.joined(separator: "\n")
            }
            return "bar \(index) title=\(item?.title ?? "nil") hidden=\(bar.isHidden) alpha=\(bar.alpha) frame=\(bar.convert(bar.bounds, to: window))\nleft:\n\(items(item?.leftBarButtonItems ?? []))\nleading groups:\n\(items(item?.leadingItemGroups.flatMap(\.barButtonItems) ?? []))\nviews:\n\(controls)"
        }.joined(separator: "\n\n")
    }

    /// SwiftUI may bridge toolbar buttons as bar items or virtual accessibility
    /// elements instead of UIViews with accessibilityIdentifier. Exercise the
    /// actual bridge's public activation and verify its presented destination.
    private func activate(_ item: UIBarButtonItem, in bar: UINavigationBar) -> Bool {
        var visited = Set<ObjectIdentifier>()
        var pending: [NSObject] = [item, bar]
        while let object = pending.popLast() {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let identifier = (object as? any UIAccessibilityIdentification)?.accessibilityIdentifier
            if identifier == "mine.settings" || object.accessibilityLabel == "系统设置" {
                if object.accessibilityActivate() { return true }
                if let control = object as? UIControl {
                    control.sendActions(for: .touchUpInside)
                    return true
                }
            }
            if let view = object as? UIView { pending.append(contentsOf: view.subviews) }
            if let item = object as? UIBarButtonItem, let view = item.customView { pending.append(view) }
            pending.append(contentsOf: (object.accessibilityElements ?? []).compactMap { $0 as? NSObject })
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<min(count, 1_024) {
                    if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        if item.accessibilityActivate() { return true }
        if let action = item.action {
            return UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil)
        }
        return false
    }
}

private extension Array {
    var onlyElement: Element? { count == 1 ? first : nil }
}

@MainActor
@Observable
private final class ConfirmationDriver {
    var isPresented = false
}

private struct ConfirmationHarness: View {
    @Bindable var driver: ConfirmationDriver
    var body: some View {
        Button("退出登录") { driver.isPresented = true }
            .accountLogoutConfirmation(isPresented: $driver.isPresented)
    }
}
