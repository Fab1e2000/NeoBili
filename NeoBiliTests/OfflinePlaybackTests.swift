import XCTest
import SwiftUI
@testable import NeoBili
@testable import NeoBiliDomain

@MainActor
final class OfflinePlaybackTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "offline-player-\(UUID())"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }

    static func descriptor(video: URL = URL(fileURLWithPath: "/offline/video.mp4"),
                           audio: URL? = URL(fileURLWithPath: "/offline/audio.m4a")) -> OfflinePlaybackDescriptor {
        let item = OfflineVideo(bvid: "BV-offline", cid: 1, aid: 1, title: "离线播放测试", partTitle: "",
            author: "NeoBili", cover: nil, duration: 6, groupID: "fixture", groupTitle: "离线测试", order: 0)
        var entry = OfflineCacheEntry(video: item, quality: 80, accountID: nil)
        entry.state = .completed; entry.width = 320; entry.height = 180
        entry.chapters = [.init(from: 0, to: 6, title: "离线章节")]
        return .init(leaseID: UUID(), entry: entry, videoURLs: [video], audioURL: audio, coverURL: nil,
            danmaku: [.init(time: 1, text: "本地弹幕", mode: 1, color: 0xFFFFFF)],
            subtitles: [.init(id: "zh", language: "zh-CN", title: "中文", cues: [.init(from: 0, to: 6, content: "离线字幕同步测试")]),
                        .init(id: "en", language: "en", title: "English", cues: [.init(from: 0, to: 6, content: "Offline subtitles")])])
    }

    func testOfflineLoadUsesFilesAndNeverCallsOnlineLoadersOrReporters() async throws {
        let defaults = defaults()
        let dependencies = PlaybackDependencies.isolated(defaults: defaults, video: .init(chaptersOperation: { _, _, _ in
            XCTFail("Offline playback fetched chapters")
            return []
        }))
        var opened: PlaybackSource?
        let player = PlayerViewModel(bvid: "BV-offline", cid: 1, offline: Self.descriptor(),
            playbackURLLoader: { _, _ in XCTFail("Offline playback fetched a play URL"); throw URLError(.badURL) },
            qualityPlaybackURLLoader: { _, _, _ in XCTFail("Offline playback fetched quality"); throw URLError(.badURL) },
            watchProgressReporter: { _, _, _ in XCTFail("Offline playback reported online history") },
            danmakuLoader: { _ in XCTFail("Offline playback downloaded danmaku"); return [] },
            sourceOpener: { _, source, _ in opened = source }, dependencies: dependencies)
        defer { player.stop() }
        await player.load()
        XCTAssertTrue(try XCTUnwrap(opened).video.primary.isFileURL)
        XCTAssertTrue(try XCTUnwrap(opened?.audio).primary.isFileURL)
        XCTAssertEqual(player.selectedVideoQuality, 80)
        XCTAssertEqual(player.selectedSubtitleID, "zh")
        XCTAssertEqual(player.chapters, Self.descriptor().entry.chapters)
        XCTAssertTrue(player.availableVideoQualities.isEmpty)
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(1))
        player.ensureDanmaku()
        await Task.yield()
        XCTAssertNotNil(player.danmaku)
        player.session.onEvent?(.ended)
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(player.isPlaybackCompleted)
    }

    func testOpeningSameVideoOnlineReplacesOfflineContext() async throws {
        let defaults = defaults(), dependencies = PlaybackDependencies.isolated(defaults: defaults)
        defaults.set(false, forKey: DetailPlaybackSettings.storageKey)
        let descriptor = Self.descriptor()
        let service = OfflineCacheService(playback: { _ in descriptor })
        let store = NowPlayingStore(defaults: defaults, dependencies: dependencies)
        defer { store.close() }
        try await store.openOffline(descriptor.entry.id, service: service, from: "test")
        XCTAssertNil(store.detailViewModel)
        XCTAssertNotNil(store.offline)
        XCTAssertTrue(store.player?.isOffline == true)
        store.open(.init(bvid: descriptor.entry.video.bvid, cid: descriptor.entry.video.cid), from: "online")
        XCTAssertNil(store.offline)
        XCTAssertNotNil(store.detailViewModel)
    }

    func testSubtitleLanguageAndSeekBoundaries() {
        let track = OfflineSubtitleTrack(id: "en", language: "en", title: "English", cues: [
            .init(from: 0, to: 1, content: "First"), .init(from: 2, to: 4, content: "Second")])
        XCTAssertEqual(track.text(at: 0), "First")
        XCTAssertEqual(track.text(at: 1), "")
        XCTAssertEqual(track.text(at: 3), "Second")
        XCTAssertEqual(track.text(at: 0.5), "First")
    }

    func testSharedImageLoaderReadsCachedCoversWithoutNetwork() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("offline-cover-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(image.pngData()).write(to: url)
        let loaded = try await BiliImageLoader.load(url, download: { _ in
            XCTFail("Local artwork must not use the network loader")
            throw URLError(.notConnectedToInternet)
        })
        XCTAssertEqual(loaded.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(loaded.cgImage?.height, image.cgImage?.height)
    }
}

