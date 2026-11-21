import XCTest

@MainActor
func waitForPendingRequest(_ predicate: () -> Bool) async {
    for _ in 0..<10_000 {
        if predicate() { return }
        await Task.yield()
    }
    XCTFail("异步请求未在预期时间进入等待状态")
}

@MainActor
final class PendingModelResult<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    var isWaiting: Bool { continuation != nil }

    func value() async -> Value {
        await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
