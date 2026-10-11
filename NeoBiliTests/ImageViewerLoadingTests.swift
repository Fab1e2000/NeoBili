import XCTest
import ImageIO
import SwiftUI
@testable import NeoBili

@MainActor
final class ImageViewerLoadingTests: XCTestCase {
    private let first = URL(string: "https://example.com/first.jpg")!
    private let selected = URL(string: "https://example.com/selected.jpg")!

    func testSelectedImageAppearsBeforeSlowNeighbourCompletes() async throws {
        let probe = ImageDownloadProbe()
        let model = ImageViewerModel(images: [.init(url: first), .init(url: selected)]) {
            try await probe.fetch($0)
        }
        let prepare = Task { await model.prepare(startIndex: 1) }
        try await waitUntil { await probe.contains(self.selected) }
        try await waitUntil { await probe.contains(self.first) }
        let neighbourStarted = await probe.contains(first)
        XCTAssertTrue(neighbourStarted, "相邻页与当前页独立下载")
        await probe.succeed(selected)
        try await waitUntil { model.files[1] != nil }
        XCTAssertEqual(model.files[1], selected)
        XCTAssertNil(model.files[0], "慢图不能阻塞所选图片的展示")
        await probe.succeed(first)
        await prepare.value
        XCTAssertEqual(model.files[0], first)
    }

    func testFailedAndMissingImagesKeepTheirSlotsAndRetryIndependently() async throws {
        let probe = ImageDownloadProbe()
        let model = ImageViewerModel(images: [.init(url: nil), .init(url: selected)]) {
            try await probe.fetch($0)
        }
        await model.load(0)
        let attempt = Task { await model.load(1) }
        try await waitUntil { await probe.contains(self.selected) }
        await probe.fail(selected)
        await attempt.value
        XCTAssertEqual(model.failures, [0, 1])
        let retry = Task { await model.load(1, retry: true) }
        try await waitUntil { await probe.contains(self.selected) }
        await probe.succeed(selected)
        await retry.value
        XCTAssertEqual(model.files[1], selected)
        XCTAssertEqual(model.failures, [0])
    }

    func testNilURLDoesNotChangePayloadIdentityOrStartingPosition() {
        let payload = ImageViewerPayload(urls: [nil, selected], startIndex: 1)
        XCTAssertEqual(payload.id, payload.id)
        XCTAssertEqual(payload.startIndex, 1)
        XCTAssertEqual(payload.images.count, 2)
    }

