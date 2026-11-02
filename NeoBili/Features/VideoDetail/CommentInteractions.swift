#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var openCommentAuthor: EnvironmentAction<CommentMember>? = nil
}

extension View {
    func commentAuthorHost() -> some View { modifier(CommentAuthorHost()) }
    func commentActions(comment: Comment, root: Comment? = nil, viewModel: CommentsViewModel) -> some View {
        modifier(CommentActions(comment: comment, root: root, viewModel: viewModel))
    }
}

private struct CommentAuthorHost: ViewModifier {
    @Environment(\.applicationServices) private var services
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
            .navigationDestination(item: $author) { up in SpaceView(up: up, services: services) }
    }
}

private struct CommentActions: ViewModifier {
    let comment: Comment
    let root: Comment?
    let viewModel: CommentsViewModel
    @Environment(AccountStore.self) private var account
    @State private var deletion: CommentsViewModel.Deletion?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("复制全文", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = comment.message
                    viewModel.actionMessage = String(localized: "已复制全文")
                }
                .accessibilityIdentifier("comment.copy.\(comment.id)")
                if viewModel.canDelete(comment, accountID: account.accountID, isLoggedIn: account.isLoggedIn) {
                    Button("删除评论", systemImage: "trash", role: .destructive) {
                        deletion = viewModel.deletion(for: comment, root: root, accountID: account.accountID, isLoggedIn: account.isLoggedIn)
                    }
                    .disabled(viewModel.deletingIDs.contains(comment.id))
                    .accessibilityIdentifier("comment.delete.\(comment.id)")
                }
            }
            .alert("删除这条评论？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                   presenting: deletion) { target in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    Task { await viewModel.delete(target, accountID: account.accountID, isLoggedIn: account.isLoggedIn) }
                }
            } message: { _ in Text("删除后无法恢复。") }
            .onChange(of: account.sessionID) { deletion = nil }
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
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { labels }
            VStack(alignment: .leading, spacing: 4) { labels }
        }
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
                .font(.app(.subheadline)).foregroundStyle(Color.secondary).frame(minHeight: 44)
            }
            .accessibilityLabel(String(localized: "评论排序，\(viewModel.sort.title)"))
            .accessibilityIdentifier("comment.sort")
        }
        .padding(.horizontal, CommentLayout.pageHorizontalInset)
        .padding(.top, 8).padding(.bottom, 2)
        .id(Self.scrollID)
    }
}
