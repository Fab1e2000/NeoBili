import SwiftUI

/// Shared decoded bitmap cache. Both immediate UI reads and async image loads
/// use this single byte budget; evicting a bitmap releases its only cache owner.
actor BiliImageCache {
    static let shared = BiliImageCache()

    private struct Key: Hashable, Sendable {
        let url: URL
        let pixelSize: ImagePixelSize?
    }

    private nonisolated let storage: ImageMemoryCache<Key, UIImage>
    private let requests = ImageRequestPool<Key, UIImage>()
    nonisolated(unsafe) private var memoryPressureObserver: (any NSObjectProtocol)?

    init(maximumBytes: Int = 64 * 1_024 * 1_024, maximumEntries: Int = 300) {
        let storage = ImageMemoryCache<Key, UIImage>(maximumBytes: maximumBytes, maximumEntries: maximumEntries)
        self.storage = storage
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in storage.removeAll() }
    }

    deinit {
        if let memoryPressureObserver { NotificationCenter.default.removeObserver(memoryPressureObserver) }
    }

    var cachedByteCount: Int { storage.cachedByteCount }

    nonisolated func cachedImage(for url: URL, pixelSize: ImagePixelSize? = nil) -> UIImage? {
        storage.value(for: Key(url: url, pixelSize: pixelSize))
    }

    nonisolated func insert(_ image: UIImage, for url: URL, pixelSize: ImagePixelSize? = nil) {
        let byteCount = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        // Oversized originals are returned to callers without evicting the feed.
        storage.insert(image, for: Key(url: url, pixelSize: pixelSize), cost: byteCount)
    }

    /// A disappearing cell leaves the shared request immediately. Other visible
    /// cells keep it alive; the last cancellation stops download/queued decode.
    func image(
        for url: URL,
        pixelSize: ImagePixelSize? = nil,
        downloader: @escaping @Sendable () async throws -> UIImage
    ) async throws -> UIImage {
        try Task.checkCancellation()
        if let cached = cachedImage(for: url, pixelSize: pixelSize) { return cached }
        // Explicitly supplied originals (for example preloaded avatars) remain
        // suitable for every smaller presentation of that URL.
        if pixelSize != nil, let original = cachedImage(for: url) { return original }
        return try await requests.value(for: Key(url: url, pixelSize: pixelSize)) { [self] in
            // Another operation may have filled the cache before this pool hop.
            if let cached = cachedImage(for: url, pixelSize: pixelSize) { return cached }
            let image = try await downloader()
            try Task.checkCancellation()
            insert(image, for: url, pixelSize: pixelSize)
            return image
        }
    }
}

/// Different visible sizes still share one HTTP transfer. URLSession retains
/// compressed responses; this pool retains data only during the transfer.
/// 限制同时进行的图片预取数量。
private actor PrefetchGate {
    static let shared = PrefetchGate()
    private static let limit = 6
    private var active = 0

    func tryEnter() -> Bool {
        guard !Task.isCancelled, active < Self.limit else { return false }
        active += 1
        return true
    }

    func leave() { active -= 1 }
}

/// Synchronous access to the same decoded cache used by the loader, so cached
/// images appear in the first frame without a second independent retention cap.
enum BiliImageMemoryCache {
    static func image(for url: URL, pixelSize: ImagePixelSize) -> UIImage? {
        BiliImageCache.shared.cachedImage(for: url, pixelSize: pixelSize)
            ?? BiliImageCache.shared.cachedImage(for: url)
    }

    static func insert(_ image: UIImage, for url: URL, pixelSize: ImagePixelSize) {
        BiliImageCache.shared.insert(image, for: url, pixelSize: pixelSize)
    }
}

enum BiliImageLoader {
    /// The collection owns this handle and cancels it when UIKit drops prefetch.
    @discardableResult
    static func prefetch(_ url: URL?, pointSize: CGSize, scale: CGFloat) -> Task<Void, Never>? {
        guard let url, let pixelSize = ImagePixelSize(points: pointSize, scale: scale),
              BiliImageMemoryCache.image(for: url, pixelSize: pixelSize) == nil else { return nil }
        return Task(priority: .utility) {
            guard await PrefetchGate.shared.tryEnter() else { return }
            _ = try? await load(url, pixelSize: pixelSize)
            await PrefetchGate.shared.leave()
        }
    }

    /// nil requests an original; on-screen cards always supply physical pixels.
    static func load(_ url: URL, pixelSize: ImagePixelSize? = nil,
                     download: @escaping @Sendable (URL) async throws -> Data = ApplicationServices.imageData) async throws -> UIImage {
        try await BiliImageCache.shared.image(for: url, pixelSize: pixelSize) {
            let data = try await download(url)
            try await ImageDecodeGate.shared.enter()
            do {
                try Task.checkCancellation()
                let decoding = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    guard let decoded = ImageDownsampling.decode(data, fitting: pixelSize) else {
                        throw BiliAPIError.invalidURL
                    }
                    return UIImage(cgImage: decoded)
                }
                let image = try await withTaskCancellationHandler {
                    try await decoding.value
                } onCancel: { decoding.cancel() }
                try Task.checkCancellation()
                await ImageDecodeGate.shared.leave()
                return image
            } catch {
                await ImageDecodeGate.shared.leave()
                throw error
            }
        }
    }
}
