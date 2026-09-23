import SwiftUI

extension EnvironmentValues {
    /// 仅视频评论注入此动作，动态等评论不会控制无关的后台视频。
    @Entry var commentTimeJump: EnvironmentAction<Double>? = nil
}

enum CommentTimeLinks {
    struct Match: Equatable {
        let range: NSRange
        let seconds: Int
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![0-9:：])(?:[0-9]{1,3}[:：][0-5][0-9][:：][0-5][0-9]|[0-9]{1,3}[:：][0-5][0-9])(?![0-9:：])"#
    )
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private final class CachedText: NSObject {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    // NSCache is thread-safe and bounded; no font, theme or playback handler is cached.
    nonisolated(unsafe) private static let preparedText: NSCache<NSString, CachedText> = {
        let cache = NSCache<NSString, CachedText>()
        cache.countLimit = 512
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    static func matches(in text: String) -> [Match] {
        guard text.contains(":") || text.contains("：") else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        let candidates = pattern.matches(in: text, range: full)
        guard !candidates.isEmpty else { return [] }
        let links = linkDetector.matches(in: text, range: full).map(\.range)
        return candidates.compactMap { match in
            guard !links.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  let range = Range(match.range, in: text) else { return nil }
            let parts = text[range].split(whereSeparator: { $0 == ":" || $0 == "：" }).compactMap { Int($0) }
            return Match(range: match.range, seconds: parts.reduce(0) { $0 * 60 + $1 })
        }
    }

    static func attributed(_ text: String) -> AttributedString {
        let key = text as NSString
        if let cached = preparedText.object(forKey: key) { return cached.value }
        var result = AttributedString()
        var cursor = text.startIndex
        for match in matches(in: text) {
            guard let range = Range(match.range, in: text) else { continue }
            result += AttributedString(text[cursor..<range.lowerBound])
            var time = AttributedString(text[range])
            time.link = URL(string: "neobili://comment-time/\(match.seconds)")
            result += time
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        preparedText.setObject(CachedText(result), forKey: key, cost: text.utf16.count * 8 + 128)
        return result
    }

    static func seconds(from url: URL) -> Double? {
        guard url.scheme == "neobili", url.host == "comment-time",
              let value = Int(url.lastPathComponent), value >= 0 else { return nil }
        return Double(value)
    }
}
