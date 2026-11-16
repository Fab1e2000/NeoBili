#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

final class SpaceHeaderLayoutTests: XCTestCase {
    @MainActor
    func testSpaceIndicatorsStartBelowProfileAndPickerOnBothPages() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let session = UUID()
        let emptyVideos = try JSONDecoder().decode(SpaceVideoPage.self, from: Data("{\"list\":{\"vlist\":[]}}".utf8))
        let card = SpaceCard(mid: 42, name: "测试 UP 主", face: "", sign: "个人主页滚动条布局", level: 6,
                             isVIP: false, banner: nil, follower: 100, followingCount: 20, likeCount: 300,
                             archiveCount: 0, isFollowing: false)
        let services = ApplicationServices(session: .init(currentID: { session }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }),
            community: .init(spaceCardOperation: { _ in card }, spaceProfileOperation: { _ in card },
                             spaceVideosOperation: { _, _ in emptyVideos }))
        let host = UIHostingController(rootView: NavigationStack {
            SpaceView(up: FollowedUp(mid: 42, uname: "测试 UP 主", face: "", hasUpdate: false), services: services, likeStore: VideoLikeStore())
        }.environment(AccountStore(monitorNetwork: false)).environment(NowPlayingStore()).environment(ActionFeedback())
            .environment(\.applicationServices, services).dynamicTypeSize(.xxxLarge))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(400))
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let picker = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UISegmentedControl }.first)
        for page in [0, 1] {
            picker.selectedSegmentIndex = page
            picker.sendActions(for: .valueChanged)
            window.overrideUserInterfaceStyle = page == 0 ? .light : .dark
            try await Task.sleep(for: .milliseconds(400))
            let list = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first {
                $0.alwaysBounceVertical && abs($0.convert($0.bounds, to: window).minX) < 1
            })
            let indicator = try await ScrollIndicatorSnapshot.frame(in: list, window: window)
            let pickerBottom = picker.convert(picker.bounds, to: window).maxY
            XCTAssertEqual(indicator.minY, pickerBottom + 8 + 3, accuracy: 2,
                           "Page \(page) must reserve the visible profile and the picker")
            add(ScrollIndicatorSnapshot.attachment(window: window, name: "space-indicator-page-\(page)-large"))
        }
    }

    func testPartiallyCollapsedHeaderAlignsBothPages() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 0, collapse: 120, headerHeight: 300), 120)
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 120, headerHeight: 300), 120)
    }

    func testPinnedHeaderPreservesDeeperPagePosition() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 300, headerHeight: 300), 700)
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 0, collapse: 300, headerHeight: 300), 300)
    }

    func testExpandedHeaderReturnsOtherPageToTop() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 0, headerHeight: 300), 0)
    }
}
