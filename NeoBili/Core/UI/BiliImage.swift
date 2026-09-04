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
    /// 已经排好版的播放量。推荐流给的是裸数字，走 `playCount` 那个构造器；
    /// 关注页的动态流给的本来就是「1.2万」这样的成品文字，原样传进来。
    let playText: String
    var aspectRatio: CGFloat = 16.0 / 9.0
    var cornerRadius: CGFloat = 6
    /// 下面两个角单独控制。首页卡片的封面下缘紧贴文字区，圆角会在那里
    /// 割出一道缺口，所以传 0；不传就和上面两个角一样。
    var bottomCornerRadius: CGFloat?

    init(
        url: URL?,
        duration: String,
        playText: String,
        aspectRatio: CGFloat = 16.0 / 9.0,
        cornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.url = url
        self.duration = duration
        self.playText = playText
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    init(
        url: URL?,
        duration: String,
        playCount: Int,
        aspectRatio: CGFloat = 16.0 / 9.0,
        cornerRadius: CGFloat = 6,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.init(
            url: url,
            duration: duration,
            playText: playCount.biliCountText,
            aspectRatio: aspectRatio,
            cornerRadius: cornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: bottomCornerRadius ?? cornerRadius,
            bottomTrailingRadius: bottomCornerRadius ?? cornerRadius,
            topTrailingRadius: cornerRadius,
            style: .continuous
        )
    }

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
                if !playText.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "play.rectangle")
                        Text(playText)
                    }
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
        .clipShape(shape)
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
