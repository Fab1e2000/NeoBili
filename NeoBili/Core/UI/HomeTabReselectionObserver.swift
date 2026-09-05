import SwiftUI
import UIKit

/// SwiftUI 的 selection 不保证在重复点击当前标签时改变，观察 UIKit 的选择事件。
struct HomeTabReselectionObserver: UIViewControllerRepresentable {
    let onReselect: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> ProbeController {
        let controller = ProbeController()
        controller.onReady = { [weak controller, weak coordinator = context.coordinator] in
            guard let controller else { return }
            coordinator?.attach(from: controller)
        }
        return controller
    }
    func updateUIViewController(_ controller: ProbeController, context: Context) {
        context.coordinator.onReselect = onReselect
        DispatchQueue.main.async { controller.onReady?() }
    }
    static func dismantleUIViewController(_ controller: ProbeController, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeController: UIViewController {
        var onReady: (() -> Void)?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onReady?() }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            DispatchQueue.main.async { self.onReady?() }
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: (() -> Void)?
        private var callbackPending = false
        private weak var controller: UITabBarController?
        // NSObject 的转发入口为 nonisolated；所有访问均由主线程入口或下方线程检查保护。
        nonisolated(unsafe) private weak var original: (any UITabBarControllerDelegate)?

        func attach(from probe: UIViewController) {
            var root = probe
            while let parent = root.parent { root = parent }
            guard let tab = probe.tabBarController ?? Self.findTab(in: root), tab.delegate !== self else { return }
            if controller !== tab { detach() }
            controller = tab
            original = tab.delegate
            tab.delegate = self
        }
        private static func findTab(in controller: UIViewController) -> UITabBarController? {
            if let tab = controller as? UITabBarController { return tab }
            for child in controller.children {
                if let tab = findTab(in: child) { return tab }
            }
            return nil
        }
        func detach() {
            if controller?.delegate === self { controller?.delegate = original }
            controller = nil
            original = nil
        }
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            let allowed = original?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
            if allowed, tabBarController.selectedViewController === viewController,
               tabBarController.viewControllers?.first === viewController {
                notifyReselection()
            }
            return allowed
        }
        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            let allowed = original?.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
            if allowed, tabBarController.selectedTab === tab, tabBarController.tabs.first === tab {
                notifyReselection()
            }
            return allowed
        }

        private func notifyReselection() {
            // 有些系统同时发送新旧回调，同一次点击只处理一次。
            guard !callbackPending else { return }
            callbackPending = true
            DispatchQueue.main.async { [weak self] in
                self?.callbackPending = false
                self?.onReselect?()
            }
        }

        // 其他 delegate 消息继续交给 SwiftUI，保留它的选择同步和转场行为。
        override nonisolated func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            guard Thread.isMainThread else { return false }
            return MainActor.assumeIsolated { original?.responds(to: selector) == true }
        }
        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            // UIKit 的选择事件在主线程分发；NSObject 的查询接口本身不带 actor 标注。
            if Thread.isMainThread {
                if let original, original.responds(to: selector) { return original }
            }
            return super.forwardingTarget(for: selector)
        }
    }
}
