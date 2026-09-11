import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// 本地资料展示生产组件；以后在真机执行，不调用真实关注接口或直播网络。
@MainActor
final class LiveRoomDetailStyleTests: XCTestCase {
    func testGlassOwnerTitleAndDescriptionLayoutsOnPhysicalDevice() async throws {
        XCTAssertFalse(PlatformInfo.isSimulator)
        var availableScene: UIWindowScene?
        for _ in 0..<100 {
            availableScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if availableScene != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(availableScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let longTitle = "晚间音乐现场：一起听歌聊天，分享今天发生的故事与正在循环的好音乐"
        let cases: [(String, String, Bool, ColorScheme, DynamicTypeSize)] = [
            ("light-short-collapsed", "一起听歌", false, .light, .large),
            ("light-long-collapsed", longTitle, false, .light, .large),
            ("dark-long-expanded", longTitle, true, .dark, .large),
            ("large-type-expanded", longTitle, true, .light, .xxxLarge)
        ]
        var longCollapsedHeight: CGFloat = 0
        for (name, title, expanded, scheme, textSize) in cases {
            let room = LiveRoom(roomID: 7734200, title: title, username: "测试主播", uid: 42,
                                online: 216_800, areaName: "音乐现场",
                                description: "分享每天的音乐与生活。<br>喜欢的歌曲可以在评论里留言，感谢大家来到直播间。",
                                announcement: "每晚八点开播，周五休息。")
            let card = SpaceCard(mid: 42, name: "测试主播", face: "", sign: "", level: 6, isVIP: false,
                                 banner: nil, follower: 12_345, followingCount: 9, likeCount: 0,
                                 archiveCount: 86, isFollowing: true)
            let measurements = LiveDetailMeasurements()
            host.rootView = AnyView(
                ScrollView {
                    VStack(spacing: 14) {
                        LiveRoomOwnerRow(room: room, card: card, isFollowing: true, isLoading: false,
                                         isToggling: false, isOwnAccount: false, onToggleFollow: {})
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measurements.owner = $0 }
                        LiveRoomIntroductionCard(room: room, isOffline: false, isExpanded: .constant(expanded))
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { measurements.introduction = $0 }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .background(Color(uiColor: .systemBackground))
                .dynamicTypeSize(textSize)
                .preferredColorScheme(scheme)
                .id(name)
            )
            for _ in 0..<100 {
                window.layoutIfNeeded()
                if measurements.introduction.height > 0 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(measurements.owner.width, measurements.introduction.width, accuracy: 1, name)
            XCTAssertEqual(measurements.owner.minX, measurements.introduction.minX, accuracy: 1, name)
            XCTAssertGreaterThanOrEqual(measurements.owner.height, 64, name)
            XCTAssertEqual(measurements.introduction.minY - measurements.owner.maxY, 14, accuracy: 1, name)
            if name == "light-long-collapsed" { longCollapsedHeight = measurements.introduction.height }
            if name == "dark-long-expanded" {
                XCTAssertGreaterThan(measurements.introduction.height, longCollapsedHeight + 70,
                                     "Expanding must add body text below the full title")
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "live-room-details-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

@MainActor
private final class LiveDetailMeasurements {
    var owner = CGRect.zero
    var introduction = CGRect.zero
}
