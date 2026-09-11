import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Opt-in playback against the phone's normal account. Evidence deliberately
/// contains only quality IDs, dimensions and states, never credentials/URLs.
@MainActor
final class VideoQualityDeviceSmokeTests: XCTestCase {
    func testAuthorized4KSelectionRendersRealDecodedFramesOnPhysicalDevice() async throws {
        guard ProcessInfo.processInfo.environment["NEOBILI_VIDEO_QUALITY_SMOKE"] == "1" else {
            throw XCTSkip("仅在 NEOBILI_VIDEO_QUALITY_SMOKE=1 时执行真机4K联网验收")
        }
        guard !PlatformInfo.isSimulator else {
            XCTFail("此验收只允许真机")
            return
        }

        let account = AccountStore(monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        guard account.isLoggedIn else {
            throw XCTSkip("手机未恢复已登录的正常账号，无法验证账号的4K播放权限")
        }
        guard account.profile != nil, account.sessionError == nil else {
            XCTFail("服务器未能确认当前账号状态；没有将网络问题当作4K权限不足")
            return
        }

        let suite = "neobili.4k.device-smoke.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let evidence = VideoQualityServerEvidence()
        let player = PlayerViewModel(
            bvid: "BV1po4y177z8", cid: 1_163_679_532,
            playbackURLLoader: { bvid, cid in
                do {
                    let payload = try await BiliAPI.playURL(bvid: bvid, cid: cid)
                    await evidence.record(payload, requested: 127)
                    return payload
                } catch {
                    await evidence.recordFailure(error)
                    throw error
                }
            },
            qualityPlaybackURLLoader: { bvid, cid, quality in
                do {
                    let payload = try await BiliAPI.playURL(bvid: bvid, cid: cid, quality: quality)
                    await evidence.record(payload, requested: quality)
                    return payload
                } catch {
                    await evidence.recordFailure(error)
                    throw error
                }
            },
            watchProgressReporter: { _, _, _ in },
            progressStore: PlaybackProgressStore(defaults: defaults)
        )
        defer { player.stop() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: VideoQualitySmokeSurface(player: player))
        host.safeAreaRegions = []
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer {
            player.stop()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }

        let initialLoad = Task { await player.load() }
        defer { initialLoad.cancel() }
        await waitUntil(seconds: 45) { player.hasRenderedFirstFrame || player.errorMessage != nil }
        try await skipIfServerExplicitlyDenied(evidence, account: account)
        guard player.errorMessage == nil, player.hasRenderedFirstFrame, !player.isLoading else {
            attachEvidence(player, status: "initial_frame_failed")
            XCTFail("默认画质未在45秒内收到真实首帧，或播放器报错；详细地址未写入日志")
            return
        }
        guard player.availableVideoQualities.contains(120) else {
            attachEvidence(player, status: "server_did_not_declare_120")
            XCTFail("该4K源的服务端声明列表未包含120；没有将该结果假定为账号未授权")
            return
        }

        var selectionFinished = false
        var selectionHadMessage = false
        let selection = Task {
            let message = await player.selectQuality(video: 120)
            selectionHadMessage = message != nil
            selectionFinished = true
        }
        defer { selection.cancel() }
        await waitUntil(seconds: 45) { selectionFinished || player.errorMessage != nil }
        try await skipIfServerExplicitlyDenied(evidence, account: account)
        guard selectionFinished, !selectionHadMessage, player.errorMessage == nil else {
            attachEvidence(player, status: "selection_failed")
            XCTFail("4K选择未完成或服务端未下发可播放轨道；只有明确权限拒绝才跳过")
            return
        }
        XCTAssertEqual(player.selectedVideoQuality, 120, "必须实际选中120，不能把降级响应当作4K成功")
        XCTAssertTrue(is4K(width: player.selectedVideoWidth, height: player.selectedVideoHeight),
                      "实际选中DASH轨道的宽度须至少3840或高度至少2160")
        await waitUntil(seconds: 45) {
            player.errorMessage != nil || (player.hasRenderedFirstFrame
                && is4K(width: player.decodedVideoWidth, height: player.decodedVideoHeight))
        }
        attachEvidence(player, status: player.errorMessage == nil ? "decode_completed" : "decode_failed")
        XCTAssertTrue(player.errorMessage == nil, "4K解码阶段播放器报错，原始错误/媒体URL未写入日志")
        XCTAssertTrue(player.hasRenderedFirstFrame, "mpv必须收到真实的4K首帧事件")
        XCTAssertTrue(is4K(width: player.decodedVideoWidth, height: player.decodedVideoHeight),
                      "必须是mpv实际解码尺寸；不能用源metadata或16:9比例代替4K证据")
        XCTAssertEqual(player.selectedVideoQuality, 120)
    }

    private func skipIfServerExplicitlyDenied(_ evidence: VideoQualityServerEvidence,
                                              account: AccountStore) async throws {
        if await evidence.loginRejected {
            throw XCTSkip("播放接口明确返回未登录(-101)，当前正常账号会话未获授权；未执行4K成功断言")
        }
        if account.profile?.isVIP == false, account.sessionError == nil,
           await evidence.requested4KButOnlyVIPTrackWasWithheld {
            throw XCTSkip("正常账号资料显示非大会员；显式qn=120响应要求大会员且未下发120轨道，无法验证授权4K播放")
        }
    }

    private func is4K(width: Int?, height: Int?) -> Bool {
        guard let width, let height, width > 0, height > 0 else { return false }
        return width >= 3840 || height >= 2160
    }

    private func waitUntil(seconds: TimeInterval, _ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate(), Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func attachEvidence(_ player: PlayerViewModel, status: String) {
        let evidence = XCTAttachment(string: "status=\(status)\navailableQualityIDs=\(player.availableVideoQualities)\nselectedQuality=\(player.selectedVideoQuality ?? 0)\ntrackWidth=\(player.selectedVideoWidth ?? 0)\ntrackHeight=\(player.selectedVideoHeight ?? 0)\ndecodedWidth=\(player.decodedVideoWidth ?? 0)\ndecodedHeight=\(player.decodedVideoHeight ?? 0)\nfirstFrame=\(player.hasRenderedFirstFrame)\nisPlaying=\(player.isPlaying)")
        evidence.name = "video-4k-safe-evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}

private struct VideoQualitySmokeSurface: View {
    let player: PlayerViewModel
    var body: some View {
        PlayerSurface(session: player.session)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .ignoresSafeArea()
    }
}

private actor VideoQualityServerEvidence {
    private(set) var loginRejected = false
    private(set) var requested4KButOnlyVIPTrackWasWithheld = false
    private var serverRequiresVIPFor4K = false

    func record(_ payload: PlayURLData, requested: Int) {
        if let format = payload.supportFormats?.first(where: { $0.quality == 120 }) {
            serverRequiresVIPFor4K = format.needsVIP == true
        }
        guard requested == 120 else { return }
        requested4KButOnlyVIPTrackWasWithheld = !payload.hasVideoStream(quality: 120)
            && serverRequiresVIPFor4K
    }

    func recordFailure(_ error: any Error) {
        if case BiliAPIError.apiError(let code, _) = error, code == -101 { loginRejected = true }
    }
}
