import SwiftUI
import UIKit

/// Scroll persistence does not publish per-frame offsets back through SwiftUI.
@MainActor
final class VideoDescriptionScrollState {
    /// 离列表顶部滚了多远（不含顶部边距），顶部边距变化后仍能恢复到同一位置。
    var offset: CGFloat = 0
}

/// One vertical scroll surface: self-sizing introduction followed by recycled,
/// fixed-height related cards. No nested expanding list or per-scroll SwiftUI state.
struct VideoDescriptionComponent {
    let id: String
    let revision: [AnyHashable]
    let content: AnyView
    var introduction: VideoIntroductionCard? = nil
    var bottomSpacing: CGFloat = 0
    init<Content: View>(_ id: String, revision: [AnyHashable], @ViewBuilder content: () -> Content) {
        self.id = id
        self.revision = revision
        self.content = AnyView(content())
    }
    init(introduction: VideoIntroductionCard, bottomSpacing: CGFloat = 14) {
        id = "introduction"
        revision = [introduction.title, introduction.desc, AnyHashable(introduction.stat), introduction.pubdate, introduction.isExpanded]
        content = AnyView(EmptyView())
        self.introduction = introduction
        self.bottomSpacing = bottomSpacing
    }

}

struct VideoDescriptionCollection: UIViewRepresentable {
    let videos: [VideoSummary]
    let components: [VideoDescriptionComponent]
    let scrollState: VideoDescriptionScrollState
    let onSelect: (VideoSummary) -> Void
    let consume: (CGFloat) -> CGFloat
    let end: () -> Void
    let canConsume: (CGFloat) -> Bool
    let canContinue: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { section, _ in
            let height: NSCollectionLayoutDimension = section == 0 ? .estimated(100) : .absolute(110)
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: height))
            let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: height), subitems: [item])
            let result = NSCollectionLayoutSection(group: group)
            if section == 1 { result.contentInsets = .init(top: 0, leading: 16, bottom: 16, trailing: 16) }
            return result
        }
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.selfSizingInvalidation = .enabledIncludingConstraints
        view.bottomEdgeEffect.isHidden = true
        view.register(IntroductionCollectionCell.self, forCellWithReuseIdentifier: "introduction")
        view.register(DescriptionComponentCell.self, forCellWithReuseIdentifier: "header")
        view.register(PersistentFeedHostingCell.self, forCellWithReuseIdentifier: "video")
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.prefetchDataSource = context.coordinator
        view.addSubview(context.coordinator.collapse)
        context.coordinator.collapse.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let c = context.coordinator
        c.environment = context.environment
        c.onSelect = onSelect
        c.collapse.consume = consume
        c.collapse.end = end
        c.collapse.canConsume = canConsume
        c.collapse.canContinue = canContinue
        if !canContinue() { c.collapse.cancelMomentum() }
        if !canConsume(1), !canConsume(-1) { c.collapse.releaseScroll() }
        c.collapse.attach()
        let stateChanged = c.scrollState !== scrollState
        c.scrollState = scrollState
        let environmentChanged = c.typeSize != context.environment.dynamicTypeSize
            || c.theme != context.environment.appThemeColor
            || c.colorScheme != context.environment.colorScheme
        let rowsChanged = c.videos != videos || environmentChanged
        let previous = c.components
        let structureChanged = previous.map(\.id) != components.map(\.id)
        c.typeSize = context.environment.dynamicTypeSize
        c.theme = context.environment.appThemeColor
        c.colorScheme = context.environment.colorScheme
        c.videos = videos
        c.components = components
        if !c.initialized || stateChanged {
            c.initialized = true
            let savedOffset = scrollState.offset
            view.reloadData()
            view.layoutIfNeeded()
            view.setContentOffset(CGPoint(x: 0, y: savedOffset - view.adjustedContentInset.top), animated: false)
        } else {
            // Both section counts are already published to the data source.
            // Reload them atomically: separate reloads make UIKit validate one
            // new section against the other section's old item count.
            var reloaded = IndexSet()
            if rowsChanged { reloaded.insert(1) }
            if structureChanged { reloaded.insert(0) }
            if !reloaded.isEmpty {
                UIView.performWithoutAnimation { view.reloadSections(reloaded) }
            }
            if !structureChanged {
                // Only the changed component is rebound. UIKit owns the single
                // self-sizing transaction that moves every following cell.
                var nativeSizeChanged = false
                for index in components.indices where environmentChanged || previous[index].revision != components[index].revision {
                    if let cell = view.cellForItem(at: IndexPath(item: index, section: 0)) {
                        let previousHeight = (cell as? IntroductionCollectionCell)?.measuredHeight
                        let update = { c.configure(cell, at: index) }
                        if context.environment.accessibilityReduceMotion { UIView.performWithoutAnimation(update) }
                        else { update() }
                        if let previousHeight, let native = cell as? IntroductionCollectionCell,
                           previousHeight != native.measuredHeight { nativeSizeChanged = true }
                    }
                }
                if nativeSizeChanged {
                    let update = {
                        view.performBatchUpdates { view.collectionViewLayout.invalidateLayout() }
                    }
                    if context.environment.accessibilityReduceMotion { UIView.performWithoutAnimation(update) }
                    else { update() }
                }
            }
        }
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.collapse.detach()
        coordinator.prefetch.values.forEach { $0.cancel() }
        coordinator.preparations.values.forEach { $0.cancel() }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        var videos: [VideoSummary] = []
        var components: [VideoDescriptionComponent] = []
        var theme: Color?
        var colorScheme: ColorScheme?
        var environment = EnvironmentValues()
        var typeSize: DynamicTypeSize?
        var scrollState: VideoDescriptionScrollState?
        var initialized = false
        var onSelect: ((VideoSummary) -> Void)?
        let collapse = PausedVideoCollapseScroll.Observer()
        var prefetch: [String: Task<Void, Never>] = [:]
        var preparations: [ObjectIdentifier: Task<Void, Never>] = [:]

        func numberOfSections(in collectionView: UICollectionView) -> Int { 2 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            section == 0 ? components.count : videos.count
        }
        func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
            if path.section == 0 {
                let cell = view.dequeueReusableCell(withReuseIdentifier: components[path.item].introduction == nil ? "header" : "introduction", for: path)
                configure(cell, at: path.item)
                return cell
            }
            let video = videos[path.item]
            let cell = view.dequeueReusableCell(withReuseIdentifier: "video", for: path) as! PersistentFeedHostingCell
            let content = Button { [weak self] in self?.onSelect?(video) } label: {
                NativeRelatedVideoCard(video: video)
                    .frame(height: 110)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { WatchLaterMenuButton(aid: video.aid, bvid: video.bvid) }
            .environment(\.self, environment)
            cell.setContent(AnyView(content))
            return cell
        }
        func configure(_ cell: UICollectionViewCell, at index: Int) {
            let component = components[index]
            cell.accessibilityIdentifier = "description.\(component.id)"
            cell.clipsToBounds = true
            if let native = cell as? IntroductionCollectionCell, let introduction = component.introduction {
                native.configure(introduction, typeSize: environment.dynamicTypeSize, bottomSpacing: component.bottomSpacing)
                return
            }
            cell.contentConfiguration = UIHostingConfiguration {
                component.content
                    .environment(\.self, environment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transaction { $0.animation = nil }
            }.margins(.all, 0).minSize(height: 0)
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollState?.offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        }
        func collectionView(_ view: UICollectionView, prefetchItemsAt paths: [IndexPath]) {
            for path in paths where path.section == 1 && path.item < videos.count {
                let video = videos[path.item]
                guard prefetch[video.bvid] == nil else { continue }
                let scale = view.traitCollection.displayScale
                prefetch[video.bvid] = Task { [weak self] in
                    defer { self?.prefetch[video.bvid] = nil }
                    guard let url = video.secureCoverURL,
                          let pixels = ImagePixelSize(points: CGSize(width: 160, height: 90), scale: scale) else { return }
                    _ = try? await BiliImageLoader.load(url, pixelSize: pixels)
                }
            }
        }
        func collectionView(_ view: UICollectionView, cancelPrefetchingForItemsAt paths: [IndexPath]) {
            for path in paths where path.section == 1 && path.item < videos.count {
                prefetch.removeValue(forKey: videos[path.item].bvid)?.cancel()
            }
        }
        func collectionView(_ view: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt path: IndexPath) {
            guard path.section == 1, path.item < videos.count else { return }
            let video = videos[path.item]
            cell.accessibilityIdentifier = "related.\(video.bvid)"
            let key = ObjectIdentifier(cell)
            preparations.removeValue(forKey: key)?.cancel()
            preparations[key] = Task {
                await VideoPreparationCache.shared.prefetchWhenSettled(bvid: video.bvid, cid: video.cid)
            }
        }
        func collectionView(_ view: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt path: IndexPath) {
            preparations.removeValue(forKey: ObjectIdentifier(cell))?.cancel()
        }
    }
}

