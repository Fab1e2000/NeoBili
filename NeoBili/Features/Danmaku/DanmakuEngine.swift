import UIKit

/// 弹幕渲染引擎。
///
/// 渲染路径刻意全部留在 CALayer 层面：每条弹幕预渲染成一张带黑描边的位图
/// 交给 `CALayer.contents`，CADisplayLink 只更新活动图层的 `position`——
/// 合成器直接消费 transform，不触发任何布局或 SwiftUI 重算，滚动期
/// 主线程开销只有每帧几次位置赋值。位图按「字号+颜色+文本」缓存，同文本
/// 弹幕（刷屏场景）零重复渲染成本。
///
/// 两种时间轴：
/// - `.video`：由 `update(currentTime:)` 驱动注入，暂停冻结，seek 由控制器清场重排；
/// - `.live`：到达即从右缘进入，不依赖任何播放时间。
///
/// 展示规则对齐 PiliPlus（canvas_danmaku）：滚动时长 7s 穿越全屏、
/// 静态停留 4s、显示区域默认半屏、轨道防重叠含追及判定、找不到轨道就丢弃。
final class DanmakuEngine: UIView {
    enum Mode { case video, live }

    var mode: Mode = .video
    var coloredEnabled = true
    private var blockTop = false
    private var blockBottom = false

    func applyAppearance(fontSize: CGFloat, opacity: Double, blockTop: Bool, blockBottom: Bool) {
        let size = min(40, max(8, fontSize.isFinite ? fontSize : 15))
        if self.fontSize != size || self.blockTop != blockTop || self.blockBottom != blockBottom {
            clear(keepTimelineAt: max(0, injectedThrough))
            self.fontSize = size
            self.blockTop = blockTop
            self.blockBottom = blockBottom
            setNeedsLayout()
        }
        alpha = min(1, max(0.1, opacity.isFinite ? opacity : 1))
    }
    /// 弹幕铺满的高度比例；0.5 即上半屏（B 站与 PiliPlus 的默认值）。
    var area: CGFloat = 0.5
    var scrollDuration: TimeInterval = 7
    var staticDuration: TimeInterval = 4
    var fontSize: CGFloat = 15
    private(set) var isTimelinePaused = false
    /// 画面收起成标题条时置位：不注入、不推进、不启动逐帧循环。
    var isSuppressed = false { didSet {
        if isSuppressed { stopTicking() } else if activeCount > 0 { startTickingIfNeeded() }
    } }

    private var rowHeight: CGFloat { Self.rowHeight(for: fontSize) }
    private static func rowHeight(for fontSize: CGFloat) -> CGFloat { ceil(fontSize * 1.6) }

    // MARK: 视频时间轴状态

    private var items: [DanmakuItem] = []
    private var cursorIndex = 0
    private var injectedThrough = -1.0

    // MARK: 活动图层

    private struct ScrollItem {
        let layer: CALayer
        let width: CGFloat
        let speed: CGFloat
        var x: CGFloat
    }
    private struct StaticItem {
        let layer: CALayer
        var remaining: TimeInterval
    }
    private var scrollTracks: [[ScrollItem]] = []
    private var staticTracks: [StaticItem?] = []
    private var displayLink: CADisplayLink?
    private var lastTick: TimeInterval = 0

    /// 活动图层硬上限：防御异常刷屏把合成器压垮，超出的直接丢弃。
    private static let maximumActiveLayers = 90
    private var activeCount = 0

