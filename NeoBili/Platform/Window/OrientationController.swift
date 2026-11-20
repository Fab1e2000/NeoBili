import UIKit

/// Locks the app to one interface orientation and asks the active scene to
/// adopt it. The supported-orientation mask is changed before the geometry
/// request so system UI always observes the same coordinate space as the app.
@MainActor
enum OrientationController {
    /// 横屏允许左右两个方向，用户可按持机方向旋转；该方向集合排除竖屏。
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

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation), errorHandler: geometryRequestFailed)
    }

    // UIKit may deliver this callback from a worker queue. Logging must not
    // inherit this enum's MainActor isolation or change the newer desired mask.
    nonisolated static func geometryRequestFailed(_ error: Error) {
        NSLog("Orientation geometry request failed: %@", error.localizedDescription)
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
