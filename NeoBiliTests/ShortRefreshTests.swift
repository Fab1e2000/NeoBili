import XCTest
import UIKit
import SwiftUI
@testable import NeoBili

@MainActor
final class ShortRefreshTests: XCTestCase {
    func testSeventyPointFingerMovementArmsButDoesNotRefreshUntilRelease() {
        var state = ShortPullState()
        state.begin(atTop: true)
        state.update(x: 0, y: 69, threshold: 70)
        XCTAssertFalse(state.armed)
        state.update(x: 0, y: 70, threshold: 70)
        XCTAssertTrue(state.armed)
        XCTAssertTrue(state.finish(cancelled: false))
        XCTAssertFalse(state.finish(cancelled: false), "同一手势只能提交一次")
    }

    func testPushingBackAndCancellationDoNotRefresh() {
        var state = ShortPullState()
        state.begin(atTop: true)
        state.update(x: 0, y: 90, threshold: 70)
        state.update(x: 0, y: 50, threshold: 70)
        XCTAssertFalse(state.finish(cancelled: false))
        state.begin(atTop: true)
        state.update(x: 0, y: 90, threshold: 70)
        XCTAssertFalse(state.finish(cancelled: true))
    }

    func testScrollingWithinFeedAndHorizontalSwipeDoNotArm() {
        var state = ShortPullState()
        state.begin(atTop: false)
        state.update(x: 0, y: 200, threshold: 70)
        XCTAssertFalse(state.finish(cancelled: false))
        state.begin(atTop: true)
        state.update(x: 150, y: 90, threshold: 70)
        XCTAssertFalse(state.finish(cancelled: false))
    }

    func testThresholdUsesChosenValueAndClampsInvalidStorage() {
        var state = ShortPullState()
        state.begin(atTop: true)
        state.update(x: 0, y: 70, threshold: 100)
        XCTAssertFalse(state.armed)
        state.update(x: 0, y: 100, threshold: 100)
        XCTAssertTrue(state.armed)
        XCTAssertEqual(HomeRefreshSettings.clamped(-1), 40)
        XCTAssertEqual(HomeRefreshSettings.clamped(999), 140)
        XCTAssertEqual(HomeRefreshSettings.clamped(.nan), 70)
    }

    func testTabReselectionPreservesOriginalDelegate() async {
        let home = UIViewController()
        let other = UIViewController()
        let tab = UITabBarController()
        tab.setViewControllers([home, other], animated: false)
        tab.selectedIndex = 0
        let original = Delegate()
        tab.delegate = original
        let observer = HomeTabReselectionObserver.Coordinator()
        let reselected = expectation(description: "重复点击推荐")
        observer.onReselect = { reselected.fulfill() }
        observer.attach(from: home)
        XCTAssertTrue(tab.delegate === observer)
        XCTAssertTrue(observer.tabBarController(tab, shouldSelect: home))
        XCTAssertEqual(original.selectionChecks, 1)
        await fulfillment(of: [reselected], timeout: 1)
        tab.delegate?.tabBarController?(tab, didSelect: home)
        XCTAssertEqual(original.didSelectCount, 1, "SwiftUI 原 delegate 必须继续收到选择事件")
        observer.detach()
        XCTAssertTrue(tab.delegate === original)
    }

    func testModernSwiftUITabContainerConnectsReselectionObserver() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let reselected = expectation(description: "实际 SwiftUI 标签容器的新回调")
        let host = UIHostingController(rootView: TabView {
            Tab("推荐", systemImage: "house.fill") {
                NavigationStack { Text("推荐内容") }
                    .background {
                        HomeTabReselectionObserver { reselected.fulfill() }.frame(width: 0, height: 0)
                    }
            }
            Tab("我的", systemImage: "person.crop.circle") { Text("我的") }
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKey?.makeKey() }
        host.view.layoutIfNeeded()
        // 等待 SwiftUI 完成控制器挂载及延迟接入。
        try await Task.sleep(for: .milliseconds(300))
        func findTab(_ controller: UIViewController) -> UITabBarController? {
            if let tab = controller as? UITabBarController { return tab }
            return controller.children.compactMap(findTab).first
        }
        let tab = try XCTUnwrap(findTab(host))
        XCTAssertTrue(tab.delegate is HomeTabReselectionObserver.Coordinator)
        let first = try XCTUnwrap(tab.tabs.first)
        tab.selectedTab = first
        XCTAssertEqual(tab.delegate?.tabBarController?(tab, shouldSelectTab: first), true)
        await fulfillment(of: [reselected], timeout: 1)
    }

    func testSwiftUIScrollViewPreservesRefreshSpaceAcrossLayoutUpdates() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let state = HoldingState()
        let host = UIHostingController(rootView: HoldingFixture(state: state))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKey?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        func findScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.compactMap(findScroll).first
        }
        let scroll = try XCTUnwrap(findScroll(host.view))
        let originalTop = scroll.convert(.zero, to: host.view).y
        state.height = 70
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertEqual(scroll.convert(.zero, to: host.view).y, originalTop + 70, accuracy: 1)
        XCTAssertEqual(scroll.contentOffset.y, -scroll.adjustedContentInset.top, accuracy: 1)
        state.version += 1
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(scroll.convert(.zero, to: host.view).y, originalTop + 70, accuracy: 1)
        state.height = 0
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertEqual(scroll.convert(.zero, to: host.view).y, originalTop, accuracy: 1)
        XCTAssertEqual(scroll.contentOffset.y, -scroll.adjustedContentInset.top, accuracy: 1)
    }

    @Observable final class HoldingState {
        var height: CGFloat = 0
        var version = 0
    }
    private struct HoldingFixture: View {
        let state: HoldingState
        var body: some View {
            ScrollView {
                Color.clear.frame(height: 0)
                    .background {
                        ShortPullRefresh(threshold: 70, enabled: state.height == 0,
                                         onProgress: { _, _ in }, onRefresh: {})
                    }
                Text("内容 \(state.version)").frame(height: 1400)
            }
            .scrollDisabled(state.height > 0)
            .padding(.top, state.height)
            .animation(.easeOut(duration: 0.25), value: state.height)
        }
    }

    private final class Delegate: NSObject, UITabBarControllerDelegate {
        var selectionChecks = 0
        var didSelectCount = 0
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            selectionChecks += 1
            return true
        }
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            didSelectCount += 1
        }
    }
}
