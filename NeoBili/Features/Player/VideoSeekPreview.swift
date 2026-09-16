import SwiftUI

struct VideoPreviewID: Hashable {
    let bvid: String
    let cid: Int
}

/// Bilibili's storyboard tiles; the first two index entries precede tile zero.
/// Matches PiliPlus updatePreviewIndex, including the leading sentinel.
struct VideoStoryboard: Decodable {
    let imgXLen: Int
    let imgYLen: Int
    let imgXSize: Double
    let imgYSize: Double
    let image: [String]
    let index: [Double]

    enum CodingKeys: String, CodingKey {
        case imgXLen = "img_x_len", imgYLen = "img_y_len"
        case imgXSize = "img_x_size", imgYSize = "img_y_size"
        case image, index
    }

    struct Tile: Equatable {
        let url: URL
        let rect: CGRect
    }

    func tile(at seconds: Double) -> Tile? {
        guard seconds.isFinite, !index.isEmpty, imgXLen > 0, imgYLen > 0,
              imgXLen <= 100, imgYLen <= 100,
              imgXSize > 0, imgYSize > 0, !image.isEmpty else { return nil }
        let perImage = imgXLen * imgYLen
        let offset = min(max(0, index.filter { $0 <= seconds }.count - 2), image.count * perImage - 1)
        let raw = image[offset / perImage]
        guard let url = URL(string: raw.hasPrefix("//") ? "https:" + raw : raw.replacingOccurrences(of: "http://", with: "https://")),
              url.scheme == "https" else { return nil }
        let local = offset % perImage
        return Tile(url: url, rect: CGRect(x: Double(local % imgXLen) * imgXSize,
                                          y: Double(local / imgXLen) * imgYSize,
                                          width: imgXSize, height: imgYSize))
    }
}

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
    @ObservationIgnored private var metadataTask: Task<VideoStoryboard, Error>?

    @ObservationIgnored private let metadataLoader: (VideoPreviewID) async throws -> VideoStoryboard
    @ObservationIgnored private let imageLoader: (URL) async throws -> UIImage

    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let retryWait: (Int) async throws -> Void

    init(metadataLoader: @escaping (VideoPreviewID) async throws -> VideoStoryboard = { id in
        try await APIClient.shared.get(
            path: "x/player/videoshot", params: ["bvid": id.bvid, "cid": String(id.cid), "index": "1"],
            additionalHeaders: ["Referer": "https://www.bilibili.com/video/\(id.bvid)"])
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
        await loadSprite(tile.url)
        guard !Task.isCancelled, let position = board.image.firstIndex(where: {
            Self.secureURL($0) == tile.url
        }) else { return }
        for neighbor in [position + 1, position - 1] where board.image.indices.contains(neighbor) {
            if Task.isCancelled { return }
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
        guard let tile = storyboard?.tile(at: seconds),
              let cgImage = sprites[tile.url]?.cgImage?.cropping(to: tile.rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct VideoSeekPreview: View {
    let video: VideoPreviewID
    let seconds: Double
    let store: VideoStoryboardStore

    var body: some View {
        let tile = store.storyboard?.tile(at: seconds)
        VStack(spacing: 4) {
            if let frame = store.frame(at: seconds) {
                Image(uiImage: frame).resizable().scaledToFit()
                    .frame(height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // Do not present a generic picture as if it were a video frame.
                // The timestamp remains useful even if the server has no shots.
                Group {
                    if store.failed || tile.map({ store.failedURLs.contains($0.url) }) == true {
                        VStack(spacing: 3) {
                            Text("暂无预览")
                            Text("稍后拖动重试")
                        }.font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 74)
            }
            Text(PlaybackTime.text(seconds)).font(.caption.monospacedDigit())
        }
        .padding(5)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
        .task(id: video) {
            // A failed preload must not disable previews for the whole session.
            // Cached/in-flight metadata is reused; a later drag can retry failure.
            await store.load(video)
        }
        .task(id: tile?.url) { await store.prepare(at: seconds) }
    }
}

struct VideoScrubPreviewPosition {
    let bounds: Anchor<CGRect>
    let video: VideoPreviewID
    let seconds: Double
    let duration: Double
}

struct VideoScrubPreviewPreference: PreferenceKey {
    static var defaultValue: VideoScrubPreviewPosition? { nil }
    static func reduce(value: inout VideoScrubPreviewPosition?, nextValue: () -> VideoScrubPreviewPosition?) {
        value = nextValue() ?? value
    }
}
