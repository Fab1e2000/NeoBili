#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Presentation/layout coverage only: static fixtures do not measure video GPU cost.
@MainActor
final class VideoPickerPresentationTests: XCTestCase {
    func testPartsPickerRetainsHalfAndFullHeightPresentation() async throws {
        let parts = (1...60).map {
            VideoPart(cid: $0, page: $0, part: "本地分P样例 \($0)", duration: 120)
        }
        let store = try pickerStore()
        defer { store.close() }
        try await checkPresentation(name: "parts", content: AnyView(
            VideoPartsPlaybackSheet(parts: parts, coverURL: nil).environment(store)
        ), selectionStore: store)
    }

    func testSeasonPickerRetainsHalfAndFullHeightPresentation() async throws {
        let episodes = (1...60).map { (index: Int) in
            UgcSeasonEpisode(episodeId: index, aid: index, cid: index, bvid: "BVFixture\(index)",
                title: "本地合集样例 \(index)", arc: nil)
        }
        let season = UgcSeason(id: 1, title: "本地合集", cover: nil, mid: nil,
            sections: [UgcSeasonSection(id: 1, title: nil, episodes: episodes)])
        let store = try pickerStore()
        defer { store.close() }
        try await checkPresentation(name: "season", content: AnyView(
            UgcSeasonPlaybackSheet(season: season).environment(store)
                .environment(\.hidesPortraitVideos, false)
        ), selectionStore: store)
    }

    private func pickerStore() throws -> NowPlayingStore {
        let suite = "picker-selection.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: DetailPlaybackSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        store.open(VideoDetailRoute(bvid: "BVFixture42", cid: 42), from: "fixture")
        XCTAssertNil(store.player)
        return store
    }

