import Foundation
import Synchronization

/// 生命周期标记与横幅缓存独立于分页游标；账号切换后的旧响应不能写入新会话。
final class AppRecommendationSession: Sendable {
    static let shared = AppRecommendationSession()
    struct Context: Sendable {
        let epoch: UUID
        let openEvent: String
        let bannerHash: String
    }
    private struct State {
        var epoch = UUID()
        var accountSession: UUID?
        var openEvent = "cold"
        var bannerHash = ""
        var backgrounded = false
    }
    private let state = Mutex(State())

    func didEnterBackground() { state.withLock { $0.backgrounded = true } }
    func didBecomeActive() {
        state.withLock {
            if $0.backgrounded { $0.openEvent = "hot"; $0.backgrounded = false }
        }
    }
    func takeRequest(accountSession: UUID) -> Context {
        state.withLock {
            if let previous = $0.accountSession, previous != accountSession {
                $0.epoch = UUID(); $0.bannerHash = ""
            }
            $0.accountSession = accountSession
            let result = Context(epoch: $0.epoch, openEvent: $0.openEvent, bannerHash: $0.bannerHash)
            $0.openEvent = ""
            return result
        }
    }
    func recordBanner(_ hash: String?, context: Context) {
        guard let hash, !hash.isEmpty else { return }
        state.withLock {
            guard $0.epoch == context.epoch, $0.bannerHash.isEmpty else { return }
            $0.bannerHash = hash
        }
    }
}

/// Only known locale fields are encoded; unknown region fields are deliberately omitted.
enum AppRecommendationLocale {
    static var header: String {
        func field(_ number: UInt8, _ bytes: Data) -> Data {
            precondition(bytes.count < 128)
            return Data([number << 3 | 2, UInt8(bytes.count)]) + bytes
        }
        let locale = field(1, Data("zh".utf8)) + field(2, Data("Hans".utf8)) + field(3, Data("CN".utf8))
        return (field(1, locale) + field(2, locale) + field(4, Data("Asia/Shanghai".utf8))).base64EncodedString()
    }
}
