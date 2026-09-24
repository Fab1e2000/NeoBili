import Foundation

extension Int {
    /// 播放量、点赞数这类大数字的简写：中文界面 1.2万、3.4亿，英文界面 12.3K、1.2M、3.4B。
    var biliCountText: String {
        if AppLanguage.isEnglish {
            if self >= 1_000_000_000 { return String(format: "%.1fB", Double(self) / 1_000_000_000) }
            if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
            if self >= 10_000 { return String(format: "%.1fK", Double(self) / 1_000) }
            return String(self)
        }
        if self >= 100_000_000 {
            return String(format: "%.1f亿", Double(self) / 100_000_000)
        }
        if self >= 10_000 {
            return String(format: "%.1f万", Double(self) / 10_000)
        }
        return String(self)
    }

    /// 稿件发布时间（秒级时间戳）的相对写法：刚刚、23分钟前、3小时前、昨天、
    /// 9月4日。关注页的卡片用它，和 B 站客户端动态流的时间行一致。
    var biliRelativeTimeText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return String(localized: "刚刚") }
        if elapsed < 3600 { return String(localized: "\(Int(elapsed / 60))分钟前") }
        if elapsed < 86_400 { return String(localized: "\(Int(elapsed / 3600))小时前") }

        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return String(localized: "昨天") }

        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        formatter.setLocalizedDateFormatFromTemplate(isThisYear ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }

    /// 稿件发布时间（秒级时间戳）的完整写法：2026年9月4日 09:00 / Sep 4, 2026 09:00。
    var biliPubdateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMdHHmm")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(self)))
    }
}
