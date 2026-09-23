import SwiftUI

/// Headers, request coalescing and a decoded bitmap sized to the actual view.
/// Geometry observation leaves the caller's aspect ratio and layout untouched.
struct BiliImage: View {
    let url: URL?
    /// 调用方已经知道的显示尺寸（点）。给了就不用等布局测量：第一帧就能按这个
    /// 尺寸取缓存或开始加载，也和列表预取用同一个缓存键。
    var targetSize: CGSize? = nil
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?
    @State private var loadedURL: URL?
    @State private var failed = false
    @State private var measuredSize: ImagePixelSize?

    private struct Request: Hashable {
        let url: URL?
        let pixelSize: ImagePixelSize?
    }

    private var pixelSize: ImagePixelSize? {
        if let targetSize { return ImagePixelSize(points: targetSize, scale: displayScale) }
        return measuredSize
    }

    /// 自己加载好的图优先；还没加载时，已经解码过（或被预取过）的图直接画，不先闪空白。
    private var displayedImage: Image? {
        if loadedURL == url, let image { return image }
        guard let url, let pixelSize,
              let cached = BiliImageMemoryCache.image(for: url, pixelSize: pixelSize) else { return nil }
        return Image(uiImage: cached)
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                image.resizable()
            } else if failed {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(LoadingTaskAnchor().controlSize(.small))
            }
        }
        .modifier(MeasuredPixelSize(enabled: targetSize == nil, scale: displayScale, size: $measuredSize))
        .task(id: Request(url: url, pixelSize: pixelSize)) {
            await load()
        }
    }

    private func load() async {
        if loadedURL != url {
            image = nil
            loadedURL = url
        }
        failed = false
        guard let url else {
            failed = true
            return
        }
        guard let pixelSize else { return }
        if let cached = BiliImageMemoryCache.image(for: url, pixelSize: pixelSize) {
            image = Image(uiImage: cached)
            return
        }
        // 网络抖动或请求排队超时不应让图片一直停在失败图标：稍等后再试两次。
        for attempt in 0..<3 {
            do {
                let loaded = try await BiliImageLoader.load(url, pixelSize: pixelSize)
                if !Task.isCancelled { image = Image(uiImage: loaded) }
                return
            } catch {
                guard !Task.isCancelled else { return }
                guard attempt < 2 else {
                    failed = true
                    return
                }
                do { try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 3)) } catch { return }
            }
        }
    }
}

/// 没有给出显示尺寸的图片才需要等布局测量自己的大小。
private struct MeasuredPixelSize: ViewModifier {
    let enabled: Bool
    let scale: CGFloat
    @Binding var size: ImagePixelSize?

    func body(content: Content) -> some View {
        if enabled {
            content.onGeometryChange(for: ImagePixelSize?.self) { proxy in
                ImagePixelSize(points: proxy.size, scale: scale)
            } action: { size = $0 }
        } else {
            content
        }
    }
}
