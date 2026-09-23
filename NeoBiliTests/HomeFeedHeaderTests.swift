import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class HomeFeedHeaderTests: XCTestCase {
    func testPullDownKeepsHeaderStationaryWhileCardsMoveAndUpwardScrollHidesHeader() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let videos = (1...16).map { index in
            VideoSummary(bvid: "header-test-\(index)", aid: index, cid: index, title: "测试视频",
                         pic: "", desc: "", duration: 60, pubdate: 0,
                         owner: VideoOwner(mid: 1, name: "测试", face: ""),
                         stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        }
        let model = HomeViewModel(fetchRecommendations: { _ in [] })
        let host = UIHostingController(rootView:
            HomeFeedCollection(rows: HomeFeedRow.group(videos.map { .video($0) }),
                               viewModel: model, hidesPortraitVideos: false, isRefreshing: false,
                               isInteractionEnabled: true, refreshDistance: 100,
                               controller: HomeFeedScrollController(), onRefresh: {}, onOpenLastSeen: {})
                .environment(AccountStore(monitorNetwork: false))
                .environment(NowPlayingStore())
                .environment(ActionFeedback())
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(200))
        func collection(in view: UIView) -> UICollectionView? {
            if let result = view as? UICollectionView { return result }
            return view.subviews.lazy.compactMap { collection(in: $0) }.first
        }
        let feed = try XCTUnwrap(collection(in: host.view))
        let top = -feed.adjustedContentInset.top
        feed.setContentOffset(CGPoint(x: 0, y: top), animated: false)
        feed.layoutIfNeeded()
        let header = try XCTUnwrap(feed.cellForItem(at: IndexPath(item: 0, section: 0)))
        let card = try XCTUnwrap(feed.cellForItem(at: IndexPath(item: 0, section: 1)))
        func screenY(_ view: UIView) -> CGFloat { view.convert(view.bounds, to: window).minY }
        let headerY = screenY(header)
        let cardY = screenY(card)

        for pull in [CGFloat(40), 120, 180, 60, 0] {
            feed.setContentOffset(CGPoint(x: 0, y: top - pull), animated: false)
            feed.layoutIfNeeded()
            XCTAssertEqual(screenY(header), headerY, accuracy: 1, "下拉及回弹中页头应保持原位")
            XCTAssertEqual(screenY(card), cardY + pull, accuracy: 1, "内容仍应跟随下拉")
        }
        feed.setContentOffset(CGPoint(x: 0, y: top + 30), animated: false)
        feed.layoutIfNeeded()
        XCTAssertEqual(screenY(header), headerY - 30, accuracy: 1, "向上浏览时不应吸顶")
        XCTAssertEqual(header.transform, .identity)
    }
}
