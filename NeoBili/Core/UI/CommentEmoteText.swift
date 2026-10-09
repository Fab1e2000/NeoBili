import SwiftUI
import UIKit

/// 评论表情的图片仓库。
///
/// 表情要嵌在文字行里，所以不能用普通的异步图片视图——`Text` 只接受已经就绪、
/// 且尺寸正确的 `Image`。这里按 URL 合并加载，将原图归一化到最长 512 像素并
/// 有界缓存；拼进 `Text` 前再按当时的字号与显示缩放生成小图。
///
/// 缩放结果按「URL + 目标高度 + 显示缩放」记忆化（NSCache，内存压力下自动淘汰）：
/// 滚动期同一行会随列表重建反复求值，每次都重绘小图会叠成持续的主线程
/// CPU。文字档位变了 key 随之变化，不存在旧档位图冒充新档位的问题。
@MainActor
@Observable
final class CommentEmoteStore {
    static let shared = CommentEmoteStore()

    @Observable
    final class Original {
        // The bounded cache owns originals; observation slots do not retain
        // every bitmap ever seen during a long comments session.
        weak var image: UIImage?
    }
    // Each comment observes only the URLs it renders, not the whole image dictionary.
    @ObservationIgnored private var originals: [URL: Original] = [:]

    private func original(for url: URL) -> Original {
        if let existing = originals[url] { return existing }
        let entry = Original()
        originals[url] = entry
        return entry
    }
    @ObservationIgnored private let originalsCache: ImageMemoryCache<URL, UIImage>
    @ObservationIgnored private let requests = ImageRequestPool<URL, UIImage>()
    @ObservationIgnored private let loader: @Sendable (URL) async throws -> UIImage
    @ObservationIgnored private let maximumPixelDimension: CGFloat

    init(maximumOriginalBytes: Int = 16 * 1024 * 1024,
         loader: @escaping @Sendable (URL) async throws -> UIImage = {
             try await BiliImageLoader.load($0, pixelSize: ImagePixelSize(points: CGSize(width: 256, height: 256), scale: 1))
         }) {
        let budget = max(4096, maximumOriginalBytes)
        originalsCache = ImageMemoryCache(maximumBytes: budget, maximumEntries: 256)
        // Align to 16 pixels so a 64-byte-aligned RGBA row also fits the budget.
        maximumPixelDimension = min(512, floor(sqrt(CGFloat(budget) / 4) / 16) * 16)
        self.loader = loader
    }

    var cachedOriginalByteCount: Int { originalsCache.cachedByteCount }
    var loadingConsumerCount: Int { get async { await requests.consumerCount } }
    private let scaledCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 800
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// 已经就绪的表情，按目标高度缩放好。原图没就绪时返回 nil，调用方按原文显示。
    func image(for url: URL, height: CGFloat, scale: CGFloat = 1) -> Image? {
        let key = "\(url.absoluteString)|\(Int(height * 100))|\(scale)" as NSString
        if let cached = scaledCache.object(forKey: key) {
            return Image(uiImage: cached)
        }
        guard let original = original(for: url).image else { return nil }
        _ = originalsCache.value(for: url)
        let scaled = Self.scaled(original, toHeight: height, scale: scale)
        scaledCache.setObject(scaled, forKey: key, cost: Self.pixelCost(scaled))
        return Image(uiImage: scaled)
    }

