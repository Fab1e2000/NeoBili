import SwiftUI
import UIKit

/// 评论表情的图片仓库。
///
/// 表情要嵌在文字行里，所以不能用普通的异步图片视图——`Text` 只接受已经就绪、
/// 且尺寸正确的 `Image`。这里按 URL 把**原图**下载并缓存一份；拼进 `Text` 前
/// 再按当时的字号就地缩放。
///
/// 缩放结果刻意不落缓存：表情高度跟着文字档位走（见 `CommentEmoteText`），
/// 档位一变就要按新尺寸重排，如果按「URL + 高度」缓存，改档位后旧图全部
/// 命不中、还得重新下载一遍才能显示。原图只下一遍，缩放是本地的小图重绘，
/// 代价可以忽略。
@MainActor
@Observable
final class CommentEmoteStore {
    static let shared = CommentEmoteStore()

    private var originals: [URL: UIImage] = [:]
    private var loading: Set<URL> = []

    /// 已经就绪的表情，按目标高度缩放好。原图没就绪时返回 nil，调用方按原文显示。
    func image(for url: URL, height: CGFloat) -> Image? {
        guard let original = originals[url] else { return nil }
        return Image(uiImage: Self.scaled(original, toHeight: height))
    }

    /// 把这条评论用到的表情原图都取回来。重复调用不会重复下载。
    func preload(_ emotes: [CommentEmote]) async {
        await withTaskGroup(of: Void.self) { group in
            for emote in emotes {
                guard let url = emote.secureURL else { continue }
                guard originals[url] == nil, !loading.contains(url) else { continue }
                loading.insert(url)
                group.addTask { [weak self] in
                    await self?.load(url: url)
                }
            }
        }
    }

    /// 仅供间距测试：把现成图片塞进原图缓存，让渲染不依赖网络。
    func insertOriginalForTesting(_ image: UIImage, for url: URL) {
        originals[url] = Self.trimmed(image) ?? image
    }

    private func load(url: URL) async {
        defer { loading.remove(url) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let original = UIImage(data: data),
              original.size.height > 0
        else { return }

        // 裁掉透明边再入库，原因见 `trimmed`。
        originals[url] = Self.trimmed(original) ?? original
    }

    /// 裁掉表情四周的透明留白。
    ///
    /// `Text` 里的图片按「图片底边贴文字基线」排版（已用像素级实验验证）。
    /// 很多表情 PNG 自带一圈透明边，底部那一段会把画面整个架高，表情看
    /// 起来浮在文字上方；裁掉之后画面本体真正贴住基线，与文字底边对齐。
    private static func trimmed(_ image: UIImage) -> UIImage? {
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
    private static func scaled(_ image: UIImage, toHeight height: CGFloat) -> UIImage {
        let size = CGSize(width: height * image.size.width / image.size.height, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UITraitCollection.current.displayScale
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

    @Environment(\.dynamicTypeSize) private var typeSize

    private var store: CommentEmoteStore { .shared }

    var body: some View {
        composed
            .font(font)
            .task(id: message) {
                await store.preload(Array(emotes.values))
            }
    }

    private var composed: Text {
        segments.reduce(Text(prefix).foregroundColor(.secondary)) { partial, segment in
            switch segment {
            case .text(let value):
                return partial + Text(value)
            case .emote(let literal, let emote):
                guard let url = emote.secureURL,
                      let image = store.image(for: url, height: emoteHeight(for: emote))
                else {
                    // 还没下载好就先显示原来那段文字，不留空洞。
                    return partial + Text(literal)
                }
                // 往下沉一点，见 `emoteBaselineOffset`。
                return partial + Text(image).baselineOffset(emoteBaselineOffset)
            }
        }
    }

    /// 表情相对基线往下沉的量（负值向下）。
    ///
    /// `Text` 里的行内图片是底边贴基线排的，而中文字面框要伸到基线**以下**
    /// 一段——汉字没有降部，整行的视觉底边就落在基线之下，图片于是显得被
    /// 架高了。这里按降部高度的一半把图片压下去，对齐汉字的视觉底边。
    ///
    /// 取一半而不是取满：取满是对齐 `g`/`y` 这类降部字母的最低点，中文行里
    /// 表情会低于汉字底边，显得往下掉。
    private var emoteBaselineOffset: CGFloat {
        (scaledFont.descender * Self.baselineOffsetRatio).rounded()
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
    private func emoteHeight(for emote: CommentEmote) -> CGFloat {
        if emote.heightMultiplier >= 2 {
            return (scaledFont.pointSize * emote.heightMultiplier).rounded()
        }
        return scaledFont.ascender.rounded()
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

    private enum Segment {
        case text(String)
        case emote(String, CommentEmote)
    }

    /// 扫描正文，把方括号里能在表情表中查到的那些切出来。
    ///
    /// 只认表情表里真实存在的键：正文里本来就可能有 `[捂脸]` 这种没有对应图片的
    /// 方括号内容，那些必须原样留着。
    private var segments: [Segment] {
        guard !emotes.isEmpty else { return [.text(message)] }

        var result: [Segment] = []
        var plain = ""
        var index = message.startIndex

        while index < message.endIndex {
            guard message[index] == "[",
                  let close = message[index...].firstIndex(of: "]")
            else {
                plain.append(message[index])
                index = message.index(after: index)
                continue
            }

            let literal = String(message[index...close])
            if let emote = emotes[literal] {
                if !plain.isEmpty {
                    result.append(.text(plain))
                    plain = ""
                }
                result.append(.emote(literal, emote))
                index = message.index(after: close)
            } else {
                plain.append(message[index])
                index = message.index(after: index)
            }
        }

        if !plain.isEmpty { result.append(.text(plain)) }
        return result
    }
}
