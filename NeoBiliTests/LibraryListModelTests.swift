import XCTest
import SwiftUI
import Synchronization
@testable import NeoBili
import NeoBiliDomain

@MainActor
final class LibraryListModelTests: XCTestCase {
    private let folder = FavFolder(id: 1, title: "收藏", mediaCount: 20)

    private func services() -> ApplicationServices {
        let session = UUID()
        return ApplicationServices(session: .init(currentID: { session }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
    }

    private func favorites(_ ids: [Int]) throws -> FavResourceList {
        let rows = ids.map { ["id": $0, "type": 2, "title": "测试"] as [String: Any] }
        return try JSONDecoder().decode(FavResourceList.self, from: JSONSerialization.data(withJSONObject: ["medias": rows]))
    }

    func testFavoritesRefreshSupersedesPaginationAndPrunesSelection() async throws {
        let model = FavoriteFolderListModel()
        let oldPage = PendingModelResult<FavResourceList>()
        let first = try favorites(Array(1...20)), fresh = try favorites([1, 30])
        var initial = services()
        initial.library.favoriteVideosOperation = { _, page in
            if page == 1 { return first }
            return await oldPage.value()
        }
        await model.reload(services: initial, folder: folder)
        let pending = Task { await model.loadNextPage(services: initial, folder: folder, refreshing: false) }
        await waitForPendingRequest { oldPage.isWaiting }
        model.selectedIDs = [1, 2]
        var updated = services()
        updated.library.favoriteVideosOperation = { _, page in
            XCTAssertEqual(page, 1)
            return fresh
        }
        let staged = await model.stageReload(services: updated, feedback: ActionFeedback(), folder: folder)
        XCTAssertTrue(staged)
        XCTAssertEqual(model.videos.map(\.id), Array(1...20))
        await model.loadNextPage(services: updated, folder: folder, refreshing: false)
        model.commitStagedReload()
        oldPage.resolve(first)
        await pending.value
        XCTAssertEqual(model.videos.map(\.id), [1, 30])
        XCTAssertEqual(model.selectedIDs, [1])
        XCTAssertFalse(model.isLoadingMore)
    }

    func testHistoryAndFavoritesUseTheSameErrorDescriptionForFirstAndNextPages() async {
        let timeout = URLError(.timedOut)
        var services = services()
        services.library.historyPageOperation = { _, _ in throw timeout }
        services.library.favoriteVideosOperation = { _, _ in throw timeout }
        let history = HistoryListModel()
        let favorites = FavoriteFolderListModel()

        await history.reload(services: services)
        await favorites.reload(services: services, folder: folder)
        XCTAssertEqual(history.errorMessage, timeout.loadFailureDescription)
        XCTAssertEqual(favorites.errorMessage, timeout.loadFailureDescription)

        await history.loadNextPage(services: services, refreshing: false)
        await favorites.loadNextPage(services: services, folder: folder, refreshing: false)
        XCTAssertEqual(history.errorMessage, timeout.loadFailureDescription)
        XCTAssertEqual(favorites.errorMessage, timeout.loadFailureDescription)
    }

    func testHistoryRemovalDiscardsLatePageAndRestoresOriginalOrderOnFailure() async throws {
        let model = HistoryListModel(), feedback = ActionFeedback()
        let initial = try JSONDecoder().decode(HistoryCursorPage.self, from: Data(#"""
        {"cursor":{"max":3,"view_at":42},"list":[
        {"title":"A","history":{"business":"archive","oid":1,"bvid":"BV1"}},
        {"title":"B","history":{"business":"archive","oid":2,"bvid":"BV2"}}]}
        """#.utf8))
        let page = PendingModelResult<HistoryCursorPage>()
        var services = services()
        services.library.historyPageOperation = { max, time in
            if max == 0 { return initial }
            XCTAssertEqual(time, 42)
            return await page.value()
        }
        services.library.deleteHistoryOperation = { _, _ in throw URLError(.notConnectedToInternet) }
        let client = AccountSessionClient(credentials: { .init(hasCredentials: false, accountID: nil) },
            save: { _, _ in }, clear: {}, profile: { throw URLError(.notConnectedToInternet) })
        let suite = "library.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = AccountStore(client: client, defaults: defaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        await model.reload(services: services)
        let pagination = Task { await model.loadNextPage(services: services, refreshing: false) }
        await waitForPendingRequest { page.isWaiting }
        let item = try XCTUnwrap(model.items.first)
        let deletion = Task { await model.delete(item, services: services, account: account, feedback: feedback, refreshing: false) }
        await waitForPendingRequest { feedback.canUndo }
        page.resolve(initial)
        await pagination.value
        XCTAssertEqual(model.items.map(\.title), ["B"])
        feedback.show("提交删除")
        await deletion.value
        XCTAssertEqual(model.items.map(\.title), ["A", "B"])
    }
    func testHistoryWindowRefreshesAndRemovesSelectedRowFromItsMenu() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let first = try historyPage(1), second = try historyPage(2)
        let pages = AsyncStream<HistoryCursorPage>.makeStream()
        pages.continuation.yield(first)
        let feedback = ActionFeedback()
        let session = UUID()
        var services = ApplicationServices(session: .init(currentID: { session }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        services.library.historyPageOperation = { _, _ in
            for await page in pages.stream { return page }
            throw CancellationError()
        }
        let removal = Mutex(false)
        services.library.deleteHistoryOperation = { kid, expected in
            XCTAssertEqual(kid, "archive_2")
            XCTAssertEqual(expected, session)
            removal.withLock { $0 = true }
        }
        let suite = "library.window.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); pages.continuation.finish() }
        let client = AccountSessionClient(credentials: { .init(hasCredentials: false, accountID: nil) },
            save: { _, _ in }, clear: {}, profile: { throw URLError(.notConnectedToInternet) })
        let account = AccountStore(client: client, defaults: defaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        let dependencies = PlaybackDependencies.isolated(defaults: defaults)
        let player = NowPlayingStore(defaults: defaults, dependencies: dependencies)
        defer { player.close() }
        let host = UIHostingController(rootView: NavigationStack { HistoryView() }
            .environment(\.applicationServices, services).environment(\.hidesPortraitVideos, false)
            .environment(\.videoPreparation, dependencies.preparation)
            .environment(account).environment(feedback).environment(player))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await TestWindowTransition.wait(for: host)
        func marker(_ id: String, in view: UIView) -> ResolvedMenuMarkerView<String>? {
            if let card = view as? ResolvedMenuMarkerView<String>, card.id == id { return card }
            for child in view.subviews {
                if let card = marker(id, in: child) { return card }
            }
            return nil
        }
        func removalButton() -> NSObject? {
            accessibilityItem(in: window) { item in
                item.accessibilityTraits.contains(.button) && (item.accessibilityLabel == "移出所选" ||
                    (item as? UIAccessibilityIdentification)?.accessibilityIdentifier == "library.selection.remove")
            }
        }
        try await waitFor("initial history row") { marker("archive-1", in: window) != nil }
        let pull = try XCTUnwrap(accessibilityItem(in: window) { $0 is ShortPullRefresh.ObserverView } as? ShortPullRefresh.ObserverView)
        let refresh = try XCTUnwrap(pull.onRefresh)
        refresh()
        pages.continuation.yield(second)
        try await waitFor("refreshed row and enabled selection menu") {
            marker("archive-2", in: window)?.registry?.menu("archive-2").children.contains {
                ($0 as? UIAction).map { $0.title == "多选" && !$0.attributes.contains(.disabled) } == true
            } == true
        }
        let menu = try XCTUnwrap(marker("archive-2", in: window)?.registry?.menu("archive-2"))
        let select = try XCTUnwrap(menu.children.first { $0.title == "多选" } as? UIAction)
        UIButton(primaryAction: select).sendActions(for: .primaryActionTriggered)
        try await waitFor("selection bar") { removalButton() != nil }
        XCTAssertTrue(try XCTUnwrap(removalButton()).accessibilityActivate())
        try await waitFor("undo window") { feedback.canUndo }
        feedback.show("确认")
        try await waitFor("removal request") { removal.withLock { $0 } }
        try await waitFor("selected row removed") { marker("archive-2", in: window) == nil }
    }

    private func historyPage(_ id: Int) throws -> HistoryCursorPage {
        try JSONDecoder().decode(HistoryCursorPage.self, from: Data("""
        {"list":[{"title":"测试","history":{"business":"archive","oid":\(id),"bvid":"BV\(id)"}}]}
        """.utf8))
    }

    private func waitFor(_ event: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for " + event)
                throw NSError(domain: "LibraryListModelTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for " + event])
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

}
