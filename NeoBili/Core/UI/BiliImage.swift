import SwiftUI

/// Reserves a caller-selected aspect ratio, then fills that exact box with a
/// cropped, cached image. Search results keep the conventional 16:9 default;
/// the recommendation grid opts into the official client's taller 4:3 cards.
struct CoverThumbnail: View {
    let url: URL?
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            // 封面框的尺寸就是解码目标：不必等图片自己测量，也不会因为占位图和
            // 真图的比例不同而按两个尺寸各解码一次。
            BiliImage(url: url, targetSize: proxy.size)
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

/// Shared cover treatment for every video card. Keeping the metadata overlay
/// here prevents feed and search cards from drifting into different styles.
struct VideoCoverThumbnail: View {
    let url: URL?
    let duration: String
    /// 已经排好版的播放量。推荐流给的是裸数字，走 `playCount` 那个构造器；
    /// 关注页的动态流给的本来就是「1.2万」这样的成品文字，原样传进来。
    let playText: String
    var aspectRatio: CGFloat = 16.0 / 9.0
    var cornerRadius: CGFloat = 6
    /// 下面两个角单独控制。首页卡片的封面下缘紧贴文字区，圆角会在那里
    /// 割出一道缺口，所以传 0；不传就和上面两个角一样。
    var bottomCornerRadius: CGFloat?

    init(
        url: URL?,
        duration: String,
        playText: String,
        aspectRatio: CGFloat = 16.0 / 9.0,
        cornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.url = url
        self.duration = duration
        self.playText = playText
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    init(
        url: URL?,
        duration: String,
        playCount: Int,
        aspectRatio: CGFloat = 16.0 / 9.0,
        cornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.init(
            url: url,
            duration: duration,
            playText: playCount.biliCountText,
            aspectRatio: aspectRatio,
            cornerRadius: cornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: bottomCornerRadius ?? cornerRadius,
            bottomTrailingRadius: bottomCornerRadius ?? cornerRadius,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )
    }

    /// 渐变只贴住封面下缘，下面两个角跟封面一致。
    private var scrimShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: bottomCornerRadius ?? cornerRadius,
            bottomTrailingRadius: bottomCornerRadius ?? cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        // 只裁剪封面图片本身，渐变和文字画在裁剪外面，文字也不加阴影：
        // 裁剪里套着多层内容、以及文字阴影，都会让系统每帧额外做离屏渲染，
        // 一屏十几张卡叠起来会把渲染时间顶到 120Hz 的上限。
        // 文字的可读性改由加深的渐变保证。
        CoverThumbnail(url: url, aspectRatio: aspectRatio)
            .clipShape(shape)
            .overlay(alignment: .bottom) {
                scrimShape
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.2), location: 0.4),
                            .init(color: .black.opacity(0.6), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(height: 52)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    if !playText.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "play.rectangle")
                            Text(playText)
                        }
                    }

                    Spacer(minLength: 0)

                    if !duration.isEmpty {
                        Text(duration)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
    }
}

/// Shared decoded bitmap cache. Its budget is in decoded bytes, so a few large
/// photos cannot silently turn a 300-image limit into several gigabytes.
actor BiliImageCache {
    static let shared = BiliImageCache()

    private struct Key: Hashable {
        let url: URL
        let pixelSize: ImagePixelSize?
    }

    private struct Entry {
        let image: UIImage
        let byteCount: Int
        var lastAccess: UInt64
    }

    private let maximumBytes: Int
    private let maximumEntries: Int
    private var storage: [Key: Entry] = [:]
    private var inFlight: [Key: Task<UIImage, Error>] = [:]
    private var accessSequence: UInt64 = 0
    private(set) var cachedByteCount = 0
    nonisolated(unsafe) private var memoryPressureObserver: (any NSObjectProtocol)?

    init(maximumBytes: Int = 64 * 1_024 * 1_024, maximumEntries: Int = 300) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumEntries = max(1, maximumEntries)
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.handleMemoryPressure() }
        }
    }

    deinit {
        if let memoryPressureObserver { NotificationCenter.default.removeObserver(memoryPressureObserver) }
    }

    private func handleMemoryPressure() {
        storage.removeAll()
        cachedByteCount = 0
    }

    func cachedImage(for url: URL, pixelSize: ImagePixelSize? = nil) -> UIImage? {
        let key = Key(url: url, pixelSize: pixelSize)
        guard var entry = storage[key] else { return nil }
        accessSequence &+= 1
        entry.lastAccess = accessSequence
        storage[key] = entry
        return entry.image
    }

    func insert(_ image: UIImage, for url: URL, pixelSize: ImagePixelSize? = nil) {
        let key = Key(url: url, pixelSize: pixelSize)
        if let replaced = storage.removeValue(forKey: key) { cachedByteCount -= replaced.byteCount }
        let byteCount = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        // Still return oversized images to the caller; retaining them here would
        // immediately evict every feed thumbnail for a single full-size image.
        guard byteCount <= maximumBytes else { return }
        while cachedByteCount + byteCount > maximumBytes || storage.count >= maximumEntries {
            guard let oldest = storage.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            cachedByteCount -= oldest.value.byteCount
            storage[oldest.key] = nil
        }
        accessSequence &+= 1
        storage[key] = Entry(image: image, byteCount: byteCount, lastAccess: accessSequence)
        cachedByteCount += byteCount
    }

    /// Identical URL/size requests share both download and decode. Cancelling a
    /// disappearing cell must not cancel another visible cell's shared request.
    func image(
        for url: URL,
        pixelSize: ImagePixelSize? = nil,
        downloader: @escaping @Sendable () async throws -> UIImage
    ) async throws -> UIImage {
        if let cached = cachedImage(for: url, pixelSize: pixelSize) { return cached }
        // Explicitly supplied originals (for example preloaded avatars) are
        // suitable for every smaller presentation of that URL.
        if pixelSize != nil, let original = cachedImage(for: url) { return original }
        let key = Key(url: url, pixelSize: pixelSize)
        if let existing = inFlight[key] { return try await existing.value }
        let task = Task { try await downloader() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let image = try await task.value
        insert(image, for: url, pixelSize: pixelSize)
        return image
    }
}

