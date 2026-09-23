import SwiftUI
import UIKit

/// Fixed-geometry card content. The enclosing SwiftUI button owns interactions and entrance animations.
struct NativeHomeVideoCard: UIViewRepresentable {
    let video: VideoSummary
    let titleWidth: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    func makeUIView(context: Context) -> CardView { CardView() }

    func updateUIView(_ view: CardView, context: Context) {
        view.configure(video: video, titleWidth: titleWidth, dynamicTypeSize: dynamicTypeSize, scale: displayScale)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CardView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: width / HomeCardLayout.coverAspectRatio + HomeCardLayout.detailsHeight)
    }

    final class CardView: UIView {
        private let cover = CardImageView()
        private let avatar = CardImageView(symbol: "person.crop.circle")
        private var avatarTask: Task<Void, Never>?
        private let resolveAvatar: @Sendable (Int) async -> URL?
        private let title = UIImageView()
        private let owner = UILabel()
        private let playCount = UILabel()
        private let duration = UILabel()
        private let playIcon = UIImageView()
        private let gradient = CAGradientLayer()
        private var fallbackTitle: UIHostingController<AnyView>?
        private var titleHeight: CGFloat = 40
        private var configuration: Configuration?
        private var configuredTypeSize: DynamicTypeSize?
        private var durationMeasurement: (availableWidth: CGFloat, width: CGFloat)?

        private struct Configuration: Equatable {
            let video: VideoSummary
            let width: CGFloat
            let typeSize: DynamicTypeSize
            let scale: CGFloat
        }

        init(resolveAvatar: @escaping @Sendable (Int) async -> URL? = { await OwnerAvatarCache.shared.url(for: $0) }) {
            self.resolveAvatar = resolveAvatar
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .secondarySystemGroupedBackground
            layer.cornerRadius = 7
            layer.cornerCurve = .continuous
            layer.borderWidth = 0.5
            cover.layer.cornerRadius = HomeCardLayout.coverCornerRadius
            cover.layer.cornerCurve = .continuous
            cover.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            avatar.layer.cornerRadius = 8
            avatar.accessibilityIdentifier = "home.owner.avatar"
            addSubview(cover)
            gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.2).cgColor,
                               UIColor.black.withAlphaComponent(0.6).cgColor]
            gradient.locations = [0, 0.4, 1]
            layer.addSublayer(gradient)
            for view in [title, owner, playCount, duration, playIcon, avatar] { addSubview(view) }
            title.contentMode = .topLeft
            title.tintColor = .label
            owner.textColor = .secondaryLabel
            owner.lineBreakMode = .byTruncatingTail
            playCount.textColor = .white
            duration.textColor = .white
            playIcon.tintColor = .white
            playIcon.contentMode = .scaleAspectFit
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: CardView, _: UITraitCollection) in
                view.updateBorder()
            }
            updateBorder()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { avatarTask?.cancel() }

        private func updateBorder() {
            layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).withAlphaComponent(
                UIColor.separator.resolvedColor(with: traitCollection).cgColor.alpha * 0.18
            ).cgColor
        }

        func configure(video: VideoSummary, titleWidth: CGFloat, dynamicTypeSize: DynamicTypeSize, scale: CGFloat) {
            let updated = Configuration(video: video, width: titleWidth, typeSize: dynamicTypeSize, scale: scale)
            guard configuration != updated else { return }
            configuration = updated
            // Rebinding a reused card changes its content, not its typography.
            // Avoid repeated font lookup and symbol configuration on that path.
            if configuredTypeSize != dynamicTypeSize {
                configuredTypeSize = dynamicTypeSize
                let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
                let small = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traits)
                owner.font = small
                let semibold = UIFont.systemFont(ofSize: small.pointSize, weight: .semibold)
                playCount.font = semibold
                duration.font = semibold
                playIcon.image = UIImage(systemName: "play.rectangle", withConfiguration: UIImage.SymbolConfiguration(font: semibold))
                durationMeasurement = nil
            }
            playCount.text = video.stat.view.biliCountText
            let durationText = video.formattedDuration
            if duration.text != durationText {
                duration.text = durationText
                durationMeasurement = nil
            }
            owner.text = video.owner.name
            let fontSize = PreparedTitle.fontSize(for: dynamicTypeSize)
            let metrics = PreparedTitle.metrics(fontSize: fontSize)
            titleHeight = metrics?.boxHeight ?? 40
            if metrics == nil {
                // fontSize(for:) queues measurement outside the current SwiftUI
                // update. Reconfigure after that measurement, provided the cell
                // still represents this card and text-size setting.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.configuration == updated,
                          PreparedTitle.metrics(fontSize: fontSize) != nil else { return }
                    self.configuration = nil
                    self.configure(video: video, titleWidth: titleWidth, dynamicTypeSize: dynamicTypeSize, scale: scale)
                }
            }
            if PreparedTitle.supports(video.title),
               let key = PreparedTitle.Key(title: video.title, width: titleWidth, fontSize: fontSize, scale: scale),
               let image = PreparedTitle.image(for: key) {
                title.image = image
                title.isHidden = false
                fallbackTitle?.view.removeFromSuperview()
                fallbackTitle = nil
            } else {
                title.isHidden = true
                let content = AnyView(PreparedCardTitle(title: video.title, width: titleWidth)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                    .environment(\.displayScale, scale))
                if let fallbackTitle { fallbackTitle.rootView = content }
                else {
                    let host = UIHostingController(rootView: content)
                    host.view.backgroundColor = .clear
                    fallbackTitle = host
                    addSubview(host.view)
                }
            }
            let coverSize = CGSize(width: titleWidth + 16, height: (titleWidth + 16) / HomeCardLayout.coverAspectRatio)
            cover.load(video.secureCoverURL, size: coverSize, scale: scale)
            avatarTask?.cancel()
            avatar.load(video.secureAvatarURL, size: HomeCardLayout.avatarSize, scale: scale)
            if video.secureAvatarURL == nil, video.owner.mid > 0 {
                let resolveAvatar = resolveAvatar
                avatarTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    let url = await resolveAvatar(video.owner.mid)
                    guard !Task.isCancelled, let self, self.configuration == updated else { return }
                    self.avatar.load(url, size: HomeCardLayout.avatarSize, scale: scale)
                }
            }
            accessibilityLabel = "\(video.title)，\(video.owner.name)，\(video.stat.view.biliCountText)，\(video.formattedDuration)"
            isAccessibilityElement = true
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let width = bounds.width
            let coverHeight = width / HomeCardLayout.coverAspectRatio
            cover.frame = CGRect(x: 0, y: 0, width: width, height: coverHeight)
            gradient.frame = CGRect(x: 0, y: coverHeight - 52, width: width, height: 52)
            let titleFrame = CGRect(x: 8, y: coverHeight + 8, width: max(0, width - 16), height: titleHeight)
            title.frame = titleFrame
            fallbackTitle?.view.frame = titleFrame
            let ownerY = titleFrame.maxY + 7
            avatar.frame = CGRect(x: 8, y: ownerY, width: 16, height: 16)
            let ownerHeight = owner.font.lineHeight
            owner.frame = CGRect(x: 28, y: ownerY + (16 - ownerHeight) / 2,
                                 width: max(0, width - 36), height: ownerHeight)
            let labelHeight = playCount.font.lineHeight
            let labelY = coverHeight - 6 - labelHeight
            let iconSize = playIcon.image?.size ?? CGSize(width: 13, height: 11)
            playIcon.frame = CGRect(x: 8, y: labelY + (labelHeight - iconSize.height) / 2,
                                    width: iconSize.width, height: iconSize.height)
            if durationMeasurement?.availableWidth != width {
                durationMeasurement = (width, duration.sizeThatFits(CGSize(width: width, height: labelHeight)).width)
            }
            let durationWidth = durationMeasurement?.width ?? 0
            duration.frame = CGRect(x: width - 8 - durationWidth, y: labelY, width: durationWidth, height: labelHeight)
            playCount.frame = CGRect(x: playIcon.frame.maxX + 2, y: labelY,
                                     width: max(0, duration.frame.minX - playIcon.frame.maxX - 8), height: labelHeight)
        }
    }

    final class CardImageView: UIView {
        private let imageView = UIImageView()
        private let failure: UIImageView
        private var request: Request?
        private var task: Task<Void, Never>?
        private struct Request: Equatable { let url: URL?; let pixels: ImagePixelSize? }

        init(symbol: String = "photo") {
            failure = UIImageView(image: UIImage(systemName: symbol))
            super.init(frame: .zero)
            clipsToBounds = true
            imageView.contentMode = .scaleAspectFill
            failure.contentMode = .center
            failure.tintColor = .tertiaryLabel
            addSubview(imageView)
            addSubview(failure)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { task?.cancel() }
        override func layoutSubviews() {
            super.layoutSubviews()
            imageView.frame = bounds
            failure.frame = bounds
        }
        func load(_ url: URL?, size: CGSize, scale: CGFloat) {
            let request = Request(url: url, pixels: ImagePixelSize(points: size, scale: scale))
            guard self.request != request else { return }
            self.request = request
            task?.cancel()
            imageView.image = nil
            backgroundColor = .quaternaryLabel
            failure.isHidden = url != nil
            guard let url, let pixels = request.pixels else { return }
            if let cached = BiliImageMemoryCache.image(for: url, pixelSize: pixels) {
                imageView.image = cached
                backgroundColor = .clear
                return
            }
            task = Task { [weak self] in
                for attempt in 0..<3 {
                    do {
                        let image = try await BiliImageLoader.load(url, pixelSize: pixels)
                        guard !Task.isCancelled, let self, self.request == request else { return }
                        self.imageView.image = image
                        self.backgroundColor = .clear
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        if attempt == 2 { self?.failure.isHidden = false; return }
                        do { try await Task.sleep(for: .seconds(attempt == 0 ? 1 : 3)) } catch { return }
                    }
                }
            }
        }
    }
}