    func testOriginalOnlyLoadsOnRequestAndLatePreviewCannotReplaceIt() async throws {
        let image = ViewerImage(url: URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg"))
        let previewURL = try XCTUnwrap(image.previewURL)
        let originalURL = try XCTUnwrap(image.originalURL)
        let probe = ImageDownloadProbe()
        let model = ImageViewerModel(images: [image]) { try await probe.fetch($0) }
        let preview = Task { await model.prepare(startIndex: 0) }
        try await waitUntil { await probe.contains(previewURL) }
        let originalStarted = await probe.contains(originalURL)
        XCTAssertFalse(originalStarted)
        let original = Task { await model.loadOriginal(0) }
        try await waitUntil { await probe.contains(originalURL) }
        await probe.succeed(originalURL)
        await original.value
        await probe.succeed(previewURL)
        await preview.value
        XCTAssertEqual(model.files[0], originalURL)
        XCTAssertEqual(model.previews[0], previewURL)
        XCTAssertFalse(model.canLoadOriginal(0))
    }

    func testOriginalFailureKeepsPreviewAndCanRetry() async throws {
        let image = ViewerImage(url: URL(string: "https://i0.hdslb.com/bfs/new_dyn/example.jpg"))
        let originalURL = try XCTUnwrap(image.originalURL)
        let previewURL = try XCTUnwrap(image.previewURL)
        let probe = ImageDownloadProbe()
        let model = ImageViewerModel(images: [image]) { url in
            if url == previewURL { return previewURL }
            return try await probe.fetch(url)
        }
        await model.load(0)
        let original = Task { await model.loadOriginal(0) }
        try await waitUntil { await probe.contains(originalURL) }
        await probe.fail(originalURL)
        await original.value
        XCTAssertEqual(model.files[0], previewURL)
        XCTAssertTrue(model.originalFailures.contains(0))
        XCTAssertTrue(model.canLoadOriginal(0))
        let retry = Task { await model.loadOriginal(0) }
        try await waitUntil { await probe.contains(originalURL) }
        await probe.succeed(originalURL)
        await retry.value
        XCTAssertEqual(model.files[0], originalURL)
        XCTAssertFalse(model.originalFailures.contains(0))
    }

    func testOnlyPublicBiliImageURLsReceivePreviewTransform() {
        let original = URL(string: "https://i0.hdslb.com/bfs/new_dyn/a.jpg")!
        let transformed = ViewerImage(url: URL(string: original.absoluteString + "@320w_320h.webp"))
        XCTAssertEqual(transformed.originalURL, original)
        XCTAssertEqual(transformed.previewURL?.lastPathComponent, "a.jpg@960w_960h_1e_75q.webp")
        for raw in ["https://example.com/bfs/a.jpg", "https://i0.hdslb.com/bfs/a.jpg?sign=example", "https://hdslb.com.example.com/bfs/a.jpg"] {
            let url = URL(string: raw)!
            XCTAssertEqual(ViewerImage(url: url).previewURL, url)
            XCTAssertEqual(ViewerImage(url: url).originalURL, url)
        }
    }

    func testImagePanIsDisabledUntilZoomedSoPagingCanStartOnTheImage() {
        let view = ViewerZoomScrollView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.display(UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { _ in })
        view.layoutIfNeeded()
        XCTAssertFalse(view.panGestureRecognizer.isEnabled)
        view.setZoomScale(2, animated: false)
        XCTAssertTrue(view.panGestureRecognizer.isEnabled)
        view.setZoomScale(1, animated: false)
        XCTAssertFalse(view.panGestureRecognizer.isEnabled)
    }

    func testPagerIncludesLoadingAndFailedPagesInBothDirections() async throws {
        let model = ImageViewerModel(images: [.init(url: first), .init(url: nil), .init(url: selected)]) { $0 }
        await model.load(1)
        var selection = 0
        let coordinator = ImageGalleryPreview.Coordinator(count: 3, model: model,
            selection: Binding(get: { selection }, set: { selection = $0 }))
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        let firstPage = try XCTUnwrap(coordinator.page(0))
        let failedPage = try XCTUnwrap(coordinator.pageViewController(pager, viewControllerAfter: firstPage) as? ImageGalleryPreview.Page)
        XCTAssertEqual(failedPage.index, 1)
        let loadingPage = try XCTUnwrap(coordinator.pageViewController(pager, viewControllerAfter: failedPage) as? ImageGalleryPreview.Page)
        XCTAssertEqual(loadingPage.index, 2)
        XCTAssertEqual((coordinator.pageViewController(pager, viewControllerBefore: loadingPage) as? ImageGalleryPreview.Page)?.index, 1)
        XCTAssertNil(coordinator.pageViewController(pager, viewControllerAfter: loadingPage))
        XCTAssertNil(coordinator.pageViewController(pager, viewControllerBefore: firstPage))
    }

    func testAnimatedImageDecodesIndividualFramesAndTheirTiming() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: file) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        for color in [UIColor.red, .blue] {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let frames = try await ViewerImageFrames(file: file)
        XCTAssertEqual(frames.count, 2)
        let first = try await frames.frame(0)
        let second = try await frames.frame(1)
        XCTAssertEqual(first.duration, 0.2, accuracy: 0.01)
        XCTAssertGreaterThan(first.image.width, 0)
        XCTAssertNotEqual(first.image.dataProvider?.data as Data?, second.image.dataProvider?.data as Data?)
    }

