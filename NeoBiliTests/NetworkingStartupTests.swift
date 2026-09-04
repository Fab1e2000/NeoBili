import XCTest
@testable import NeoBili

final class NetworkingStartupTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return calendar
    }

    func testWBIMixinKeyIsReusedForTheWholeCalendarDay() throws {
        let savedAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 0, minute: 1))
        )
        let laterThatDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 23, minute: 59))
        )

        XCTAssertTrue(
            WBISigner.isCacheFresh(savedAt: savedAt, now: laterThatDay, calendar: calendar)
        )
    }

    func testWBIMixinKeyExpiresAcrossCalendarDayBoundary() throws {
        let savedAt = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 23, minute: 59))
        )
        let nextDay = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 0, minute: 1))
        )

        XCTAssertFalse(
            WBISigner.isCacheFresh(savedAt: savedAt, now: nextDay, calendar: calendar)
        )
    }
    // MARK: - WBI 查询值转义

    /// 签名和真正发出去的 URL 必须用同一套转义，而且要和服务端重算时用的
    /// 规则（encodeURIComponent：只放行字母数字和 `-_.~`）一致。
    ///
    /// 以前这里放行了 `, : / +`，`dm_img_inter` 里的逗号冒号就没被转义，
    /// 我们算的摘要和服务端算的对不上；宽松接口照常返回数据，UP 主投稿列表
    /// 这种严格接口直接回 -403。
    func testWBIQueryValueEncodingMatchesReferenceImplementation() throws {
        func encoded(_ value: String) throws -> String {
            try XCTUnwrap(value.addingPercentEncoding(withAllowedCharacters: .wbiQueryValueAllowed))
        }

        XCTAssertEqual(
            try encoded(#"{"ds":[],"wh":[0,0,0]}"#),
            "%7B%22ds%22%3A%5B%5D%2C%22wh%22%3A%5B0%2C0%2C0%5D%7D",
            "逗号和冒号必须转义"
        )
        XCTAssertEqual(try encoded("V2ViR0wg+YmVz/dA=="), "V2ViR0wg%2BYmVz%2FdA%3D%3D", "随机指纹里的 + 和 /")
        XCTAssertEqual(try encoded("C++"), "C%2B%2B", "搜索关键词里的加号")
        XCTAssertEqual(try encoded("猫 咪"), "%E7%8C%AB%20%E5%92%AA", "空格是 %20，不是 +")
        XCTAssertEqual(try encoded("已经-安全_的.值~"), "%E5%B7%B2%E7%BB%8F-%E5%AE%89%E5%85%A8_%E7%9A%84.%E5%80%BC~")
    }

}
