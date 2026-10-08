import SwiftUI

/// Link ranges are selected before replacing titles, so URL timestamps and title
/// text can never become accidental playback links. All ranges use UTF-16.
enum CommentLinks {
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let videoID = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])(?:BV[1-9A-HJ-NP-Za-km-z]{10}|av[0-9]+)(?![A-Za-z0-9])"#)

    private final class CachedText: NSObject {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }
    nonisolated(unsafe) private static let cache: NSCache<NSString, CachedText> = {
        let cache = NSCache<NSString, CachedText>()
        cache.countLimit = 512
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()

    struct Link {
        let range: NSRange
        let title: String
        let url: URL
    }

    static func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func videoRoute(_ url: URL) -> VideoDetailRoute? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let token: String
        if scheme == "bilibili", host == "video" {
            token = url.pathComponents.dropFirst().first ?? ""
        } else if ["http", "https"].contains(scheme ?? ""),
                  ["bilibili.com", "www.bilibili.com", "m.bilibili.com"].contains(host ?? ""),
                  url.pathComponents.count >= 3, url.pathComponents[1] == "video" {
            token = url.pathComponents[2]
        } else { return nil }
        // Part/time parameters must not silently open the wrong part/position.
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if query.contains(where: { ["p", "t", "start_progress"].contains($0.name) }) { return nil }
        if token.range(of: #"^BV[1-9A-HJ-NP-Za-km-z]{10}$"#, options: .regularExpression) != nil {
            return VideoDetailRoute(bvid: token)
        }
        let digits = token.hasPrefix("av") ? String(token.dropFirst(2)) : token
        if let aid = Int(digits), let bvid = VideoIdentifier.bvid(aid: aid) {
            return VideoDetailRoute(bvid: bvid, aid: aid)
        }
        return nil
    }

    static func links(in text: String, metadata: [String: CommentJumpLink], includesTimes: Bool) -> [Link] {
        let source = text as NSString
        let full = NSRange(location: 0, length: source.length)
        var links: [Link] = []
        func insert(_ range: NSRange, title: String, url: URL) {
            guard !links.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else { return }
            links.append(Link(range: range, title: title, url: url))
        }
        for (token, value) in metadata.sorted(by: { $0.key.count > $1.key.count || ($0.key.count == $1.key.count && $0.key < $1.key) }) {
            guard !token.isEmpty else { continue }
            let appURL = value.appURLSchema.flatMap(URL.init(string:))
            let destination = appURL.flatMap { videoRoute($0) == nil ? nil : $0 } ?? webURL(token)
            guard let destination else { continue }
            var search = full
            while search.length > 0 {
                let range = source.range(of: token, range: search)
                guard range.location != NSNotFound else { break }
                let title = value.title.flatMap { $0.isEmpty ? nil : $0 } ?? token
                insert(range, title: title, url: destination)
                search = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
            }
        }
        for match in detector.matches(in: text, range: full) {
            guard let url = match.url, webURL(url.absoluteString) != nil else { continue }
            insert(match.range, title: source.substring(with: match.range), url: url)
        }
        for match in videoID.matches(in: text, range: full) {
            let token = source.substring(with: match.range)
            insert(match.range, title: token, url: URL(string: "https://www.bilibili.com/video/\(token)")!)
        }
        if includesTimes {
            for match in CommentTimeLinks.matches(in: text) {
                insert(match.range, title: source.substring(with: match.range),
                       url: URL(string: "neobili://comment-time/\(match.seconds)")!)
            }
        }
        return links.sorted { $0.range.location < $1.range.location }
    }

    static func attributed(_ text: String, metadata: [String: CommentJumpLink], includesTimes: Bool) -> AttributedString {
        let fields = [text, String(includesTimes)] + metadata.sorted { $0.key < $1.key }
            .flatMap { [$0.key, $0.value.title ?? "", $0.value.appURLSchema ?? ""] }
        let key = fields.map { "\($0.utf16.count):\($0)" }.joined() as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let source = text as NSString
        var result = AttributedString()
        var cursor = 0
        for link in links(in: text, metadata: metadata, includesTimes: includesTimes) {
            result += AttributedString(source.substring(with: NSRange(location: cursor, length: link.range.location - cursor)))
            var span = AttributedString(link.title)
            span.link = link.url
            span.foregroundColor = .blue
            result += span
            cursor = NSMaxRange(link.range)
        }
        result += AttributedString(source.substring(from: cursor))
        cache.setObject(CachedText(result), forKey: key, cost: key.length * 8 + 128)
        return result
    }
}
