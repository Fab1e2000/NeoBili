import SwiftUI

private let skeletonFill = Color(uiColor: .tertiarySystemFill)

struct VideoIntroductionSkeleton: View {
    @ScaledMetric(relativeTo: .headline) private var titleLineHeight = 22.0
    @ScaledMetric(relativeTo: .subheadline) private var textLineHeight = 18.0
    @ScaledMetric(relativeTo: .caption) private var captionHeight = 14.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(skeletonFill).frame(width: 40, height: 40)
                SkeletonLine(fraction: 0.42, lineHeight: textLineHeight)
                Capsule().fill(skeletonFill).frame(width: 68, height: 34)
            }
            .frame(minHeight: 44)
            .padding(.top, 12)
            .padding(.bottom, 10)

            SkeletonLine(fraction: 0.88, lineHeight: titleLineHeight)
            SkeletonLine(fraction: 0.57, lineHeight: titleLineHeight)
            SkeletonLine(fraction: 0.44, lineHeight: captionHeight)
                .padding(.bottom, 12)

            HStack(spacing: VideoActionBarLayout.buttonSpacing) {
                ForEach(0..<6) { _ in
                    VStack(spacing: VideoActionBarLayout.captionSpacing) {
                        RoundedRectangle(cornerRadius: VideoActionBarLayout.cornerRadius)
                            .fill(skeletonFill)
                            .frame(height: VideoActionBarLayout.buttonHeight)
                        SkeletonLine(fraction: 0.48, lineHeight: captionHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载视频简介")
        .accessibilityIdentifier("video.introduction.loading")
    }
}

struct VideoCommentSkeleton: View {
    let rowCount: Int
    let label: LocalizedStringKey
    @ScaledMetric(relativeTo: .caption) private var captionHeight = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var textLineHeight = 20.0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                HStack(alignment: .top, spacing: CommentLayout.avatarTextSpacing) {
                    Circle()
                        .fill(skeletonFill)
                        .frame(width: CommentLayout.avatarSize, height: CommentLayout.avatarSize)
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonLine(fraction: 0.28, lineHeight: captionHeight)
                            .padding(.bottom, CommentLayout.nameMessageSpacing)
                        SkeletonLine(fraction: 0.88, lineHeight: textLineHeight)
                        SkeletonLine(fraction: 0.63, lineHeight: textLineHeight)
                        SkeletonLine(fraction: 0.33, lineHeight: captionHeight)
                    }
                }
                .padding(.horizontal, CommentLayout.pageHorizontalInset)
                .padding(.vertical, CommentLayout.rowVerticalPadding)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }
}

struct RelatedVideosSkeleton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var titleLineHeight = 20.0
    @ScaledMetric(relativeTo: .caption) private var captionHeight = 16.0

    var body: some View {
        let cover = NativeRelatedVideoCard.coverSize
        VStack(spacing: 0) {
            ForEach(0..<2) { _ in
                HStack(alignment: .top, spacing: NativeRelatedVideoCard.coverTextSpacing) {
                    RoundedRectangle(cornerRadius: HomeCardLayout.coverCornerRadius)
                        .fill(skeletonFill)
                        .frame(width: cover.width, height: cover.height)
                    VStack(alignment: .leading, spacing: 0) {
                        SkeletonLine(fraction: 0.93, lineHeight: titleLineHeight)
                        SkeletonLine(fraction: 0.69, lineHeight: titleLineHeight)
                        Spacer(minLength: 0)
                        SkeletonLine(fraction: 0.58, lineHeight: captionHeight)
                        SkeletonLine(fraction: 0.43, lineHeight: captionHeight)
                    }
                }
                .frame(height: NativeRelatedVideoCard.cardHeight(typeSize: typeSize), alignment: .top)
                .padding(.vertical, NativeRelatedVideoCard.verticalInset)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载相关视频")
        .accessibilityIdentifier("video.related.loading")
    }
}

private struct SkeletonLine: View {
    let fraction: CGFloat
    let lineHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(skeletonFill)
                .frame(width: geometry.size.width * fraction, height: min(10, lineHeight / 2))
                .frame(height: lineHeight)
        }
        .frame(height: lineHeight)
    }
}
