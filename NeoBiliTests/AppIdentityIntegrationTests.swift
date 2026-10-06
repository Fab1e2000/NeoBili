import XCTest
import Synchronization
@testable import NeoBili

final class AppIdentityIntegrationTests: XCTestCase {
    func testOwnGuestDeviceAndTicketAreSharedByHeadersAndSMS() async throws {
        let name = "AppIdentityIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let credentials = CredentialStorage.memory()
        credentials.write("12345", AppGuestRegistration.storageKey)
        let guest = AppGuestRegistration(credentials: credentials, transport: { _ in
            XCTFail("Persisted guest should not be registered again")
            throw URLError(.badURL)
        })
        let requests = Mutex<[URLRequest]>([])
        let ticket = AppTicketService(credentials: credentials, transport: { request in
            requests.withLock { $0.append(request) }
            return (AppProto.frame(AppProto.string(1, "own-ticket") + AppProto.integer(3, 7200)),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["grpc-status": "0"])!)
        })
        let identity = DeviceIdentity(defaults: defaults, credentials: credentials, allowsNetwork: false,
            vendorIdentifier: { "00112233-4455-6677-8899-AABBCCDDEEFF" },
            guestRegistration: guest, ticketService: ticket, purgeCookies: {})
        let session = identity.loginSessionID
        let first = try await identity.appRequestHeaders(expectedSessionID: session)
        XCTAssertEqual(first["guestid"], "12345")
        XCTAssertNil(first["x-bili-ticket"], "First acquisition must not block a feed request")
        await ticket.awaitPendingForTesting()
        let ready = try await identity.appRequestHeaders(expectedSessionID: session)
        XCTAssertEqual(ready["x-bili-ticket"], "own-ticket")
        let device = try AppProto(XCTUnwrap(Data(base64Encoded: XCTUnwrap(ready["x-bili-device-bin"]))))
        XCTAssertEqual(device.text(3), ready["buvid"])
        XCTAssertEqual(device.text(16), "12345")
        let sent = try XCTUnwrap(requests.withLock { $0.first })
        let signedDevice = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(sent.value(forHTTPHeaderField: "x-bili-device-bin"))))
        let payload = try AppProto(AppProto.unframe(XCTUnwrap(sent.httpBody)))
        XCTAssertEqual(payload.data(3), AppTicketProtocol.signature(device: signedDevice))
        let login = try await SMSPassport.prepare(identity: identity)
        XCTAssertEqual(SMSPassport.baseParameters(login)["device_tourist_id"], "12345")
        XCTAssertEqual(login.headers["x-bili-ticket"], "own-ticket")
        await identity.clearLoginCookies()
        let newHeaders = try await identity.appRequestHeaders(expectedSessionID: identity.loginSessionID)
        XCTAssertNil(newHeaders["x-bili-ticket"], "Logout discards the previous account's ticket immediately")
        XCTAssertEqual(newHeaders["guestid"], "12345", "Guest identity survives logout")
        await ticket.awaitPendingForTesting()
    }
}
