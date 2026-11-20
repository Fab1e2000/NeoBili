#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

/// 推荐页放进原生导航栏（大标题 + 下滑收起）后，列表的布局不能陷入自我失效的递归。
@MainActor
final class HomeFeedNavigationBarTests: XCTestCase {
    func testLoadingSkeletonUsesTheFeedCardDimensions() throws {
        for (width, height, scheme, textSize, leadingLargeCard) in [
            (CGFloat(408), CGFloat(650), ColorScheme.light, DynamicTypeSize.large, false),
            (CGFloat(800), CGFloat(430), ColorScheme.dark, DynamicTypeSize.accessibility3, false),
            (CGFloat(408), CGFloat(780), ColorScheme.dark, DynamicTypeSize.large, true)
        ] {
            let renderer = ImageRenderer(content: HomeFeedSkeleton(leadingLargeCard: leadingLargeCard)
                .frame(width: width, height: height)
                .background(Color(uiColor: .systemGroupedBackground))
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, textSize))
            let image = try XCTUnwrap(renderer.cgImage)
            func pixel(_ x: CGFloat, _ y: CGFloat) throws -> Data {
                let crop = try XCTUnwrap(image.cropping(to: CGRect(x: floor(x), y: floor(y), width: 1, height: 1)))
                return try XCTUnwrap(UIImage(cgImage: crop).pngData())
            }

            let cover = HomeCardLayout.coverSize(for: width)
            let left = HomeCardLayout.horizontalInset
            let right = width - left
            let firstRowTop = HomeCardLayout.verticalInset
            let largeCardBottom = firstRowTop + HomeCardLayout.largeCardHeight(for: width)
            let top = leadingLargeCard ? largeCardBottom + HomeCardLayout.rowSpacing : firstRowTop
            let coverBottom = top + cover.height
            let cardBottom = top + HomeCardLayout.cardHeight(for: width)
            let background = try pixel(width / 2, top + 16)
            let coverFill = try pixel(left + 16, top + 16)
            XCTAssertNotEqual(coverFill, background)
            XCTAssertEqual(try pixel(left + 1, top + 16), coverFill)
            XCTAssertEqual(try pixel(right - 2, top + 16), coverFill)
            XCTAssertEqual(try pixel(left - 1, top + 16), background)
            XCTAssertEqual(try pixel(right, top + 16), background)
            XCTAssertEqual(try pixel(left + 16, top - 1), background)
            XCTAssertEqual(try pixel(left + 16, coverBottom - 1), coverFill)
            XCTAssertNotEqual(try pixel(left + 16, coverBottom + 1), coverFill)
            XCTAssertNotEqual(try pixel(left + 16, cardBottom - 2), background)
            XCTAssertEqual(try pixel(left + 16, cardBottom + 2), background)
            XCTAssertEqual(try pixel(left + 16, cardBottom + HomeCardLayout.rowSpacing + 12), coverFill)

            if leadingLargeCard {
                let largeCoverBottom = firstRowTop + HomeCardLayout.largeCoverSize(for: width).height
                XCTAssertEqual(try pixel(width / 2, firstRowTop + 16), coverFill)
                XCTAssertEqual(try pixel(right - 2, firstRowTop + 16), coverFill)
                XCTAssertEqual(try pixel(left - 1, firstRowTop + 16), background)
                XCTAssertEqual(try pixel(width / 2, largeCoverBottom - 1), coverFill)
                XCTAssertNotEqual(try pixel(width / 2, largeCoverBottom + 1), coverFill)
                XCTAssertNotEqual(try pixel(width / 2, largeCardBottom - 2), background)
                XCTAssertEqual(try pixel(width / 2, largeCardBottom + 2), background)
            }
        }
    }

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
                                   safeInsets: safeInsets)
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
        let source = try XCTUnwrap(feed.dataSource as? UICollectionViewDiffableDataSource<HomeFeedCollection.Section, String>)
        XCTAssertEqual(source.snapshot().itemIdentifiers.first, HomeFeedItem.video(videos[0]).id)
        XCTAssertFalse(feed.topEdgeEffect.isHidden)
        let top = -feed.adjustedContentInset.top
        let indicator = try await ScrollIndicatorSnapshot.frame(in: feed, window: window)
        XCTAssertEqual(indicator.minY, feed.verticalScrollIndicatorInsets.top + 3, accuracy: 1,
                       "The navigation safe area must be applied to the indicator once")
        add(ScrollIndicatorSnapshot.attachment(window: window, name: "home-scroll-indicator-top"))
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
        window.overrideUserInterfaceStyle = .dark
        feed.setContentOffset(CGPoint(x: 0, y: feed.contentSize.height - feed.bounds.height + feed.contentInset.bottom), animated: false)
        let bottomIndicator = try await ScrollIndicatorSnapshot.frame(in: feed, window: window)
        // UIKit also reserves room for the display's rounded lower corners.
        let bottomLimit = max(feed.verticalScrollIndicatorInsets.bottom, window.safeAreaInsets.top)
        XCTAssertGreaterThanOrEqual(bottomIndicator.maxY, window.bounds.maxY - bottomLimit - 4,
                                    "The bottom safe area must be applied to the indicator once")
        add(ScrollIndicatorSnapshot.attachment(window: window, name: "home-scroll-indicator-bottom-dark"))
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
