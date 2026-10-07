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
        var backgroundedAt: TimeInterval?
    }
    private let state = Mutex(State())

    private let now: @Sendable () -> TimeInterval

    init(now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func didEnterBackground() { state.withLock { $0.backgroundedAt = now() } }
    func didBecomeActive() {
        state.withLock {
            if let started = $0.backgroundedAt {
                if now() - started > 1800 {
                    $0.bannerHash = ""
                    // An in-flight response from before expiry must not revive it.
                    $0.epoch = UUID()
                }
                $0.openEvent = "hot"
                $0.backgroundedAt = nil
            }
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
