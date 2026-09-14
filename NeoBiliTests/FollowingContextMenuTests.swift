import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// These fixtures exercise production menu delegates and preview views with
/// local data. Running them requires a connected device; no Simulator is used.
@MainActor
final class FollowingContextMenuTests: XCTestCase {
    func testLateLiveStateIsVisibleNearTopOfAlreadyExpandedSidebar() async throws {
        let fixture = try await makeFixture()
        defer { fixture.dismiss() }
        fixture.probe.additional = (3...30).map {
            FollowedUp(mid: $0, uname: "普通 UP \($0)", face: "", hasUpdate: false)
        }
        try await Task.sleep(for: .milliseconds(150))
        fixture.probe.additional[27].liveRoomID = 3000
        try await Task.sleep(for: .milliseconds(300))
        fixture.window.layoutIfNeeded()
        let live = try XCTUnwrap(fixture.collection.cellForItem(at: IndexPath(item: 2, section: 0)))
        XCTAssertTrue(live.accessibilityLabel?.contains("普通 UP 30，正在直播") == true)
        let image = UIGraphicsImageRenderer(bounds: fixture.window.bounds).image { _ in
            fixture.window.drawHierarchy(in: fixture.window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "late-live-avatar-badge"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testOnlyLiveUPsOfferLiveRoomActionAndBothOfferProfileAction() throws {
        let controller = FollowingAvatarScrollController()
        var additional: [FollowedUp] = []
    let live = FollowedUp(mid: 1, uname: "直播 UP", face: "", hasUpdate: false, liveRoomID: 100)
        let ordinary = FollowedUp(mid: 2, uname: "普通 UP", face: "", hasUpdate: true)
        let liveActions = controller.contextMenu(for: live).children.compactMap { $0 as? UIAction }
        let ordinaryActions = controller.contextMenu(for: ordinary).children.compactMap { $0 as? UIAction }
        XCTAssertEqual(liveActions.map(\.title), ["进入直播间", "查看 UP 主主页"])
        XCTAssertEqual(ordinaryActions.map(\.title), ["查看 UP 主主页"])
        XCTAssertTrue(liveActions.allSatisfy { $0.image != nil && !$0.attributes.contains(.disabled) })

        var openedLive: [Int] = []
        var openedProfiles: [Int] = []
        controller.onOpenLive = { openedLive.append($0.mid) }
        controller.onOpenUp = { openedProfiles.append($0.mid) }
        invoke(try XCTUnwrap(liveActions.first))
        invoke(try XCTUnwrap(ordinaryActions.first))
        XCTAssertEqual(openedLive, [1])
        XCTAssertEqual(openedProfiles, [2])
    }

    func testModernHighlightAndDismissalDelegatesLiftOnlyTransparentAvatarAndBadge() async throws {
        let fixture = try await makeFixture()
        defer { fixture.dismiss() }
        let controller = fixture.probe.controller
        let collection = fixture.collection
        let delegate: any UICollectionViewDelegate = controller
        for index in [1, 2] {
            let path = IndexPath(item: index, section: 0)
            let cell = try XCTUnwrap(collection.cellForItem(at: path))
            let configuration = try XCTUnwrap(controller.collectionView(
                collection, contextMenuConfigurationForItemsAt: [path], point: cell.center
            ))
            XCTAssertEqual(configuration.identifier as? NSNumber, NSNumber(value: index))
            // Invoke the iOS 16+ protocol methods, not the deprecated single-item
            // preview callbacks or a test-only cell helper.
            let highlight = try XCTUnwrap(delegate.collectionView?(
                collection, contextMenuConfiguration: configuration, highlightPreviewForItemAt: path
            ))
            let dismissal = try XCTUnwrap(delegate.collectionView?(
                collection, contextMenuConfiguration: configuration, dismissalPreviewForItemAt: path
            ))
            XCTAssertTrue(highlight.view === dismissal.view)
            for preview in [highlight, dismissal] {
                XCTAssertFalse(preview.view === cell)
                XCTAssertFalse(preview.view === cell.contentView)
                XCTAssertTrue(preview.view.isDescendant(of: cell.contentView))
                XCTAssertLessThan(preview.view.bounds.width, cell.contentView.bounds.width,
                                  "The preview must target the avatar host rather than the rectangular row")
                XCTAssertEqual(preview.parameters.backgroundColor.cgColor.alpha, 0, accuracy: 0.001)
                let visible = try XCTUnwrap(preview.parameters.visiblePath)
                let diameter = preview.view.bounds.width
                XCTAssertTrue(visible.contains(CGPoint(x: diameter / 2, y: diameter / 2)))
                XCTAssertFalse(visible.contains(CGPoint(x: 1, y: 1)), "The avatar's rectangle corners must remain transparent")
                if index == 1 {
                    XCTAssertTrue(visible.contains(CGPoint(x: diameter / 2, y: diameter * 1.05)),
                                  "The live badge must remain included in the lifted preview")
                    XCTAssertFalse(visible.contains(CGPoint(x: 1, y: diameter * 1.05)))
                } else {
                    XCTAssertEqual(visible.bounds.height, diameter, accuracy: 0.01)
                }
            }
        }
        XCTAssertNil(controller.collectionView(collection, contextMenuConfigurationForItemsAt: [IndexPath(item: 0, section: 0)], point: .zero),
                     "The all-dynamics item has no UP profile or live-room menu")
    }

    func testMenuLocksScrollingAndDefersNavigationUntilDismissAnimationCompletes() async throws {
        let fixture = try await makeFixture()
        defer { fixture.dismiss() }
        let controller = fixture.probe.controller
        let collection = fixture.collection
        let path = IndexPath(item: 1, section: 0)
        let configuration = try XCTUnwrap(controller.collectionView(
            collection, contextMenuConfigurationForItemsAt: [path], point: .zero
        ))
        XCTAssertTrue(collection.isScrollEnabled)
        let before = collection.contentOffset
        controller.collectionView(collection, willDisplayContextMenu: configuration, animator: nil)
        XCTAssertFalse(collection.isScrollEnabled)
        XCTAssertEqual(fixture.probe.menuStates, [true])
        controller.beginExternalDrag()
        controller.moveExternalDrag(translation: -70, velocity: 200)
        controller.endExternalDrag()
        XCTAssertEqual(collection.contentOffset, before, "The external drag path must also respect the menu lock")

        let action = try XCTUnwrap(controller.contextMenu(for: fixture.probe.live).children.first as? UIAction)
        invoke(action)
        XCTAssertTrue(fixture.probe.openedLive.isEmpty, "Selecting a menu action must not move the page underneath the lifted avatar")
        let animator = MenuCompletionFixture()
        controller.collectionView(collection, willEndContextMenuInteraction: configuration, animator: animator)
        XCTAssertFalse(collection.isScrollEnabled)
        XCTAssertTrue(fixture.probe.openedLive.isEmpty)
        XCTAssertEqual(animator.completionCount, 1)
        animator.finish()
        XCTAssertTrue(collection.isScrollEnabled)
        XCTAssertEqual(fixture.probe.menuStates, [true, false])
        XCTAssertEqual(fixture.probe.openedLive, [1])
        animator.finish()
        XCTAssertEqual(fixture.probe.openedLive, [1], "An action is consumed only once")

        controller.collectionView(collection, willDisplayContextMenu: configuration, animator: nil)
        controller.collectionView(collection, willEndContextMenuInteraction: configuration, animator: nil)
        XCTAssertTrue(collection.isScrollEnabled, "A cancelled menu with no animator must also unlock immediately")
        XCTAssertEqual(fixture.probe.menuStates, [true, false, true, false])
    }

    private func invoke(_ action: UIAction) {
        let button = UIButton(type: .system)
        button.addAction(action, for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)
    }

    private func makeFixture() async throws -> MenuWindowFixture {
        var scene: UIWindowScene?
        for _ in 0..<100 {
            scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if scene != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let activeScene = try XCTUnwrap(scene)
        let probe = MenuProbe()
        let window = UIWindow(windowScene: activeScene)
        let previous = activeScene.keyWindow
        window.frame = activeScene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: MenuSidebarFixture(probe: probe))
        window.makeKeyAndVisible()
        for _ in 0..<60 {
            window.layoutIfNeeded()
            if let collection = findCollection(window),
               collection.cellForItem(at: IndexPath(item: 2, section: 0)) != nil {
                return MenuWindowFixture(window: window, previous: previous, collection: collection, probe: probe)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKey()
        throw MenuFixtureError.layoutTimedOut
    }

    private func findCollection(_ view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.compactMap { findCollection($0) }.first
    }
}

private enum MenuFixtureError: Error { case layoutTimedOut }

@MainActor
private final class MenuCompletionFixture: NSObject, UIContextMenuInteractionAnimating {
    var previewViewController: UIViewController? { nil }
    private var completions: [() -> Void] = []
    var completionCount: Int { completions.count }
    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping () -> Void) { completions.append(completion) }
    func finish() {
        let pending = completions
        completions.removeAll()
        pending.forEach { $0() }
    }
}

@MainActor @Observable
private final class MenuProbe {
    var expanded = true
    var selection: FollowingSelection.ID = .up(1)
    let controller = FollowingAvatarScrollController()
    var additional: [FollowedUp] = []
    let live = FollowedUp(mid: 1, uname: "直播 UP", face: "", hasUpdate: false, liveRoomID: 100)
    @ObservationIgnored var menuStates: [Bool] = []
    @ObservationIgnored var openedLive: [Int] = []
}

private struct MenuSidebarFixture: View {
    @Bindable var probe: MenuProbe
    var body: some View {
        FollowingCarousel(
            items: [.all, .up(probe.live), .up(FollowedUp(mid: 2, uname: "普通 UP", face: "", hasUpdate: false))] + probe.additional.map(FollowingSelection.up),
            focusedID: $probe.selection, side: .left, isExpanded: $probe.expanded,
            onSettled: { _ in }, onOpenUp: { _ in },
            onOpenLive: { probe.openedLive.append($0.mid) },
            onContextMenuChange: { probe.menuStates.append($0) }, controller: probe.controller
        )
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

@MainActor
private struct MenuWindowFixture {
    let window: UIWindow
    let previous: UIWindow?
    let collection: UICollectionView
    let probe: MenuProbe
    func dismiss() {
        probe.controller.stop()
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKey()
    }
}
