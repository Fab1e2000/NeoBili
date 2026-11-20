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

    var currentVideoID: String? {
        guard let activeCid = cid ?? detail?.cid else { return nil }
        return "\(bvid):\(activeCid)"
    }

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

    @discardableResult
    func applyScope() -> [(index: Int, bvid: String)] {
        guard let detail else { return [] }
        let currentSelection = "\(bvid):\(cid ?? detail.cid)"
        if !collectionSelected {
            videos = Self.items(detail, collection: nil, offset: 0)
            selected = [currentSelection]
            return []
        }
        guard let collection = detail.ugcSeason else { return [] }
        error = nil
        var seen = Set<String>()
        var resolvedVideos: [OfflineVideo] = []
        var missing: [(index: Int, bvid: String)] = []
        for (index, episode) in collection.episodes.enumerated() {
            guard let id = episode.bvid, seen.insert(id).inserted else { continue }
            if let items = Self.episodeItems(episode, detail: detail, collection: collection, offset: index * 10_000) {
                resolvedVideos += items
            } else {
                missing.append((index, id))
            }
        }
        videos = resolvedVideos
        selected = [currentSelection]
        return missing
    }

    func changeScope() async {
        guard let detail else { return }
        let missing = applyScope()
        guard collectionSelected, let collection = detail.ugcSeason, !missing.isEmpty else { return }
        for item in missing {
            guard !Task.isCancelled, collectionSelected else { return }
            do {
                let video = item.bvid == detail.bvid ? detail : try await services.video.videoDetail(bvid: item.bvid)
                guard !Task.isCancelled, collectionSelected else { return }
                let loaded = Self.items(video, collection: collection, offset: item.index * 10_000)
                let existingIDs = Set(videos.map(\.id))
                videos = (videos + loaded.filter { !existingIDs.contains($0.id) }).sorted { $0.order < $1.order }
            } catch {
                self.error = String(localized: "部分视频未加载：\(error.localizedDescription)")
            }
        }
    }

    static func episodeItems(_ episode: UgcSeasonEpisode, detail: VideoDetail, collection: UgcSeason, offset: Int) -> [OfflineVideo]? {
        guard let bvid = episode.bvid else { return [] }
        if bvid == detail.bvid {
            return items(detail, collection: collection, offset: offset)
        }
        let groupID = collection.id.map { "season:\($0)" } ?? "video:\(detail.bvid)"
        let groupTitle = collection.title ?? detail.title
        let title = episode.title ?? detail.title
        let cover = episode.secureCoverURL ?? detail.secureCoverURL
        if let pages = episode.pages, !pages.isEmpty {
            return pages.enumerated().map { index, part in
                .init(bvid: bvid, cid: part.cid, aid: episode.aid ?? 0, title: title,
                      partTitle: pages.count > 1 ? "P\(part.page) · \(part.part)" : "",
                      author: detail.owner.name, cover: cover, duration: Double(part.duration),
                      groupID: groupID, groupTitle: groupTitle, order: offset + index)
            }
        }
        guard let cid = episode.cid, cid > 0 else { return nil }
        return [.init(bvid: bvid, cid: cid, aid: episode.aid ?? 0, title: title,
                      partTitle: "", author: detail.owner.name, cover: cover,
                      duration: Double(episode.arc?.duration ?? 0),
                      groupID: groupID, groupTitle: groupTitle, order: offset)]
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
        if videos.allSatisfy({ video in snapshot.completed.contains { $0.matches(videoID: video.id, quality: quality) } }) {
            return String(localized: "所选内容已缓存")
        }
        if videos.allSatisfy({ video in (snapshot.completed + snapshot.tasks).contains { $0.matches(videoID: video.id, quality: quality) } }) {
            return String(localized: "所选内容已在缓存列表中")
        }
        return nil
    }

    func needsReplacement(in snapshot: OfflineCacheSnapshot) -> Bool {
        guard let quality else { return false }
        let entries = snapshot.completed + snapshot.tasks
        return selected.contains { id in
            entries.contains { $0.id == id } && !entries.contains { $0.matches(videoID: id, quality: quality) }
        }
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
