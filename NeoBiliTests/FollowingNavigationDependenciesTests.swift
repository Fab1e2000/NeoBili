import SwiftUI
import Synchronization
import XCTest
@testable import NeoBili
@testable import NeoBiliDomain

@MainActor
final class FollowingNavigationDependenciesTests: XCTestCase {
    func testFollowingThroughAllUpsAndSpaceToDynamicDetailUsesInjectedGraph() async throws {
        let suite = "following-navigation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: CardAnimationSettings.masterKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let stores = ApplicationStores(likes: VideoLikeStore(),
            followingRead: FollowingReadStore(defaults: defaults), searchHistory: SearchHistory(defaults: defaults))
        let up = FollowedUp(mid: 42, uname: "注入 UP 主", face: "", hasUpdate: true)
        let decoder = JSONDecoder()
        let profile = try decoder.decode(AccountProfilePayload.self, from: Data(#"""
            {"isLogin":true,"mid":99,"uname":"注入账号","face":"","money":0}
            """#.utf8))
        let account = AccountStore(client: .init(credentials: { .init(hasCredentials: true, accountID: 99) },
            save: { _, _ in }, clear: {}, profile: { profile }),
            defaults: defaults, likeStore: stores.likes, monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        XCTAssertTrue(account.isLoggedIn)

        let recorder = Calls()
        let services = try makeServices(up: up, recorder: recorder)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let host = UIHostingController(rootView: AnyView(Color.clear))
        let playback = PlaybackDependencies.isolated(defaults: defaults)
        let player = NowPlayingStore(defaults: defaults, dependencies: playback)
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previous?.makeKey()
                player.close()
            }
            try await self.wait("navigation settles before window removal") { !self.isTransitioning(host) }
            if let presenter = self.presentedController(in: host)?.presentingViewController {
                await withCheckedContinuation { continuation in
                    presenter.dismiss(animated: false) { continuation.resume() }
                }
            }
            host.rootView = AnyView(Color.clear)
            host.view.layoutIfNeeded()
            await Task.yield()
        }
        OrientationController.enterPortrait()
        try await wait("portrait test window becomes key") {
            scene.effectiveGeometry.interfaceOrientation.isPortrait && window.isKeyWindow && !isTransitioning(host)
        }
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        host.rootView = AnyView(TabView {
            Tab("关注", systemImage: "person.2") { FollowingView() }
        }
        .environment(account)
        .environment(player)
        .environment(ActionFeedback())
        .environment(\.applicationServices, services)
        .environment(\.applicationStores, stores)
        .environment(\.videoPreparation, playback.preparation)
        .defaultAppStorage(defaults))

        try await wait("injected portal and following feed") {
            recorder.contains("portal") && recorder.contains("following:all:1")
        }
        XCTAssertTrue(stores.followingRead.hasUpdate(up))
        try await activate("following.avatar.42", in: host)
        try await wait("avatar clears the selected UP's unread state") { !stores.followingRead.hasUpdate(up) }
        try await wait("selected UP feed request") { recorder.contains("following:42:1") }

        try await activate("dynamic.like.1001", in: host)
        try await wait("optimistic like and injected write") {
            recorder.contains("like:1001:true") && stores.likes.isLiked(.dynamic("1001"), serverValue: false)
        }

        try await activate("following.allFollowings", in: host)
        try await wait("injected All Ups page") { recorder.contains("followings:99:1") }
        let allUps: UIViewController = try await waitForValue("visible All Ups destination") {
            navigationPage(titled: "全部关注", in: host)
        }
        try await activate("following.allUp.42", in: allUps)
        try await wait("injected Space profile and videos") {
            recorder.contains("profile:42") && recorder.contains("videos:42:1")
        }
        let space: UIViewController = try await waitForValue("visible Space destination") {
            navigationPage(titled: up.uname, in: host)
        }
        let segment: UISegmentedControl = try await waitForValue("visible Space tabs after push") {
            guard let view = settledView(in: space) else { return nil }
            return accessibilityItem(in: view) { $0 is UISegmentedControl } as? UISegmentedControl
        }
        segment.selectedSegmentIndex = try XCTUnwrap((0..<segment.numberOfSegments).first {
            segment.titleForSegment(at: $0) == "动态"
        })
        segment.sendActions(for: .valueChanged)
        try await wait("injected Space dynamics") { recorder.contains("space:42") }
        try await activate("dynamic.comments.1001", in: space)
        let detail: UIViewController = try await waitForValue("presented Dynamic Detail controller") {
            guard let detail = presentedController(in: host), settledView(in: detail) != nil else { return nil }
            return detail
        }
        try await wait("injected Dynamic Detail comments") { recorder.contains("comments:123:17:1") }

        // The server returns an unliked snapshot in both lists. The detail
        // must read the injected override from the first list and send unlike.
        try await activate("dynamic.detail.like", in: detail)
        try await wait("unlike over the shared override") {
            recorder.contains("like:1001:false") && !stores.likes.isLiked(.dynamic("1001"), serverValue: true)
        }
        XCTAssertEqual(recorder.likeCalls, ["like:1001:true", "like:1001:false"])
    }

    private func makeServices(up: FollowedUp, recorder: Calls) throws -> ApplicationServices {
        let decoder = JSONDecoder()
        func feed(id: String) throws -> DynamicFeedPage {
            try decoder.decode(DynamicFeedPage.self, from: Data(#"""
            {"items":[{"id_str":"\#(id)","type":"DYNAMIC_TYPE_WORD",
              "basic":{"comment_id_str":"123","comment_type":17},
              "modules":{
                "module_author":{"mid":42,"name":"注入 UP 主"},
                "module_dynamic":{"desc":{"text":"注入动态正文"}},
                "module_stat":{"like":{"count":0,"status":false}}
              }}],"has_more":false}
            """#.utf8))
        }
        let allFeed = try feed(id: "1000")
        let selectedFeed = try feed(id: "1001")
        let followings = try decoder.decode(FollowingsPage.self, from: Data(#"""
            {"list":[{"mid":42,"uname":"注入 UP 主","face":""}],"total":1}
            """#.utf8))
        let videos = try decoder.decode(SpaceVideoPage.self, from: Data(#"{"list":{"vlist":[]}}"#.utf8))
        let card = SpaceCard(mid: up.mid, name: up.uname, face: "", sign: "", level: 1,
            isVIP: false, banner: nil, follower: 0, followingCount: 0, likeCount: 0,
            archiveCount: 0, isFollowing: true)
        let session = UUID()
        return ApplicationServices(session: .init(currentID: { session },
                homeAccount: { .init(accountID: 99, hasAppCredential: false) }),
            comment: .init(commentsOperation: { oid, type, page, _ in
                recorder.record("comments:\(oid):\(type):\(page)")
                return .init(page: .init(num: 1, size: 20, count: 0), replies: [])
            }),
            streaming: .init(followedUsersOperation: { .init(rooms: [], page: 1, hasMore: false) }),
            community: .init(
                followedUpsOperation: { recorder.record("portal"); return [up] },
                followingsOperation: { mid, page in recorder.record("followings:\(mid):\(page)"); return followings },
                followedDynamicsOperation: { page, _, mid in
                    recorder.record("following:\(mid.map(String.init) ?? "all"):\(page)")
                    return mid == nil ? allFeed : selectedFeed
                },
                spaceDynamicsOperation: { mid, _ in recorder.record("space:\(mid)"); return selectedFeed },
                likeDynamicOperation: { id, likes in recorder.record("like:\(id):\(likes)") },
                spaceProfileOperation: { mid in recorder.record("profile:\(mid)"); return card },
                spaceVideosOperation: { mid, page in recorder.record("videos:\(mid):\(page)"); return videos }))
    }

    private func activate(
        _ id: String, in controller: UIViewController,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        // SwiftUI accessibility nodes can expose the getter without conforming to the UIKit protocol.
        let identifierGetter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        let element: NSObject = try await waitForValue(id, file: file, line: line) {
            guard let view = settledView(in: controller), let window = view.window else { return nil }
            return accessibilityItem(in: view) { item in
                guard item.accessibilityTraits.contains(.button),
                      !item.accessibilityTraits.contains(.notEnabled),
                      item.responds(to: identifierGetter),
                      let identifier = item.perform(identifierGetter)?.takeUnretainedValue() as? String,
                      identifier == id else { return false }
                let frame = window.convert(item.accessibilityFrame, from: window.screen.coordinateSpace)
                return window.bounds.intersects(frame)
            }
        }
        guard element.accessibilityActivate() else {
            XCTFail("Could not activate \(id)", file: file, line: line)
            throw URLError(.cannotParseResponse)
        }
    }

    private func settledView(in controller: UIViewController) -> UIView? {
        guard !isTransitioning(controller), let view = controller.viewIfLoaded, view.window != nil else { return nil }
        view.layoutIfNeeded()
        return view
    }

    private func isTransitioning(_ controller: UIViewController) -> Bool {
        if controller.transitionCoordinator != nil || controller.isBeingPresented || controller.isBeingDismissed {
            return true
        }
        if let presented = controller.presentedViewController, isTransitioning(presented) { return true }
        return controller.children.contains { $0.viewIfLoaded?.window != nil && isTransitioning($0) }
    }

    private func presentedController(in controller: UIViewController) -> UIViewController? {
        if let presented = controller.presentedViewController { return presented }
        return controller.children.lazy.compactMap { self.presentedController(in: $0) }.first
    }

    private func navigationPage(titled title: String, in controller: UIViewController) -> UIViewController? {
        if let navigation = controller as? UINavigationController,
           navigation.navigationBar.topItem?.title == title,
           let page = navigation.topViewController,
           settledView(in: navigation) != nil, settledView(in: page) != nil {
            return page
        }
        return controller.children.lazy.compactMap { self.navigationPage(titled: title, in: $0) }.first
    }

    private func wait(
        _ event: String, file: StaticString = #filePath, line: UInt = #line, until ready: () -> Bool
    ) async throws {
        _ = try await waitForValue(event, file: file, line: line) { ready() ? true : nil }
    }

    private func waitForValue<Value>(
        _ event: String, file: StaticString = #filePath, line: UInt = #line, _ value: () -> Value?
    ) async throws -> Value {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let value = value() { return value }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(event)", file: file, line: line)
        throw URLError(.timedOut)
    }

    private final class Calls: Sendable {
        private let values = Mutex<[String]>([])
        func record(_ call: String) { values.withLock { $0.append(call) } }
        func contains(_ call: String) -> Bool { values.withLock { $0.contains(call) } }
        var likeCalls: [String] { values.withLock { $0.filter { $0.hasPrefix("like:") } } }
    }
}
