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
        let store = CommentEmoteStore(maximumOriginalBytes: cost * 2)
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
    }

    func testCancellingOneCommentKeepsAnotherEmoteConsumerAlive() async throws {
        let probe = EmoteLoadProbe()
        let store = CommentEmoteStore(loader: { _ in await probe.load() })
        let url = URL(string: "https://example.invalid/shared-emote.png")!
        let emote = CommentEmote(url: url.absoluteString, meta: .init(size: 1))
        let first = Task { await store.preload([emote, emote]) }
        try await until { await store.loadingConsumerCount == 1 }
        let second = Task { await store.preload([emote]) }
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
