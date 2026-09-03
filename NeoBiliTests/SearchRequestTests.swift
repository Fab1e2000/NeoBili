import XCTest
@testable import NeoBili

final class SearchRequestTests: XCTestCase {
    func testSearchRequestIncludesGaiaValidationContext() throws {
        let parameters = SearchRequest.parameters(keyword: "猫 咪", page: 2)
        let headers = SearchRequest.headers(keyword: "猫 咪")

        XCTAssertEqual(parameters["keyword"], "猫 咪")
        XCTAssertEqual(parameters["page"], "2")
        XCTAssertEqual(parameters["page_size"], "20")
        XCTAssertEqual(parameters["platform"], "pc")
        XCTAssertEqual(parameters["search_type"], "video")
        XCTAssertEqual(parameters["web_location"], "1430654")
        XCTAssertEqual(headers["Origin"], "https://search.bilibili.com")

        let referer = try XCTUnwrap(headers["Referer"])
        let components = try XCTUnwrap(URLComponents(string: referer))
        XCTAssertEqual(components.host, "search.bilibili.com")
        XCTAssertEqual(components.queryItems?.first?.value, "猫 咪")
    }

    func testSearchRiskControlPayloadKeepsVoucher() throws {
        let data = Data(#"{"result":null,"v_voucher":"challenge"}"#.utf8)
        let response = try JSONDecoder().decode(SearchResultPage.self, from: data)

        XCTAssertNil(response.result)
        XCTAssertEqual(response.vVoucher, "challenge")
    }
}
