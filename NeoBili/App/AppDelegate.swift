import UIKit

/// SwiftUI's `WindowGroup` doesn't expose a hook for per-screen orientation
/// support, so the current orientation lock is supplied at the application
/// delegate level.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.shared.supportedOrientations
    }
}
