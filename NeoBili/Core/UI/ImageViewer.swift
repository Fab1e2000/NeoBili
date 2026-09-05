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

extension EnvironmentValues {
    /// 打开图片查看器。由最近的一个 `imageViewerHost()` 接住。
    @Entry var openImageViewer: (ImageViewerPayload) -> Void = { _ in }
}

extension View {
    /// 在这一屏挂一个图片查看器。它下面的任何视图都能通过
    /// `@Environment(\.openImageViewer)` 打开它。
    ///
    /// 每一屏各挂各的，而不是全 App 共用一个：视频页本身就是从根视图
    /// present 出来的，同一处再叠第二个 fullScreenCover 是presenting冲突。
    func imageViewerHost() -> some View {
        modifier(ImageViewerHost())
    }
}

private struct ImageViewerHost: ViewModifier {
    @State private var payload: ImageViewerPayload?

    func body(content: Content) -> some View {
        content
            .environment(\.openImageViewer) { payload = $0 }
            .fullScreenCover(item: $payload) { ImageViewer(payload: $0) }
    }
}

/// 全屏图片查看器：双指缩放、拖动、双击缩放、左右翻页、下滑关闭、保存/分享。
///
/// 三种拖动（翻页、平移、下滑关闭）共用同一个 `DragGesture`，按当前缩放级别和
/// 起手方向分派。分成多个手势的话它们会互相抢，缩放状态下尤其容易误翻页。
struct ImageViewer: View {
    let payload: ImageViewerPayload

    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    /// 已经取到的原图，保存和分享要用。键是图片下标。
    @State private var loaded: [Int: UIImage] = [:]

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    /// 翻页和下滑关闭的实时位移。同一次拖动只会有一个非零。
    @State private var pageDrag: CGFloat = 0
    @State private var dismissDrag: CGFloat = 0
    @State private var dragAxis: DragAxis?

    @State private var saveMessage: String?

    private enum DragAxis { case paging, dismissing, panning }

    private static let maxScale: CGFloat = 4
    private static let doubleTapScale: CGFloat = 2.5
    private static let dismissThreshold: CGFloat = 120
    private static let pageSpacing: CGFloat = 24

    init(payload: ImageViewerPayload) {
        self.payload = payload
        _index = State(initialValue: payload.startIndex)
    }

    private var currentImage: UIImage? { loaded[index] }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()

