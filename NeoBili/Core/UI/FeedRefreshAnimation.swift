import SwiftUI
import UIKit
import Observation

/// 首页刷新动画的全部可调参数。
///
/// 三段式：松手后旧卡片原地缓慢淡出；数据没回来就停在很淡的残留上（可以无限久）；
/// 数据到达后残留淡尽，新卡从镜头前上方落下。
///
/// 退出动画作用在真实的卡片视图上，只改一个 opacity——不位移、不缩放、不截图。
/// 之前用滚动视图的位图做残影，位图和真实视图的位置总对不齐，就是"闪到下方"的来源。
/// 这些数字是拍脑袋的初值，真机上边看边改就行，改完不用动别的地方。
/// 界面动画的快慢。倍率越大越快，实际时长是基准时长除以倍率。
/// 设置页给两条滑杆：退出（旧内容离场）和进入（新内容登场）。
///
/// 目前管两处：首页下拉刷新的淡出/落位，以及三个主页面之间的切换。
/// 键名里的 feed 是历史遗留，改了会丢掉用户已经存下的档位，所以留着。
enum AnimationSpeedSettings {
    static let exitSpeedKey = "neobili.feedExitSpeed"
    static let enterSpeedKey = "neobili.feedEnterSpeed"
    static let defaultSpeed = 1.0
    static let range = 0.1...10.0

    /// 主页面切换时单侧淡出/淡入的基准时长。
    ///
    /// 比刷新的淡出短得多：Tab 的高亮要等内容切完才会移动（TabView 的高亮和
    /// 内容共用同一个 selection），淡出太长就会显得"点了没反应"。
    static let tabFadeDuration: Double = 0.25

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultSpeed
    }

    static func tabFade(speed: Double) -> Double {
        tabFadeDuration / clamped(speed)
    }
}

enum FeedRefreshTuning {
    // MARK: 淡出（旧内容退出）

    /// 旧卡片淡尽所需的时间，与网络无关：松手就开始，跑完就是跑完。
    ///
    /// 早先的版本会在中途停在一个很淡的浓度上等数据，好处是慢网络下画面不全空，
    /// 代价是那个停顿看起来像卡死——尤其把速度调快之后，停顿来得更早也更明显。
    /// 现在不再等：淡出自己走完，数据没到就是空屏，到了再让新卡片落位。
    static let fadeExitDuration: Double = 0.9

    static func fadeExit(speed: Double) -> Double {
        fadeExitDuration / AnimationSpeedSettings.clamped(speed)
    }

    // MARK: 落位（新内容）

    /// 新卡起始位置在屏幕上方多远。
    static let dropRise: CGFloat = 170
    /// 起始比最终大，等于离镜头更近。
    static let dropScale: CGFloat = 1.24
    /// 绕 X 轴前倾，配合 perspective 做出"朝着用户的上方"。
    static let dropTilt: Double = -16
    static let dropPerspective: CGFloat = 0.55
    /// 相邻两行的落位间隔（倍率为 1 时）。
    static let staggerDuration: Double = 0.055
    /// 限制行间错峰的最大延迟，不限制播放动画的卡片数量。
    static let staggerRows = 4
    /// 单行落位的基准时长。
    static let landingDuration: Double = 0.55
    static let landingBounce: Double = 0.08

    static func stagger(speed: Double) -> Double { staggerDuration / AnimationSpeedSettings.clamped(speed) }

    static func landing(speed: Double) -> Animation {
        .snappy(duration: landingDuration / AnimationSpeedSettings.clamped(speed), extraBounce: landingBounce)
    }

    /// 落位窗口：这段时间内新建出来的行才播落位动画。
    /// 关掉之后再新建的行（比如用户滚下去又滚回来）保持原样，
    /// 否则就成了"滚到哪掉到哪"。
    static func landingWindow(speed: Double) -> Double {
        (landingDuration + staggerDuration * Double(staggerRows)) / AnimationSpeedSettings.clamped(speed)
    }

    // MARK: 下拉过程

