import Foundation
import NeoBiliDomain

struct OfflinePreparedResources: Sendable {
    var resources: [OfflineResource]
    var audioQuality: Int?
    var width: Int?
    var height: Int?
    var chapters: [VideoChapter] = []
}

enum OfflineCachePreparation {
    static func prepare(_ entry: OfflineCacheEntry, client: APIClient, identity: DeviceIdentity) async throws -> OfflinePreparedResources {
        let sessionID = identity.loginSessionID
        async let playback = BiliAPI.playURL(bvid: entry.video.bvid, cid: entry.video.cid,
            quality: entry.quality, client: client, identity: identity)
        async let info = BiliAPI.playerVideoInfo(bvid: entry.video.bvid, cid: entry.video.cid,
            client: client, expectedSessionID: sessionID)
        let (payload, playerInfo) = try await (playback, info)
        guard sessionID == identity.loginSessionID else { throw CancellationError() }
        let seconds = payload.dash.map { Double($0.duration) }
            ?? payload.durl.map { Double($0.reduce(0) { $0 + ($1.length ?? 0) }) / 1_000 } ?? 0
        if seconds > 0, entry.video.duration > seconds + 1 { throw OfflineCacheError.partialPlayback }
        var result = try mediaResources(payload, quality: entry.quality, audioQuality: entry.audioQuality ?? 0)
        result.chapters = playerInfo.chapters
        if let cover = entry.video.cover {
            result.resources.append(.init(id: "cover", kind: .cover, url: cover, filename: "cover.image"))
        }
        result.resources.append(.init(id: "danmaku", kind: .danmaku,
            url: URL(string: "https://api.bilibili.com/x/v1/dm/list.so?oid=\(entry.video.cid)")!, filename: "danmaku.xml"))
        guard let subtitle = playerInfo.subtitle else { throw OfflineCacheError.invalidResource }
        for track in subtitle.subtitles {
            guard let url = URL.biliSecure(track.subtitleURL) else { throw OfflineCacheError.invalidResource }
            result.resources.append(.init(id: "subtitle-\(track.lan)", kind: .subtitle, url: url,
                filename: "subtitle-\(UUID().uuidString).json", language: track.lan, title: track.lanDoc))
        }
        return result
    }

    static func mediaResources(_ payload: PlayURLData, quality: Int, audioQuality: Int) throws -> OfflinePreparedResources {
        guard payload.hasVideoStream(quality: quality) else { throw OfflineCacheError.unavailableQuality(quality) }
        var result = OfflinePreparedResources(resources: [])
        if let dash = payload.dash, let video = dash.video.filter({ $0.id == quality }).sorted(by: {
            let left = codecRank($0.codecs), right = codecRank($1.codecs)
            if left != right { return left < right }
            return $0.bandwidth > $1.bandwidth
        }).first {
            guard let url = URL.biliSecure(video.baseUrl) else { throw OfflineCacheError.invalidResource }
            result.resources = [.init(id: "video-0", kind: .video, url: url, filename: "video-0.m4s")]
            result.width = video.width; result.height = video.height
            let audio = dash.allAudio.first(where: { $0.id == audioQuality }) ?? dash.allAudio.max {
                PlaybackQuality.audioRank($0.id) < PlaybackQuality.audioRank($1.id)
            }
            if let audio {
                guard let url = URL.biliSecure(audio.baseUrl) else { throw OfflineCacheError.invalidResource }
                result.audioQuality = audio.id
                result.resources.append(.init(id: "audio", kind: .audio, url: url, filename: "audio.m4s"))
            }
        } else if let parts = payload.durl, !parts.isEmpty, payload.quality == quality {
            result.resources = try parts.enumerated().map { index, part in
                guard let url = URL.biliSecure(part.url) else { throw OfflineCacheError.invalidResource }
                return .init(id: "video-\(index)", kind: .video, url: url, filename: "video-\(index).mp4",
                             expectedBytes: Int64(part.size ?? 0))
            }
        } else { throw OfflineCacheError.unavailableQuality(quality) }
        return result
    }

    private static func codecRank(_ codec: String) -> Int {
        ["avc", "hvc", "hev", "av01"].firstIndex { codec.lowercased().hasPrefix($0) } ?? 4
    }
}
