import XCTest
import SwiftUI
import UIKit
@testable import NeoBili
@testable import NeoBiliDomain
@testable import NeoBiliData

final class AppUpdateTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "com.elsterlee.NeoBili.tests.appUpdate.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoBiliUpdateTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - AppVersion

    func testAppVersionComparisonAndNormalization() {
        XCTAssertLessThan(AppVersion("1.3.5")!, AppVersion("1.3.6")!)
        XCTAssertLessThan(AppVersion("1.3.9")!, AppVersion("1.3.10")!)
        XCTAssertLessThan(AppVersion("1.3.5")!, AppVersion("2.0")!)
        XCTAssertEqual(AppVersion("1.3"), AppVersion("1.3.0"))
        XCTAssertEqual(AppVersion("v1.3.5"), AppVersion("1.3.5"))
        XCTAssertEqual(AppVersion("V1.3.5-beta.1"), AppVersion("1.3.5"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1..2"))
    }

    // MARK: - AppUpdateSourceParser

    func testParserDecodesValidSideStoreSource() throws {
        let json = """
        {
          "name": "NeoBili",
          "sourceURL": "https://n015.top/neobili/apps.json",
          "apps": [
            {
              "name": "NeoBili",
              "bundleIdentifier": "com.elsterlee.NeoBili",
              "version": "1.3.6",
              "versionDate": "2026-11-25T08:00:00Z",
              "versionDescription": "新增应用内更新检查。",
              "downloadURL": "https://n015.top/neobili/NeoBili-v1.3.6-unsigned.ipa",
              "size": 134554988
            }
          ]
        }
        """
        let release = try AppUpdateSourceParser.parse(
            data: Data(json.utf8),
            bundleIdentifier: "com.elsterlee.NeoBili.regression"
        )
        XCTAssertEqual(release.version, "1.3.6")
        XCTAssertEqual(release.parsedVersion, AppVersion("1.3.6"))
        XCTAssertEqual(release.releaseNotes, "新增应用内更新检查。")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://n015.top/neobili/NeoBili-v1.3.6-unsigned.ipa")
        XCTAssertEqual(release.packageSize, 134554988)
        XCTAssertEqual(release.sourceURL.absoluteString, "https://n015.top/neobili/apps.json")
        XCTAssertNotNil(release.releaseDate)
    }

    func testParserRejectsInvalidFeedMissingAppAndBadScheme() {
        XCTAssertThrowsError(try AppUpdateSourceParser.parse(data: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidFeed)
        }

        let wrongApp = """
        {"apps":[{"bundleIdentifier":"com.example.Other","version":"1.0.0","downloadURL":"https://example.com/a.ipa"}]}
        """
        XCTAssertThrowsError(try AppUpdateSourceParser.parse(data: Data(wrongApp.utf8))) { error in
            XCTAssertEqual(error as? AppUpdateError, .appNotFound)
        }

        let badScheme = """
        {"apps":[{"bundleIdentifier":"com.elsterlee.NeoBili","version":"1.4.0","downloadURL":"file:///tmp/app.ipa"}]}
        """
        XCTAssertThrowsError(try AppUpdateSourceParser.parse(data: Data(badScheme.utf8))) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidDownloadURL)
        }
    }

    // MARK: - LiveAppUpdateService

    func testLiveServiceFetchesDownloadsAndCleansUp() async throws {
        let sourceURL = URL(string: "https://mock.neobili.test/apps.json")!
        let ipaURL = URL(string: "https://mock.neobili.test/NeoBili-v1.4.0-unsigned.ipa")!
        let feedJSON = """
        {
          "sourceURL": "\(sourceURL.absoluteString)",
          "apps": [{
            "bundleIdentifier": "com.elsterlee.NeoBili",
            "version": "1.4.0",
            "versionDescription": "测试更新",
            "downloadURL": "\(ipaURL.absoluteString)",
            "size": 1024
          }]
        }
        """
        let ipaPayload = Data(repeating: 0x50, count: 1024)

        let session = makeMockSession { request in
            if request.url == sourceURL {
                let response = HTTPURLResponse(url: sourceURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(feedJSON.utf8))
            }
            if request.url == ipaURL {
                let response = HTTPURLResponse(
                    url: ipaURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "\(ipaPayload.count)"]
                )!
                return (response, ipaPayload)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = AppUpdateService.live(
            session: session,
            sourceURL: sourceURL,
            cacheDirectory: tempDirectory
        )

        let release = try await service.fetchLatestRelease()
        XCTAssertEqual(release.version, "1.4.0")

        var downloadedURL: URL?
        for try await event in service.downloadPackage(release.downloadURL, release.version) {
            if case .completed(let url) = event {
                downloadedURL = url
            }
        }
        let fileURL = try XCTUnwrap(downloadedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), ipaPayload)

        service.cleanupPackages()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - AppUpdateStore

    @MainActor
    func testAutoCheckRespectsToggleAnd24HourThrottle() async {
        var fetchCount = 0
        var currentNow = Date(timeIntervalSince1970: 1_760_000_000)
        let release = makeRelease(version: "1.3.6")

        let service = AppUpdateService(
            fetchLatestRelease: {
                fetchCount += 1
                return release
            }
        )

        let store = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            now: { currentNow },
            canOpenURL: { _ in false },
            openURL: { _ in true }
        )

        // First auto check runs and shows badge.
        await store.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertTrue(store.showsUpdateBadge)
        XCTAssertEqual(store.availableRelease, release)

        // Within 24h: throttled.
        currentNow = currentNow.addingTimeInterval(3600)
        await store.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetchCount, 1)

        // After 24h: runs again.
        currentNow = currentNow.addingTimeInterval(AppUpdateConstants.autoCheckInterval)
        await store.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetchCount, 2)

        // Disable auto check: skipped even after another 24h.
        store.autoCheckEnabled = false
        currentNow = currentNow.addingTimeInterval(AppUpdateConstants.autoCheckInterval + 60)
        await store.checkAutomaticallyIfNeeded()
        XCTAssertEqual(fetchCount, 2)
    }

    @MainActor
    func testAutoCheckSwallowsErrorsWhileManualCheckSurfacesErrors() async {
        let service = AppUpdateService(
            fetchLatestRelease: { throw AppUpdateError.networkFailed("offline") }
        )
        let store = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            canOpenURL: { _ in false },
            openURL: { _ in true }
        )

        await store.checkAutomaticallyIfNeeded()
        XCTAssertEqual(store.checkState, .idle)
        XCTAssertFalse(store.showsUpdateBadge)

        await store.checkManually()
        XCTAssertEqual(store.checkState, .failed("offline"))
    }

    @MainActor
    func testIgnoreVersionClearsBadgeUntilNewerReleaseArrives() async {
        var remoteRelease = makeRelease(version: "1.3.6")
        let service = AppUpdateService(fetchLatestRelease: { remoteRelease })
        let store = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            canOpenURL: { _ in false },
            openURL: { _ in true }
        )

        await store.checkManually()
        XCTAssertTrue(store.showsUpdateBadge)

        store.ignoreAvailableVersion()
        XCTAssertFalse(store.showsUpdateBadge)
        XCTAssertTrue(store.isAvailableVersionIgnored)
        XCTAssertEqual(store.availableRelease?.version, "1.3.6")

        // Checking the same version keeps it ignored.
        await store.checkManually()
        XCTAssertFalse(store.showsUpdateBadge)

        // Newer version clears ignore and shows badge again.
        remoteRelease = makeRelease(version: "1.3.7")
        await store.checkManually()
        XCTAssertTrue(store.showsUpdateBadge)
        XCTAssertFalse(store.isAvailableVersionIgnored)
    }

    @MainActor
    func testInstallerDetectionAndURLHandoff() async {
        var openedURLs: [URL] = []
        let release = makeRelease(version: "1.3.6")
        let service = AppUpdateService(fetchLatestRelease: { release })

        let sideStoreOnly = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            canOpenURL: { $0.scheme == "sidestore" },
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        XCTAssertEqual(sideStoreOnly.installedInstaller, .sideStore)
        await sideStoreOnly.checkManually()
        let openedSideStoreSource = await sideStoreOnly.openInInstaller(.sideStore)
        XCTAssertTrue(openedSideStoreSource)
        XCTAssertEqual(
            openedURLs.last?.absoluteString,
            AppUpdateConstants.sideStoreSourceURL(for: release.sourceURL).absoluteString
        )

        let openedSideStoreGitHub = await sideStoreOnly.openInInstaller(.sideStore, source: .github)
        XCTAssertTrue(openedSideStoreGitHub)
        XCTAssertEqual(
            openedURLs.last?.absoluteString,
            AppUpdateConstants.sideStoreInstallURL(for: release.downloadURL(for: .github)).absoluteString
        )
        XCTAssertEqual(
            release.downloadURL(for: .github).absoluteString,
            "https://github.com/Fab1e2000/NeoBili/releases/download/v1.3.6/NeoBili-v1.3.6-unsigned.ipa"
        )
        XCTAssertEqual(
            release.downloadURL(for: .mirror).absoluteString,
            "https://n015.top/neobili/NeoBili-v1.3.6-unsigned.ipa"
        )

        let altStoreOnly = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            canOpenURL: { $0.scheme == "altstore" },
            openURL: { url in
                openedURLs.append(url)
                return true
            }
        )
        XCTAssertEqual(altStoreOnly.installedInstaller, .altStore)
        _ = await altStoreOnly.openGitHubReleases()
        XCTAssertEqual(openedURLs.last, AppUpdateConstants.githubReleasesURL)
    }

    @MainActor
    func testDownloadProgressShareAndCleanupLifecycle() async {
        let release = makeRelease(version: "1.3.6")
        let expectedFile = tempDirectory.appendingPathComponent("NeoBili-v1.3.6-unsigned.ipa")
        var cleanupCount = 0
        var requestedDownloadURLs: [URL] = []

        let service = AppUpdateService(
            fetchLatestRelease: { release },
            downloadPackage: { url, _ in
                requestedDownloadURLs.append(url)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.progress(fraction: 0.5, completedBytes: 50, totalBytes: 100))
                    continuation.yield(.completed(expectedFile))
                    continuation.finish()
                }
            },
            cleanupPackages: {
                cleanupCount += 1
            }
        )

        let store = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            canOpenURL: { _ in false },
            openURL: { _ in true }
        )

        await store.checkManually()
        store.startDownload()

        let deadline = Date().addingTimeInterval(2)
        while store.downloadState != .readyToShare(expectedFile) && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.downloadState, .readyToShare(expectedFile))
        XCTAssertEqual(store.activeDownloadSource, .github)
        XCTAssertEqual(requestedDownloadURLs.last, release.downloadURL(for: .github))

        store.finishSharingPackage()
        XCTAssertEqual(store.downloadState, .idle)
        XCTAssertEqual(cleanupCount, 1)

        store.startDownload(source: .mirror)
        let mirrorDeadline = Date().addingTimeInterval(2)
        while store.downloadState != .readyToShare(expectedFile) && Date() < mirrorDeadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.activeDownloadSource, .mirror)
        XCTAssertEqual(requestedDownloadURLs.last, release.downloadURL(for: .mirror))
    }

    @MainActor
    func testAboutAndUpdateSheetRenderInLightAndDarkModes() async {
        let release = makeRelease(version: "1.3.6")
        let service = AppUpdateService(fetchLatestRelease: { release })
        let store = AppUpdateStore(
            service: service,
            defaults: defaults,
            currentVersionProvider: { "1.3.5" },
            canOpenURL: { $0.scheme == "sidestore" },
            openURL: { _ in true }
        )
        await store.checkManually()

        for style in [UIUserInterfaceStyle.light, .dark] {
            let aboutHost = UIHostingController(
                rootView: NavigationStack { AboutSettingsView().environment(store) }
            )
            aboutHost.overrideUserInterfaceStyle = style
            aboutHost.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            aboutHost.view.layoutIfNeeded()
            XCTAssertGreaterThan(aboutHost.view.bounds.height, 0)

            let sheetHost = UIHostingController(rootView: AppUpdateSheet(store: store))
            sheetHost.overrideUserInterfaceStyle = style
            sheetHost.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            sheetHost.view.layoutIfNeeded()
            XCTAssertGreaterThan(sheetHost.view.bounds.height, 0)
        }
    }

    // MARK: - Helpers

    private func makeRelease(version: String) -> AppUpdateRelease {
        AppUpdateRelease(
            version: version,
            parsedVersion: AppVersion(version)!,
            releaseDate: Date(timeIntervalSince1970: 1_760_000_000),
            releaseNotes: "更新日志内容",
            downloadURL: URL(string: "https://n015.top/neobili/NeoBili-v\(version)-unsigned.ipa")!,
            packageSize: 134_554_988
        )
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockUpdateURLProtocol.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockUpdateURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class MockUpdateURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ newHandler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let currentHandler = Self.handler
        Self.lock.unlock()

        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try currentHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
