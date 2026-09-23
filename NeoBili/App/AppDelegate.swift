import UIKit

/// SwiftUI's `WindowGroup` doesn't expose a hook for per-screen orientation
/// support, so the current orientation lock is supplied at the application
/// delegate level.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 标题后台预排版之前，先在主线程把系统排版组件初始化好、量好当前字号的
        // 排版参数，避免与 SwiftUI 死锁。此时 UIKit 已就绪，还没有任何 SwiftUI 界面更新。
        let textSizeIndex = UserDefaults.standard.object(forKey: AppTextSize.storageKey) as? Int ?? AppTextSize.defaultIndex
        PreparedTitle.warmUp(dynamicTypeSize: AppTextSize.size(at: textSizeIndex))
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.shared.supportedOrientations
    }
}
