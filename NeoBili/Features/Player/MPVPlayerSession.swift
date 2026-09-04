import AVFAudio
import Foundation
import Libmpv
import UIKit

/// mpv 自己的音频输出走 CoreAudio，不经过 AVFoundation，但 `AVAudioSession`
/// 的分类是整个进程共用的系统设置——不设成 `.playback`，手机静音键会直接把
/// 视频的声音关掉。
///
/// 同步的 `setActive(true)` 在这台设备上会直接触发 libdispatch 的队列断言
/// 崩溃（`_dispatch_assert_queue_fail`），换过调用的线程、换过调用的时机
/// 都没用——系统日志一开始给的提示就是对的："改用异步版本"，问题出在这个
/// 同步 API 本身，不是我们怎么调它。iOS 27 才有官方异步版本，26 上只能退回
/// 同步调用（回到最初那个"可能卡主线程"的警告，但至少不崩）。
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
        if #available(iOS 27.0, *) {
            session.activate(options: []) { _, _ in }
        } else {
            try? session.setActive(true)
        }
    }
}

struct PlaybackStream: Sendable, Hashable {
    let primary: URL
    let backups: [URL]

    var candidates: [URL] {
        var result = [primary]
        for backup in backups where !result.contains(backup) { result.append(backup) }
        return result
    }
}

/// `audio == nil` is a server-side muxed stream, opened directly. Otherwise
/// the two elementary streams are joined into one `edl://` pseudo-URL that
/// mpv demuxes as a single source — see `PlaybackSourceBuilder.edlURL`.
struct PlaybackSource: Sendable, Hashable {
    let video: PlaybackStream
    let audio: PlaybackStream?
    let duration: TimeInterval

    var candidates: [PlaybackSource] {
        let videos = Array(video.candidates.prefix(2))
        guard let audio else {
            return videos.map {
                PlaybackSource(video: PlaybackStream(primary: $0, backups: []), audio: nil, duration: duration)
            }
        }
        let audios = Array(audio.candidates.prefix(2))
        return videos.flatMap { videoURL in
            audios.map { audioURL in
                PlaybackSource(
                    video: PlaybackStream(primary: videoURL, backups: []),
                    audio: PlaybackStream(primary: audioURL, backups: []),
                    duration: duration
                )
            }
        }
    }
}

enum PlayerPlaybackEvent: Sendable {
    case firstFrame
    case playing(Bool)
    case buffering(Bool)
    case position(TimeInterval)
    case duration(TimeInterval)
    case buffered(TimeInterval)
    case ended
    case error(String)
}

enum PlayerSessionError: LocalizedError {
    case invalidSource
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource: return "视频地址无效"
        case .playbackFailed(let detail): return "视频加载失败：\(detail)"
        }
    }
}

enum PlaybackSourceBuilder {
    /// 同一清晰度下的编码偏好：avc1 兼容性最好、硬解最省电，排后面的
    /// （dvh1、av01）通常只有软解或部分机型才有硬解。mpv/FFmpeg 都能解，
    /// 这只是"优先选哪个"，不是能不能播的问题。
    private static let preferredCodecPrefixes = ["avc1", "hvc1", "hev1", "dvh1", "av01"]

    static func makeSource(from payload: PlayURLData, configuration: VideoPlaybackConfiguration) throws -> PlaybackSource {
        if let dash = payload.dash,
           let video = bestVideoStream(dash.video, preferredQuality: configuration.quality),
           let audio = dash.audio.max(by: { $0.bandwidth < $1.bandwidth }),
           let videoStream = makeStream(from: video),
           let audioStream = makeStream(from: audio) {
            return PlaybackSource(video: videoStream, audio: audioStream, duration: TimeInterval(dash.duration))
        }

        // durl（html5，服务端已合并好音视频）只在 DASH 拿不到时才用到。
        if let durl = payload.durl?.first, let stream = makeStream(from: durl) {
            return PlaybackSource(video: stream, audio: nil, duration: TimeInterval(durl.length ?? 0) / 1_000)
        }
        throw PlayerSessionError.invalidSource
    }

    static func bestVideoStream(_ streams: [DashStream], preferredQuality: Int) -> DashStream? {
        let usable = streams.filter { URL(string: $0.baseUrl) != nil }
        guard !usable.isEmpty else { return nil }
        let atOrBelow = usable.filter { $0.id <= preferredQuality }
        let targetQuality = atOrBelow.map(\.id).max() ?? usable.map(\.id).min()!
        return usable.filter { $0.id == targetQuality }.min { lhs, rhs in
            let left = codecRank(lhs.codecs)
            let right = codecRank(rhs.codecs)
            if left == right { return lhs.bandwidth > rhs.bandwidth }
            return left < right
        }
    }

