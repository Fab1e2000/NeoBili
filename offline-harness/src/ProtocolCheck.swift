import Foundation

/// This executable never reads Keychain, dumps requests or rotates credentials.
/// Optional context is a private JSON file supplied by the caller, not a capture search.
@main struct ProtocolCheck {
    struct PrivateContext: Decodable {
        let accessKey: String
        let mid: Int
        let headers: [String: String]
    }
    static func main() async {
        do { try await run() }
        catch {
            // Error descriptions can contain signed URLs. Print only a classification.
            print("CHECK_FAILED type=\(String(describing: type(of: error)))")
            exit(1)
        }
    }
    static func run() async throws {
        let login = UUID()
        let encoder = AppRequestEncoder(timestamp: { 1_700_000_000 })
        let fixture = AppRequestContext(account: .init(accessKey: "fixture-access", mid: 42, sessionID: login))
        let encoded = try encoder.encode(.get(path: "x/v2/feed/index", parameters: ["q": "A+B & 测试", "empty": ""], requiresAccountCredential: true), context: fixture)
        guard encoded.url?.query == "access_key=fixture-access&appkey=27eb53fc9058f8c3&empty=&q=A%2BB%20%26%20%E6%B5%8B%E8%AF%95&sign=8df05bb434a5daa7bd271a1b2aadfe76&ts=1700000000" else { throw CheckFailure.contract }
        for (request, flush, pull) in [
            (RecommendationRequest(source: .app), "0", "1"),
            (RecommendationRequest(source: .app, appCursor: 900, isRefresh: true), "6", "1"),
            (RecommendationRequest(source: .app, pageIndex: 1, appCursor: 700), "8", "0")
        ] {
            let fields = AppRecommendationProtocol.parameters(for: request)
            guard fields["flush"] == flush, fields["pull"] == pull,
                  fields["idx"] == String(request.appCursor), fields["auto_refresh_state"] == "4" else { throw CheckFailure.contract }
        }
        print("PASS production encoding golden + initial/refresh/pagination policy")
        guard CommandLine.arguments.dropFirst().allSatisfy({ $0 == "--network" }) else { throw CheckFailure.arguments }
        guard CommandLine.arguments.contains("--network") else {
            print("NETWORK_NOT_RUN (use --network; maximum 4 GET requests, no retry)"); return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let key = AppGuestProtocol.request(path: "x/passport-login/web/key", headers: [:], timestamp: Int(Date().timeIntervalSince1970), isPost: false)
        let keyReply = await fetch(key, label: "DEV-09 public-key", session: session)
        let hasPublicKey = ((keyReply?["data"] as? [String: Any])?["key"] as? String)?.isEmpty == false
        print("public_key_present=\(hasPublicKey)")
        guard hasPublicKey else { throw CheckFailure.network }
        let time = try AppRequestEncoder().encode(.get(path: "x/report/click/now", parameters: [:], requiresAccountCredential: false, usesAPIHost: true), context: .init(account: .init(accessKey: nil, mid: nil, sessionID: login)))
        guard await fetch(time, label: "HB-04 server-time", session: session) != nil else { throw CheckFailure.network }
        guard let path = ProcessInfo.processInfo.environment["NEOBILI_PROBE_CONTEXT"] else {
            print("ACCOUNT_NOT_RUN missing private context; no guest results substituted for personalized feed")
            return
        }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        guard bytes.count < 128 * 1024 else { throw CheckFailure.context }
        let input = try JSONDecoder().decode(PrivateContext.self, from: bytes)
        guard !input.accessKey.isEmpty, input.mid > 0,
              input.headers.keys.contains(where: { $0.lowercased() == "buvid" }) else { throw CheckFailure.context }
        let context = AppRequestContext(account: .init(accessKey: input.accessKey, mid: input.mid, sessionID: login), headers: input.headers)
        var request = RecommendationRequest(source: .app)
        for index in 0..<2 {
            let wire = try AppRequestEncoder().encode(.get(path: "x/v2/feed/index", parameters: AppRecommendationProtocol.parameters(for: request, openEvent: index == 0 ? "cold" : ""), requiresAccountCredential: true), context: context)
            guard let object = await fetch(wire, label: "FEED-01 batch-\(index + 1)", session: session),
                  let payload = object["data"], JSONSerialization.isValidJSONObject(payload),
                  let page = try? JSONDecoder().decode(AppRecommendationPage.self, from: JSONSerialization.data(withJSONObject: payload)) else { throw CheckFailure.network }
            print("decoded_cards=\(page.cards.count) refresh_cursor_present=\(page.refreshCursor != nil) next_cursor_present=\(page.nextCursor != nil)")
            guard let cursor = page.nextCursor else { break }
            request = request.next(appCursor: cursor)
        }
        print("LIMIT: supplied context does not verify header lifecycle; no watching, likes, favorites, or credential renewal sent")
    }
    static func fetch(_ request: URLRequest, label: String, session: URLSession) async -> [String: Any]? {
        do {
            let (bytes, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            let code = (object?["code"] as? NSNumber)?.intValue
            print("\(label) http=\(status) code=\(code.map(String.init) ?? "absent") bytes=\(bytes.count)")
            guard status == 200, code == 0 else { return nil }
            return object
        } catch {
            print("\(label) transport_error=\((error as NSError).code)")
            return nil
        }
    }
    enum CheckFailure: Error { case contract, arguments, context, network }
    final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
