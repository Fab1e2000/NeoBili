import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Real-window evidence for the production collapse overlay. The backdrop and
/// underlying UIButton are local fixtures, not a video stream or MPV session.
@MainActor
final class InlineVideoCollapseVisualTests: XCTestCase {
    func testContinuousHeaderTintAndTouchPassthroughOnRealDevice() async throws {
        let host = try CollapseVisualWindow()
        defer { host.close() }
        let cases: [(String, InlineVideoPlaybackPhase, CGFloat)] = [
            ("paused-000", .paused, 0), ("paused-025", .paused, 0.25),
            ("paused-050", .paused, 0.5), ("paused-075", .paused, 0.75),
            ("paused-100", .paused, 1), ("playing-clamped", .playing, 1),
            ("loading-clamped", .loading, 1)
        ]
        var previousPausedTint = -1

        for (name, phase, fraction) in cases {
            let recorder = CollapseVisualRecorder()
            try await host.show(CollapseVisualFixture(phase: phase, fraction: fraction, recorder: recorder).id(name))
            let metrics = try XCTUnwrap(recorder.metrics, name)
            let video = try XCTUnwrap(recorder.frames["video"], name)
            let gap = try XCTUnwrap(recorder.frames["gap"], name)
            let comments = try XCTUnwrap(recorder.frames["comments"], name)
            let underlyingButton = try XCTUnwrap(recorder.underlyingButton, name)

            XCTAssertLessThan(host.window.bounds.width, host.window.bounds.height, name)
            XCTAssertGreaterThan(metrics.topInset, 0, "Exercise the physical iPhone top safe area: \(name)")
            XCTAssertEqual(video.minY, host.window.safeAreaInsets.top - metrics.topOverlap, accuracy: 0.5, name)
            XCTAssertEqual(video.height, metrics.height, accuracy: 0.5, name)
            XCTAssertEqual(gap.minY, video.maxY, accuracy: 0.5, name)
            XCTAssertEqual(gap.height, 10, accuracy: 0.5, name)
            XCTAssertEqual(comments.minY, gap.maxY, accuracy: 0.5, name)
            XCTAssertEqual(metrics.progress, phase == .paused ? Double(fraction) : 0, accuracy: 0.0001, name)

            let buttonCenter = underlyingButton.convert(
                CGPoint(x: underlyingButton.bounds.midX, y: underlyingButton.bounds.midY), to: host.window
            )
            let hit = host.window.hitTest(buttonCenter, with: nil)
            let reachesUnderlyingButton = hit === underlyingButton || hit?.isDescendant(of: underlyingButton) == true
            XCTAssertEqual(reachesUnderlyingButton, !metrics.isCollapsed,
                           "Only the completed compact strip takes over input; tint/probes must pass it through: \(name)")

            let screenshot = UIGraphicsImageRenderer(bounds: host.window.bounds).image { _ in
                host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "inline-collapse-local-fixture-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            // x=20 is deliberately black in the safe area, video reference
            // rail and gap. Equal composited pixels prove one uninterrupted
            // tint layer, independently of the local colorful central image.
            let samples = try [CGPoint(x: 20, y: metrics.topInset / 2),
                               CGPoint(x: 20, y: video.midY),
                               CGPoint(x: 20, y: gap.midY)].map { try rgbPixel(in: screenshot, at: $0) }
            for sample in samples.dropFirst() {
                for channel in 0..<3 {
                    XCTAssertEqual(Double(sample[channel]), Double(samples[0][channel]), accuracy: 2,
                                   "Safe area, video and gap must share the same tint: \(name)")
                }
            }
            for x in [CGFloat(1), host.window.bounds.width - 1] {
                let corner = try rgbPixel(in: screenshot, at: CGPoint(x: x, y: comments.minY + 1))
                for channel in 0..<3 {
                    XCTAssertEqual(Double(corner[channel]), Double(samples[0][channel]), accuracy: 2,
                                   "Both exposed content corners must match the strip: \(name)")
                }
            }
            let tint = samples[0].reduce(0, +)
            if phase == .paused {
                XCTAssertGreaterThan(tint, previousPausedTint, "Tint must advance continuously with distance: \(name)")
                previousPausedTint = tint
            } else {
                XCTAssertLessThanOrEqual(tint, 6, "Playing/loading must keep the standard-size image untinted: \(name)")
            }

            let evidence = XCTAttachment(string: "LOCAL STATIC FIXTURE, NO VIDEO/NETWORK\nwindow=\(host.window.bounds)\nsafeArea=\(host.window.safeAreaInsets)\nvideo=\(video)\ngap=\(gap)\ncomments=\(comments)\nprogress=\(metrics.progress)\nisCollapsed=\(metrics.isCollapsed)\nRGB.safeArea/video/gap=\(samples)\nunderlyingControlReceivesHit=\(reachesUnderlyingButton)")
            evidence.name = "inline-collapse-local-fixture-\(name)-geometry-and-pixels"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
    }

    private func rgbPixel(in image: UIImage, at point: CGPoint) throws -> [Int] {
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: floor(point.x * image.scale),
                                                          y: floor(point.y * image.scale), width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                                                bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba.prefix(3).map(Int.init)
    }
}

private struct CollapseVisualFixture: View {
    let phase: InlineVideoPlaybackPhase
    let fraction: CGFloat
    let recorder: CollapseVisualRecorder

    var body: some View {
        GeometryReader { geometry in
            let topOverlap = min(9, max(0, geometry.safeAreaInsets.top - 47))
            let fullSize = CGSize(width: geometry.size.width,
                                  height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
            let layout = InlineVideoCollapseLayout(
                expandedHeight: InlineVideoLayout.height(for: fullSize, aspectRatio: 9.0 / 16),
                standardHeight: InlineVideoLayout.height(for: fullSize), allowsCompact: true
            )
            let requestedDistance = layout.compactTravel + (layout.compactHeight - layout.minimumHeight) * fraction
            let distance = layout.constrainedDistance(requestedDistance, for: phase)
            let height = layout.containerHeight(for: distance)
            let progress = layout.visualProgress(for: distance, phase: phase)
            let isCollapsed = layout.hidesVideo(for: distance)
            let metrics = CollapseVisualMetrics(height: height, topInset: geometry.safeAreaInsets.top,
                                                topOverlap: topOverlap, progress: progress, isCollapsed: isCollapsed)

            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    LinearGradient(colors: [.indigo, .cyan, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .padding(.horizontal, 40)
                    Text("本地静态画面\n收缩布局测试 · 不播放视频")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    CollapseUnderlyingControl(recorder: recorder).frame(width: 48, height: 48)
                }
                .frame(width: geometry.size.width, height: height)
                .clipped()
                .allowsHitTesting(!isCollapsed)
                .background(CollapseVisualProbe(name: "video", recorder: recorder, metrics: metrics))

                Color.clear.frame(height: 10)
                    .background(CollapseVisualProbe(name: "gap", recorder: recorder))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 24) {
                            Text("简介").foregroundStyle(.secondary)
                            Text("评论 128").fontWeight(.semibold)
                        }
                        Text(caption).font(.headline)
                        Text("上方画面为测试绘制。左右黑栏用于验证状态栏、视频与 10pt 间隔是否连续染色。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(0..<6) { index in
                            HStack(spacing: 12) {
                                Circle().fill(.gray.opacity(0.18)).frame(width: 34, height: 34)
                                Text("本地评论示例 \(index + 1)").font(.subheadline)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                .background(alignment: .top) {
                    Color.accentColor.opacity(progress).frame(height: 12).allowsHitTesting(false)
                }
                .background(CollapseVisualProbe(name: "comments", recorder: recorder))
            }
            .frame(width: geometry.size.width,
                   height: geometry.size.height + topOverlap + geometry.safeAreaInsets.bottom, alignment: .top)
            .overlay(alignment: .top) {
                InlineVideoCollapseOverlay(progress: progress, videoHeight: height,
                                           topInset: geometry.safeAreaInsets.top, isCollapsed: isCollapsed,
                                           player: nil, onBack: {}) {}
            }
            .offset(y: -topOverlap)
        }
        .background(Color.black.ignoresSafeArea(edges: .top))
        .preferredColorScheme(.light)
        .dynamicTypeSize(.large)
        .transaction { $0.disablesAnimations = true; $0.animation = nil }
    }

    private var caption: String {
        switch phase {
        case .paused: "暂停末段收缩 \(Int(fraction * 100))%"
        case .playing: "正在播放 · 收缩停在 16:9"
        case .loading: "正在加载 · 收缩停在 16:9"
        }
    }
}

private struct CollapseVisualMetrics {
    let height: CGFloat
    let topInset: CGFloat
    let topOverlap: CGFloat
    let progress: Double
    let isCollapsed: Bool
}

@MainActor
private final class CollapseVisualRecorder {
    var metrics: CollapseVisualMetrics?
    var frames: [String: CGRect] = [:]
    weak var underlyingButton: UIButton?
}

private struct CollapseUnderlyingControl: UIViewRepresentable {
    let recorder: CollapseVisualRecorder
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = "本地下层触摸透传测试控件"
        recorder.underlyingButton = button
        return button
    }
    func updateUIView(_ uiView: UIButton, context: Context) { recorder.underlyingButton = uiView }
}

private struct CollapseVisualProbe: UIViewRepresentable {
    let name: String
    let recorder: CollapseVisualRecorder
    var metrics: CollapseVisualMetrics?
    func makeUIView(context: Context) -> CollapseVisualProbeView {
        let view = CollapseVisualProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ uiView: CollapseVisualProbeView, context: Context) {
        uiView.record = { recorder.frames[name] = $0 }
        if let metrics { recorder.metrics = metrics }
        uiView.recordFrame()
    }
}

private final class CollapseVisualProbeView: UIView {
    var record: ((CGRect) -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); recordFrame() }
    override func layoutSubviews() { super.layoutSubviews(); recordFrame() }
    func recordFrame() {
        guard let window else { return }
        record?(convert(bounds, to: window))
    }
}

@MainActor
private final class CollapseVisualWindow {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    private let previousWindow: UIWindow?
    private let previousOrientation: UIInterfaceOrientationMask

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousWindow = scene.keyWindow
        previousOrientation = OrientationLock.shared.supportedOrientations
        controller = UIHostingController(rootView: AnyView(Color.black))
        window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func show<Content: View>(_ content: Content) async throws {
        controller.rootView = AnyView(content)
        OrientationController.enterPortrait()
        let scene = try XCTUnwrap(window.windowScene)
        var portrait = false
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if window.bounds.height > window.bounds.width, scene.interfaceOrientation.isPortrait {
                portrait = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard portrait else { throw URLError(.timedOut) }
        if let transition = controller.transitionCoordinator, transition.isAnimated {
            await withCheckedContinuation { continuation in
                if !transition.animate(alongsideTransition: nil, completion: { _ in continuation.resume() }) {
                    continuation.resume()
                }
            }
        }
        window.frame = scene.coordinateSpace.bounds
        controller.view.frame = window.bounds
        window.setNeedsLayout()
        controller.view.setNeedsLayout()
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
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
