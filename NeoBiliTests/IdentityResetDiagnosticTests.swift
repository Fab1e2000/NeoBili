#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if DEBUG
import XCTest
@testable import NeoBili

final class IdentityResetDiagnosticTests: XCTestCase {
    func testResetClearsOldScopesAndRunsOnlyOnceWithoutErasingOtherPreferences() throws {
        let suite = "identity-reset.\(UUID())", sequenceSuite = "identity-sequence.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let sequence = try XCTUnwrap(UserDefaults(suiteName: sequenceSuite))
        defer { defaults.removePersistentDomain(forName: suite); sequence.removePersistentDomain(forName: sequenceSuite) }
        let credentials = CredentialStorage.memory()
        for key in IdentityResetDiagnostic.credentialKeys { credentials.write("old", key) }
        for key in IdentityResetDiagnostic.preferenceKeys { defaults.set("old", forKey: key) }
        defaults.set("dark", forKey: "theme")
        defaults.set("keep-downloads", forKey: "download-directory")
        sequence.set(42, forKey: "neobili.neuron.eventSerial")
        var clears = 0
        XCTAssertTrue(try IdentityResetDiagnostic.resetOnce(defaults: defaults, credentials: credentials,
            sequenceDefaults: sequence, clearNetworking: { clears += 1 }))
        let randomKey = "neobili.experiment.randomBuvid.v1"
        for key in IdentityResetDiagnostic.credentialKeys where key != randomKey { XCTAssertNil(credentials.read(key), key) }
        let fresh = try XCTUnwrap(credentials.read(randomKey))
        XCTAssertEqual(fresh.count, 36)
        XCTAssertEqual(defaults.string(forKey: randomKey), fresh)
        XCTAssertEqual(defaults.string(forKey: "neobili.appBuvid.mode"), "random")
        XCTAssertNil(sequence.object(forKey: "neobili.neuron.eventSerial"))
        XCTAssertEqual(defaults.string(forKey: "theme"), "dark")
        XCTAssertEqual(defaults.string(forKey: "download-directory"), "keep-downloads")
        credentials.write("new-login", "neobili.access_key")
        XCTAssertFalse(try IdentityResetDiagnostic.resetOnce(defaults: defaults, credentials: credentials,
            sequenceDefaults: sequence, clearNetworking: { clears += 1 }))
        XCTAssertEqual(clears, 1)
        XCTAssertEqual(credentials.read("neobili.access_key"), "new-login")
        XCTAssertEqual(credentials.read(randomKey), fresh)
    }

    func testFailedCredentialDeletionDoesNotMarkCompletedOrProceedToNetworking() throws {
        let suite = "identity-reset-failure.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let base = CredentialStorage.memory()
        base.write("old", "neobili.access_key")
        let blocked = CredentialStorage(read: base.read, write: { _, _ in })
        XCTAssertThrowsError(try IdentityResetDiagnostic.resetOnce(defaults: defaults, credentials: blocked,
            sequenceDefaults: defaults, clearNetworking: { XCTFail("Failed deletion cannot proceed") }))
        XCTAssertFalse(defaults.bool(forKey: IdentityResetDiagnostic.marker))
    }

    func testInterruptedCacheResetCanRetryOnNextLaunch() throws {
        let suite = "identity-reset-retry.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStorage.memory()
        XCTAssertThrowsError(try IdentityResetDiagnostic.resetOnce(defaults: defaults, credentials: credentials,
            sequenceDefaults: defaults, clearNetworking: { throw URLError(.cannotCreateFile) }))
        XCTAssertFalse(defaults.bool(forKey: IdentityResetDiagnostic.marker))
        XCTAssertTrue(try IdentityResetDiagnostic.resetOnce(defaults: defaults, credentials: credentials,
            sequenceDefaults: defaults, clearNetworking: {}))
    }
}
#endif
