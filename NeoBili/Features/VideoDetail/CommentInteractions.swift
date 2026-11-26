import NeoBiliDomain
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var commentMenuRegistry: CommentMenuRegistry?
    @Entry var commentCardAnimations = CardAnimationSettings.defaultValue
    @Entry var openCommentAuthor: EnvironmentAction<CommentMember>? = nil
}

extension View {
    func commentAuthorHost() -> some View { modifier(CommentAuthorHost()) }
    func commentActions(comment: Comment, root: Comment?, surface: UIColor, isDeleting: Bool) -> some View {
        CommentMenuSource(content: self, target: CommentMenuTarget(comment: comment, root: root, isDeleting: isDeleting),
                          surface: surface)
    }

    func commentMenuHost(viewModel: CommentsViewModel, nativeList: Bool = false) -> some View {
        modifier(CommentMenuHost(viewModel: viewModel, nativeList: nativeList))
    }
}

private struct CommentAuthorHost: ViewModifier {
    @State private var author: FollowedUp?
    @State private var openAction = EnvironmentAction<CommentMember> { _ in }

    func body(content: Content) -> some View {
        content
            .environment(\.openCommentAuthor, openAction)
            .onAppear {
                openAction.setHandler { [destination = $author] member in
                    guard let mid = member.mid else { return }
                    destination.wrappedValue = FollowedUp(mid: mid, uname: member.uname, face: member.avatar, hasUpdate: false)
                }
            }
            .navigationDestination(item: $author) { up in SpaceView(up: up) }
    }
}

struct CommentMenuTarget: Hashable {
    let comment: Comment
    let root: Comment?
    let isDeleting: Bool
}

struct CommentMenuCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var destructive = false
    var disabled = false
    let perform: () -> Void

    @MainActor func action() -> UIAction {
        var attributes: UIMenuElement.Attributes = destructive ? .destructive : []
        if disabled { attributes.insert(.disabled) }
        let action = UIAction(title: title, image: UIImage(systemName: symbol), attributes: attributes) { _ in perform() }
        action.accessibilityIdentifier = id
        return action
    }
}

@MainActor @Observable final class CommentMenuRegistry {
    let markers = ResolvedMenuRegistry<CommentMenuTarget>()
    var commands: (CommentMenuTarget) -> [CommentMenuCommand] = { _ in [] }

    init() {
        markers.menu = { [weak self] target in
            UIMenu(children: self?.commands(target).map { $0.action() } ?? [])
        }
    }
}

private struct CommentMenuSource<Content: View>: View {
    let content: Content
    let target: CommentMenuTarget
    let surface: UIColor
    @Environment(\.commentMenuRegistry) private var registry

    var body: some View {
        content
            .background(Color(uiColor: surface), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .background {
                if let registry {
                    ResolvedMenuMarker(id: target, registry: registry.markers, cornerRadius: 4, previewBackground: surface) { values in
                        let elevated = UIColor { traits in
                            surface.resolvedColor(with: traits.modifyingTraits { $0.userInterfaceLevel = .elevated })
                        }
                        return UIHostingConfiguration {
                            content.environment(\.self, values).background(Color(uiColor: elevated))
                        }.margins(.all, 0).makeContentView()
                    }
                }
            }
            .accessibilityActions {
                ForEach(registry?.commands(target) ?? []) { command in
                    Button(command.title, action: command.perform)
                        .disabled(command.disabled)
                        .accessibilityIdentifier(command.id)
                }
            }
    }
}

private struct CommentMenuHost: ViewModifier {
    let viewModel: CommentsViewModel
    let nativeList: Bool
    @Environment(AccountStore.self) private var account
    @State private var registry = CommentMenuRegistry()
    private struct PendingDeletion {
        let model: CommentsViewModel
        let target: CommentsViewModel.Deletion
        let accountSession: UUID
    }
    @State private var deletion: PendingDeletion?

    func body(content: Content) -> some View {
        content
            .environment(\.commentMenuRegistry, registry)
            .background {
                if !nativeList { ResolvedMenuInstaller(registry: registry.markers, menu: registry.markers.menu) }
            }
            .onAppear { registry.commands = commands }
            .onChange(of: ObjectIdentifier(viewModel)) {
                deletion = nil
                registry.commands = commands
            }
            .onDisappear { registry.commands = { _ in [] } }
            .alert("删除这条评论？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                   presenting: deletion) { target in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    guard target.model === viewModel, target.accountSession == account.sessionID else { return }
                    Task { await target.model.delete(target.target, accountID: account.accountID, isLoggedIn: account.isLoggedIn) }
                }
            } message: { _ in Text("删除后无法恢复。") }
            .onChange(of: account.sessionID) { deletion = nil }
    }

