import UIKit

/// Locks the app to one interface orientation and asks the active scene to
/// adopt it. The supported-orientation mask is changed before the geometry
/// request so system UI always observes the same coordinate space as the app.
@MainActor
enum OrientationController {
    /// 横屏两个方向都放开：用户把手机往哪边转都能进全屏，而且设备已经处在
    /// landscapeLeft 时请求也不会被判成需要反向旋转。方向集里依旧没有竖屏，
    /// 所以 `OrientationLock` 的那条注释仍然成立。
    static func enterLandscape() {
        lock(to: .landscape)
    }

    static func enterPortrait() {
        lock(to: .portrait)
    }

    static func setPlaybackOrientation(_ orientation: UIInterfaceOrientationMask, owner: UUID) {
        guard OrientationLock.shared.request(orientation, owner: owner) else { return }
        apply(orientation)
    }

    static func endPlaybackOrientation(owner: UUID) {
        guard OrientationLock.shared.endPlayback(owner: owner) else { return }
        apply(.portrait)
    }

    private static func lock(to orientation: UIInterfaceOrientationMask) {
        guard OrientationLock.shared.request(orientation) else { return }
        apply(orientation)
    }

    private static func apply(_ orientation: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        // Update the presented controller as well as the root before requesting rotation.
        for controller in presentationChain(of: scene) {
            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            // Keep the desired mask. A rejected or delayed request must never restore
            // an old portrait mask after a newer fullscreen request has taken effect.
            NSLog("Orientation geometry request failed: %@", error.localizedDescription)
        }
    }

    private static func presentationChain(of scene: UIWindowScene) -> [UIViewController] {
        guard var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return [] }

        var chain = [controller]
        while let presented = controller.presentedViewController {
            chain.append(presented)
            controller = presented
        }
        return chain
    }
}