/// Different visible sizes still share a single concurrent HTTP transfer. The
/// URLSession HTTP cache retains compressed responses; this actor only keeps
/// transfers while they are in flight, without a second unbounded data cache.
private actor BiliImageDataLoader {
    static let shared = BiliImageDataLoader()
    private var inFlight: [URL: Task<Data, Error>] = [:]

    func data(for url: URL) async throws -> Data {
        if let existing = inFlight[url] { return try await existing.value }
        let task = Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw BiliAPIError.httpStatus(response.statusCode)
            }
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        return try await task.value
    }
}

/// ImageIO 解码并发闸门。快速滚动时被掠过的卡片都会发起解码，一次 fling
/// 可能同时排入几十个大图解码，与 UI 动画抢 CPU；限制并发数让单帧内最多
/// 只有少数解码在跑，其余排队（下载不受影响，那本来就是 I/O 等待）。
private actor DecodeGate {
    static let shared = DecodeGate()
    static let limit = 4
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        if inFlight < Self.limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inFlight -= 1
        }
    }
}

/// 限制同时进行的图片预取数量。
private actor PrefetchGate {
    static let shared = PrefetchGate()
    private static let limit = 6
    private var active = 0

    func tryEnter() -> Bool {
        guard active < Self.limit else { return false }
        active += 1
        return true
    }

    func leave() { active -= 1 }
}

/// 主线程可以同步读取的已解码图片索引，让已加载或已预取的图在视图创建的
/// 第一帧就画出来，不先闪一帧空白。只引用 `BiliImageCache` 里同一批 UIImage，
/// 系统内存紧张时 NSCache 会自行清空。
enum BiliImageMemoryCache {
    nonisolated(unsafe) private static let storage: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()

    static func image(for url: URL, pixelSize: ImagePixelSize) -> UIImage? {
        storage.object(forKey: key(url, pixelSize))
    }

    static func insert(_ image: UIImage, for url: URL, pixelSize: ImagePixelSize) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        storage.setObject(image, forKey: key(url, pixelSize), cost: cost)
    }

    private static func key(_ url: URL, _ pixelSize: ImagePixelSize) -> NSString {
        "\(pixelSize.width)x\(pixelSize.height) \(url.absoluteString)" as NSString
    }
}

enum BiliImageLoader {
    /// 列表预取：在卡片进入屏幕前下载并解码，结果进缓存。尺寸必须和卡片
    /// 显示时请求的一致才能命中；失败不影响之后的正常加载。
    static func prefetch(_ url: URL?, pointSize: CGSize, scale: CGFloat) {
        guard let url, let pixelSize = ImagePixelSize(points: pointSize, scale: scale),
              BiliImageMemoryCache.image(for: url, pixelSize: pixelSize) == nil else { return }
        Task(priority: .utility) {
            // 预取只是锦上添花：同时进行的数量有上限，超出的直接放弃，
            // 等卡片显示时再正常加载，不和屏幕上的图片抢网络。
            guard await PrefetchGate.shared.tryEnter() else { return }
            _ = try? await load(url, pixelSize: pixelSize)
            await PrefetchGate.shared.leave()
        }
    }

    /// nil requests an original; on-screen cards always supply physical pixels.
    static func load(_ url: URL, pixelSize: ImagePixelSize? = nil) async throws -> UIImage {
        let image = try await decoded(url, pixelSize: pixelSize)
        if let pixelSize { BiliImageMemoryCache.insert(image, for: url, pixelSize: pixelSize) }
        return image
    }

    private static func decoded(_ url: URL, pixelSize: ImagePixelSize?) async throws -> UIImage {
        try await BiliImageCache.shared.image(for: url, pixelSize: pixelSize) {
            let data = try await BiliImageDataLoader.shared.data(for: url)
            await DecodeGate.shared.enter()
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    guard let decoded = ImageDownsampling.decode(data, fitting: pixelSize) else {
                        throw BiliAPIError.invalidURL
                    }
                    return UIImage(cgImage: decoded)
                }.value
                await DecodeGate.shared.leave()
                return image
            } catch {
                await DecodeGate.shared.leave()
                throw error
            }
        }
    }
}

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
