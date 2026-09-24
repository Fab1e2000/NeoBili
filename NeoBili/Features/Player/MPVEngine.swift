import Foundation
import Libmpv
import UIKit

/// Owns the mpv core and the C-API event loop that turns mpv events into
/// `PlayerPlaybackEvent`s.
///
/// 故意不继承 `UIViewController`/`NSObject`：那两个在这个 SDK 里默认是
/// `@MainActor` 隔离的，哪怕方法自己标了 `nonisolated`，Swift 6 运行时还是
/// 会在通过裸 C 回调（`mpv_set_wakeup_callback`）调用这类对象的方法时插入
/// 一次"是否在正确的执行体上"的动态检查——而 mpv 自己的线程显然不是主线程，
/// 检查必然失败，直接触发 `_dispatch_assert_queue_fail` 崩溃。这是一个普通
/// 的 Swift 类，没有任何父类强加的 actor 隔离，回调线程调用它的方法不会
/// 触发这种检查。真正需要碰 UIKit（渲染层、通知）的部分留在
/// `MPVMetalViewController` 里，那边所有入口本来就只会从 MainActor 调用。
///
/// 地址失败后的候选切换由 PlayerViewModel 管理，每次尝试使用独立内核，
/// 旧内核的迟到事件不会混入下一次播放。
/// `@unchecked`：这个类的可变状态确实会被多个线程碰到（mpv 的回调线程、
/// eventQueue、主线程），但访问路径靠的是人工约束好的顺序（各处注释已经
/// 说明），不是 Swift 的 actor/Sendable 机制——安全性是手动保证的。
final class MPVEngine: @unchecked Sendable {
    /// mpv 的客户端 API（命令、属性读写）本身是线程安全的，可以从任意线程
    /// 调用；只有终止上下文（`mpv_terminate_destroy`）之后不能再用这个指针。
    /// 为了不让"终止"和"正在收事件"这两件事在两个线程上撞车，这个指针的
    /// 每一次写入（初始化之外）都固定发生在 `eventQueue` 上，读取也只在
    /// 这一个队列里发生——`eventQueue` 是串行队列，天然把这些操作排成顺序。
    private var mpv: OpaquePointer?
    private let eventQueue = DispatchQueue(label: "com.neobili.mpv.events", qos: .userInitiated)
    private var isStopped = false
    private var hasReportedFirstFrame = false
    private var lastKnownPosition: TimeInterval = 0
    // Only accessed on eventQueue. Throttle before waking the main thread.
    private var latestEventPosition: TimeInterval = 0
    private var lastPositionDispatch: UInt64 = 0
    private var lastCacheDispatch: UInt64 = 0

    private func publishPosition(_ position: TimeInterval, force: Bool = false) {
        latestEventPosition = position
        let now = DispatchTime.now().uptimeNanoseconds
        guard force || now - lastPositionDispatch >= 100_000_000 else { return }
        lastPositionDispatch = now
        dispatchToMain { [weak self] in self?.handlePosition(position) }
    }

    var onEvent: ((PlayerPlaybackEvent) -> Void)?

    private let configuration: VideoPlaybackConfiguration

    init(configuration: VideoPlaybackConfiguration) {
        self.configuration = configuration
    }

    /// `layer` 只是取一次它的地址交给 mpv 的 `wid` 选项，不需要长期持有——
    /// 渲染层本身的生命周期由 `MPVMetalViewController` 管。
    func start(renderingInto layer: MPVMetalLayer) {
        attachedLayer = layer
        guard let mpv = mpv_create() else {
            dispatchToMain { [weak self] in self?.onEvent?(.error(String(localized: "mpv 初始化失败"))) }
            return
        }
        self.mpv = mpv

#if DEBUG
        // debug 级日志每个解封装包都有数条，每条都会变成一个事件挤进
        // 事件队列；排查 mpv 内部问题时临时改回 "debug"。
        mpv_request_log_messages(mpv, "warn")
#else
        mpv_request_log_messages(mpv, "no")
#endif
        var layerPointer = Unmanaged.passUnretained(layer).toOpaque()
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerPointer)

