import SwiftUI

/// Reserves a caller-selected aspect ratio, then fills that exact box with a
/// cropped, cached image. Search results keep the conventional 16:9 default;
/// the recommendation grid opts into the official client's taller 4:3 cards.
struct CoverThumbnail: View {
    let url: URL?
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            BiliImage(url: url)
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

/// Shared cover treatment for every video card. Keeping the metadata overlay
/// here prevents feed and search cards from drifting into different styles.
struct VideoCoverThumbnail: View {
    let url: URL?
    let duration: String
    let playCount: Int
    var aspectRatio: CGFloat = 16.0 / 9.0
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            CoverThumbnail(url: url, aspectRatio: aspectRatio)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.08), location: 0.4),
                            .init(color: .black.opacity(0.45), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 46)
                }

            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Image(systemName: "play.rectangle")
                    Text(playCount.biliCountText)
                }

                Spacer(minLength: 0)

                if !duration.isEmpty {
                    Text(duration)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// In-memory image cache. Bilibili's image CDN (hdslb.com) is hotlink-protected
/// on some resources, so every request needs the same Referer/User-Agent as the
/// rest of the app - plain `AsyncImage` can't attach those headers.
actor BiliImageCache {
    static let shared = BiliImageCache()
    private var storage: [URL: Image] = [:]

    func image(for url: URL) -> Image? { storage[url] }
    func insert(_ image: Image, for url: URL) {
        if storage.count > 300 { storage.removeAll() } // crude cap, good enough for a feed
        storage[url] = image
    }
}

/// Drop-in replacement for `AsyncImage` that sends Bilibili's required headers
/// and caches decoded images in memory so re-appearing cells (scroll up/down)
/// don't re-fetch.
struct BiliImage: View {
    let url: URL?
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image.resizable()
            } else if failed {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        failed = false
        guard let url else {
            failed = true
            return
        }
        if let cached = await BiliImageCache.shared.image(for: url) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let uiImage = UIImage(data: data) else {
                failed = true
                return
            }
            let loaded = Image(uiImage: uiImage)
            await BiliImageCache.shared.insert(loaded, for: url)
            if !Task.isCancelled {
                image = loaded
            }
        } catch {
            if !Task.isCancelled {
                failed = true
            }
        }
    }
}