    func testShareUsesSmallPreparedPreviewAndPreservesOriginalFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600), format: format).image { context in
            UIColor.systemGreen.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }
        try XCTUnwrap(original.pngData()).write(to: file)
        let frames = try await ViewerImageFrames(file: file)
        let preview = try await frames.thumbnail()
        XCTAssertEqual(max(preview.width, preview.height), 256)
        let source = ImageShareSource(file: file, preview: UIImage(cgImage: preview))
        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        XCTAssertEqual(source.activityViewControllerPlaceholderItem(controller) as? URL, file)
        XCTAssertEqual(source.activityViewController(controller, itemForActivityType: .saveToCameraRoll) as? URL, file)
        XCTAssertNotNil(source.activityViewControllerLinkMetadata(controller)?.imageProvider)
        XCTAssertEqual(source.activityViewController(controller, dataTypeIdentifierForActivityType: nil), "public.png")
        let animated = ImageShareSource(file: URL(fileURLWithPath: "/tmp/animated.gif"), preview: nil)
        XCTAssertEqual(animated.activityViewController(controller, dataTypeIdentifierForActivityType: nil), "com.compuserve.gif")
    }

    func testShareSheetForegroundPresentationCost() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.frame = scene.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600), format: format).image { context in
            UIColor.systemGreen.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }
        try XCTUnwrap(image.pngData()).write(to: file)
        let frames = try await ViewerImageFrames(file: file)
        let thumbnail = UIImage(cgImage: try await frames.thumbnail())
        for pass in 0..<3 {
            for prepared in [false, true] {
                let start = CACurrentMediaTime()
                let controller = UIActivityViewController(activityItems: prepared ? [ImageShareSource(file: file, preview: thumbnail)] : [file], applicationActivities: nil)
                controller.popoverPresentationController?.sourceView = host.view
                controller.popoverPresentationController?.sourceRect = CGRect(x: 20, y: 20, width: 44, height: 44)
                let shown = expectation(description: "share sheet presented")
                host.present(controller, animated: false) { shown.fulfill() }
                await fulfillment(of: [shown], timeout: 10)
                XCTAssertTrue(controller.view.window === window)
                print("IMAGE_SHARE prepared=\(prepared) pass=\(pass) present_ms=\((CACurrentMediaTime() - start) * 1000)")
                if prepared && pass == 2 {
                    try await Task.sleep(for: .milliseconds(300))
                    let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    })
                    attachment.name = "prepared-image-share-sheet"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                let dismissed = expectation(description: "share sheet dismissed")
                host.dismiss(animated: false) { dismissed.fulfill() }
                await fulfillment(of: [dismissed], timeout: 10)
            }
        }
    }

    func testGalleryForegroundLayouts() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var files: [Int: URL] = [:]
        for (index, color) in [UIColor.systemRed, .systemBlue, .systemGreen].enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
                NSString(string: "Image \(index + 1)").draw(at: CGPoint(x: 160, y: 350),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.white])
            }
            let file = directory.appendingPathComponent("image-\(index).png")
            try XCTUnwrap(image.pngData()).write(to: file)
            files[index] = file
        }
        let originalFile = try XCTUnwrap(files[2])
        let model = ImageViewerModel(images: [
            .init(url: files[0]), .init(url: first), .init(url: nil), .init(url: files[1]), .init(url: URL(string: "https://i0.hdslb.com/bfs/new_dyn/gallery.jpg"))
        ]) { url in
            url.host == "i0.hdslb.com" ? originalFile : url
        }
        for index in [0, 2, 3, 4] { await model.load(index) }
        XCTAssertNil(model.files[1], "保留永不完成的下载页")
        XCTAssertTrue(model.failures.contains(2))
        for (name, style, size, frame, start) in [
            ("light-portrait", UIUserInterfaceStyle.light, DynamicTypeSize.large, CGRect(x: 0, y: 0, width: 402, height: 874), 0),
            ("light-loading", .light, .large, CGRect(x: 0, y: 0, width: 402, height: 874), 1),
            ("dark-failure", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 402, height: 874), 2),
            ("dark-large-landscape", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 874, height: 402), 3),
            ("light-original-control", .light, .large, CGRect(x: 0, y: 0, width: 402, height: 874), 4),
            ("dark-large-original-control", .dark, .accessibility3, CGRect(x: 0, y: 0, width: 874, height: 402), 4)
        ] {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: GalleryFixture(model: model, selection: start).environment(\.dynamicTypeSize, size))
            window.frame = frame
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
            try await Task.sleep(for: .seconds(1))
            window.layoutIfNeeded()
            XCTAssertTrue(host.view.window === window)
            XCTAssertEqual(scene.activationState, .foregroundActive)
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            })
            attachment.name = "image-gallery-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("等待下载任务超时")
    }
}

private actor ImageDownloadProbe {
    private var pending: [URL: CheckedContinuation<URL, Error>] = [:]
    func fetch(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { pending[url] = $0 }
    }
    func contains(_ url: URL) -> Bool { pending[url] != nil }
    func succeed(_ url: URL) { pending.removeValue(forKey: url)?.resume(returning: url) }
    func fail(_ url: URL) { pending.removeValue(forKey: url)?.resume(throwing: URLError(.timedOut)) }
}

private struct GalleryFixture: View {
    let model: ImageViewerModel
    @State var selection: Int
    var body: some View {
        NavigationStack {
            ImageGalleryPreview(count: 5, model: model, selection: $selection)
                .navigationTitle("\(selection + 1) / 5")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
