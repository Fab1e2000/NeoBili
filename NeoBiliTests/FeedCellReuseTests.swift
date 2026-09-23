import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class FeedCellReuseTests: XCTestCase {
    func testReusedImageDisplaysNewURLInsteadOfPreviousCard() async throws {
        let oldURL = URL(string: "https://example.com/feed-reuse-old.png")!
        let newURL = URL(string: "https://example.com/feed-reuse-new.png")!
        let scale = UIScreen.main.scale
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 40, height: 40), scale: scale))
        BiliImageMemoryCache.insert(solid(.red), for: oldURL, pixelSize: pixels)
        BiliImageMemoryCache.insert(solid(.blue), for: newURL, pixelSize: pixels)
        let state = ImageState(url: oldURL)
        let host = UIHostingController(rootView: ImageHarness(state: state))
        let window = show(host)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        let before = colorAtCenter(host.view)
        XCTAssertGreaterThan(before.red, 200)
        XCTAssertLessThan(before.blue, 40)
        state.url = newURL
        try await Task.sleep(for: .milliseconds(100))
        let after = colorAtCenter(host.view)
        XCTAssertGreaterThan(after.blue, 200, "Rebinding a reused cell must display its new cover")
        XCTAssertLessThan(after.red, 40, "The previous card must not remain visible")
    }

    func testNativeCardReuseUpdatesCoverAndAccessibleTitle() async throws {
        let oldURL = URL(string: "https://example.com/native-old.png")!
        let newURL = URL(string: "https://example.com/native-new.png")!
        let size = CGSize(width: 188, height: 141)
        let pixels = try XCTUnwrap(ImagePixelSize(points: size, scale: UIScreen.main.scale))
        BiliImageMemoryCache.insert(solid(.red), for: oldURL, pixelSize: pixels)
        BiliImageMemoryCache.insert(solid(.blue), for: newURL, pixelSize: pixels)
        func video(_ id: Int, cover: URL) -> VideoSummary {
            VideoSummary(bvid: "BV-native-\(id)", aid: id, cid: id, title: "Title \(id)",
                         pic: cover.absoluteString, desc: "", duration: 60, pubdate: 0,
                         owner: VideoOwner(mid: 1, name: "Author", face: ""),
                         stat: VideoStat(view: 1, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        }
        let state = NativeState(video: video(1, cover: oldURL))
        let host = UIHostingController(rootView: NativeHarness(state: state))
        let window = show(host)
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(colorAtCenter(host.view).red, 100)
        XCTAssertLessThan(colorAtCenter(host.view).blue, 40)
        state.video = video(2, cover: newURL)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(colorAtCenter(host.view).blue, 100)
        XCTAssertLessThan(colorAtCenter(host.view).red, 40)
        func card(in view: UIView) -> NativeHomeVideoCard.CardView? {
            if let card = view as? NativeHomeVideoCard.CardView { return card }
            return view.subviews.lazy.compactMap { card(in: $0) }.first
        }
        let rendered = try XCTUnwrap(card(in: host.view))
        XCTAssertTrue(rendered.accessibilityLabel?.contains("Title 2") == true)
        XCTAssertFalse(rendered.accessibilityLabel?.contains("Title 1") == true)
    }

    func testReusedCardCannotClaimPreviousVideosNativeTransitionSource() {
        var presentation = MediaPresentationState()
        presentation.prepareSource("old-video")
        presentation.destination = .player
        XCTAssertEqual(presentation.source(for: "old-video"), .player)
        // The same cell now renders a different identity; no retained UIView
        // registry can point the old video at that new card.
        XCTAssertEqual(presentation.source(for: "new-video"), .content("new-video"))
        presentation.prepareSource("new-video")
        XCTAssertEqual(presentation.source(for: "new-video"), .player)
        XCTAssertEqual(presentation.source(for: "old-video"), .content("old-video"))
    }

    func testNativeCardTypographyAndDurationMeasurementFollowReuseChanges() throws {
        let card = NativeHomeVideoCard.CardView()
        card.frame = CGRect(x: 0, y: 0, width: 188, height: 222)
        func configure(seconds: Int, size: DynamicTypeSize, width: CGFloat = 188) throws {
            let video = VideoSummary(bvid: "BV-typography", aid: 1, cid: 1, title: "Title",
                                     pic: "", desc: "", duration: seconds, pubdate: 0,
                                     owner: VideoOwner(mid: 1, name: "Author", face: ""),
                                     stat: VideoStat(view: 1, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
            card.frame.size.width = width
            card.configure(video: video, titleWidth: width - 16, dynamicTypeSize: size, scale: 3)
            card.setNeedsLayout()
            card.layoutIfNeeded()
            let labels = card.subviews.compactMap { $0 as? UILabel }
            let owner = try XCTUnwrap(labels.first { $0.text == "Author" })
            let duration = try XCTUnwrap(labels.first { $0.text == video.formattedDuration })
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            XCTAssertEqual(owner.font.pointSize, UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits).pointSize)
            let measured = duration.sizeThatFits(CGSize(width: width, height: duration.font.lineHeight)).width
            XCTAssertEqual(duration.frame.width, measured, accuracy: 0.01)
            XCTAssertEqual(duration.frame.maxX, width - 8, accuracy: 0.01)
        }
        try configure(seconds: 60, size: .large)
        try configure(seconds: 3661, size: .large)
        try configure(seconds: 3661, size: .xxxLarge)
        try configure(seconds: 3661, size: .xxxLarge, width: 220)
        try configure(seconds: 60, size: .large)
    }

    func testPersistentHostReusesContentAndDetachesFromParent() async throws {
        let parent = UIViewController()
        let window = show(parent)
        defer { window.isHidden = true }
        var cell: PersistentFeedHostingCell? = PersistentFeedHostingCell(frame: CGRect(x: 0, y: 0, width: 300, height: 240))
        cell!.setContent(AnyView(HostedReuseProbe(value: "old")))
        parent.view.addSubview(cell!)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(parent.children.count, 1)
        weak var controller = parent.children.first
        let initialHost = try XCTUnwrap(controller).view
        func probe(in view: UIView) -> UIView? {
            if view.accessibilityIdentifier == "hosted-reuse-probe" { return view }
            return view.subviews.lazy.compactMap { probe(in: $0) }.first
        }
        let first = try XCTUnwrap(probe(in: initialHost!))
        XCTAssertEqual(first.accessibilityValue, "old")
        cell!.prepareForReuse()
        cell!.setContent(AnyView(HostedReuseProbe(value: "new")))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(parent.children.first === controller)
        XCTAssertTrue(probe(in: initialHost!) === first, "Reuse should preserve the represented view, not rebuild it")
        XCTAssertEqual(first.accessibilityValue, "new", "The reused host must display the new card's content")
        cell!.removeFromSuperview()
        XCTAssertTrue(parent.children.isEmpty, "Offscreen hosts must not remain retained by the page controller")
        parent.view.addSubview(cell!)
        XCTAssertTrue(parent.children.first === controller, "A reused cell must reattach its existing host")
        cell!.removeFromSuperview()
        cell = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(controller, "Releasing the cell must release its hosting controller")
    }

    func testAdjacentCardsHaveIndependentNativeHostingTransforms() async throws {
        let parent = UIViewController()
        let window = show(parent)
        defer { window.isHidden = true }
        let left = PersistentFeedHostingCell(frame: CGRect(x: 8, y: 60, width: 180, height: 216))
        let right = PersistentFeedHostingCell(frame: CGRect(x: 196, y: 60, width: 180, height: 216))
        left.setContent(AnyView(Color.red))
        right.setContent(AnyView(Color.blue))
        parent.view.addSubview(left)
        parent.view.addSubview(right)
        defer { left.removeFromSuperview(); right.removeFromSuperview() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(parent.children.count, 2)
        let leftHost = try XCTUnwrap(parent.children.first?.view)
        let rightHost = try XCTUnwrap(parent.children.last?.view)
        XCTAssertTrue(leftHost.isDescendant(of: left.contentView))
        XCTAssertFalse(rightHost.isDescendant(of: left.contentView))
        XCTAssertTrue(rightHost.isDescendant(of: right.contentView))
        let originalRight = rightHost.convert(rightHost.bounds, to: window)
        // UIKit can transform either the source host or its collection cell.
        // Neither boundary may contain the neighbouring card anymore.
        leftHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        left.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        XCTAssertEqual(rightHost.transform, .identity)
        XCTAssertEqual(right.transform, .identity)
        XCTAssertEqual(rightHost.convert(rightHost.bounds, to: window), originalRight)
    }

    private func show(_ host: UIViewController) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }

    private func solid(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    private func colorAtCenter(_ view: UIView) -> (red: Int, blue: Int) {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return (0, 0) }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: -CGFloat(cgImage.width / 2), y: -CGFloat(cgImage.height / 2))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return (Int(pixel[0]), Int(pixel[2]))
    }
}

@MainActor @Observable private final class ImageState {
    var url: URL
    init(url: URL) { self.url = url }
}
private struct ImageHarness: View {
    let state: ImageState
    var body: some View {
        BiliImage(url: state.url, targetSize: CGSize(width: 40, height: 40))
            .frame(width: 40, height: 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}
@MainActor @Observable private final class NativeState {
    var video: VideoSummary
    init(video: VideoSummary) { self.video = video }
}
private struct NativeHarness: View {
    let state: NativeState
    var body: some View {
        NativeHomeVideoCard(video: state.video, titleWidth: 172)
            .frame(width: 188, height: 222)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

private struct HostedReuseProbe: UIViewRepresentable {
    let value: String
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = "hosted-reuse-probe"
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityValue = value
    }
}
