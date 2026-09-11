import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Real-device snapshots of the two introduction components. Avatars have no
/// URL, and all actions are local closures: there is no playback or networking.
@MainActor
final class VideoIntroductionStyleTests: XCTestCase {
    func testOwnerAndIntroductionInBothAppearancesAndExpandedStates() async throws {
        let host = try IntroductionSnapshotHost()
        defer { host.close() }
        try await host.preparePortrait()
        var collapsedHeight: CGFloat = 0
        for (name, appearance, expanded, following, typeSize) in [
            ("light-collapsed", ColorScheme.light, false, false, DynamicTypeSize.large),
            ("light-expanded", .light, true, true, .large),
            ("dark-collapsed", .dark, false, true, .large),
            ("dark-expanded", .dark, true, false, .large),
            ("large-text-expanded", .light, true, false, .xxxLarge)
        ] {
            let size = host.window.bounds.size
            let insets = host.window.safeAreaInsets
            do {
                try await host.show(IntroductionFixture(size: size, insets: insets, expanded: expanded,
                                                        following: following, recorder: host.recorder)
                    .preferredColorScheme(appearance)
                    .environment(\.dynamicTypeSize, typeSize))
            } catch {
                let geometry = XCTAttachment(string: "window=\(host.window.bounds)\nsafe=\(insets)\nframes=\(host.recorder.frames)")
                geometry.name = "video-introduction-\(name)-incomplete-geometry"
                geometry.lifetime = .keepAlways
                add(geometry)
                let screenshot = UIGraphicsImageRenderer(bounds: host.window.bounds).image { _ in
                    host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: screenshot)
                attachment.name = "video-introduction-\(name)-incomplete-layout"
                attachment.lifetime = .keepAlways
                add(attachment)
                throw error
            }
            let canvas = try XCTUnwrap(host.recorder.frames["canvas"])
            let owner = try XCTUnwrap(host.recorder.frames["owner"])
            let card = try XCTUnwrap(host.recorder.frames["introduction"])
            let followingContent = try XCTUnwrap(host.recorder.frames["following-content"])
            XCTAssertEqual(canvas.minX, 0, accuracy: 0.5, name)
            XCTAssertEqual(canvas.minY, 0, accuracy: 0.5, name)
            XCTAssertEqual(canvas.size.width, size.width, accuracy: 0.5, name)
            XCTAssertEqual(canvas.size.height, size.height, accuracy: 0.5, name)
            for frame in [owner, card, followingContent] {
                XCTAssertEqual(frame.minX, 16, accuracy: 0.5, name)
                XCTAssertEqual(frame.width, size.width - 32, accuracy: 0.5, name)
            }
            XCTAssertGreaterThanOrEqual(owner.height, 64, name)
            XCTAssertGreaterThanOrEqual(card.minY - owner.maxY, 13.5, name)
            XCTAssertGreaterThanOrEqual(followingContent.minY - card.maxY, 13.5, name)
            if !expanded { collapsedHeight = card.height }
            else { XCTAssertGreaterThan(card.height, collapsedHeight + 80, "Expanded text must grow its card: \(name)") }

            let geometry = XCTAttachment(string: "window=\(host.window.bounds)\nsafe=\(insets)\nframes=\(host.recorder.frames)")
            geometry.name = "video-introduction-\(name)-geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
            let screenshot = UIGraphicsImageRenderer(bounds: host.window.bounds).image { _ in
                host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "video-introduction-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

private struct IntroductionFixture: View {
    let size: CGSize
    let insets: UIEdgeInsets
    let expanded: Bool
    let following: Bool
    let recorder: IntroductionFrameRecorder

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassEffectContainer(spacing: 8) {
                    VStack(alignment: .leading, spacing: 14) {
                        VideoOwnerRow(owner: VideoOwner(mid: 17, name: "每天记录风景的旅行摄影师", face: ""),
                                      avatarURL: nil, card: MemberCard(follower: 128_000, archiveCount: 235),
                                      isFollowing: following, onToggleFollow: {}, onOpenSpace: {})
                            .background(IntroductionFrameProbe(name: "owner", recorder: recorder))
                        VideoIntroductionCard(
                            title: "把镜头留给生活：一起走过山川、海岸与城市，记录那些值得被记住的普通时刻",
                            stat: VideoStat(view: 1_280_000, danmaku: 3821, like: 12_300, favorite: 2300,
                                            coin: 8700, share: 128, reply: 420),
                            pubdate: 1_788_883_200,
                            desc: "这期从清晨的海边出发，穿过小镇与山间步道，把一路遇到的光线和声音收进镜头。\n\n拍摄与剪辑：旅行摄影师\n感谢每一位停下来分享故事的人。希望你也能在忙碌的日常里，找到一段属于自己的风景。",
                            isExpanded: .constant(expanded)
                        )
                        .background(IntroductionFrameProbe(name: "introduction", recorder: recorder))
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        ForEach(["生活", "摄影", "旅行"], id: \.self) { Text($0).font(.subheadline) }
                    }
                    HStack {
                        ForEach(["hand.thumbsup", "b.circle", "star", "square.and.arrow.up"], id: \.self) { symbol in
                            Image(systemName: symbol).frame(maxWidth: .infinity).frame(height: 44)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IntroductionFrameProbe(name: "following-content", recorder: recorder))
            }
            .padding(.horizontal, 16)
            .padding(.top, insets.top + 20)
            .padding(.bottom, insets.bottom + 20)
        }
        .frame(width: size.width, height: size.height)
        .background(IntroductionFrameProbe(name: "canvas", recorder: recorder))
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea()
    }
}

@MainActor
private final class IntroductionSnapshotHost {
    let window: UIWindow
    let controller = UIHostingController(rootView: AnyView(Color.clear))
    let recorder = IntroductionFrameRecorder()
    private let previousWindow: UIWindow?
    private let previousOrientation: UIInterfaceOrientationMask

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousWindow = scene.keyWindow
        previousOrientation = OrientationLock.shared.supportedOrientations
        window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        controller.safeAreaRegions = []
        window.rootViewController = controller
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.makeKeyAndVisible()
    }

    func preparePortrait() async throws {
        OrientationController.enterPortrait()
        guard let scene = window.windowScene else { throw URLError(.cannotFindHost) }
        for _ in 0..<100 {
            if scene.interfaceOrientation.isPortrait, window.bounds.width < window.bounds.height { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard scene.interfaceOrientation.isPortrait else { throw URLError(.timedOut) }
        if let transition = controller.transitionCoordinator, transition.isAnimated {
            await withCheckedContinuation { continuation in
                if !transition.animate(alongsideTransition: nil, completion: { _ in continuation.resume() }) {
                    continuation.resume()
                }
            }
        }
        window.frame = scene.coordinateSpace.bounds
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
    }

    func show<Content: View>(_ content: Content) async throws {
        recorder.frames.removeAll()
        controller.rootView = AnyView(content)
        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let names = ["canvas", "owner", "introduction", "following-content"]
        var previousFrames: [CGRect] = []
        var stableSamples = 0
        for _ in 0..<100 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            // An unchanged background probe can survive rootView replacement
            // without updateUIView/layoutSubviews. Measure those existing UIKit
            // views again instead of relying on a new layout callback.
            recorder.refreshMeasurements.values.forEach { $0() }
            let frames = names.compactMap { recorder.frames[$0] }
            let complete = frames.count == names.count && frames.allSatisfy {
                $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite
                    && $0.width > 0 && $0.height > 0
            }
            if complete, frames == previousFrames {
                stableSamples += 1
                if stableSamples >= 3 { return }
            } else {
                stableSamples = 0
            }
            previousFrames = frames
            try await Task.sleep(for: .milliseconds(20))
        }
        throw URLError(.timedOut)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKey()
        OrientationLock.shared.supportedOrientations = previousOrientation
        previousWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: previousOrientation)) { _ in }
    }
}

@MainActor
private final class IntroductionFrameRecorder {
    var frames: [String: CGRect] = [:]
    var refreshMeasurements: [String: () -> Void] = [:]
}

private struct IntroductionFrameProbe: UIViewRepresentable {
    let name: String
    let recorder: IntroductionFrameRecorder

    func makeUIView(context: Context) -> IntroductionProbeView {
        let view = IntroductionProbeView()
        view.isUserInteractionEnabled = false
        view.capture = { [weak recorder, name] in recorder?.frames[name] = $0 }
        recorder.refreshMeasurements[name] = { [weak view] in view?.record() }
        return view
    }

    func updateUIView(_ view: IntroductionProbeView, context: Context) {
        view.capture = { [weak recorder, name] in recorder?.frames[name] = $0 }
        recorder.refreshMeasurements[name] = { [weak view] in view?.record() }
        view.setNeedsLayout()
        DispatchQueue.main.async { [weak view] in view?.record() }
    }
}

private final class IntroductionProbeView: UIView {
    var capture: ((CGRect) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); record() }
    override func layoutSubviews() { super.layoutSubviews(); record() }
    func record() {
        guard let window, bounds.width > 0, bounds.height > 0 else { return }
        capture?(convert(bounds, to: window))
    }
}
