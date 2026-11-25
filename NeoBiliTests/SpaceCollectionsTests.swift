@testable import NeoBiliData
@testable import NeoBiliDomain
import Synchronization
import XCTest
@testable import NeoBili

@MainActor
final class SpaceCollectionsTests: XCTestCase {
    func testDecodesBothKindsAndUsesFirstSeriesArchiveAsFallbackCover() throws {
        let page = try decode(SpaceCollectionListPage.self, """
            {"items_lists":{"seasons_list":[null,{"meta":{"season_id":"7","mid":"42","name":"合集",
            "description":"简介","cover":"season.png","total":"3","last_update_ts":"123"}},{"meta":{}}],
            "series_list":[{"meta":{"series_id":7,"cover":null,"mtime":321},"archives":[{"pic":"first.png"},{"pic":"second.png"}]},
            {"meta":{"series_id":8,"cover":"series.png"},"archives":[{"pic":"unused.png"}]}],
            "page":{"page_num":"1","page_size":"3","total":"4"}}}
            """)
        XCTAssertEqual(page.collections.map(\.id), ["season:7", "series:7", "series:8"])
        XCTAssertEqual(page.collections.map(\.cover), ["season.png", "first.png", "series.png"])
        XCTAssertEqual(page.collections.map(\.updatedAt), [123, 321, 0])
        XCTAssertEqual(page.collections.map(\.mid), [42, 0, 0])
        XCTAssertEqual(page.collections.map(\.description), ["简介", "", ""])
        XCTAssertEqual(page.collections.map(\.total), [3, 0, 0])
        XCTAssertEqual(page.pageNumber, 1)
        XCTAssertTrue(page.hasMore(after: 3))

        let outer = try decode(SpaceCollectionListPage.self, """
            {"items_lists":{},"page":{"page_num":2,"page_size":20,"total":36}}
            """)
        XCTAssertTrue(outer.collections.isEmpty)
        XCTAssertEqual(outer.pageSize, 20)
        XCTAssertFalse(outer.hasMore(after: 2))
    }

    func testDecodesBothArchivePageShapesWithLenientMetadata() throws {
        let page = try decode(SpaceCollectionArchivePage.self, """
            {"archives":[{"bvid":"BVfirst","aid":"123","title":"第一集","pic":"cover.png","duration":"3661",
              "pubdate":"456","stat":{"view":"89"},"dimension":{"width":"1080","height":1920}},
              {"title":"Invalid"}, {"bvid":"BVsecond","duration":64}],
             "page":{"page_num":1,"page_size":2,"total":3}}
            """)
        XCTAssertEqual(page.archives.map(\.bvid), ["BVfirst", "BVsecond"])
        XCTAssertEqual(page.archives.map(\.durationText), ["1:01:01", "01:04"])
        XCTAssertTrue(page.hasMore(after: 2))
        let first = try XCTUnwrap(page.archives.first)
        XCTAssertEqual(first.aid, 123)
        XCTAssertEqual(first.title, "第一集")
        XCTAssertEqual(first.pic, "cover.png")
        XCTAssertEqual(first.pubdate, 456)
        XCTAssertEqual(first.viewCount, 89)
        XCTAssertEqual(first.dimension?.isPortrait, true)

        let series = try decode(SpaceCollectionArchivePage.self, """
            {"archives":[{"bvid":"BVseries"}],"page":{"num":2,"size":2,"total":3}}
            """)
        XCTAssertEqual(series.pageNumber, 2)
        XCTAssertEqual(series.pageSize, 2)
        XCTAssertFalse(series.hasMore(after: 1))
        XCTAssertEqual(series.archives.first?.durationText, "")
        XCTAssertEqual(series.archives.first?.viewCount, -1)
    }

