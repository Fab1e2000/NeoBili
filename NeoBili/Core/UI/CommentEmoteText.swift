import NeoBiliCore
import NeoBiliDomain
import SwiftUI
import UIKit

/// 评论表情的图片仓库。
///
/// 表情要嵌在文字行里，所以不能用普通的异步图片视图——`Text` 只接受已经就绪、
/// 且尺寸正确的 `Image`。这里按 URL 合并加载，将原图归一化到最长 512 像素并
/// 有界缓存。后台按「URL + 目标高度 + 显示缩放」生成小图，正文读取对应缓存。
@MainActor
@Observable
final class CommentEmoteStore {
    private nonisolated static let scaledByteBudget = 32 * 1024 * 1024

    @Observable
    final class EmoteState {
        // The original cache owns even the bitmaps injected for layout tests.
        @ObservationIgnored weak var fixture: UIImage?
        var renderRevision = 0
    }
    // Each comment observes only the URLs it renders, not the whole image dictionary.
    @ObservationIgnored private var emoteStates: [URL: EmoteState] = [:]
    private(set) var memoryWarningRevision = 0

    private func state(for url: URL) -> EmoteState {
        if let existing = emoteStates[url] { return existing }
        let entry = EmoteState()
        emoteStates[url] = entry
        return entry
    }
    @ObservationIgnored private let originalsCache: ImageMemoryCache<URL, UIImage>
    private let notifications: NotificationCenter
    @ObservationIgnored private nonisolated(unsafe) var memoryPressureObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let requests = ImageRequestPool<URL, UIImage>()
    @ObservationIgnored private let renderRequests = ImageRequestPool<RenderRequest, Void>()
    @ObservationIgnored private let loader: @Sendable (URL) async throws -> UIImage
    @ObservationIgnored private let maximumPixelDimension: CGFloat
    @ObservationIgnored private let scaledCache: ImageMemoryCache<RenderRequest, UIImage>