    /// mpv 打开两条独立的视频、音频流靠的是这个 EDL 伪协议地址——不是真的文件，
    /// 只是告诉 mpv 的解封装器"把这两个当成一个文件的两条轨道"，不需要像
    /// AVFoundation 那样提前分别探测两条流再手工拼 composition。
    /// 长度必须按字节数（UTF-8）算，不能按字符数，否则多字节字符会导致地址
    /// 从中间被截断。
    static func edlURL(for source: PlaybackSource) -> String {
        let videoURLString = source.video.primary.absoluteString
        guard let audio = source.audio else { return videoURLString }
        let audioURLString = audio.primary.absoluteString
        return "edl://!no_chapters;%\(videoURLString.utf8.count)%\(videoURLString);"
            + "!new_stream;!no_chapters;%\(audioURLString.utf8.count)%\(audioURLString)"
    }

    private static func makeStream(from stream: DashStream) -> PlaybackStream? {
        makeStream(primary: stream.baseUrl, backups: stream.backupUrl ?? [])
    }

    private static func makeStream(from stream: DurlItem) -> PlaybackStream? {
        makeStream(primary: stream.url, backups: stream.backupUrl ?? [])
    }

    private static func makeStream(primary: String, backups: [String]) -> PlaybackStream? {
        let urls = ([primary] + backups).compactMap(URL.init(string:))
        var seen = Set<URL>()
        let unique = urls.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return nil }
        let ranked = unique.enumerated().sorted { left, right in
            let leftRank = cdnRank(left.element)
            let rightRank = cdnRank(right.element)
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
        return PlaybackStream(primary: ranked[0], backups: Array(ranked.dropFirst()))
    }

    private static func codecRank(_ codec: String) -> Int {
        preferredCodecPrefixes.firstIndex { codec.lowercased().hasPrefix($0) } ?? preferredCodecPrefixes.count
    }