    private func commands(_ target: CommentMenuTarget) -> [CommentMenuCommand] {
        let comment = target.comment
        let copy = CommentMenuCommand(id: "comment.copy.\(comment.id)", title: String(localized: "复制全文"),
                                      symbol: "doc.on.doc") {
            UIPasteboard.general.string = comment.message
            viewModel.actionMessage = String(localized: "已复制全文")
        }
        guard viewModel.canDelete(comment, accountID: account.accountID, isLoggedIn: account.isLoggedIn)
        else { return [copy] }
        let session = account.sessionID
        let remove = CommentMenuCommand(id: "comment.delete.\(comment.id)", title: String(localized: "删除评论"),
                                        symbol: "trash", destructive: true, disabled: target.isDeleting) {
            guard account.sessionID == session,
                  let request = viewModel.deletion(for: comment, root: target.root, accountID: account.accountID,
                                                   isLoggedIn: account.isLoggedIn) else { return }
            deletion = PendingDeletion(model: viewModel, target: request, accountSession: session)
        }
        return [copy, remove]
    }
}

struct CommentUPBadge: View {
    @Environment(\.appThemeColor) private var color
    var body: some View {
        Text("UP 主")
            .font(.app(.caption2, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.65), lineWidth: 0.7) }
            .fixedSize()
    }

    /// One small bitmap per text-size/theme combination keeps the same badge inside
    /// the existing flowing Text paragraph without rendering it on every scroll.
    @MainActor private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    @MainActor static func inlineImage(size: DynamicTypeSize, scale: CGFloat, color: Color, scheme: ColorScheme) -> Image? {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        let key = "\(size)|\(scale)|\(resolved)" as NSString
        if let cached = images.object(forKey: key) { return Image(uiImage: cached) }
        let renderer = ImageRenderer(content: CommentUPBadge()
            .environment(\.dynamicTypeSize, size).environment(\.appThemeColor, Color(uiColor: resolved)))
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        images.setObject(image, forKey: key)
        return Image(uiImage: image)
    }
}

struct CommentUPInteraction: View {
    let comment: Comment
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                                              : AnyLayout(HStackLayout(spacing: 8))
        layout { labels }
        .font(.app(.caption2)).foregroundStyle(.secondary)
    }
    @ViewBuilder private var labels: some View {
        if comment.upAction?.like == true { Label("UP 主觉得很赞", systemImage: "hand.thumbsup") }
        if comment.upAction?.reply == true { Label("UP 主回复过", systemImage: "bubble.left") }
    }
}

extension CommentSort {
    var title: String { self == .hot ? String(localized: "热门") : String(localized: "最新") }
}

struct CommentSortHeader: View {
    let viewModel: CommentsViewModel
    static let scrollID = "comment-list-top"
    private static let topInset: CGFloat = 8
    private static let bottomInset: CGFloat = 2
    private static let menuHeight: CGFloat = 44
    static let minimumHeight = topInset + menuHeight + bottomInset
    var body: some View {
        HStack(spacing: 10) {
            Text(viewModel.displayCount > 0 ? String(localized: "评论 \(viewModel.displayCount)") : String(localized: "评论"))
                .font(.app(.subheadline, weight: .semibold))
            Spacer(minLength: 4)
            if viewModel.isRefreshing { ProgressView().controlSize(.small) }
            Menu {
                Picker("评论排序", selection: Binding(get: { viewModel.sort }, set: { sort in
                    Task { await viewModel.changeSort(to: sort) }
                })) {
                    ForEach(CommentSort.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.sort.title)
                    Image(systemName: "chevron.down").font(.app(.caption2, weight: .semibold))
                }
                .font(.app(.subheadline)).foregroundStyle(Color.secondary).frame(minHeight: Self.menuHeight)
            }
            .accessibilityLabel(String(localized: "评论排序，\(viewModel.sort.title)"))
            .accessibilityIdentifier("comment.sort")
        }
        .padding(.horizontal, CommentLayout.pageHorizontalInset)
        .padding(.top, Self.topInset).padding(.bottom, Self.bottomInset)
        .id(Self.scrollID)
    }
}
