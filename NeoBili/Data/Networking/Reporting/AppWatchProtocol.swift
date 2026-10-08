import Foundation

/// Encodes measured playback facts. Timing and delivery decisions remain in the
/// playback state machine and BiliAPI, independent of future protocol changes.
enum AppWatchProtocol {
    static func mobileParameters(_ report: PlaybackWatchReport) -> [String: String] {
        var fields = AppClientIdentity.parameters.merging(report.sourceFields) { _, value in value }
        fields.merge([
            "actionKey": "appkey", "statistics": AppClientIdentity.statistics,
            "type": "3", "sub_type": "0", "auto_play": report.isInlinePreview ? "2" : "0", "play_type": "1",
            "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN",
            "played_time": seconds(report.watchedTime), "actual_played_time": seconds(report.actualPlayedTime ?? report.watchedTime),
            "paused_time": seconds(report.pausedTime), "miniplayer_play_time": seconds(report.miniPlayerTime),
            "total_time": seconds(report.watchedTime + report.pausedTime),
            "last_play_progress_time": seconds(report.position == -1 ? report.maximumPosition : report.position),
            "max_play_progress_time": seconds(report.maximumPosition), "video_duration": seconds(report.duration),
            "start_ts": String(report.startTimestamp)
        ]) { _, value in value }
        return fields
    }

    static func historyParameters(aid: Int, cid: Int, report: PlaybackWatchReport,
                                  deviceTimestamp: Int) -> [String: String] {
        AppClientIdentity.parameters.merging([
            "aid": String(aid), "cid": String(cid), "type": "3", "sub_type": "0",
            "progress": String(Int(report.position.rounded(.down))), "start_ts": String(report.localStartTimestamp ?? report.startTimestamp),
            "statistics": AppClientIdentity.statistics, "actionKey": "appkey",
            "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN", "duration": seconds(report.duration),
            "device_ts": String(deviceTimestamp), "disable_rcmd": "0", "teenagers_age": "16", "epid": "0", "sid": "0"
        ]) { _, value in value }
    }

    private static func seconds(_ value: Double) -> String {
        String(Int(max(0, min(Double(Int.max) / 2, value.isFinite ? value : 0)).rounded(.down)))
    }
}
