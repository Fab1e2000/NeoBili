#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class HomeFeedGapTests: XCTestCase {
    func testFilteredAdBorrowsNextNormalCardAndKeepsServerMetadata() throws {
        let items = [card(1), card(2, ad: true), card(3, large: true), card(4),
                     card(5), card(6, large: true), card(7)]
        let data = try JSONSerialization.data(withJSONObject: ["items": items])
        let page = try JSONDecoder().decode(AppRecommendationPage.self, from: data)
        let batch = page.batch(for: .init(source: .app), filter: .none)
        let rows = HomeFeedRow.group(batch.videos.map(HomeFeedItem.video))
        let displayed = displayedVideos(rows)

        XCTAssertEqual(batch.videos.map(\.aid), [1, 3, 4, 5, 6, 7])
        XCTAssertEqual(displayed.map(\.aid), [1, 4, 3, 5, 7, 6])
        XCTAssertEqual(displayed.map(\.recommendationPosition), [1, 4, 3, 5, 7, 6])
        XCTAssertEqual(batch.nextRequest?.appCursor, 7)
        XCTAssertEqual(batch.refreshCursor, 1)
        for video in displayed {
            XCTAssertEqual(video, batch.videos.first { $0.bvid == video.bvid })
        }
        assertCompleteNormalRows(rows)
    }

    func testConsecutiveLargeCardsStayFullWidthAndSingleRemainderMovesToEnd() {
        let values = [video(1), video(2, large: true), video(3, large: true), video(4),
                      video(5), video(6, large: true)]
        let rows = HomeFeedRow.group(values.map(HomeFeedItem.video))
        XCTAssertEqual(displayedVideos(rows).map(\.aid), [1, 4, 2, 3, 6, 5])
        XCTAssertEqual(rows.map(\.id), ["row-fixture-1", "row-fixture-2", "row-fixture-3", "row-fixture-6", "row-fixture-5"])
        XCTAssertEqual(displayedVideos(rows).filter(\.isLargeRecommendationCard).map(\.aid), [2, 3, 6])
    }

    func testRefreshMarkerStaysBetweenNewAndOldLargeCards() {
        let rows = HomeFeedRow.group([.video(video(1)), .video(video(2, large: true)), .lastSeen,
            .video(video(3, large: true)), .video(video(4)), .video(video(5)), .video(video(6))])
        XCTAssertEqual(rows.map(\.id), ["row-fixture-1", "row-fixture-2", "last-seen-row", "row-fixture-3", "row-fixture-5"])
        XCTAssertEqual(displayedVideos(rows).map(\.aid), [1, 4, 2, 3, 5, 6])
        assertCompleteNormalRows(rows)

        let noPartner = HomeFeedRow.group([.video(video(1)), .video(video(2, large: true)),
                                          .lastSeen, .video(video(3, large: true))])
        XCTAssertEqual(noPartner.map(\.id), ["row-fixture-2", "row-fixture-1", "last-seen-row", "row-fixture-3"],
                       "An unmatched new card must not move below the refresh boundary")
    }

    func testPackingIsIdempotentAndPreservesEachCardAndRelativeOrderWithinEachSize() {
        for mask in 0..<64 {
            let values = (0..<6).map { video($0, large: mask & (1 << $0) != 0) }
            for hasMarker in [false, true] {
                var items = values.map(HomeFeedItem.video)
                if hasMarker { items.insert(.lastSeen, at: 3) }
                let rows = HomeFeedRow.group(items)
                let displayed = displayedVideos(rows)
                XCTAssertEqual(displayed.count, values.count)
                XCTAssertEqual(Set(displayed.map(\.bvid)).count, values.count)
                XCTAssertEqual(displayed.filter(\.isLargeRecommendationCard), values.filter(\.isLargeRecommendationCard))
                XCTAssertEqual(displayed.filter { !$0.isLargeRecommendationCard }, values.filter { !$0.isLargeRecommendationCard })
                XCTAssertEqual(HomeFeedRow.group(HomeFeedRow.collectionItems(rows)), rows)
            }
        }
    }

    func testCollectionDeduplicatesBeforeFillingRows() throws {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let coordinator = HomeFeedCollection.Coordinator()
        coordinator.showsHeaderRow = false
        coordinator.attach(collection)
        coordinator.apply([.videos([video(1), video(1), video(2, large: true), video(3)])])
        let source = try XCTUnwrap(collection.dataSource as? UICollectionViewDiffableDataSource<HomeFeedCollection.Section, String>)
        XCTAssertEqual(source.snapshot().itemIdentifiers, [1, 3, 2].map { "video-fixture-\($0)" })
        XCTAssertEqual(source.snapshot().numberOfSections, 2)
    }

    func testRemovalAndPaginationDoNotChangeSourceOrderOrCursor() async {
        let session = UUID()
        var requests: [RecommendationRequest] = []
        let values = [video(1), video(2), video(3, large: true), video(4), video(5)]
        let model = HomeViewModel(source: .app, dislikeVideo: { _, _ in },
            currentAccount: { .init(hasAppCredential: false) }, currentSessionID: { session },
            fetchRecommendations: { request in
                requests.append(request)
                return requests.count == 1
                    ? .init(videos: values, nextRequest: request.next(appCursor: 99), refreshCursor: 10)
                    : .init(videos: [self.video(6)], nextRequest: nil)
            })
        await model.loadInitial()
        _ = await model.dislikeWebRecommendation(values[1], dislike: true)
        XCTAssertEqual(model.videos.map(\.aid), [1, 3, 4, 5])
        XCTAssertEqual(displayedVideos(model.feedRows).map(\.aid), [1, 4, 3, 5])
        await model.loadMoreIfNeeded(current: values[4])
        XCTAssertEqual(requests.map(\.appCursor), [0, 99])
        XCTAssertEqual(model.videos.map(\.aid), [1, 3, 4, 5, 6])
        XCTAssertEqual(displayedVideos(model.feedRows).map(\.aid), [1, 4, 3, 5, 6])
    }

    func testVisibleGapClosesAfterRemovalInLightDarkLargeTextAndLandscape() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        defer { previous?.makeKey() }
        let values = (1...8).map { video($0, large: $0 == 3 || $0 == 6) }
        for (name, size, scheme, textSize) in [
            ("light", CGSize(width: 402, height: 874), ColorScheme.light, DynamicTypeSize.large),
            ("dark", CGSize(width: 402, height: 874), .dark, .large),
            ("large-text", CGSize(width: 402, height: 874), .light, .xxxLarge),
            ("landscape", CGSize(width: 874, height: 402), .light, .large)
        ] {
            let session = UUID()
            let model = HomeViewModel(dislikeVideo: { _, _ in },
                currentAccount: { .init(hasAppCredential: false) }, currentSessionID: { session },
                fetchRecommendations: { _ in .init(videos: values, nextRequest: nil) })
            await model.loadInitial()
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: GapHarness(model: model)
                .environment(AccountStore(monitorNetwork: false))
                .environment(NowPlayingStore()).environment(ActionFeedback())
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, textSize)
                .environment(\.videoCardAnimationOverrides, .init(enter: false, exit: false)))
            window.frame = CGRect(origin: .zero, size: size)
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(200))
            let collection = try XCTUnwrap(findCollection(in: host.view))
            let source = try XCTUnwrap(collection.dataSource as? UICollectionViewDiffableDataSource<HomeFeedCollection.Section, String>)
            XCTAssertEqual(source.snapshot().numberOfItems, 8)
            _ = await model.dislikeWebRecommendation(values[1], dislike: true)
            for _ in 0..<100 {
                if source.snapshot().numberOfItems == 7 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            collection.layoutIfNeeded()
            XCTAssertEqual(source.snapshot().itemIdentifiers, [1, 4, 3, 5, 7, 6, 8].map { "video-fixture-\($0)" })
            for section in 0..<collection.numberOfSections {
                let ids = source.snapshot().itemIdentifiers(inSection: source.snapshot().sectionIdentifiers[section])
                let large = ids.first == "video-fixture-3" || ids.first == "video-fixture-6"
                if large {
                    XCTAssertEqual(ids.count, 1)
                    let frame = try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: section))).frame
                    XCTAssertEqual(frame.width, collection.bounds.width - 16, accuracy: 1)
                } else if section < collection.numberOfSections - 1 {
                    XCTAssertEqual(ids.count % 2, 0, "Every interior ordinary-card section must have complete rows")
                    let left = try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 0, section: section))).frame
                    let right = try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at: IndexPath(item: 1, section: section))).frame
                    XCTAssertEqual(left.minY, right.minY, accuracy: 1)
                    XCTAssertEqual(right.minX - left.maxX, HomeCardLayout.columnSpacing, accuracy: 1)
                }
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "home-gap-filled-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        (view as? UICollectionView) ?? view.subviews.lazy.compactMap { self.findCollection(in: $0) }.first
    }

    private func video(_ id: Int, large: Bool = false) -> VideoSummary {
        var value = VideoSummary(bvid: "fixture-\(id)", aid: id, cid: id,
            title: large ? "全宽大卡 \(id) · 保留原来的尺寸" : "普通推荐 \(id) · 自动补齐右侧空位",
            pic: "", desc: "", duration: 180, pubdate: 0,
            owner: .init(mid: 42, name: "测试 UP 主", face: ""),
            stat: .init(view: 12345, danmaku: 100, like: 200, favorite: 0, coin: 0, share: 0, reply: 0))
        value.isLargeRecommendationCard = large
        return value
    }

    private func displayedVideos(_ rows: [HomeFeedRow]) -> [VideoSummary] {
        rows.flatMap { row in if case .videos(let videos) = row { return videos }; return [] }
    }

    private func assertCompleteNormalRows(_ rows: [HomeFeedRow], file: StaticString = #filePath, line: UInt = #line) {
        for row in rows {
            guard case .videos(let videos) = row, videos.first?.isLargeRecommendationCard == false else { continue }
            XCTAssertEqual(videos.count, 2, "An available ordinary card must fill the right slot", file: file, line: line)
        }
    }

    private func card(_ id: Int, large: Bool = false, ad: Bool = false) -> [String: Any] {
        var result: [String: Any] = [
            "idx": id, "param": id, "bvid": "fixture-\(id)", "title": "推荐视频 \(id)",
            "cover": "https://example.invalid/\(id).jpg", "can_play": 1,
            "card_goto": large ? "inline_av_v2" : "av",
            "card_type": large ? "large_cover_v9" : "small_cover_v9",
            "args": ["up_id": 42, "up_name": "测试 UP 主"],
            "player_args": ["aid": id, "cid": id, "duration": 180],
            "track_id": "fixture-track-\(id)", "report_flow_data": "fixture-flow-\(id)"
        ]
        if ad { result["ad_info"] = ["id": id] }
        return result
    }
}

private struct GapHarness: View {
    let model: HomeViewModel
    @State private var safeInsets = EdgeInsets()
    private let controller = HomeFeedScrollController()

    var body: some View {
        NavigationStack {
            HomeFeedCollection(rows: model.feedRows, viewModel: model, hidesPortraitVideos: false,
                isRefreshing: false, isInteractionEnabled: true, refreshDistance: 100,
                controller: controller, onRefresh: {}, onOpenLastSeen: {},
                pinsTitleBar: true, safeInsets: safeInsets)
                .ignoresSafeArea()
                .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { safeInsets = $0 }
                .rootPageChrome(title: "推荐")
                .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}
