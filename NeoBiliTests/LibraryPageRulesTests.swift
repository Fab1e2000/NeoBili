import XCTest
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

    func testMixedFavoritePageUsesUnfilteredServerCount() {
        // A full page may contain courses or collections that are not shown as video rows.
        XCTAssertTrue(LibraryPageRules.hasMoreFavorites(rawCount: 20))
        XCTAssertFalse(LibraryPageRules.hasMoreFavorites(rawCount: 19))
        XCTAssertFalse(LibraryPageRules.hasMoreFavorites(rawCount: 0))
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
        client?.urlProtocol(self, didLoad: Data(#"{"code":0,"data":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
