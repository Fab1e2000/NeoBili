import SwiftUI
import UIKit

/// Shared typography and selection behavior for the native collection cell
/// and standalone previews. The collection uses IntroductionView directly.
struct VideoIntroductionCard: View {
    let title: String
    let stat: VideoStat
    let pubdate: Int
    let desc: String
    @Binding var isExpanded: Bool

    var body: some View {
        NativeVideoIntroductionCard(title: title, stat: stat, pubdate: pubdate, desc: desc,
                                    isExpanded: isExpanded, onToggle: { isExpanded.toggle() })
    }
}

struct NativeVideoIntroductionCard: UIViewRepresentable {
    let title: String
    let stat: VideoStat
    let pubdate: Int
    let desc: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeUIView(context: Context) -> IntroductionView { IntroductionView() }
    func updateUIView(_ view: IntroductionView, context: Context) {
        view.configure(title: title, metadata: Self.metadataText(stat: stat, pubdate: pubdate),
                       description: desc, expanded: isExpanded, typeSize: typeSize)
        view.onToggle = onToggle
    }
    /// 标题下方的信息行：播放 · 弹幕 · 发布时间。
    static func metadataText(stat: VideoStat, pubdate: Int) -> String {
        ["\(stat.view.biliCountText)播放", "\(stat.danmaku.biliCountText)弹幕", pubdate.biliPubdateText]
            .joined(separator: " · ")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IntroductionView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.height(for: width))
    }

    /// 平铺在页面上，不加底色：左右与页面正文对齐，上下只留很小的间距，层次靠字号区分。
    final class IntroductionView: UIView, UIGestureRecognizerDelegate {
        private static let verticalInset: CGFloat = 2
        /// 展开箭头占用的宽度，标题为它让出右侧空间。
        private static let arrowWidth: CGFloat = 16
        private static let arrowGap: CGFloat = 8

        let titleLabel = UILabel()
        private let metadataLabel = UILabel()
        private let descriptionView = UITextView()
        private let divider = UIView()
        private let arrow = UIImageView()
        private var typeSize: DynamicTypeSize?
        private var expanded = false
        private var hasDescription = false
        var onToggle: (() -> Void)?

        init() {
            super.init(frame: .zero)
            clipsToBounds = true
            titleLabel.numberOfLines = 0
            titleLabel.textColor = .label
            titleLabel.accessibilityIdentifier = "video.introduction.title"
            metadataLabel.numberOfLines = 0
            metadataLabel.textColor = .secondaryLabel
            metadataLabel.accessibilityIdentifier = "video.introduction.metadata"
            descriptionView.backgroundColor = .clear
            descriptionView.textColor = .secondaryLabel
            descriptionView.isEditable = false
            descriptionView.isSelectable = true
            descriptionView.isScrollEnabled = false
            descriptionView.textContainerInset = .zero
            descriptionView.textContainer.lineFragmentPadding = 0
            descriptionView.accessibilityIdentifier = "video.introduction.description"
            divider.backgroundColor = .separator
            arrow.tintColor = .secondaryLabel
            arrow.contentMode = .scaleAspectFit
            arrow.isAccessibilityElement = false
            for view in [titleLabel, metadataLabel, divider, descriptionView, arrow] { addSubview(view) }
            let tap = UITapGestureRecognizer(target: self, action: #selector(toggle))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func configure(title: String, metadata: String, description: String, expanded: Bool, typeSize: DynamicTypeSize) {
            if self.typeSize != typeSize {
                self.typeSize = typeSize
                let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
                let titleFont = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: traits)
                titleLabel.font = .systemFont(ofSize: titleFont.pointSize, weight: .semibold)
                metadataLabel.font = .preferredFont(forTextStyle: .footnote, compatibleWith: traits)
                descriptionView.font = .preferredFont(forTextStyle: .callout, compatibleWith: traits)
            }
            // Expansion never assigns or retypesets the title.
            if titleLabel.text != title { titleLabel.text = title }
            if metadataLabel.text != metadata { metadataLabel.text = metadata }
            if descriptionView.text != description { descriptionView.text = description }
            self.expanded = expanded
            hasDescription = !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            descriptionView.isHidden = !expanded || !hasDescription
            divider.isHidden = descriptionView.isHidden
            arrow.isHidden = !hasDescription
            arrow.image = UIImage(systemName: expanded ? "chevron.up" : "chevron.down",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            titleLabel.accessibilityCustomActions = hasDescription ? [UIAccessibilityCustomAction(
                name: expanded ? "收起简介" : "展开简介", target: self, selector: #selector(accessibilityToggle))] : []
            titleLabel.accessibilityValue = hasDescription ? (expanded ? "已展开" : "已收起") : nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }

        private func measured(_ label: UILabel, width: CGFloat) -> CGFloat {
            ceil(label.sizeThatFits(CGSize(width: max(1, width), height: .greatestFiniteMagnitude)).height)
        }
        private var titleTrailingInset: CGFloat { hasDescription ? Self.arrowWidth + Self.arrowGap : 0 }

        func height(for width: CGFloat) -> CGFloat {
            let contentWidth = max(1, width)
            var height = 2 * Self.verticalInset + measured(titleLabel, width: contentWidth - titleTrailingInset)
                + 6 + measured(metadataLabel, width: contentWidth)
            if expanded && hasDescription {
                height += 17 + ceil(descriptionView.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height)
            }
            return height
        }
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: bounds.width > 0 ? height(for: bounds.width) : UIView.noIntrinsicMetric)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            UIView.performWithoutAnimation {
                let width = max(1, bounds.width)
                let titleWidth = max(1, width - titleTrailingInset)
                let titleHeight = measured(titleLabel, width: titleWidth)
                titleLabel.frame = CGRect(x: 0, y: Self.verticalInset, width: titleWidth, height: titleHeight)
                arrow.frame = CGRect(x: bounds.width - Self.arrowWidth, y: Self.verticalInset,
                                     width: Self.arrowWidth, height: titleLabel.font.lineHeight)
                let metadataHeight = measured(metadataLabel, width: width)
                metadataLabel.frame = CGRect(x: 0, y: titleLabel.frame.maxY + 6, width: width, height: metadataHeight)
                divider.frame = CGRect(x: 0, y: metadataLabel.frame.maxY + 8, width: width, height: 1 / max(1, traitCollection.displayScale))
                let bodyHeight = ceil(descriptionView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                descriptionView.frame = CGRect(x: 0, y: divider.frame.maxY + 8, width: width, height: bodyHeight)
            }
        }
        @objc private func toggle() { if hasDescription { onToggle?() } }
        @objc private func accessibilityToggle() -> Bool { toggle(); return hasDescription }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Leave text selection and its menu to UITextView.
            !(touch.view?.isDescendant(of: descriptionView) ?? false)
        }
    }
}
