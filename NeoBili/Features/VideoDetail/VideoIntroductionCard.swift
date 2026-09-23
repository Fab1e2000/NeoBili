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
        view.configure(title: title,
                       metadata: ["\(stat.view.biliCountText)播放", "\(stat.danmaku.biliCountText)弹幕", pubdate.biliPubdateText].joined(separator: "  "),
                       description: desc, expanded: isExpanded, typeSize: typeSize)
        view.onToggle = onToggle
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: IntroductionView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.height(for: width))
    }

    final class IntroductionView: UIView, UIGestureRecognizerDelegate {
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
            backgroundColor = .tertiarySystemFill
            layer.cornerRadius = 24
            layer.cornerCurve = .continuous
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
                let font = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits)
                titleLabel.font = .systemFont(ofSize: font.pointSize, weight: .semibold)
                metadataLabel.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
                descriptionView.font = font
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
        func height(for width: CGFloat) -> CGFloat {
            let contentWidth = max(1, width - 32)
            var height = 32 + measured(titleLabel, width: contentWidth - (hasDescription ? 24 : 0))
                + 8 + measured(metadataLabel, width: contentWidth)
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
                let width = max(1, bounds.width - 32)
                let titleWidth = max(1, width - (hasDescription ? 24 : 0))
                let titleHeight = measured(titleLabel, width: titleWidth)
                titleLabel.frame = CGRect(x: 16, y: 16, width: titleWidth, height: titleHeight)
                arrow.frame = CGRect(x: bounds.width - 32, y: 16, width: 16, height: titleLabel.font.lineHeight)
                let metadataHeight = measured(metadataLabel, width: width)
                metadataLabel.frame = CGRect(x: 16, y: titleLabel.frame.maxY + 8, width: width, height: metadataHeight)
                divider.frame = CGRect(x: 16, y: metadataLabel.frame.maxY + 8, width: width, height: 1)
                let bodyHeight = ceil(descriptionView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                descriptionView.frame = CGRect(x: 16, y: divider.frame.maxY + 8, width: width, height: bodyHeight)
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
