import Foundation

/// 一条弹幕的最小渲染必需信息。
/// mode 只保留能渲染的三类：1/2/3 滚动、4 底部、5 顶部；
/// 6/7/8/9（逆向、高级、代码、BAS）照 PiliPlus 的做法直接丢弃。
struct DanmakuItem: Sendable {
    let time: TimeInterval
    let text: String
    let isScroll: Bool
    let isTop: Bool
    let color: UInt32

    init(time: TimeInterval, text: String, mode: Int, color: UInt32) {
        self.time = time
        self.text = text
        self.isScroll = mode == 1 || mode == 2 || mode == 3
        self.isTop = mode == 5
        self.color = color
    }
}

enum DanmakuSettings {
    static let fontScaleKey = "danmaku.fontScale"
    static let opacityKey = "danmaku.opacity"
    static let blockTopKey = "danmaku.blockTop"
    static let blockBottomKey = "danmaku.blockBottom"
    static let coloredEnabledKey = "danmaku.colored.enabled"
    static let videoEnabledKey = "danmaku.video.enabled"
    static let liveEnabledKey = "danmaku.live.enabled"
    static let defaultValue = true

    static func isEnabled(_ defaults: UserDefaults = .standard, key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}

/// 拉取整段弹幕历史。XML 端点一次返回全部弹幕，不需要 WBI 签名；
/// 解析是纯 CPU 工作，整体留在非主线程执行。
enum DanmakuLoader {
    static let maximumItems = 20_000

    @concurrent static func load(cid: Int, session: URLSession = .shared) async throws -> [DanmakuItem] {
        guard cid > 0 else { return [] }
        guard let url = URL(string: "https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        return Self.parse(data)
    }

    /// list.so 返回 XML：<d p="时间,类型,字号,颜色,发送时间,池,哈希,弹幕id">文本</d>。
    /// 大视频的 XML 可达数 MB，XMLParser 事件式解析内存占用可控。
    nonisolated static func parse(_ data: Data) -> [DanmakuItem] {
        let parser = XMLParser(data: data)
        let delegate = ParserDelegate(limit: maximumItems)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        private let limit: Int
        private(set) var items: [DanmakuItem] = []
        private var pendingAttributes: [String: String]?
        private var text = ""

        init(limit: Int) { self.limit = limit }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            guard elementName == "d" else { return }
            pendingAttributes = attributes
            text.removeAll(keepingCapacity: true)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if pendingAttributes != nil { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard elementName == "d", let attributes = pendingAttributes else { return }
            pendingAttributes = nil
            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, items.count < limit else { return }
            let fields = attributes["p"]?.split(separator: ",", omittingEmptySubsequences: false)
            guard let timeField = fields?.first, let time = Double(timeField) else { return }
            let mode = fields?.count ?? 0 > 1 ? Int(fields![1]) ?? 1 : 1
            // 6/7/8/9（逆向、高级、代码、BAS）不渲染，与 PiliPlus 的映射一致。
            guard [1, 2, 3, 4, 5].contains(mode) else { return }
            let color = fields?.count ?? 0 > 3 ? UInt32(fields![3]) ?? 0xFF_FFFF : 0xFF_FFFF
            items.append(DanmakuItem(time: time, text: content, mode: mode, color: color))
        }
    }
}
