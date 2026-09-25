import AVFAudio
import Foundation

/// mpv 自己的音频输出走 CoreAudio，不经过 AVFoundation，但 `AVAudioSession`
/// 的分类是整个进程共用的系统设置——不设成 `.playback`，手机静音键会直接把
/// 视频的声音关掉。
///
/// 同步的 `setActive(true)` 在这台设备上会直接触发 libdispatch 的队列断言
/// 崩溃（`_dispatch_assert_queue_fail`），换过调用的线程、换过调用的时机
/// 都没用——系统日志一开始给的提示就是对的："改用异步版本"，问题出在这个
/// 同步 API 本身，不是我们怎么调它。iOS 27 才有官方异步版本，26 上只能退回
/// 同步调用（回到最初那个"可能卡主线程"的警告，但至少不崩）。
///
/// 异步版本在 iOS 26 SDK 里标记为 iOS 不可用，用 Xcode 26 编译会直接报错，
/// 所以还要按编译器版本（Xcode 27 = Swift 6.4）在编译期分开。用 Xcode 26
/// 构建的包在 iOS 27 上也只走同步调用，上面那个崩溃可能再次出现。
enum PlaybackAudioSession {
    /// 幂等且可重复调用。建播放器时先做一次（必须早于 mpv 初始化音频输出），
    /// 第一帧后再兜一次——启动时那次激活可能失败（错误被 `try?` 吞掉），
    /// 失败的会话不会让系统把 App 认成「正在播放」的媒体应用，灵动岛、
    /// 锁屏和控制中心就都不出现。第一帧时 mpv 的音频输出已经建好，
    /// 这时重复激活不会碰它的初始化。
    @MainActor
    static func activateOnce() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            session.activate(options: []) { _, _ in }
        } else {
            try? session.setActive(true)
        }
        #else
        try? session.setActive(true)
        #endif
    }
}