    private static func cdnRank(_ url: URL) -> Int {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host.hasPrefix("upos-") || host.contains(".akamaized.") { return 0 }
        if path.contains("/upgcxcode/") && !host.contains(".mcdn.") { return 1 }
        if host.contains(".mcdn.") || path.contains("/v1/resource/") { return 3 }
        return 2
    }
}

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
/// v1（先验证渲染链路能不能跑通）：只打开主候选地址，没有 AVFoundation 版本
/// 那一套候选重试、看门狗超时；这些等真机确认 Metal+Vulkan 渲染没问题之后
/// 再加回来。
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

    var onEvent: ((PlayerPlaybackEvent) -> Void)?

    private let configuration: VideoPlaybackConfiguration

    init(configuration: VideoPlaybackConfiguration) {
        self.configuration = configuration
    }

    /// `layer` 只是取一次它的地址交给 mpv 的 `wid` 选项，不需要长期持有——
    /// 渲染层本身的生命周期由 `MPVMetalViewController` 管。
    func start(renderingInto layer: MPVMetalLayer) {
        guard let mpv = mpv_create() else {
            dispatchToMain { [weak self] in self?.onEvent?(.error("mpv 初始化失败")) }
            return
        }
        self.mpv = mpv

#if DEBUG
        mpv_request_log_messages(mpv, "debug")
#else
        mpv_request_log_messages(mpv, "no")
#endif
        var layerPointer = Unmanaged.passUnretained(layer).toOpaque()
        mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerPointer)

        let referer = "Referer: \(BiliHeaders.referer)"
        for (name, value) in MPVPlaybackOptions.make(
            configuration: configuration,
            isSimulator: PlatformInfo.isSimulator,
            httpHeaderFields: referer
        ) {
            mpv_set_option_string(mpv, name, value)
        }

        mpv_initialize(mpv)

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        // 这个闭包会被当作 C 函数指针调用，不能捕获任何 Swift 上下文——
        // 唯一的信息通道是 `context`，对应下面传入的 `self` 指针。
        // 指向的是这个普通类自己，不是任何 UIKit 对象，见类型上面的说明。
        mpv_set_wakeup_callback(mpv, { context in
            guard let context else { return }
            Unmanaged<MPVEngine>.fromOpaque(context).takeUnretainedValue().scheduleEventDrain()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func open(source: PlaybackSource) {
        guard !isStopped, let mpv else { return }
        hasReportedFirstFrame = false
        lastKnownPosition = 0
        dispatchToMain { [weak self] in self?.onEvent?(.duration(source.duration)) }
        let url = PlaybackSourceBuilder.edlURL(for: source)
        sendCommand(mpv, ["loadfile", url, "replace"])
    }

    func play() {
        guard let mpv else { return }
        setFlag(mpv, name: "pause", value: false)
    }

    func pause() {
        guard let mpv else { return }
        setFlag(mpv, name: "pause", value: true)
    }

    func seek(to seconds: TimeInterval) {
        guard let mpv else { return }
        sendCommand(mpv, ["seek", String(format: "%.3f", seconds), "absolute"])
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        guard let mpv else { return }

        // wakeup 回调是裸 C 函数指针 + `Unmanaged...unretained`，不受 Swift
        // 的 weak 引用保护——先同步取消注册，保证这个对象接下来无论什么
        // 时候被释放，mpv 都不会再摸到一块已经释放的内存。
        mpv_set_wakeup_callback(mpv, nil, nil)

        // 用 `sync` 而不是 `async`：一是要和 `drainEvents()` 借用同一个串行
        // 队列排好顺序——mpv 规定销毁期间不能有别的调用在并发访问同一个
        // handle；二是要保证这个函数真正返回时 mpv 已经销毁完了。调用方
        // 紧接着往往会释放整条对象链，如果销毁还没做完，mpv 内部线程可能
        // 会在这条链已经被回收之后还去碰它。
        eventQueue.sync {
            var pauseFlag: Int32 = 1
            mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag)
            mpv_terminate_destroy(mpv)
        }
        self.mpv = nil
    }

    /// 回前台后画面有时不会自动恢复；先关视频轨道，回前台再打开，强制让
    /// 渲染表面重新建立一次。
    func enterBackground() {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "vid", "no")
    }

    func enterForeground() {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "vid", "auto")
    }

    // MARK: - mpv command/property helpers（只从调用方所在线程执行，本身线程安全）

    private func sendCommand(_ mpv: OpaquePointer, _ args: [String]) {
        // `mpv_command` 要的是 `const char*` 数组（不可变），`strdup` 给的是
        // `char*`（可变，因为我们要负责 free）；两个数组分开，一个管分配和
        // 释放，一个只负责喂给 C 调用。
        let owned: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { owned.forEach { if let pointer = $0 { free(pointer) } } }
        var cArgs: [UnsafePointer<CChar>?] = owned.map { $0.map { UnsafePointer($0) } }
        cArgs.append(nil)
        mpv_command(mpv, &cArgs)
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
        while true {
            guard let event = mpv_wait_event(mpv, 0) else { break }
            if event.pointee.event_id == MPV_EVENT_NONE { break }
            handle(event: event)
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
            dispatchToMain { [weak self] in self?.reportFirstFrameIfNeeded() }
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
            dispatchToMain { [weak self] in self?.handlePosition(max(value, 0)) }
        case ("duration", MPV_FORMAT_DOUBLE):
            let value = data.assumingMemoryBound(to: Double.self).pointee
            guard value.isFinite, value > 0 else { return }
            dispatchToMain { [weak self] in self?.onEvent?(.duration(value)) }
        case ("demuxer-cache-time", MPV_FORMAT_DOUBLE):
            let value = data.assumingMemoryBound(to: Double.self).pointee
            guard value.isFinite else { return }
            dispatchToMain { [weak self] in self?.handleCacheTime(value) }
        case ("pause", MPV_FORMAT_FLAG):
            let value = data.assumingMemoryBound(to: Int32.self).pointee
            dispatchToMain { [weak self] in self?.onEvent?(.playing(value == 0)) }
        case ("paused-for-cache", MPV_FORMAT_FLAG):
            let value = data.assumingMemoryBound(to: Int32.self).pointee
            dispatchToMain { [weak self] in self?.onEvent?(.buffering(value != 0)) }
        default:
            break
        }
    }

    // MARK: - 主线程上的状态更新

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

/// 只负责承载渲染层和转发通知——真正的 mpv 逻辑全在 `MPVEngine` 里。
/// 这里所有方法都只会从 MainActor 调用（`MPVPlayerSession` 的方法、UIKit
/// 自己的生命周期回调、`NotificationCenter` 的这两个前后台通知本身就在
/// 主线程发出），从没有 mpv 的回调线程直接摸这个类。
final class MPVMetalViewController: UIViewController {
    private let engine: MPVEngine
    private let metalLayer = MPVMetalLayer()
    private var stableSurfaceSize: CGSize = .zero

    var onEvent: ((PlayerPlaybackEvent) -> Void)? {
        didSet { engine.onEvent = onEvent }
    }