    func testDirectoryLoadsLazilyAndAdvancesPastDuplicateOnlyPage() async throws {
        let pages = try [
            directory(seasonID: 1, page: 1, total: 3),
            directory(seasonID: 1, page: 2, total: 3),
            directory(seasonID: 2, page: 3, total: 3)
        ]
        var services = services()
        services.community.spaceCollectionsOperation = { mid, page in
            XCTAssertEqual(mid, 42)
            guard (1...pages.count).contains(page) else {
                XCTFail("Unexpected page \(page)")
                throw CancellationError()
            }
            return pages[page - 1]
        }
        let model = SpaceViewModel(mid: 42, services: services).collections
        XCTAssertTrue(model.collections.isEmpty)
        XCTAssertEqual(model.list.generation, 0)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        XCTAssertEqual(model.list.generation, 1)
        let first = try XCTUnwrap(model.collections.first)
        await model.loadMoreIfNeeded(current: first)
        XCTAssertEqual(model.collections.map(\.collectionID), [1, 2])
        XCTAssertFalse(model.list.hasMore)
    }

    func testDirectoryAdvancesPastSkippedRowsWithTotalOnlyPagination() async throws {
        let pages = [
            #"{"items_lists":{"seasons_list":[{"meta":{"season_id":1}}],"page":{"total":3}}}"#,
            #"{"items_lists":{"seasons_list":[{"meta":{}}],"page":{"total":3}}}"#,
            #"{"items_lists":{"series_list":[{"meta":{"series_id":2}}],"page":{"total":3}}}"#
        ]
        var services = services()
        services.community.spaceCollectionsOperation = { _, page in
            guard (1...pages.count).contains(page) else {
                XCTFail("Unexpected page \(page)")
                throw CancellationError()
            }
            return try JSONDecoder().decode(SpaceCollectionListPage.self, from: Data(pages[page - 1].utf8))
        }
        let model = SpaceCollectionsModel(mid: 42, services: services)
        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(model.collections.map(\.id), ["season:1", "series:2"])
        XCTAssertFalse(model.list.hasMore)
    }

    func testDetailAdvancesPastPageWhereEveryArchiveFailsDecoding() async throws {
        let pages = try [
            archivePage(bvid: "BVfirst", page: 1, total: 3),
            decode(SpaceCollectionArchivePage.self, """
                {"archives":[{"title":"Missing BVID"}],"page":{"num":2,"size":1,"total":3}}
                """),
            archivePage(bvid: "BVlast", page: 3, total: 3)
        ]
        XCTAssertTrue(pages[1].archives.isEmpty)
        XCTAssertEqual(pages[1].rawItemCount, 1)
        var services = services()
        services.community.spaceSeasonArchivesOperation = { _, _, page, _ in
            guard (1...pages.count).contains(page) else {
                XCTFail("Unexpected page \(page)")
                throw CancellationError()
            }
            return pages[page - 1]
        }
        let collection = try XCTUnwrap(directory(seasonID: 7, page: 1, total: 1).collections.first)
        let model = SpaceCollectionDetailModel(collection: collection, hostMID: 42, services: services, filtering: .live)
        await model.loadIfNeeded()
        await model.loadReplacementPage()

        XCTAssertEqual(model.archives.map(\.bvid), ["BVfirst", "BVlast"])
        XCTAssertFalse(model.list.hasMore)
    }

    func testDetailStopsOnEmptyPageOrRepeatedServerCursor() async throws {
        let first = try archivePage(bvid: "BVfirst", page: 1, total: 3)
        let empty = try decode(SpaceCollectionArchivePage.self, """
            {"archives":[],"page":{"num":2,"size":1,"total":3}}
            """)
        let collection = try XCTUnwrap(directory(seasonID: 7, page: 1, total: 1).collections.first)
        for second in [empty, first] {
            let requests = Mutex<[Int]>([])
            var services = services()
            services.community.spaceSeasonArchivesOperation = { _, _, page, _ in
                requests.withLock { $0.append(page) }
                guard page <= 2 else {
                    XCTFail("Unexpected page \(page)")
                    throw CancellationError()
                }
                return page == 1 ? first : second
            }
            let model = SpaceCollectionDetailModel(collection: collection, hostMID: 42, services: services, filtering: .live)
            await model.loadIfNeeded()
            await model.loadReplacementPage()
            await model.loadReplacementPage()

            XCTAssertEqual(requests.withLock { $0 }, [1, 2])
            XCTAssertEqual(model.archives.map(\.bvid), ["BVfirst"])
            XCTAssertFalse(model.list.canLoadMore)
        }
    }

