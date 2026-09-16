import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Hosts the production LiveView and LiveRoomCard in a real iPhone window.
/// Account credentials, feed data and cover bitmaps are local fixtures; no
/// Keychain, remote account, stream player or HTTP endpoint is used.
@MainActor
final class LivePageLayoutTests: XCTestCase {
    func testLivePageRecommendationFollowingEmptyAndFailureLayoutsOnRealDevice() async throws {
        let host = try LivePageSnapshotHost()
        defer { host.close() }
        let rooms = await makeRooms()
        let cases: [(String, Bool, LiveFeedModel.Source, [LiveRoom], Bool)] = [
            ("signed-out-recommendations", false, .recommended, rooms, false),
            ("signed-in-recommendations", true, .recommended, rooms, false),
            ("following-rooms", true, .following, rooms, false),
            ("following-empty", true, .following, [], false),
            ("feed-failure", false, .recommended, [], true)
        ]

        for (name, loggedIn, source, fixtureRooms, fails) in cases {
            let suiteName = "NeoBili.LivePageLayoutTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(false, forKey: CardAnimationSettings.masterKey)
            let account = try await makeAccount(loggedIn: loggedIn, defaults: defaults)
            let model = LiveFeedModel { _, page in
                if fails { throw LivePageFixtureError.unavailable }
                return LiveRoomPage(rooms: fixtureRooms, page: page, hasMore: false)
            }
            model.synchronizeAccount(sessionID: account.sessionID, isLoggedIn: account.isLoggedIn)
            model.select(source)
            await model.loadInitial()

            try await host.show(
                LivePageFixtureTabs(model: model)
                    .environment(account)
                    .defaultAppStorage(defaults)
                    .dynamicTypeSize(.large)
                    .preferredColorScheme(.light)
                    .id(name)
            )

            XCTAssertEqual(account.isLoggedIn, loggedIn, name)
            XCTAssertEqual(model.source, source, name)
            XCTAssertEqual(model.rooms.map(\.roomID), fixtureRooms.map(\.roomID), name)
            XCTAssertEqual(model.errorMessage != nil, fails, name)
            XCTAssertEqual(host.controller.view.convert(host.controller.view.bounds, to: host.window),
                           host.window.bounds, "The fixture must use the real full window: \(name)")
            XCTAssertLessThan(host.window.bounds.width, host.window.bounds.height, name)

            let controls = descendants(of: host.controller.view).compactMap { $0 as? UISegmentedControl }
            XCTAssertTrue(controls.contains { $0.numberOfSegments == (loggedIn ? 2 : 1) },
                          "The native source selector must reflect the fixture's account: \(name)")
            let tabBar = try XCTUnwrap(descendants(of: host.controller.view).compactMap { $0 as? UITabBar }.first)
            XCTAssertEqual(tabBar.selectedItem?.title, "直播", name)
            let tabFrame = tabBar.convert(tabBar.bounds, to: host.window)
            XCTAssertTrue(host.window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(tabFrame), name)

            let coordinates = XCTAttachment(string: "window=\(host.window.bounds)\nsafeArea=\(host.window.safeAreaInsets)\nhost=\(host.controller.view.frame)\ntabBar.windowFrame=\(tabFrame)\nsource=\(source)\nroomCount=\(model.rooms.count)\nloggedIn=\(account.isLoggedIn)")
            coordinates.name = "live-page-\(name)-geometry"
            coordinates.lifetime = .keepAlways
            add(coordinates)
            let screenshot = UIGraphicsImageRenderer(bounds: host.window.bounds).image { _ in
                host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "live-page-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func makeAccount(loggedIn: Bool, defaults: UserDefaults) async throws -> AccountStore {
        let profile = try JSONDecoder().decode(AccountProfilePayload.self, from: Data(
            #"{"isLogin":true,"mid":42,"uname":"本地测试账号","face":"","level_info":{"current_level":6}}"#.utf8
        ))
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: loggedIn, accountID: loggedIn ? 42 : nil) },
            save: { _, _ in }, clear: {}, profile: { profile }
        )
        let account = AccountStore(client: client, defaults: defaults,
                                   likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        return account
    }

