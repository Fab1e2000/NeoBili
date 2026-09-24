import Foundation

/// 头像条红点以服务端 portal 的 `has_update` 为准（与 PiliPlus 一致）。
/// 选中一位 UP 主时，他的动态经 `feed/all?host_mid=` 加载，服务端随之清除红点；
/// 在下一次 portal 列表回来之前，本地先把红点藏起来，并让他在「有更新」组里保位五分钟。
@MainActor
@Observable
final class FollowingReadStore {
    static let shared = FollowingReadStore()
    /// 本地已清除红点的 UP 主及清除时间，等服务端列表确认后移除。
    private(set) var cleared: [Int: Double] = [:]
    private(set) var priorityUntil: [String: Double] = [:]
    private var accountID: Int?
    private let defaults: UserDefaults
    private let now: () -> Date
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// 清除后这么久内，服务端仍报有更新时视为清除请求尚未生效；超过则当作真正的新动态。
    private static let confirmationWindow: TimeInterval = 60
    private static let priorityDuration: TimeInterval = 300

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func configure(accountID: Int?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        cleared = [:]
        priorityUntil = accountID.flatMap { defaults.dictionary(forKey: "following.priority.\($0)") as? [String: Double] } ?? [:]
        // 旧版本按本地浏览推算已读，改为服务端红点后不再需要。
        if let accountID { defaults.removeObject(forKey: "following.read.\(accountID)") }
        expirePriority()
    }

    /// 新的 portal 列表回来：服务端已不报更新的，本地覆盖可以撤掉；
    /// 仍报更新且清除已久的，说明又有新动态，重新显示红点。
    func updateServerStatus(_ ups: [FollowedUp]) {
        let unread = Set(ups.filter(\.hasUpdate).map(\.mid))
        let cutoff = now().timeIntervalSince1970 - Self.confirmationWindow
        cleared = cleared.filter { unread.contains($0.key) && $0.value > cutoff }
    }

    func hasUpdate(_ up: FollowedUp) -> Bool {
        up.hasUpdate && cleared[up.mid] == nil
    }

    func keepsPriority(_ up: FollowedUp) -> Bool {
        hasUpdate(up) || priorityUntil[String(up.mid)] != nil
    }

    /// 选中 UP 主时立即清除红点；原本有更新的在原位保留五分钟，避免选中后立刻跳走。
    func markSelected(_ up: FollowedUp) {
        guard hasUpdate(up) else { return }
        let timestamp = now().timeIntervalSince1970
        cleared[up.mid] = timestamp
        priorityUntil[String(up.mid)] = timestamp + Self.priorityDuration
        if let accountID { defaults.set(priorityUntil, forKey: "following.priority.\(accountID)") }
        scheduleExpiry()
    }

    func expirePriority() {
        priorityUntil = priorityUntil.filter { $0.value > now().timeIntervalSince1970 }
        if let accountID { defaults.set(priorityUntil, forKey: "following.priority.\(accountID)") }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let deadline = priorityUntil.values.min() else { return }
        let delay = max(deadline - now().timeIntervalSince1970, 0)
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.expirePriority()
        }
    }
}
