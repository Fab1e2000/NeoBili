import Foundation

/// 播放器控件位置：设置对象读取旧的 @AppStorage 键，且只写入改动的那一项。
@main struct PlayerChromePreferencesRegression {
    @MainActor static func main() {
        let suite = "neobili.harness.playerChrome.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fullKeys = PlayerChromeSettings.keys(for: .fullScreen)
        let inlineKeys = PlayerChromeSettings.keys(for: .inline)

        let fresh = PlayerChromePreferences(defaults: defaults)
        precondition(fresh.fullScreen == PlayerChromeSettings.defaults(for: .fullScreen))
        precondition(fresh.inline == PlayerChromeSettings.defaults(for: .inline))
        print("PASS  没有保存过的键使用默认值")

        // 旧版本 @AppStorage 写下的值（Double 和整数）继续有效。
        defaults.set(12.0, forKey: fullKeys.topInset)
        defaults.set(20, forKey: inlineKeys.spacing)
        let migrated = PlayerChromePreferences(defaults: defaults)
        precondition(migrated.fullScreen.topInset == 12)
        precondition(migrated.inline.spacing == 20)
        precondition(migrated.fullScreen.followsSafeArea)
        print("PASS  沿用原有设置键，已保存的值继续生效")

        migrated.update(.inline) { $0.bottomInset = 6 }
        precondition(migrated.inline.bottomInset == 6)
        precondition(defaults.double(forKey: inlineKeys.bottomInset) == 6)
        precondition(defaults.object(forKey: inlineKeys.topInset) == nil)
        precondition(defaults.object(forKey: inlineKeys.horizontalInset) == nil)
        precondition(defaults.object(forKey: fullKeys.bottomInset) == nil)
        print("PASS  只写入改动的那一项，另一组不受影响")

        migrated.update(.fullScreen) { $0 = PlayerChromeSettings.defaults(for: .fullScreen) }
        precondition(migrated.fullScreen == PlayerChromeSettings.defaults(for: .fullScreen))
        precondition(defaults.double(forKey: fullKeys.topInset) == PlayerChromeSettings.defaults(for: .fullScreen).topInset)
        precondition(PlayerChromePreferences(defaults: defaults).fullScreen == PlayerChromeSettings.defaults(for: .fullScreen))
        print("PASS  恢复默认后重新读取仍是默认值")

        // 下面几段用单独的存储：App 里只有一个共享对象，这里另起对象会互相覆盖。
        let legacySuite = suite + ".legacy"
        let legacy = UserDefaults(suiteName: legacySuite)!
        defer { legacy.removePersistentDomain(forName: legacySuite) }

        // 旧版本把「跟随系统」存成负数的左右边距；非负数是手动值。
        legacy.set(-1.0, forKey: fullKeys.horizontalInset)
        let legacyAutomatic = PlayerChromePreferences(defaults: legacy).fullScreen
        precondition(legacyAutomatic.followsSafeArea)
        precondition(legacyAutomatic.horizontalInset == PlayerChromeSettings.defaults(for: .fullScreen).horizontalInset)
        legacy.set(30.0, forKey: fullKeys.horizontalInset)
        let legacyManual = PlayerChromePreferences(defaults: legacy).fullScreen
        precondition(!legacyManual.followsSafeArea && legacyManual.horizontalInset == 30)
        legacy.set(-1.0, forKey: fullKeys.horizontalInset)
        print("PASS  旧版本的「跟随系统」和手动左右边距都能正确读出")

        // 新的手动边距可以是负数（玻璃贴边），不能再被当成「跟随系统」。
        let edge = PlayerChromePreferences(defaults: legacy)
        edge.update(.fullScreen) { $0.followsSafeArea = false; $0.horizontalInset = -PlayerChromeSettings.tapAreaMargin }
        precondition(legacy.object(forKey: fullKeys.followsSafeArea!) as? Bool == false)
        let reloaded = PlayerChromePreferences(defaults: legacy).fullScreen
        precondition(!reloaded.followsSafeArea && reloaded.horizontalInset == -PlayerChromeSettings.tapAreaMargin)
        precondition(PlayerChromeSettings.fullScreenHorizontalInset(reloaded, safeArea: 62) == -8)
        precondition(PlayerChromeSettings.fullScreenHorizontalInset(PlayerChromeSettings.defaults(for: .fullScreen), safeArea: 62) == 62)
        print("PASS  负数的手动边距保存后仍是手动值，跟随系统时取安全区")
    }
}
