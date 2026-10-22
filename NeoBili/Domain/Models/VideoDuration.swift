import Foundation

public enum VideoDuration {
    /// 接口的时长文本使用 M:SS 或 H:MM:SS；无法解析时交给详情补查。
    public static func seconds(from text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0
        for (index, part) in parts.enumerated() {
            guard let value = Int(part), value >= 0,
                  index == 0 || value < 60,
                  total <= (Int.max - value) / 60 else { return nil }
            total = total * 60 + value
        }
        return total > 0 ? total : nil
    }
}
