import Foundation

struct SearchResultItem: Decodable, Identifiable, Hashable, VideoDimensionProviding {
    let bvid: String
    let title: String
    let author: String
    let pic: String
    let duration: String
    let play: Int
    var dimension: VideoDimension? = nil

    var id: String { bvid }

    /// Search results wrap the matched keyword in `<em>` tags; strip them for display.
    var plainTitle: String {
        title.replacingOccurrences(of: "<em class=\"keyword\">", with: "")
             .replacingOccurrences(of: "</em>", with: "")
    }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
}

struct SearchResultPage: Decodable {
    let result: [SearchResultItem]?
    let vVoucher: String?
    var numPages: Int? = nil

    enum CodingKeys: String, CodingKey {
        case result
        case vVoucher = "v_voucher"
        case numPages
    }
}

/// 搜索联想的响应。没有命中任何候选词时 `result` 会从对象退化成空数组，
/// 按对象硬解会直接抛错，所以这里解不出来就当作「没有候选词」。
struct SearchSuggestPayload: Decodable {
    let suggestions: [SearchSuggestion]

    private enum CodingKeys: String, CodingKey {
        case result
    }

    private struct ResultBody: Decodable {
        let tag: [SearchSuggestion]?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tags = (try? container.decode(ResultBody.self, forKey: .result))?.tag ?? []
        // 同一个词偶尔会出现两次，去重后才能直接当 ForEach 的标识用。
        var seen = Set<String>()
        suggestions = tags.filter { !$0.value.isEmpty && seen.insert($0.value).inserted }
    }
}

/// 一条搜索候选词。`name` 里带 `<em>` 高亮标签，展示只用 `value`。
struct SearchSuggestion: Decodable, Identifiable, Hashable {
    let value: String

    var id: String { value }

    enum CodingKeys: String, CodingKey {
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
    }

    init(value: String) {
        self.value = value
    }
}