    func testDetailCanManuallyContinueWithVisibleRowsAfterEightFilteredPages() async throws {
        let suite = "neobili.collections.filter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let duration = VideoDurationFilterSettings(defaults: defaults)
        duration.minimumMinutes = 1
        let filtering = VideoFilterDependencies(duration: duration, metadata: .init(defaults: defaults, loader: { _ in
            XCTFail("Fixture archives should already have dimensions")
            return nil
        }))
        let collection = try XCTUnwrap(directory(seasonID: 7, page: 1, total: 1).collections.first)
        var services = services()
        services.community.spaceSeasonArchivesOperation = { _, _, page, _ in
            let visible = page == 1 || page == 10
            // 偶数页因竖屏被滤掉，其余中间页因时长被滤掉。
            let portrait = !visible && page.isMultiple(of: 2)
            let seconds = visible || portrait ? 120 : 30
            let clip = #"{"bvid":"BV\#(page)","duration":\#(seconds),"dimension":{"width":\#(portrait ? 1080 : 1920),"height":\#(portrait ? 1920 : 1080)}}"#
            let firstPageExtra = #",{"bvid":"BVshort","duration":20,"dimension":{"width":1920,"height":1080}}"#
            let data = #"{"archives":[\#(clip)\#(page == 1 ? firstPageExtra : "")],"page":{"num":\#(page),"size":2,"total":20}}"#
            return try JSONDecoder().decode(SpaceCollectionArchivePage.self, from: Data(data.utf8))
        }
        let model = SpaceCollectionDetailModel(collection: collection, hostMID: 42, services: services, filtering: filtering)
        await model.loadIfNeeded()
        for _ in 0..<8 { await model.loadReplacementPage() }

        XCTAssertEqual(model.archives.count, 10)
        XCTAssertEqual(model.archives.hidingKnownPortraitVideos(true, filtering: filtering).map(\.bvid), ["BV1"])
        XCTAssertTrue(model.list.canLoadMore)

        await model.loadReplacementPage()
        XCTAssertEqual(model.archives.hidingKnownPortraitVideos(true, filtering: filtering).map(\.bvid), ["BV1", "BV10"])
        XCTAssertFalse(model.list.canLoadMore)
    }

