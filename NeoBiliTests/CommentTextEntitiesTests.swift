import XCTest
@testable import NeoBili

final class CommentTextEntitiesTests: XCTestCase {
    func testQuotesAndNumericEmojiDecodeAsPlainText() {
        XCTAssertEqual(CommentTextEntities.decode("&#34;你好&#34; &#128514; &#x1F602; &quot;ok&quot;"), "\"你好\" 😂 😂 \"ok\"")
        XCTAssertEqual(CommentTextEntities.decode("&#x1F468;&#8205;&#x1F4BB;"), "👨‍💻")
        XCTAssertEqual(CommentTextEntities.decode("&lt;b&gt;内容&lt;/b&gt; &amp;"), "<b>内容</b> &")
    }
    func testMalformedAndIntentionallyEscapedTextIsPreserved() {
        let text = "%#34 &#34 &unknown; &#xD800; &#1114112; &#0; 50% %22"
        XCTAssertEqual(CommentTextEntities.decode(text), text)
        XCTAssertEqual(CommentTextEntities.decode("&amp;#34;"), "&#34;")
    }
    func testCommentBodyAndEmoteKeysUseTheSameDecodedNames() throws {
        let json = Data(#"{"message":"&#91;表情&#34;包&#93; &#128514;","emote":{"[表情&quot;包]":{"url":"https://i0.hdslb.com/bfs/emote/example.png","meta":{"size":1}}}}"#.utf8)
        let content = try JSONDecoder().decode(CommentContent.self, from: json)
        XCTAssertEqual(content.message, "[表情\"包] 😂")
        XCTAssertNotNil(content.emote?["[表情\"包]"])
        XCTAssertTrue(content.pictures.isEmpty)
    }
}
