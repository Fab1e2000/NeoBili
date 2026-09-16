import SwiftUI
import UIKit

/// Weak geometry anchors: registration never changes a running transition.
@MainActor
final class MediaZoomSources {
    static let shared = MediaZoomSources()
    private struct Key: Hashable { let namespace: Namespace.ID; let id: String }
    private struct WeakView { weak var value: UIView? }
    private var views: [Key: [WeakView]] = [:]

    func register(_ view: UIView, id: String, namespace: Namespace.ID) {
        let key = Key(namespace: namespace, id: id)
        var matches = views[key, default: []].filter { $0.value != nil }
        if !matches.contains(where: { $0.value === view }) { matches.append(WeakView(value: view)) }
        views[key] = matches
    }

    func view(id: String, namespace: Namespace.ID) -> UIView? {
        let key = Key(namespace: namespace, id: id)
        let candidates = views[key, default: []].compactMap(\.value).filter { !$0.bounds.isEmpty && $0.superview != nil }
        return candidates.last(where: { $0.window != nil }) ?? candidates.last
    }
}

struct MediaZoomSource: UIViewRepresentable {
    let id: String
    let namespace: Namespace.ID
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        MediaZoomSources.shared.register(view, id: id, namespace: namespace)
    }
}

extension View {
    func mediaZoomCover<Content: View>(isPresented: Binding<Bool>, entrySourceID: String,
                                      namespace: Namespace.ID, onDismiss: @escaping () -> Void,
                                      @ViewBuilder content: () -> Content) -> some View {
        background {
            MediaZoomPresenter(isPresented: isPresented, shouldPresent: isPresented.wrappedValue, entrySourceID: entrySourceID,
                               namespace: namespace, onDismiss: onDismiss, content: content())
                .frame(width: 0, height: 0)
        }
    }
}

private struct MediaZoomPresenter<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let shouldPresent: Bool
    let entrySourceID: String
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    let content: Content

    func makeUIViewController(context: Context) -> Presenter {
        let controller = Presenter()
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        // Carry the exact SwiftUI environment across the UIKit hosting boundary.
        controller.content = AnyView(content.environment(\.self, context.environment))
        controller.presentation = $isPresented
        controller.shouldPresent = shouldPresent
        controller.entrySourceID = entrySourceID
        controller.namespace = namespace
        controller.onDismiss = onDismiss
        controller.reconcile()
    }

    @MainActor
    final class Presenter: UIViewController {
        var content = AnyView(EmptyView())
        var presentation: Binding<Bool> = .constant(false)
        var shouldPresent = false
        var entrySourceID = ""
        var namespace: Namespace.ID?
        var onDismiss: () -> Void = {}
        private var host: ZoomHost?
        private var scheduled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reconcile()
        }

        func reconcile() {
            if let host {
                if !shouldPresent, !host.isBeingDismissed {
                    host.dismiss(animated: true) { [weak self, weak host] in
                        guard let host else { return }
                        self?.didDismiss(host)
                    }
                }
                return
            }
            guard shouldPresent, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard self.shouldPresent, self.host == nil,
                      self.viewIfLoaded?.window != nil, let namespace = self.namespace else { return }
                var presenter: UIViewController = self
                while let parent = presenter.parent { presenter = parent }
                guard presenter.presentedViewController == nil else { return }
                let host = ZoomHost(rootView: self.content)
                let entry = self.entrySourceID
                // Keep source anchors and SwiftUI's dismissal binding mounted
                // while the media page covers the screen.
                host.modalPresentationStyle = .overFullScreen
                // Configure once, before presentation. UIKit asks for each leg's
                // source; SwiftUI never replaces a transition while it is running.
                host.preferredTransition = .zoom { [weak host] context in
                    guard let host else { return nil }
                    return host.sourceView(entryID: entry, namespace: namespace,
                                           isDismissing: context.zoomedViewController.isBeingDismissed)
                }
                host.onDismissed = { [weak self, weak host] in
                    guard let host else { return }
                    self?.didDismiss(host)
                }
                self.host = host
                presenter.present(host, animated: true)
            }
        }

        private func didDismiss(_ dismissed: ZoomHost) {
            guard host === dismissed else { return }
            host = nil
            presentation.wrappedValue = false
            onDismiss()
        }
    }
}

/// One native transition instance owns the complete present / interrupt / return.
@MainActor
final class ZoomHost: UIHostingController<AnyView> {
    var onDismissed: () -> Void = {}
    private(set) var hasCompletedEntrance = false
    private var returnSourceID: String?

    func sourceID(entryID: String, isDismissing: Bool) -> String {
        if isDismissing, returnSourceID == nil {
            returnSourceID = hasCompletedEntrance ? NowPlayingStore.miniPlayerTransitionSourceID : entryID
        }
        return returnSourceID ?? entryID
    }

    func sourceView(entryID: String, namespace: Namespace.ID, isDismissing: Bool) -> UIView? {
        let id = sourceID(entryID: entryID, isDismissing: isDismissing)
        let source = MediaZoomSources.shared.view(id: id, namespace: namespace)
            ?? MediaZoomSources.shared.view(id: entryID, namespace: namespace)
            ?? MediaZoomSources.shared.view(id: NowPlayingStore.miniPlayerTransitionSourceID, namespace: namespace)
        return source
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasCompletedEntrance = true
        returnSourceID = nil // A cancelled interactive return can be attempted again.
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        onDismissed()
    }
}