    /// 下拉到阈值时列表淡掉的幅度，是退出动画的预告，也代替原来那颗提示胶囊。
    /// 松手后就从这个浓度接着往下淡，中间没有跳变。
    static let pullFade: Double = 0.18
}

/// 新卡的落位变换。`progress` 0 = 起始（镜头前上方），1 = 落到位。
struct FeedDropInEffect: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        let remaining = 1 - progress
        content
            .scaleEffect(1 + (FeedRefreshTuning.dropScale - 1) * remaining)
            .rotation3DEffect(
                .degrees(FeedRefreshTuning.dropTilt * remaining),
                axis: (x: 1, y: 0, z: 0),
                perspective: FeedRefreshTuning.dropPerspective
            )
            .offset(y: -FeedRefreshTuning.dropRise * remaining)
            .opacity(progress)
    }
}

/// 包住首页的一行卡片，负责刷新完成后的落位动画。
///
/// 刷新会把新视频插到列表最前面，行的 id 跟着变，所以首屏这几行在刷新后是
/// **全新的视图**而不是沿用下来的——落位动画因此必须在创建时就能自己跑起来，
/// 光靠 `onChange(of: generation)` 是等不到的。行一出生就是全透明的起始态，
/// 不会先闪一下已经落位的样子。
struct FeedDropInRow<Content: View>: View {
    let index: Int
    let generation: Int
    /// 保留刷新调用方的窗口参数；新卡片入场不再受窗口或行数限制。
    let landing: Bool
    /// 落位速度倍率，来自设置页。
    let speed: Double
    let reduceMotion: Bool
    @ViewBuilder var content: Content

    @Environment(\.videoEntranceID) private var videoID
    @Environment(\.videoEntranceClocks) private var entranceClocks
    @State private var progress: Double
    /// 新卡片从隐藏状态开始；任务取消后保留等待状态，再出现时继续入场。
    @State private var awaitingLanding: Bool
    /// 已经为哪一代播过动画，避免同一代播两次。
    @State private var playedGeneration: Int?

    init(
        index: Int,
        generation: Int,
        landing: Bool,
        speed: Double,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.index = index
        self.generation = generation
        self.landing = landing
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.content = content()
        let startsHidden = !reduceMotion
        _progress = State(initialValue: startsHidden ? 0 : 1)
        _awaitingLanding = State(initialValue: startsHidden)
    }

    /// 沿用下来的行（id 没变）在换代时要不要重播。换代只发生在刷新那一刻，
    /// 那时窗口一定是开着的，所以这里不必再看 `landing`。
    private var animatable: Bool {
        !reduceMotion
    }

    var body: some View {
        Group {
            if let videoID {
                // 起点来自整个列表的判断结果，卡片被懒加载回收也不会重置。
                let scope = entranceClocks.first { $0.ids.contains(videoID) }
                let start = scope?.start(for: videoID)
                TimedVideoEntrance(start: start, speed: speed, reduceMotion: reduceMotion) {
                    content
                }
            } else {
                legacyEntrance
            }
        }
        .environment(\.videoEntranceProvided, true)
    }

    private var legacyEntrance: some View {
        content
            .modifier(FeedDropInEffect(progress: progress))
            // 刷新后新建出来的行走这条。用结构化的 task 而不是自己起 Task：
            // 视图被回收重建时它会跟着取消，新实例按自己的 init 重新决定。
            .task {
                guard awaitingLanding else { return }
                // 隔一帧再启动：同一帧内改两次状态会被合并成"没有动画"。
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                awaitingLanding = false
                playedGeneration = generation
                withAnimation(landingAnimation) { progress = 1 }
            }
            // id 没变、被沿用下来的行走这条（比如刷新没拿到新内容）。
            .onChange(of: generation) {
                guard animatable, playedGeneration != generation else { return }
                playedGeneration = generation
                progress = 0
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(16))
                    withAnimation(landingAnimation) { progress = 1 }
                }
            }

    }

    private var landingAnimation: Animation {
        FeedRefreshTuning.landing(speed: speed)
            .delay(Double(min(index, FeedRefreshTuning.staggerRows - 1)) * FeedRefreshTuning.stagger(speed: speed))
    }
}