struct NativeRelatedVideoCard: UIViewRepresentable {
    let video: VideoSummary
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale
    func makeUIView(context: Context) -> CardView { CardView() }
    func updateUIView(_ view: CardView, context: Context) { view.configure(video, typeSize: typeSize, scale: scale) }

    final class CardView: UIView {
        private let cover = NativeHomeVideoCard.CardImageView()
        private let title = UILabel()
        private let owner = UILabel()
        private let metadata = UILabel()
        private let separator = UIView()
        private var video: VideoSummary?
        private var typeSize: DynamicTypeSize?
        private var scale: CGFloat = 0
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            for view in [cover, title, owner, metadata, separator] { addSubview(view) }
            // 与首页卡片封面同一圆角规格。
            cover.layer.cornerRadius = HomeCardLayout.coverCornerRadius
            cover.layer.cornerCurve = .continuous
            title.numberOfLines = 2
            title.textColor = .label
            owner.textColor = .secondaryLabel
            metadata.textColor = .tertiaryLabel
            separator.backgroundColor = .separator
            isAccessibilityElement = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ video: VideoSummary, typeSize: DynamicTypeSize, scale: CGFloat) {
            guard self.video != video || self.typeSize != typeSize || self.scale != scale else { return }
            if self.typeSize != typeSize {
                let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
                let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
                title.font = .systemFont(ofSize: font.pointSize, weight: .medium)
                owner.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
                metadata.font = .preferredFont(forTextStyle: .caption2, compatibleWith: traits)
            }
            self.video = video; self.typeSize = typeSize; self.scale = scale
            title.text = video.title
            owner.text = video.owner.name
            let text = NSMutableAttributedString()
            for (symbol, value) in [("play.rectangle", video.stat.view.biliCountText), ("clock", video.formattedDuration)] {
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: metadata.font.pointSize))?
                    .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal)
                let size = metadata.font.pointSize
                attachment.bounds = CGRect(x: 0, y: -1, width: size, height: size)
                text.append(NSAttributedString(attachment: attachment))
                text.append(NSAttributedString(string: " \(value)   "))
            }
            metadata.attributedText = text
            cover.load(video.secureCoverURL, size: CGSize(width: 160, height: 90), scale: scale)
            accessibilityLabel = "\(video.title)，\(video.owner.name)，\(video.stat.view.biliCountText)次播放，\(video.formattedDuration)"
            setNeedsLayout()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            cover.frame = CGRect(x: 0, y: 10, width: 160, height: 90)
            let x: CGFloat = 170, width = max(0, bounds.width - 170)
            title.frame = CGRect(x: x, y: 10, width: width, height: min(52, ceil(title.font.lineHeight * 2)))
            owner.frame = CGRect(x: x, y: 64, width: width, height: 18)
            metadata.frame = CGRect(x: x, y: 83, width: width, height: 17)
            separator.frame = CGRect(x: 0, y: bounds.height - 1 / max(1, scale), width: bounds.width, height: 1 / max(1, scale))
        }
    }
}

