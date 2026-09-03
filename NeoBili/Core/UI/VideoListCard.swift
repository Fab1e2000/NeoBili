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
    let playCount: Int
    /// 已经排好版的时长文字，例如 `12:34`。留空则不显示这一项。
    let durationText: String

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

                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: VideoListCardLayout.metadataSpacing) {
                    HStack(spacing: VideoListCardLayout.metadataIconTextSpacing) {
                        Image(systemName: "play.rectangle")
                        Text(playCount.biliCountText)
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
        .padding(VideoListCardLayout.contentPadding)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(
            RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous)
                .stroke(
                    Color(uiColor: .separator).opacity(VideoListCardLayout.borderOpacity),
                    lineWidth: VideoListCardLayout.borderWidth
                )
        }
        .contentShape(
            RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous)
        )
    }
}
