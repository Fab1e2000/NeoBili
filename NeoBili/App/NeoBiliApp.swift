import SwiftUI

@main
struct NeoBiliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // stdout is fully buffered off a terminal, so `print()` debug logs
        // just sit unflushed instead of reaching `devicectl --console`.
        setvbuf(stdout, nil, _IONBF, 0)

        // 「有声音没画面」只在真机上复现，诊断日志同时进 Xcode 控制台和沙盒文件，
        // 事后整份拉下来看。每次冷启动清空，拉到的就只有本轮复现的记录。

        // 设备标识和 WBI 签名密钥是每个接口都要用的前置条件。
        // 启动时先在后台取好，第一批推荐和第一个视频就不用排在它们后面。
        DeviceIdentity.shared.warmUp()
        WBISigner.shared.warmUp()

        // 音频分类要在主线程上激活，而且必须早于第一次打开视频——mpv 自己
        // 初始化音频输出时如果这一步还没做完，两边同时碰 `AVAudioSession`
        // 的全局状态容易出问题（见 `PlaybackAudioSession` 的说明）。
        Task { @MainActor in
            PlaybackAudioSession.activateOnce()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
