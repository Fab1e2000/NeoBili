#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import Libmpv
import UIKit

/// 持有 mpv 内核和事件队列，将事件转发为 PlayerPlaybackEvent。
/// 普通 Swift 类型不继承 UIKit 的 actor 隔离，裸 C 唤醒回调只投递到 eventQueue。
/// 公开播放操作由主线程调用，事件读取与异步销毁在串行 eventQueue 执行；
/// @unchecked Sendable 依赖这些调用约定。UIKit 渲染宿主由 MPVMetalViewController 管理。
final class MPVEngine: @unchecked Sendable {
    /// 主线程创建并读取播放命令所需的句柄，eventQueue 读取事件并负责最终销毁。
    /// stop 先在主线程置 isStopped，后续同步播放操作在读取句柄前检查该标记。
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

    /// wid 使用图层地址；宿主持有图层，stop 将它强引用到异步内核销毁结束。
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
        // Regression exercises playback through injected sessions, never native network I/O.
        guard !RuntimePolicy.isRegression else { return }
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

    /// 把暂停命令排入 eventQueue，与事件读取和销毁串行执行，避免退出转场在主线程等待内核锁。
    func pauseAsync(afterPaused: (@MainActor @Sendable () -> Void)? = nil) {
        eventQueue.async { [weak self] in
            if let mpv = self?.mpv {
                var flag: Int32 = 1
                mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &flag)
            }
            if let afterPaused { DispatchQueue.main.async { afterPaused() } }
        }
    }

    func setPlaybackRate(_ rate: Double) {
        guard !isStopped, let command = PlaybackSpeed.command(rate) else { return }
        eventQueue.async { [weak self] in
            guard let self, let mpv = self.mpv else { return }
            self.sendCommand(mpv, command)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard !isStopped, let mpv else { return }
        sendCommand(mpv, ["seek", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds), "absolute+exact"])
    }

    func stop(afterStopped: (@MainActor @Sendable () -> Void)? = nil) {
        guard !isStopped else {
            if let afterStopped {
                eventQueue.async { DispatchQueue.main.async { afterStopped() } }
            }
            return
        }
        isStopped = true
        guard let mpv else {
            if let afterStopped { DispatchQueue.main.async { afterStopped() } }
            return
        }

        // wakeup 回调是裸 C 函数指针 + `Unmanaged...unretained`，不受 Swift
        // 的 weak 引用保护——先同步取消注册，保证这个对象接下来无论什么
        // 时候被释放，mpv 都不会再摸到一块已经释放的内存。
        mpv_set_wakeup_callback(mpv, nil, nil)

        // 内核销毁排在事件读取之后，避免主线程等待解码管线与 Vulkan 资源释放。
        // 闭包保留 engine 和渲染图层，直到销毁完成。
        let layer = attachedLayer
        eventQueue.async { [self] in
            var pauseFlag: Int32 = 1
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
            mpv_terminate_destroy(mpv)
            self.mpv = nil
            _ = layer
            if let afterStopped { DispatchQueue.main.async { afterStopped() } }
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

    /// 按事件队列的投递顺序将状态更新转到主队列，供 MainActor 上的播放模型消费。
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
