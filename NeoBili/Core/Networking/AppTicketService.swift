import Foundation
import CommonCrypto

/// TICKET-01/02: native 8.89 request construction and cache lifecycle.
/// Context experiments are deliberately omitted until their local materials exist.
enum AppTicketProtocol {
    static let path = "bilibili.api.ticket.v1.Ticket/GetTicket"
    // General client signing constants recovered at 0x100096888 and 0x100096b78.
    // These are not an account credential or a server ticket-minting key.
    static let keyID = "ec01"
    static let signingKey = Data("Ezlc3tgtl".utf8)

    static func signingInput(device: Data, context: [String: Data]) -> Data {
        var result = device
        for key in context.keys.sorted() where !key.isEmpty {
            result += Data(key.utf8)
            result += context[key]!
        }
        return result
    }

    static func signature(device: Data, context: [String: Data] = [:], key: Data = signingKey) -> Data {
        let input = signingInput(device: device, context: context)
        guard !input.isEmpty, !key.isEmpty else { return Data() }
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { secret in
                input.withUnsafeBytes { bytes in
                    CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), secret.baseAddress, key.count,
                           bytes.baseAddress, input.count, output.baseAddress)
                }
            }
        }
        return digest
    }

    static func request(headers: [String: String], accessKey: String?, context: [String: Data] = [:]) throws -> URLRequest {
        func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name }?.value }
        guard let encoded = header("x-bili-device-bin"), let device = Data(base64Encoded: encoded), !device.isEmpty else {
            throw AppProto.Failure.malformed
        }
        var payload = Data()
        for key in context.keys.sorted() where !key.isEmpty {
            payload += AppProto.bytes(1, AppProto.string(1, key) + AppProto.bytes(2, context[key]!))
        }
        payload += AppProto.string(2, keyID) + AppProto.bytes(3, signature(device: device, context: context))
        var request = URLRequest(url: URL(string: "https://grpc.biliapi.net/" + path)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.httpBody = AppProto.frame(payload)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
        request.setValue("trailers", forHTTPHeaderField: "te")
        request.setValue("15S", forHTTPHeaderField: "grpc-timeout")
        request.setValue("gzip", forHTTPHeaderField: "grpc-accept-encoding")
        if let accessKey, !accessKey.isEmpty { request.setValue("identify_v1 " + accessKey, forHTTPHeaderField: "authorization") }
        let metadata = AppProto.string(1, accessKey) + AppProto.string(2, AppClientIdentity.mobiApp)
            + AppProto.string(3, "phone") + AppProto.integer(4, Int(AppClientIdentity.build) ?? 0)
            + AppProto.string(5, "pink_overseas") + AppProto.string(6, header("buvid")) + AppProto.string(7, "ios")
        request.setValue(metadata.base64EncodedString(), forHTTPHeaderField: "x-bili-metadata-bin")
        return request
    }

    static func response(_ data: Data, response: URLResponse) throws -> (ticket: String, ttl: TimeInterval) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.value(forHTTPHeaderField: "grpc-status").map({ $0 == "0" }) ?? true else { throw AppProto.Failure.malformed }
        let message = try AppProto(AppProto.unframe(data))
        guard let ticket = message.text(1), !ticket.isEmpty, ticket.utf8.count <= 16_384,
              case .integer(let rawTTL) = message.fields[3]?.first else { throw AppProto.Failure.malformed }
        // Protobuf int64 uses a two's-complement varint. Expiry is receipt time + ttl,
        // not createdAt; preserve signed semantics rather than imposing an invented TTL.
        return (ticket, TimeInterval(Int64(bitPattern: rawTTL)))
    }
}

