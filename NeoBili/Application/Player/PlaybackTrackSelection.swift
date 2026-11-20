import Foundation
import NeoBiliDomain

struct PlaybackTrackSelection {
    let source: PlaybackSource
    let video: DashStream?
    let videoQuality: Int?
    let audioQuality: Int?

    init(payload: PlayURLData, configuration: VideoPlaybackConfiguration) throws {
        let source = try PlaybackSourceBuilder.makeSource(from: payload, configuration: configuration)
        self.source = source
        video = source.isDASH ? payload.dash.flatMap {
            PlaybackSourceBuilder.bestVideoStream($0.video, preferredQuality: configuration.quality)
        } : nil
        videoQuality = source.isDASH ? video?.id : payload.quality
        audioQuality = source.audio == nil ? nil : payload.dash.flatMap {
            PlaybackSourceBuilder.bestAudioStream($0.allAudio, preferredQuality: configuration.audioQuality)?.id
        }
    }

    static func unavailableQualityMessage(_ quality: Int, response: PlayURLData, previous: PlayURLData) -> String {
        let format = response.supportFormats?.first { $0.quality == quality }
            ?? previous.supportFormats?.first { $0.quality == quality }
        let title = PlaybackQuality.videoTitle(quality)
        if format?.needsVIP == true { return String(localized: "未取得\(title)播放地址，该档位需要大会员权限；已保留当前画质") }
        if format?.needsLogin == true { return String(localized: "未取得\(title)播放地址，请确认登录状态；已保留当前画质") }
        return String(localized: "服务器未提供\(title)播放地址，已保留当前画质")
    }
}
