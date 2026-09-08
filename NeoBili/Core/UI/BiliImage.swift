import SwiftUI

/// Reserves a caller-selected aspect ratio, then fills that exact box with a
/// cropped, cached image. Search results keep the conventional 16:9 default;
/// the recommendation grid opts into the official client's taller 4:3 cards.
struct CoverThumbnail: View {
    let url: URL?
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            BiliImage(url: url)
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

    var body: some View {
        ZStack(alignment: .bottom) {
            CoverThumbnail(url: url, aspectRatio: aspectRatio)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.08), location: 0.4),
                            .init(color: .black.opacity(0.45), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 46)
                }

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
            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .clipShape(shape)
    }
}

/// In-memory image cache. Bilibili's image CDN (hdslb.com) is hotlink-protected
/// on some resources, so every request needs the same Referer/User-Agent as the
/// rest of the app - plain `AsyncImage` can't attach those headers.
///
/// 容量按张数封顶；满了以后逐出**最旧**的条目而不是整罐清空——整罐清空会让
/// 回滚列表时所有封面同时重新下载。系统发出内存警告时清空位图（在途下载保留，
/// 结果照常入缓存），先把内存让给前台，正在显示的单元格也不会因此变成裂图。
actor BiliImageCache {
    static let shared = BiliImageCache()

    private struct Entry {
        let image: UIImage
        let savedAt: Date
    }

    /// 存 `UIImage` 而不是 SwiftUI 的 `Image`：图片查看器要拿原图去保存和分享，
    /// `Image` 取不回底层位图。展示端再包一层 `Image(uiImage:)` 就是了。
    private var storage: [URL: Entry] = [:]
    /// 同一地址正在进行的下载。列表快速滚动时，同一个封面（同一 UP 头像）
    /// 会同时出现在多张卡片上，这里保证只发一次请求。
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    /// 观察者令牌只在 init 注册、deinit 注销，中间不被任何隔离域读写；
    /// NotificationCenter 返回的协议类型不是 Sendable，所以按非隔离存储处理。
    nonisolated(unsafe) private var memoryPressureObserver: (any NSObjectProtocol)?

    private init() {
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { await self?.handleMemoryPressure() }
        }
    }

    deinit {
        if let memoryPressureObserver {
            NotificationCenter.default.removeObserver(memoryPressureObserver)
        }
    }

    /// 系统内存告急时丢掉全部位图。在途下载不打断：取消会让正在等结果的
    /// 单元格直接显示失败态，而让下载跑完只是晚一点把图放回（此时已清空的）缓存。
    private func handleMemoryPressure() {
        storage.removeAll()
    }

    func cachedImage(for url: URL) -> UIImage? {
        storage[url]?.image
    }

    func insert(_ image: UIImage, for url: URL) {
        if storage.count >= Self.capacity {
            evictOldest()
        }
        storage[url] = Entry(image: image, savedAt: Date())
    }

    /// 命中缓存直接返回；否则并入同一地址的在途下载（没有就发起一次），
    /// 下载成功后自动入缓存。调用方取消自己的任务不影响共享下载。
    func image(
        for url: URL,
        downloader: @escaping @Sendable () async throws -> UIImage
    ) async throws -> UIImage {
        if let cached = storage[url]?.image { return cached }
        if let existing = inFlight[url] {
            return try await existing.value
        }
        let task = Task { try await downloader() }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        insert(image, for: url)
        return image
    }

    private func evictOldest() {
        let oldestFirst = storage.sorted { $0.value.savedAt < $1.value.savedAt }
        // 一次淘汰一小批，避免连续插入时每次插入都触发整罐排序。
        let target = Self.capacity - Self.evictionBatch
        for (url, _) in oldestFirst {
            guard storage.count > target else { break }
            storage[url] = nil
        }
    }

    /// 缓存张数上限。与旧实现的量级一致，只是满了以后改成逐出最旧条目。
    private static let capacity = 300
    private static let evictionBatch = 30
}

/// 带 B 站必需请求头的取图。命中缓存直接返回，不发请求。
enum BiliImageLoader {
    static func load(_ url: URL) async throws -> UIImage {
        try await BiliImageCache.shared.image(for: url) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else { throw BiliAPIError.invalidURL }
            return image
        }
    }
}

/// Drop-in replacement for `AsyncImage` that sends Bilibili's required headers
/// and caches decoded images in memory so re-appearing cells (scroll up/down)
/// don't re-fetch.
struct BiliImage: View {
    let url: URL?
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
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
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        failed = false
        guard let url else {
            failed = true
            return
        }
        do {
            let loaded = try await BiliImageLoader.load(url)
            if !Task.isCancelled { image = Image(uiImage: loaded) }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
