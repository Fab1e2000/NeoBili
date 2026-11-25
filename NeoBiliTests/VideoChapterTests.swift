import XCTest
import NeoBiliDomain
@testable import NeoBiliData
@testable import NeoBili

final class VideoChapterTests: XCTestCase {
    func testPlayerInfoKeepsValidOfficialChaptersInTimeOrder() throws {
        let json = """
        {
          "subtitle": {"subtitles":[]},
          "view_points": [
            {"type":2, "from":20.25, "to":30, "content":"  正片  ", "imgUrl":7},
            {"type":1, "from":0, "to":30, "content":"高能"},
            {"type":2, "from":0, "to":20.25, "content":"开场", "imgUrl":"//i0.hdslb.com/cover.jpg"},
            {"type":2, "from":-1, "to":2, "content":"负数"},
            {"type":2, "from":3, "to":2, "content":"倒序"},
            {"type":2, "from":3, "to":3, "content":"零长度"},
            {"type":2, "from":3, "to":4, "content":"  "},
            {"type":"2", "from":3, "to":4, "content":"类型错误"},
            {"type":2, "from":"3", "to":4, "content":"时间错误"},
            {"type":2, "from":3, "content":"缺少结束时间"},
            {"type":2, "from":3, "to":4, "content":false},
            null,
            42
          ]
        }
        """
        let info = try JSONDecoder().decode(PlayerVideoInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.chapters, [
            .init(from: 0, to: 20.25, title: "开场", imageURL: URL(string: "https://i0.hdslb.com/cover.jpg")),
            .init(from: 20.25, to: 30, title: "正片")
        ])
        XCTAssertEqual(info.subtitle?.subtitles.count, 0)
    }

    func testMissingEmptyAndMalformedViewPointsDoNotAffectSubtitles() throws {
        for field in ["", ",\"view_points\":[]", ",\"view_points\":null", ",\"view_points\":{}"] {
            let json = "{\"subtitle\":{\"subtitles\":[{\"lan\":\"zh\",\"lan_doc\":\"中文\",\"subtitle_url\":\"//example.test/sub\"}]}\(field)}"
            let info = try JSONDecoder().decode(PlayerVideoInfo.self, from: Data(json.utf8))
            XCTAssertEqual(info.chapters, [])
            XCTAssertEqual(info.subtitle?.subtitles.first?.lan, "zh")
        }
    }

    func testChapterLookupAtStartsAdjacentBoundariesGapsAndEnd() {
        let chapters: [VideoChapter] = [.init(from: 2, to: 4, title: "A"),
            .init(from: 4, to: 6, title: "B"), .init(from: 7, to: 10, title: "C")]
        for seconds: Double in [-1, 0, 6, 6.5, 10.01, .nan, .infinity] {
            XCTAssertNil(chapters.chapter(at: seconds))
        }
        XCTAssertNil([VideoChapter]().chapter(at: 0))
        XCTAssertEqual(chapters.chapter(at: 2), chapters[0])
        XCTAssertEqual(chapters.chapter(at: 3.99), chapters[0])
        XCTAssertEqual(chapters.chapter(at: 4), chapters[1])
        XCTAssertEqual(chapters.chapter(at: 7), chapters[2])
        XCTAssertEqual(chapters.chapter(at: 10), chapters[2])
    }

    @MainActor
    func testSwitchingPartAndVideoDiscardsLateChapterResponses() async throws {
        let name = "chapters-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let loader = ControlledChapterLoader()
        addTeardownBlock { await loader.finishAll() }
        let dependencies = PlaybackDependencies.isolated(defaults: defaults, video: .init(chaptersOperation: { bvid, cid, _ in
            await loader.load("\(bvid):\(cid)")
        }))
        let store = NowPlayingStore(defaults: defaults, dependencies: dependencies)
        defer { store.close() }

        store.open(.init(bvid: "BVfirst", cid: 1), from: "chapters")
        let first = try XCTUnwrap(store.player)
        try await wait { await loader.isPending("BVfirst:1") }

        store.selectPart(cid: 2)
        let second = try XCTUnwrap(store.player)
        XCTAssertFalse(first === second)
        XCTAssertTrue(second.chapters.isEmpty)
        try await wait { await loader.isPending("BVfirst:2") }

        store.open(.init(bvid: "BVother", cid: 2), from: "chapters")
        let current = try XCTUnwrap(store.player)
        XCTAssertFalse(second === current)
        XCTAssertTrue(current.chapters.isEmpty)
        try await wait { await loader.isPending("BVother:2") }

        await loader.finish("BVfirst:1")
        await loader.finish("BVfirst:2")
        await loader.finish("BVother:2")
        try await wait { current.chapters.first?.title == "BVother:2" }
        XCTAssertTrue(first.chapters.isEmpty)
        XCTAssertTrue(second.chapters.isEmpty)
        XCTAssertTrue(store.player === current)

        store.selectPart(cid: 3)
        XCTAssertTrue(current.chapters.isEmpty)
        XCTAssertEqual(store.player?.chapters, [])
    }

    @MainActor
    private func wait(until condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for chapters")
        throw URLError(.timedOut)
    }
}

private actor ControlledChapterLoader {
    private var pending: [String: CheckedContinuation<[VideoChapter], Never>] = [:]
    private var isClosed = false

    func load(_ key: String) async -> [VideoChapter] {
        guard !isClosed else { return [] }
        return await withCheckedContinuation { pending[key] = $0 }
    }

    func isPending(_ key: String) -> Bool { pending[key] != nil }

    func finish(_ key: String) {
        pending.removeValue(forKey: key)?.resume(returning: [.init(from: 0, to: 10, title: key)])
    }

    func finishAll() {
        isClosed = true
        for continuation in pending.values { continuation.resume(returning: []) }
        pending.removeAll()
    }
}