/// The introduction bypasses UIHostingConfiguration entirely. Its title has a
/// stable native layout; only the cell height and following rows interpolate.
final class IntroductionCollectionCell: UICollectionViewCell {
    let introductionView = NativeVideoIntroductionCard.IntroductionView()
    private var bottomSpacing: CGFloat = 14
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(introductionView)
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ card: VideoIntroductionCard, typeSize: DynamicTypeSize, bottomSpacing: CGFloat) {
        self.bottomSpacing = bottomSpacing
        introductionView.configure(title: card.title,
            metadata: NativeVideoIntroductionCard.metadataText(stat: card.stat, pubdate: card.pubdate),
            description: card.desc, expanded: card.isExpanded, typeSize: typeSize)
        introductionView.onToggle = { [weak self] in
            card.isExpanded.toggle()
            guard let self else { return }
            self.configure(card, typeSize: typeSize, bottomSpacing: bottomSpacing)
            guard let list = self.superview as? UICollectionView else { return }
            let update = {
                list.performBatchUpdates { list.collectionViewLayout.invalidateLayout() }
            }
            if UIAccessibility.isReduceMotionEnabled { UIView.performWithoutAnimation(update) }
            else { update() }
        }
        setNeedsLayout()
    }
    var measuredHeight: CGFloat { introductionView.height(for: max(1, bounds.width - 32)) + bottomSpacing }
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = introductionView.height(for: max(1, attributes.size.width - 32)) + bottomSpacing
        return attributes
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        introductionView.frame = CGRect(x: 16, y: 0, width: max(1, bounds.width - 32), height: max(0, bounds.height - bottomSpacing))
        introductionView.layoutIfNeeded()
    }
}

