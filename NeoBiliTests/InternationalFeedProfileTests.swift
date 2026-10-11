#if DEBUG
import XCTest
@testable import NeoBili

final class InternationalFeedProfileTests: XCTestCase {
    func testEncodedFeedUsesCapturedProfileAndOwnDynamicIdentity() throws {
        let account = AppAccountSnapshot(accessKey: "own-token", mid: 42, sessionID: UUID())
        let headers = ["buvid":"own-device", "session_id":"own-session", "x-bili-ticket":"own-ticket",
                       "x-bili-device-bin":"own-metadata", "x-bili-aurora-zone":"sh001"]
        let params = AppRecommendationProtocol.parameters(for: .init(source: .app, appCursor: 123, isRefresh: true))
        let request = try AppRequestEncoder(timestamp: { 456 }).encode(
            .get(path: "x/v2/feed/index", parameters: params, requiresAccountCredential: true),
            context: .init(account: account, headers: headers))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["mobi_app"], "iphone_i")
        XCTAssertEqual(query["build"], "91300300")
        XCTAssertEqual(query["statistics"], #"{"appId":14,"version":"6.6.0","abtest":"","platform":1}"#)
        XCTAssertEqual(query["flush"], "14")
        XCTAssertEqual(query["idx"], "123")
        XCTAssertEqual(query["access_key"], "own-token")
        XCTAssertEqual(query["ts"], "456")
        XCTAssertEqual(query["widgets"], "")
        XCTAssertNil(query["teenagers_age"])
        XCTAssertNil(query["ad_extra"])
        for name in ["buvid", "session_id", "x-bili-ticket"] { XCTAssertEqual(request.value(forHTTPHeaderField: name), headers[name]) }
        XCTAssertEqual(request.value(forHTTPHeaderField: "app-key"), "iphone_i")
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("mobi_app/iphone_i") == true)
        for name in ["Referer", "x-bili-device-bin", "x-bili-aurora-zone"] { XCTAssertNil(request.value(forHTTPHeaderField: name)) }
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-bili-metadata-ip-region"), "CN")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-bili-redirect"), "1")
        let locale = try AppProto(try XCTUnwrap(Data(base64Encoded: AppDeviceLocale.header)))
        XCTAssertEqual(locale.text(4), "Asia/Shanghai")
        XCTAssertEqual(locale.text(8), "USA")
        let other = try AppRequestEncoder().encode(
            .get(path: "x/v2/view", parameters: [:], requiresAccountCredential: true),
            context: .init(account: account, headers: headers))
        XCTAssertEqual(other.value(forHTTPHeaderField: "x-bili-device-bin"), "own-metadata")
        XCTAssertNil(other.value(forHTTPHeaderField: "x-bili-metadata-ip-region"))
    }
    func testDefaultBuildUsesTheValidatedInternationalProfile() {
        XCTAssertTrue(AppClientIdentity.isInternationalProfile)
        XCTAssertEqual(AppClientIdentity.mobiApp, "iphone_i")
        XCTAssertEqual(AppClientIdentity.build, "91300300")
    }
}
#endif
