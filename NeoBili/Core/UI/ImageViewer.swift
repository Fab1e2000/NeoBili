import QuickLook
import SwiftUI
import UIKit

/// 图片查看器里的一张图。
struct ViewerImage: Identifiable, Hashable, Sendable {
    let url: URL?
    var id: String { url?.absoluteString ?? UUID().uuidString }
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
    /// present 出来的，同一处再叠第二个 fullScreenCover 会冲突。
    func imageViewerHost() -> some View {
        modifier(ImageViewerHost())
    }
}

private struct ImageViewerHost: ViewModifier {
    @State private var payload: ImageViewerPayload?
    @State private var openAction = EnvironmentAction<ImageViewerPayload> { _ in }

    func body(content: Content) -> some View {
        openAction.setHandler { [payload = $payload] in payload.wrappedValue = $0 }
        return content
            .environment(\.openImageViewer, openAction)
            .fullScreenCover(item: $payload) { ImageViewer(payload: $0) }
    }
}

/// 全屏图片查看器。
///
/// 交互整套交给系统的 QuickLook：捏合缩放、双击定点放大、左右翻页、
/// 顶部「1 / 9」计数、分享面板（自带「存储图像」）、标记，都不用自己写。
///
/// 代价是 QuickLook 只认**本地文件**，所以先把图下到磁盘缓存里再交给它。
struct ImageViewer: View {
    let payload: ImageViewerPayload

    @Environment(\.dismiss) private var dismiss

    @State private var files: [URL]?
    /// 有图片下载失败时，起始下标要按剩下的重新对齐。
    @State private var start = 0
    @State private var failureMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let files {
                QuickLookViewer(files: files, startIndex: start) { dismiss() }
                    .ignoresSafeArea()
            } else {
                loadingOrFailure
            }
        }
        .task(id: payload.id) { await prepare() }
    }

    @ViewBuilder
    private var loadingOrFailure: some View {
        VStack(spacing: 16) {
            if let failureMessage {
                Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                Text(failureMessage).font(.subheadline)
            } else {
                LoadingTaskAnchor().tint(.white)
            }

            Button("关闭") { dismiss() }
                .font(.subheadline)
                .padding(.top, 8)
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    /// 把这一组图都落到磁盘再交给 QuickLook。
    ///
    /// 全部就绪才展示：QuickLook 的数据源是按需回调的，某一张还没落地时
    /// 那一页会直接显示成"无法预览"，而且不会自己重试。图片一般不超过九张，
    /// 命中缓存时这一步没有任何等待。
    private func prepare() async {
        failureMessage = nil
        let remotes = payload.images.compactMap(\.url)
        guard !remotes.isEmpty else {
            failureMessage = "没有可显示的图片"
            return
        }

        // 并发下，不然九张图要一张接一张地等。
        let downloaded = await withTaskGroup(of: (Int, URL?).self) { group in
            for (position, remote) in remotes.enumerated() {
                group.addTask {
                    (position, try? await ImageFileCache.shared.localFile(for: remote))
                }
            }
            var result: [Int: URL] = [:]
            for await (position, local) in group { result[position] = local }
            return result
        }

        var located: [URL] = []
        var adjustedStart = 0
        for position in remotes.indices {
            // 落在起始那一张之前的失败图会让下标前移，这里跟着对齐。
            if position == payload.startIndex { adjustedStart = located.count }
            if let local = downloaded[position] { located.append(local) }
        }

        guard !located.isEmpty else {
            failureMessage = "图片加载失败"
            return
        }
        start = min(adjustedStart, located.count - 1)
        files = located
    }
}

/// 包一层 QuickLook。外面再套一个导航控制器，才有顶部那条工具栏
/// （标题是「1 / 9」，右边是分享）；关闭按钮得自己加，嵌入式的
/// QLPreviewController 不会自带"完成"。
private struct QuickLookViewer: UIViewControllerRepresentable {
    let files: [URL]
    let startIndex: Int
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(files: files, onClose: onClose)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.currentPreviewItemIndex = min(max(startIndex, 0), max(files.count - 1, 0))
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: context.coordinator,
            action: #selector(Coordinator.close)
        )
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {
        context.coordinator.files = files
        context.coordinator.onClose = onClose
    }

    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var files: [URL]
        var onClose: () -> Void

        init(files: [URL], onClose: @escaping () -> Void) {
            self.files = files
            self.onClose = onClose
        }

        nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            MainActor.assumeIsolated { files.count }
        }

        nonisolated func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            MainActor.assumeIsolated { files[index] as NSURL }
        }

        @objc func close() { onClose() }
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

        let (data, _) = try await URLSession.shared.data(for: request)
        guard !data.isEmpty else { throw BiliAPIError.invalidURL }

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
