import SwiftUI
import UIKit
import Observation

/// 刷新退出、卡片原位淡入和主页面淡入的速度设置。
/// 保留原有存储键，让用户已选的速度继续生效。
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
    /// 现在不再等：淡出自己走完，数据没到就是空屏，到了再让新卡片淡入。
    static let fadeExitDuration: Double = 0.9

    static func fadeExit(speed: Double) -> Double {
        fadeExitDuration / AnimationSpeedSettings.clamped(speed)
    }

    // MARK: 原位淡入
    static let fadeInDuration: Double = 0.25
}

/// Only opacity changes; card geometry and hit-testing bounds stay fixed.
struct FeedFadeInEffect: ViewModifier {
    var progress: Double
    func body(content: Content) -> some View { content.opacity(progress) }
}

/// 包住首页的一行卡片，负责刷新完成后的淡入动画。
///
/// 刷新会把新视频插到列表最前面，行的 id 跟着变，所以首屏这几行在刷新后是
/// **全新的视图**而不是沿用下来的——淡入动画因此必须在创建时就能自己跑起来，
/// 光靠 `onChange(of: generation)` 是等不到的。行一出生就是全透明的起始态，
/// 不会先闪一下已经淡入的样子。
struct FeedFadeInRow<Content: View>: View {
    /// 淡入速度倍率，来自设置页。
    let speed: Double
    let reduceMotion: Bool
    let category: CardAnimationCategory
    @ViewBuilder var content: Content

    private var animations = CardAnimationPreferences()
    @Environment(\.videoEntranceID) private var videoID
    @Environment(\.videoEntranceClocks) private var entranceClocks
    @State private var legacyStart: TimeInterval?

    init(
        speed: Double,
        reduceMotion: Bool,
        category: CardAnimationCategory = .video,
        @ViewBuilder content: () -> Content
    ) {
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.category = category
        self.content = content()
    }

    private var animatable: Bool {
        !reduceMotion && animations.isEnabled(category: category, phase: .enter)
    }

    var body: some View {
        Group {
            if let videoID {
                // 起点来自整个列表的判断结果，卡片被懒加载回收也不会重置。
                let scope = entranceClocks.first { $0.ids.contains(videoID) }
                let start = scope?.start(for: videoID)
                TimedVideoEntrance(start: start, speed: speed, enabled: animatable) {
                    content
                }
            } else {
                legacyEntrance
            }
        }
        .environment(\.videoEntranceProvided, true)
    }

    private var legacyEntrance: some View {
        TimedVideoEntrance(start: legacyStart, speed: speed, enabled: animatable) {
            content
        }
        .task {
            // A stored monotonic start replaces per-row delayed Tasks and
            // implicit animation transactions. Recycled rows resume that clock.
            legacyStart = ProcessInfo.processInfo.systemUptime
        }
    }

}

extension EnvironmentValues {
    @Entry var videoEntranceProvided = false
    @Entry var videoEntranceID: String? = nil
    @Entry var videoEntranceClocks: [VideoEntranceScope] = []
}

private struct VideoCardEntrance: ViewModifier {
    var enabled = true
    var category: CardAnimationCategory = .video
    @Environment(\.videoEntranceProvided) private var provided
    @Environment(\.videoCardAnimationSource) private var source
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var speed = AnimationSpeedSettings.defaultSpeed

    func body(content: Content) -> some View {
        if provided || !enabled || !CardAnimationSettings.supports(category: category, phase: .enter, source: source) {
            content
        } else {
            FeedFadeInRow(speed: speed, reduceMotion: reduceMotion, category: category) {
                content
            }
        }
    }
}

extension View {
    func videoCardEntrance(enabled: Bool = true, category: CardAnimationCategory = .video) -> some View {
        modifier(VideoCardEntrance(enabled: enabled, category: category))
    }

    func videoEntranceIdentity(_ id: String?) -> some View {
        environment(\.videoEntranceID, id)
    }
}

