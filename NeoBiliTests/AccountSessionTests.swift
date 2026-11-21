#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

final class AccountSessionTests: XCTestCase {
    @MainActor
    func testLegacyHDTokenIsExcludedAndIPhoneTokenSurvivesRelaunch() async {
        let suite = "neobili.migration.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = CredentialStorage.memory()
        storage.write("cookie", "neobili.sessdata")
        storage.write("csrf", "neobili.bili_jct")
        storage.write("42", "neobili.dedeuserid")
        storage.write("legacy-hd-token", "neobili.access_key")
        func identity() -> DeviceIdentity {
            DeviceIdentity(defaults: defaults, credentials: storage, allowsNetwork: false, purgeCookies: {})
        }
        let old = identity()
        let snapshot = await old.accountSnapshot()
        XCTAssertTrue(snapshot.hasCredentials)
        XCTAssertTrue(snapshot.needsAppCredentialMigration)
        XCTAssertFalse(snapshot.hasAppCredential)
        let request = await old.appAccount()
        XCTAssertNil(request.accessKey)
        let saved = await old.setAccessKey("ios-token", forAccount: "42")
        XCTAssertTrue(saved)
        let restored = identity()
        let current = await restored.appAccount()
        XCTAssertEqual(current.accessKey, "ios-token")
        let migrated = await restored.accountSnapshot()
        XCTAssertFalse(migrated.needsAppCredentialMigration)
        await restored.clearLoginCookies()
        XCTAssertNil(storage.read("neobili.access_key.client"))
        XCTAssertNil(storage.read("neobili.access_key"))
    }

