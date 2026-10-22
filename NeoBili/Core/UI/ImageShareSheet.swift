#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import LinkPresentation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 预览在按钮出现后后台准备；点击时只提交文件地址和已就绪的小图。
struct ImageShareButton: View {
    let file: URL
    var onPresentationChanged: (Bool) -> Void = { _ in }
    @State private var preview: UIImage?
    @State private var previewFile: URL?
    @State private var request: ImageShareRequest?

    var body: some View {
        Button {
            request = ImageShareRequest(file: file, preview: previewFile == file ? preview : nil)
            onPresentationChanged(true)
        } label: {
            Label("分享图片", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("imageViewer.share")
        .sheet(item: $request, onDismiss: { onPresentationChanged(false) }) { request in
            ImageShareSheet(source: ImageShareSource(file: request.file, preview: request.preview))
        }
        .task(id: file) {
            preview = nil
            previewFile = nil
            do {
                let frames = try await ViewerImageFrames(file: file)
                let image = try await frames.thumbnail()
                try Task.checkCancellation()
                preview = UIImage(cgImage: image)
                previewFile = file
            } catch { /* 分享仍可立即打开，实际文件不依赖预览解码。 */ }
        }
    }
}

private struct ImageShareRequest: Identifiable {
    let id = UUID()
    let file: URL
    let preview: UIImage?
}

struct ImageShareSheet: UIViewControllerRepresentable {
    let source: ImageShareSource
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 主线程回调中不读文件、不解码图片；分享接收方取到完整文件，动图也保留原格式。
final class ImageShareSource: NSObject, UIActivityItemSource {
    let file: URL
    private let metadata: LPLinkMetadata
    init(file: URL, preview: UIImage?) {
        self.file = file
        metadata = LPLinkMetadata()
        metadata.title = String(localized: "图片")
        if let preview { metadata.imageProvider = NSItemProvider(object: preview) }
        super.init()
    }
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { file }
    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { file }
    func activityViewController(_ controller: UIActivityViewController, dataTypeIdentifierForActivityType type: UIActivity.ActivityType?) -> String {
        UTType(filenameExtension: file.pathExtension)?.identifier ?? UTType.image.identifier
    }
    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? { metadata }
}