actor AppTicketService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private struct Cache: Codable { let scope: String; let ticket: String; var expiry: TimeInterval }
    private struct Context { let scope: String; let headers: [String: String]; let accessKey: String? }
    private static let storageKey = "neobili.app.ticket"
    private let credentials: CredentialStorage
    private let transport: Transport
    private let clock: @Sendable () -> TimeInterval
    private let jitter: @Sendable () -> Double
    private var cache: Cache?
    private var currentScope: String?
    private var context: Context?
    private var pending: Task<Void, Never>?
    private var generation = UUID()
    private var failureCount = 0
    private var nextAttempt: TimeInterval = 0

    init(credentials: CredentialStorage, transport: @escaping Transport = { try await AppNetwork.session.data(for: $0) },
         clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
         jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }) {
        self.credentials = credentials; self.transport = transport; self.clock = clock; self.jitter = jitter
        if let text = credentials.read(Self.storageKey), let data = text.data(using: .utf8) {
            cache = try? JSONDecoder().decode(Cache.self, from: data)
        }
    }

    /// Returns the existing value immediately, including during renewal failure.
    /// Scope is a local account-generation + device identity, never sent on the wire.
    func cachedTicket(scope: String, headers: [String: String], accessKey: String?) -> String? {
        if currentScope != scope { selectScope(scope) }
        context = Context(scope: scope, headers: headers, accessKey: accessKey)
        let value = cache?.scope == scope ? cache?.ticket : nil
        if cache == nil || cache!.expiry == 0 || cache!.expiry - clock() < 1800 { schedule() }
        return value
    }

    func observe(status: String?, scope: String) {
        guard status == "1", currentScope == scope else { return }
        if cache != nil { cache!.expiry = 0; persist() }
        schedule()
    }

    /// Response hook with the ticket captured on the outgoing request. A late
    /// response for an older ticket cannot invalidate its already-refreshed replacement.
    func observe(status: String?, sentTicket: String?) {
        guard (cache?.ticket ?? "") == (sentTicket ?? ""), let scope = currentScope else { return }
        observe(status: status, scope: scope)
    }

    /// Explicit account boundary policy: isolate accounts rather than claiming that
    /// the official app's unresolved cross-account reset path has been replicated.
    func reset(scope: String) { selectScope(scope) }

    func invalidateAccount(prefix: String) {
        guard currentScope?.hasPrefix(prefix) == true || cache?.scope.hasPrefix(prefix) == true else { return }
        selectScope("invalidated-" + UUID().uuidString)
    }

    private func selectScope(_ scope: String) {
        generation = UUID(); pending?.cancel(); pending = nil
        currentScope = scope; context = nil; failureCount = 0; nextAttempt = 0
        if cache?.scope != scope { cache = nil; persist() }
    }

    private func schedule() {
        guard pending == nil, let context, clock() >= nextAttempt else { return }
        let request: URLRequest
        do { request = try AppTicketProtocol.request(headers: context.headers, accessKey: context.accessKey) }
        catch { nextAttempt = clock() + 15; return }
        let generation = generation, transport = transport
        pending = Task {
            do {
                let (data, response) = try await transport(request)
                let result = try AppTicketProtocol.response(data, response: response)
                self.complete(generation: generation, context: context, result: result)
            } catch {
                self.complete(generation: generation, context: context, result: nil)
            }
        }
    }

    private func complete(generation: UUID, context: Context, result: (ticket: String, ttl: TimeInterval)?) {
        guard self.generation == generation, currentScope == context.scope else { return }
        pending = nil
        if let result {
            cache = Cache(scope: context.scope, ticket: result.ticket, expiry: clock() + result.ttl)
            failureCount = 0; nextAttempt = 0; persist()
        } else {
            failureCount = min(failureCount + 1, 15)
            nextAttempt = clock() + Double(failureCount) + min(max(jitter(), 0), 1)
            // No recursive retry. A later ordinary request can trigger another attempt.
        }
    }

    private func persist() {
        let text = cache.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        credentials.write(text, Self.storageKey)
    }

    func awaitPendingForTesting() async { await pending?.value }
}
