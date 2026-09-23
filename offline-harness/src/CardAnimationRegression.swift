import Foundation

@main struct CardAnimationRegression {
    static func main() async throws {
        let defaults = UserDefaults.standard
        let keys = [CardAnimationSettings.masterKey, CardAnimationSettings.videoEnterKey,
                    CardAnimationSettings.videoExitKey, CardAnimationSettings.dynamicEnterKey,
                    CardAnimationSettings.dynamicExitKey, CardAnimationSettings.pageEnterKey]
            + VideoCardAnimationSource.allCases.flatMap { source in
                [CardAnimationPhase.enter, .exit].map { CardAnimationSettings.storageKey(source: source, phase: $0) }
            }
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        for category in CardAnimationCategory.allCases {
            precondition(CardAnimationSettings.isEnabled(category: category, phase: .enter) == (category == .page))
            precondition(CardAnimationSettings.isEnabled(category: category, phase: .exit) == (category != .video))
        }
        defaults.set(true, forKey: CardAnimationSettings.dynamicEnterKey)
        for source in VideoCardAnimationSource.allCases {
            let key = CardAnimationSettings.storageKey(source: source, phase: .enter)
            defaults.set(true, forKey: key)
            precondition(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: source)
                         == [.recommendation, .live, .search].contains(source))
            precondition(!CardAnimationSettings.isEnabled(category: .dynamic, phase: .enter, source: source))
            defaults.removeObject(forKey: key)
        }
        defaults.set(false, forKey: CardAnimationSettings.videoEnterKey)
        precondition(!CardAnimationSettings.isEnabled(category: .video, phase: .enter))
        precondition(!CardAnimationSettings.isEnabled(category: .video, phase: .exit))
        precondition(!CardAnimationSettings.isEnabled(category: .dynamic, phase: .enter))
        print("PASS  仅指定页面可使用卡片进入动画，退出和页面淡入设置保持独立")

        defaults.set(false, forKey: CardAnimationSettings.masterKey)
        let skipped = ProcessInfo.processInfo.systemUptime
        try await CardAnimationSettings.waitWhileEnabled(for: 10, category: .dynamic, phase: .exit)
        precondition(ProcessInfo.processInfo.systemUptime - skipped < 0.5)
        defaults.set(true, forKey: CardAnimationSettings.masterKey)
        precondition(!CardAnimationSettings.isEnabled(category: .video, phase: .enter))
        print("PASS  关闭总开关立即跳过等待，重新开启保留各卡片开关")

        let started = ProcessInfo.processInfo.systemUptime
        let waiting = Task {
            try await CardAnimationSettings.waitWhileEnabled(for: 10, category: .dynamic, phase: .exit)
        }
        try await Task.sleep(for: .milliseconds(30))
        defaults.set(false, forKey: CardAnimationSettings.dynamicExitKey)
        NotificationCenter.default.post(name: CardAnimationSettings.didChangeNotification, object: nil)
        try await waiting.value
        precondition(ProcessInfo.processInfo.systemUptime - started < 0.5)
        print("PASS  动画等待期间关闭设置立即唤醒，10 秒延时不残留")

        let cancelled = Task {
            try await CardAnimationSettings.waitWhileEnabled(for: 10, category: .video, phase: .exit, source: .recommendation)
        }
        try await Task.sleep(for: .milliseconds(10))
        cancelled.cancel()
        do {
            try await cancelled.value
            preconditionFailure("取消必须传播到刷新任务")
        } catch is CancellationError {}
        print("PASS  离页取消会终止动画等待和设置监听")

        for source in VideoCardAnimationSource.allCases {
            precondition(!CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: source))
            precondition(CardAnimationSettings.isEnabled(category: .video, phase: .exit, source: source) == [.recommendation, .live].contains(source))
        }
        defaults.set(true, forKey: CardAnimationSettings.storageKey(source: .search, phase: .enter))
        precondition(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: .search))
        precondition(!CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: .recommendation))
        precondition(!CardAnimationSettings.isEnabled(category: .dynamic, phase: .enter, source: .recommendation))
        print("PASS  新来源继承旧视频开关，单页覆写不改变其他页面和动态卡片")

        for source in [VideoCardAnimationSource.history, .favorites, .watchLater] {
            defaults.set(true, forKey: CardAnimationSettings.storageKey(source: source, phase: .exit))
            let start = ProcessInfo.processInfo.systemUptime
            try await CardAnimationSettings.waitWhileEnabled(for: 10, category: .video, phase: .exit, source: source)
            precondition(ProcessInfo.processInfo.systemUptime - start < 0.5)
        }
        let sourceStarted = ProcessInfo.processInfo.systemUptime
        let historyWaiting = Task {
            try await CardAnimationSettings.waitWhileEnabled(for: 10, category: .video, phase: .exit, source: .live)
        }
        let favoriteWaiting = Task {
            try await CardAnimationSettings.waitWhileEnabled(for: 0.15, category: .video, phase: .exit, source: .recommendation)
        }
        try await Task.sleep(for: .milliseconds(20))
        defaults.set(false, forKey: CardAnimationSettings.storageKey(source: .live, phase: .exit))
        NotificationCenter.default.post(name: CardAnimationSettings.didChangeNotification, object: nil)
        try await historyWaiting.value
        precondition(ProcessInfo.processInfo.systemUptime - sourceStarted < 0.5)
        try await favoriteWaiting.value
        precondition(ProcessInfo.processInfo.systemUptime - sourceStarted >= 0.12)
        print("PASS  关闭直播退出立即结束该页等待，推荐的等待不受影响")
    }
}
