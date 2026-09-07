import XCTest
import SwiftUI
@testable import NeoBili

@MainActor
final class FollowingSidebarTests: XCTestCase {
    private func findCollection(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.compactMap { findCollection(in: $0) }.first
    }

    private func scrollViewCount(in view: UIView) -> Int {
        (view is UIScrollView ? 1 : 0) + view.subviews.reduce(0) { $0 + scrollViewCount(in: $1) }
    }

    func testBackgroundTracksFirstAndLastAvatarWithoutBlankEnds() {
        let first = FollowingSidebarLayout.occupiedBounds(count: 31, rowHeight: 64, offset: -192, viewport: 448)
        XCTAssertEqual(first.lowerBound, 184)
        XCTAssertEqual(first.upperBound, 448)
        let moved = FollowingSidebarLayout.occupiedBounds(count: 31, rowHeight: 64, offset: -179, viewport: 448)
        XCTAssertEqual(moved.lowerBound, first.lowerBound - 13)
        let last = FollowingSidebarLayout.occupiedBounds(count: 31, rowHeight: 64, offset: 1728, viewport: 448)
        XCTAssertEqual(last.lowerBound, 0)
        XCTAssertEqual(last.upperBound, 264)
        let single = FollowingSidebarLayout.occupiedBounds(count: 1, rowHeight: 64, offset: -192, viewport: 448)
        XCTAssertEqual(single, 184...264)
    }

    func testHeightFitsRequestedRowsAndAvailableSpace() {
        for count in FollowingSidebarLayout.counts {
            let height = FollowingSidebarLayout.height(count: count, available: 900)
            XCTAssertEqual(height / CGFloat(count), 64)
            XCTAssertLessThanOrEqual(FollowingSidebarLayout.height(count: count, available: 650), 602)
        }
        XCTAssertEqual(FollowingSidebarLayout.count(8), 7)
    }

    func testOutlineClipsCapsAndOnlyBulgesTowardContent() {
        let rect = CGRect(x: 0, y: 0, width: 88, height: 480)
        let path = FollowingSidebarShape(side: .left).path(in: rect)
        XCTAssertFalse(path.contains(CGPoint(x: 3, y: 3)), "胶囊顶角不能露出头像")
        XCTAssertFalse(path.contains(CGPoint(x: 52, y: 477)), "胶囊底角不能露出头像")
        XCTAssertFalse(path.contains(CGPoint(x: 75, y: 60)), "非焦点区域不能沿矩形边界露出头像")
        XCTAssertTrue(path.contains(CGPoint(x: 84, y: 240)), "选中区域向内容侧平滑突出")
        XCTAssertTrue(path.contains(CGPoint(x: 2, y: 240)), "屏幕侧边缘不能因独立圆形背景产生凹口")
    }

    func testLeftAndRightOutlinesMirrorAtEverySample() {
        let rect = CGRect(x: 0, y: 0, width: 88, height: 480)
        let left = FollowingSidebarShape(side: .left).path(in: rect)
        let right = FollowingSidebarShape(side: .right).path(in: rect)
        for y in stride(from: 1, to: 480, by: 7) {
            for x in stride(from: 1, to: 88, by: 3) {
                XCTAssertEqual(left.contains(CGPoint(x: x, y: y)), right.contains(CGPoint(x: 88 - x, y: y)))
            }
        }
    }

