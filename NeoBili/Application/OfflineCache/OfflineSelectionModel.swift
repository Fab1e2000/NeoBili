import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class OfflineSelectionModel {
    let bvid: String
    let cid: Int?
    let services: ApplicationServices
    private let defaults: UserDefaults
    private var detail: VideoDetail?
    var videos: [OfflineVideo] = []
    var selected: Set<String> = []
    var qualities: [Int] = []
    var quality: Int?
    var hasCollection = false
    var collectionSelected = false
    var isLoading = false
    var isSubmitting = false
    var error: String?
    static let qualityKey = "neobili.offline.preferredQuality"

    init(bvid: String, cid: Int?, services: ApplicationServices, defaults: UserDefaults = .standard) {
        self.bvid = bvid; self.cid = cid; self.services = services; self.defaults = defaults
        quality = defaults.object(forKey: Self.qualityKey) as? Int ?? 80
    }

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let detail = try await services.video.videoDetail(bvid: bvid)
            try Task.checkCancellation()
            self.detail = detail; hasCollection = detail.ugcSeason?.episodes.isEmpty == false
            videos = Self.items(detail, collection: nil, offset: 0)
            selected = ["\(bvid):\(cid ?? detail.cid)"]
            let payload = try await services.video.playURL(bvid: bvid, cid: cid ?? detail.cid)
            try Task.checkCancellation()
            qualities = Array(Set((payload.dash?.video.map(\.id) ?? []) +
                (payload.durl?.isEmpty == false ? [payload.quality].compactMap { $0 } : []))).sorted(by: >)
            if !qualities.contains(quality ?? 0) { quality = nil }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func changeScope() async {
        guard let detail else { return }
        if !collectionSelected {
            videos = Self.items(detail, collection: nil, offset: 0)
            selected = ["\(bvid):\(cid ?? detail.cid)"]
            return
        }
        guard let collection = detail.ugcSeason else { return }
        isLoading = true; error = nil; videos = []
        defer { isLoading = false }
        var seen = Set<String>()
        for (index, episode) in collection.episodes.enumerated() {
            guard !Task.isCancelled else { return }
            guard let id = episode.bvid, seen.insert(id).inserted else { continue }
            do {
                let video = id == detail.bvid ? detail : try await services.video.videoDetail(bvid: id)
                videos += Self.items(video, collection: collection, offset: index * 10_000)
            } catch { self.error = String(localized: "部分视频未加载：\(error.localizedDescription)") }
        }
        selected = ["\(bvid):\(cid ?? detail.cid)"]
    }

    static func items(_ detail: VideoDetail, collection: UgcSeason?, offset: Int) -> [OfflineVideo] {
        let groupID = collection?.id.map { "season:\($0)" } ?? "video:\(detail.bvid)"
        let groupTitle = collection?.title ?? detail.title
        let parts = detail.pages
        if parts.isEmpty {
            return [.init(bvid: detail.bvid, cid: detail.cid, aid: detail.aid, title: detail.title,
                partTitle: "", author: detail.owner.name, cover: detail.secureCoverURL,
                duration: Double(detail.duration), groupID: groupID, groupTitle: groupTitle, order: offset)]
        }
        return parts.enumerated().map { index, part in
            .init(bvid: detail.bvid, cid: part.cid, aid: detail.aid, title: detail.title,
                partTitle: parts.count > 1 ? "P\(part.page) · \(part.part)" : "",
                author: detail.owner.name, cover: detail.secureCoverURL, duration: Double(part.duration),
                groupID: groupID, groupTitle: groupTitle, order: offset + index)
        }
    }

    var selectedVideos: [OfflineVideo] { videos.filter { selected.contains($0.id) } }

    func duplicateMessage(in snapshot: OfflineCacheSnapshot) -> String? {
        let videos = selectedVideos
        guard !videos.isEmpty, let quality else { return nil }
        if videos.allSatisfy({ video in snapshot.completed.contains { $0.id == video.id && $0.quality == quality } }) {
            return String(localized: "所选内容已缓存")
        }
        if videos.allSatisfy({ video in (snapshot.completed + snapshot.tasks).contains { $0.id == video.id && $0.quality == quality } }) {
            return String(localized: "所选内容已在缓存列表中")
        }
        return nil
    }

    func needsReplacement(in snapshot: OfflineCacheSnapshot) -> Bool {
        (snapshot.completed + snapshot.tasks).contains { selected.contains($0.id) && $0.quality != quality }
    }

    func submit(replace: Bool) async -> Bool {
        guard let quality, !selectedVideos.isEmpty, !isSubmitting else { return false }
        isSubmitting = true; defer { isSubmitting = false }
        do {
            try await services.offlineCache.enqueue(selectedVideos, quality, VideoPlaybackConfiguration.current.audioQuality, replace)
            defaults.set(quality, forKey: Self.qualityKey)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
