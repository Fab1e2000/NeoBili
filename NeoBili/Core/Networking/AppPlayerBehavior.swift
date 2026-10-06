import Foundation

/// Encodes only existing playback events; it neither observes the player nor schedules work.
@MainActor
enum AppPlayerBehavior {
    static func payload(aid: Int, cid: Int, position: Double, playbackSession: String,
                        source: [String: String], quality: Int?, playbackRate: Double = 1,
                        inlinePreview: Bool = false) -> Data? {
        guard aid > 0, cid > 0, position.isFinite, position >= 0,
              playbackRate.isFinite, playbackRate > 0 else { return nil }
        let origin = source["from_spmid"].flatMap { $0.isEmpty ? nil : $0 } ?? "default-value"
        var info = AppProto.string(1, origin) + AppProto.integer(3, 3)
        // Official common fields use playback position in milliseconds, not watched duration.
        info += AppProto.string(6, String(Int(min(position * 1000, Double(Int32.max)))))
        info += AppProto.string(7, String(aid)) + AppProto.string(8, String(cid))
        let speed = playbackRate.rounded(.towardZero) == playbackRate
            ? String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), playbackRate)
            : NSNumber(value: playbackRate).stringValue
        info += AppProto.string(14, playbackSession) + AppProto.string(15, speed)
        info += AppProto.integer(17, inlinePreview ? 1 : 2)
        if let quality {
            let supported = [15, 16, 32, 64, 74, 80, 100, 112, 116, 120, 129]
            info += AppProto.string(16, String(supported.contains(quality) ? quality : 0))
        }
        return info
    }

    static func record(_ name: String, aid: Int, cid: Int, position: Double, playbackSession: String,
                       source: [String: String], accountSession: UUID, quality: Int?, playbackRate: Double = 1, sequence: Int, inlinePreview: Bool = false) {
        guard !AppNetwork.isRegression,
              let info = payload(aid: aid, cid: cid, position: position, playbackSession: playbackSession,
                                 source: source, quality: quality, playbackRate: playbackRate, inlinePreview: inlinePreview) else { return }
        var fields = ["event_policy": "0", "$player_event_seq": String(sequence)]
        if name == "player.player.start.all.player", let track = source["track_id"] { fields["track_id"] = track }
        let payload = info
        let time = Int(Date().timeIntervalSince1970 * 1000)
        Task { await AppBehaviorReporter.shared.record(name: name, category: 9, fields: fields,
            player: payload, session: accountSession, timestamp: time) }
    }
}
