#if canImport(NeoBiliData)
import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

@main
struct NeoBiliApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let identityResetFailed: Bool

    init() {
        #if DEBUG && NEOBILI_IDENTITY_RESET_DIAGNOSTIC && !targetEnvironment(simulator)
        do {
            if !AppNetwork.isRegression {
                try IdentityResetDiagnostic.resetOnce(defaults: .standard, credentials: .keychain,
                    sequenceDefaults: UserDefaults(suiteName: "com.elsterlee.NeoBili.behavior-sequence") ?? .standard,
                    clearNetworking: IdentityResetDiagnostic.clearNetworkingCaches)
            }
            identityResetFailed = false
        } catch { identityResetFailed = true }
        #else
        identityResetFailed = false
        #endif
        // 保留系统下拉刷新手势，隐藏其加载指示器。
        UIRefreshControl.appearance().tintColor = .clear
        // stdout is fully buffered off a terminal, so `print()` debug logs
        // just sit unflushed instead of reaching `devicectl --console`.
        setvbuf(stdout, nil, _IONBF, 0)
        // 记下本次启动的语言，设置页据此提示「重新打开后生效」。
        _ = AppLanguage.launched
        _ = RecommendationSourcePreference.launched

        // 封面/头像的压缩数据完全依赖 URLSession 的 HTTP 缓存（解码位图另有
        // 内存缓存）。系统默认 URLCache 只有几百 KB 内存 / 10MB 磁盘，feed 场景
        // 必然抖动回源；放大后回滚列表和二次进页直接命中磁盘。
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024,
                                   directory: nil)

        // 设备标识和 WBI 签名密钥是每个接口都要用的前置条件。
        // 启动时先在后台取好，第一批推荐和第一个视频就不用排在它们后面。
        if !isTestHost, !identityResetFailed, !capturedDeviceUnavailable {
            RecommendationExperiment.configure(environment: ProcessInfo.processInfo.environment)
            DeviceIdentity.shared.warmUp()
            WBISigner.shared.warmUp()
        }

    }

    private var isTestHost: Bool {
        AppNetwork.isRegression || ProcessInfo.processInfo.environment["NEOBILI_TEST_HOST"] == "1"
    }

    private var capturedDeviceUnavailable: Bool {
        !isTestHost && CapturedDeviceDiagnostic.isEnabled && CapturedDeviceDiagnostic.configuration == nil
    }

    var body: some Scene {
        WindowGroup {
            if capturedDeviceUnavailable {
                ContentUnavailableView("设备对照信息未准备", systemImage: "exclamationmark.triangle",
                    description: Text("请安装包含本机对照信息的测试版本。"))
            } else if identityResetFailed {
                ContentUnavailableView("身份重置未完成", systemImage: "exclamationmark.triangle",
                    description: Text("请解锁手机后重新打开 NeoBili。原有登录不会继续使用。"))
            } else if isTestHost {
                Color.clear
            } else {
                RootView()
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background {
                            AppRecommendationSession.shared.didEnterBackground()
                            Task { await AppBehaviorReporter.shared.setBackground(true) }
                        }
                        else if phase == .active {
                            AppRecommendationSession.shared.didBecomeActive()
                            Task {
                                await AppBehaviorReporter.shared.setBackground(false)
                                await DeviceIdentity.shared.refreshAppServices(validateCredential: true)
                            }
                        }
                    }
            }
        }
    }
}
