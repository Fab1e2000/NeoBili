@testable import NeoBiliDomain
import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class EmotePipelineTests: XCTestCase {
    func testOriginalBitmapRetentionIsBoundedAcrossComments() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        func bitmap() -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
        }
        let cost = 32 * 32 * 4
        let notifications = NotificationCenter()
        let store = CommentEmoteStore(maximumOriginalBytes: cost * 2, notifications: notifications)
        weak var first: UIImage?
        for index in 0..<20 {
            autoreleasepool {
                let image = bitmap()
                if index == 0 { first = image }
                store.insertOriginalForTesting(image, for: URL(string: "https://example.invalid/emote/\(index)")!)
                XCTAssertLessThanOrEqual(store.cachedOriginalByteCount, cost * 2)
            }
        }
        XCTAssertNil(first, "Observation slots must not keep evicted original bitmaps alive")
        XCTAssertGreaterThan(store.cachedOriginalByteCount, 0)
        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(store.cachedOriginalByteCount, 0)
    }

    func testCancellingOneCommentKeepsAnotherEmoteConsumerAlive() async throws {
        let probe = EmoteLoadProbe()
        let store = CommentEmoteStore(loader: { _ in await probe.load() })
        let url = URL(string: "https://example.invalid/shared-emote.png")!
        let emote = CommentEmote(url: url.absoluteString, meta: .init(size: 1))
        let first = Task { await store.preload([emote, emote]) }
        try await until { await store.loadingConsumerCount == 1 }
        let second = Task { await store.preload([emote]) { _ in .init(height: 16, scale: 2) } }
        try await until { await store.loadingConsumerCount == 2 }
        first.cancel()
        await first.value
        try await until { await store.loadingConsumerCount == 1 }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        await probe.release(image)
        await second.value
        let starts = await probe.starts
        XCTAssertEqual(starts, 1)
        XCTAssertNotNil(store.image(for: url, height: 16, scale: 2))
    }

    func testPreloadCachesRequestedSizesAndPreparesNewSizesFromRetainedOriginal() async throws {
        let probe = ImmediateEmoteProbe()
        let store = CommentEmoteStore(loader: { _ in await probe.load() })
        let url = URL(string: "https://example.invalid/emote-variants.png")!
        let small = CommentEmote(url: url.absoluteString, meta: .init(size: 1))
        let large = CommentEmote(url: url.absoluteString, meta: .init(size: 2))
        await store.preload([small, large]) {
            .init(height: $0.heightMultiplier >= 2 ? 32 : 16, scale: 3)
        }
        // An immediate read only succeeds when the asynchronous render already produced the bitmap.
        XCTAssertNotNil(store.image(for: url, height: 16, scale: 3))
        XCTAssertNotNil(store.image(for: url, height: 32, scale: 3))
        XCTAssertNil(store.image(for: url, height: 16, scale: 2))
        await store.preload([small]) { _ in .init(height: 16, scale: 2) }
        XCTAssertNotNil(store.image(for: url, height: 16, scale: 2))
        let starts = await probe.starts
        XCTAssertEqual(starts, 1)
    }

    func testOversizedOriginalIsResizedBeforeBoundedRetention() {
        let store = CommentEmoteStore(maximumOriginalBytes: 8192)
        let url = URL(string: "https://example.invalid/large-emote.png")!
        autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            }
            store.insertOriginalForTesting(image, for: url)
        }
        XCTAssertGreaterThan(store.cachedOriginalByteCount, 0)
        XCTAssertLessThanOrEqual(store.cachedOriginalByteCount, 8192)
        XCTAssertNotNil(store.image(for: url, height: 16, scale: 2))
    }

    func testWideAccessibilityEmoteFitsScaledCacheAndPreservesAspectRatio() async throws {
        let size = CGSize(width: 320, height: 4)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let store = CommentEmoteStore(loader: { _ in source })
        let url = URL(string: "https://example.invalid/wide-emote.png")!
        let emote = CommentEmote(url: url.absoluteString, meta: .init(size: 2))
        let height: CGFloat = 110
        let scale: CGFloat = 3

        await store.preload([emote]) { _ in .init(height: height, scale: scale) }

        let rendered = try XCTUnwrap(store.image(for: url, height: height, scale: scale))
        let bitmap = try XCTUnwrap(rendered.cgImage)
        XCTAssertLessThanOrEqual(bitmap.bytesPerRow * bitmap.height, 32 * 1024 * 1024)
        XCTAssertEqual(rendered.size, CGSize(width: height, height: height))
        var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: bitmap.width, height: bitmap.height,
            bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        let filled = (0..<bitmap.height).filter { pixels[($0 * bitmap.width + bitmap.width / 2) * 4 + 3] > 127 }
        XCTAssertEqual(CGFloat(filled.count), CGFloat(bitmap.width) * size.height / size.width, accuracy: 1)
        XCTAssertTrue(store.image(for: url, height: height, scale: scale) === rendered)
    }

    func testVisibleCommentRecoversAfterMemoryWarningWithoutChangingSizeOrReappearing() async throws {
        let notifications = NotificationCenter()
        let probe = ImmediateEmoteProbe()
        let store = CommentEmoteStore(notifications: notifications, loader: { _ in await probe.load() })
        let url = URL(string: "https://example.invalid/visible-emote.png")!
        let emote = CommentEmote(url: url.absoluteString, meta: .init(size: 2))
        let probeEmote = CommentEmote(url: "https://example.invalid/measurement-emote.png", meta: .init(size: 2))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: VStack {
            CommentEmoteText(message: "[doge]", emotes: ["[doge]": emote], font: .body,
                             textStyle: .body, store: store)
            CommentEmoteText(message: "[probe]", emotes: ["[probe]": probeEmote], font: .body,
                             textStyle: .body, loadsEmotes: false, store: store)
                .hidden()
        }
        .environment(\.dynamicTypeSize, .large)
        .environment(\.displayScale, 2))
        window.rootViewController = host
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }

        let height = (AppFont.baseSize(.body) * emote.heightMultiplier).rounded()
        try await until { store.image(for: url, height: height, scale: 2) != nil }
        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(store.cachedOriginalByteCount, 0)
        XCTAssertNil(store.image(for: url, height: height, scale: 2))
        try await until { store.image(for: url, height: height, scale: 2) != nil }
        XCTAssertTrue(host.view.window === window)
        let starts = await probe.starts
        XCTAssertEqual(starts, 2, "Only the visible emote should load before and after the warning")
    }

    func testVisibleCommentReloadsEvictedOriginalAfterTextSizeChange() async throws {
        let probe = ImmediateEmoteProbe()
        let store = CommentEmoteStore(maximumOriginalBytes: 4096, loader: { _ in await probe.load() })
        let url = URL(string: "https://example.invalid/resize-emote.png")!
        let emotes = ["[doge]": CommentEmote(url: url.absoluteString, meta: .init(size: 1))]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: AnyView(Color.clear))
        window.rootViewController = host
        window.frame = scene.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        func content(_ size: DynamicTypeSize) -> AnyView {
            AnyView(CommentEmoteText(message: "正文[doge]", emotes: emotes, font: .body,
                                    textStyle: .body, store: store).environment(\.dynamicTypeSize, size))
        }
        host.rootView = content(.large)
        try await until { await probe.starts == 1 && store.cachedOriginalByteCount > 0 }
        try await Task.sleep(for: .milliseconds(30))
        autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let other = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            store.insertOriginalForTesting(other, for: URL(string: "https://example.invalid/other.png")!)
        }
        try await Task.sleep(for: .milliseconds(30))
        host.rootView = content(.accessibility3)
        try await until { await probe.starts == 2 }
        try await until { await store.loadingConsumerCount == 0 }
        await store.preload(Array(emotes.values)) { _ in .init(height: 30, scale: 2) }
        XCTAssertNotNil(store.image(for: url, height: 30, scale: 2))
    }

    private func until(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw URLError(.timedOut)
    }
}

private actor EmoteLoadProbe {
    private var continuation: CheckedContinuation<UIImage, Never>?
    private(set) var starts = 0
    func load() async -> UIImage {
        starts += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ image: UIImage) { continuation?.resume(returning: image); continuation = nil }
}

private actor ImmediateEmoteProbe {
    private(set) var starts = 0
    func load() -> UIImage {
        starts += 1
        return autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
                UIColor.blue.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
        }
    }
}
