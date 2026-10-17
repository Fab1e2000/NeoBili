import Foundation

public struct SearchResultItem: Decodable, Identifiable, Hashable, VideoDimensionProviding {
    public let bvid: String
    public let title: String
    public let author: String
    public let pic: String
    public let duration: String
    public let play: Int
    public var dimension: VideoDimension? = nil

    public var id: String { bvid }

    /// Search results wrap the matched keyword in `<em>` tags; strip them for display.
    public var plainTitle: String {
        title.replacingOccurrences(of: "<em class=\"keyword\">", with: "")
             .replacingOccurrences(of: "</em>", with: "")
    }

    public var secureCoverURL: URL? { URL.biliSecure(pic) }
}

public struct SearchResultPage: Decodable {
    public let result: [SearchResultItem]?
    public let vVoucher: String?
    public var numPages: Int? = nil

    enum CodingKeys: String, CodingKey {
        case result
        case vVoucher = "v_voucher"
        case numPages
    }

    public init(
        result: [SearchResultItem]? = nil,
        vVoucher: String? = nil,
        numPages: Int? = nil
    ) {
        self.result = result
        self.vVoucher = vVoucher
        self.numPages = numPages
    }
}

/// 搜索联想的响应。没有命中任何候选词时 `result` 会从对象退化成空数组，
/// 按对象硬解会直接抛错，所以这里解不出来就当作「没有候选词」。
public struct SearchSuggestPayload: Decodable {
    public let suggestions: [SearchSuggestion]

    private enum CodingKeys: String, CodingKey {
        case result
    }

    private struct ResultBody: Decodable {
        let tag: [SearchSuggestion]?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tags = (try? container.decode(ResultBody.self, forKey: .result))?.tag ?? []
        // 同一个词偶尔会出现两次，去重后才能直接当 ForEach 的标识用。
        var seen = Set<String>()
        suggestions = tags.filter { !$0.value.isEmpty && seen.insert($0.value).inserted }
    }
}

/// 一条搜索候选词。`name` 里带 `<em>` 高亮标签，展示只用 `value`。
public struct SearchSuggestion: Decodable, Identifiable, Hashable {
    public let value: String

    public var id: String { value }

    enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }

    public init(value: String) {
        self.value = value
    }
}
