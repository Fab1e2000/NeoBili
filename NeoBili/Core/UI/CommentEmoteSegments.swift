import Foundation

/// 只缓存文本分段，不缓存 Text 或表情图片，图片加载和字号变化仍由视图独立观察。
@MainActor
enum CommentEmoteSegments {
    enum Segment: Equatable {
        case text(String)
        case emote(String, CommentEmote)
    }

    private struct Inputs: Hashable {
        let message: String
        let emotes: [String: CommentEmote]
    }

    private final class Key: NSObject {
        let inputs: Inputs
        init(_ inputs: Inputs) { self.inputs = inputs }
        override var hash: Int { inputs.hashValue }
        override func isEqual(_ object: Any?) -> Bool {
            (object as? Key)?.inputs == inputs
        }
    }

    private final class Value {
        let segments: [Segment]
        init(_ segments: [Segment]) { self.segments = segments }
    }

    private static let cache: NSCache<Key, Value> = {
        let cache = NSCache<Key, Value>()
        cache.countLimit = 256
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()

    static func prepared(message: String, emotes: [String: CommentEmote]) -> [Segment] {
        guard !emotes.isEmpty else { return [.text(message)] }
        let key = Key(Inputs(message: message, emotes: emotes))
        if let cached = cache.object(forKey: key) { return cached.segments }
        let result = parse(message: message, emotes: emotes)
        let cost = message.utf8.count * 2 + emotes.reduce(0) {
            $0 + $1.key.utf8.count + $1.value.url.utf8.count + 64
        }
        cache.setObject(Value(result), forKey: key, cost: cost)
        return result
    }

    private static func parse(message: String, emotes: [String: CommentEmote]) -> [Segment] {
        var result: [Segment] = []
        var plain = ""
        var index = message.startIndex
        // 同一个闭括号只查找一次；连续的未知开括号不会反复扫描整段余文。
        var nextClose: String.Index?
        while index < message.endIndex {
            guard message[index] == "[" else {
                plain.append(message[index])
                index = message.index(after: index)
                continue
            }
            if nextClose == nil || nextClose! < index {
                nextClose = message[index...].firstIndex(of: "]")
            }
            guard let close = nextClose else {
                plain.append(contentsOf: message[index...])
                break
            }
            let literal = String(message[index...close])
            if let emote = emotes[literal] {
                if !plain.isEmpty {
                    result.append(.text(plain))
                    plain = ""
                }
                result.append(.emote(literal, emote))
                index = message.index(after: close)
            } else {
                plain.append(message[index])
                index = message.index(after: index)
            }
        }
        if !plain.isEmpty { result.append(.text(plain)) }
        return result
    }
}