struct VideoEntranceScope: Equatable {
    let ids: Set<String>
    let generation: Int
    let clock: VideoEntranceClock

    @MainActor func start(for id: String) -> TimeInterval? {
        clock.generation == generation ? clock.start(for: id) : nil
    }

    /// 列表每次重算都会生成新的 scope；内容相同就视为没变，卡片不必跟着重算。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.clock === rhs.clock && lhs.generation == rhs.generation && lhs.ids == rhs.ids
    }
}

/// 由调用方直接给出入场起点的版本，不经过环境里的入场时钟。
///
/// 放进 UIKit 列表格子（UIHostingConfiguration）里的 SwiftUI 内容，刚被复用、换上
/// 新内容时对时钟的观察有时收不到变化通知，卡片会一直停在入场起点（透明）。
/// 这类列表由 UIKit 一侧监听时钟，在配置格子时把起点直接传进来。
struct TimedFeedEntrance<Content: View>: View {
    let start: TimeInterval?
    let speed: Double
    let reduceMotion: Bool
    let category: CardAnimationCategory
    @ViewBuilder var content: Content
    private var animations = CardAnimationPreferences()

    init(start: TimeInterval?, speed: Double, reduceMotion: Bool,
         category: CardAnimationCategory = .video, @ViewBuilder content: () -> Content) {
        self.start = start
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.category = category
        self.content = content()
    }

    var body: some View {
        TimedVideoEntrance(start: start, speed: speed,
                           enabled: !reduceMotion && animations.isEnabled(category: category, phase: .enter)) {
            content
        }
        .environment(\.videoEntranceProvided, true)
    }
}

private struct TimedVideoEntrance<Content: View>: View {
    let start: TimeInterval?
    let speed: Double
    let enabled: Bool
    @ViewBuilder var content: Content
    @State private var finishedStart: TimeInterval?

    private var finished: Bool { start != nil && finishedStart == start }

    private var duration: Double {
        FeedRefreshTuning.fadeInDuration / AnimationSpeedSettings.clamped(speed)
    }

    private var progress: Double {
        guard enabled, !finished else { return 1 }
        guard start != nil else { return 0 }
        let fraction = min(1, elapsed / duration)
        return fraction * fraction * (3 - 2 * fraction)
    }

    private var elapsed: TimeInterval {
        guard let start else { return 0 }
        return max(0, ProcessInfo.processInfo.systemUptime - start)
    }

    var body: some View {
        // Disabled effects never wait for a clock or suppress hit testing.
        // TimelineView has no running display link once settled or disabled.
        TimelineView(.animation(paused: !enabled || start == nil || finished || elapsed >= duration)) { _ in
            content.modifier(FeedFadeInEffect(progress: progress))
        }
        .allowsHitTesting(!enabled || finished || start != nil)
        .onChange(of: enabled) { _, enabled in
            if !enabled { finishedStart = start }
        }
        .task(id: EntranceTaskID(start: start, enabled: enabled, speed: speed)) {
            if !enabled {
                finishedStart = start
                return
            }
            guard enabled, start != nil, !finished else { return }
            // 滚动时懒加载重新创建的卡片早已淡入：直接返回，不再多写一次状态让整张卡重算。
            guard elapsed < duration else { return }
            let delay = max(0, (start ?? 0) - ProcessInfo.processInfo.systemUptime)
            let remaining = max(0, duration - elapsed) + delay
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            finishedStart = start
        }
    }

    private struct EntranceTaskID: Hashable {
        let start: TimeInterval?
        let enabled: Bool
        let speed: Double
    }

}

/// The request and exit run concurrently; fast responses wait only for the
/// remaining exit time, slow responses never start a second fade.
struct FeedRefreshExitTiming {
    let start: TimeInterval
    let duration: TimeInterval

    func remaining(at now: TimeInterval) -> TimeInterval {
        max(0, duration - max(0, now - start))
    }
}
