import SwiftUI

/// 一组可点开查看的图片。动态卡片、动态详情、评论配图共用同一套排版和交互。
///
/// 单图按原图比例（已压在 3:4 到 16:9 之间），多图排成正方形九宫格。
/// 点任意一张打开查看器，并从这一张开始。
struct TappableImageGrid: View {
    /// 每张图的地址与它自己的宽高比。宽高比只有单图时用得上。
    let images: [(url: URL?, aspectRatio: CGFloat)]
    var spacing: CGFloat = 4
    var cornerRadius: CGFloat = 4
    /// 最多画几张。九宫格之外的不画，但仍然会进查看器。
    var displayLimit: Int = 9

    @Environment(\.openImageViewer) private var openImageViewer

    var body: some View {
        if images.count == 1, let single = images.first {
            thumbnail(at: 0, url: single.url, aspectRatio: single.aspectRatio)
        } else {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(Array(images.prefix(displayLimit).enumerated()), id: \.offset) { position, image in
                    thumbnail(at: position, url: image.url, aspectRatio: 1)
                }
            }
        }
    }

    private func thumbnail(at position: Int, url: URL?, aspectRatio: CGFloat) -> some View {
        CoverThumbnail(url: url, aspectRatio: aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 卡片整体也挂着"点进详情"的手势，这里的手势在内层，优先响应。
            .contentShape(Rectangle())
            .onTapGesture {
                openImageViewer(ImageViewerPayload(urls: images.map(\.url), startIndex: position))
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("第 \(position + 1) 张图片，共 \(images.count) 张")
    }

    /// 和官方一致：2 张、4 张排两列，其余排三列。
    private var columns: [GridItem] {
        let count = images.count == 2 || images.count == 4 ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}

extension TappableImageGrid {
    init(
        dynamicImages: [DynamicImage],
        spacing: CGFloat = 4,
        cornerRadius: CGFloat = 4
    ) {
        self.init(
            images: dynamicImages.map { ($0.secureURL, $0.displayAspectRatio) },
            spacing: spacing,
            cornerRadius: cornerRadius
        )
    }

    init(
        commentPictures: [CommentPicture],
        spacing: CGFloat = 4,
        cornerRadius: CGFloat = 4
    ) {
        self.init(
            images: commentPictures.map { ($0.secureURL, $0.displayAspectRatio) },
            spacing: spacing,
            cornerRadius: cornerRadius
        )
    }
}