    private func makeRooms() async -> [LiveRoom] {
        let names = ["周四音乐现场 · 一起听歌到天亮", "城市漫游，聊聊今天的新鲜事",
                     "画一幅雨后的街道｜绘画过程分享", "经典游戏挑战，今天能通关吗"]
        let streamers = ["晚风音乐社", "慢慢看世界", "小岛画室", "星河游戏"]
        let areas = ["音乐现场", "日常", "绘画", "单机游戏"]
        var rooms: [LiveRoom] = []
        for index in names.indices {
            // File URLs ensure that even an unexpected cache miss cannot make
            // an HTTP request. Original-size seeds are used by BiliImage's
            // existing preloaded-image path at every on-screen pixel size.
            let coverURL = URL(fileURLWithPath: "/neobili-layout-fixtures/live-cover-\(index).png")
            let faceURL = URL(fileURLWithPath: "/neobili-layout-fixtures/live-face-\(index).png")
            let color = UIColor(hue: CGFloat(index) * 0.19 + 0.05, saturation: 0.55, brightness: 0.7, alpha: 1)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let cover = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 270), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 480, height: 270))
                UIColor.white.withAlphaComponent(0.16).setFill()
                UIBezierPath(ovalIn: CGRect(x: 275, y: -70, width: 260, height: 260)).fill()
                UIColor.black.withAlphaComponent(0.12).setFill()
                UIBezierPath(roundedRect: CGRect(x: 45, y: 55, width: 245, height: 190), cornerRadius: 24).fill()
                (areas[index] as NSString).draw(at: CGPoint(x: 65, y: 135),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .semibold), .foregroundColor: UIColor.white])
            }
            let face = UIGraphicsImageRenderer(size: CGSize(width: 72, height: 72), format: format).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 72, height: 72))
                (String(streamers[index].prefix(1)) as NSString).draw(at: CGPoint(x: 17, y: 15),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .medium), .foregroundColor: UIColor.white])
            }
            await BiliImageCache.shared.insert(cover, for: coverURL)
            await BiliImageCache.shared.insert(face, for: faceURL)
            rooms.append(LiveRoom(roomID: 9_000_001 + index, title: names[index], username: streamers[index],
                                  coverURL: coverURL, faceURL: faceURL, online: 21_680 + index * 1729,
                                  areaName: areas[index]))
        }
        return rooms
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}

private enum LivePageFixtureError: LocalizedError {
    case unavailable
    var errorDescription: String? { "暂时无法连接直播服务，请检查网络后重试。" }
}

private struct LivePageFixtureTabs: View {
    let model: LiveFeedModel

    var body: some View {
        TabView(selection: .constant(2)) {
            Tab("推荐", systemImage: "house.fill", value: 0) { Color.clear }
            Tab("关注", systemImage: "person.2.fill", value: 1) { Color.clear }
            Tab("直播", systemImage: "dot.radiowaves.left.and.right", value: 2) {
                LiveView(model: model) { _, _ in }
            }
            Tab("我的", systemImage: "person.crop.circle", value: 3) { Color.clear }
        }
    }
}

@MainActor
private final class LivePageSnapshotHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    private let previousKeyWindow: UIWindow?
    private let previousOrientation: UIInterfaceOrientationMask

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.keyWindow
        previousOrientation = OrientationLock.shared.supportedOrientations
        controller = UIHostingController(rootView: AnyView(Color.clear))
        window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func show<Content: View>(_ content: Content) async throws {
        controller.rootView = AnyView(content)
        OrientationController.enterPortrait()
        for _ in 0..<100 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            if window.bounds.height > window.bounds.width { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if let transition = controller.transitionCoordinator, transition.isAnimated {
            await withCheckedContinuation { continuation in
                if !transition.animate(alongsideTransition: nil, completion: { _ in continuation.resume() }) {
                    continuation.resume()
                }
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        OrientationLock.shared.supportedOrientations = previousOrientation
        previousKeyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: previousOrientation)) { _ in }
    }
}
