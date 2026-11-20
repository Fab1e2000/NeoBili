import Foundation

public struct OfflineVideo: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(bvid):\(cid)" }
    public var bvid: String
    public var cid: Int
    public var aid: Int
    public var title: String
    public var partTitle: String
    public var author: String
    public var cover: URL?
    public var duration: Double
    public var groupID: String
    public var groupTitle: String
    public var order: Int

    public init(bvid: String, cid: Int, aid: Int, title: String, partTitle: String, author: String,
                cover: URL?, duration: Double, groupID: String, groupTitle: String, order: Int) {
        self.bvid = bvid; self.cid = cid; self.aid = aid; self.title = title; self.partTitle = partTitle
        self.author = author; self.cover = cover; self.duration = duration
        self.groupID = groupID; self.groupTitle = groupTitle; self.order = order
    }

    public var displayTitle: String { partTitle.isEmpty ? title : partTitle }
}

public enum OfflineCacheState: String, Codable, Sendable {
    case queued, preparing, waitingForNetwork, downloading, paused, accountPaused, failed, completed
    public var title: String {
        switch self {
        case .queued: String(localized: "等待下载")
        case .preparing: String(localized: "准备缓存")
        case .waitingForNetwork: String(localized: "等待网络")
        case .downloading: String(localized: "下载中")
        case .paused: String(localized: "已暂停")
        case .accountPaused: String(localized: "账号已变更，请确认继续")
        case .failed: String(localized: "下载失败")
        case .completed: String(localized: "已缓存")
        }
    }
    public var canSchedule: Bool { [.queued, .preparing, .waitingForNetwork, .downloading].contains(self) }
}

public struct OfflineResource: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case video, audio, cover, danmaku, subtitle }
    public var id: String
    public var kind: Kind
    public var url: URL
    public var filename: String
    public var language: String?
    public var title: String?
    public var expectedBytes: Int64
    public var receivedBytes: Int64 = 0
    public var isComplete = false
    public var resumeData: Data?
    public var transferID = UUID()

    public init(id: String, kind: Kind, url: URL, filename: String, expectedBytes: Int64 = 0,
                language: String? = nil, title: String? = nil) {
        self.id = id; self.kind = kind; self.url = url; self.filename = filename
        self.expectedBytes = expectedBytes; self.language = language; self.title = title
    }
}

public struct OfflineCacheEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { video.id }
    public var video: OfflineVideo
    public var generation: UUID
    public var quality: Int
    public var audioQuality: Int?
    public var state: OfflineCacheState
    public var resources: [OfflineResource]
    public var allowsCellular = false
    public var accountID: String?
    public var message: String?
    public var createdAt: Date
    public var width: Int?
    public var height: Int?

    public init(video: OfflineVideo, quality: Int, accountID: String?, generation: UUID = UUID()) {
        self.video = video; self.quality = quality; self.accountID = accountID; self.generation = generation
        state = .queued; resources = []; createdAt = Date()
    }
    public func matches(videoID: String, quality: Int) -> Bool {
        id == videoID && self.quality == quality
    }

    public var receivedBytes: Int64 { resources.reduce(0) { $0 + $1.receivedBytes } }
    public var expectedBytes: Int64 { resources.reduce(0) { $0 + max($1.expectedBytes, $1.receivedBytes) } }
    public var progress: Double? {
        guard !resources.isEmpty, resources.allSatisfy({ $0.isComplete || $0.expectedBytes > 0 }), expectedBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(expectedBytes))
    }
}

public struct OfflineCacheSnapshot: Sendable {
    public var completed: [OfflineCacheEntry] = []
    public var tasks: [OfflineCacheEntry] = []
    public var coverURLs: [UUID: URL] = [:]
    public var speeds: [String: Double] = [:]
    public var availableBytes: Int64 = 0
    public var error: String?
    public var occupiedBytes: Int64 { (completed + tasks).reduce(0) { $0 + $1.receivedBytes } }
    public init() {}
}

public struct OfflineSubtitleCue: Codable, Hashable, Sendable {
    public var from: Double
    public var to: Double
    public var content: String
    public init(from: Double, to: Double, content: String) { self.from = from; self.to = to; self.content = content }
}

public struct OfflineSubtitleTrack: Sendable, Identifiable {
    public var id: String
    public var language: String
    public var title: String
    public var cues: [OfflineSubtitleCue]
    public init(id: String, language: String, title: String, cues: [OfflineSubtitleCue]) {
        self.id = id; self.language = language; self.title = title; self.cues = cues
    }
    public func text(at time: Double) -> String {
        cues.filter { $0.from <= time && time < $0.to }.map(\.content).joined(separator: "\n")
    }
    public static func decode(_ data: Data) throws -> [OfflineSubtitleCue] {
        struct File: Decodable { let body: [OfflineSubtitleCue] }
        let cues = try JSONDecoder().decode(File.self, from: data).body
        guard cues.allSatisfy({ $0.from.isFinite && $0.to.isFinite && $0.from >= 0 && $0.to >= $0.from }) else {
            throw OfflineCacheError.invalidResource
        }
        return cues.sorted { $0.from < $1.from }
    }
}

public struct OfflinePlaybackDescriptor: Sendable {
    public var leaseID: UUID
    public var entry: OfflineCacheEntry
    public var videoURLs: [URL]
    public var audioURL: URL?
    public var coverURL: URL?
    public var danmaku: [DanmakuItem]
    public var subtitles: [OfflineSubtitleTrack]
    public init(leaseID: UUID, entry: OfflineCacheEntry, videoURLs: [URL], audioURL: URL?, coverURL: URL?,
                danmaku: [DanmakuItem], subtitles: [OfflineSubtitleTrack]) {
        self.leaseID = leaseID; self.entry = entry; self.videoURLs = videoURLs; self.audioURL = audioURL
        self.coverURL = coverURL; self.danmaku = danmaku; self.subtitles = subtitles
    }
}

public enum OfflineCacheError: LocalizedError {
    case unavailableQuality(Int), invalidResource, missingFile, storageFull, unconfigured, partialPlayback
    public var errorDescription: String? {
        switch self {
        case .unavailableQuality(let quality): String(localized: "未取得\(PlaybackQuality.videoTitle(quality))资源，请重新选择缓存画质")
        case .invalidResource: String(localized: "缓存资源不完整，请重试")
        case .missingFile: String(localized: "缓存文件缺失，请重新缓存")
        case .storageFull: String(localized: "手机空间不足，请清理后继续")
        case .unconfigured: String(localized: "缓存服务暂不可用")
        case .partialPlayback: String(localized: "服务器只提供了视频片段，请确认账号权限后重试")
        }
    }
}
