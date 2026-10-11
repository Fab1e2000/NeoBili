import XCTest
@testable import NeoBili

final class CapturedDeviceDiagnosticTests: XCTestCase {
    func testCapturedSeedRegeneratesExactIdentityAndRejectsMismatch() throws {
        let seed = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let buvid = try XCTUnwrap(AppBuvid.generate(idfv: seed))
        var configuration = CapturedDeviceDiagnostic.Configuration(buvid: buvid, guestID: "123", generationSeedIDFV: seed)
        XCTAssertEqual(CapturedDeviceDiagnostic.decode(try JSONEncoder().encode(configuration))?.buvid, buvid)
        configuration.buvid = "Y000" + String(repeating: "0", count: 32)
        XCTAssertNil(CapturedDeviceDiagnostic.decode(try JSONEncoder().encode(configuration)))
        configuration.buvid = buvid
        configuration.generationSeedIDFV = "invalid"
        XCTAssertNil(CapturedDeviceDiagnostic.decode(try JSONEncoder().encode(configuration)))
    }
    func testMalformedOrMissingIdentityCannotEnableComparison() throws {
        for body in [#"{}"#, #"{"buvid":"short","guestID":"123"}"#,
                     #"{"buvid":"fixture-device-123456","guestID":"0"}"#,
                     #"{"buvid":"fixture-device-123456","guestID":"-2"}"#,
                     #"{"buvid":"fixture-device-123456","guestID":"invalid"}"#] {
            XCTAssertNil(CapturedDeviceDiagnostic.decode(Data(body.utf8)))
        }
    }

    func testComparisonStorageCannotReuseOrOverwriteOwnDeviceCaches() throws {
        let base = CredentialStorage.memory()
        base.write("own-ticket", "neobili.app.ticket")
        let a = CapturedDeviceDiagnostic.Configuration(buvid: "fixture-device-123456", guestID: "123")
        let b = CapturedDeviceDiagnostic.Configuration(buvid: "fixture-device-123456", guestID: "456")
        let first = CapturedDeviceDiagnostic.isolatedStorage(base, configuration: a)
        let second = CapturedDeviceDiagnostic.isolatedStorage(base, configuration: b)
        XCTAssertNil(first.read("neobili.app.ticket"))
        first.write("comparison-ticket", "neobili.app.ticket")
        XCTAssertEqual(base.read("neobili.app.ticket"), "own-ticket")
        XCTAssertNil(second.read("neobili.app.ticket"))
        let randomized = CapturedDeviceDiagnostic.Configuration(buvid: a.buvid, guestID: "789", registrationScopeGuestID: a.guestID)
        XCTAssertEqual(randomized.parsedGuestID, 789)
        XCTAssertEqual(CapturedDeviceDiagnostic.isolatedStorage(base, configuration: randomized).read("neobili.app.ticket"), "comparison-ticket")
        XCTAssertEqual(CapturedDeviceDiagnostic.isolatedStorage(base, configuration: a).read("neobili.app.ticket"), "comparison-ticket")
    }

    func testCapturedGuestIdentityDoesNotRequestAnotherGuestOrReplaceOwnIdentity() async {
        let storage = CredentialStorage.memory()
        storage.write("456", AppGuestRegistration.storageKey)
        let guest = AppGuestRegistration(credentials: storage,
            transport: { _ in XCTFail("Captured guest must be used for this comparison"); throw URLError(.badServerResponse) },
            capturedGuestID: 123)
        let value = await guest.load(buvid: "fixture-device", headers: [:])
        XCTAssertEqual(value, 123)
        XCTAssertEqual(storage.read(AppGuestRegistration.storageKey), "456")
    }
}
