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

    static func matches(in text: String) -> [Match] {
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
        return result
    }

    static func seconds(from url: URL) -> Double? {
        guard url.scheme == "neobili", url.host == "comment-time",
              let value = Int(url.lastPathComponent), value >= 0 else { return nil }
        return Double(value)
    }
}