    init(maximumOriginalBytes: Int = 16 * 1024 * 1024,
         notifications: NotificationCenter = .default,
         loader: @escaping @Sendable (URL) async throws -> UIImage = {
             try await BiliImageLoader.load($0, pixelSize: ImagePixelSize(points: CGSize(width: 256, height: 256), scale: 1))
         }) {
        let budget = max(4096, maximumOriginalBytes)
        let cache = ImageMemoryCache<URL, UIImage>(maximumBytes: budget, maximumEntries: 256)
        let variants = ImageMemoryCache<RenderRequest, UIImage>(maximumBytes: Self.scaledByteBudget, maximumEntries: 800)
        originalsCache = cache
        scaledCache = variants
        self.notifications = notifications
        // Align to 16 pixels so a 64-byte-aligned RGBA row also fits the budget.
        maximumPixelDimension = min(512, floor(sqrt(CGFloat(budget) / 4) / 16) * 16)
        self.loader = loader
        memoryPressureObserver = notifications.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            cache.removeAll()
            variants.removeAll()
            Task { @MainActor in self?.memoryWarningRevision &+= 1 }
        }
    }

    deinit {
        if let memoryPressureObserver { notifications.removeObserver(memoryPressureObserver) }
    }

    var cachedOriginalByteCount: Int { originalsCache.cachedByteCount }
    var loadingConsumerCount: Int { get async { await requests.consumerCount } }
    struct RenderSize: Hashable, Sendable {
        let height: CGFloat
        let scale: CGFloat
    }

    private struct RenderRequest: Hashable, Sendable {
        let url: URL
        let size: RenderSize
    }

    /// 返回已按目标高度缩放的表情。未就绪时调用方显示原文。
    func image(for url: URL, height: CGFloat, scale: CGFloat = 1) -> UIImage? {
        let request = RenderRequest(url: url, size: RenderSize(height: height, scale: scale))
        if let cached = scaledCache.value(for: request) { return cached }
        let entry = state(for: url)
        _ = entry.renderRevision
        // Layout fixtures can supply bitmaps without a view lifecycle.
        guard let fixture = entry.fixture else { return nil }
        let rendered = Self.scaled(fixture, toHeight: height, scale: scale)
        scaledCache.insert(rendered, for: request, cost: Self.pixelCost(rendered))
        return rendered
    }

    /// Each row joins the shared load. A disappearing row cancels only its
    /// own wait, so another visible comment cannot lose its pending emote.
    func preload(_ emotes: [CommentEmote], target: ((CommentEmote) -> RenderSize)? = nil) async {
        guard !Task.isCancelled else { return }
        var sizesByURL: [URL: Set<RenderSize>] = [:]
        for emote in emotes {
            guard let url = emote.secureURL else { continue }
            if let target { sizesByURL[url, default: []].insert(target(emote)) }
            else if sizesByURL[url] == nil { sizesByURL[url] = [] }
        }
        await withTaskGroup(of: Void.self) { group in
            for (url, sizes) in sizesByURL {
                if sizes.isEmpty {
                    guard originalsCache.value(for: url) == nil else { continue }
                } else {
                    guard sizes.contains(where: {
                        scaledCache.value(for: RenderRequest(url: url, size: $0)) == nil
                    }) else { continue }
                }
                group.addTask { [weak self] in await self?.load(url: url, sizes: sizes) }
            }
        }
    }

    /// 仅供间距测试：把现成图片塞进原图缓存，让渲染不依赖网络。
    func insertOriginalForTesting(_ image: UIImage, for url: URL) {
        scaledCache.removeAll()
        let prepared = Self.prepared(image, maximumDimension: maximumPixelDimension)
        originalsCache.insert(prepared, for: url, cost: Self.pixelCost(prepared))
        let entry = state(for: url)
        entry.fixture = prepared
        entry.renderRevision &+= 1
    }

    private func load(url: URL, sizes: Set<RenderSize>) async {
        do {
            let prepared: UIImage
            if let cached = originalsCache.value(for: url) {
                prepared = cached
            } else {
                prepared = try await requests.value(for: url) { [loader, maximumPixelDimension] in
                    let image = try await loader(url)
                    return try await Self.prepareOriginal(image, maximumDimension: maximumPixelDimension)
                }
                try Task.checkCancellation()
                originalsCache.insert(prepared, for: url, cost: Self.pixelCost(prepared))
            }
            for size in sizes { try await prepareRender(RenderRequest(url: url, size: size), from: prepared) }
        } catch { /* Keep the textual emote until a later appearance can retry. */ }
    }

    private func prepareRender(_ request: RenderRequest, from image: UIImage) async throws {
        guard scaledCache.value(for: request) == nil else { return }
        defer {
            if scaledCache.value(for: request) != nil { state(for: request.url).renderRevision &+= 1 }
        }
        try await renderRequests.value(for: request) { [scaledCache] in
            try await Self.render(image, request: request, cache: scaledCache)
        }
    }

    @concurrent
    private static func prepareOriginal(_ image: UIImage, maximumDimension: CGFloat) async throws -> UIImage {
        try Task.checkCancellation()
        return prepared(image, maximumDimension: maximumDimension)
    }

    @concurrent
    private static func render(_ image: UIImage, request: RenderRequest,
                               cache: ImageMemoryCache<RenderRequest, UIImage>) async throws {
        try Task.checkCancellation()
        guard cache.value(for: request) == nil else { return }
        let bitmap = scaled(image, toHeight: request.size.height, scale: request.size.scale)
        try Task.checkCancellation()
        cache.insert(bitmap, for: request, cost: pixelCost(bitmap))
    }

    private nonisolated static func prepared(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height) * image.scale
        let normalized: UIImage
        let bitmapBytes = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        if longestSide > maximumDimension || bitmapBytes > Int(maximumDimension * maximumDimension * 4) {
            let ratio = min(image.scale, maximumDimension / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, floor(image.size.width * ratio)),
                              height: max(1, floor(image.size.height * ratio)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.preferredRange = .standard
            normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else { normalized = image }
        return trimmed(normalized) ?? normalized
    }

    private nonisolated static func pixelCost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    /// 裁掉表情四周的透明留白。
    ///
    /// `Text` 里的图片按「图片底边贴文字基线」排版（已用像素级实验验证）。
    /// 很多表情 PNG 自带一圈透明边，底部那一段会把画面整个架高，表情看
    /// 起来浮在文字上方；裁掉之后画面本体真正贴住基线，与文字底边对齐。
    private nonisolated static func trimmed(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }

        // 统一绘制为预乘 alpha 的 RGBA 位图，再按 alpha 通道定位有效边界。
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width {
                // 几乎透明的边缘（alpha ≤ 8/255）不算画面。
                if pixels[row + x * 4 + 3] > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // 全图都是画面就不用裁。
        if minX == 0, minY == 0, maxX == width - 1, maxY == height - 1 { return nil }

        // CGContext 的 y 轴朝上，cropping 用的是图像坐标（y 朝下），翻一下。
        let rect = CGRect(
            x: minX,
            y: height - 1 - maxY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// `Text` 里的图片是按点尺寸原样画的，没法再 resize，所以在这里就缩到位。
    private nonisolated static func scaled(_ image: UIImage, toHeight height: CGFloat, scale: CGFloat) -> UIImage {
        let width = height * image.size.width / image.size.height
        let pixelWidth = width * scale
        let pixelHeight = height * scale
        let maximumSide: CGFloat = 4096
        // Standard RGBA uses four bytes per pixel. Leave room for row
        // alignment and pixel rounding before allocating the canvas.
        let rowPaddingAllowance: CGFloat = 256
        let pixelBudget = (CGFloat(scaledByteBudget) - rowPaddingAllowance * maximumSide) / 4
        let reduction = min(1, maximumSide / max(pixelWidth, pixelHeight),
                            sqrt(pixelBudget / (ceil(pixelWidth) * ceil(pixelHeight))))
        let size = reduction == 1 ? CGSize(width: width, height: height) : CGSize(
            width: max(1, floor(pixelWidth * reduction)) / scale,
            height: max(1, floor(pixelHeight * reduction)) / scale
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.preferredRange = .standard
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// 一段可能带表情的评论正文。
///
/// 正文里的表情是 `[doge]` 这样的字面量。这里把它按表情表切成若干段，
/// 图片就绪的换成图，没就绪或不认识的仍按原文显示——所以图还没下载完的时候
/// 读起来也不会缺字。
struct CommentEmoteText: View {
    let message: String
    let emotes: [String: CommentEmote]
    let font: Font
    /// 表情随这套文字样式的档位一起缩放。`Font` 本身查不回样式信息，
    /// 所以单独传一份进来。
    let textStyle: Font.TextStyle
    var prefix: String = ""
    var prefixURL: URL? = nil
    var prefixStyle = PrefixStyle()
    var prefixBadge: Image? = nil
    var prefixSuffix: String = ""
    var jumpURLs: [String: CommentJumpLink] = [:]
    /// 隐藏的高度探针共享可见正文的图片请求，仅观察已加载的表情。
    var loadsEmotes = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.commentTimeJump) private var timeJump
    @Environment(\.openURL) private var openURL

    @Environment(\.commentEmoteStore) private var environmentStore
    var store: CommentEmoteStore? = nil
    private var resolvedStore: CommentEmoteStore { store ?? environmentStore }

    /// 前缀（楼中楼里的「名字：」）的字重和颜色。不设置时沿用次级文字色。
    struct PrefixStyle {
        var weight: Font.Weight? = nil
        /// 相对主文字色的强度；为 nil 时用系统次级文字色。
        var opacity: Double? = nil
    }

    private struct LoadIdentity: Equatable {
        let store: ObjectIdentifier?
        let emotes: [String: CommentEmote]
        let textStyle: Font.TextStyle
        let typeSize: DynamicTypeSize
        let scale: CGFloat
        let memoryWarningRevision: Int?
        let needsImages: Bool
    }

    var body: some View {
        let store = emotes.isEmpty ? nil : resolvedStore
        let content = composed(using: store)
        let identity = LoadIdentity(store: store.map(ObjectIdentifier.init), emotes: emotes, textStyle: textStyle,
                                    typeSize: typeSize, scale: displayScale,
                                    memoryWarningRevision: loadsEmotes ? store?.memoryWarningRevision : nil,
                                    needsImages: loadsEmotes && content.hasMissingImages)
        return content.text
            .font(font)
            .environment(\.openURL, OpenURLAction { url in
                guard let seconds = CommentTimeLinks.seconds(from: url) else {
                    openURL(url)
                    return .handled
                }
                timeJump?(seconds)
                return .handled
            })
            .task(id: identity) {
                guard identity.needsImages, let store else { return }
                await Self.preload(emotes, store: store, textStyle: textStyle,
                                   typeSize: typeSize, scale: displayScale)
            }
    }

    static func preload(_ emotes: [String: CommentEmote], store: CommentEmoteStore, textStyle: Font.TextStyle,
                        typeSize: DynamicTypeSize, scale: CGFloat) async {
        let font = scaledFont(textStyle: textStyle, typeSize: typeSize)
        await store.preload(Array(emotes.values)) { .init(height: emoteHeight(for: $0, font: font), scale: scale) }
    }

    private func composed(using store: CommentEmoteStore?) -> (text: Text, hasMissingImages: Bool) {
        // 一次组合只求一次字号；每个表情不再反复创建 UIFontMetrics / traits。
        let scaledFont = emotes.isEmpty ? nil : Self.scaledFont(textStyle: textStyle, typeSize: typeSize)
        let baseline = ((scaledFont?.descender ?? 0) * Self.baselineOffsetRatio).rounded()
        var prefixText = AttributedString(prefix)
        prefixText.foregroundColor = prefixStyle.opacity.map { Color.primary.opacity($0) } ?? .secondary
        if let weight = prefixStyle.weight { prefixText.font = font.weight(weight) }
        prefixText.link = prefixURL
        var decoratedPrefix = Text(prefixText)
        if let prefixBadge { decoratedPrefix = decoratedPrefix + Text(" ") + Text(prefixBadge).baselineOffset(-3) }
        decoratedPrefix = decoratedPrefix + Text(prefixSuffix)
        guard let store else {
            let text = CommentLinks.attributed(message, metadata: jumpURLs, includesTimes: timeJump != nil)
            return (decoratedPrefix + Text(text), false)
        }
        var hasMissingImages = false
        let text = CommentEmoteSegments.prepared(message: message, emotes: emotes)
            .reduce(decoratedPrefix) { partial, segment in
            switch segment {
            case .text(let value):
                return partial + Text(CommentLinks.attributed(value, metadata: jumpURLs, includesTimes: timeJump != nil))
            case .emote(let literal, let emote):
                guard let url = emote.secureURL, let font = scaledFont else { return partial + Text(literal) }
                guard let image = store.image(for: url, height: Self.emoteHeight(for: emote, font: font), scale: displayScale) else {
                    hasMissingImages = true
                    // 还没下载好就先显示原来那段文字，不留空洞。
                    return partial + Text(literal)
                }
                // 往下沉一点，见 `emoteBaselineOffset`。
                return partial + Text(Image(uiImage: image)).baselineOffset(baseline)
            }
        }
        return (text, hasMissingImages)
    }

    /// 降部高度的取用比例。0 就是回到 SwiftUI 默认的基线对齐。
    private static let baselineOffsetRatio: CGFloat = 0.5

    // MARK: - 表情高度

    /// 小表情的画布高度：当前档位下这套字体的**上行高度**（ascent）。
    ///
    /// `Text` 里的图片底边贴文字基线、整幅都在基线以上，一旦高过上行高度，
    /// 行高就被撑大（中文字面只到 cap 高度，顶部还会明显高出文字一截）。
    /// 参考 PiliPlus：小表情底边贴基线、比字面大一些，行高靠 Flutter 的
    /// strut 定死；SwiftUI 没有 strut，等价做法是把画布夹在上行高度以内，
    /// 底边仍与文字底边对齐。大表情（倍率 ≥ 2）刻意保留大尺寸、允许撑高行，
    /// 与 PiliPlus 的 40pt 大表情一致。
    ///
    /// 高度从 `UIFontMetrics` 按当前档位现算，不经过 `@ScaledMetric`——
    /// 后者不跟随本 App 注入的档位（文字在变、表情基准值不变），
    /// 表情大小会和文字脱节。
    private static func emoteHeight(for emote: CommentEmote, font: UIFont) -> CGFloat {
        if emote.heightMultiplier >= 2 {
            return (font.pointSize * emote.heightMultiplier).rounded()
        }
        return font.ascender.rounded()
    }

    /// 当前档位下这套样式的实际字体。
    private static func scaledFont(textStyle: Font.TextStyle, typeSize: DynamicTypeSize) -> UIFont {
        let category = Self.contentCategory(typeSize)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let style: UIFont.TextStyle
        let baseSize: CGFloat
        switch textStyle {
        case .caption, .caption2: (style, baseSize) = (.caption1, 12)
        case .footnote: (style, baseSize) = (.footnote, 13)
        case .body: (style, baseSize) = (.body, 17)
        default: (style, baseSize) = (.subheadline, 15)
        }
        return UIFontMetrics(forTextStyle: style)
            .scaledFont(for: AppFont.uiFont(ofSize: baseSize), compatibleWith: traits)
    }

    /// 把 SwiftUI 的档位枚举翻成 UIKit 的内容大小分类。
    private static func contentCategory(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

}