extension EnvironmentValues {
    @Entry var videoEntranceProvided = false
    @Entry var videoEntranceID: String? = nil
    @Entry var videoEntranceClocks: [VideoEntranceScope] = []
}

private struct VideoCardEntrance: ViewModifier {
    var enabled = true
    @Environment(\.videoEntranceProvided) private var provided
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var speed = AnimationSpeedSettings.defaultSpeed

    func body(content: Content) -> some View {
        if provided || !enabled {
            content
        } else {
            FeedDropInRow(index: 0, generation: 0, landing: true, speed: speed, reduceMotion: reduceMotion) {
                content
            }
        }
    }
}

extension View {
    func videoCardEntrance(enabled: Bool = true) -> some View { modifier(VideoCardEntrance(enabled: enabled)) }

    func videoEntranceIdentity(_ id: String?) -> some View {
        environment(\.videoEntranceID, id)
    }
}


/// 每个列表独立保存已通过判断的卡片起点，不依赖卡片视图是否存在。
@MainActor @Observable
final class VideoEntranceClock {
    private(set) var starts: [String: TimeInterval] = [:]
    private(set) var generation = 0

    func prepare(ids: Set<String>, generation: Int, reset: Bool) {
        self.generation = generation
        starts = reset ? [:] : starts.filter { ids.contains($0.key) }
    }

    func admit(_ ids: [String]) {
        let active = Set(ids)
        let now = ProcessInfo.processInfo.systemUptime
        var updated = starts.filter { active.contains($0.key) }
        for id in ids where updated[id] == nil { updated[id] = now }
        if updated != starts { starts = updated }
    }
}

struct VideoEntranceScope {
    let ids: Set<String>
    let generation: Int
    let clock: VideoEntranceClock

    @MainActor func start(for id: String) -> TimeInterval? {
        clock.generation == generation ? clock.starts[id] : nil
    }
}

private struct TimedVideoEntrance<Content: View>: View {
    let start: TimeInterval?
    let speed: Double
    let reduceMotion: Bool
    @ViewBuilder var content: Content
    @State private var finished = false

    private var spring: Spring {
        .snappy(duration: FeedRefreshTuning.landingDuration / AnimationSpeedSettings.clamped(speed),
                extraBounce: FeedRefreshTuning.landingBounce)
    }

    private var elapsed: TimeInterval {
        guard let start else { return 0 }
        return max(0, ProcessInfo.processInfo.systemUptime - start)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || start == nil || finished || elapsed >= spring.settlingDuration)) { _ in
            let progress = start == nil ? 0 : (reduceMotion || elapsed >= spring.settlingDuration
                ? 1 : spring.value(target: 1.0, time: elapsed))
            content.modifier(FeedDropInEffect(progress: progress))
        }
        .allowsHitTesting(start != nil)
        // 这里只停止已完成的屏幕绘制；动画的起点、进度不由 task 或 onAppear 决定。
        .task(id: start) {
            finished = false
            guard start != nil, !reduceMotion else { return }
            let remaining = max(0, spring.settlingDuration - elapsed)
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            finished = true
        }
    }
}


/// 刷新分隔条沿用整批视频的入场起点，包括屏幕外的提示条。
private struct VideoBatchEntrance: ViewModifier {
    @Environment(\.videoEntranceClocks) private var scopes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var speed = AnimationSpeedSettings.defaultSpeed

    func body(content: Content) -> some View {
        let scope = scopes.first
        let start = scope.flatMap { scope in
            scope.clock.generation == scope.generation ? scope.clock.starts.values.min() : nil
        }
        TimedVideoEntrance(start: start, speed: speed, reduceMotion: reduceMotion) {
            content
        }
    }
}

extension View {
    func videoBatchEntrance() -> some View { modifier(VideoBatchEntrance()) }
}