    private func isolatedIdentity() -> DeviceIdentity {
        let suite = "neobili.identity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return DeviceIdentity(defaults: defaults, credentials: .memory(),
                              allowsNetwork: false, purgeCookies: {})
    }

    func testAndroidCredentialIsPreservedButExcludedUntilIPhoneExchangeSucceeds() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let storage = CredentialStorage.memory()
        storage.write("s", "neobili.sessdata")
        storage.write("j", "neobili.bili_jct")
        storage.write("42", "neobili.dedeuserid")
        storage.write("old-android-token", "neobili.access_key")
        storage.write("android-phone-v1", "neobili.access_key.client")
        let identity = DeviceIdentity(defaults: defaults, credentials: storage, allowsNetwork: false, purgeCookies: {})
        let snapshot = await identity.accountSnapshot()
        XCTAssertTrue(snapshot.hasCredentials)
        XCTAssertTrue(snapshot.needsAppCredentialMigration)
        let account = await identity.appAccount()
        XCTAssertNil(account.accessKey)
        XCTAssertEqual(storage.read("neobili.access_key"), "old-android-token", "Failed migration must not delete old credentials")
        let session = identity.loginSessionID
        let saved = await identity.setAccessKey("new-ios-token", forAccount: "42", expectedSessionID: session)
        XCTAssertTrue(saved)
        XCTAssertEqual(storage.read("neobili.access_key.client"), "ios-27eb53fc-v1")
        XCTAssertEqual(storage.read("neobili.sessdata"), "s")
    }

    func testLateCredentialExchangeCannotOverwriteReloginToSameAccount() async {
        let identity = isolatedIdentity()
        await identity.setLoginCookies(sessdata: "old", biliJct: "j", dedeUserID: "42")
        let oldSession = identity.loginSessionID
        await identity.setLoginCookies(sessdata: "new", biliJct: "j2", dedeUserID: "42")
        await identity.setAccessKey("new-token")
        let saved = await identity.setAccessKey("late-token", forAccount: "42", expectedSessionID: oldSession)
        XCTAssertFalse(saved)
        let account = await identity.appAccount()
        XCTAssertEqual(account.accessKey, "new-token")
    }

    // MARK: - 登录 Cookie 拼接

    @MainActor
    func testCookieHeaderCarriesLoginCredentials() async {
        let identity = isolatedIdentity()
        await identity.setLoginCookies(
            sessdata: "abc%2Cdef123",
            biliJct: "csrf456",
            dedeUserID: "10000"
        )

        let header = await identity.cookieHeader()
        XCTAssertTrue(header.contains("SESSDATA=abc%2Cdef123"), "SESSDATA 原样发送，不做二次转义")
        XCTAssertTrue(header.contains("bili_jct=csrf456"))
        XCTAssertTrue(header.contains("DedeUserID=10000"))
        let loggedIn = await identity.isLoggedIn
        XCTAssertTrue(loggedIn)
        let csrf = await identity.csrfToken
        XCTAssertEqual(csrf, "csrf456")
    }

    @MainActor
    func testClearingCookiesRemovesLoginState() async {
        let identity = isolatedIdentity()
        await identity.setLoginCookies(sessdata: "a", biliJct: "b", dedeUserID: "c")
        await identity.clearLoginCookies()

        let header = await identity.cookieHeader()
        XCTAssertFalse(header.contains("SESSDATA="))
        let loggedIn = await identity.isLoggedIn
        XCTAssertFalse(loggedIn)
    }

    // MARK: - 历史条目

    func testHistoryItemFiltersNonArchiveAndBuildsKid() throws {
        let json = """
        [
          {"title":"某个视频","long_title":"","cover":"http://i0.hdslb.com/x.jpg",
           "duration":300,"author_name":"UP主","view_at":1700000000,"progress":95,
           "history":{"business":"archive","oid":12345,"bvid":"BV1xx","cid":777,"type":3}},
          {"title":"某场直播","long_title":"","cover":"","duration":0,
           "history":{"business":"live","oid":999,"bvid":"","cid":0,"type":9}}
        ]
        """
        let items = try JSONDecoder().decode([HistoryItem].self, from: Data(json.utf8))

        XCTAssertEqual(items.count, 2)
        let video = try XCTUnwrap(items.first)
        // 删除参数使用业务名作为前缀，例如 archive_12345。
        XCTAssertEqual(video.kidParam, "archive_12345")
        XCTAssertTrue(video.isVideo)
        XCTAssertEqual(video.asVideoSummary?.cid, 777)
        XCTAssertEqual(video.asVideoSummary?.bvid, "BV1xx")

        let live = try XCTUnwrap(items.last)
        XCTAssertFalse(live.isVideo)
        XCTAssertNil(live.asVideoSummary)
    }

    // MARK: - 收藏条目

    func testFavMediaOnlyMapsVideoEntries() throws {
        let json = """
        [{"id":42,"bvid":"BV1fav","type":2,"title":"收藏的视频","cover":"http://i0.hdslb.com/y.jpg",
          "duration":120,"cnt_info":{"play":1000,"danmaku":10},"upper":{"mid":7,"name":"UP","face":""}},
         {"id":43,"bvid":"","type":24,"title":"某课程","cover":"","duration":0}]
        """
        let medias = try JSONDecoder().decode([FavMedia].self, from: Data(json.utf8))

        let video = try XCTUnwrap(medias.first)
        XCTAssertTrue(video.isVideo)
        let summary = try XCTUnwrap(video.asVideoSummary)
        XCTAssertEqual(summary.bvid, "BV1fav")
        // 收藏接口不带 cid；调用方必须把 0 视为「无 cid」传 nil。
        XCTAssertEqual(summary.cid, 0)

        let course = try XCTUnwrap(medias.last)
        XCTAssertFalse(course.isVideo)
        XCTAssertNil(course.asVideoSummary)
    }

    // MARK: - 收藏夹 / 历史响应解包

    func testFavFolderListUnwrapsDataList() throws {
        // list-all 的 data 是 {"count", "list"}，不是裸数组。
        let json = """
        {"count":1,"list":[{"id":123456,"fid":0,"mid":7,"title":"默认收藏夹","media_count":3}]}
        """
        let payload = try JSONDecoder().decode(FavFolderList.self, from: Data(json.utf8))
        XCTAssertEqual(payload.list?.first?.id, 123456)
        XCTAssertEqual(payload.list?.first?.mediaCount, 3)
    }

    func testHistoryPageReadsListKey() throws {
        // 历史接口的条目在 data.list（文档写的 items 实际不返回）。
        let json = """
        {"cursor":{"max":-1,"view_at":1700000000,"ps":20},
         "list":[{"title":"某个视频","cover":"http://i0.hdslb.com/x.jpg","duration":300,
                  "author_name":"UP主","view_at":1700000000,"progress":95,"kid":12345,
                  "history":{"business":"archive","oid":12345,"bvid":"BV1xx","cid":777}}]}
        """
        let page = try JSONDecoder().decode(HistoryCursorPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.allItems.count, 1)
        XCTAssertEqual(page.allItems.first?.kidParam, "archive_12345", "条目自带的 kid 优先，前缀仍是业务名")
        XCTAssertEqual(page.cursor?.resolvedViewAt, 1700000000)
    }

    func testHistoryItemWithoutDirectKidFallsBackToOid() throws {
        let json = """
        {"title":"某个视频","history":{"business":"archive","oid":12345,"bvid":"BV1xx","cid":777}}
        """
        let item = try JSONDecoder().decode(HistoryItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.kidParam, "archive_12345")
    }

    // MARK: - 稍后再看

    func testWatchLaterItemDecodesOwnerKey() throws {
        // toview/web 变体的 UP 主信息在 `owner` 键（与视频详情一致），不在 `upper`。
        let json = """
        {"aid":99,"bvid":"BV1later","cid":55,"title":"稍后再看的视频","pic":"http://i0.hdslb.com/z.jpg",
         "duration":180,"add_at":1700000000,
         "owner":{"mid":7,"name":"UP主","face":"http://i0.hdslb.com/face.jpg"}}
        """
        let item = try JSONDecoder().decode(WatchLaterItem.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(item.asVideoSummary, "有 owner 时必须能映射出视频卡片")
        XCTAssertEqual(summary.bvid, "BV1later")
        XCTAssertEqual(summary.owner.name, "UP主")

        // 老接口的 upper 键也要兼容。
        let legacy = """
        {"aid":100,"bvid":"BV1old","cid":56,"title":"老结构","upper":{"mid":8,"name":"老UP","face":""}}
        """
        let oldItem = try JSONDecoder().decode(WatchLaterItem.self, from: Data(legacy.utf8))
        XCTAssertNotNil(oldItem.asVideoSummary)
    }

    // MARK: - 展示工具
}

