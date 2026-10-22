#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

enum FeedRefreshTuning {
    // MARK: 淡出（旧内容退出）

    /// 旧卡片淡尽所需的时间，与网络无关：松手就开始，跑完就是跑完。
    ///
    /// 早先的版本会在中途停在一个很淡的浓度上等数据，好处是慢网络下画面不全空，
    /// 代价是那个停顿看起来像卡死——尤其把速度调快之后，停顿来得更早也更明显。
    /// 现在不再等：淡出自己走完，数据没到就是空屏，到了再让新卡片淡入。
    static let fadeExitDuration: Double = 0.9

    static let fadeExit = fadeExitDuration / AnimationSpeedSettings.exitSpeed

    // MARK: 原位淡入
    static let fadeInDuration: Double = 0.25
    static let fadeIn = fadeInDuration / AnimationSpeedSettings.enterSpeed
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
    let reduceMotion: Bool
    let category: CardAnimationCategory
    @ViewBuilder var content: Content

    private var animations = CardAnimationPreferences()
    @Environment(\.videoEntranceID) private var videoID
    @Environment(\.videoEntranceClocks) private var entranceClocks
    @State private var legacyStart: TimeInterval?

    init(
        reduceMotion: Bool,
        category: CardAnimationCategory = .video,
        @ViewBuilder content: () -> Content
    ) {
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
                TimedVideoEntrance(start: start, enabled: animatable) {
                    content
                }
            } else {
                legacyEntrance
            }
        }
        .environment(\.videoEntranceProvided, true)
    }

    private var legacyEntrance: some View {
        TimedVideoEntrance(start: legacyStart, enabled: animatable) {
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

    func body(content: Content) -> some View {
        if provided || !enabled || !CardAnimationSettings.supports(category: category, phase: .enter, source: source) {
            content
        } else {
            FeedFadeInRow(reduceMotion: reduceMotion, category: category) {
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
    let reduceMotion: Bool
    let category: CardAnimationCategory
    @ViewBuilder var content: Content
    private var animations = CardAnimationPreferences()

    init(start: TimeInterval?, reduceMotion: Bool,
         category: CardAnimationCategory = .video, @ViewBuilder content: () -> Content) {
        self.start = start
        self.reduceMotion = reduceMotion
        self.category = category
        self.content = content()
    }

    var body: some View {
        TimedVideoEntrance(start: start,
                           enabled: !reduceMotion && animations.isEnabled(category: category, phase: .enter)) {
            content
        }
        .environment(\.videoEntranceProvided, true)
    }
}

private struct TimedVideoEntrance<Content: View>: View {
    let start: TimeInterval?
    let enabled: Bool
    @ViewBuilder var content: Content
    @State private var presentationProgress: Double = 0

    private var duration: Double { FeedRefreshTuning.fadeIn }

    private var elapsed: TimeInterval {
        guard let start else { return 0 }
        return max(0, ProcessInfo.processInfo.systemUptime - start)
    }

    var body: some View {
        // Native opacity interpolation avoids one TimelineView/body update per
        // visible card per frame. Recycled, completed cards are visible immediately.
        content
            .modifier(FeedFadeInEffect(progress: !enabled || (start != nil && elapsed >= duration)
                                      ? 1 : presentationProgress))
            .allowsHitTesting(!enabled || start != nil)
            .task(id: EntranceTaskID(start: start, enabled: enabled)) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                let initial = !enabled ? 1 : (start == nil ? 0 : min(1, elapsed / duration))
                withTransaction(transaction) { presentationProgress = initial }
                guard enabled, let start, initial < 1 else { return }
                let delay = max(0, start - ProcessInfo.processInfo.systemUptime)
                // Also yield once for a newly inserted row so the initial opacity
                // is committed before animating. Cancellation follows row reuse.
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                let remaining = max(0, duration - elapsed)
                withAnimation(.easeInOut(duration: remaining)) { presentationProgress = 1 }
            }
    }

    private struct EntranceTaskID: Hashable {
        let start: TimeInterval?
        let enabled: Bool
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
