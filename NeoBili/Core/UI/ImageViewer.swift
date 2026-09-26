import ImageIO
import QuickLook
import SwiftUI
import UIKit

/// 图片查看器里的一张图。
struct ViewerImage: Identifiable, Hashable, Sendable {
    let url: URL?
    var id: String { url?.absoluteString ?? "missing-image" }
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
                    TabView(selection: $selection) {
                        ForEach(payload.images.indices, id: \.self) { index in
                            page(at: index).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
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
                    if let file = model.files[selection] {
                        ShareLink(item: file) { Label("分享图片", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .task { await model.prepare(startIndex: payload.startIndex) }
        // 快速翻页时立即请求所选页，不必等待后台预取轮到它。
        .task(id: selection) { await model.load(selection) }
    }

    @ViewBuilder
    private func page(at index: Int) -> some View {
        if let file = model.files[index] {
            // 只实例化当前及相邻预览，避免一组大图同时解码。
            if abs(index - selection) <= 1 {
                ImageFilePreview(file: file)
            } else {
                Color(uiColor: .systemBackground)
            }
        } else if model.failures.contains(index) {
            ContentUnavailableView {
                Label("图片加载失败", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("其他图片仍可左右滑动查看。")
            } actions: {
                Button("重试") { Task { await model.load(index, retry: true) } }
                    .accessibilityIdentifier("imageViewer.retry")
            }
        } else {
            ProgressView("正在加载图片").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
@Observable
final class ImageViewerModel {
    private(set) var files: [Int: URL] = [:]
    private(set) var failures: Set<Int> = []
    @ObservationIgnored private var loading: [Int: Task<URL, Error>] = [:]
    private let images: [ViewerImage]
    private let fetch: @Sendable (URL) async throws -> URL

    init(images: [ViewerImage], fetch: @escaping @Sendable (URL) async throws -> URL = {
        try await ImageFileCache.shared.localFile(for: $0)
    }) {
        self.images = images
        self.fetch = fetch
    }

    func prepare(startIndex: Int) async {
        await load(startIndex)
        // 当前图完成后再预取其余图；顺序下载控制弱设备的网络和解码压力。
        let order = images.indices.filter { $0 != startIndex }.sorted {
            abs($0 - startIndex) < abs($1 - startIndex)
        }
        for index in order {
            guard !Task.isCancelled else { return }
            await load(index)
        }
    }

    func load(_ index: Int, retry: Bool = false) async {
        guard images.indices.contains(index), files[index] == nil,
              retry || !failures.contains(index) else { return }
        guard let remote = images[index].url else { failures.insert(index); return }
        failures.remove(index)
        let task: Task<URL, Error>
        if let existing = loading[index] {
            task = existing
        } else {
            let fetch = fetch
            task = Task { try await fetch(remote) }
            loading[index] = task
        }
        do {
            let file = try await task.value
            guard !Task.isCancelled else { return }
            files[index] = file
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            failures.insert(index)
        }
        loading[index] = nil
    }
}

/// 单页 QuickLook 保留系统缩放和动图解码；外层统一负责分页、分享及关闭。
private struct ImageFilePreview: UIViewControllerRepresentable {
    let file: URL
    func makeCoordinator() -> Coordinator { Coordinator(file: file) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return preview
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.file != file else { return }
        context.coordinator.file = file
        controller.reloadData()
    }
    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var file: URL
        init(file: URL) { self.file = file }
        nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            MainActor.assumeIsolated { file as NSURL }
        }
    }
}

/// 图片的磁盘缓存。
///
/// QuickLook 只认本地文件，所以查看大图前要先把原始字节落盘。放在 Caches 下：
/// 这些文件随时可以重新下载，系统空间紧张时自己清掉就行，不需要我们管理容量。
///
/// 存的是**原始字节**而不是重新编码的位图，动图因此还能动，体积也不会被放大。
actor ImageFileCache {
    static let shared = ImageFileCache()

    private let directory: URL
    /// 同一张图并发请求时只下载一次。
    private var inFlight: [URL: Task<URL, Error>] = [:]

    /// QuickLook 靠扩展名认格式，所以按字节头判断真实格式，不信 URL 上的后缀
    /// ——B 站的图片地址常带 `@1e_1c.webp` 这类后缀，和实际内容未必一致。
    private static let knownExtensions = ["jpg", "png", "gif", "webp", "heic"]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appending(path: "ImageViewer", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func localFile(for remote: URL) async throws -> URL {
        if let cached = cachedFile(for: remote) { return cached }

        if let existing = inFlight[remote] { return try await existing.value }

        let task = Task<URL, Error> { try await download(remote) }
        inFlight[remote] = task
        defer { inFlight[remote] = nil }
        return try await task.value
    }

    private func cachedFile(for remote: URL) -> URL? {
        let name = Self.digest(of: remote)
        for ext in Self.knownExtensions {
            let candidate = directory.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func download(_ remote: URL) async throws -> URL {
        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw URLError(.cannotDecodeContentData) }

        let file = directory.appending(path: "\(Self.digest(of: remote)).\(Self.fileExtension(of: data))")
        try data.write(to: file, options: .atomic)
        return file
    }

    /// 用地址算一个稳定的文件名。地址本身有斜杠和查询串，不能直接当文件名。
    private static func digest(of remote: URL) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Data(remote.absoluteString.utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// 按字节头认格式。认不出就当 JPEG——B 站的图绝大多数是 JPEG，
    /// 而且 QuickLook 自己还会再嗅一次，扩展名只是给它的第一个提示。
    private static func fileExtension(of data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        guard head.count >= 12 else { return "jpg" }

        if head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return "jpg" }
        if head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return "png" }
        if head[0] == 0x47, head[1] == 0x49, head[2] == 0x46 { return "gif" }
        // RIFF....WEBP
        if head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return "webp" }
        // ....ftyp（HEIC 及同族）
        if head[4] == 0x66, head[5] == 0x74, head[6] == 0x79, head[7] == 0x70 { return "heic" }
        return "jpg"
    }
}
