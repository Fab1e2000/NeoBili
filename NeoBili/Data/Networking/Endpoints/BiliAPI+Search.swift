import Foundation

extension BiliAPI {
    static func searchVideos(keyword: String, page: Int) async throws -> SearchResultPage {
        let response: SearchResultPage = try await APIClient.shared.get(
            path: "x/web-interface/wbi/search/type",
            params: SearchRequest.parameters(keyword: keyword, page: page),
            requiresWBI: true,
            additionalHeaders: SearchRequest.headers(keyword: keyword)
        )
        // 搜索风控与取流接口一样会返回 code=0，但 data 里只有挑战串。
        // 不能把这种响应解码成“没有搜索结果”，否则用户只会看到空页面。
        guard response.vVoucher == nil else {
            throw BiliAPIError.riskControlled
        }
        // video 分类里仍可能混入课堂推广卡，它们没有 bvid，不能进入普通
        // 视频详情页；同时过滤后可避免多个空字符串破坏 SwiftUI 的列表 ID。
        return SearchResultPage(result: response.result?.filter { !$0.bvid.isEmpty }, vVoucher: nil, numPages: response.numPages)
    }

    /// 输入过程中的候选词。
    ///
    /// 这个接口在 s.search.bilibili.com 上，返回体也没有站内那层
    /// `{code, message, data}` 信封：候选词直接挂在 `result.tag` 上，而且
    /// 一个都没命中时 `code` 会是 3、`result` 退化成空数组。所以这里走
    /// `getRaw`，由 `SearchSuggestPayload` 自己宽松地解。
    static func searchSuggestions(term: String) async throws -> [SearchSuggestion] {
        var components = URLComponents(string: "https://s.search.bilibili.com/main/suggest")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "main_ver", value: "v1"),
            // 传空值即可，服务端仍会在 name 里加高亮标签，我们只用 value。
            URLQueryItem(name: "highlight", value: "")
        ]
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        let payload: SearchSuggestPayload = try await APIClient.shared.getRaw(
            url: url,
            additionalHeaders: SearchRequest.headers(keyword: term)
        )
        return payload.suggestions
    }
}

/// B 站搜索接口会同时检查 WBI 参数、页面位置和来源站点。这里集中生成请求，
/// 避免以后改搜索分页时漏掉其中一项又落入 Gaia 风控。
enum SearchRequest {
    static func parameters(keyword: String, page: Int) -> [String: String] {
        [
            "keyword": keyword,
            "page": String(page),
            "page_size": "20",
            "platform": "pc",
            "search_type": "video",
            "web_location": "1430654"
        ]
    }

    static func headers(keyword: String) -> [String: String] {
        var components = URLComponents(string: "https://search.bilibili.com/video")!
        components.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return [
            "Origin": "https://search.bilibili.com",
            "Referer": components.url?.absoluteString ?? "https://search.bilibili.com/video"
        ]
    }
}
