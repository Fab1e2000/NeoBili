import XCTest
import SwiftUI
@testable import NeoBili
@testable import NeoBiliDomain

@MainActor
final class OfflineCacheDesignTests: XCTestCase {
    private func window() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        addTeardownBlock { @MainActor in
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
        }
        return window
    }

    private func nowPlaying() -> NowPlayingStore {
        let name = "cache-design-\(UUID())", defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let store = NowPlayingStore(defaults: defaults, dependencies: .isolated(defaults: defaults))
        addTeardownBlock { @MainActor in store.close() }
        return store
    }

    private func fixture() throws -> OfflineCacheStore {
        let cache = OfflineCacheStore(service: OfflineCacheService())
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).image { context in
            UIColor(red: 0.65, green: 0.77, blue: 0.72, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            for (offset, shade) in [(0.0, 0.45), (65.0, 0.32), (140.0, 0.2)] {
                UIColor(red: shade * 0.65, green: shade, blue: shade * 0.9, alpha: 1).setFill()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: offset - 50, y: 200))
                path.addLine(to: CGPoint(x: offset + 85, y: 35 + offset * 0.3))
                path.addLine(to: CGPoint(x: offset + 240, y: 200)); path.close(); path.fill()
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-cover-\(UUID()).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        for index in 1...4 {
            let video = OfflineVideo(bvid: "BV-design", cid: index, aid: 1,
                title: "把周末交给山野", partTitle: ["山脚下的第一缕晨光", "沿着山脊，慢慢走", "在日落之前抵达", "把时间留给星空"][index - 1],
                author: "山野来信", cover: nil, duration: 988, groupID: "mountains", groupTitle: "把周末交给山野", order: index - 1)
            var entry = OfflineCacheEntry(video: video, quality: 80, accountID: nil)
            var resource = OfflineResource(id: "video", kind: .video, url: URL(fileURLWithPath: "/fixture.mp4"), filename: "video.mp4", expectedBytes: 400_000_000)
            resource.receivedBytes = index == 4 ? 228_000_000 : 400_000_000
            resource.isComplete = index != 4
            entry.resources = [resource]; entry.state = index == 4 ? .downloading : .completed
            cache.snapshot.coverURLs[entry.generation] = url
            if index == 4 { cache.snapshot.tasks = [entry]; cache.snapshot.speeds[entry.id] = 4_200_000 }
            else { cache.snapshot.completed.append(entry) }
        }
        var single = cache.snapshot.completed[0]
        single.video.bvid = "BV-single"; single.video.groupID = "single"; single.video.partTitle = ""
        single.video.title = "我把桌面重新整理了一遍"; single.video.author = "小岛工作室"
        cache.snapshot.completed.append(single)
        cache.snapshot.availableBytes = 18_600_000_000
        return cache
    }

    private func render<V: View>(_ view: V, in window: UIWindow, name: String,
                                 style: ColorScheme = .light, size: DynamicTypeSize = .large,
                                 bounds: CGRect = CGRect(x: 0, y: 0, width: 393, height: 852)) async throws {
        window.frame = bounds
        window.overrideUserInterfaceStyle = style == .light ? .light : .dark
        let host = UIHostingController(rootView: view.environment(\.colorScheme, style)
            .environment(\.dynamicTypeSize, size).environment(AccountStore()).environment(ActionFeedback()).appTheme())
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        let attachment = ScrollIndicatorSnapshot.attachment(window: window, name: name)
        add(attachment)
        XCTAssertFalse(host.view.bounds.isEmpty)
        for scroll in scrollViews(host.view) {
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1, "Horizontal overflow in \(name)")
        }
    }

    func testNativeLibraryDownloadsAndPlayerLayouts() async throws {
        let window = try window(), cache = try fixture(), store = nowPlaying()
        for (name, style, size, bounds) in [
            ("light", ColorScheme.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 393, height: 852)),
            ("dark", .dark, .large, CGRect(x: 0, y: 0, width: 393, height: 852)),
            ("large-text", .light, .accessibility3, CGRect(x: 0, y: 0, width: 393, height: 852)),
            ("landscape", .dark, .large, CGRect(x: 0, y: 0, width: 852, height: 393))
        ] {
            try await render(NavigationStack { OfflineCacheView(cache: cache) }.environment(store),
                             in: window, name: "native-library-\(name)", style: style, size: size, bounds: bounds)
            try await render(NavigationStack { OfflineCacheView(cache: cache, showsDownloads: true) }.environment(store),
                             in: window, name: "native-downloads-\(name)", style: style, size: size, bounds: bounds)
        }
        var descriptor = OfflinePlaybackTests.descriptor()
        descriptor.entry = cache.snapshot.completed[1]
        descriptor.coverURL = cache.snapshot.coverURLs[descriptor.entry.generation]
        let ready = descriptor
        try await store.openOffline(ready.entry.id, service: OfflineCacheService(playback: { _ in ready }), from: "test")
        try await render(VideoPage(offlineCache: cache).environment(store), in: window, name: "native-player-light")
        try await render(VideoPage(offlineCache: cache).environment(store), in: window, name: "native-player-dark-large", style: .dark, size: .accessibility2)
    }

    func testSelectionStartsChosenPartsFromBottomButton() async throws {
        let window = try window(), recorder = CacheDesignActions()
        let navigation = OfflineCacheNavigation()
        var services = ApplicationServices(session: .init(currentID: { UUID() }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        let detail = OfflineSelectionTests.detail()
        let payload = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"durl":[{"url":"https://example.invalid/video"}]}"#.utf8))
        services.video.videoDetailOperation = { _ in detail }
        services.video.playURLOperation = { _, _, _ in payload }
        services.offlineCache.enqueue = { videos, quality, _, _ in await recorder.record(videos.map(\.id), quality: quality) }
        let cache = OfflineCacheStore(service: services.offlineCache)
        try await render(OfflineDownloadSheet(bvid: detail.bvid, cid: 12, services: services, cache: cache)
            .environment(\.offlineCacheNavigation, navigation),
                         in: window, name: "native-selection-light")
        XCTAssertTrue(try element("全选", in: window).accessibilityActivate())
        try await waitForState("all parts selected") { (try? self.element("取消全选", in: window)) != nil }
        let start = try element("开始缓存", in: window)
        XCTAssertTrue(window.bounds.contains(window.convert(start.accessibilityFrame, from: nil)))
        XCTAssertTrue(start.accessibilityActivate())
        try await waitForState("download navigation request") { navigation.requestID != nil }
        let recorded = await recorder.videos
        XCTAssertEqual(Set(recorded), ["BV-one:11", "BV-one:12"])
        let quality = await recorder.quality
        XCTAssertEqual(quality, 80)
        XCTAssertNotNil(navigation.requestID)
    }

    func testFailedEnqueueStaysOnSelectionWithoutNavigating() async throws {
        let window = try window(), navigation = OfflineCacheNavigation()
        var services = ApplicationServices(session: .init(currentID: { UUID() }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        let detail = OfflineSelectionTests.detail()
        let payload = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"durl":[{"url":"https://example.invalid/video"}]}"#.utf8))
        services.video.videoDetailOperation = { _ in detail }
        services.video.playURLOperation = { _, _, _ in payload }
        services.offlineCache.enqueue = { _, _, _, _ in throw URLError(.notConnectedToInternet) }
        try await render(OfflineDownloadSheet(bvid: detail.bvid, cid: 12, services: services,
            cache: OfflineCacheStore(service: services.offlineCache))
            .environment(\.offlineCacheNavigation, navigation), in: window, name: "cache-selection-enqueue-failure")
        XCTAssertTrue(try element("开始缓存", in: window).accessibilityActivate())
        try await waitForState("retry button after enqueue failure") { (try? self.element("重新加载", in: window)) != nil }
        XCTAssertNil(navigation.requestID)
        XCTAssertFalse(try element("开始缓存", in: window).accessibilityTraits.contains(.notEnabled))
    }

    func testRootRoutesFromPlayerToDownloadsAndResetsCacheNavigation() async throws {
        let window = try window(), navigation = OfflineCacheNavigation(), cache = try fixture(), store = nowPlaying()
        let name = "cache-navigation-\(UUID())", defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        defaults.set("home,live,following,history", forKey: MainTabSettings.orderKey)
        defaults.set("offlineCache,watchLater,favorites", forKey: MainTabSettings.hiddenKey)
        try await render(RootView(nowPlaying: store, cacheNavigation: navigation, offlineCache: cache)
            .defaultAppStorage(defaults), in: window, name: "cache-tab-before-routing")
        let descriptor = OfflinePlaybackTests.descriptor()
        try await store.openOffline(descriptor.entry.id, service: OfflineCacheService(playback: { _ in descriptor }), from: "test")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(store.isExpanded)
        navigation.openDownloads()
        for _ in 0..<30 {
            if !store.isExpanded, window.rootViewController?.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.isExpanded)
        XCTAssertNil(window.rootViewController?.presentedViewController)
        let tabs = try XCTUnwrap(controllers(window.rootViewController).compactMap { $0 as? UITabBarController }.first)
        XCTAssertEqual(tabs.selectedTab?.title, "缓存")
        XCTAssertEqual(tabs.tabs.count, 5)
        let segment = try XCTUnwrap(descendants(window).compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual(segment.selectedSegmentIndex, 1)
        segment.selectedSegmentIndex = 0
        segment.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(try element("把周末交给山野", in: window).accessibilityActivate())
        try await Task.sleep(for: .milliseconds(350))
        navigation.openDownloads()
        try await Task.sleep(for: .milliseconds(350))
        let resetSegment = try XCTUnwrap(descendants(window).compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual(resetSegment.selectedSegmentIndex, 1)
        XCTAssertEqual(defaults.string(forKey: MainTabSettings.hiddenKey), "offlineCache,watchLater,favorites")
        add(ScrollIndicatorSnapshot.attachment(window: window, name: "cache-tab-downloads-after-routing"))
    }

    private func controllers(_ root: UIViewController?) -> [UIViewController] {
        guard let root else { return [] }
        return [root] + root.children.flatMap { controllers($0) }
    }

    func testRootRoutesOutOfMineServiceAndItsPlayer() async throws {
        let window = try window(), navigation = OfflineCacheNavigation(), cache = try fixture(), store = nowPlaying()
        try await render(RootView(nowPlaying: store, cacheNavigation: navigation, offlineCache: cache),
                         in: window, name: "cache-route-from-mine")
        XCTAssertTrue(try element("我的", in: window).accessibilityActivate())
        try await Task.sleep(for: .milliseconds(500))
        let mine = try XCTUnwrap(window.rootViewController?.presentedViewController)
        XCTAssertTrue(try element("离线缓存", in: mine.view).accessibilityActivate())
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(store.isServiceSheetPresented)
        XCTAssertNotNil(mine.presentedViewController)
        let descriptor = OfflinePlaybackTests.descriptor()
        try await store.openOffline(descriptor.entry.id, service: OfflineCacheService(playback: { _ in descriptor }), from: "test")
        try await Task.sleep(for: .milliseconds(500))
        navigation.openDownloads()
        for _ in 0..<40 {
            if !store.isExpanded, window.rootViewController?.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.isServiceSheetPresented)
        XCTAssertNil(window.rootViewController?.presentedViewController)
        let tabs = try XCTUnwrap(controllers(window.rootViewController).compactMap { $0 as? UITabBarController }.first)
        XCTAssertEqual(tabs.selectedTab?.title, "缓存")
        let segment = try XCTUnwrap(descendants(window).compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual(segment.selectedSegmentIndex, 1)
        add(ScrollIndicatorSnapshot.attachment(window: window, name: "cache-tab-after-mine-dismissal"))
    }

    func testOfflineVideoPageUsesNativeIntroductionAndPartsPicker() async throws {
        let window = try window(), fixture = try fixture(), store = nowPlaying(), recorder = CacheDesignActions()
        let snapshot = fixture.snapshot
        let baseDescriptor = OfflinePlaybackTests.descriptor()
        let service = OfflineCacheService(playback: { id in
            await recorder.action(id)
            var descriptor = baseDescriptor
            descriptor.entry = try XCTUnwrap(snapshot.completed.first { $0.id == id })
            descriptor.coverURL = snapshot.coverURLs[descriptor.entry.generation]
            return descriptor
        })
        let cache = OfflineCacheStore(service: service)
        cache.snapshot = snapshot
        try await store.openOffline("BV-design:1", service: service, from: "test")
        try await render(VideoPage(offlineCache: cache).environment(store), in: window, name: "shared-offline-video-page")
        let title = try XCTUnwrap(descendants(window).compactMap { $0 as? UILabel }.first {
            $0.accessibilityIdentifier == "video.introduction.title"
        })
        XCTAssertEqual(title.text, "把周末交给山野")
        let partsRow = try XCTUnwrap(descendants(window).compactMap { $0 as? UICollectionViewCell }.first {
            $0.accessibilityIdentifier == "description.parts"
        })
        XCTAssertGreaterThanOrEqual(partsRow.bounds.height, 48)
        try await render(OfflinePartsPlaybackSheet(entries: cache.entries(in: "mountains"), cache: cache)
            .environment(store), in: window, name: "shared-offline-parts-picker")
        XCTAssertTrue(try element("沿着山脊，慢慢走", in: window, exact: false).accessibilityActivate())
        try await waitForState("selected offline part") { store.activeCid == 2 }
        XCTAssertEqual(store.activeCid, 2)
        XCTAssertEqual(store.offline?.entry.id, "BV-design:2")
        XCTAssertNil(store.detailViewModel)
        XCTAssertNil(store.commentsViewModel)
        let requests = await recorder.actions
        XCTAssertEqual(requests, ["BV-design:1", "BV-design:2"])
    }

    func testDownloadCardPauseAndResumeUseRealService() async throws {
        let window = try window(), cache = try fixture(), store = nowPlaying(), recorder = CacheDesignActions()
        var service = OfflineCacheService()
        service.pause = { await recorder.action("pause:\($0)") }
        service.resume = { await recorder.action("resume:\($0):\($1)") }
        let model = OfflineCacheStore(service: service)
        model.snapshot = cache.snapshot
        try await render(NavigationStack { OfflineCacheView(cache: model, showsDownloads: true) }.environment(store),
                         in: window, name: "native-download-actions")
        XCTAssertTrue(try element("暂停", in: window).accessibilityActivate())
        try await waitForState("pause request") { await recorder.actions.count == 1 }
        model.snapshot.tasks[0].state = .paused
        try await waitForState("resume button") { (try? self.element("继续", in: window)) != nil }
        XCTAssertTrue(try element("继续", in: window).accessibilityActivate())
        try await waitForState("resume request") { await recorder.actions.count == 2 }
        let actions = await recorder.actions
        XCTAssertEqual(actions, ["pause:BV-design:4", "resume:BV-design:4:false"])
    }

    func testManagingAGroupShowsDeletionCountWithoutDeletingBeforeConfirmation() async throws {
        let window = try window(), cache = try fixture(), store = nowPlaying(), recorder = CacheDesignActions()
        let service = OfflineCacheService(delete: { await recorder.record($0, quality: 0) })
        let model = OfflineCacheStore(service: service)
        model.snapshot = cache.snapshot
        try await render(NavigationStack { OfflineCacheView(cache: model) }.environment(store),
                         in: window, name: "native-management")
        XCTAssertTrue(try element("管理", in: window).accessibilityActivate())
        try await waitForState("group in selection mode") {
            (try? self.element("把周末交给山野", in: window))?.accessibilityValue == "未选择"
        }
        XCTAssertTrue(try element("把周末交给山野", in: window).accessibilityActivate())
        try await waitForState("three-item deletion button") { (try? self.element("删除 3 项", in: window)) != nil }
        XCTAssertTrue(try element("删除 3 项", in: window).accessibilityActivate())
        try await waitForState("deletion confirmation sheet") { window.rootViewController?.presentedViewController != nil }
        let beforeConfirmation = await recorder.videos
        XCTAssertTrue(beforeConfirmation.isEmpty)
        add(ScrollIndicatorSnapshot.attachment(window: window, name: "native-delete-confirmation"))
        let dialog = try XCTUnwrap(window.rootViewController?.presentedViewController)
        let confirm = try element("删除 3 项", in: dialog.view)
        XCTAssertFalse(confirm.accessibilityTraits.contains(.notEnabled))
    }

    private func waitForState(_ description: String, condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "OfflineCacheDesignTests", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for " + description])
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func scrollViews(_ view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    private func element(_ label: String, in root: UIView, exact: Bool = true) throws -> NSObject {
        var visited = Set<ObjectIdentifier>(), pending: [NSObject] = [root]
        var available: [String] = []
        while let object = pending.popLast() {
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            if let label = object.accessibilityLabel, !label.isEmpty {
                available.append("\(type(of: object)): \(label) [\(object.accessibilityTraits.rawValue)]")
            }
            let matches = exact ? object.accessibilityLabel == label : object.accessibilityLabel?.contains(label) == true
            if matches && object.accessibilityTraits.contains(.button) { return object }
            if let view = object as? UIView { pending.append(contentsOf: view.subviews) }
            pending.append(contentsOf: (object.accessibilityElements ?? []).compactMap { $0 as? NSObject })
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<min(count, 1024) {
                    if let child = object.accessibilityElement(at: index) as? NSObject { pending.append(child) }
                }
            }
        }
        throw NSError(domain: "OfflineCacheDesignTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing button: \(label). Available: \(available.joined(separator: "; "))"])
    }
}

private actor CacheDesignActions {
    var videos: [String] = []
    var quality: Int?
    var actions: [String] = []
    func record(_ videos: [String], quality: Int) { self.videos = videos; self.quality = quality }
    func action(_ value: String) { actions.append(value) }
}