                pages(width: width)
            }
            .contentShape(Rectangle())
            .gesture(drag(width: width))
            .simultaneousGesture(magnify)
            .onTapGesture(count: 2) { toggleZoom() }
            .overlay(alignment: .top) { chrome }
            .overlay(alignment: .bottom) { toast }
        }
        .statusBarHidden()
        // 背景自己画，系统的 cover 背景留白会在下滑关闭时露出来。
        .presentationBackground(.clear)
    }

    // MARK: - 内容

    private func pages(width: CGFloat) -> some View {
        HStack(spacing: Self.pageSpacing) {
            ForEach(Array(payload.images.enumerated()), id: \.element.id) { position, image in
                ViewerPage(url: image.url) { loaded[position] = $0 }
                    .frame(width: width)
                    // 缩放和平移只作用在当前这一张上。
                    .scaleEffect(position == index ? scale : 1)
                    .offset(position == index ? offset : .zero)
            }
        }
        .offset(x: -CGFloat(index) * (width + Self.pageSpacing) + pageDrag)
        .offset(y: dismissDrag)
        // 下滑时整体跟着缩小，松手回弹或关闭。
        .scaleEffect(dismissProgress > 0 ? 1 - dismissProgress * 0.2 : 1)
    }

    private var chrome: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("关闭")

            Spacer()

            if payload.images.count > 1 {
                Text("\(index + 1) / \(payload.images.count)")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }

            Spacer()

            Menu {
                Button("保存到相册", systemImage: "square.and.arrow.down") { saveCurrent() }
                if let currentImage {
                    ShareLink(
                        item: Image(uiImage: currentImage),
                        preview: SharePreview("图片", image: Image(uiImage: currentImage))
                    ) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .disabled(currentImage == nil)
            .accessibilityLabel("更多操作")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        // 下滑关闭时一起淡掉，别让工具条孤零零挂在半透明画面上。
        .opacity(1 - dismissProgress * 2.5)
    }

    @ViewBuilder
    private var toast: some View {
        if let saveMessage {
            Text(saveMessage)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 40)
                .transition(.opacity)
        }
    }

    // MARK: - 手势

    /// 0（没拖）到 1（拖满一个关闭阈值）。背景透明度和缩小幅度都跟它走。
    private var dismissProgress: CGFloat {
        min(abs(dismissDrag) / (Self.dismissThreshold * 2), 1)
    }

    private var backgroundOpacity: Double {
        1 - Double(dismissProgress) * 0.7
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, 0.6), Self.maxScale)
            }
            .onEnded { _ in
                if scale < 1 {
                    resetZoom()
                } else {
                    committedScale = scale
                    committedOffset = offset
                }
            }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragAxis == nil {
                    dragAxis = axis(for: value.translation)
                }
                switch dragAxis {
                case .panning:
                    offset = CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    )
                case .paging:
                    pageDrag = rubberBanded(value.translation.width, width: width)
                case .dismissing:
                    dismissDrag = value.translation.height
                case nil:
                    break
                }
            }
            .onEnded { value in
                switch dragAxis {
                case .panning:
                    committedOffset = offset
                case .paging:
                    endPaging(translation: value.translation.width,
                              predicted: value.predictedEndTranslation.width,
                              width: width)
                case .dismissing:
                    endDismissing(translation: value.translation.height,
                                  predicted: value.predictedEndTranslation.height)
                case nil:
                    break
                }
                dragAxis = nil
            }
    }

    /// 放大状态下一律当作平移；否则按起手方向分给翻页或关闭。
    private func axis(for translation: CGSize) -> DragAxis {
        if scale > 1.01 { return .panning }
        return abs(translation.width) > abs(translation.height) ? .paging : .dismissing
    }

    /// 第一张往右拖、最后一张往左拖时加阻尼：拖不过去，但手上有反馈。
    private func rubberBanded(_ raw: CGFloat, width: CGFloat) -> CGFloat {
        let atStart = index == 0 && raw > 0
        let atEnd = index == payload.images.count - 1 && raw < 0
        return (atStart || atEnd) ? raw * 0.35 : raw
    }

    private func endPaging(translation: CGFloat, predicted: CGFloat, width: CGFloat) {
        // 甩得够快也算翻页，不必真的拖过三分之一。
        let shouldAdvance = abs(translation) > width / 3 || abs(predicted) > width / 2
        var target = index
        if shouldAdvance {
            target = translation < 0 ? index + 1 : index - 1
        }
        target = min(max(target, 0), payload.images.count - 1)

        withAnimation(.snappy(duration: 0.28)) {
            index = target
            pageDrag = 0
        }
        resetZoom()
    }

    private func endDismissing(translation: CGFloat, predicted: CGFloat) {
        if abs(translation) > Self.dismissThreshold || abs(predicted) > Self.dismissThreshold * 2 {
            dismiss()
        } else {
            withAnimation(.snappy(duration: 0.28)) { dismissDrag = 0 }
        }
    }

    private func toggleZoom() {
        withAnimation(.snappy(duration: 0.28)) {
            if scale > 1.01 {
                scale = 1
                offset = .zero
            } else {
                scale = Self.doubleTapScale
            }
            committedScale = scale
            committedOffset = offset
        }
    }

    private func resetZoom() {
        withAnimation(.snappy(duration: 0.28)) {
            scale = 1
            offset = .zero
        }
        committedScale = 1
        committedOffset = .zero
    }

    // MARK: - 保存

    private func saveCurrent() {
        guard let currentImage else { return }
        UIImageWriteToSavedPhotosAlbum(currentImage, nil, nil, nil)
        show("已保存到相册")
    }

    private func show(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) { saveMessage = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.2)) { saveMessage = nil }
        }
    }
}

/// 查看器里的一张图。自己取图，取到之后把原图回传给查看器备用（保存/分享）。
private struct ViewerPage: View {
    let url: URL?
    let onLoad: (UIImage) -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                    Text("图片加载失败").font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            guard let url else {
                failed = true
                return
            }
            do {
                let loaded = try await BiliImageLoader.load(url)
                guard !Task.isCancelled else { return }
                image = loaded
                onLoad(loaded)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}
