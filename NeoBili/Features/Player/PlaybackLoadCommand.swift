import Foundation

enum PlaybackLoadCommand {
    /// MPVKit 的 mpv 0.41 使用 loadfile URL replace INDEX OPTIONS。
    /// https://mpv.io/manual/stable/#command-loadfile
    static func arguments(url: String, startTime: TimeInterval) -> [String] {
        let position = startTime.isFinite ? max(startTime, 0) : 0
        let start = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), position)
        return ["loadfile", url, "replace", "-1", "start=\(start)"]
    }
}