/// UICollectionView animates the cell's bounds to reveal more content. The
/// hosting surface must already have its final bounds: animating its backing
/// surface too shifts SwiftUI's rendered text even when layout coordinates stay
/// unchanged. Only the outer cell interpolates; its clipping reveals the body.
final class DescriptionComponentCell: UICollectionViewCell {
    override func layoutSubviews() {
        UIView.performWithoutAnimation {
            super.layoutSubviews()
            func settle(_ surface: UIView) {
                for key in ["position", "bounds", "bounds.size"] { surface.layer.removeAnimation(forKey: key) }
                surface.subviews.forEach(settle)
            }
            subviews.forEach(settle)
        }
    }
}

/// Observes list data without publishing per-frame scroll offsets.
struct VideoDescriptionContent: View {
    let store: NowPlayingStore
    let viewModel: VideoDetailViewModel?
    let components: [VideoDescriptionComponent]
    let consume: (CGFloat) -> CGFloat
    let end: () -> Void
    let canConsume: (CGFloat) -> Bool
    let canContinue: () -> Bool
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    var body: some View {
        let all = viewModel?.related ?? []
        let videos = all.hidingKnownPortraitVideos(hidesPortraitVideos)
        let loading = viewModel?.isLoadingRelated == true || all.hasPendingVideoDimensions(hidesPortraitVideos)
        // 与原生详情页一样用分区标题组织内容，相关视频不直接接在操作栏下面。
        let header = VideoDescriptionComponent("relatedHeader", revision: []) {
            Text("相关视频")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 2)
        }
        let rows = components + [header] + (videos.isEmpty ? [VideoDescriptionComponent("status", revision: [loading, all.isEmpty]) {
            if loading { ProgressView().padding(24) }
            else {
                Text(all.isEmpty ? "暂时没有相关视频" : "相关视频已被内容过滤设置隐藏")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
            }
        }] : [])
        VideoDescriptionCollection(videos: videos, components: rows,
                                   scrollState: store.descriptionScroll, onSelect: store.openRelated,
                                   consume: consume, end: end, canConsume: canConsume, canContinue: canContinue)
            // SwiftUI 会把 UIKit 列表摆在安全区内，顶部栏下面就只剩页面底色；铺进去之后内容才能
            // 从选择器下滑过，由系统给出与评论页一致的顶部模糊。被覆盖的高度由 UIKit 按安全区
            // 自动计入顶部边距，不用另外补。
            .ignoresSafeArea(.container, edges: .top)
            .resolvePortraitVideos(all)
    }
}
