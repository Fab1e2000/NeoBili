import SwiftUI
import Synchronization
import UIKit

/// 卡片标题的后台预排版。
///
/// 真机录到滑动时主线程约 8.5% 花在文字排版上，一半多是两行标题的换行；中文系统下
/// 系统每次换行还会重新去磁盘查断字词典。标题和封面走同一条路：进入屏幕前在后台
/// 排好版、画成一张模板图，卡片渲染时同步取用；没取到就退回普通 `Text`，显示结果一致。
///
/// 排版用系统的 NSStringDrawing：字体、行距、末尾省略号都和 SwiftUI `Text` 对齐（行距由
/// SwiftUI 自己量出），但换行是「逐行排满」。SwiftUI `Text` 用的是系统内部的均衡换行，
/// 没有公开接口能复现，真实标题里约 1/4 的换行位置会不同；这是有意接受的取舍。
/// 为了同一个标题每次出现都一样，缓存没命中时就在主线程当场排一次，不退回 `Text`。
enum PreparedTitle {
    struct Key: Hashable, Sendable {
        let title: String
        let pixelWidth: Int
        let fontSize: CGFloat
        let scale: CGFloat

        /// 宽度无效（布局还没完成）时不预排版，卡片直接用普通 `Text`。
        init?(title: String, width: CGFloat, fontSize: CGFloat, scale: CGFloat) {
            guard width > 1, fontSize > 0, scale > 0 else { return nil }
            self.title = title
            pixelWidth = Int((width * scale).rounded())
            self.fontSize = fontSize
            self.scale = scale
        }

        var width: CGFloat { CGFloat(pixelWidth) / scale }
    }

    /// 和 SwiftUI 对齐所需的排版参数，按字号分别量一次。
    struct Metrics: Sendable {
        /// SwiftUI 两行标题的高度，也就是原来 `lineLimit(2, reservesSpace: true)` 预留的高度。
        /// 预排版的图和退回的 `Text` 共用，卡片布局不受是否命中缓存影响。
        let boxHeight: CGFloat
        /// `.subheadline` 这类文字样式自带比字体本身更大的行距（15pt 字的行距是 20pt），
        /// 普通系统字体没有，靠行间距补齐。
        let lineSpacing: CGFloat
    }

    static func metrics(fontSize: CGFloat) -> Metrics? {
        metricsByFontSize.withLock { $0[fontSize] }
    }

