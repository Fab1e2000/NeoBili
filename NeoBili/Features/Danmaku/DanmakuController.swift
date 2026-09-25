import SwiftUI

/// 视频弹幕的加载与播放同步控制器。
///
/// 生命周期跟着 `PlayerViewModel`（每个 bvid+cid 一个）：加载一次整段弹幕，
/// 之后只把播放器的位置事件按 100ms 桶转发给引擎，暂停冻结、seek 清场。
/// 加载失败静默——弹幕是增补体验，不能打扰播放。
@MainActor
@Observable
final class DanmakuController {
    enum State { case idle, loading, ready, failed }

    private(set) var state: State = .idle
    /// 引擎由 DanmakuView 挂载后注入；控制器不持有视图的强引用。
    weak var engine: DanmakuEngine?

    let bvid: String
    let cid: Int
    private var items: [DanmakuItem] = []
    private var loadTask: Task<Void, Never>?
    /// 最近一次已知播放位置：弹幕异步加载完成时从这里开始注入，
    /// 续播/中途打开时不会把之前的历史弹幕一次性灌满屏幕。
    private var lastTime: Double = 0
    /// 控制器自己记暂停意图：engine 挂载时机不确定，转发式暂停会在
    /// attach 时被覆盖丢失。
    private var isPaused = false

    init(bvid: String, cid: Int) {
        self.bvid = bvid
        self.cid = cid
    }

    func load() {
        guard state == .idle else { return }
        state = .loading
        let cid = cid
        loadTask = Task {
            let loaded = (try? await DanmakuLoader.load(cid: cid)) ?? []
            guard !Task.isCancelled else { return }
            items = loaded
            state = .ready
            if let engine {
                engine.prepare(items: loaded)
                engine.seek(to: lastTime)
                engine.setTimelinePaused(isPaused)
            }
        }
    }

    func attach(_ engine: DanmakuEngine) {
        self.engine = engine
        if state == .ready {
            engine.prepare(items: items)
            engine.seek(to: lastTime)
        }
        engine.setTimelinePaused(isPaused)
    }

    func detach(_ engine: DanmakuEngine) {
        guard self.engine === engine else { return }
        self.engine = nil
    }

    func update(currentTime: TimeInterval) {
        lastTime = currentTime
        engine?.update(currentTime: currentTime)
    }

    func seek(to time: TimeInterval) {
        lastTime = time
        engine?.seek(to: time)
    }

    /// 自己刚发出的弹幕：立即上屏，并记进时间轴，重新挂载引擎后仍在原位置出现。
    func appendSent(text: String, mode: DanmakuMode) {
        let item = DanmakuItem(time: lastTime, text: text, mode: mode.rawValue, color: 0xFFFFFF, isSelf: true)
        let index = items.firstIndex { $0.time > item.time } ?? items.endIndex
        items.insert(item, at: index)
        engine?.presentImmediately(item)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        engine?.setTimelinePaused(paused)
    }

    func shutdown() {
        loadTask?.cancel()
        loadTask = nil
        engine = nil
        items = []
    }
}

/// 弹幕层的 SwiftUI 桥。只在这里创建/销毁 UIKit 引擎并把它接给控制器。
struct DanmakuView: UIViewRepresentable {
    @AppStorage(DanmakuSettings.fontScaleKey) private var fontScale = DanmakuSettings.defaultFontScale
    @AppStorage(DanmakuSettings.opacityKey) private var opacity = DanmakuSettings.defaultOpacity
    @AppStorage(DanmakuSettings.blockTopKey) private var blockTop = DanmakuSettings.defaultBlockTop
    @AppStorage(DanmakuSettings.blockBottomKey) private var blockBottom = DanmakuSettings.defaultBlockBottom
    @AppStorage(DanmakuSettings.coloredEnabledKey) private var coloredEnabled = true
    let controller: DanmakuController
    var isFullScreen = false
    /// 画面收起成标题条时整个弹幕层一起隐藏。
    var isSuppressed = false

    func makeUIView(context: Context) -> DanmakuEngine {
        let engine = DanmakuEngine()
        controller.attach(engine)
        return engine
    }

    func updateUIView(_ engine: DanmakuEngine, context: Context) {
        engine.coloredEnabled = coloredEnabled
        engine.area = 0.5
        // 全屏观看距离更远，字号跟随 PiliPlus 的两档设置（内联 1.0 / 全屏 1.2）。
        engine.applyAppearance(fontSize: (isFullScreen ? 18 : 15) * fontScale, opacity: opacity, blockTop: blockTop, blockBottom: blockBottom)
        // 抑制（画面收起）时引擎整体短路：不注入、不推进，播放事件也不会
        // 唤醒它；隐藏属性让已上屏的冻结弹幕一并消失，恢复显示时由下一次
        // update/seek 继续正常注入。
        engine.isSuppressed = isSuppressed
        engine.isHidden = isSuppressed
    }

    static func dismantleUIView(_ engine: DanmakuEngine, coordinator: ()) {
        engine.removeFromSuperview()
    }
}
