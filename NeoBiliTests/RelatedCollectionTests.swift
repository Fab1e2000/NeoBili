import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class RelatedCollectionTests: XCTestCase {
    private func video(_ id: Int) -> VideoSummary {
        VideoSummary(bvid: "BV-related-test-\(id)", aid: id, cid: 0, title: "推荐视频 \(id)",
                     pic: "", desc: "", duration: 60, pubdate: 0,
                     owner: VideoOwner(mid: 1, name: "UP \(id)", face: ""),
                     stat: VideoStat(view: id, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
    }

    func testNativeRowRebindingAndSimpleCoinSymbol() {
        let row = NativeRelatedVideoCard.CardView(frame: CGRect(x: 0, y: 0, width: 360, height: 110))
        row.configure(video(1), typeSize: .large, scale: 3)
        row.layoutIfNeeded()
        XCTAssertTrue(row.accessibilityLabel?.contains("推荐视频 1") == true)
        row.configure(video(2), typeSize: .large, scale: 3)
        XCTAssertTrue(row.accessibilityLabel?.contains("推荐视频 2") == true)
        XCTAssertFalse(row.accessibilityLabel?.contains("UP 1") == true)
        XCTAssertNotNil(UIImage(systemName: "b.circle"))
        XCTAssertNotNil(UIImage(systemName: "b.circle.fill"))
    }

    func testCollectionVirtualizesRowsAndSizesHeaderWithoutExtraGap() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = VideoDescriptionScrollState()
        let content = VideoDescriptionCollection(videos: (1...80).map(video), components: [VideoDescriptionComponent("fixture", revision: [1]) { Color.clear.frame(height: 180) }],
                                                scrollState: state, onSelect: { _ in },
                                                consume: { _ in 0 }, end: {}, canConsume: { _ in false }, canContinue: { false })
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        func collection(in view: UIView) -> UICollectionView? {
            if let view = view as? UICollectionView { return view }
            return view.subviews.compactMap { collection(in: $0) }.first
        }
        let list = try XCTUnwrap(collection(in: host.view))
        list.layoutIfNeeded()
        XCTAssertEqual(list.numberOfItems(inSection: 1), 80)
        XCTAssertLessThan(list.visibleCells.count, 15, "Only visible cards should have live hosts")
        let header = try XCTUnwrap(list.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        let first = try XCTUnwrap(list.layoutAttributesForItem(at: IndexPath(item: 0, section: 1)))
        XCTAssertEqual(header.size.height, 180, accuracy: 1)
        XCTAssertEqual(first.frame.minY, header.frame.maxY, accuracy: 1)
        XCTAssertEqual(first.size.height, 110, accuracy: 1)
    }
    func testIntroductionExpansionKeepsOwnerCellAnchored() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let scroll = VideoDescriptionScrollState()
        func content(expanded: Bool) -> VideoDescriptionCollection {
            VideoDescriptionCollection(videos: [], components: [
                VideoDescriptionComponent("owner", revision: [1]) { Color.gray.frame(height: 80) },
                VideoDescriptionComponent(introduction:
                    VideoIntroductionCard(title: "测试简介", stat: video(1).stat, pubdate: 0,
                                          desc: Array(repeating: "展开后所有组件应保持一致的移动。", count: 4).joined(separator: "\n"),
                                          isExpanded: .constant(expanded))),
                VideoDescriptionComponent("actions", revision: [1]) { Color.blue.frame(height: 60) }
            ], scrollState: scroll, onSelect: { _ in }, consume: { _ in 0 }, end: {},
               canConsume: { _ in false }, canContinue: { false })
        }
        let host = UIHostingController(rootView: content(expanded: false))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(150))
        func collection(_ view: UIView) -> UICollectionView? {
            if let list = view as? UICollectionView { return list }
            return view.subviews.compactMap(collection).first
        }
        let list = try XCTUnwrap(collection(host.view))
        let ownerPath = IndexPath(item: 0, section: 0)
        let titlePath = IndexPath(item: 1, section: 0)
        let actionsPath = IndexPath(item: 2, section: 0)
        let owner = try XCTUnwrap(list.cellForItem(at: ownerPath))
        let ownerY = owner.frame.minY
        let originalHeight = try XCTUnwrap(list.layoutAttributesForItem(at: titlePath)).size.height
        let initialActionsY = try XCTUnwrap(list.cellForItem(at: actionsPath)).frame.minY
        var movementSamples: [CGFloat] = []
        host.rootView = content(expanded: true)
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(list.cellForItem(at: ownerPath) === owner)
            XCTAssertEqual(owner.layer.presentation()?.frame.minY ?? owner.frame.minY, ownerY, accuracy: 0.5)
            let title = try XCTUnwrap(list.cellForItem(at: titlePath))
            let actions = try XCTUnwrap(list.cellForItem(at: actionsPath))
            let titleFrame = title.layer.presentation()?.frame ?? title.frame
            let actionFrame = actions.layer.presentation()?.frame ?? actions.frame
            movementSamples.append(actionFrame.minY)
            XCTAssertEqual(actionFrame.minY, titleFrame.maxY, accuracy: 1, "Title resizing and following component movement must share one animation")
        }
        let expanded = try XCTUnwrap(list.layoutAttributesForItem(at: titlePath))
        let actions = try XCTUnwrap(list.layoutAttributesForItem(at: actionsPath))
        XCTAssertGreaterThan(expanded.size.height, originalHeight + 40)
        XCTAssertEqual(actions.frame.minY, expanded.frame.maxY, accuracy: 1)
        XCTAssertTrue(movementSamples.contains { $0 > initialActionsY + 1 && $0 < actions.frame.minY - 1 }, "Expansion should interpolate rather than jump directly to its final layout")
        host.rootView = content(expanded: false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(try XCTUnwrap(list.layoutAttributesForItem(at: titlePath)).size.height, originalHeight, accuracy: 1)
        XCTAssertEqual(owner.frame.minY, ownerY, accuracy: 0.5)
    }

    func testDetailAndRecommendationsCanArriveTogetherOrInEitherOrder() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let scroll = VideoDescriptionScrollState()
        func content(detail: Bool, recommendations: Bool) -> VideoDescriptionCollection {
            var components: [VideoDescriptionComponent] = []
            if detail {
                for id in ["owner", "introduction", "actions"] {
                    components.append(VideoDescriptionComponent(id, revision: [1]) { Color.clear.frame(height: 70) })
                }
            }
            if !recommendations {
                components.append(VideoDescriptionComponent("loading", revision: [1]) { ProgressView().frame(height: 50) })
            }
            return VideoDescriptionCollection(videos: recommendations ? (1...8).map(video) : [], components: components,
                                              scrollState: scroll, onSelect: { _ in }, consume: { _ in 0 }, end: {},
                                              canConsume: { _ in false }, canContinue: { false })
        }
        let host = UIHostingController(rootView: content(detail: false, recommendations: false))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        func collection(_ view: UIView) -> UICollectionView? {
            if let list = view as? UICollectionView { return list }
            return view.subviews.compactMap(collection).first
        }
        try await Task.sleep(for: .milliseconds(100))
        let list = try XCTUnwrap(collection(host.view))
        // Together, then details first, then recommendations first. Include
        // returning to loading so both insertion and removal are exercised.
        for (detail, recommendations) in [(true, true), (false, false), (true, false), (true, true),
                                         (false, false), (false, true), (true, true)] {
            host.rootView = content(detail: detail, recommendations: recommendations)
            try await Task.sleep(for: .milliseconds(100))
            list.layoutIfNeeded()
            XCTAssertEqual(list.numberOfItems(inSection: 0), (detail ? 3 : 0) + (recommendations ? 0 : 1))
            XCTAssertEqual(list.numberOfItems(inSection: 1), recommendations ? 8 : 0)
        }
    }

    func testBoundIntroductionExpandsWithoutRebindingItsComponent() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = IntroductionExpansionState()
        let host = UIHostingController(rootView: ReactiveIntroductionFixture(state: state, stat: video(1).stat))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(150))
        func collection(_ view: UIView) -> UICollectionView? {
            if let list = view as? UICollectionView { return list }
            return view.subviews.compactMap(collection).first
        }
        let list = try XCTUnwrap(collection(host.view))
        let path = IndexPath(item: 0, section: 0)
        let originalHeight = try XCTUnwrap(list.layoutAttributesForItem(at: path)).size.height
        func nativeTitle(_ view: UIView) -> UILabel? {
            if let label = view as? UILabel, label.accessibilityIdentifier == "video.introduction.title" { return label }
            return view.subviews.compactMap(nativeTitle).first
        }
        let label = try XCTUnwrap(nativeTitle(host.view))
        let initialFrame = label.convert(label.bounds, to: nil)
        let originalText = label.text
        let originalLayerY = try XCTUnwrap(label.layer.presentation()).convert(.zero, to: window.layer.presentation()).y
        func activateTitle() throws {
            let action = try XCTUnwrap(label.accessibilityCustomActions?.first)
            let target = try XCTUnwrap(action.target as? NSObject)
            XCTAssertTrue(target.responds(to: action.selector))
            _ = target.perform(action.selector)
        }
        try activateTitle()
        XCTAssertTrue(state.expanded, "The title's real action must update the binding")
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(nativeTitle(host.view) === label)
            XCTAssertEqual(label.text, originalText)
            let textLayer = try XCTUnwrap(label.layer.presentation())
            XCTAssertEqual(textLayer.convert(.zero, to: window.layer.presentation()).y, originalLayerY, accuracy: 0.5,
                           "Measure the actual native text layer, not its SwiftUI layout box")
            let current = label.convert(label.bounds, to: nil)
            XCTAssertEqual(current.minY, initialFrame.minY, accuracy: 1)
            XCTAssertEqual(current.height, initialFrame.height, accuracy: 1)
        }
        XCTAssertGreaterThan(try XCTUnwrap(list.layoutAttributesForItem(at: path)).size.height, originalHeight + 60)
        try activateTitle()
        XCTAssertFalse(state.expanded, "The same title action must collapse the body")
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(30))
            let textLayer = try XCTUnwrap(label.layer.presentation())
            XCTAssertEqual(textLayer.convert(.zero, to: window.layer.presentation()).y, originalLayerY, accuracy: 0.5)
        }
        XCTAssertEqual(try XCTUnwrap(list.layoutAttributesForItem(at: path)).size.height, originalHeight, accuracy: 1)
        for _ in 0..<6 {
            try activateTitle()
            try await Task.sleep(for: .milliseconds(45))
            let textLayer = try XCTUnwrap(label.layer.presentation())
            XCTAssertEqual(textLayer.convert(.zero, to: window.layer.presentation()).y, originalLayerY, accuracy: 0.5)
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(state.expanded)
        XCTAssertEqual(try XCTUnwrap(list.layoutAttributesForItem(at: path)).size.height, originalHeight, accuracy: 1)
    }

    func testHistoryCapsulesKeepNaturalWidthsAndWrap() {
        let frames = WrappingCapsuleLayout.arrange(sizes: [CGSize(width: 20, height: 40), CGSize(width: 60, height: 40),
                                                         CGSize(width: 40, height: 40), CGSize(width: 180, height: 40)],
                                                  width: 100, spacing: 8)
        XCTAssertEqual(frames.map(\.width), [20, 60, 40, 100])
        XCTAssertEqual(frames.map(\.minX), [0, 28, 0, 0])
        XCTAssertEqual(frames.map(\.minY), [0, 0, 40, 80])
    }

}

@MainActor @Observable private final class IntroductionExpansionState {
    var expanded = false
}


private struct ReactiveIntroductionFixture: View {
    let state: IntroductionExpansionState
    let stat: VideoStat
    @State private var scroll = VideoDescriptionScrollState()
    var body: some View {
        let card = VideoIntroductionCard(title: "标题的位置在展开和收起过程中应当保持不变", stat: stat, pubdate: 0,
            desc: Array(repeating: "展开的正文应向下延伸，不推动标题。", count: 5).joined(separator: "\n"),
            isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 }))
        VideoDescriptionCollection(videos: [], components: [VideoDescriptionComponent(introduction: card)],
            scrollState: scroll, onSelect: { _ in }, consume: { _ in 0 }, end: {},
            canConsume: { _ in false }, canContinue: { false })
    }
}
