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

    private static func lock(to orientation: UIInterfaceOrientationMask) {
        let previous = OrientationLock.shared.supportedOrientations
        OrientationLock.shared.supportedOrientations = orientation

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            OrientationLock.shared.supportedOrientations = previous
            return
        }

        // 视频页是 fullScreenCover 呈现出来的控制器，UIKit 判定方向时看的是最
        // 上面那一个。只刷新 rootViewController 的话，这次几何请求可能按旧的
        // 方向集被驳回：屏幕没转，而界面已经按全屏排好版了。
        for controller in presentationChain(of: scene) {
            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in
            // 请求失败时把方向集改回去。否则方向集和屏幕上真正的方向会长期
            // 不一致，下一次切换也跟着错。
            Task { @MainActor in
                OrientationLock.shared.supportedOrientations = previous
            }
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
