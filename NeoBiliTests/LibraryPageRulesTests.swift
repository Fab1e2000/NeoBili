#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
import SwiftUI
import UIKit
import Synchronization
@testable import NeoBili

final class LibraryPageRulesTests: XCTestCase {
    private struct Item: Identifiable, Equatable { let id: Int; let title: String }

    func testOverlappingPagesAndInternalDuplicatesKeepFirstRecordInOrder() {
        let result = LibraryPageRules.unique([
            Item(id: 2, title: "existing"), Item(id: 3, title: "first"),
            Item(id: 3, title: "duplicate"), Item(id: 4, title: "last")
        ], excluding: [1, 2])
        XCTAssertEqual(result, [Item(id: 3, title: "first"), Item(id: 4, title: "last")])
    }

    func testHistoryStopsOnlyForMissingOrRepeatedCursor() {
        XCTAssertFalse(LibraryPageRules.advancesHistory(max: nil, viewAt: nil, fromMax: 1, fromViewAt: 2))
        XCTAssertFalse(LibraryPageRules.advancesHistory(max: 0, viewAt: 3, fromMax: 1, fromViewAt: 2))
        XCTAssertFalse(LibraryPageRules.advancesHistory(max: 1, viewAt: 2, fromMax: 1, fromViewAt: 2))
        XCTAssertTrue(LibraryPageRules.advancesHistory(max: 1, viewAt: 3, fromMax: 1, fromViewAt: 2))
        XCTAssertTrue(LibraryPageRules.advancesHistory(max: 2, viewAt: 2, fromMax: 1, fromViewAt: 2))
    }

    @MainActor
    func testFolderDeletionBindsConfirmationToOriginalAccountThroughRequestEncoding() async throws {
        for switchAccount in [false, true] {
            let suite = "neobili.folder-deletion.tests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let identity = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false, purgeCookies: {})
            await identity.saveLogin(.init(sessdata: "fixture-one", biliJct: "csrf-one", dedeUserID: "1"), accessKey: nil)
            let confirmedSession = identity.loginSessionID
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FolderDeletionProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            FolderDeletionProtocol.requests.withLock { $0 = [] }
            let client = APIClient(session: session, authentication: {
                // Switch after the endpoint read CSRF but before APIClient obtains cookies.
                if switchAccount {
                    await identity.saveLogin(.init(sessdata: "fixture-two", biliJct: "csrf-two", dedeUserID: "2"), accessKey: nil)
                }
                return await identity.authenticatedRequestSnapshot()
            })
            do {
                try await BiliAPI.deleteFavoriteFolders(folderIDs: [11, 22], expectedSessionID: confirmedSession,
                                                       client: client, identity: identity)
                XCTAssertFalse(switchAccount, "换账号后不能发送旧确认操作")
            } catch {
                XCTAssertTrue(switchAccount)
                XCTAssertTrue(error.isCancellation)
            }
            let requests = FolderDeletionProtocol.requests.withLock { $0 }
            if switchAccount {
                XCTAssertTrue(requests.isEmpty)
            } else {
                let request = try XCTUnwrap(requests.first)
                XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(request.url?.path, "/x/v3/fav/folder/del")
                let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(query?.first { $0.name == "media_ids" }?.value, "11,22")
                XCTAssertEqual(query?.first { $0.name == "csrf" }?.value, "csrf-one")
            }
        }
    }

