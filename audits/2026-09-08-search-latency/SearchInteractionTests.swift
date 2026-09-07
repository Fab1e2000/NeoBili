import XCTest

final class SearchInteractionTests: XCTestCase {
    func testSearchFocusClearSubmitAndCancel() {
        let app = XCUIApplication()
        app.launch()
        let field = app.searchFields["搜索视频"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("music")
        XCTAssertEqual(field.value as? String, "music")
        let clear = app.buttons["清空搜索"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.tap()
        XCTAssertEqual(field.value as? String, "搜索视频")
        field.typeText("music\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "music")
        field.tap()
        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "搜索视频")
        XCTAssertTrue(app.tabBars.buttons["推荐"].exists)
    }
}
