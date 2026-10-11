import XCTest
@testable import NeoBili

@MainActor
final class SMSCompletionRecoveryTests: XCTestCase {
    private func confirmedModel(identity: UUID, mid: String = "42") async -> SMSLoginModel {
        let context = SMSLoginModels.Context(accountSession: identity, headers: [:], buvid: "fixture",
                                             deviceID: "fixture", loginSession: "fixture")
        let model = SMSLoginModel(client: .init(prepare: { context }, send: { _, _, _, _, _ in .sent("fixture") },
            login: { _, _, _, _, _ in
                .confirmed(.init(cookies: .init(sessdata: "fixture", biliJct: "fixture", dedeUserID: mid), accessKey: "fixture"))
            }))
        model.phone = "13000000000"
        await model.sendCode()
        model.code = "123456"
        await model.submit()
        return model
    }

    func testStorageFailureCanRetryConfirmedCredentialsWithoutAnotherSMS() async {
        let identity = UUID(), session = UUID()
        let model = await confirmedModel(identity: identity)
        var attempts = 0
        let complete: (SMSLoginModels.Credentials, UUID) async throws -> Void = { value, prepared in
            attempts += 1
            XCTAssertEqual(value.cookies.dedeUserID, "42")
            XCTAssertEqual(prepared, identity)
            if attempts == 1 { throw CocoaError(.fileWriteNoPermission) }
        }
        let failed = await model.completeLogin(expectedSession: session, currentSession: { session },
            currentIdentitySession: { identity }, complete: complete)
        XCTAssertFalse(failed)
        XCTAssertTrue(model.canRetryCompletion)
        XCTAssertNotNil(model.credentials)
        let attempt = model.completionAttemptID
        model.retryCompletion()
        XCTAssertNotEqual(model.completionAttemptID, attempt)
        let completed = await model.completeLogin(expectedSession: session, currentSession: { session },
            currentIdentitySession: { identity }, complete: complete)
        XCTAssertTrue(completed)
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(model.completionError)
        XCTAssertFalse(model.isCompleting)
    }

    func testWrongAuthorizationAccountUnlocksPhoneWithoutWritingCredentials() async {
        let identity = UUID(), session = UUID()
        let model = await confirmedModel(identity: identity, mid: "43")
        let cooldown = model.resendAt
        let completed = await model.completeLogin(expectedSession: session, currentSession: { session },
            currentIdentitySession: { identity }, authorizationAccountID: 42) { _, _ in XCTFail("Must not overwrite current account") }
        XCTAssertFalse(completed)
        XCTAssertNil(model.credentials)
        XCTAssertNil(model.preparedAccountSession)
        XCTAssertFalse(model.canRetryCompletion)
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.isCompleting)
        XCTAssertNotNil(model.completionError)
        XCTAssertEqual(model.resendAt, cooldown, "Recovery must not bypass SMS rate limits")
        model.phone = "13000000001"
        model.resetPhone()
        XCTAssertTrue(model.validPhone)
        XCTAssertNil(model.completionError)
    }

    func testEitherChangedSessionRejectsCommitAndRequiresFreshVerification() async {
        let identity = UUID(), session = UUID()
        for accountChanged in [false, true] {
            let model = await confirmedModel(identity: identity)
            let completed = await model.completeLogin(expectedSession: session,
                currentSession: { accountChanged ? UUID() : session },
                currentIdentitySession: { accountChanged ? identity : UUID() }) { _, _ in XCTFail("Stale attempt must not save") }
            XCTAssertFalse(completed)
            XCTAssertNil(model.credentials)
            XCTAssertNotNil(model.completionError)
            XCTAssertFalse(model.canRetryCompletion)
        }
    }

    func testCommitCancellationDoesNotReportLoginSuccessOrOfferStaleRetry() async {
        let identity = UUID(), session = UUID()
        let model = await confirmedModel(identity: identity)
        let completed = await model.completeLogin(expectedSession: session, currentSession: { session },
            currentIdentitySession: { identity }) { _, _ in throw CancellationError() }
        XCTAssertFalse(completed)
        XCTAssertNil(model.credentials)
        XCTAssertFalse(model.canRetryCompletion)
        XCTAssertNotNil(model.completionError)
    }

    func testRestartDuringSuspendedCompletionCannotDismissAsSuccessful() async {
        let identity = UUID(), session = UUID()
        let model = await confirmedModel(identity: identity)
        var resume: CheckedContinuation<Void, Never>?
        let pending = Task {
            await model.completeLogin(expectedSession: session, currentSession: { session },
                currentIdentitySession: { identity }) { _, _ in
                    await withCheckedContinuation { resume = $0 }
                }
        }
        while resume == nil { await Task.yield() }
        model.cancel()
        resume?.resume()
        let completed = await pending.value
        XCTAssertFalse(completed)
        XCTAssertNil(model.credentials)
        XCTAssertFalse(model.isCompleting)
    }
}
