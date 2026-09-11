import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class InteractionControlsVisualTests: XCTestCase {
    func testCompleteTitleGlassCommentActionsAndMovementPreviewOnRealDevice() async throws {
        var activeScene: UIWindowScene?
        for _ in 0..<100 {
            activeScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if activeScene != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(activeScene, "Wait for the test host to enter the foreground before measuring UI")
        let previousWindow = scene.keyWindow
        let orientation = OrientationLock.shared.supportedOrientations
        OrientationController.enterPortrait()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
            OrientationLock.shared.supportedOrientations = orientation
            previousWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
        }
        for _ in 0..<50 {
            if scene.interfaceOrientation.isPortrait { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let comments = try JSONDecoder().decode([Comment].self, from: Data(#"""
        [{"rpid":1,"ctime":1789012800,"like":1,"rcount":0,"action":0,"member":{"uname":"本地评论示例","avatar":""},"content":{"message":"点赞和回复使用同一套原生玻璃控件。"}},
         {"rpid":2,"ctime":1789012800,"like":12800,"rcount":0,"action":1,"member":{"uname":"已点赞的评论","avatar":""},"content":{"message":"点赞状态保留粉色高亮，回复仍打开原来的编辑入口。"}}]
        """#.utf8))
        let model = CommentsViewModel(aid: 1)
        let account = AccountStore(monitorNetwork: false)
        for dark in [false, true] {
            host.rootView = AnyView(ScrollView {
                VStack(spacing: 22) {
                    Text("标题和评论 · 本地静态样例").font(.headline)
                    VideoIntroductionCard(
                        title: "轻小说的标题为什么越来越长？",
                        stat: VideoStat(view: 49000, danmaku: 147, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                        pubdate: 1660198020, desc: "简介正文保持收起。", isExpanded: .constant(false))
                    VideoIntroductionCard(
                        title: "这是一段需要完整展示的长标题：一起穿过高山、河流、城市和海岸，记录旅途中每一个值得被记住的瞬间，不论标题有多少行都完整显示到这里。",
                        stat: VideoStat(view: 12800, danmaku: 128, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                        pubdate: 1789012800, desc: "简介正文保持收起，完整标题不受影响。", isExpanded: .constant(false))
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(["赞", "9", "999", "1.2万"], id: \.self) { count in
                                Button {} label: {
                                    CommentGlassActionLabel(title: count, symbol: "hand.thumbsup")
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    ForEach(comments) { comment in
                        CommentRow(comment: comment, viewModel: model, showsReplies: false)
                    }
                }.padding(16).padding(.top, window.safeAreaInsets.top + 16)
            }
            .background(Color(uiColor: .systemBackground))
            .environment(account)
            .environment(\.replyToComment, EnvironmentAction<Comment> { _ in })
            .preferredColorScheme(dark ? .dark : .light))
            try await snapshot(window, host: host, name: dark ? "title-comment-dark" : "title-comment-light")
        }
        host.rootView = AnyView(ZStack {
            Color(uiColor: .systemBackground)
            VStack {
                Text("小窗移动范围 · 本地预览").font(.headline)
                Text("上边界 20% · 下边界 80%").foregroundStyle(.secondary)
                Spacer()
            }.padding(.top, window.safeAreaInsets.top + 16)
            MiniPlayerBoundsPreview(top: 0.2, bottom: 0.8)
            MiniPlayerContainer(content: Text("本地小窗\n不播放视频").foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).clipShape(.rect(cornerRadius: 18)),
                                aspectRatio: 9.0 / 16, anchor: CGPoint(x: 1, y: 1), reduceMotion: true,
                                topLimit: 0.2, bottomLimit: 0.8, onAnchorChange: { _ in })
        }.preferredColorScheme(.light))
        try await snapshot(window, host: host, name: "mini-movement-preview")
    }

    private func snapshot(_ window: UIWindow, host: UIHostingController<AnyView>, name: String) async throws {
        window.frame = window.windowScene!.coordinateSpace.bounds
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let shot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(window.bounds.height, window.bounds.width)
    }
}
