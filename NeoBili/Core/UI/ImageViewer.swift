#if canImport(NeoBiliData)
import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// 图片查看器里的一张图。
struct ViewerImage: Identifiable, Hashable, Sendable {
    let url: URL?
    var id: String { url?.absoluteString ?? "missing-image" }

    // 仅转换 B 站公开图片 CDN；带查询参数的地址可能已签名，保持原样。
    var originalURL: URL? {
        guard let url, Self.canResize(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.path = String(parts.path.split(separator: "@", maxSplits: 1)[0])
        return parts.url
    }

    var previewURL: URL? {
        guard let originalURL, Self.canResize(originalURL),
              var parts = URLComponents(url: originalURL, resolvingAgainstBaseURL: false) else { return url }
        parts.path += "@960w_960h_1e_75q.webp"
        return parts.url
    }

    private static func canResize(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return (host == "hdslb.com" || host.hasSuffix(".hdslb.com"))
            && url.path.hasPrefix("/bfs/") && url.query == nil && url.fragment == nil
    }
}

/// 一次查看请求：一组图 + 从第几张开始。
struct ImageViewerPayload: Identifiable {
    let images: [ViewerImage]
    let startIndex: Int

    var id: String { "\(startIndex)-" + images.map(\.id).joined(separator: "|") }

    init(images: [ViewerImage], startIndex: Int = 0) {
        self.images = images
        self.startIndex = min(max(startIndex, 0), max(images.count - 1, 0))
    }

    init(urls: [URL?], startIndex: Int = 0) {
        self.init(images: urls.map { ViewerImage(url: $0) }, startIndex: startIndex)
    }
}

/// @Entry 的默认值在每次读取时都会求值，类类型会因此被反复分配；
/// 兜底动作共用这一个全局实例（没有 host 接住时的空操作）。
/// 实例本身从不被改写（真正的动作都在 host 各自的盒子上），按非隔离常量处理。
nonisolated(unsafe) private let unhostedImageViewerAction = EnvironmentAction<ImageViewerPayload> { _ in }

extension EnvironmentValues {
    /// 打开图片查看器。由最近的一个 `imageViewerHost()` 接住。
    /// 用引用盒子而不是裸闭包，见 `EnvironmentAction` 的说明。
    @Entry var openImageViewer = unhostedImageViewerAction
}

extension View {
    /// 在这一屏挂一个图片查看器。它下面的任何视图都能通过
    /// `@Environment(\.openImageViewer)` 打开它。
    ///
    /// 每一屏各挂各的，而不是全 App 共用一个：视频页本身就是从根视图
    /// present 出来的，图片面板由当前所在屏幕承载。
    func imageViewerHost() -> some View {
        modifier(ImageViewerHost())
    }
}

private struct ImageViewerHost: ViewModifier {
    @State private var payload: ImageViewerPayload?
    @State private var openAction = EnvironmentAction<ImageViewerPayload> { _ in }

    func body(content: Content) -> some View {
        content
            .environment(\.openImageViewer, openAction)
            .onAppear {
                openAction.setHandler { [payload = $payload] in payload.wrappedValue = $0 }
            }
            .sheet(item: $payload) {
                ImageViewer(payload: $0)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }
}

/// 每页独立加载；保留原始顺序，失败的图片不会挤掉用户选中的那张。
struct ImageViewer: View {
    let payload: ImageViewerPayload
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int
    @State private var model: ImageViewerModel
    @State private var shareIsPresented = false

    init(payload: ImageViewerPayload) {
        self.payload = payload
        _selection = State(initialValue: payload.startIndex)
        _model = State(initialValue: ImageViewerModel(images: payload.images))
    }

    var body: some View {
        NavigationStack {
            Group {
                if payload.images.isEmpty {
                    ContentUnavailableView("没有可显示的图片", systemImage: "photo")
                } else {
                    ImageGalleryPreview(count: payload.images.count, model: model, selection: $selection, isActive: !shareIsPresented)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(payload.images.isEmpty ? "图片" : "\(selection + 1) / \(payload.images.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("imageViewer.close")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if let file = model.originals[selection] ?? model.previews[selection] {
                        ImageShareButton(file: file) { shareIsPresented = $0 }
                    }
                }
            }
        }
        .task(id: selection) { await model.prepare(startIndex: selection) }
    }
}

@MainActor
@Observable
final class ImageViewerModel {
    private(set) var previews: [Int: URL] = [:]
    private(set) var originals: [Int: URL] = [:]
    var files: [Int: URL] { previews.merging(originals) { _, original in original } }
    private(set) var failures: Set<Int> = []
    private(set) var originalFailures: Set<Int> = []
    private(set) var originalLoading: Set<Int> = []
    @ObservationIgnored private var loading: [Request: Task<URL, Error>] = [:]
    private let images: [ViewerImage]
    private let fetch: @Sendable (URL) async throws -> URL
    private struct Request: Hashable { let index: Int; let original: Bool }

