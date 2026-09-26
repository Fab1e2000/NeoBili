import SwiftUI

/// 单列横向视频卡片的排版参数都集中在这里。
/// 搜索页和视频页的「相关视频」共用这一份，改一次两边一起变。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
enum VideoListCardLayout {
    /// 卡片与屏幕左右边缘的距离。数字越小，卡片占用的屏幕宽度越大。
    static let pageHorizontalInset: CGFloat = 8

    /// 上下两张卡片之间的半间距。实际卡片间距约为这个数字的两倍。
    static let cardVerticalSpacing: CGFloat = 3

    /// 卡片内容与白色卡片边缘的距离。数字越大，内容周围的留白越多。
    static let contentPadding: CGFloat = 6

    /// 整张白色卡片的圆角大小。0 表示直角，数字越大就越圆。
    static let cardCornerRadius: CGFloat = 7

    /// 封面图和右侧文字之间的距离。
    static let imageTextSpacing: CGFloat = 10

    /// 封面图的宽度。高度会按 16:9 比例自动计算；数字越大，图片越大。
    static let imageWidth: CGFloat = 160

    /// 封面图的圆角大小。0 表示直角，数字越大就越圆。
    static let imageCornerRadius: CGFloat = 3

    /// 标题、作者、播放量等文字行之间的竖向距离。
    static let textVerticalSpacing: CGFloat = 4

    /// 播放量和视频时长之间的水平距离。
    static let metadataSpacing: CGFloat = 10

    /// 小图标和它后面数字的距离。这个值保持较小，图标和数字就会看起来是一组。
    static let metadataIconTextSpacing: CGFloat = 2

    /// 右侧文字区域的高度。它最好和 16:9 封面高度保持一致。
    static let textAreaHeight: CGFloat = 90

    /// 卡片边线的透明度。0 表示完全看不见，1 表示完全不透明。
    static let borderOpacity = 0.18

    /// 卡片边线的粗细。数字越大，边线越粗。
    static let borderWidth: CGFloat = 0.5
}

/// 搜索结果和相关视频共用的横向视频卡片：左边封面，右边标题、UP 主和播放数据。
///
/// 卡片外观（留白、圆角、边线）也包含在这里，所以两个页面不会各自跑偏。
/// 调用方只负责把卡片放进列表并处理点击。
struct VideoListCard: View {
    let coverURL: URL?
    let title: String
    let author: String
    /// 播放量。传负数表示该页面没有播放数据（历史、稍后再看），整段隐藏。
    let playCount: Int
    /// 已经排好版的时长文字，例如 `12:34`。留空则不显示这一项。
    let durationText: String
    /// 是否画出卡片本身的外观（浅色底、圆角、边线）。
    ///
    /// 详情页传 false，让推荐列表直接显示在页面背景上。
    var showsCardChrome = true
    var animatesEntrance = true

    var body: some View {
        VideoListCardContent(coverURL: coverURL, title: title, author: author,
                             playCount: playCount, durationText: durationText,
                             showsCardChrome: showsCardChrome)
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

    var body: some View {
        HStack(alignment: .top, spacing: VideoListCardLayout.imageTextSpacing) {
            CoverThumbnail(url: coverURL)
                .frame(width: VideoListCardLayout.imageWidth)
                .clipShape(
                    RoundedRectangle(cornerRadius: VideoListCardLayout.imageCornerRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: VideoListCardLayout.textVerticalSpacing) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    // 即使标题只有一行，也会保留第二行的位置。
                    // 这样 UP 主始终在第三行，不会跑到标题区域。
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                // UP 主和数据行以文字区底部为基准往上排，不紧跟在标题后面：
                // 标题只有一行时，这两行沉在底部，和左侧 16:9 封面的下缘对齐。
                Spacer(minLength: 0)

                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: VideoListCardLayout.metadataSpacing) {
                    if playCount >= 0 {
                        HStack(spacing: VideoListCardLayout.metadataIconTextSpacing) {
                            Image(systemName: "play.rectangle")
                            Text(playCount.biliCountText)
                        }
                    }

                    if !durationText.isEmpty {
                        HStack(spacing: VideoListCardLayout.metadataIconTextSpacing) {
                            Image(systemName: "clock")
                            Text(durationText)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: VideoListCardLayout.textAreaHeight, alignment: .top)

            Spacer(minLength: 0)
        }
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
        .contentShape(Rectangle())
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
