import XCTest
@testable import NeoBili

final class CommentTimeLinksTests: XCTestCase {
    func testMinutesHoursAndFullWidthColons() {
        XCTAssertEqual(CommentTimeLinks.matches(in: "开头 00:00，重点 02:35，结尾 1:02:03，还有 １２:３４ 不支持，03：20").map(\.seconds), [0, 155, 3723, 200])
    }
    func testInvalidSecondsAndPartialLongTimestampsAreNotLinked() {
        XCTAssertTrue(CommentTimeLinks.matches(in: "12:99 1:60:02 1000:20 12:345 1:02:03:04").isEmpty)
    }
    func testTimeInsideURLIsNotAPlaybackLink() {
        let text = "https://example.com/watch/12:34?t=01:23 正文 02:35"
        XCTAssertEqual(CommentTimeLinks.matches(in: text).map(\.seconds), [155])
    }
    func testUnicodeTextAndEmojiPreserveVisibleTextAndCorrectRange() throws {
        let text = "👨‍👩‍👧‍👦这里 02:35 很精彩[doge]"
        let match = try XCTUnwrap(CommentTimeLinks.matches(in: text).first)
        XCTAssertEqual((text as NSString).substring(with: match.range), "02:35")
        let attributed = CommentTimeLinks.attributed(text)
        XCTAssertEqual(String(attributed.characters), text)
        let links = attributed.runs.compactMap(\.link)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(CommentTimeLinks.seconds(from: try XCTUnwrap(links.first)), 155)
    }
    func testOnlyInternalTimeLinksAreHandled() {
        XCTAssertNil(CommentTimeLinks.seconds(from: URL(string: "https://example.com/155")!))
        XCTAssertNil(CommentTimeLinks.seconds(from: URL(string: "neobili://comment-time/-1")!))
    }
}