    func testRepeatedOpeningCentersFirstMiddleAndLastSelectionOnDevice() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.keyWindow
        // 缓存本地生成的测试头像，截图不依赖外网，也能检查图像实际裁切。
        for index in 1...30 {
            let avatar = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
                UIColor(hue: CGFloat(index % 8) / 8, saturation: 0.65, brightness: 0.85, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
                ("\(index)" as NSString).draw(at: CGPoint(x: 16, y: 20), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 30), .foregroundColor: UIColor.white
                ])
            }
            await BiliImageCache.shared.insert(avatar, for: URL(string: "https://example.invalid/sidebar-test/\(index).png")!)
        }
        let suite = "sidebar-tests-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let probe = SidebarProbe()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: SidebarFixture(probe: probe).defaultAppStorage(preferences))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        var persistentCollection: UICollectionView?
        for count in FollowingSidebarLayout.counts {
            preferences.set(count, forKey: FollowingSidebarLayout.countKey)
            for side in FollowingSidebarSide.allCases {
                for id: FollowingSelection.ID in [.all, .up(15), .up(30), .up(1), .up(15)] {
                    withAnimation(.snappy(duration: 0.28)) { probe.expanded = false }
                    // 在原退场动画尚未结束时再次打开，覆盖双层列表回归。
                    try await Task.sleep(for: .milliseconds(40))
                    probe.side = side
                    probe.selection = id
                    probe.distance = nil
                    withAnimation(.snappy(duration: 0.28)) { probe.expanded = true }
                    var distance: CGFloat = .infinity
                    for _ in 0..<30 {
                        try await Task.sleep(for: .milliseconds(50))
                        if let collection = findCollection(in: window),
                           let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
                            let index: Int
                            switch id { case .all: index = 0; case .up(let mid): index = mid }
                            distance = collection.contentOffset.y + collection.contentInset.top - CGFloat(index) * layout.itemSize.height
                            if abs(distance) < 1 { break }
                        }
                    }
                    XCTAssertLessThan(abs(distance), 1, "\(side) \(id) 重新展开后应实际居中")
                    XCTAssertEqual(probe.selection, id, "重新展开不能跳回第一位或旧焦点")
                    XCTAssertEqual(scrollViewCount(in: window), 1, "快速收起再展开不能残留第二层滚动列表")
                    let currentCollection = try XCTUnwrap(findCollection(in: window))
                    if let persistentCollection { XCTAssertTrue(persistentCollection === currentCollection, "收起和展开必须复用同一个列表") }
                    persistentCollection = currentCollection
                    if id == .all || id == .up(30) {
                        try await Task.sleep(for: .milliseconds(300))
                        let shot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                        let attachment = XCTAttachment(image: shot)
                        attachment.name = "sidebar-end-\(count)-\(side.rawValue)-\(id)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    if id == .up(15) {
                        let collection = try XCTUnwrap(findCollection(in: window))
                        let initialOffset = collection.contentOffset.y
                        probe.controller.beginExternalDrag()
                        probe.controller.moveExternalDrag(translation: -13, velocity: 0)
                        XCTAssertEqual(collection.contentOffset.y, initialOffset + 13, accuracy: 0.1, "触碰拖动 13pt 必须连续移动 13pt，不能逐格跳转")
                        probe.controller.moveExternalDrag(translation: 0, velocity: 0)
                        XCTAssertEqual(collection.contentOffset.y, initialOffset, accuracy: 0.1)
                        probe.controller.endExternalDrag()
                        let visible = collection.indexPathsForVisibleItems
                        XCTAssertEqual(Set(visible).count, visible.count)
                        let centers = visible.compactMap { collection.cellForItem(at: $0)?.center.y }.sorted()
                        for pair in zip(centers, centers.dropFirst()) {
                            XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 40, "头像布局不能堆叠")
                        }
                        try await Task.sleep(for: .milliseconds(300))
                        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: screenshot)
                        attachment.name = "sidebar-glass-\(count)-\(side.rawValue)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
        probe.expanded = false
        try await Task.sleep(for: .milliseconds(320))
        XCTAssertTrue(findCollection(in: window) === persistentCollection)
        let collapsed = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: collapsed)
        attachment.name = "sidebar-collapsed-persistent-avatar"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor @Observable
private final class SidebarProbe {
    var expanded = false
    var selection: FollowingSelection.ID = .all
    var side: FollowingSidebarSide = .left
    var distance: CGFloat?
    let controller = FollowingAvatarScrollController()
}

private struct SidebarFixture: View {
    @Bindable var probe: SidebarProbe
    private var items: [FollowingSelection] {
        [.all] + (1...30).map { .up(FollowedUp(mid: $0, uname: "关注的 UP 主 \($0)", face: "https://example.invalid/sidebar-test/\($0).png", hasUpdate: $0 % 3 == 0)) }
    }
    var body: some View {
        VStack {
            Color(uiColor: .systemGroupedBackground)
                .overlay {
                    FollowingCarousel(items: items, focusedID: $probe.selection, side: probe.side,
                                      isExpanded: $probe.expanded, onSettled: { _ in }, onOpenUp: { _ in }, controller: probe.controller)
                }
                .onPreferenceChange(FollowingSidebarAlignmentKey.self) { probe.distance = $0 }
            Text("关注页布局检查").padding()
        }
    }
}
