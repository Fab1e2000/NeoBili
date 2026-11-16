import SwiftUI
import NeoBiliDomain

struct OfflinePartsPlaybackSheet: View {
    let entries: [OfflineCacheEntry]
    let cache: OfflineCacheStore
    @Environment(NowPlayingStore.self) private var store
    @Environment(ActionFeedback.self) private var feedback

    var body: some View {
        let parts = entries.map {
            VideoPart(cid: $0.video.cid, page: $0.video.order % 10_000 + 1,
                      part: $0.video.displayTitle, duration: Int($0.video.duration))
        }
        let covers = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            cache.snapshot.coverURLs[entry.generation].map { (entry.video.cid, $0) }
        })
        VideoPartsSheet(parts: parts, currentCid: store.activeCid, coverURLs: covers,
                        title: entries.first?.video.groupID.hasPrefix("season:") == true
                            ? entries.first?.video.groupTitle ?? "合集" : "分P") { part in
            guard let entry = entries.first(where: { $0.video.cid == part.cid }) else { return }
            Task {
                do { try await store.openOffline(entry.id, service: cache.service, from: "offline-\(entry.id)") }
                catch { feedback.show(error.localizedDescription) }
            }
        }
        .actionFeedbackOverlay()
    }
}

struct OfflineSubtitleMenu: View {
    @Bindable var player: PlayerViewModel
    var body: some View {
        Menu("字幕", systemImage: "captions.bubble") {
            Picker("字幕语言", selection: $player.selectedSubtitleID) {
                Text("关闭字幕").tag(String?.none)
                ForEach(player.offline?.subtitles ?? []) { track in Text(track.title).tag(Optional(track.id)) }
            }
        }
    }
}

struct OfflineSubtitleOverlay: View {
    let player: PlayerViewModel
    let controlsVisible: Bool
    var body: some View {
        let track = player.offline?.subtitles.first { $0.id == player.selectedSubtitleID }
        let text = track?.text(at: player.currentTime) ?? ""
        if !text.isEmpty {
            Text(text).font(.app(.callout, weight: .medium)).multilineTextAlignment(.center)
                .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 16).padding(.bottom, controlsVisible ? 78 : 18)
                .allowsHitTesting(false)
        }
    }
}

struct OfflineArtwork: View {
    let url: URL
    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable() }
    }
}
