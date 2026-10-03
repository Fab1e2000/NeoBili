import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class RecommendationAuthorizationLayoutTests: XCTestCase {
    func testAuthorizationSettingsInForegroundAcrossAppearanceTypeSizeAndOrientation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let account = AccountStore(client: .init(credentials: { .init(hasCredentials: true, accountID: 42) }, save: { _, _ in }, clear: {}, profile: { throw URLError(.notConnectedToInternet) }), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        for (name, style, size, frame) in [
            ("light-portrait", UIUserInterfaceStyle.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 390, height: 844)),
            ("dark-accessibility-landscape", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 844, height: 390))
        ] {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: NavigationStack { RecommendationSettingsView() }.environment(account).environment(\.dynamicTypeSize, size))
            window.frame = frame
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            window.layoutIfNeeded()
            XCTAssertTrue(window.isKeyWindow)
            XCTAssertGreaterThan(host.view.bounds.width, 0)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let data = image.pngData() {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("neobili-auth-\(name).png")
                try data.write(to: url)
            }
            window.isHidden = true
            window.rootViewController = nil
        }
        previous?.makeKey()
    }
    func testSMSLoginAcrossAppearanceTypeSizeAndOrientation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let account = AccountStore(client: .init(credentials: { .init(hasCredentials: false, accountID: nil) }, save: { _, _ in }, clear: {}, profile: { throw URLError(.notConnectedToInternet) }), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        for (name, style, size, frame) in [
            ("light-portrait", UIUserInterfaceStyle.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 390, height: 844)),
            ("dark-accessibility-landscape", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 844, height: 390))
        ] {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: SMSLoginSheet().environment(account).environment(\.dynamicTypeSize, size))
            window.frame = frame; window.overrideUserInterfaceStyle = style; window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "sms-" + name; attachment.lifetime = .keepAlways; add(attachment)
            if let data = image.pngData() { try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("neobili-sms-\(name).png")) }
            XCTAssertTrue(window.isKeyWindow); XCTAssertGreaterThan(host.view.bounds.width, 0)
            window.isHidden = true; window.rootViewController = nil
        }
        previous?.makeKey()
    }
    func testDiagnosticExportSettingsAcrossAppearanceTypeSizeAndOrientation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let account = AccountStore(client: .init(credentials: { .init(hasCredentials: true, accountID: 42) }, save: { _, _ in }, clear: {}, profile: { throw URLError(.notConnectedToInternet) }), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        for (name, style, size, frame) in [
            ("light-portrait", UIUserInterfaceStyle.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 390, height: 844)),
            ("dark-accessibility-landscape", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 844, height: 390))
        ] {
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: NavigationStack { RecommendationDiagnosticsView() }.environment(account).environment(\.dynamicTypeSize, size))
            window.frame = frame
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            window.layoutIfNeeded()
            XCTAssertTrue(window.isKeyWindow)
            XCTAssertGreaterThan(host.view.bounds.width, 0)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "diagnostics-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let data = image.pngData() {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("neobili-diagnostics-\(name).png")
                try data.write(to: url)
            }
            window.isHidden = true
            window.rootViewController = nil
        }
        previous?.makeKey()
    }
}
