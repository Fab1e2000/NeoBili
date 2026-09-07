import Foundation

struct VideoPlaybackConfiguration: Sendable, Equatable {
    var quality: Int = 64
    var audioQuality: Int = 0
    var hardwareDecoding: Bool = true
    var initialBufferSeconds: Double = 3
    var maxBufferBytes: Int = 32 * 1024 * 1024
    var maxBackBufferBytes: Int = 8 * 1024 * 1024
    var networkTimeoutSeconds: Int = 10

    static let fastStart = VideoPlaybackConfiguration()

    /// 系统设置里的「默认清晰度」。每次新建播放器都重新读取，改动即时生效，
    /// 不必重启应用；已打开的视频页保持原来的配置不受影响。
    static var current: VideoPlaybackConfiguration {
        var configuration = VideoPlaybackConfiguration()
        let stored = UserDefaults.standard.object(forKey: "neobili.preferredQuality") as? Int
        if let stored, Self.validQualities.contains(stored) {
            configuration.quality = stored
        }
        let audio = UserDefaults.standard.integer(forKey: PlaybackQuality.audioStorageKey)
        if PlaybackQuality.audioOptions.contains(where: { $0.id == audio }) {
            configuration.audioQuality = audio
        }
        return configuration
    }

    /// 设置页允许选择的清晰度集合，挡住随手写进 UserDefaults 的无效值。
    static let validQualities = Set(PlaybackQuality.videoOptions.map(\.id))
}

/// Maps our own configuration onto the mpv option strings `mpv_set_option_string`
/// expects. Kept as a pure function so the mapping is testable without touching
/// the real mpv handle or the Metal render surface.
enum MPVPlaybackOptions {
    static func make(
        configuration: VideoPlaybackConfiguration,
        isSimulator: Bool,
        httpHeaderFields: String
    ) -> [(String, String)] {
        [
            // 模拟器没有对应的 VideoToolbox 硬解通道，vo=gpu-next 在模拟器上
            // 也拿不到真正的 Metal/Vulkan 设备，交给 mpv 的软解兜底。
            ("hwdec", isSimulator ? "no" : (configuration.hardwareDecoding ? "videotoolbox" : "no")),
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("cache", "yes"),
            ("cache-secs", String(format: "%.1f", configuration.initialBufferSeconds)),
            // 磁盘缓存对着直播/一次性播放的点播视频没有意义，白白多一次写文件。
            ("cache-on-disk", "no"),
            ("demuxer-max-bytes", String(configuration.maxBufferBytes)),
            ("demuxer-max-back-bytes", String(configuration.maxBackBufferBytes)),
            ("network-timeout", String(configuration.networkTimeoutSeconds)),
            // DASH 视频、音频轨道各自独立编码时长，容易有几毫秒的偏差；以音轨为
            // 基准反而会让画面追着音频走，观感上比"音画都各让一步"更稳定。
            ("video-sync", "audio"),
            ("http-header-fields", httpHeaderFields),
            ("user-agent", BiliHeaders.userAgent)
        ]
    }
}