    private let bitmapCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    private static let bitmapScaleLimit: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clearsContextBeforeDrawing = false
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    // 刻意不写 deinit：CADisplayLink 强持有 target 形成的环由「离开窗口即停表」
    // 打破（DanmakuView.dismantle 先 removeFromSuperview，必然触发 didMoveToWindow）；
    // Swift 6 的 deinit 是 nonisolated 的，摸不到本类的主线程状态。

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopTicking() } else { startTickingIfNeeded() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 画布尺寸变化（内联/全屏切换、旋转）后轨道数失效，按新尺寸重建。
        rebuildTracks()
    }

    // MARK: - 时间轴注入（视频）

    func prepare(items: [DanmakuItem]) {
        self.items = items.sorted { $0.time < $1.time }
        clear(keepTimelineAt: 0)
    }

    func update(currentTime: TimeInterval) {
        guard mode == .video, !isTimelinePaused, !isSuppressed else { return }
        guard currentTime >= injectedThrough else { return }
        while cursorIndex < items.count, items[cursorIndex].time <= currentTime {
            let item = items[cursorIndex]
            cursorIndex += 1
            present(item)
        }
        injectedThrough = currentTime
    }

    func seek(to time: TimeInterval) {
        guard mode == .video else { return }
        clear(keepTimelineAt: time)
    }

    /// 清空画面并重置注入游标；`keepTimelineAt` 为 seek 后的新位置。
    func clear(keepTimelineAt time: TimeInterval) {
        for sublayer in self.layer.sublayers ?? [] { sublayer.removeFromSuperlayer() }
        scrollTracks = scrollTracks.map { _ in [] }
        staticTracks = staticTracks.map { _ in nil }
        activeCount = 0
        stopTicking()
        injectedThrough = time
        cursorIndex = items.firstIndex { $0.time >= time } ?? items.count
    }

    func setTimelinePaused(_ paused: Bool) {
        guard isTimelinePaused != paused else { return }
        isTimelinePaused = paused
        if paused {
            // 立刻停表：已经上屏的弹幕整屏冻结（含静态到期），恢复时从
            // 新的 tick 重新起算，不跳帧。
            stopTicking()
        } else {
            startTickingIfNeeded()
        }
    }

    // MARK: - 实时注入（直播）

    func enqueue(text: String, color: UInt32) {
        guard mode == .live, !isSuppressed else { return }
        present(DanmakuItem(time: 0, text: text, mode: 1, color: color))
    }

    // MARK: - 自己发送的弹幕

    /// 发送成功后立即上屏，不等时间轴走到它。
    func presentImmediately(_ item: DanmakuItem) {
        guard !isSuppressed else { return }
        present(item)
    }

    // MARK: - 轨道分配与摆放

    private var scrollTrackCount: Int {
        max(1, Int(bounds.height * max(0.1, min(area, 1)) / rowHeight))
    }

    private func rebuildTracks() {
        let scroll = scrollTrackCount
        if scrollTracks.count < scroll {
            scrollTracks.append(contentsOf: Array(repeating: [], count: scroll - scrollTracks.count))
        } else if scrollTracks.count > scroll {
            for track in scrollTracks.dropFirst(scroll) {
                for item in track { item.layer.removeFromSuperlayer(); activeCount -= 1 }
            }
            scrollTracks.removeLast(scrollTracks.count - scroll)
        }
        let staticCount = max(1, Int(bounds.height / rowHeight))
        if staticTracks.count != staticCount {
            resizeTracked(&staticTracks, to: staticCount) { item in
                item.layer.removeFromSuperlayer()
                activeCount -= 1
            }
        }
    }

    /// 轨道数随画布尺寸变化。收缩时保留仍有效的槽位、把被裁掉的活动
    /// 图层移除并同步计数——直接整表置 nil 会留下冻结的残影和虚高的
    /// activeCount，最终提前触发并发上限丢弹幕。
    private func resizeTracked<T>(_ array: inout [T?], to count: Int, removing: (T) -> Void) {
        if array.count < count {
            array.append(contentsOf: Array(repeating: nil, count: count - array.count))
            return
        }
        for index in count..<array.count {
            if let item = array[index] { removing(item) }
        }
        array.removeLast(array.count - count)
    }

    private func present(_ item: DanmakuItem) {
        if !item.isScroll && (item.isTop ? blockTop : blockBottom) { return }
        guard bounds.width > 10, activeCount < Self.maximumActiveLayers else { return }
        rebuildTracks()
        guard let layer = Self.bitmap(for: item.text, color: coloredEnabled ? item.color : 0xFFFFFF, fontSize: fontSize,
                                      framed: item.isSelf, cache: bitmapCache,
                                      scale: min(window?.screen.scale ?? traitCollection.displayScale,
                                                 Self.bitmapScaleLimit)) else { return }
        let width = layer.bounds.width
        if item.isScroll {
            place(scroll: item, layer: layer, width: width)
        } else {
            place(static: item, layer: layer, width: width)
        }
    }

    /// 滚动弹幕：同轨道前一条右缘必须已让出右入口，且窄的前条不能被宽的新条追尾
    /// （PiliPlus _scrollCanAddToTrack 的两条判定）。找不到轨道就丢弃。
    private func place(scroll item: DanmakuItem, layer: CALayer, width: CGFloat) {
        for index in 0..<scrollTracks.count {
            if let previous = scrollTracks[index].last {
                let previousRight = previous.x + previous.width
                guard previousRight <= bounds.width else { continue }
                let nextSpeed = (bounds.width + width) / CGFloat(max(scrollDuration, 1))
                if nextSpeed > previous.speed {
                    let catchUpTime = (bounds.width - previousRight) / (nextSpeed - previous.speed)
                    let exitTime = previousRight / previous.speed
                    if catchUpTime < exitTime { continue }
                }
            }
            scrollTracks[index].append(ScrollItem(
                layer: layer, width: width,
                speed: (bounds.width + width) / CGFloat(max(scrollDuration, 1)),
                x: bounds.width
            ))
            layer.position = CGPoint(x: bounds.width + width / 2, y: rowHeight / 2 + rowHeight * CGFloat(index))
            install(layer)
            return
        }
    }

    /// 底部弹幕从最靠下的轨道往上排，顶部弹幕从最靠上的轨道往下排（PiliPlus 的反向遍历）。
    private func place(static item: DanmakuItem, layer: CALayer, width: CGFloat) {
        let trackIndices: [Int] = item.isTop
            ? Array(0..<staticTracks.count)
            : Array((0..<staticTracks.count).reversed())
        for index in trackIndices {
            guard staticTracks[index] == nil else { continue }
            staticTracks[index] = StaticItem(layer: layer, remaining: max(staticDuration, 1))
            layer.position = CGPoint(x: (bounds.width - width) / 2 + width / 2,
                                     y: rowHeight / 2 + rowHeight * CGFloat(index))
            install(layer)
            return
        }
    }

    private func install(_ layer: CALayer) {
        if layer.superlayer == nil { self.layer.addSublayer(layer) }
        activeCount += 1
        startTickingIfNeeded()
    }

    // MARK: - 逐帧推进

    private func startTickingIfNeeded() {
        guard window != nil, displayLink == nil, activeCount > 0,
              !isSuppressed,
              !(mode == .video && isTimelinePaused) else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Text motion does not need to drive a ProMotion display at 120 Hz.
        // Let the system lower the rate when energy constraints require it.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTick = CACurrentMediaTime()
    }

    private func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        var dt = link.timestamp - lastTick
        lastTick = link.timestamp
        // 后台/暂停恢复后的第一帧可能带巨大间隔，钳制避免整屏弹幕瞬移。
        dt = min(dt, 0.25)

        advance(by: dt)
    }

    func advance(by dt: TimeInterval) {
        guard !isSuppressed, !(mode == .video && isTimelinePaused) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for index in scrollTracks.indices {
            scrollTracks[index] = scrollTracks[index].compactMap { original in
                var item = original
                item.x -= CGFloat(max(0, dt)) * item.speed
                if item.x + item.width <= 0 {
                    item.layer.removeFromSuperlayer()
                    activeCount -= 1
                    return nil
                }
                item.layer.position.x = item.x + item.width / 2
                return item
            }
        }
        for index in staticTracks.indices {
            guard var item = staticTracks[index] else { continue }
            item.remaining -= max(0, dt)
            if item.remaining <= 0 {
                item.layer.removeFromSuperlayer()
                activeCount -= 1
                staticTracks[index] = nil
            } else {
                staticTracks[index] = item
            }
        }
        if activeCount == 0 { stopTicking() }
    }

    // MARK: - 位图渲染

    /// 自己发送的弹幕外框：颜色、线宽与 PiliPlus（canvas_danmaku）一致，左右比文字多留一点空隙。
    private static let selfFrameColor = UIColor.systemGreen
    private static let selfFrameWidth: CGFloat = 1.5
    private static let selfFramePadding: CGFloat = 2

    private static func bitmap(for text: String, color: UInt32, fontSize: CGFloat, framed: Bool,
                               cache: NSCache<NSString, UIImage>, scale: CGFloat) -> CALayer? {
        let key = "\(scale)|\(fontSize)|\(color)|\(framed)|\(text)" as NSString
        if let image = cache.object(forKey: key) {
            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: image.size)
            layer.contents = image.cgImage
            layer.contentsScale = image.scale
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
            return layer
        }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let stroke: CGFloat = 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Self.color(from: color),
            .strokeColor: UIColor.black,
            .strokeWidth: stroke
        ]
        let rawSize = (text as NSString).size(withAttributes: attributes)
        let inset: CGFloat = 2
        let horizontalInset = inset + (framed ? selfFramePadding : 0)
        let size = CGSize(width: ceil(rawSize.width) + horizontalInset * 2, height: ceil(rawSize.height) + inset * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let origin = CGPoint(x: horizontalInset, y: inset)
            // Stroke and fill in separate passes: an attributed-string stroke
            // is centered on the glyph edge and otherwise eats into the stems.
            (text as NSString).draw(at: origin, withAttributes: attributes)
            (text as NSString).draw(at: origin, withAttributes: [
                .font: font, .foregroundColor: Self.color(from: color)
            ])
            if framed {
                let frame = CGRect(origin: .zero, size: size).insetBy(dx: selfFrameWidth / 2, dy: selfFrameWidth / 2)
                selfFrameColor.setStroke()
                let path = UIBezierPath(rect: frame)
                path.lineWidth = selfFrameWidth
                path.stroke()
            }
        }
        let cost = Int(size.width * size.height * scale * scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: image.size)
        layer.contents = image.cgImage
            layer.contentsScale = image.scale
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        return layer
    }

    private static func color(from value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1)
    }
}
