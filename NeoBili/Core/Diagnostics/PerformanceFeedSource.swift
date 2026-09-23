#if PERFORMANCE_DEMO
import Foundation

/// Saves only public card metadata for same-content rendering comparisons.
/// Recording/replay is explicitly requested by launch argument, never in normal builds.
actor PerformanceFeedSource {
    static let shared = PerformanceFeedSource()
    private var recordedPages: [String: [[String: Any]]] = [:]
    private var replayPages: [String: [VideoSummary]]?
    private let url = URL.documentsDirectory.appending(path: "Performance/feed-fixture.json")

    func fetch(_ index: Int) async throws -> [VideoSummary] {
        if ProcessInfo.processInfo.arguments.contains("--feed-replay") {
            if replayPages == nil {
                replayPages = try JSONDecoder().decode([String: [VideoSummary]].self, from: Data(contentsOf: url))
            }
            // A fixed delay keeps pagination timing comparable between renderers.
            try await Task.sleep(for: .milliseconds(150))
            return replayPages?[String(index)] ?? []
        }
        let videos = try await BiliAPI.recommendFeed(freshIndex: index)
        if ProcessInfo.processInfo.arguments.contains("--feed-record") {
            if index == 0 { recordedPages = [:] }
            recordedPages[String(index)] = videos.map(Self.metadata)
            let data = try JSONSerialization.data(withJSONObject: recordedPages, options: [.sortedKeys])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return videos
    }

    private static func metadata(_ video: VideoSummary) -> [String: Any] {
        var result: [String: Any] = [
            "bvid": video.bvid, "aid": video.aid, "cid": video.cid,
            "title": video.title, "pic": video.pic, "desc": video.desc,
            "duration": video.duration, "pubdate": video.pubdate,
            "owner": ["mid": video.owner.mid, "name": video.owner.name, "face": video.owner.face],
            "stat": ["view": video.stat.view, "danmaku": video.stat.danmaku, "like": video.stat.like,
                     "favorite": video.stat.favorite, "coin": video.stat.coin, "share": video.stat.share,
                     "reply": video.stat.reply]
        ]
        if let dimension = video.dimension {
            result["dimension"] = ["width": dimension.width, "height": dimension.height, "rotate": dimension.rotate]
        }
        return result
    }
}
#endif
