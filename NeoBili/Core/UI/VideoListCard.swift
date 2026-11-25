import SwiftUI

/// Keep press feedback, touch hit testing and the lifted preview on the same card surface.
struct CardPressStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        surface(configuration.label, isPressed: configuration.isPressed)
    }

    func surface(_ label: some View, isPressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return label
            .overlay {
                if isPressed {
                    shape.fill(Color(uiColor: .tertiarySystemFill))
                        .allowsHitTesting(false)
                }
            }
            .contentShape([.interaction, .contextMenuPreview], shape)
    }
}

enum VideoListCardLayout {
    static let pageHorizontalInset: CGFloat = 8

    /// 上下两张卡片之间的半间距。实际卡片间距约为这个数字的两倍。
    static let cardVerticalSpacing: CGFloat = 3

    static let contentPadding: CGFloat = 6

    static let cardCornerRadius: CGFloat = 7

    static let imageTextSpacing: CGFloat = 10

    /// 封面图的宽度。高度会按 16:9 比例自动计算；数字越大，图片越大。
    static let imageWidth: CGFloat = 160

    static let imageCornerRadius: CGFloat = 3

    static let textVerticalSpacing: CGFloat = 4

    static let metadataSpacing: CGFloat = 10

    static let metadataIconTextSpacing: CGFloat = 2

    /// 右侧文字区域的高度。它最好和 16:9 封面高度保持一致。
    static let textAreaHeight: CGFloat = 90

    static let borderOpacity = 0.18

    static let borderWidth: CGFloat = 0.5
}

/// 搜索结果、空间投稿、资料库和选集列表共用的横向视频卡。
/// 视频详情页下方的推荐使用 NativeRelatedVideoCard。
struct VideoListCard: View {
    enum AccessibilityField: String {
        case title, author, duration
    }

    let coverURL: URL?
    let title: String
    let author: String
    /// 播放量。传负数表示该页面没有播放数据（历史、稍后再看），整段隐藏。
    let playCount: Int
    /// 已排版的时长或封面角标文字。留空则隐藏。
    let durationText: String
    /// 是否显示卡面底色、圆角和边线。
    var showsCardChrome = true
    var animatesEntrance = true
    var showsDurationOnCover = false

    var body: some View {
        VideoListCardContent(coverURL: coverURL, title: title, author: author,
                             playCount: playCount, durationText: durationText,
                             showsCardChrome: showsCardChrome, showsDurationOnCover: showsDurationOnCover)
            .equatable()
            .videoCardEntrance(enabled: animatesEntrance)
    }
}

/// Only immutable presentation values participate in equality. Buttons, menus,
/// entrance state and environment-driven appearance remain outside this boundary.
private struct VideoListCardContent: View, Equatable {
    let coverURL: URL?
    let title: String
    let author: String
    let playCount: Int
    let durationText: String
    let showsCardChrome: Bool
    let showsDurationOnCover: Bool

    var body: some View {
        HStack(alignment: .top, spacing: VideoListCardLayout.imageTextSpacing) {
            Group {
                if showsDurationOnCover, !durationText.isEmpty {
                    VideoCoverThumbnail(url: coverURL, duration: durationText, playText: "",
                                        cornerRadius: VideoListCardLayout.imageCornerRadius)
                } else {
                    CoverThumbnail(url: coverURL)
                        .clipShape(
                            RoundedRectangle(cornerRadius: VideoListCardLayout.imageCornerRadius, style: .continuous)
                        )
                }
            }
            .frame(width: VideoListCardLayout.imageWidth)

            VStack(alignment: .leading, spacing: VideoListCardLayout.textVerticalSpacing) {
                Text(title)
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(.primary)
                    // 即使标题只有一行，也会保留第二行的位置。
                    // 这样 UP 主始终在第三行，不会跑到标题区域。
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                // UP 主和数据行以文字区底部为基准往上排，不紧跟在标题后面：
                // 标题只有一行时，这两行沉在底部，和左侧 16:9 封面的下缘对齐。
                Spacer(minLength: 0)

                Text(author)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: VideoListCardLayout.metadataSpacing) {
                    if playCount >= 0 {
                        HStack(spacing: VideoListCardLayout.metadataIconTextSpacing) {
                            Image(systemName: "play.rectangle")
                            Text(playCount.biliCountText)
                        }
                    }

                    if !showsDurationOnCover, !durationText.isEmpty {
                        HStack(spacing: VideoListCardLayout.metadataIconTextSpacing) {
                            Image(systemName: "clock")
                            Text(durationText)
                        }
                    }
                }
                .font(.app(.caption2))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Preserve the ordinary 90pt row, but let larger text grow instead
            // of drawing the author/metadata outside a fixed-height card.
            .frame(minHeight: VideoListCardLayout.textAreaHeight, alignment: .top)

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, VideoListCardLayout.contentPadding)
        .padding(.horizontal, showsCardChrome ? VideoListCardLayout.contentPadding : 0)
        .background {
            if showsCardChrome {
                RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous)
                            .stroke(
                                Color(uiColor: .separator).opacity(VideoListCardLayout.borderOpacity),
                                lineWidth: VideoListCardLayout.borderWidth
                            )
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: showsCardChrome ? VideoListCardLayout.cardCornerRadius : 0,
                                       style: .continuous))
    }
}

/// A stacked card for sizes where a horizontal row compresses the text.
struct AccessibleVideoListCard<Probe: View>: View {
    let coverURL: URL?
    let title: String
    let author: String
    let durationText: String
    @ViewBuilder let fieldBackground: (VideoListCard.AccessibilityField) -> Probe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverThumbnail(url: coverURL)
                .frame(maxWidth: 240)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(title)
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .background { fieldBackground(.title) }
            Text(author)
                .font(.app(.caption)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .background { fieldBackground(.author) }
            Label(durationText, systemImage: "clock")
                .font(.app(.caption2)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .background { fieldBackground(.duration) }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous))
    }
}

#Preview("横向视频卡片") {
    VStack(spacing: VideoListCardLayout.cardVerticalSpacing * 2) {
        VideoListCard(coverURL: nil, title: "示例视频标题，两行时会在这里换行，放不下的部分以省略号结尾",
                      author: "示例 UP 主", playCount: 161_000, durationText: "19:56", animatesEntrance: false)
        VideoListCard(coverURL: nil, title: "单行标题", author: "示例 UP 主",
                      playCount: -1, durationText: "", animatesEntrance: false)
    }
    .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
    .frame(maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
}
