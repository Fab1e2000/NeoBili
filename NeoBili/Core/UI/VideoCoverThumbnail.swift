import SwiftUI

/// Reserves a caller-selected aspect ratio, then fills that exact box with a
/// cropped, cached image. Search results keep the conventional 16:9 default;
/// the recommendation grid opts into the official client's taller 4:3 cards.
struct CoverThumbnail: View {
    let url: URL?
    var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            // 封面框的尺寸就是解码目标：不必等图片自己测量，也不会因为占位图和
            // 真图的比例不同而按两个尺寸各解码一次。
            BiliImage(url: url, targetSize: proxy.size)
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

    /// 渐变只贴住封面下缘，下面两个角跟封面一致。
    private var scrimShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: bottomCornerRadius ?? cornerRadius,
            bottomTrailingRadius: bottomCornerRadius ?? cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        // 只裁剪封面图片本身，渐变和文字画在裁剪外面，文字也不加阴影：
        // 裁剪里套着多层内容、以及文字阴影，都会让系统每帧额外做离屏渲染，
        // 一屏十几张卡叠起来会把渲染时间顶到 120Hz 的上限。
        // 文字的可读性改由加深的渐变保证。
        CoverThumbnail(url: url, aspectRatio: aspectRatio)
            .clipShape(shape)
            .overlay(alignment: .bottom) {
                scrimShape
                    .fill(LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.2), location: 0.4),
                            .init(color: .black.opacity(0.6), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(height: 52)
            }
            .overlay(alignment: .bottom) {
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
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
    }
}