    /// 与 `.subheadline` 在当前字号档位下的大小一致。还没量过这个字号的排版参数时，
    /// 排到主线程稍后再量（见 `measure`），这期间卡片按原来的 `Text` 显示。
    @MainActor
    static func fontSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let size: CGFloat
        if let cached = fontSizes[dynamicTypeSize] {
            size = cached
        } else {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            size = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize
            fontSizes[dynamicTypeSize] = size
        }
        if metrics(fontSize: size) == nil, scheduledMeasurements.insert(dynamicTypeSize).inserted {
            // 这里可能正处在 SwiftUI 的界面更新里，测量要另起一个 SwiftUI 视图，不能嵌套进来。
            DispatchQueue.main.async { measure(dynamicTypeSize) }
        }
        return size
    }

    /// 让 SwiftUI 自己量出一行、两行标题的高度，换算成预排版要用的行间距。
    /// 必须在 SwiftUI 界面更新之外调用。
    @MainActor
    static func measure(_ dynamicTypeSize: DynamicTypeSize) {
        let size = fontSize(for: dynamicTypeSize)
        if metrics(fontSize: size) == nil {
            func swiftUIHeight(_ text: String) -> CGFloat {
                UIHostingController(rootView: Text(text).font(.subheadline.weight(.semibold))
                    .environment(\.dynamicTypeSize, dynamicTypeSize))
                    .sizeThatFits(in: CGSize(width: 1_000, height: 1_000)).height
            }
            func drawnHeight(_ text: String) -> CGFloat {
                (text as NSString).boundingRect(
                    with: CGSize(width: 1_000, height: 1_000), options: [.usesLineFragmentOrigin],
                    attributes: attributes(fontSize: size, lineSpacing: 0), context: nil
                ).height
            }
            let oneLine = swiftUIHeight("国"), twoLines = swiftUIHeight("国\n国")
            let lineSpacing = (twoLines - oneLine) - (drawnHeight("国\n国") - drawnHeight("国"))
            let metrics = Metrics(boxHeight: twoLines, lineSpacing: max(0, lineSpacing))
            metricsByFontSize.withLock { $0[size] = metrics }
        }
    }

    static func cached(_ key: Key) -> UIImage? {
        storage.object(forKey: key.cacheKey)
    }

    /// 在 App 启动完成、任何 SwiftUI 界面更新之前调用一次。
    ///
    /// 系统排版组件第一次被使用时会做类初始化，其中会写入系统默认设置并发出通知；
    /// SwiftUI 的 `@AppStorage` 收到通知要拿 SwiftUI 的全局锁。如果这次初始化发生在
    /// 后台排版线程上，而主线程正持有那把锁、同时也在等同一个组件初始化完，两边就会
    /// 互相等待（真机上出现过启动卡死被系统强制结束）。先在主线程上完整排一遍示例标题，
    /// 让这些组件都初始化好，后台再用就不会触发。
    /// 同时量好当前文字档位的排版参数。
    @MainActor
    static func warmUp(dynamicTypeSize: DynamicTypeSize) {
        guard !isReady.load(ordering: .acquiring) else { return }
        measure(dynamicTypeSize)
        let sample = "【示例】中文标题 English Title 用来触发换行与第二行末尾截断的一段足够长的示例文字"
        if let key = Key(title: sample, width: 170, fontSize: fontSize(for: dynamicTypeSize), scale: 3) {
            _ = render(key)
        }
        isReady.store(true, ordering: .releasing)
    }

    /// 含 emoji 的标题不预排版：文字图是模板图，只保留形状、统一染成文字颜色，
    /// 彩色 emoji 会变成一块实心剪影。
    static func supports(_ title: String) -> Bool {
        !title.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000) }
    }

    /// 不能预排版（含 emoji）的标题交给 `UILabel` 显示时用的文字：每行行高固定为两行框的一半。
    ///
    /// 彩色 emoji 的字形比汉字高，按自然行高排版时含 emoji 的那一行会被撑高，两行超出
    /// 标题框。固定行高后两行正好填满标题框，和预排版的标题图对齐。
    static func fixedLineHeightTitle(_ title: String, fontSize: CGFloat, metrics: Metrics) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        let lineHeight = metrics.boxHeight / 2
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineBreakStrategy = .standard
        return NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ])
    }

    /// 取缓存；没有就在当前线程（主线程）排一次并存进缓存。预热完成前返回 nil。
    @MainActor
    static func image(for key: Key) -> UIImage? {
        if let cached = cached(key) { return cached }
        guard isReady.load(ordering: .acquiring), let image = render(key) else { return nil }
        storage.setObject(image, forKey: key.cacheKey, cost: cost(of: image, scale: key.scale))
        return image
    }

    /// 在后台排版并缓存；已缓存或正在排版的标题直接跳过。预热完成前不做。
    static func prepare(_ key: Key) {
        guard isReady.load(ordering: .acquiring), supports(key.title), cached(key) == nil,
              pending.withLock({ $0.insert(key).inserted }) else { return }
        queue.async {
            defer { _ = pending.withLock { $0.remove(key) } }
            // A visible card may have rendered this title while this work waited
            // behind other titles. Reuse that result instead of drawing it twice.
            guard cached(key) == nil else { return }
            if let image = render(key) {
                storage.setObject(image, forKey: key.cacheKey, cost: cost(of: image, scale: key.scale))
            }
        }
    }

    // MARK: 实现

    // Titles are needed by imminent visible cells. Utility priority can leave
    // prefetch behind scrolling work and force the same layout onto the main thread.
    private static let queue = DispatchQueue(label: "neobili.prepared-title", qos: .userInitiated)
    private static let pending = Mutex<Set<Key>>([])
    private static let isReady = Atomic<Bool>(false)
    private static let metricsByFontSize = Mutex<[CGFloat: Metrics]>([:])
    @MainActor private static var fontSizes: [DynamicTypeSize: CGFloat] = [:]
    @MainActor private static var scheduledMeasurements = Set<DynamicTypeSize>()
    /// 一张两行标题图约 270KB（RGBA）。上限覆盖屏幕上和即将出现的标题即可。
    nonisolated(unsafe) private static let storage: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 20 * 1_024 * 1_024
        return cache
    }()

    private static func cost(of image: UIImage, scale: CGFloat) -> Int {
        Int(image.size.width * image.size.height * scale * scale * 4)
    }

    private static func attributes(fontSize: CGFloat, lineSpacing: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = .standard
        paragraph.hyphenationFactor = 0
        return [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
    }

    private static func render(_ key: Key) -> UIImage? {
        guard let metrics = metrics(fontSize: key.fontSize) else { return nil }
        let size = CGSize(width: key.width, height: metrics.boxHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = key.scale
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // 画框正好两行高：放不下的内容在第二行末尾截断成省略号，和 lineLimit(2) 一致。
            (key.title as NSString).draw(
                with: CGRect(origin: .zero, size: size),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes(fontSize: key.fontSize, lineSpacing: metrics.lineSpacing),
                context: nil
            )
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

private extension PreparedTitle.Key {
    var cacheKey: NSString { "\(pixelWidth)|\(fontSize)|\(scale)|\(title)" as NSString }
}

/// 首页卡片的标题：显示预排好的文字图（没命中缓存就当场排一次）。含 emoji 的标题、
/// 或这个字号的排版参数还没量好时，用普通 `Text`。
struct PreparedCardTitle: View {
    let title: String
    /// 标题可用的宽度（点）。
    let width: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let fontSize = PreparedTitle.fontSize(for: dynamicTypeSize)
        if let metrics = PreparedTitle.metrics(fontSize: fontSize),
           PreparedTitle.supports(title),
           let key = PreparedTitle.Key(title: title, width: width, fontSize: fontSize, scale: displayScale),
           let image = PreparedTitle.image(for: key) {
            Image(uiImage: image)
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: metrics.boxHeight, alignment: .topLeading)
                .accessibilityLabel(title)
        } else {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.primary)
                // emoji 会把所在行撑高：顶端对齐，多出的高度只往下延伸，不会压到上方的封面。
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: PreparedTitle.metrics(fontSize: fontSize)?.boxHeight, alignment: .topLeading)
        }
    }
}
