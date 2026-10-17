#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import ImageIO
import SwiftUI
import UIKit

/// 只有放大后才让图片的平移手势接管触摸；正常大小的横向拖动交给外层分页。
struct ZoomableViewerImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ViewerZoomScrollView { ViewerZoomScrollView() }
    func updateUIView(_ view: ViewerZoomScrollView, context: Context) { view.display(image) }
}

final class ViewerZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var viewport: CGSize = .zero
    private var imageSize: CGSize = .zero

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = String(localized: "图片")
        imageView.accessibilityIdentifier = "imageViewer.image"
        addSubview(imageView)
        isScrollEnabled = false
        panGestureRecognizer.isEnabled = false
        pinchGestureRecognizer?.isEnabled = true
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(_ image: UIImage) {
        imageView.image = image
        if imageSize != image.size {
            let oldRatio = imageSize.height > 0 ? imageSize.width / imageSize.height : 0
            let newRatio = image.size.height > 0 ? image.size.width / image.size.height : 0
            imageSize = image.size
            if abs(oldRatio - newRatio) > 0.001 { viewport = .zero; setNeedsLayout() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if viewport != bounds.size, bounds.width > 0, bounds.height > 0, imageSize.width > 0, imageSize.height > 0 {
            viewport = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
            contentSize = imageView.bounds.size
        }
        centerImage()
    }

    private func centerImage() {
        imageView.center = CGPoint(x: max(bounds.width, contentSize.width) / 2, y: max(bounds.height, contentSize.height) / 2)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        isScrollEnabled = zoomScale > minimumZoomScale + 0.01
        panGestureRecognizer.isEnabled = isScrollEnabled
        pinchGestureRecognizer?.isEnabled = true
        centerImage()
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.01 { setZoomScale(1, animated: true); return }
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}

/// 在独立 actor 上解码，每次只保留当前帧；离开页面即取消动画，不展开整组动图到内存。
actor ViewerImageFrames {
    private let source: CGImageSource
    nonisolated let count: Int

    init(file: URL) async throws {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw URLError(.cannotDecodeContentData) }
        self.source = source
        count = CGImageSourceGetCount(source)
    }

    func thumbnail(maximumPixelDimension: Int = 256) throws -> CGImage {
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return image
    }

    struct Frame: Sendable { let image: CGImage; let duration: Double }

    func frame(_ index: Int) throws -> Frame {
        try Task.checkCancellation()
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 1
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 1
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        var delay = 0.1
        for (dictionary, unclamped, clamped) in [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime)
        ] {
            if let metadata = properties[dictionary] as? [CFString: Any],
               let value = (metadata[unclamped] ?? metadata[clamped]) as? NSNumber {
                delay = value.doubleValue
                break
            }
        }
        return Frame(image: image, duration: delay.isFinite && delay >= 0.02 ? delay : 0.1)
    }
}