        let referer = "Referer: \(configuration.referer)"
        for (name, value) in MPVPlaybackOptions.make(
            configuration: configuration,
            isSimulator: PlatformInfo.isSimulator,
            httpHeaderFields: referer
        ) {
            mpv_set_option_string(mpv, name, value)
        }

        let status = mpv_initialize(mpv)
        guard status >= 0 else {
            let message = String(cString: mpv_error_string(status))
            mpv_terminate_destroy(mpv)
            self.mpv = nil
            dispatchToMain { [weak self] in self?.onEvent?(.error(message)) }
            return
        }

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "video-out-params/aspect", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "video-out-params/rotate", MPV_FORMAT_INT64)

        // 这个闭包会被当作 C 函数指针调用，不能捕获任何 Swift 上下文——
        // 唯一的信息通道是 `context`，对应下面传入的 `self` 指针。
        // 指向的是这个普通类自己，不是任何 UIKit 对象，见类型上面的说明。
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            Unmanaged<MPVEngine>.fromOpaque(context).takeUnretainedValue().scheduleEventDrain()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func open(source: PlaybackSource, startTime: TimeInterval = 0) {
        guard !isStopped, let mpv else { return }
        hasReportedFirstFrame = false
        lastKnownPosition = 0
        dispatchToMain { [weak self] in self?.onEvent?(.duration(source.duration)) }
        let url = PlaybackSourceBuilder.edlURL(for: source)
        let status = sendCommand(mpv, PlaybackLoadCommand.arguments(url: url, startTime: startTime))
        if status < 0 {
            let message = String(cString: mpv_error_string(status))
            dispatchToMain { [weak self] in self?.onEvent?(.error(message)) }
        }
    }

    func play() {
        // 销毁块对 mpv 指针的置空发生在 eventQueue 上；这里的主线程读取
        // 靠 isStopped 同步挡住，否则就是正式的数据竞争。
        guard !isStopped, let mpv else { return }
        setFlag(mpv, name: "pause", value: false)
    }

    func pause() {
        guard !isStopped, let mpv else { return }
        setFlag(mpv, name: "pause", value: true)
    }

    /// 手势退出的提交帧不能同步等内核拿锁（暂停期间渲染线程可能正持有着
    /// 核心锁），命令排进事件队列异步执行。mpv 指针的读写本来就约定只发生
    /// 在这条队列上（见 `stop()`），这里沿用同一份约束，与销毁天然串行。
    func pauseAsync() {
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            var flag: Int32 = 1
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard !isStopped, let mpv else { return }
        sendCommand(mpv, ["seek", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds), "absolute+exact"])
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        guard let mpv else { return }

        // wakeup 回调是裸 C 函数指针 + `Unmanaged...unretained`，不受 Swift
        // 的 weak 引用保护——先同步取消注册，保证这个对象接下来无论什么
        // 时候被释放，mpv 都不会再摸到一块已经释放的内存。
        mpv_set_wakeup_callback(mpv, nil, nil)

        // 销毁要在 eventQueue 上排队（与 drainEvents 串行，满足 mpv 的
        // 「销毁期间不能并发访问」约束），但改成 async：mpv_terminate_destroy
        // 要拆掉解码管线和 Vulkan 设备，主线程同步等它会卡住切画质/关页的
        // 转场动画几十毫秒。block 强持有 engine（连带保持 `wid` 指向的渲染
        // 层引用），销毁完成前对象链不会被释放，原来的时序保证不变。
        let layer = attachedLayer
        eventQueue.async { [self] in
            var pauseFlag: Int32 = 1
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
            mpv_terminate_destroy(mpv)
            self.mpv = nil
            _ = layer
        }
    }

    /// `start(renderingInto:)` 记下的渲染层；stop 的异步销毁要强持有它，
    /// 保证 mpv 内部线程销毁完成前 wid 指针始终有效。
    private weak var attachedLayer: MPVMetalLayer?

    /// Audio-only playback must disable decoding as well as the hidden Metal output.
    /// Serialize with event handling and shutdown without blocking UI gestures.
    func setVideoEnabled(_ enabled: Bool) {
        guard !isStopped else { return }
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            mpv_set_property_string(mpv, "vid", enabled ? "auto" : "no")
        }
    }

    // MARK: - mpv command/property helpers（只从调用方所在线程执行，本身线程安全）

    @discardableResult
    private func sendCommand(_ mpv: OpaquePointer, _ args: [String]) -> Int32 {
        // `mpv_command` 要的是 `const char*` 数组（不可变），`strdup` 给的是
        // `char*`（可变，因为我们要负责 free）；两个数组分开，一个管分配和
        // 释放，一个只负责喂给 C 调用。
        let owned: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { owned.forEach { if let pointer = $0 { free(pointer) } } }
        var cArgs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }
        cArgs.append(nil)
        return mpv_command(mpv, &cArgs)
    }

    private func setFlag(_ mpv: OpaquePointer, name: String, value: Bool) {
        var flag: Int32 = value ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &flag)
    }

    // MARK: - mpv 事件循环（只在 eventQueue 上运行）

    /// 由 `mpv_set_wakeup_callback` 从 mpv 自己的线程触发，转发到我们自己的
    /// 串行队列上排空事件，不在 mpv 的线程上做任何事。
    private func scheduleEventDrain() {
        eventQueue.async { [weak self] in
            self?.drainEvents()
        }
    }

    private func drainEvents() {
        guard let mpv else { return }
        // mpv 对 time-pos 基本每个视频帧发一次变化事件；一次唤醒经常携带
        // 一整批。连续的 time-pos 合并成最后一条再派发（其余事件照常逐条、
        // 按原顺序处理），主线程的跳转次数从每帧一次降到每批一次。
        var pendingPosition: Double?
        while true {
            guard let event = mpv_wait_event(mpv, 0) else { break }
            if event.pointee.event_id == MPV_EVENT_NONE { break }
            if event.pointee.event_id == MPV_EVENT_PROPERTY_CHANGE,
               let raw = event.pointee.data {
                let property = raw.assumingMemoryBound(to: mpv_event_property.self).pointee
                if let namePointer = property.name,
                   property.format == MPV_FORMAT_DOUBLE,
                   strcmp(namePointer, "time-pos") == 0,
                   let value = property.data?.assumingMemoryBound(to: Double.self).pointee,
                   value.isFinite {
                    pendingPosition = max(value, 0)
                    continue
                }
            }
            if let pending = pendingPosition {
                pendingPosition = nil
                publishPosition(pending)
            }
            handle(event: event)
        }
        if let pending = pendingPosition {
            publishPosition(pending)
        }
    }

    private func handle(event: UnsafePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let raw = event.pointee.data else { return }
            let property = raw.assumingMemoryBound(to: mpv_event_property.self).pointee
            guard let namePointer = property.name else { return }
            handlePropertyChange(name: String(cString: namePointer), format: property.format, data: property.data)
        case MPV_EVENT_PLAYBACK_RESTART:
            var position: Double = 0
            let hasPosition = mpv.map {
                mpv_get_property($0, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0
            } ?? false
            let resumedPosition = hasPosition && position.isFinite ? max(position, 0) : nil
            lastCacheDispatch = 0
            if let resumedPosition { publishPosition(resumedPosition, force: true) }
            dispatchToMain { [weak self] in
                self?.reportFirstFrameIfNeeded()
                if let resumedPosition { self?.onEvent?(.seekCompleted(resumedPosition)) }
            }
        case MPV_EVENT_VIDEO_RECONFIG:
            reportDisplayAspectRatio()
        case MPV_EVENT_END_FILE:
            guard let raw = event.pointee.data else { return }
            let endFile = raw.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            switch endFile.reason {
            case MPV_END_FILE_REASON_EOF:
                dispatchToMain { [weak self] in self?.onEvent?(.ended) }
            case MPV_END_FILE_REASON_ERROR:
                let message = String(cString: mpv_error_string(endFile.error))
                dispatchToMain { [weak self] in self?.onEvent?(.error(message)) }
            default:
                break
            }
        default:
            break
        }
    }

    private func handlePropertyChange(name: String, format: mpv_format, data: UnsafeMutableRawPointer?) {
        guard let data else { return }
        switch (name, format) {
        case ("time-pos", MPV_FORMAT_DOUBLE):
            let value = data.assumingMemoryBound(to: Double.self).pointee
            guard value.isFinite else { return }
            publishPosition(max(value, 0))
        case ("duration", MPV_FORMAT_DOUBLE):
            let value = data.assumingMemoryBound(to: Double.self).pointee
            guard value.isFinite, value > 0 else { return }
            dispatchToMain { [weak self] in self?.onEvent?(.duration(value)) }
        case ("demuxer-cache-time", MPV_FORMAT_DOUBLE):
            let value = data.assumingMemoryBound(to: Double.self).pointee
            guard value.isFinite else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now - lastCacheDispatch >= 500_000_000 else { return }
            lastCacheDispatch = now
            dispatchToMain { [weak self] in self?.handleCacheTime(value) }
        case ("pause", MPV_FORMAT_FLAG):
            let value = data.assumingMemoryBound(to: Int32.self).pointee
            publishPosition(latestEventPosition, force: true)
            dispatchToMain { [weak self] in self?.onEvent?(.playing(value == 0)) }
        case ("paused-for-cache", MPV_FORMAT_FLAG):
            let value = data.assumingMemoryBound(to: Int32.self).pointee
            dispatchToMain { [weak self] in self?.onEvent?(.buffering(value != 0)) }
        case ("video-out-params/aspect", MPV_FORMAT_DOUBLE),
             ("video-out-params/rotate", MPV_FORMAT_INT64):
            reportDisplayAspectRatio()
        default:
            break
        }
    }

    // MARK: - 主线程上的状态更新

    /// 从同一份解码参数读取画幅和旋转，避免只用 DASH 编码宽高把旋转视频认反。
    private func reportDisplayAspectRatio() {
        guard let mpv else { return }
        // 解码器输入尺寸用于验证实际播放档位，不能用显示比例或稿件元信息替代。
        var width: Int64 = 0
        var height: Int64 = 0
        if mpv_get_property(mpv, "video-params/w", MPV_FORMAT_INT64, &width) >= 0,
           mpv_get_property(mpv, "video-params/h", MPV_FORMAT_INT64, &height) >= 0,
           width > 0, height > 0 {
            let decodedWidth = Int(width)
            let decodedHeight = Int(height)
            dispatchToMain { [weak self] in
                self?.onEvent?(.decodedVideoSize(width: decodedWidth, height: decodedHeight))
            }
        }
        var aspect: Double = 0
        var rotation: Int64 = 0
        guard mpv_get_property(mpv, "video-out-params/aspect", MPV_FORMAT_DOUBLE, &aspect) >= 0 else { return }
        _ = mpv_get_property(mpv, "video-out-params/rotate", MPV_FORMAT_INT64, &rotation)
        guard let displayAspect = PlayerSurfaceGeometry.displayAspectRatio(aspect, rotation: rotation) else { return }
        dispatchToMain { [weak self] in self?.onEvent?(.displayAspectRatio(displayAspect)) }
    }

    /// `onEvent` 最终会调到 `PlayerViewModel`（`@MainActor`），这里统一走
    /// 普通的 `DispatchQueue.main.async`，而不是 `Task { @MainActor in }`——
    /// 这个类本身没有任何 actor 隔离，用哪种方式跳主线程都可以，选前者是
    /// 因为它不会被 Swift 6 运行时的隔离检查误伤（正是这份文件另一处崩溃
    /// 的起因）。
    private func dispatchToMain(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    private func handlePosition(_ value: TimeInterval) {
        lastKnownPosition = value
        onEvent?(.position(value))
    }

    private func handleCacheTime(_ value: TimeInterval) {
        onEvent?(.buffered(max(value - lastKnownPosition, 0)))
    }

    private func reportFirstFrameIfNeeded() {
        guard !hasReportedFirstFrame else { return }
        hasReportedFirstFrame = true
        onEvent?(.firstFrame)
    }
}

enum PlatformInfo {
    static let isSimulator: Bool = {
#if targetEnvironment(simulator)
        true
#else
        false
#endif
    }()
}
