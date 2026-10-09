import XCTest
@testable import NeoBili

@MainActor
final class LoginCallbackLifecycleTests: XCTestCase {
    func testCaptchaSuccessThenCloseDeliversOnlySuccess() {
        var values: [GeetestView.Result?] = []
        let coordinator = GeetestView.Coordinator { values.append($0) }
        let result = GeetestView.Result(challenge: "challenge", validate: "validate", seccode: "code")
        coordinator.finish(result)
        coordinator.finish(nil)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first!, result)
    }

    func testDismantledCaptchaDiscardsLateResult() {
        let coordinator = GeetestView.Coordinator { _ in XCTFail("Dismissed validation must not start login") }
        coordinator.cancel()
        coordinator.finish(.init(challenge: "challenge", validate: "validate", seccode: "code"))
    }
}