    init(configuration: VideoPlaybackConfiguration) {
        engine = MPVEngine(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        metalLayer.contentsScale = traitCollection.displayScale
        // 始终按设备横屏的完整像素尺寸渲染。内联与全屏只改变 layer 的显示
        // 几何，不改变 Vulkan surface，因此整个方向动画都不需要重建 swapchain。
        if let screen = activeScreen {
            let drawableSize = PlayerSurfaceGeometry.stableDrawableSize(
                for: screen.nativeBounds.size
            )
            metalLayer.drawableSize = drawableSize
            stableSurfaceSize = PlayerSurfaceGeometry.pointSize(
                for: drawableSize,
                displayScale: metalLayer.contentsScale
            )
        }
        metalLayer.bounds = CGRect(origin: .zero, size: stableSurfaceSize)
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)
        layoutMetalLayer()


        engine.start(renderingInto: metalLayer)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutMetalLayer()
    }

    /// 渲染控制器有没有挂在某个容器下面。脱离父级就等于画面不再显示。
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    private func layoutMetalLayer() {
        guard stableSurfaceSize.width > 0, stableSurfaceSize.height > 0 else {
            metalLayer.frame = view.bounds
            return
        }

        // CAMetalLayer 的 drawable 大于 bounds 时不会按 contentsGravity 缩放，
        // 而是从左上角直接裁切（真机截图里的左侧黑条正来源于此）。让 layer
        // 自己始终保持横屏 bounds，再整体做居中的 aspect-fill 变换，才能既
        // 保持同一个 swapchain，又让小屏正确显示。系统旋转会连续插值这个
        // position/transform，所以全屏切换仍然连贯。
        let scale = PlayerSurfaceGeometry.presentationScale(
            surfaceSize: stableSurfaceSize,
            containerSize: view.bounds.size
        )
        metalLayer.bounds = CGRect(origin: .zero, size: stableSurfaceSize)
        metalLayer.position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        metalLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    private var activeScreen: UIScreen? {
        if let screen = view.window?.windowScene?.screen { return screen }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    func open(source: PlaybackSource) { engine.open(source: source) }
    func play() { engine.play() }
    func pause() { engine.pause() }
    func seek(to seconds: TimeInterval) { engine.seek(to: seconds) }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        engine.stop()
    }

    deinit {
    }

    @objc private func handleDidEnterBackground() { engine.enterBackground() }
    @objc private func handleWillEnterForeground() { engine.enterForeground() }
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

/// 固定渲染表面的尺寸逻辑，单独拆出来便于单测。
enum PlayerSurfaceGeometry {
    /// 无论当前设备方向如何，都返回同一个横屏像素尺寸。
    static func stableDrawableSize(for screenSize: CGSize) -> CGSize {
        CGSize(
            width: max(screenSize.width, screenSize.height),
            height: min(screenSize.width, screenSize.height)
        )
    }

    static func pointSize(for pixelSize: CGSize, displayScale: CGFloat) -> CGSize {
        guard displayScale > 0 else { return .zero }
        return CGSize(
            width: pixelSize.width / displayScale,
            height: pixelSize.height / displayScale
        )
    }

    /// 把固定横屏 surface 等比铺满当前容器，超出的部分由父 view 居中裁掉。
    static func presentationScale(surfaceSize: CGSize, containerSize: CGSize) -> CGFloat {
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return 1 }
        return max(
            containerSize.width / surfaceSize.width,
            containerSize.height / surfaceSize.height
        )
    }
}

@MainActor
final class MPVPlayerSession {
    let viewController: MPVMetalViewController
    var onEvent: ((PlayerPlaybackEvent) -> Void)? {
        didSet { viewController.onEvent = onEvent }
    }

    private var isStopped = false

    init(configuration: VideoPlaybackConfiguration) {
        PlaybackAudioSession.activateOnce()
        viewController = MPVMetalViewController(configuration: configuration)
    }

    func open(source: PlaybackSource) async throws {
        guard !isStopped else { return }
        // mpv 只有在 `viewDidLoad` 跑过之后才存在（`engine.start` 在那里调用）。
        // SwiftUI 什么时候真正把 viewController 挂进窗口是不确定的——如果
        // playURL 命中缓存、`load()` 里的 await 几乎立刻返回，这里可能跑在
        // SwiftUI 挂载之前。主动强制加载一次，不能指望调用方替我们做这件事。
        viewController.loadViewIfNeeded()
        viewController.open(source: source)
    }

    func play() {
        guard !isStopped else { return }
        viewController.play()
    }

    func pause() {
        viewController.pause()
    }

    func seek(to seconds: TimeInterval) async {
        viewController.seek(to: max(seconds, 0))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        viewController.stop()
    }
}