    /// Each row joins the shared load. A disappearing row cancels only its
    /// own wait, so another visible comment cannot lose its pending emote.
    func preload(_ emotes: [CommentEmote]) async {
        let urls = Set(emotes.compactMap(\.secureURL))
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                guard original(for: url).image == nil else { continue }
                group.addTask { [weak self] in await self?.load(url: url) }
            }
        }
    }

    /// 仅供间距测试：把现成图片塞进原图缓存，让渲染不依赖网络。
    func insertOriginalForTesting(_ image: UIImage, for url: URL) {
        scaledCache.removeAllObjects()
        install(Self.prepared(image, maximumDimension: maximumPixelDimension), for: url)
    }

    private func install(_ image: UIImage, for url: URL) {
        originalsCache.insert(image, for: url, cost: Self.pixelCost(image))
        if original(for: url).image !== image { original(for: url).image = image }
    }

    private func load(url: URL) async {
        do {
            let prepared = try await requests.value(for: url) { [loader, maximumPixelDimension] in
                let image = try await loader(url)
                try Task.checkCancellation()
                // Trimming scans all pixels, so keep it off the main actor and
                // coalesce it along with the transfer for duplicate comments.
                let task = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    return Self.prepared(image, maximumDimension: maximumPixelDimension)
                }
                return try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }
            }
            guard !Task.isCancelled else { return }
            install(prepared, for: url)
        } catch { /* Keep the textual emote until a later appearance can retry. */ }
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

    private static func pixelCost(_ image: UIImage) -> Int {
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

        // 画进一张已知格式（RGBA、非预乘）的位图里再按 alpha 找边界，
        /// 避开原图通道顺序/预乘与否的差异。
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
        let size = CGSize(width: height * image.size.width / image.size.height, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
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
    var jumpURLs: [String: CommentJumpLink] = [:]
    /// 隐藏的高度探针共享可见正文的图片请求，仅观察已加载的表情。
    var loadsEmotes = true

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.commentTimeJump) private var timeJump
    @Environment(\.openURL) private var openURL

    var store: CommentEmoteStore = .shared

    private struct LoadIdentity: Equatable {
        let emotes: [String: CommentEmote]
        let typeSize: DynamicTypeSize
        let scale: CGFloat
    }

    var body: some View {
        composed
            .font(font)
            .environment(\.openURL, OpenURLAction { url in
                guard let seconds = CommentTimeLinks.seconds(from: url) else {
                    openURL(url)
                    return .handled
                }
                timeJump?(seconds)
                return .handled
            })
            .task(id: LoadIdentity(emotes: emotes, typeSize: typeSize, scale: displayScale)) {
                guard loadsEmotes, !emotes.isEmpty else { return }
                await store.preload(Array(emotes.values))
            }
    }

    private var composed: Text {
        // 一次组合只求一次字号；每个表情不再反复创建 UIFontMetrics / traits。
        let scaledFont = emotes.isEmpty ? nil : scaledFont
        let baseline = ((scaledFont?.descender ?? 0) * Self.baselineOffsetRatio).rounded()
        var prefixText = AttributedString(prefix)
        prefixText.foregroundColor = .secondary
        prefixText.link = prefixURL
        if emotes.isEmpty {
            return Text(prefixText + CommentLinks.attributed(message, metadata: jumpURLs, includesTimes: timeJump != nil))
        }
        return CommentEmoteSegments.prepared(message: message, emotes: emotes)
            .reduce(Text(prefixText)) { partial, segment in
            switch segment {
            case .text(let value):
                return partial + Text(CommentLinks.attributed(value, metadata: jumpURLs, includesTimes: timeJump != nil))
            case .emote(let literal, let emote):
                guard let url = emote.secureURL,
                      let font = scaledFont,
                      let image = store.image(for: url, height: emoteHeight(for: emote, font: font), scale: displayScale)
                else {
                    // 还没下载好就先显示原来那段文字，不留空洞。
                    return partial + Text(literal)
                }
                // 往下沉一点，见 `emoteBaselineOffset`。
                return partial + Text(image).baselineOffset(baseline)
            }
        }
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
    private func emoteHeight(for emote: CommentEmote, font: UIFont) -> CGFloat {
        if emote.heightMultiplier >= 2 {
            return (font.pointSize * emote.heightMultiplier).rounded()
        }
        return font.ascender.rounded()
    }

    /// 当前档位下这套样式的实际字体。
    private var scaledFont: UIFont {
        let category = Self.contentCategory(typeSize)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: uiTextStyle)
            .scaledFont(for: .systemFont(ofSize: baseSize), compatibleWith: traits)
    }

    /// `.large`（默认档）下这几种样式的字号，供 `UIFontMetrics` 起算。
    ///
    /// 认不出的样式退回 subheadline，和以前的行为一致。
    private var baseSize: CGFloat {
        switch textStyle {
        case .caption, .caption2: 12
        case .footnote: 13
        case .body: 17
        default: 15
        }
    }

    /// SwiftUI 的文字样式翻成 UIKit 的同名样式。
    private var uiTextStyle: UIFont.TextStyle {
        switch textStyle {
        case .caption, .caption2: .caption1
        case .footnote: .footnote
        case .body: .body
        default: .subheadline
        }
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
