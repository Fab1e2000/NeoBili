#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

/// 推荐页放进原生导航栏（大标题 + 下滑收起）后，列表的布局不能陷入自我失效的递归。
@MainActor
final class HomeFeedNavigationBarTests: XCTestCase {
    /// 与 `HomeView.feed` 相同的接法：列表忽略安全区，外层量出安全区再交给列表。
    private struct Host: View {
        let rows: [HomeFeedRow]
        let viewModel: HomeViewModel
        let controller: HomeFeedScrollController
        @State private var safeInsets = EdgeInsets()

        var body: some View {
            NavigationStack {
                HomeFeedCollection(rows: rows, viewModel: viewModel, hidesPortraitVideos: false, isRefreshing: false,
                                   isInteractionEnabled: true, refreshDistance: 100,
                                   controller: controller, onRefresh: {}, onOpenLastSeen: {},
                                   pinsTitleBar: true, safeInsets: safeInsets)
                    .ignoresSafeArea()
                    .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { safeInsets = $0 }
                    .rootPageChrome(title: "推荐")
                    .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }

    func testScrollingUnderTheNativeNavigationBarDoesNotRecurseInLayout() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let videos = (1...60).map { index in
            VideoSummary(bvid: "nav-test-\(index)", aid: index, cid: index, title: "测试视频 \(index)",
                         pic: "", desc: "", duration: 60, pubdate: 0,
                         owner: VideoOwner(mid: 1, name: "测试", face: ""),
                         stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        }
        let model = HomeViewModel(fetchRecommendations: { _ in RecommendationBatch(videos: [], nextRequest: nil) })
        let controller = HomeFeedScrollController()
        let host = UIHostingController(rootView:
            Host(rows: HomeFeedRow.group(videos.map { .video($0) }), viewModel: model, controller: controller)
                .environment(AccountStore(monitorNetwork: false))
                .environment(NowPlayingStore())
                .environment(ActionFeedback()))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(400))
        func collection(in view: UIView) -> UICollectionView? {
            if let result = view as? UICollectionView { return result }
            return view.subviews.lazy.compactMap { collection(in: $0) }.first
        }
        let feed = try XCTUnwrap(collection(in: host.view))
        let top = -feed.adjustedContentInset.top
        // 向下滚、回滚几个来回，每步都让布局和导航栏有机会响应。
        for _ in 0..<3 {
            for step in 0..<40 {
                feed.setContentOffset(CGPoint(x: 0, y: top + CGFloat(step) * 45), animated: false)
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(8))
            }
            for step in stride(from: 39, through: 0, by: -1) {
                feed.setContentOffset(CGPoint(x: 0, y: top + CGFloat(step) * 45), animated: false)
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(8))
            }
        }
        XCTAssertEqual(feed.contentOffset.y, top, accuracy: 2)
    }

    /// 回归：自适应高度的「上次看到这里」分隔条不能随它与安全区的重叠量改变高度。
    /// 原生导航栏让列表有了顶部/底部安全区后，分隔条滑进安全区带时 SwiftUI 会给它加上内边距，
    /// 高度变化 → 内容尺寸变化 → 布局失效，边界附近来回滑动时形成递归，最终被 UIKit 断言终止。
    func testLastSeenMarkerHeightIsIndependentOfSafeAreaOverlap() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        func video(_ index: Int) -> HomeFeedItem {
            .video(VideoSummary(bvid: "marker-test-\(index)", aid: index, cid: index, title: "测试视频 \(index)",
                                pic: "", desc: "", duration: 60, pubdate: 0,
                                owner: VideoOwner(mid: 1, name: "测试", face: ""),
                                stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)))
        }
        let items = (1...8).map(video) + [.lastSeen] + (9...40).map(video)
        let model = HomeViewModel(fetchRecommendations: { _ in RecommendationBatch(videos: [], nextRequest: nil) })
        let host = UIHostingController(rootView:
            Host(rows: HomeFeedRow.group(items), viewModel: model, controller: HomeFeedScrollController())
                .environment(AccountStore(monitorNetwork: false))
                .environment(NowPlayingStore())
                .environment(ActionFeedback()))
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(400))
        func collection(in view: UIView) -> UICollectionView? {
            if let result = view as? UICollectionView { return result }
            return view.subviews.lazy.compactMap { collection(in: $0) }.first
        }
        let feed = try XCTUnwrap(collection(in: host.view))
        XCTAssertGreaterThan(feed.safeAreaInsets.top, 0, "the native navigation bar must give the list a top safe area")
        let top = -feed.adjustedContentInset.top
        var sizes: [CGFloat] = []
        // 分隔条在第四行之后：整段慢速扫过，让它依次穿过顶部安全区带和屏幕。
        for step in 0..<120 {
            feed.setContentOffset(CGPoint(x: 0, y: top + CGFloat(step) * 12), animated: false)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(15))
            window.layoutIfNeeded()
            sizes.append(feed.contentSize.height)
        }
        let spread = (sizes.max() ?? 0) - (sizes.min() ?? 0)
        XCTAssertLessThan(spread, 1, "content height changed while scrolling: \(Set(sizes.map { Int($0) }).sorted())")
    }

    func testLastSeenHeightIsDeterministicAndFollowsTextSize() {
        let width: CGFloat = 402
        let standard = HomeCardLayout.lastSeenHeight(for: width, dynamicTypeSize: .large)
        XCTAssertEqual(standard, 44, accuracy: 4, "a single line plus 12pt padding, close to the old 44pt estimate")
        XCTAssertEqual(standard, HomeCardLayout.lastSeenHeight(for: width, dynamicTypeSize: .large), "same inputs give the same height")
        XCTAssertGreaterThan(HomeCardLayout.lastSeenHeight(for: width, dynamicTypeSize: .xxxLarge), standard)
        // 大字号下文字折行，窄屏比宽屏更高。
        XCTAssertGreaterThanOrEqual(HomeCardLayout.lastSeenHeight(for: 320, dynamicTypeSize: .accessibility3),
                                    HomeCardLayout.lastSeenHeight(for: 430, dynamicTypeSize: .accessibility3))
    }
}
