import XCTest

@MainActor
final class CommentLabUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        if app == nil { app = XCUIApplication() }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.textFields["comment.draft"].waitForExistence(timeout: 8))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAProfileDraftCopyAndDeleteReply() {
        launch(["--variant", "A", "--thread", "2"])
        let draft = app.textFields["comment.draft"]
        draft.tap()
        draft.typeText("weekend draft")
        XCTAssertEqual(draft.value as? String, "weekend draft")

        app.buttons["author.21"].tap()
        XCTAssertTrue(app.scrollViews["author.profile"].waitForExistence(timeout: 3))
        capture("author-profile")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.scrollViews["thread.list"].waitForExistence(timeout: 3))
        XCTAssertEqual(draft.value as? String, "weekend draft", "Returning from a profile must preserve the draft.")

        let mine = app.staticTexts["comment.message.22"]
        mine.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["comment.copy"].waitForExistence(timeout: 3))
        capture("A-menu")
        app.buttons["comment.copy"].tap()
        XCTAssertTrue(app.staticTexts["已复制全文"].waitForExistence(timeout: 3))

        mine.press(forDuration: 0.8)
        app.buttons["comment.delete"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        capture("delete-confirmation")
        app.alerts.buttons["删除"].tap()
        XCTAssertTrue(mine.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["全部回复 2"].exists)
        XCTAssertEqual(draft.value as? String, "weekend draft")
        capture("delete-success")
    }

    func testBActionSheetDeletionFailureAndSorting() {
        launch(["--variant", "B", "--thread", "2", "--delete-fails"])
        let mine = app.staticTexts["comment.message.22"]
        mine.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["删除评论"].waitForExistence(timeout: 3))
        capture("B-actions")
        app.buttons["删除评论"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 4))
        app.alerts.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["删除失败，请稍后重试"].waitForExistence(timeout: 4))
        XCTAssertTrue(mine.exists)
        XCTAssertTrue(app.staticTexts["全部回复 3"].exists)
        capture("delete-failure")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["sort.最新"].waitForExistence(timeout: 3))
        app.buttons["sort.最新"].tap()
        XCTAssertTrue(app.buttons["author.3"].waitForExistence(timeout: 3))
        capture("B-latest")
        let picture = app.buttons["comment.image.3"]
        if !picture.isHittable { app.scrollViews["comments.list"].swipeUp() }
        picture.tap()
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 3))
        capture("comment-image")
        app.buttons["关闭"].tap()
    }

    func testThreeVisualVariants() {
        for variant in ["A", "B", "C"] {
            for (appearance, flags) in [("light", [String]()), ("dark", ["--dark"]), ("large", ["--large"])] {
                launch(["--variant", variant] + flags)
                XCTAssertTrue(app.buttons["lab.settings"].waitForExistence(timeout: 3))
                capture("\(variant)-\(appearance)")
                if appearance == "large" {
                    app.scrollViews["comments.list"].swipeUp()
                    capture("\(variant)-large-replies")
                }
            }
        }
        launch(["--variant", "B", "--dynamic"])
        capture("dynamic-comments")
        launch(["--variant", "C", "--thread", "2", "--dark"])
        capture("C-thread-dark")
    }

    func testPreviewProfileActionsAndRefreshPreserveDraft() {
        launch(["--variant", "B", "--dynamic"])
        let draft = app.textFields["comment.draft"]
        draft.tap()
        draft.typeText("refresh draft")

        let preview = app.staticTexts["reply.preview.21"]
        let list = app.scrollViews["comments.list"]
        if !preview.isHittable { list.swipeUp() }
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.18)).tap()
        XCTAssertTrue(app.scrollViews["author.profile"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(draft.value as? String, "refresh draft")

        let ownPreview = app.staticTexts["reply.preview.22"]
        if !ownPreview.isHittable { list.swipeUp() }
        ownPreview.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["删除评论"].waitForExistence(timeout: 3), "The actions must belong to the reply, not its parent.")
        app.buttons["取消"].tap()
        XCTAssertTrue(list.waitForExistence(timeout: 3), "Long press must not also open the author's profile.")

        let header = app.staticTexts["山里的风，和一个不赶时间的下午。🌿"]
        if !header.isHittable { list.swipeDown() }
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        // The toast can expire while XCTest waits for the refresh-control animation.
        // Check the persistent accessible completion state instead.
        let refreshed = expectation(for: NSPredicate(format: "value == %@", "评论已刷新"), evaluatedWith: list)
        wait(for: [refreshed], timeout: 4)
        XCTAssertEqual(draft.value as? String, "refresh draft")
        capture("refresh-preserves-draft")
    }
}
