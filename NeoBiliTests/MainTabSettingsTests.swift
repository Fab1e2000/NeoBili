import XCTest
@testable import NeoBili

final class MainTabSettingsTests: XCTestCase {
    func testCacheIsVisibleByDefaultAndAddedToExistingDefaultOrder() {
        let expected: [MainTab] = [.home, .live, .following, .offlineCache]
        XCTAssertEqual(MainTabSettings.visible(order: "", hidden: nil), expected)
        XCTAssertEqual(MainTabSettings.visible(order: "home,live,following,watchLater,favorites,history", hidden: nil), expected)
        XCTAssertEqual(MainTabSettings.launchTab(from: "offlineCache", visible: expected), .offlineCache)
    }

    func testRevealingCachePreservesTabLimitAndStoredPreferences() {
        let order = "history,favorites,home,following,live,offlineCache,watchLater"
        let hidden = "live,offlineCache,watchLater"
        XCTAssertEqual(MainTabSettings.visible(order: order, hidden: hidden), [.history, .favorites, .home, .following])
        XCTAssertEqual(MainTabSettings.visible(order: order, hidden: hidden, revealing: .offlineCache), [.history, .favorites, .home, .offlineCache])
        XCTAssertEqual(MainTabSettings.visible(order: order, hidden: hidden), [.history, .favorites, .home, .following])
    }
}
