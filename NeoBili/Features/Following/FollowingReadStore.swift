import Foundation

/// 按账号记录实际看到的动态时间，服务端旧红点不会在刷新后重新出现。
@MainActor
@Observable
final class FollowingReadStore {
    static let shared = FollowingReadStore()
    private(set) var readThrough: [String: Int] = [:]
    private(set) var latest: [Int: Int] = [:]
    private var accountID: Int?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var serverUnread: Set<Int> = []
    private(set) var priorityUntil: [String: Double] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func updateServerStatus(_ ups: [FollowedUp]) {
        serverUnread = Set(ups.filter(\.hasUpdate).map(\.mid))
    }

    func keepsPriority(_ up: FollowedUp) -> Bool {
        hasUpdate(up) || priorityUntil[String(up.mid)] != nil
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

    func configure(accountID: Int?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        latest = [:]
        serverUnread = []
        readThrough = accountID.flatMap { defaults.dictionary(forKey: "following.read.\($0)") as? [String: Int] } ?? [:]
        priorityUntil = accountID.flatMap { defaults.dictionary(forKey: "following.priority.\($0)") as? [String: Double] } ?? [:]
        expirePriority()
    }

    func observe(_ entries: [DynamicEntry]) {
        for entry in entries where entry.publishedTimestamp > 0 {
            latest[entry.authorMid] = max(latest[entry.authorMid] ?? 0, entry.publishedTimestamp)
        }
    }

    func markViewed(_ entry: DynamicEntry) {
        guard entry.publishedTimestamp > 0 else { return }
        let key = String(entry.authorMid)
        guard entry.publishedTimestamp > (readThrough[key] ?? 0) else { return }
        let wasUnread = readThrough[key].map { (latest[entry.authorMid] ?? 0) > $0 }
            ?? serverUnread.contains(entry.authorMid)
        readThrough[key] = entry.publishedTimestamp
        // 红点即时清除，但只有一次真正的未读→已读变化才开始五分钟保位。
        if wasUnread, entry.publishedTimestamp >= (latest[entry.authorMid] ?? 0) {
            priorityUntil[key] = now().addingTimeInterval(300).timeIntervalSince1970
            if let accountID { defaults.set(priorityUntil, forKey: "following.priority.\(accountID)") }
            scheduleExpiry()
        }
        if let accountID { defaults.set(readThrough, forKey: "following.read.\(accountID)") }
    }

    func hasUpdate(_ up: FollowedUp) -> Bool {
        guard let read = readThrough[String(up.mid)] else { return up.hasUpdate }
        return (latest[up.mid] ?? 0) > read
    }
}