    private func checkPresentation(name: String, content: AnyView, selectionStore: NowPlayingStore) async throws {
        var activeScene: UIWindowScene?
        for _ in 0..<100 {
            activeScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if activeScene != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(activeScene)
        let previous = scene.keyWindow
        let orientation = OrientationLock.shared.supportedOrientations
        OrientationController.enterPortrait()
        let driver = VideoPickerPresentationDriver()
        let host = UIHostingController(rootView: VideoPickerPresentationHarness(driver: driver, content: content))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
            OrientationLock.shared.request(orientation)
            previous?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { @Sendable _ in }
        }
        for _ in 0..<50 {
            if scene.interfaceOrientation.isPortrait { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(scene.interfaceOrientation.isPortrait)
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            driver.isPresented = true
            for _ in 0..<100 {
                if host.presentedViewController?.view.window != nil { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(400))
            let presented = try XCTUnwrap(host.presentedViewController)
            let sheet = try XCTUnwrap(presented.sheetPresentationController)
            XCTAssertEqual(Set(sheet.detents.map(\.identifier)), Set([.medium, .large]))
            sheet.selectedDetentIdentifier = .medium
            try await Task.sleep(for: .milliseconds(200))
            window.layoutIfNeeded()
            let halfFrame = presented.view.convert(presented.view.bounds, to: window)
            XCTAssertGreaterThan(halfFrame.minY, window.bounds.height * 0.2)
            XCTAssertGreaterThan(halfFrame.height, window.bounds.height * 0.3)
            let scroll = try XCTUnwrap(scrollViews(in: presented.view).first { $0.contentSize.height > $0.bounds.height })
            let current = try XCTUnwrap(currentItem(in: presented.view), "Playing item must be realized even far down the lazy list")
            XCTAssertTrue(current.accessibilityTraits.contains(.selected))
            let selectedFrame = window.convert(current.accessibilityFrame, from: window.screen.coordinateSpace)
            let visible = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            XCTAssertEqual(selectedFrame.midY, visible.midY, accuracy: 12,
                           "Opening the picker should center the playing item in the visible scroll area")
            try snapshot(window, name: "\(name)-\(style.rawValue)-medium")

            for next in [43, 44] {
                let item = try XCTUnwrap(accessibilityItem(in: presented.view) {
                    $0.accessibilityLabel?.contains("样例 \(next)、") == true
                })
                XCTAssertTrue(item.accessibilityActivate(), "Select the real row button")
                try await Task.sleep(for: .milliseconds(250))
                XCTAssertTrue(host.presentedViewController === presented, "Selection must preserve the presented sheet")
                XCTAssertTrue(driver.isPresented)
                XCTAssertEqual(selectionStore.player?.cid, next, "Explicit selection starts playback even with autoplay disabled")
                if name == "season" {
                    XCTAssertEqual(selectionStore.route?.bvid, "BVFixture\(next)")
                    XCTAssertNil(selectionStore.detailViewModel?.detail, "The original list survives unavailable replacement details")
                }
                XCTAssertTrue(currentItem(in: presented.view)?.accessibilityLabel?.contains("样例 \(next)、") == true)
            }
            try snapshot(window, name: "\(name)-\(style.rawValue)-after-selection")

            sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
            try await Task.sleep(for: .milliseconds(450))
            window.layoutIfNeeded()
            let fullFrame = presented.view.convert(presented.view.bounds, to: window)
            XCTAssertGreaterThan(fullFrame.height, halfFrame.height + 100)
            XCTAssertLessThan(fullFrame.minY, halfFrame.minY - 100)
            try snapshot(window, name: "\(name)-\(style.rawValue)-large")

            // Browsing away from the playing item must not continually recenter.
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(scroll.contentOffset.y, -scroll.adjustedContentInset.top, accuracy: 1)

            let bars = navigationBars(in: presented.view)
            XCTAssertFalse(bars.isEmpty)
            XCTAssertTrue(activateClose(in: bars), "Activate the real close toolbar action")
            for _ in 0..<100 {
                if host.presentedViewController == nil { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNil(host.presentedViewController)
            XCTAssertFalse(driver.isPresented)
        }
    }

    private func snapshot(_ window: UIWindow, name: String) throws {
        XCTAssertTrue(window.isKeyWindow)
        XCTAssertGreaterThan(window.traitCollection.displayScale, 0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.traitCollection.displayScale
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func currentItem(in root: UIView) -> NSObject? {
        accessibilityItem(in: root) { $0.accessibilityLabel?.contains("正在播放") == true }
    }

    private func accessibilityItem(in root: UIView, matching: (NSObject) -> Bool) -> NSObject? {
        var visited = Set<ObjectIdentifier>()
        var pending: [NSObject] = [root]
        while let object = pending.popLast() {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            if matching(object) {
                return object
            }
            if let view = object as? UIView { pending.append(contentsOf: view.subviews) }
            pending.append(contentsOf: (object.accessibilityElements ?? []).compactMap { $0 as? NSObject })
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<min(count, 1024) {
                    if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return nil
    }

    private func navigationBars(in view: UIView) -> [UINavigationBar] {
        (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap { navigationBars(in: $0) }
    }

    private func activateClose(in bars: [UINavigationBar]) -> Bool {
        var visited = Set<ObjectIdentifier>()
        var pending: [NSObject] = bars
        for bar in bars {
            for item in bar.items ?? [] {
                pending.append(contentsOf: item.leftBarButtonItems ?? [])
                pending.append(contentsOf: item.rightBarButtonItems ?? [])
                pending.append(contentsOf: item.leadingItemGroups.flatMap(\.barButtonItems))
                pending.append(contentsOf: item.trailingItemGroups.flatMap(\.barButtonItems))
                pending.append(contentsOf: item.centerItemGroups.flatMap(\.barButtonItems))
            }
        }
        while let object = pending.popLast() {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            if object.accessibilityLabel == "关闭" || (object as? UIBarButtonItem)?.title == "关闭" {
                if object.accessibilityActivate() { return true }
                if let item = object as? UIBarButtonItem, let action = item.action,
                   UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil) {
                    return true
                }
                if let control = object as? UIControl {
                    control.sendActions(for: .touchUpInside)
                    return true
                }
            }
            if let view = object as? UIView { pending.append(contentsOf: view.subviews) }
            if let item = object as? UIBarButtonItem, let view = item.customView { pending.append(view) }
            pending.append(contentsOf: (object.accessibilityElements ?? []).compactMap { $0 as? NSObject })
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<min(count, 1_024) {
                    if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        return false
    }
}

@MainActor @Observable
private final class VideoPickerPresentationDriver {
    var isPresented = false
}

private struct VideoPickerPresentationHarness: View {
    @Bindable var driver: VideoPickerPresentationDriver
    let content: AnyView

    var body: some View {
        Color.blue.ignoresSafeArea()
            .sheet(isPresented: $driver.isPresented) { content }
    }
}
