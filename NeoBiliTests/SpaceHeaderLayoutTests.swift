@testable import NeoBiliDomain
import SwiftUI
import XCTest
@testable import NeoBili

final class SpaceHeaderLayoutTests: XCTestCase {
    @MainActor
    func testSpaceIndicatorsStartBelowProfileAndPickerOnAllThreePages() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let session = UUID()
        let emptyVideos = try JSONDecoder().decode(SpaceVideoPage.self, from: Data("{\"list\":{\"vlist\":[]}}".utf8))
        let emptyCollections = try JSONDecoder().decode(SpaceCollectionListPage.self, from: Data(#"{"items_lists":{}}"#.utf8))
        let emptyDynamics = try JSONDecoder().decode(DynamicFeedPage.self, from: Data(#"{"items":[],"has_more":false}"#.utf8))
        let card = SpaceCard(mid: 42, name: "测试 UP 主", face: "", sign: "个人主页滚动条布局", level: 6,
                             isVIP: false, banner: nil, follower: 100, followingCount: 20, likeCount: 300,
                             archiveCount: 0, isFollowing: false)
        let services = ApplicationServices(session: .init(currentID: { session }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }),
            community: .init(spaceDynamicsOperation: { _, _ in emptyDynamics },
                             spaceCardOperation: { _ in card }, spaceProfileOperation: { _ in card },
                             spaceVideosOperation: { _, _ in emptyVideos },
                             spaceCollectionsOperation: { _, _ in emptyCollections }))
        let stores = ApplicationStores(likes: VideoLikeStore(), followingRead: FollowingReadStore(), searchHistory: SearchHistory())
        let host = UIHostingController(rootView: NavigationStack {
            SpaceView(up: FollowedUp(mid: 42, uname: "测试 UP 主", face: "", hasUpdate: false))
        }.environment(AccountStore(likeStore: stores.likes, monitorNetwork: false)).environment(NowPlayingStore()).environment(ActionFeedback())
            .environment(\.applicationServices, services).environment(\.applicationStores, stores).dynamicTypeSize(.xxxLarge))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(400))
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let picker = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual((0..<picker.numberOfSegments).map { picker.titleForSegment(at: $0) }, ["投稿", "合集", "动态"])
        for page in [0, 1, 2, 0] {
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

    func testPartiallyCollapsedHeaderAlignsAllThreePages() {
        let offsets: [CGFloat] = [0, 120, 700]
        XCTAssertEqual(offsets.map {
            SpaceHeaderLayout.synchronizedOffset(pageOffset: $0, collapse: 120, headerHeight: 300)
        }, [120, 120, 120])
    }

    func testPinnedHeaderPreservesDeeperPagePosition() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 300, headerHeight: 300), 700)
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 0, collapse: 300, headerHeight: 300), 300)
    }

    func testExpandedHeaderReturnsOtherPageToTop() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 0, headerHeight: 300), 0)
    }
}
