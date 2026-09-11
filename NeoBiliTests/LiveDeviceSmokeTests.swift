import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// 显式启用的真机联网验收，不进入日常离线回归；不输出登录凭据和带签名的媒体 URL。
@MainActor
final class LiveDeviceSmokeTests: XCTestCase {
    func testPublicLiveRoomRendersAndCanPauseOnPhysicalDevice() async throws {
        try requireLiveSmoke()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var openedContainers: [String] = []
        let model = LivePlayerModel(
            room: LiveRoom(roomID: 6, title: "直播间", username: "主播"),
            sourceOpener: { session, source, _ in
                // 只记录容器和尝试次数，绝不把服务器 URL/签名带入测试附件。
                openedContainers.append(source.video.primary.pathExtension.lowercased())
                try await session.open(source: source)
            },
            publishesSystemMedia: false
        )
        let host = UIHostingController(rootView: LiveRoomView(player: model)
            .environment(AccountStore(monitorNetwork: false)).environment(ActionFeedback()))
        window.rootViewController = host
        let playbackStartedAt = ContinuousClock.now
        window.makeKeyAndVisible()
        defer {
            model.stop()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
            OrientationController.enterPortrait()
        }
        let deadline = Date().addingTimeInterval(65)
        while !model.hasRenderedFirstFrame, !model.isOffline, model.errorMessage == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let startupDuration = playbackStartedAt.duration(to: .now)
        let firstFrameSeconds = Double(startupDuration.components.seconds) + Double(startupDuration.components.attoseconds) / 1e18
        XCTAssertFalse(model.isOffline, "测试用公开直播间当前未开播，请选择其他正在直播的房间")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.hasRenderedFirstFrame, "mpv 必须收到真实媒体首帧事件")
        XCTAssertGreaterThan(model.displayAspectRatio ?? 0, 0, "必须收到实际视频解码画幅")
        guard model.hasRenderedFirstFrame else { return }
        try await Task.sleep(for: .milliseconds(180))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "live-room-physical-device"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        model.pause()
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertFalse(model.isPlaying)
        model.play()
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertTrue(model.isPlaying)
        let evidence = XCTAttachment(string: "roomID=\(model.room.roomID)\nfirstFrame=\(model.hasRenderedFirstFrame)\nfirstFrameSeconds=\(firstFrameSeconds)\nstreamAttempts=\(openedContainers.count)\ncontainers=\(openedContainers.joined(separator: ","))\naspect=\(model.displayAspectRatio ?? 0)\nquality=\(model.selectedQuality)\nqualityCount=\(model.qualities.count)\npauseResume=passed")
        evidence.name = "live-playback-evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testLiveDirectoryWithNormalAppSessionOnPhysicalDevice() async throws {
        try requireLiveSmoke()
        // 走应用正常的会话恢复，不在测试中提取或输出用户凭据。
        let account = AccountStore(monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        let hasAppKey = await DeviceIdentity.shared.accessKey?.isEmpty == false
        let sessionEvidence = XCTAttachment(string: "hasWebSession=\(account.isLoggedIn)\nhasAppCredential=\(hasAppKey)")
        sessionEvidence.name = "live-session-availability"
        sessionEvidence.lifetime = .keepAlways
        add(sessionEvidence)
        do {
            let page = try await LiveAPI.recommended()
            XCTAssertFalse(page.rooms.isEmpty)
            let evidence = XCTAttachment(string: "recommended=\(page.rooms.count)\nhasMore=\(page.hasMore)")
            evidence.name = "live-directory-evidence"
            evidence.lifetime = .keepAlways
            add(evidence)
            try await captureDirectory(page, account: account)
        } catch {
            XCTFail("正常App会话直播推荐请求失败：\(error.localizedDescription)")
        }
        if account.isLoggedIn {
            do {
                let page = try await LiveAPI.followed()
                XCTAssertTrue(page.rooms.allSatisfy(\.isLive))
                let evidence = XCTAttachment(string: "liveFollowedRooms=\(page.rooms.count)\nhasMore=\(page.hasMore)")
                evidence.name = "live-following-evidence"
                evidence.lifetime = .keepAlways
                add(evidence)
            } catch {
                XCTFail("正常App会话直播关注请求失败：\(error.localizedDescription)")
            }
        }
    }

    private func captureDirectory(_ page: LiveRoomPage, account: AccountStore) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let model = LiveFeedModel { _, _ in page }
        let host = UIHostingController(rootView: LiveView(model: model, onOpenRoom: { _ in }).environment(account))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(800))
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "live-recommendations-real-response"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func requireLiveSmoke() throws {
        guard ProcessInfo.processInfo.environment["NEOBILI_LIVE_SMOKE"] == "1" else {
            throw XCTSkip("仅显式启用的真机联网验收运行")
        }
        XCTAssertFalse(PlatformInfo.isSimulator)
    }
}