    @ObservationIgnored private let cache: ImageFileCache?
    @ObservationIgnored private let owner = UUID()

    init(images: [ViewerImage], cache: ImageFileCache = .shared,
         fetch: (@Sendable (URL) async throws -> URL)? = nil) {
        self.images = images
        self.cache = fetch == nil ? cache : nil
        let owner = self.owner
        self.fetch = fetch ?? { try await cache.localFile(for: $0, owner: owner) }
    }

    deinit {
        if let cache {
            let owner = owner
            Task { await cache.release(owner: owner) }
        }
    }

    func decodingFailed(_ index: Int, file: URL) async {
        guard images.indices.contains(index) else { return }
        let original = originals[index] == file
        guard original || previews[index] == file else { return }
        if original {
            originals[index] = nil
            originalFailures.insert(index)
        } else {
            previews[index] = nil
            failures.insert(index)
        }
        let remote = original ? images[index].originalURL : images[index].previewURL
        if let remote, let cache { await cache.invalidate(remote, file: file) }
    }

    func canLoadOriginal(_ index: Int) -> Bool {
        images.indices.contains(index) && images[index].originalURL != nil
            && images[index].originalURL != images[index].previewURL && originals[index] == nil
    }

    func prepare(startIndex: Int) async {
        // 三个独立请求：慢图不能挡住所选页或另一侧相邻页。不自动下载整组原图。
        await withTaskGroup(of: Void.self) { group in
            for index in [startIndex, startIndex - 1, startIndex + 1] where images.indices.contains(index) {
                group.addTask { await self.load(index) }
            }
        }
    }

    func load(_ index: Int, retry: Bool = false) async {
        await load(index, original: false, retry: retry)
    }

    func loadOriginal(_ index: Int) async {
        await load(index, original: true, retry: true)
    }

    private func load(_ index: Int, original: Bool, retry: Bool) async {
        guard images.indices.contains(index) else { return }
        if original {
            guard originals[index] == nil else { return }
        } else {
            guard previews[index] == nil, originals[index] == nil, retry || !failures.contains(index) else { return }
        }
        let remote = original ? images[index].originalURL : images[index].previewURL
        guard let remote else { failures.insert(index); return }
        if original { originalFailures.remove(index); originalLoading.insert(index) }
        else { failures.remove(index) }
        let key = Request(index: index, original: original)
        let task: Task<URL, Error>
        if let existing = loading[key] { task = existing }
        else {
            let fetch = fetch
            task = Task { try await fetch(remote) }
            loading[key] = task
        }
        do {
            let file = try await task.value
            // 下载结果按页与清晰度存储；迟到的预览不能覆盖已加载的原图。
            if original { originals[index] = file }
            else { previews[index] = file }
        } catch {
            if !error.isCancellation {
                if original { originalFailures.insert(index) }
                else { failures.insert(index) }
            }
        }
        loading[key] = nil
        if original { originalLoading.remove(index) }
    }
}

/// 页数只由图片列表决定；加载、失败、解码都不会增删或禁用页面。
struct ImageGalleryPreview: UIViewControllerRepresentable {
    @Environment(\.scenePhase) private var scenePhase
    let count: Int
    let model: ImageViewerModel
    @Binding var selection: Int
    var isActive = true

