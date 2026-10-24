#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// Scroll persistence does not publish per-frame offsets back through SwiftUI.
@MainActor
final class VideoDescriptionScrollState {
    /// 离列表顶部滚了多远（不含顶部边距），顶部边距变化后仍能恢复到同一位置。
    var offset: CGFloat = 0
}

/// One vertical scroll surface: self-sizing introduction followed by recycled,
/// font-sized related cards. No nested expanding list or per-scroll SwiftUI state.
struct VideoDescriptionComponent {
    let id: String
    let revision: [AnyHashable]
    let content: AnyView
    var introduction: VideoIntroductionCard? = nil
    var bottomSpacing: CGFloat = 0
    init<Content: View>(_ id: String, revision: [AnyHashable], bottomSpacing: CGFloat = 0,
                        @ViewBuilder content: () -> Content) {
        self.id = id
        self.revision = revision
        self.content = AnyView(content())
        self.bottomSpacing = bottomSpacing
    }
    @MainActor init(introduction: VideoIntroductionCard, bottomSpacing: CGFloat = 12) {
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
    var footers: [VideoDescriptionComponent] = []
    let scrollState: VideoDescriptionScrollState
    let onSelect: (VideoSummary) -> Void
    var onReachEnd: () -> Void = {}
    let consume: (CGFloat) -> CGFloat
    let end: () -> Void
    let canConsume: (CGFloat) -> Bool
    let canContinue: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { [weak coordinator = context.coordinator] section, _ in
            let rowHeight = NativeRelatedVideoCard.rowHeight(typeSize: coordinator?.typeSize ?? .large)
            let height: NSCollectionLayoutDimension = section == 1 ? .absolute(rowHeight) : .estimated(100)
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
        c.onReachEnd = onReachEnd
        c.collapse.consume = consume
        c.collapse.end = end
        c.collapse.canConsume = canConsume
        let stateChanged = c.scrollState !== scrollState
        c.scrollState = scrollState
        let typeSizeChanged = c.typeSize != context.environment.dynamicTypeSize
        let environmentChanged = typeSizeChanged
            || c.theme != context.environment.appThemeColor
            || c.colorScheme != context.environment.colorScheme
        let rowsChanged = c.videos != videos || environmentChanged
        let footersChanged = c.footers.map(\.id) != footers.map(\.id) || c.footers.map(\.revision) != footers.map(\.revision) || environmentChanged
        let previous = c.components
        let structureChanged = previous.map(\.id) != components.map(\.id)
        c.typeSize = context.environment.dynamicTypeSize
        c.theme = context.environment.appThemeColor
        c.colorScheme = context.environment.colorScheme
        c.videos = videos
        c.components = components
        c.footers = footers
        if typeSizeChanged { view.collectionViewLayout.invalidateLayout() }
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
            if footersChanged { reloaded.insert(2) }
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
        c.collapse.configure(context.environment.videoScrollContext, page: .description, ownsInsets: true)
        c.collapse.attach()
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.collapse.detach()
        coordinator.prefetch.values.forEach { $0.cancel() }
        coordinator.preparations.values.forEach { $0.cancel() }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        var videos: [VideoSummary] = []
        var components: [VideoDescriptionComponent] = []
        var footers: [VideoDescriptionComponent] = []
        var theme: Color?
        var colorScheme: ColorScheme?
        var environment = EnvironmentValues()
        var typeSize: DynamicTypeSize?
        var scrollState: VideoDescriptionScrollState?
        var initialized = false
        var onSelect: ((VideoSummary) -> Void)?
        var onReachEnd: (() -> Void)?
        let collapse = PausedVideoCollapseScroll.Observer()
        var prefetch: [String: Task<Void, Never>] = [:]
        var preparations: [ObjectIdentifier: Task<Void, Never>] = [:]

        func numberOfSections(in collectionView: UICollectionView) -> Int { 3 }
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            section == 0 ? components.count : section == 1 ? videos.count : footers.count
        }
        func collectionView(_ view: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
            if path.section == 2 {
                let cell = view.dequeueReusableCell(withReuseIdentifier: "header", for: path)
                configure(cell, component: footers[path.item])
                return cell
            }
            if path.section == 0 {
                let cell = view.dequeueReusableCell(withReuseIdentifier: components[path.item].introduction == nil ? "header" : "introduction", for: path)
                configure(cell, at: path.item)
                return cell
            }
            let video = videos[path.item]
            let cell = view.dequeueReusableCell(withReuseIdentifier: "video", for: path) as! PersistentFeedHostingCell
            let content = Button { [weak self] in self?.onSelect?(video) } label: {
                NativeRelatedVideoCard(video: video)
                    .frame(height: NativeRelatedVideoCard.rowHeight(typeSize: environment.dynamicTypeSize))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { WatchLaterMenuButton(aid: video.aid, bvid: video.bvid) }
            .environment(\.self, environment)
            cell.setContent(AnyView(content))
            return cell
        }
        func configure(_ cell: UICollectionViewCell, at index: Int) {
            configure(cell, component: components[index])
        }
        func configure(_ cell: UICollectionViewCell, component: VideoDescriptionComponent) {
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
            scrollState?.offset = collapse.logicalOffset(for: scrollView)
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
            if path.item >= videos.count - 3 { onReachEnd?() }
            let video = videos[path.item]
            cell.accessibilityIdentifier = "related.\(video.bvid)"
            let key = ObjectIdentifier(cell)
            preparations.removeValue(forKey: key)?.cancel()
            let preparation = environment.videoPreparation
            preparations[key] = Task {
                await preparation.prefetchWhenSettled(bvid: video.bvid, cid: video.cid)
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

    /// 卡片上下各留 6；卡片之间不画分隔线，相邻两张封面靠这两份留白隔开 12。
    static let verticalInset: CGFloat = 6
    /// UP 主与播放数据相对主文字色的强度。
    static let secondaryTextColor = UIColor.label.withAlphaComponent(0.6)

    static func rowHeight(typeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let titleHeight = ceil(AppFont.preferred(.subheadline, traits: traits).lineHeight * 2)
        let ownerHeight = ceil(AppFont.preferred(.caption1, traits: traits).lineHeight)
        let metadataHeight = ceil(AppFont.preferred(.caption1, traits: traits).lineHeight)
        return max(90 + 2 * verticalInset,
                   max(60, verticalInset + titleHeight + 4) + max(18, ownerHeight) + 1 + max(17, metadataHeight) + verticalInset)
    }

    final class CardView: UIView {
        private let cover = NativeHomeVideoCard.CardImageView()
        private let title = UILabel()
        private let owner = UILabel()
        private let metadata = UILabel()
        private var video: VideoSummary?
        private var typeSize: DynamicTypeSize?
        private var scale: CGFloat = 0
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            for view in [cover, title, owner, metadata] { addSubview(view) }
            // 与首页卡片封面同一圆角规格。
            cover.layer.cornerRadius = HomeCardLayout.coverCornerRadius
            cover.layer.cornerCurve = .continuous
            title.numberOfLines = 2
            title.textColor = .label
            owner.textColor = NativeRelatedVideoCard.secondaryTextColor
            metadata.textColor = NativeRelatedVideoCard.secondaryTextColor
            isAccessibilityElement = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(_ video: VideoSummary, typeSize: DynamicTypeSize, scale: CGFloat) {
            guard self.video != video || self.typeSize != typeSize || self.scale != scale else { return }
            if self.typeSize != typeSize {
                let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
                let font = AppFont.preferred(.subheadline, traits: traits)
                title.font = AppFont.uiFont(ofSize: font.pointSize, weight: .medium)
                owner.font = AppFont.preferred(.caption1, traits: traits)
                metadata.font = AppFont.preferred(.caption1, traits: traits)
            }
            self.video = video; self.typeSize = typeSize; self.scale = scale
            title.text = video.title
            owner.text = video.owner.name
            let text = NSMutableAttributedString()
            for (symbol, value) in [("play.rectangle", video.stat.view.biliCountText), ("clock", video.formattedDuration)] {
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: metadata.font.pointSize))?
                    .withTintColor(NativeRelatedVideoCard.secondaryTextColor, renderingMode: .alwaysOriginal)
                let size = metadata.font.pointSize
                attachment.bounds = CGRect(x: 0, y: -1, width: size, height: size)
                text.append(NSAttributedString(attachment: attachment))
                text.append(NSAttributedString(string: " \(value)   "))
            }
            metadata.attributedText = text
            cover.load(video.secureCoverURL, size: CGSize(width: 160, height: 90), scale: scale)
            accessibilityLabel = String(localized: "\(video.title)，\(video.owner.name)，\(video.stat.view.biliCountText)次播放，\(video.formattedDuration)")
            setNeedsLayout()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = NativeRelatedVideoCard.verticalInset
            cover.frame = CGRect(x: 0, y: inset, width: 160, height: 90)
            let x: CGFloat = 170, width = max(0, bounds.width - 170)
            title.frame = CGRect(x: x, y: inset, width: width, height: ceil(title.font.lineHeight * 2))
            owner.frame = CGRect(x: x, y: max(60, title.frame.maxY + 4), width: width,
                                 height: max(18, ceil(owner.font.lineHeight)))
            metadata.frame = CGRect(x: x, y: owner.frame.maxY + 1, width: width,
                                    height: max(17, ceil(metadata.font.lineHeight)))
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
            @MainActor func settle(_ surface: UIView) {
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
    @Environment(\.videoFiltering) private var filtering
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    var body: some View {
        let all = viewModel?.related ?? []
        let videos = all.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: filtering)
        let relatedError = viewModel?.relatedErrorMessage
        let loading = viewModel?.isLoadingRelated == true || all.hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering)
        // 相关视频不加分区标题，直接接在操作栏（或合集、分P 入口）下面，间距由上方组件自带。
        let status = (videos.isEmpty || relatedError != nil ? [VideoDescriptionComponent("status", revision: [loading, all.isEmpty, relatedError]) {
            if loading { ProgressView().padding(24) }
            else if let relatedError {
                VStack(spacing: 12) {
                    Text(relatedError).font(.app(.subheadline)).foregroundStyle(.secondary)
                    Button("重试") { Task { await viewModel?.retryRelated() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("related.retry")
                }
                .padding(16)
            } else {
                Text(all.isEmpty ? "暂时没有相关视频" : "相关视频已被内容过滤设置隐藏")
                    .font(.app(.subheadline)).foregroundStyle(.secondary).padding(16)
            }
        }] : [])
        let rows = components + (videos.isEmpty ? status : [])
        VideoDescriptionCollection(videos: videos, components: rows, footers: videos.isEmpty ? [] : status,
                                   scrollState: store.descriptionScroll, onSelect: store.openRelated,
                                   onReachEnd: { Task { await store.detailViewModel?.loadMoreRelated() } },
                                   consume: consume, end: end, canConsume: canConsume, canContinue: canContinue)
            // SwiftUI 会把 UIKit 列表摆在安全区内，顶部栏下面就只剩页面底色；铺进去之后内容才能
            // 从选择器下滑过，由系统给出与评论页一致的顶部模糊。被覆盖的高度由 UIKit 按安全区
            // 自动计入顶部边距，不用另外补。
            .ignoresSafeArea(.container, edges: .top)
            .resolvePortraitVideos(all)
            .environment(\.videoPreparation, store.preparationCache)
    }
}
