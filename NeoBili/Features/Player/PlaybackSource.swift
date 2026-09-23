import Foundation

struct PlaybackStream: Sendable, Hashable {
    let primary: URL
    let backups: [URL]

    var candidates: [URL] {
        var result = [primary]
        for backup in backups where !result.contains(backup) { result.append(backup) }
        return result
    }
}

/// `audio == nil` is a server-side muxed stream, opened directly. Otherwise
/// the two elementary streams are joined into one `edl://` pseudo-URL that
/// mpv demuxes as a single source — see `PlaybackSourceBuilder.edlURL`.
struct PlaybackSource: Sendable, Hashable {
    let video: PlaybackStream
    let audio: PlaybackStream?
    let duration: TimeInterval

    var candidates: [PlaybackSource] {
        let videos = Array(video.candidates.prefix(2))
        guard let audio else {
            return videos.map {
                PlaybackSource(video: PlaybackStream(primary: $0, backups: []), audio: nil, duration: duration)
            }
        }
        let audios = Array(audio.candidates.prefix(2))
        return videos.flatMap { videoURL in
            audios.map { audioURL in
                PlaybackSource(
                    video: PlaybackStream(primary: videoURL, backups: []),
                    audio: PlaybackStream(primary: audioURL, backups: []),
                    duration: duration
                )
            }
        }
    }
}

enum PlaybackSourceBuilder {
    /// 同一清晰度下的编码偏好：avc1 兼容性最好、硬解最省电，排后面的
    /// （dvh1、av01）通常只有软解或部分机型才有硬解。mpv/FFmpeg 都能解，
    /// 这只是"优先选哪个"，不是能不能播的问题。
    private static let preferredCodecPrefixes = ["avc1", "hvc1", "hev1", "dvh1", "av01"]

    static func makeSource(from payload: PlayURLData, configuration: VideoPlaybackConfiguration) throws -> PlaybackSource {
        if let dash = payload.dash,
           let video = bestVideoStream(dash.video, preferredQuality: configuration.quality),
           let audio = bestAudioStream(dash.allAudio, preferredQuality: configuration.audioQuality),
           let videoStream = makeStream(from: video),
           let audioStream = makeStream(from: audio) {
            return PlaybackSource(video: videoStream, audio: audioStream, duration: TimeInterval(dash.duration))
        }

        // durl（html5，服务端已合并好音视频）只在 DASH 拿不到时才用到。
        if let durl = payload.durl?.first, let stream = makeStream(from: durl) {
            return PlaybackSource(video: stream, audio: nil, duration: TimeInterval(durl.length ?? 0) / 1_000)
        }
        throw PlayerSessionError.invalidSource
    }

    static func bestAudioStream(_ streams: [DashStream], preferredQuality: Int) -> DashStream? {
        let usable = streams.filter { URL(string: $0.baseUrl) != nil }
        if let exact = usable.filter({ $0.id == preferredQuality }).max(by: { $0.bandwidth < $1.bandwidth }) {
            return exact
        }
        let ceiling = preferredQuality == 0 ? Int.max : PlaybackQuality.audioRank(preferredQuality)
        let lower = usable.filter { PlaybackQuality.audioRank($0.id) <= ceiling }
        return (lower.isEmpty ? usable : lower).max {
            let lhs = PlaybackQuality.audioRank($0.id), rhs = PlaybackQuality.audioRank($1.id)
            return lhs == rhs ? $0.bandwidth < $1.bandwidth : lhs < rhs
        }
    }

    static func bestVideoStream(_ streams: [DashStream], preferredQuality: Int) -> DashStream? {
        let usable = streams.filter { URL(string: $0.baseUrl) != nil }
        guard !usable.isEmpty else { return nil }
        let atOrBelow = usable.filter { $0.id <= preferredQuality }
        let targetQuality = atOrBelow.map(\.id).max() ?? usable.map(\.id).min()!
        return usable.filter { $0.id == targetQuality }.min { lhs, rhs in
            let left = codecRank(lhs.codecs)
            let right = codecRank(rhs.codecs)
            if left == right { return lhs.bandwidth > rhs.bandwidth }
            return left < right
        }
    }

    /// mpv 打开两条独立的视频、音频流靠的是这个 EDL 伪协议地址——不是真的文件，
    /// 只是告诉 mpv 的解封装器"把这两个当成一个文件的两条轨道"，不需要像
    /// AVFoundation 那样提前分别探测两条流再手工拼 composition。
    /// 长度必须按字节数（UTF-8）算，不能按字符数，否则多字节字符会导致地址
    /// 从中间被截断。
    static func edlURL(for source: PlaybackSource) -> String {
        let videoURLString = source.video.primary.absoluteString
        guard let audio = source.audio else { return videoURLString }
        let audioURLString = audio.primary.absoluteString
        return "edl://!no_chapters;%\(videoURLString.utf8.count)%\(videoURLString);"
            + "!new_stream;!no_chapters;%\(audioURLString.utf8.count)%\(audioURLString)"
    }

    private static func makeStream(from stream: DashStream) -> PlaybackStream? {
        makeStream(primary: stream.baseUrl, backups: stream.backupUrl ?? [])
    }

    private static func makeStream(from stream: DurlItem) -> PlaybackStream? {
        makeStream(primary: stream.url, backups: stream.backupUrl ?? [])
    }

    private static func makeStream(primary: String, backups: [String]) -> PlaybackStream? {
        let urls = ([primary] + backups).compactMap(URL.init(string:))
        var seen = Set<URL>()
        let unique = urls.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return nil }
        let ranked = unique.enumerated().sorted { left, right in
            let leftRank = cdnRank(left.element)
            let rightRank = cdnRank(right.element)
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
        return PlaybackStream(primary: ranked[0], backups: Array(ranked.dropFirst()))
    }

    private static func codecRank(_ codec: String) -> Int {
        preferredCodecPrefixes.firstIndex { codec.lowercased().hasPrefix($0) } ?? preferredCodecPrefixes.count
    }

    private static func cdnRank(_ url: URL) -> Int {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host.hasPrefix("upos-") || host.contains(".akamaized.") { return 0 }
        if path.contains("/upgcxcode/") && !host.contains(".mcdn.") { return 1 }
        if host.contains(".mcdn.") || path.contains("/v1/resource/") { return 3 }
        return 2
    }
}
