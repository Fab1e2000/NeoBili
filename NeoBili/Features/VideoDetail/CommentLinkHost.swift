import SafariServices
import SwiftUI

extension View {
    func commentLinkHost(beforeOpeningVideo: @escaping () -> Void = {}) -> some View {
        modifier(CommentLinkHost(beforeOpeningVideo: beforeOpeningVideo))
    }
}

private struct CommentLinkHost: ViewModifier {
    @Environment(\.applicationServices) private var services
    let beforeOpeningVideo: () -> Void
    @Environment(NowPlayingStore.self) private var store
    @Environment(ActionFeedback.self) private var feedback
    @State private var browser: BrowserDestination?
    @State private var shortLink: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                shortLink = nil
                if let route = CommentLinks.videoRoute(url) {
                    beforeOpeningVideo()
                    store.openCommentVideo(route)
                } else if let web = CommentLinks.webURL(url.absoluteString) {
                    if ["b23.tv", "www.b23.tv"].contains(web.host?.lowercased() ?? "") {
                        shortLink = web
                    } else { browser = BrowserDestination(url: web) }
                } else {
                    feedback.show(String(localized: "暂不支持打开此链接"))
                }
                return .handled
            })
            .sheet(item: $browser) { destination in
                CommentBrowser(url: destination.url).ignoresSafeArea()
            }
            .task(id: shortLink) {
                guard let original = shortLink else { return }
                defer { if shortLink == original { shortLink = nil } }
                let resolved = try? await services.links.resolve(original)
                guard !Task.isCancelled, shortLink == original else { return }
                if let resolved, let route = CommentLinks.videoRoute(resolved) {
                    beforeOpeningVideo()
                    store.openCommentVideo(route)
                } else { browser = BrowserDestination(url: original) }
            }
    }
}

private struct BrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct CommentBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
