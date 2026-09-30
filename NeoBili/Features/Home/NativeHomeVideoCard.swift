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
        /// 推荐理由小标签（「已关注」「4万点赞」），放在头像和 UP 主名字之间。
        private let badge = UILabel()
        private var badgeWidth: CGFloat = 0
        private let playCount = UILabel()
        private let duration = UILabel()
        private let playIcon = UIImageView()
        /// 弹幕数，和 PiliPlus 一样跟在播放数后面；直播、图文卡不显示。
        private let danmakuCount = UILabel()
        private let danmakuIcon = UIImageView()
        private var playCountWidth: CGFloat = 0
        private var danmakuWidth: CGFloat = 0
        private let gradient = CAGradientLayer()
        /// 不能预排版的标题（含 emoji，或排版参数还没量好）用它显示。
        private let fallbackTitle = UILabel()
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
            for view in [title, fallbackTitle, owner, badge, playCount, duration, playIcon, danmakuCount, danmakuIcon, avatar] {
                addSubview(view)
            }
            danmakuCount.textColor = .white
            danmakuIcon.tintColor = .white
            danmakuIcon.contentMode = .scaleAspectFit
            badge.textColor = .secondaryLabel
            badge.backgroundColor = .tertiarySystemFill
            badge.textAlignment = .center
            badge.layer.cornerRadius = 3
            badge.layer.cornerCurve = .continuous
            badge.clipsToBounds = true
            badge.isHidden = true
            title.contentMode = .topLeft
            title.tintColor = .label
            fallbackTitle.numberOfLines = 2
            fallbackTitle.lineBreakMode = .byTruncatingTail
            fallbackTitle.textColor = .label
            fallbackTitle.isHidden = true
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
                badge.font = small
                let semibold = UIFont.systemFont(ofSize: small.pointSize, weight: .semibold)
                playCount.font = semibold
                danmakuCount.font = semibold
                danmakuIcon.image = UIImage(systemName: "text.bubble", withConfiguration: UIImage.SymbolConfiguration(font: semibold))
                duration.font = semibold
                playIcon.image = UIImage(systemName: "play.rectangle", withConfiguration: UIImage.SymbolConfiguration(font: semibold))
                durationMeasurement = nil
                badge.text = nil
            }
            playCount.text = video.stat.view.biliCountText
            // 图文卡没有播放数时不画这一组。
            let hidesCount = video.recommendationTarget != nil && video.stat.view == 0
            playCount.isHidden = hidesCount
            playIcon.isHidden = hidesCount
            playCountWidth = ceil(playCount.intrinsicContentSize.width)
            danmakuCount.text = video.stat.danmaku.biliCountText
            let hidesDanmaku = video.recommendationTarget != nil
            danmakuCount.isHidden = hidesDanmaku
            danmakuIcon.isHidden = hidesDanmaku
            danmakuWidth = hidesDanmaku ? 0 : ceil(danmakuCount.intrinsicContentSize.width)
            let durationText = video.coverCornerText
            if duration.text != durationText {
                duration.text = durationText
                durationMeasurement = nil
            }
            // 网页推荐带发布时间，和 PiliPlus 一样显示出来；App 推荐没有这个字段。
            owner.text = video.isWebRecommendation && video.pubdate > 0
                ? "\(video.owner.name) · \(video.pubdate.biliRelativeTimeText)" : video.owner.name
            if badge.text != video.recommendationBadge {
                badge.text = video.recommendationBadge
                badge.isHidden = video.recommendationBadge == nil
                badgeWidth = video.recommendationBadge == nil ? 0 : ceil(badge.intrinsicContentSize.width) + 8
            }
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
                fallbackTitle.isHidden = true
                fallbackTitle.attributedText = nil
            } else {
                title.isHidden = true
                fallbackTitle.isHidden = false
                if let metrics {
                    fallbackTitle.attributedText = PreparedTitle.fixedLineHeightTitle(video.title, fontSize: fontSize, metrics: metrics)
                } else {
                    fallbackTitle.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                    fallbackTitle.text = video.title
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
            accessibilityLabel = "\(video.title)，\(video.recommendationBadge.map { "\($0)，" } ?? "")\(video.owner.name)，\(video.stat.view.biliCountText)，\(video.coverCornerText)"
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
            // UILabel 会把文字在自身高度内垂直居中；按实际内容高度贴顶放置，和标题图一致。
            let fallbackHeight = min(titleHeight, fallbackTitle.sizeThatFits(titleFrame.size).height)
            fallbackTitle.frame = CGRect(origin: titleFrame.origin, size: CGSize(width: titleFrame.width, height: fallbackHeight))
            let ownerY = titleFrame.maxY + 7
            avatar.frame = CGRect(x: 8, y: ownerY, width: 16, height: 16)
            let ownerHeight = owner.font.lineHeight
            // 标签最多占这一行的一半，UP 主名字始终留得下。
            let shownBadgeWidth = badge.isHidden ? 0 : min(badgeWidth, max(0, (width - 36) / 2))
            badge.frame = CGRect(x: 28, y: ownerY + (16 - ownerHeight - 2) / 2,
                                 width: shownBadgeWidth, height: ownerHeight + 2)
            let ownerX = shownBadgeWidth > 0 ? badge.frame.maxX + 4 : 28
            owner.frame = CGRect(x: ownerX, y: ownerY + (16 - ownerHeight) / 2,
                                 width: max(0, width - 8 - ownerX), height: ownerHeight)
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
            let statsLimit = duration.frame.minX - 8
            playCount.frame = CGRect(x: playIcon.frame.maxX + 2, y: labelY,
                                     width: max(0, min(playCountWidth, statsLimit - playIcon.frame.maxX - 2)), height: labelHeight)
            let danmakuIconSize = danmakuIcon.image?.size ?? iconSize
            let danmakuIconX = playCount.frame.maxX + 8
            // 空间不够（大字号、窄屏）时宁可不显示弹幕数，也不和播放数、时长挤在一起。
            let fitsDanmaku = danmakuIconX + danmakuIconSize.width + 2 + danmakuWidth <= statsLimit
            danmakuIcon.alpha = fitsDanmaku ? 1 : 0
            danmakuCount.alpha = fitsDanmaku ? 1 : 0
            danmakuIcon.frame = CGRect(x: danmakuIconX, y: labelY + (labelHeight - danmakuIconSize.height) / 2,
                                       width: danmakuIconSize.width, height: danmakuIconSize.height)
            danmakuCount.frame = CGRect(x: danmakuIcon.frame.maxX + 2, y: labelY, width: danmakuWidth, height: labelHeight)
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
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                task?.cancel()
                task = nil
            } else if imageView.image == nil, task == nil, let request {
                start(request)
            }
        }
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
            task = nil
            imageView.image = nil
            backgroundColor = .quaternaryLabel
            failure.isHidden = url != nil
            start(request)
        }
        private func start(_ request: Request) {
            guard let url = request.url, let pixels = request.pixels else { return }
            failure.isHidden = true
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
                        self.failure.isHidden = true
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
