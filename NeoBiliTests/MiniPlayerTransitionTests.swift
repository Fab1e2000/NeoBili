import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Uses the system fullScreenCover/zoom on the connected iPhone. The colored
/// fixture isolates transition geometry without fetching or playing a video.
@MainActor
final class MiniPlayerTransitionTests: XCTestCase {
    func testNativeDismissalShrinksTowardTheActualMiniWindow() async throws {
        var scene: UIWindowScene?
        for _ in 0..<100 {
            scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            if scene != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let activeScene = try XCTUnwrap(scene)
        let previous = activeScene.keyWindow
        let fixture = MiniTransitionFixture()
        let host = UIHostingController(rootView: MiniTransitionHost(fixture: fixture))
        let window = UIWindow(windowScene: activeScene)
        window.frame = activeScene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(100))
        fixture.isPresented = true
        for _ in 0..<100 {
            if fixture.didAppear { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(fixture.didAppear, "The native presentation must finish before its return destination changes")
        try await Task.sleep(for: .milliseconds(100))
        let mini = try XCTUnwrap(fixture.miniView)
        let target = mini.convert(mini.bounds, to: window)
        XCTAssertGreaterThan(target.width, 100)
        XCTAssertGreaterThan(target.minY, window.bounds.midY, "The test's mini window must be far from the top card")
        let expandedImage = render(window, scale: 0.25)
        let expanded = try XCTUnwrap(greenBounds(in: expandedImage))
        XCTAssertGreaterThan(expanded.height, window.bounds.height * 0.9)

        fixture.isPresented = false
        var samples: [CGRect] = []
        var lastImage: UIImage?
        for _ in 0..<28 {
            try await Task.sleep(for: .milliseconds(20))
            let image = render(window, scale: 0.25)
            if let bounds = greenBounds(in: image) {
                if bounds.height < expanded.height * 0.6 {
                    samples.append(bounds)
                    lastImage = image
                }
            }
            if fixture.didDismiss { break }
        }
        let final = try XCTUnwrap(samples.last, "Capture an intermediate native zoom frame, not only the destination ID")
        let geometry = XCTAttachment(string: "target=\(target), expanded=\(expanded), final=\(final), window=\(window.bounds)")
        geometry.lifetime = .keepAlways
        add(geometry)
        // Native zoom cross-fades before the page reaches its final bounds.
        // Check its trajectory at the captured scale, not an already-faded endpoint.
        let progress = (expanded.height - final.height) / (expanded.height - target.height)
        XCTAssertGreaterThan(progress, 0.25)
        let projectedX = expanded.midX + (final.midX - expanded.midX) / progress
        let projectedY = expanded.midY + (final.midY - expanded.midY) / progress
        XCTAssertLessThan(abs(projectedX - target.midX), 45)
        XCTAssertLessThan(abs(projectedY - target.midY), 60,
                          "The sampled zoom trajectory must lead to the actual mini bar, not the original top card")
        if let lastImage {
            let attachment = XCTAttachment(image: lastImage)
            attachment.name = "native-video-dismissal-approaches-mini-window"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(fixture.didDismiss)
    }

    private func render(_ window: UIWindow, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: window.bounds.width * scale,
                                                    height: window.bounds.height * scale), format: format).image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    private func greenBounds(in image: UIImage) -> CGRect? {
        guard let image = image.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> CGRect? in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    if bytes[index + 1] > 160 && bytes[index] < 100 && bytes[index + 2] < 100 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX * 4, y: minY * 4, width: (maxX - minX + 1) * 4,
                          height: (maxY - minY + 1) * 4)
        }
    }
}

@MainActor @Observable
private final class MiniTransitionFixture {
    var isPresented = false
    var sourceID = "card"
    var didAppear = false
    var didDismiss = false
    @ObservationIgnored weak var miniView: UIView?
}

private struct MiniTransitionHost: View {
    @Bindable var fixture: MiniTransitionFixture
    @Namespace private var transition

    var body: some View {
        Color.white
            .overlay(alignment: .topLeading) {
                Color.red.frame(width: 180, height: 100)
                    .videoTransitionSource("card", in: transition)
                    .padding(20)
            }
            .overlay {
                MiniPlayerContainer(
                    content: Color.blue
                        .overlay { MiniTransitionViewProbe { fixture.miniView = $0 } }
                        .videoTransitionSource(NowPlayingStore.miniPlayerTransitionSourceID, in: transition),
                    aspectRatio: 16.0 / 9, anchor: CGPoint(x: 0, y: 0.8), reduceMotion: false,
                    onAnchorChange: { _ in }
                )
            }
            .mediaZoomCover(isPresented: $fixture.isPresented, entrySourceID: "card", namespace: transition, onDismiss: { fixture.didDismiss = true }) {
                Color(red: 0, green: 1, blue: 0).ignoresSafeArea()
                    .background {
                        VideoPagePresentationObserver {
                            fixture.didAppear = true
                        }
                    }
            }
    }
}

private struct MiniTransitionViewProbe: UIViewRepresentable {
    let capture: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        capture(view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { capture(view) }
}
