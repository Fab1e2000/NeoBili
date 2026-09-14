import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class DanmakuRegressionTests: XCTestCase {
    func testVideoColorFieldKeepsItsPositionWhenFontSizeIsMissing() {
        let items = DanmakuLoader.parse(Data("<i><d p=\"1,1,,16711680,0,0,u,1\">红色</d></i>".utf8))
        XCTAssertEqual(items.first?.color, 0xFF0000)
    }

    func testLiveStandardHeaderColorDoesNotRequireExtraJSON() throws {
        let model = LiveDanmakuModel()
        let data = try JSONSerialization.data(withJSONObject: [
            "cmd": "DANMU_MSG", "info": [[0, 1, 25, 0xFF0000], "红色", [123, "观众"]]
        ])
        model.handleFrame(LivePacketCodec.packet(op: 5, protover: 0, seq: 1, body: data))
        XCTAssertEqual(model.messages.last?.color, 0xFF0000)
    }

    func testColorSwitchChangesRenderedPixelsWithoutChangingSourceColor() throws {
        for enabled in [true, false] {
            let engine = DanmakuEngine(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
            engine.mode = .live
            engine.coloredEnabled = enabled
            engine.enqueue(text: "彩色测试", color: 0xFF0000)
            let layer = try XCTUnwrap(engine.layer.sublayers?.first)
            let image = try XCTUnwrap(layer.contents) as! CGImage
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            let redPixels = stride(from: 0, to: bytes.count, by: 4).filter {
                bytes[$0] > 180 && bytes[$0 + 1] < 40 && bytes[$0 + 2] < 40
            }.count
            if enabled { XCTAssertGreaterThan(redPixels, 20) }
            else { XCTAssertEqual(redPixels, 0) }
        }
    }

    func testLivePanelFollowsBurstsAfterMessagesAreTrimmed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let model = LiveDanmakuModel()
        window.rootViewController = UIHostingController(rootView: LiveDanmakuPanel(model: model).frame(height: 280))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        func scroll(in view: UIView) -> UIScrollView? {
            if let view = view as? UIScrollView { return view }
            return view.subviews.compactMap { scroll(in: $0) }.first
        }
        for batch in 0..<4 {
            for index in 0..<90 {
                let body = try JSONSerialization.data(withJSONObject: ["cmd": "DANMU_MSG", "info": [[], "弹幕 \(batch)-\(index)", [123, "观众"]]])
                model.handleFrame(LivePacketCodec.packet(op: 5, protover: 0, seq: 1, body: body))
            }
            try await Task.sleep(for: .milliseconds(500))
            window.layoutIfNeeded()
            let list = try XCTUnwrap(scroll(in: window))
            let gap = list.contentSize.height - list.contentOffset.y - list.bounds.height + list.adjustedContentInset.bottom
            XCTAssertLessThanOrEqual(gap, 5, "新消息和列表裁剪之后必须仍在底部")
        }
    }

    func testOutlineDoesNotDarkenOpaqueGlyphInteriors() throws {
        let engine = DanmakuEngine(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        engine.mode = .live
        let text = "字体笔画内部完整 ABC"
        engine.enqueue(text: text, color: 0xFFFFFF)
        let layer = try XCTUnwrap(engine.layer.sublayers?.first)
        let actual = try XCTUnwrap(layer.contents) as! CGImage
        let format = UIGraphicsImageRendererFormat()
        format.scale = layer.contentsScale
        let reference = UIGraphicsImageRenderer(size: layer.bounds.size, format: format).image { _ in
            (text as NSString).draw(at: CGPoint(x: 2, y: 2), withAttributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: UIColor.white
            ])
        }
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        let expected = pixels(try XCTUnwrap(reference.cgImage)), rendered = pixels(actual)
        var interiors = 0
        for index in stride(from: 0, to: expected.count, by: 4) where expected[index + 3] >= 250 {
            interiors += 1
            XCTAssertGreaterThanOrEqual(rendered[index], 245, "描边不能侵蚀不透明的字形内部")
        }
        XCTAssertGreaterThan(interiors, 100)
        let attachment = XCTAttachment(image: UIImage(cgImage: actual, scale: layer.contentsScale, orientation: .up))
        attachment.name = "danmaku-solid-fill"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEarlierCommentKeepsMovingWhenTrackIsReused() throws {
        let engine = DanmakuEngine(frame: CGRect(x: 0, y: 0, width: 400, height: 24))
        engine.mode = .live
        engine.enqueue(text: "第一条弹幕", color: 0xFFFFFF)
        let first = try XCTUnwrap(engine.layer.sublayers?.first)
        engine.advance(by: 2)
        engine.enqueue(text: "第二条弹幕", color: 0xFFFFFF)
        XCTAssertEqual(engine.layer.sublayers?.count, 2)
        let previousX = first.position.x
        engine.advance(by: 1)
        XCTAssertLessThan(first.position.x, previousX)
        XCTAssertNil(first.animationKeys())
        XCTAssertEqual(first.contentsScale, engine.traitCollection.displayScale)
        engine.advance(by: 10)
        XCTAssertTrue(engine.layer.sublayers?.isEmpty ?? true)
    }

    func testPauseFreezesFixedCommentLifetime() throws {
        let engine = DanmakuEngine(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        engine.prepare(items: [DanmakuItem(time: 0, text: "固定弹幕", mode: 5, color: 0xFFFFFF)])
        engine.update(currentTime: 0)
        engine.advance(by: 1)
        engine.setTimelinePaused(true)
        engine.advance(by: 20)
        XCTAssertEqual(engine.layer.sublayers?.count, 1)
        engine.setTimelinePaused(false)
        engine.advance(by: 2)
        XCTAssertEqual(engine.layer.sublayers?.count, 1)
        engine.advance(by: 2)
        XCTAssertTrue(engine.layer.sublayers?.isEmpty ?? true)
    }

    func testServerHostAndLegacyMessageDecode() throws {
        let info = try JSONDecoder().decode(LiveDanmuInfoPayload.self, from: Data(#"{"token":"test","host_list":[{"host":"example.com","wss_port":443}]}"#.utf8))
        XCTAssertEqual(info.hosts.first?.wssPort, 443)
        let model = LiveDanmakuModel()
        let body = Data(#"{"cmd":"DANMU_MSG","info":[[0,1,25,16777215],"正常弹幕",[123,"观众",0]]}"#.utf8)
        model.handleFrame(LivePacketCodec.packet(op: 5, protover: 0, seq: 1, body: body))
        XCTAssertEqual(model.messages.first?.text, "正常弹幕")
        XCTAssertEqual(model.messages.first?.name, "观众")
    }

    func testConcatenatedMessagesAndMalformedHeaderTerminate() {
        let model = LiveDanmakuModel()
        let body = Data(#"{"cmd":"DANMU_MSG","info":[[],"消息",[123,"观众"]]}"#.utf8)
        let packet = LivePacketCodec.packet(op: 5, protover: 0, seq: 1, body: body)
        model.handleFrame(packet + packet)
        XCTAssertEqual(model.messages.count, 2)
        model.handleFrame(Data(repeating: 0, count: 16))
        XCTAssertTrue(LivePacketCodec.splitConcatenated(Data(repeating: 0, count: 16)).isEmpty)
    }

    func testAuthenticationFailureIsNotConnected() {
        let model = LiveDanmakuModel()
        model.handleFrame(LivePacketCodec.packet(op: 8, protover: 1, seq: 1, body: Data(#"{"code":-101}"#.utf8)))
        XCTAssertNotEqual(model.connection, .connected)
    }

    func testDynamicPortalLiveUsersCarryAvatarIdentity() throws {
        let payload = try JSONDecoder().decode(FollowedLiveUsersPayload.self, from: Data(#"{"live_users":{"items":[{"mid":"123","room_id":456,"uname":"主播","face":"https://example.com/avatar","title":"直播中"}]}}"#.utf8))
        let room = try XCTUnwrap(payload.live_users.items.first)
        XCTAssertEqual(room.uid, 123)
        XCTAssertEqual(room.roomID, 456)
        XCTAssertTrue(room.isLive)
    }
}

@MainActor
final class DanmakuDeviceSmokeTests: XCTestCase {
    func testLiveMessagesAndFollowingPortalOnPhysicalDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical device only")
        #endif
        let account = AccountStore(monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        if account.isLoggedIn {
            let portal = try await LiveAPI.followedUsers()
            XCTAssertTrue(portal.rooms.allSatisfy { $0.uid > 0 && $0.roomID > 0 })
            let evidence = XCTAttachment(string: "liveUsersWithIdentity=\(portal.rooms.count)")
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        let recommended = try await LiveAPI.recommended()
        let room = try XCTUnwrap(recommended.rooms.filter(\.isLive).max(by: { $0.online < $1.online }))
        let model = LiveDanmakuModel()
        model.start(roomID: room.roomID)
        defer { model.stop() }
        let deadline = Date().addingTimeInterval(45)
        while model.messages.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertEqual(model.connection, .connected)
        XCTAssertFalse(model.messages.isEmpty, "实际直播间应收到可显示的弹幕")
        let evidence = XCTAttachment(string: "roomID=\(room.roomID)\nconnected=\(model.connection == .connected)\nreceivedMessages=\(model.messages.count)")
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