@MainActor
extension AccountSessionTests {
    func testOfflineSessionKeepsCredentialsAndRecoversOnRetry() async throws {
        let defaults = try temporaryDefaults()
        var online = false
        let payload = try profile()
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: {},
            profile: { if !online { throw URLError(.notConnectedToInternet) }; return payload }
        )
        let account = AccountStore(client: client, defaults: defaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertFalse(account.isRestoringSession)
        XCTAssertNotNil(account.sessionError)
        online = true
        await account.retrySessionIfNeeded()
        XCTAssertEqual(account.profile?.mid, 42)
        XCTAssertNil(account.sessionError)
        online = false
        let restored = AccountStore(client: client, defaults: defaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        await restored.restoreSessionIfNeeded()
        XCTAssertEqual(restored.profile?.mid, 42, "同账号可使用缓存资料离线启动")
    }

    func testCookieOnlyLoginAndRestoreDoNotStartHiddenQRCodeExchange() async throws {
        var exchanges = 0
        let payload = try profile()
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: {}, profile: { payload },
            exchangeAppCredential: { exchanges += 1 }
        )
        let restored = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await restored.restoreSessionIfNeeded()
        XCTAssertEqual(exchanges, 0, "已登录的账号不在后台悄悄换取，由用户在设置里确认")
        XCTAssertFalse(restored.hasAppCredential)

        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.completeLogin(LoginModels.LoginCookies(sessdata: "s", biliJct: "j", dedeUserID: "42"))
        for _ in 0..<20 where !account.hasAppCredential { await Task.yield() }
        XCTAssertEqual(exchanges, 0)
        XCTAssertFalse(account.hasAppCredential)
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertEqual(account.accountID, 42)
    }