@MainActor
final class OfflineCacheUITests: XCTestCase {
    func testCacheLayoutsInLightDarkLargeTextAndLandscape() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let name = "offline-ui-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let dependencies = PlaybackDependencies.isolated(defaults: defaults)
        let nowPlaying = NowPlayingStore(defaults: defaults, dependencies: dependencies)
        let cache = OfflineCacheStore(service: OfflineCacheService())
        cache.snapshot.completed = [OfflinePlaybackTests.descriptor().entry]
        var task = OfflinePlaybackTests.descriptor().entry
        task.state = .waitingForNetwork; task.quality = 64
        cache.snapshot.tasks = [task]
        cache.snapshot.availableBytes = 12_345_678_900
        for (name, style, size, bounds) in [
            ("light", ColorScheme.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 393, height: 852)),
            ("dark", .dark, .large, CGRect(x: 0, y: 0, width: 393, height: 852)),
            ("large-text", .light, .accessibility3, CGRect(x: 0, y: 0, width: 393, height: 852)),
            ("landscape", .dark, .large, CGRect(x: 0, y: 0, width: 852, height: 393))
        ] {
            window.frame = bounds
            let root = NavigationStack { OfflineCacheView(cache: cache) }
                .environment(nowPlaying).environment(\.colorScheme, style).environment(\.dynamicTypeSize, size)
            let host = UIHostingController(rootView: root)
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(host.view.bounds.isEmpty)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "offline-library-\(name)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testDownloadSelectionSheetLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow, window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        var services = ApplicationServices(session: .init(currentID: { UUID() }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        let detail = OfflineSelectionTests.detail()
        let payload = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"durl":[{"url":"https://example.invalid/video"}]}"#.utf8))
        services.video.videoDetailOperation = { _ in detail }
        services.video.playURLOperation = { _, _, _ in payload }
        let cache = OfflineCacheStore(service: services.offlineCache)
        for (name, style, size) in [("light", ColorScheme.light, DynamicTypeSize.large), ("dark-large", .dark, .accessibility2)] {
            let host = UIHostingController(rootView: OfflineDownloadSheet(bvid: detail.bvid, cid: 12, services: services, cache: cache)
                .environment(\.colorScheme, style).environment(\.dynamicTypeSize, size))
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "offline-selection-\(name)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}

@MainActor
final class OfflineSelectionTests: XCTestCase {
    static func detail(_ bvid: String = "BV-one", collection: UgcSeason? = nil) -> VideoDetail {
        VideoDetail(bvid: bvid, aid: 1, cid: 11, title: "课程视频", desc: "", pic: "", duration: 60, pubdate: 0,
            owner: .init(mid: 1, name: "作者", face: ""),
            stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
            pages: [.init(cid: 11, page: 1, part: "第一课", duration: 30), .init(cid: 12, page: 2, part: "第二课", duration: 30)],
            tname: nil, copyright: nil, ugcSeason: collection)
    }

    func testCurrentPartCollectionExpansionQualityChoiceAndPreference() async throws {
        let collection = try JSONDecoder().decode(UgcSeason.self, from: Data(#"{"id":7,"title":"课程合集","sections":[{"episodes":[{"bvid":"BV-one"},{"bvid":"BV-two"}]}]}"#.utf8))
        let detail = Self.detail(collection: collection), second = Self.detail("BV-two")
        let payload = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"durl":[{"url":"https://example.invalid/video"}]}"#.utf8))
        var services = ApplicationServices(session: .init(currentID: { UUID() }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        services.video.videoDetailOperation = { $0 == detail.bvid ? detail : second }
        services.video.playURLOperation = { _, cid, _ in XCTAssertEqual(cid, 12); return payload }
        services.offlineCache.enqueue = { videos, quality, _, replace in
            XCTAssertEqual(videos.count, 4)
            XCTAssertEqual(Set(videos.map(\.groupID)), ["season:7"])
            XCTAssertEqual(quality, 80)
            XCTAssertFalse(replace)
        }
        let name = "offline-selection-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = OfflineSelectionModel(bvid: detail.bvid, cid: 12, services: services, defaults: defaults)
        await model.load()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.selected, ["BV-one:12"])
        XCTAssertEqual(model.quality, 80)
        XCTAssertEqual(model.qualities, [80])
        var existing = OfflineCacheSnapshot()
        existing.completed = model.selectedVideos.map { OfflineCacheEntry(video: $0, quality: 80, accountID: nil) }
        XCTAssertNotNil(model.duplicateMessage(in: existing))
        model.quality = 64
        XCTAssertNil(model.duplicateMessage(in: existing))
        XCTAssertTrue(model.needsReplacement(in: existing))
        model.quality = 80
        model.collectionSelected = true
        await model.changeScope()
        XCTAssertEqual(model.videos.map(\.id), ["BV-one:11", "BV-one:12", "BV-two:11", "BV-two:12"])
        XCTAssertEqual(model.selected, ["BV-one:12"])
        model.selected = Set(model.videos.map(\.id))
        let submitted = await model.submit(replace: false)
        XCTAssertTrue(submitted)
        XCTAssertEqual(defaults.integer(forKey: OfflineSelectionModel.qualityKey), 80)
        defaults.set(120, forKey: OfflineSelectionModel.qualityKey)
        let unavailable = OfflineSelectionModel(bvid: detail.bvid, cid: 12, services: services, defaults: defaults)
        await unavailable.load()
        XCTAssertNil(unavailable.quality)
    }
}