    func testFavoriteFolderDecodesOptionalCover() throws {
        let withCover = try JSONDecoder().decode(
            FavFolder.self,
            from: Data(#"{"id":1,"title":"山野","media_count":2,"attr":2,"cover":"//i0.hdslb.com/a.jpg"}"#.utf8))
        XCTAssertEqual(withCover.secureCoverURL, URL(string: "https://i0.hdslb.com/a.jpg"))
        let withoutCover = try JSONDecoder().decode(
            FavFolder.self,
            from: Data(#"{"id":1,"title":"默认","media_count":0}"#.utf8))
        XCTAssertNil(withoutCover.cover)
        XCTAssertNil(withoutCover.secureCoverURL)
    }

    func testDefaultFolderIsMarkedByAttributeBit() {
        XCTAssertTrue(FavFolder(id: 1, title: "默认", mediaCount: 0, attr: 0).isDefaultFolder)
        XCTAssertTrue(FavFolder(id: 2, title: "私密默认", mediaCount: 0, attr: 1).isDefaultFolder)
        XCTAssertFalse(FavFolder(id: 3, title: "自建", mediaCount: 0, attr: 2).isDefaultFolder)
        XCTAssertFalse(FavFolder(id: 4, title: "缺标记", mediaCount: 0).isDefaultFolder)
        XCTAssertFalse(FavFolder(id: 1, title: "默认", mediaCount: 0, attr: 0).isPrivate)
        XCTAssertTrue(FavFolder(id: 2, title: "私密默认", mediaCount: 0, attr: 1).isPrivate)
        XCTAssertFalse(FavFolder(id: 3, title: "公开自建", mediaCount: 0, attr: 2).isPrivate)
        XCTAssertTrue(FavFolder(id: 5, title: "私密自建", mediaCount: 0, attr: 3).isPrivate)
        XCTAssertFalse(FavFolder(id: 4, title: "缺标记", mediaCount: 0).isPrivate)
    }

    @MainActor
    func testEditFavoriteFolderSendsMediaIDTitleIntroPrivacyCoverAndCSRF() async throws {
        let suite = "neobili.folder-update.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false, purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture-one", biliJct: "csrf-one", dedeUserID: "1"), accessKey: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FolderDeletionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        FolderDeletionProtocol.requests.withLock { $0 = [] }
        let client = APIClient(session: session, authentication: { await identity.authenticatedRequestSnapshot() })

        let updated = try await BiliAPI.editFavoriteFolder(
            folderID: 9, title: "新名字", intro: "更新简介", isPublic: false, cover: "https://i0.hdslb.com/a.jpg",
            expectedSessionID: identity.loginSessionID, client: client, identity: identity
        )
        XCTAssertEqual(updated.id, 9)
        XCTAssertEqual(updated.title, "新名字")
        XCTAssertEqual(updated.intro, "更新简介")
        XCTAssertTrue(updated.isPrivate)

        let requests = FolderDeletionProtocol.requests.withLock { $0 }
        let edit = try XCTUnwrap(requests.first)
        let query = URLComponents(url: try XCTUnwrap(edit.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(edit.url?.path, "/x/v3/fav/folder/edit")
        XCTAssertEqual(query?.first { $0.name == "media_id" }?.value, "9")
        XCTAssertEqual(query?.first { $0.name == "title" }?.value, "新名字")
        XCTAssertEqual(query?.first { $0.name == "intro" }?.value, "更新简介")
        XCTAssertEqual(query?.first { $0.name == "privacy" }?.value, "1")
        XCTAssertEqual(query?.first { $0.name == "cover" }?.value, "https://i0.hdslb.com/a.jpg")
        XCTAssertEqual(query?.first { $0.name == "csrf" }?.value, "csrf-one")
    }

    @MainActor
    func testCreateFavoriteFolderSendsTitlePrivacyAndCSRF() async throws {
        let suite = "neobili.folder-edit.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false, purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture-one", biliJct: "csrf-one", dedeUserID: "1"), accessKey: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FolderDeletionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        FolderDeletionProtocol.requests.withLock { $0 = [] }
        let client = APIClient(session: session, authentication: { await identity.authenticatedRequestSnapshot() })

        let created = try await BiliAPI.addFavoriteFolder(
            title: "山野", intro: "周末", isPublic: false, expectedSessionID: identity.loginSessionID,
            client: client, identity: identity)
        XCTAssertEqual(created.id, 9)
        XCTAssertEqual(created.title, "新收藏")
        XCTAssertFalse(created.isDefaultFolder)

        let requests = FolderDeletionProtocol.requests.withLock { $0 }
        let add = try XCTUnwrap(requests.first)
        let addQuery = URLComponents(url: try XCTUnwrap(add.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(add.url?.path, "/x/v3/fav/folder/add")
        XCTAssertEqual(addQuery?.first { $0.name == "title" }?.value, "山野")
        XCTAssertEqual(addQuery?.first { $0.name == "intro" }?.value, "周末")
        XCTAssertEqual(addQuery?.first { $0.name == "privacy" }?.value, "1")
        XCTAssertEqual(addQuery?.first { $0.name == "csrf" }?.value, "csrf-one")
    }

    func testMixedFavoritePageUsesUnfilteredServerCount() {
        // A full page may contain courses or collections that are not shown as video rows.
        XCTAssertTrue(LibraryPageRules.hasMoreFavorites(rawCount: 20))
        XCTAssertFalse(LibraryPageRules.hasMoreFavorites(rawCount: 19))
        XCTAssertFalse(LibraryPageRules.hasMoreFavorites(rawCount: 0))
    }

    @MainActor
    func testFavoritesWindowRendersPlainListWithInlineCreateRowAndNoToolbarAccessory() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }

        let session = UUID()
        var services = ApplicationServices(session: .init(currentID: { session }, homeAccount: { .init(accountID: 42, hasAppCredential: false) }))
        services.library.favoriteFoldersOperation = { _, _ in
            [
                FavFolder(id: 1, title: "默认收藏夹", mediaCount: 12, attr: 0),
                FavFolder(id: 2, title: "技术分享", mediaCount: 8, attr: 2),
                FavFolder(id: 3, title: "私密清单", mediaCount: 3, attr: 3)
            ]
        }

        let suite = "neobili.favorites.plain.\(UUID())"
        let accountDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { accountDefaults.removePersistentDomain(forName: suite) }
        let client = AccountSessionClient(
            credentials: { .init(hasCredentials: true, accountID: 42) },
            save: { _, _ in },
            clear: {},
            profile: { throw URLError(.notConnectedToInternet) }
        )
        let account = AccountStore(client: client, defaults: accountDefaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        let feedback = ActionFeedback()
        let accessory = RootToolbarAccessory()

        let host = UIHostingController(
            rootView: NavigationStack { FavoritesView(isTabRoot: true) }
                .environment(\.applicationServices, services)
                .environment(account)
                .environment(feedback)
                .environment(accessory)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await TestWindowTransition.wait(for: host)

        let collectionView = try await waitForCollectionView(in: host.view) { view in
            view.numberOfSections >= 1 && view.numberOfItems(inSection: 0) == 4
        }
        collectionView.layoutIfNeeded()

        XCTAssertNil(accessory.button, "收藏页不应在顶部系统工具栏注入新建按钮")
        XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 4, "应包含 3 个收藏夹与 1 行页面内新建入口")
    }

    @MainActor
    private func waitForCollectionView(
        in root: UIView,
        matching predicate: (UICollectionView) -> Bool
    ) async throws -> UICollectionView {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let found = findCollectionView(in: root), predicate(found) {
                return found
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("未能等到收藏夹原生列表完成布局")
        throw CancellationError()
    }

    @MainActor
    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for child in view.subviews {
            if let found = findCollectionView(in: child) { return found }
        }
        return nil
    }
}

private final class FolderDeletionProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body: Data
        if request.url?.path.contains("folder/add") == true {
            body = Data(#"{"code":0,"data":{"id":9,"title":"新收藏","media_count":0,"attr":2}}"#.utf8)
        } else if request.url?.path.contains("folder/edit") == true {
            body = Data(#"{"code":0,"data":{"id":9,"title":"新名字","intro":"更新简介","media_count":3,"attr":3}}"#.utf8)
        } else {
            body = Data(#"{"code":0,"data":{}}"#.utf8)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
