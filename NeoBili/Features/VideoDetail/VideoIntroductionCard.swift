import SwiftUI

/// 标题、元信息和可展开正文共享一张随内容增长的玻璃卡片。
struct VideoIntroductionCard: View {
    let title: String
    let stat: VideoStat
    let pubdate: Int
    let desc: String
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var titleLineHeight: CGFloat = 22

    var body: some View {
        if hasDescription {
            card
                .contentShape(RoundedRectangle(cornerRadius: 24))
                .onTapGesture(perform: toggleDescription)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("视频简介")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggleDescription() }
                .accessibilityActions {
                    Button(isExpanded ? "收起简介" : "展开简介", action: toggleDescription)
                }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, hasDescription ? 36 : 0)
                .accessibilityIdentifier("video.introduction.title")
                .overlay(alignment: .topTrailing) {
                    if hasDescription {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                            .offset(x: 8, y: (titleLineHeight - 44) / 2)
                    }
                }

            Text([
                "\(stat.view.biliCountText)播放",
                "\(stat.danmaku.biliCountText)弹幕",
                pubdate.biliPubdateText
            ].joined(separator: "  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("video.introduction.metadata")

            if isExpanded, hasDescription {
                Divider()
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("video.introduction.description")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }

    private var hasDescription: Bool {
        !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleDescription() {
        guard hasDescription else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}