    func testMalformedContainerDuringRefreshKeepsDirectoryAndArchives() async throws {
        let collectionsJSON = Mutex(#"{"items_lists":{"seasons_list":[{"meta":{"season_id":7}}]}}"#)
        let archivesJSON = Mutex(#"{"archives":[{"bvid":"BVoriginal"}]}"#)
        var services = services()
        services.community.spaceCollectionsOperation = { _, _ in
            try JSONDecoder().decode(SpaceCollectionListPage.self, from: Data(collectionsJSON.withLock { $0 }.utf8))
        }
        services.community.spaceSeasonArchivesOperation = { _, _, _, _ in
            try JSONDecoder().decode(SpaceCollectionArchivePage.self, from: Data(archivesJSON.withLock { $0 }.utf8))
        }
        let model = SpaceCollectionsModel(mid: 42, services: services)
        await model.loadIfNeeded()
        let collection = try XCTUnwrap(model.collections.first)
        let detail = SpaceCollectionDetailModel(collection: collection, hostMID: 42, services: services, filtering: .live)
        await detail.loadIfNeeded()

        for malformed in [#"{"items_lists":{"seasons_list":{}}}"#, #"{"items_lists":{"series_list":{}}}"#,
                          #"{"items_lists":{"page":[]}}"#, #"{"items_lists":{},"page":[]}"#] {
            collectionsJSON.withLock { $0 = malformed }
            let staged = await model.stageRefresh()
            XCTAssertFalse(staged)
            model.commitRefresh()
            XCTAssertEqual(model.collections.map(\.collectionID), [7])
            XCTAssertEqual(model.list.generation, 1)
            XCTAssertNotNil(model.list.errorMessage)
        }

        archivesJSON.withLock { $0 = #"{"archives":{}}"# }
        let staged = await detail.stageRefresh()
        XCTAssertFalse(staged)
        detail.commitRefresh()
        XCTAssertEqual(detail.archives.map(\.bvid), ["BVoriginal"])
        XCTAssertEqual(detail.list.generation, 1)
        XCTAssertNotNil(detail.list.errorMessage)
    }

    func testDirectoryStagesAndDiscardsRefreshAndRejectsOldPage() async throws {
        let initial = try directory(seasonID: 1, page: 1, total: 2)
        let fresh = try directory(seasonID: 2, page: 1, total: 1)
        let late = try directory(seasonID: 3, page: 2, total: 2)
        let gate = SpaceCollectionRequestGate<SpaceCollectionListPage>()
        defer { Task { await gate.cancelAll() } }
        var services = services()
        services.community.spaceCollectionsOperation = { _, _ in try await gate.load() }
        let model = SpaceCollectionsModel(mid: 42, services: services)

        let first = Task { await model.loadIfNeeded() }
        try await waitUntil { await gate.count == 1 }
        await gate.resolve(1, initial)
        await first.value

        let pagination = Task { await model.loadMore() }
        try await waitUntil { await gate.count == 2 }
        let refresh = Task { await model.stageRefresh() }
        try await waitUntil { await gate.count == 3 }
        await gate.resolve(3, fresh)
        let staged = await refresh.value
        XCTAssertTrue(staged)
        XCTAssertEqual(model.collections.map(\.collectionID), [1])
        model.commitRefresh()
        await gate.resolve(2, late)
        await pagination.value
        XCTAssertEqual(model.collections.map(\.collectionID), [2])
        XCTAssertEqual(model.list.generation, 2)

        let discarded = Task { await model.stageRefresh() }
        try await waitUntil { await gate.count == 4 }
        await gate.resolve(4, initial)
        let stagedAgain = await discarded.value
        XCTAssertTrue(stagedAgain)
        model.discardRefresh()
        model.commitRefresh()
        XCTAssertEqual(model.collections.map(\.collectionID), [2])
        XCTAssertEqual(model.list.generation, 2)
    }

    func testDetailDispatchesByKindAndSortRejectsOldResponses() async throws {
        let collection = try XCTUnwrap(directory(seasonID: 7, page: 1, total: 1).collections.first)
        let ascending = try archivePage(bvid: "BVasc", page: 1, total: 1)
        let descending = try archivePage(bvid: "BVdesc", page: 1, total: 2)
        let late = try archivePage(bvid: "BVlate", page: 2, total: 2)
        let gate = SpaceCollectionRequestGate<SpaceCollectionArchivePage>()
        defer { Task { await gate.cancelAll() } }
        var services = services()
        services.community.spaceSeasonArchivesOperation = { mid, id, page, reverse in
            XCTAssertEqual(mid, 42)
            XCTAssertEqual(id, 7)
            if !reverse {
                XCTAssertEqual(page, 1)
                return ascending
            }
            if page == 1 { return descending }
            let result = try await gate.load()
            XCTAssertTrue(Task.isCancelled)
            return result
        }
        services.community.spaceSeriesArchivesOperation = { mid, id, page, reverse in
            XCTAssertEqual(mid, 55)
            XCTAssertEqual(id, 8)
            XCTAssertEqual(page, 1)
            return reverse ? descending : ascending
        }
        let model = SpaceCollectionDetailModel(collection: collection, hostMID: 42, services: services, filtering: .live)
        XCTAssertTrue(model.sortReverse)
        await model.loadIfNeeded()
        XCTAssertEqual(model.archives.map(\.bvid), ["BVdesc"])
        let pagination = Task { await model.loadReplacementPage() }
        try await waitUntil { await gate.count == 1 }
        model.toggleSort()
        XCTAssertFalse(model.sortReverse)
        XCTAssertTrue(model.archives.isEmpty)
        await model.loadIfNeeded()
        await gate.resolve(1, late)
        await pagination.value
        XCTAssertEqual(model.archives.map(\.bvid), ["BVasc"])
        XCTAssertFalse(model.list.hasMore)
        XCTAssertFalse(model.list.isLoadingMore)

        let series = try XCTUnwrap(decode(SpaceCollectionListPage.self, """
            {"items_lists":{"series_list":[{"meta":{"series_id":8,"mid":55}}]}}
            """).collections.first)
        let seriesModel = SpaceCollectionDetailModel(collection: series, hostMID: 42, services: services, filtering: .live)
        XCTAssertTrue(seriesModel.sortReverse)
        await seriesModel.loadIfNeeded()
        XCTAssertEqual(seriesModel.archives.map(\.bvid), ["BVdesc"])
        seriesModel.toggleSort()
        XCTAssertFalse(seriesModel.sortReverse)
        await seriesModel.loadIfNeeded()
        XCTAssertEqual(seriesModel.archives.map(\.bvid), ["BVasc"])
        seriesModel.toggleSort()
        XCTAssertTrue(seriesModel.sortReverse)
        await seriesModel.loadIfNeeded()
        XCTAssertEqual(seriesModel.archives.map(\.bvid), ["BVdesc"])
    }

    func testDetailSortsLoadedPagesByPublicationDateForBothKinds() async throws {
        let collections = try decode(SpaceCollectionListPage.self, """
            {"items_lists":{"seasons_list":[{"meta":{"season_id":7}}],
            "series_list":[{"meta":{"series_id":8}}]}}
            """).collections
        let firstPage = try decode(SpaceCollectionArchivePage.self, """
            {"archives":[{"bvid":"BVold","pubdate":100},{"bvid":"BVunknown"},{"bvid":"BVnew","pubdate":300}],
            "page":{"num":1,"size":3,"total":5}}
            """)
        let secondPage = try decode(SpaceCollectionArchivePage.self, """
            {"archives":[{"bvid":"BVnewest","pubdate":400},{"bvid":"BVequal","pubdate":300}],
            "page":{"num":2,"size":3,"total":5}}
            """)
        var services = services()
        let fetch: @Sendable (Int, Int, Int, Bool) async throws -> SpaceCollectionArchivePage = { _, _, page, _ in
            page == 1 ? firstPage : secondPage
        }
        services.community.spaceSeasonArchivesOperation = fetch
        services.community.spaceSeriesArchivesOperation = fetch
        for collection in collections {
            let model = SpaceCollectionDetailModel(collection: collection, hostMID: 42, services: services, filtering: .live)
            await model.loadIfNeeded()
            XCTAssertEqual(model.archives.map(\.bvid), ["BVnew", "BVold", "BVunknown"])
            await model.loadReplacementPage()
            XCTAssertEqual(model.archives.map(\.bvid), ["BVnewest", "BVnew", "BVequal", "BVold", "BVunknown"])

            model.toggleSort()
            await model.loadIfNeeded()
            await model.loadReplacementPage()
            XCTAssertEqual(model.archives.map(\.bvid), ["BVold", "BVnew", "BVequal", "BVnewest", "BVunknown"])
        }
    }

    func testLiveServiceUsesSignedSpaceRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpaceCollectionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        SpaceCollectionURLProtocol.requests.withLock { $0 = [] }
        let identity = TestNetworking.identity()
        let client = TestNetworking.client(identity: identity, session: session, signWebParameters: { parameters in
            parameters.merging(["w_rid": "fixture", "wts": "123"]) { current, _ in current }
        })
        let service = CommunityService.live(client: client, identity: identity)
        _ = try await service.spaceCollections(mid: 42, page: 2)
        _ = try await service.spaceSeasonArchives(mid: 42, seasonID: 7, page: 3, sortReverse: true)
        _ = try await service.spaceSeasonArchives(mid: 42, seasonID: 7, page: 1, sortReverse: false)
        _ = try await service.spaceSeriesArchives(mid: 42, seriesID: 8, page: 1, sortReverse: true)
        _ = try await service.spaceSeriesArchives(mid: 42, seriesID: 8, page: 4, sortReverse: false)
        let requests = SpaceCollectionURLProtocol.requests.withLock { $0 }
        let expected: [(String, [String: String])] = [
            ("/x/polymer/web-space/seasons_series_list", ["page_num": "2", "page_size": "20"]),
            ("/x/polymer/web-space/seasons_archives_list",
             ["season_id": "7", "page_num": "3", "page_size": "30", "sort_reverse": "true"]),
            ("/x/polymer/web-space/seasons_archives_list",
             ["season_id": "7", "page_num": "1", "page_size": "30", "sort_reverse": "false"]),
            ("/x/series/archives", ["series_id": "8", "pn": "1", "ps": "30", "sort": "desc", "only_normal": "true"]),
            ("/x/series/archives", ["series_id": "8", "pn": "4", "ps": "30", "sort": "asc", "only_normal": "true"])
        ]
        XCTAssertEqual(requests.count, expected.count)
        for (request, (path, parameters)) in zip(requests, expected) {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, path)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://space.bilibili.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://space.bilibili.com/42/lists")
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            for (name, value) in parameters.merging(["mid": "42", "w_rid": "fixture", "wts": "123"],
                                                     uniquingKeysWith: { current, _ in current }) {
                XCTAssertEqual(query.first { $0.name == name }?.value, value)
            }
        }
    }

    private func services() -> ApplicationServices {
        let sessionID = UUID()
        return ApplicationServices(session: .init(currentID: { sessionID }, homeAccount: {
            .init(accountID: nil, hasAppCredential: false)
        }))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func directory(seasonID: Int, page: Int, total: Int) throws -> SpaceCollectionListPage {
        try decode(SpaceCollectionListPage.self, """
            {"items_lists":{"seasons_list":[{"meta":{"season_id":\(seasonID)}}],
            "page":{"page_num":\(page),"page_size":1,"total":\(total)}}}
            """)
    }

    private func archivePage(bvid: String, page: Int, total: Int) throws -> SpaceCollectionArchivePage {
        try decode(SpaceCollectionArchivePage.self, """
            {"archives":[{"bvid":"\(bvid)"}],"page":{"num":\(page),"size":1,"total":\(total)}}
            """)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Injected request did not start")
        throw CancellationError()
    }
}

private actor SpaceCollectionRequestGate<Value: Sendable> {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<Value, Error>] = [:]

    func load() async throws -> Value {
        count += 1
        let id = count
        return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }

    func resolve(_ id: Int, _ value: Value) {
        pending.removeValue(forKey: id)?.resume(returning: value)
    }

    func cancelAll() {
        let requests = Array(pending.values)
        pending.removeAll()
        for request in requests { request.resume(throwing: CancellationError()) }
    }
}

private final class SpaceCollectionURLProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requests.withLock { $0.append(request) }
        let body = #"{"code":0,"data":{"items_lists":{},"archives":[]}}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
