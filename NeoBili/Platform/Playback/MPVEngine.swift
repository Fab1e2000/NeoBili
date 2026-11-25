import NeoBiliDomain
import Foundation
import Libmpv
import UIKit

/// UIKit 和播放回调留在 MainActor。句柄、命令、事件读取和销毁都归串行队列。
final class MPVEngine: @unchecked Sendable {
    @MainActor private var isStopped = false
    @MainActor private var sourceRevision = 0
    @MainActor private var hasReportedFirstFrame = false
    @MainActor private var lastKnownPosition: TimeInterval = 0
    private let eventQueue = DispatchQueue(label: "com.neobili.mpv.events", qos: .userInitiated)
    private var mpv: OpaquePointer?
    /// The queue uses only the layer's address and retains it until native shutdown.
    /// UIKit continues to own layer geometry.
    private struct RenderTarget: @unchecked Sendable {
        let layer: MPVMetalLayer
        var address: UnsafeMutableRawPointer { Unmanaged.passUnretained(layer).toOpaque() }
    }
    private var renderTarget: RenderTarget?
    private var eventRevision = 0
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

    @MainActor var onEvent: ((PlayerPlaybackEvent) -> Void)?

    private let configuration: VideoPlaybackConfiguration

    init(configuration: VideoPlaybackConfiguration) {
        self.configuration = configuration
    }

    @MainActor func start(renderingInto layer: MPVMetalLayer) {
        guard !isStopped else { return }
        let target = RenderTarget(layer: layer)
        eventQueue.async { [self] in initialize(renderingInto: target) }
    }

    private func initialize(renderingInto target: RenderTarget) {
        guard let mpv = mpv_create() else {
            reportInitializationError(String(localized: "mpv 初始化失败"))
            return
        }
        renderTarget = target

#if DEBUG
        // debug 级日志每个解封装包都有数条，每条都会变成一个事件挤进
        // 事件队列；排查 mpv 内部问题时临时改回 "debug"。
        mpv_request_log_messages(mpv, "warn")
#else
        mpv_request_log_messages(mpv, "no")
#endif
        var layerPointer = target.address
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
            renderTarget = nil
            reportInitializationError(message)
            return
        }
        self.mpv = mpv

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

    @MainActor func open(source: PlaybackSource, startTime: TimeInterval = 0) {
        // Regression exercises playback through injected sessions, never native network I/O.
        guard !RuntimePolicy.isRegression, !isStopped else { return }
        sourceRevision += 1
        hasReportedFirstFrame = false
        lastKnownPosition = 0
        let revision = sourceRevision
        enqueue { engine, mpv in
            // Events already waiting belong to the previous source.
            engine.drainEvents()
            engine.eventRevision = revision
            engine.latestEventPosition = 0
            engine.lastPositionDispatch = 0
            engine.lastCacheDispatch = 0
            engine.dispatchToMain { [weak engine] in engine?.onEvent?(.duration(source.duration)) }
            let url = PlaybackSourceBuilder.edlURL(for: source)
            let status = engine.sendCommand(mpv, PlaybackLoadCommand.arguments(url: url, startTime: startTime))
            if status < 0 {
                let message = String(cString: mpv_error_string(status))
                engine.dispatchToMain { [weak engine] in engine?.onEvent?(.error(message)) }
            }
        }
    }

    @MainActor func play() {
        enqueue { $0.setFlag($1, name: "pause", value: false) }
    }

    @MainActor func pause() { pauseAsync() }

    @MainActor func pauseAsync(afterPaused: (@MainActor @Sendable () -> Void)? = nil) {
        eventQueue.async { [weak self] in
            if let self, let mpv { setFlag(mpv, name: "pause", value: true) }
            if let afterPaused { DispatchQueue.main.async { afterPaused() } }
        }
    }

    @MainActor func setPlaybackRate(_ rate: Double) {
        guard let command = PlaybackSpeed.command(rate) else { return }
        enqueue { $0.sendCommand($1, command) }
    }

    @MainActor func seek(to seconds: TimeInterval) {
        enqueue { engine, mpv in
            let target = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), seconds)
            engine.sendCommand(mpv, ["seek", target, "absolute+exact"])
        }
    }

    @MainActor func stop(afterStopped: (@MainActor @Sendable () -> Void)? = nil) {
        if !isStopped {
            isStopped = true
            eventQueue.async { [self] in
                if let mpv {
                    mpv_set_wakeup_callback(mpv, nil, nil)
                    setFlag(mpv, name: "pause", value: true)
                    mpv_terminate_destroy(mpv)
                    self.mpv = nil
                }
                renderTarget = nil
            }
        }
        if let afterStopped {
            eventQueue.async { DispatchQueue.main.async { afterStopped() } }
        }
    }

    /// Audio-only playback disables decoding as well as the hidden Metal output.
    @MainActor func setVideoEnabled(_ enabled: Bool) {
        enqueue { _, mpv in mpv_set_property_string(mpv, "vid", enabled ? "auto" : "no") }
    }

    @MainActor private func enqueue(_ command: @escaping @Sendable (MPVEngine, OpaquePointer) -> Void) {
        guard !isStopped else { return }
        eventQueue.async { [weak self] in
            guard let self, let mpv else { return }
            command(self, mpv)
        }
    }

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

    private func dispatchToMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        let revision = eventRevision
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopped, sourceRevision == revision else { return }
            work()
        }
    }

    private func reportInitializationError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopped else { return }
            onEvent?(.error(message))
        }
    }

    @MainActor private func handlePosition(_ value: TimeInterval) {
        lastKnownPosition = value
        onEvent?(.position(value))
    }

    @MainActor private func handleCacheTime(_ value: TimeInterval) {
        onEvent?(.buffered(max(value - lastKnownPosition, 0)))
    }

    @MainActor private func reportFirstFrameIfNeeded() {
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
