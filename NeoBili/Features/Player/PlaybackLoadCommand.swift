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

/// Deliberately bounded choices; changing rate does not create polling or network work.
enum PlaybackSpeed {
    static let options: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    static func title(_ rate: Double) -> String { NSNumber(value: rate).stringValue + "×" }
    static func command(_ rate: Double) -> [String]? {
        guard options.contains(rate) else { return nil }
        return ["set", "speed", NSNumber(value: rate).stringValue]
    }
}
