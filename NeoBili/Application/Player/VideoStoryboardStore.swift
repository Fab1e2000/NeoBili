import SwiftUI

@MainActor @Observable
final class VideoStoryboardStore {
    var storyboard: VideoStoryboard?
    var failed = false
    private(set) var sprites: [URL: UIImage] = [:]
    private(set) var failedURLs: Set<URL> = []
    private(set) var lastError: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var metadataRetryAfter: TimeInterval = 0
    @ObservationIgnored private var spriteRetryAfter: [URL: TimeInterval] = [:]
    @ObservationIgnored private var video: VideoPreviewID?
    @ObservationIgnored private var order: [URL] = []
    @ObservationIgnored private var requests: [URL: Task<UIImage, Error>] = [:]
    @ObservationIgnored private var cachedFrame: (tile: VideoStoryboard.Tile, image: UIImage)?
    @ObservationIgnored private var metadataTask: Task<VideoStoryboard, Error>?

    @ObservationIgnored private let metadataLoader: (VideoPreviewID) async throws -> VideoStoryboard
    @ObservationIgnored private let imageLoader: (URL) async throws -> UIImage

    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let retryWait: (Int) async throws -> Void

    init(metadataLoader: @escaping (VideoPreviewID) async throws -> VideoStoryboard = { id in
        try await ApplicationServices.live.video.storyboard(bvid: id.bvid, cid: id.cid)
    }, imageLoader: @escaping (URL) async throws -> UIImage = { try await BiliImageLoader.load($0) },
       now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
       retryWait: @escaping (Int) async throws -> Void = { attempt in
           try await Task.sleep(for: .milliseconds(attempt == 0 ? 600 : 1500))
       }) {
        self.metadataLoader = metadataLoader
        self.imageLoader = imageLoader
        self.now = now
        self.retryWait = retryWait
    }

    func load(_ id: VideoPreviewID) async {
        if video == id, storyboard != nil { return }
        if video != id {
            generation = UUID()
            metadataRetryAfter = 0
            spriteRetryAfter.removeAll()
            lastError = nil
            metadataTask?.cancel()
            for request in requests.values { request.cancel() }
            requests.removeAll()
            sprites.removeAll()
            cachedFrame = nil
            order.removeAll()
            failedURLs.removeAll()
            storyboard = nil
            video = id
            metadataTask = nil
        }
        guard metadataTask != nil || now() >= metadataRetryAfter else { return }
        failed = false
        let currentGeneration = generation
        if metadataTask == nil {
            let loader = metadataLoader
            let wait = retryWait
            metadataTask = Task {
                try await Self.retry(wait: wait) {
                    let result = try await loader(id)
                    guard result.tile(at: 0) != nil else { throw PreviewFailure.emptyStoryboard }
                    return result
                }
            }
        }
        guard let task = metadataTask else { return }
        do {
            let result = try await task.value
            guard generation == currentGeneration else { return }
            storyboard = result
            failed = false
            metadataRetryAfter = 0
            lastError = nil
        } catch {
            guard generation == currentGeneration else { return }
            storyboard = nil // Empty results must never become a successful cache entry.
            failed = true
            lastError = String(describing: error)
            metadataRetryAfter = now() + 3
        }
        if generation == currentGeneration { metadataTask = nil }
    }

    /// Tasks belong to the player, so lifting a finger or hiding controls never
    /// cancels a sprite download. Keep at most four decoded sheets (~23 MB).
    func prepare(at seconds: Double) async {
        guard let board = storyboard, let tile = board.tile(at: seconds) else { return }
        let currentGeneration = generation
        await loadSprite(tile.url)
        guard generation == currentGeneration, !Task.isCancelled, let position = board.image.firstIndex(where: {
            Self.secureURL($0) == tile.url
        }) else { return }
        for neighbor in [position + 1, position - 1] where board.image.indices.contains(neighbor) {
            if generation != currentGeneration || Task.isCancelled { return }
            if let url = Self.secureURL(board.image[neighbor]) { await loadSprite(url) }
        }
    }

    private static func secureURL(_ raw: String) -> URL? {
        URL(string: raw.hasPrefix("//") ? "https:" + raw : raw.replacingOccurrences(of: "http://", with: "https://"))
    }

    private func loadSprite(_ url: URL) async {
        if sprites[url] != nil {
            order.removeAll { $0 == url }
            order.append(url)
            return
        }
        guard requests[url] != nil || now() >= (spriteRetryAfter[url] ?? 0) else { return }
        let currentGeneration = generation
        if requests[url] == nil {
            failedURLs.remove(url)
            let loader = imageLoader
            let wait = retryWait
            requests[url] = Task {
                try await Self.retry(wait: wait) {
                    let image = try await loader(url)
                    guard image.cgImage != nil else { throw PreviewFailure.invalidImage }
                    return image
                }
            }
        }
        guard let task = requests[url] else { return }
        do {
            let image = try await task.value
            guard generation == currentGeneration else { return }
            sprites[url] = image
            failedURLs.remove(url)
            spriteRetryAfter[url] = nil
            order.removeAll { $0 == url }
            order.append(url)
            while order.count > 4 { sprites.removeValue(forKey: order.removeFirst()) }
        } catch {
            if generation == currentGeneration {
                failedURLs.insert(url)
                lastError = String(describing: error)
                spriteRetryAfter[url] = now() + 3
            }
        }
        if generation == currentGeneration { requests[url] = nil }
    }

    private enum PreviewFailure: Error { case emptyStoryboard, invalidImage }

    /// One shared request performs at most three attempts. Finger movement cannot
    /// reset this budget; an exhausted request has a three-second cooldown.
    private static func retry<T>(wait: (Int) async throws -> Void,
                                 operation: () async throws -> T) async throws -> T {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do { return try await operation() }
            catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                guard attempt < 2 else { throw error }
                try await wait(attempt)
            }
        }
        throw CancellationError()
    }

    func frame(at seconds: Double) -> UIImage? {
        guard let tile = storyboard?.tile(at: seconds) else { return nil }
        if let cachedFrame, cachedFrame.tile == tile { return cachedFrame.image }
        guard let cgImage = sprites[tile.url]?.cgImage?.cropping(to: tile.rect) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cachedFrame = (tile, image)
        return image
    }
}