    func testRestorePreservesLegacyLoginUntilSMSAuthorization() async throws {
        var exchanges = 0
        let payload = try profile()
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, needsAppCredentialMigration: true, accountID: 42) },
            save: { _, _ in }, clear: { XCTFail("Migration must preserve cookies") }, profile: { payload },
            exchangeAppCredential: { exchanges += 1 }
        )
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        for _ in 0..<20 where !account.hasAppCredential { await Task.yield() }
        XCTAssertEqual(exchanges, 0)
        XCTAssertFalse(account.hasAppCredential)
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertEqual(account.accountID, 42)
    }

    func testFailedAppMigrationIsVisibleAndScanAuthorizationPreservesAccount() async throws {
        let payload = try profile()
        var saved = 0
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in XCTFail("App authorization must not replace web login") },
            clear: { XCTFail("App authorization must not log out") }, profile: { payload },
            exchangeAppCredential: { throw LoginModels.PassportError.rejected("账号未登录 (code -101)") },
            saveAppAuthorization: { key, mid in XCTAssertEqual(key, "fixture"); XCTAssertEqual(mid, 42); saved += 1 }
        )
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        let error = await account.ensureAppCredential()
        XCTAssertEqual(account.appCredentialError, error)
        XCTAssertNotNil(error)
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertFalse(account.hasAppCredential)
        let session = account.sessionID
        let cookies = LoginModels.LoginCookies(sessdata: "s", biliJct: "j", dedeUserID: "42")
        try await account.completeAppAuthorization(cookies, accessKey: "fixture", expectedSessionID: session)
        XCTAssertEqual(saved, 1)
        XCTAssertTrue(account.hasAppCredential)
        XCTAssertEqual(account.sessionID, session)
        XCTAssertNil(account.appCredentialError)
    }

    func testAppScanRejectsDifferentAccountMissingTokenAndStaleSessionBeforeSaving() async throws {
        let payload = try profile()
        var saves = 0
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: {}, profile: { payload }, saveAppAuthorization: { _, _ in saves += 1 })
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        for (mid, key, session): (String, String?, UUID) in [("43", "fixture", account.sessionID), ("42", nil, account.sessionID), ("42", "fixture", UUID())] {
            do {
                try await account.completeAppAuthorization(.init(sessdata: "s", biliJct: "j", dedeUserID: mid), accessKey: key, expectedSessionID: session)
                XCTFail("Invalid authorization must fail")
            } catch {}
        }
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertFalse(account.hasAppCredential)
    }

    func testLateProfileResponseCannotLogBackInAfterLogout() async throws {
        let pending = PendingModelResult<AccountProfilePayload>()
        let store = VideoLikeStore()
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: {}, profile: { await pending.value() }
        )
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: store, monitorNetwork: false)
        let restore = Task { await account.restoreSessionIfNeeded() }
        await waitForPendingRequest { pending.isWaiting }
        XCTAssertTrue(account.isLoggedIn, "Cached credentials must be usable while network work is pending")
        XCTAssertEqual(account.accountID, 42)
        XCTAssertFalse(account.isRestoringSession, "Profile loading must not gate local session restoration")
        store.setOverride(aid: 9, liked: true)
        let oldSession = store.sessionID
        await account.logout()
        pending.resolve(try profile())
        await restore.value
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertNil(account.profile)
        XCTAssertFalse(store.isLiked(aid: 9, serverValue: false))
        store.setOverride(aid: 9, liked: true, sessionID: oldSession)
        XCTAssertFalse(store.isLiked(aid: 9, serverValue: false), "旧请求不能污染新的账号会话")
    }

    func testExplicitExpiredSessionClearsCredentials() async throws {
        var didClear = false
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: { didClear = true },
            profile: { throw BiliAPIError.apiError(code: -101, message: "expired") }
        )
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        XCTAssertTrue(didClear)
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertFalse(account.isRestoringSession)
    }

    private func temporaryDefaults() throws -> UserDefaults {
        let suite = "neobili.audit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func profile() throws -> AccountProfilePayload {
        try decode(#"{"isLogin":true,"mid":42,"uname":"Test Account"}"#)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