    func makeCoordinator() -> Coordinator { Coordinator(count: count, model: model, selection: $selection) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        if let page = context.coordinator.page(selection) {
            pager.setViewControllers([page], direction: .forward, animated: false)
        }
        return pager
    }
    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        context.coordinator.updateSelection(selection, isForeground: isActive && scenePhase == .active)
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let count: Int
        let model: ImageViewerModel
        let selection: Binding<Int>
        private var pages: [Int: Page] = [:]
        private var current: Int
        var isForeground = true
        init(count: Int, model: ImageViewerModel, selection: Binding<Int>) {
            self.count = count
            self.model = model
            self.selection = selection
            current = selection.wrappedValue
        }
        func page(_ index: Int) -> Page? {
            guard (0..<count).contains(index) else { return nil }
            if let existing = pages[index] { return existing }
            let page = Page(index: index, rootView: ImageViewerPage(model: model, index: index, active: index == current && isForeground, nearby: true))
            pages[index] = page
            return page
        }
        func updateSelection(_ index: Int, isForeground: Bool? = nil) {
            let foreground = isForeground ?? self.isForeground
            guard current != index || self.isForeground != foreground else { return }
            self.isForeground = foreground
            current = index
            for (position, page) in pages {
                page.rootView = ImageViewerPage(model: model, index: position, active: position == index && foreground, nearby: abs(position - index) <= 1)
            }
            pages = pages.filter { abs($0.key - index) <= 1 }
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? Page else { return nil }
            return self.page(page.index - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? Page else { return nil }
            return self.page(page.index + 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let page = pageViewController.viewControllers?.first as? Page else { return }
            updateSelection(page.index)
            selection.wrappedValue = page.index
        }
    }
    final class Page: UIHostingController<ImageViewerPage> {
        let index: Int
        init(index: Int, rootView: ImageViewerPage) {
            self.index = index
            super.init(rootView: rootView)
        }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

struct ImageViewerPage: View {
    let model: ImageViewerModel
    let index: Int
    let active: Bool
    let nearby: Bool
    @State private var decoded: UIImage?
    @State private var decodedFile: URL?
    @State private var frameCount = 0
    @State private var decodeFailed = false
    @State private var decodeAttempt = 0
    private var file: URL? { model.originals[index] ?? model.previews[index] }
    private struct DisplayRequest: Hashable { let file: URL?; let active: Bool; let nearby: Bool; let attempt: Int }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if let decoded {
                ZoomableViewerImage(image: decoded)
            } else if decodeFailed || model.failures.contains(index) {
                VStack(spacing: 12) {
                    Text("图片加载失败")
                    Button("重试") {
                        decodeAttempt += 1
                        Task { await model.load(index, retry: true) }
                    }
                        .accessibilityIdentifier("imageViewer.retry")
                }
            } else {
                ProgressView("正在加载图片")
                    .accessibilityIdentifier("imageViewer.loading.\(index)")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if decoded != nil, model.canLoadOriginal(index) {
                VStack(alignment: .trailing, spacing: 6) {
                    if model.originalFailures.contains(index) {
                        Text("原图加载失败")
                            .font(.app(.caption))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Button {
                        Task { await model.loadOriginal(index) }
                    } label: {
                        HStack(spacing: 6) {
                            if model.originalLoading.contains(index) {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(model.originalLoading.contains(index) ? "正在加载原图" : (model.originalFailures.contains(index) ? "重试" : "查看原图"))
                                .font(.app(.footnote))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.originalLoading.contains(index))
                    .accessibilityIdentifier("imageViewer.original.\(index)")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .task(id: DisplayRequest(file: file, active: active, nearby: nearby, attempt: decodeAttempt)) {
            guard nearby, let file else { decoded = nil; decodedFile = nil; frameCount = 0; return }
            // 分享面板覆盖时保留最后一帧；静态图也不因前后台或相邻页状态重新解码。
            if decodedFile == file, decoded != nil, (!active || frameCount == 1) { return }
            decodeFailed = false
            do {
                let frames = try await ViewerImageFrames(file: file)
                frameCount = frames.count
                var frameIndex = 0
                repeat {
                    try Task.checkCancellation()
                    let frame = try await frames.frame(frameIndex)
                    try Task.checkCancellation()
                    decoded = UIImage(cgImage: frame.image)
                    decodedFile = file
                    guard active, frames.count > 1 else { return }
                    try await Task.sleep(for: .seconds(frame.duration))
                    frameIndex = (frameIndex + 1) % frames.count
                } while !Task.isCancelled
            } catch {
                if !error.isCancellation, !Task.isCancelled {
                    // 保留已显示的有效预览；失败原图回到可重试状态，并清除坏文件。
                    if decodedFile == file { decoded = nil; decodedFile = nil; frameCount = 0 }
                    decodeFailed = true
                    await model.decodingFailed(index, file: file)
                }
            }
        }
    }
}
