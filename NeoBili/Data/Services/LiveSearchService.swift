#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension SearchService {
    public static func live(client: APIClient) -> Self {
        Self(hotSearches: {
            let payload: HotSearchPayload = try await client.getRaw(url: URL(string: "https://s.search.bilibili.com/main/hotword")!,
                                    additionalHeaders: SearchRequest.headers(keyword: ""))
            guard payload.code == 0 else {
                throw BiliAPIError.apiError(code: payload.code, message: String(localized: "热搜暂时不可用"))
            }
            return payload.list
        },
            searchVideosOperation: { keyword, page in
                try await BiliAPI.searchVideos(keyword: keyword, page: page, client: client)
            },
            searchSuggestionsOperation: { term in
                try await BiliAPI.searchSuggestions(term: term, client: client)
            }
        )
    }
}

struct HotSearchPayload: Decodable {
    let code: Int
    let list: [HotSearchItem]
}
