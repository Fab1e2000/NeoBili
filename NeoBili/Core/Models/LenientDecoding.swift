import Foundation

/// 逐条解码的数组：解不出来的那一条直接跳过，其余照常返回。
///
/// 动态流一页里混着投稿、合集、直播预约、番剧等好几种结构，用普通的
/// `[T]` 解码时，只要有一条对不上，整页就会失败——用户看到的是一片
/// 「数据解析失败」。列表类接口一律走这个类型。
struct LenientList<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var collected: [Element] = []
        while !container.isAtEnd {
            let indexBefore = container.currentIndex
            if let element = try? container.decode(Element.self) {
                collected.append(element)
            } else {
                // 解不出来的那一条也必须消费掉，否则游标停在原地。
                _ = try? container.decode(IgnoredValue.self)
            }
            // 兜底：万一两次解码都没能推进游标，立刻停手，绝不在这里空转。
            if container.currentIndex == indexBefore { break }
        }
        elements = collected
    }
}

/// 只为了把一条解不动的数据「读掉」而存在，本身不保留任何内容。
private struct IgnoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// B 站有些字段同一个含义在不同接口、不同稿件上一会儿是数字、一会儿是
    /// 字符串（动态流的 `aid`、隐藏播放量时的 `--`），两种都试一遍。
    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
    }

    /// 同上，反过来：本该是文字的字段偶尔会回一个数字（动态 id、播放量）。
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    /// 开关字段有时是 true/false，有时是 1/0，也见过 "true"。
    func flexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return text == "true" || text == "1"
        }
        return nil
    }
}
