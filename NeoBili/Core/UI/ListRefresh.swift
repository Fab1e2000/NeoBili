#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 与推荐、直播、关注一致的列表手动刷新：自绘短距离下拉（距离见「推荐流」设置），松手后旧内容
/// 淡出，请求同时进行，淡出和请求都结束后一次换上新内容；全程没有系统转圈。
///
/// 页面只提供三件事：`fetch` 取回新数据但先不显示，`commit` 把它换进列表，`discard` 放弃它。
/// 动作跑在控制器自己持有的任务里，列表内容变化不会取消请求。
@MainActor @Observable
final class ListRefreshController {
    private(set) var isRefreshing = false
    private(set) var contentOpacity = 1.0
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(
        hasContent: Bool, animatesExit: Bool, source: VideoCardAnimationSource,
        category: CardAnimationCategory = .video,
        fetch: @escaping @MainActor () async -> Bool,
        commit: @escaping @MainActor () -> Void,
        discard: @escaping @MainActor () -> Void
    ) {
        guard !isRefreshing else { return }
        task = Task { [self] in
            await run(hasContent: hasContent, animatesExit: animatesExit, source: source, category: category,
                      fetch: fetch, commit: commit, discard: discard)
        }
    }

    /// 页面消失、换账号时恢复到静止状态，丢弃进行中的刷新。
    func reset(discard: @MainActor () -> Void = {}) {
        task?.cancel()
        task = nil
        discard()
        refreshID = UUID()
        withAnimation(nil) {
            contentOpacity = 1
            isRefreshing = false
        }
    }

    private func run(
        hasContent: Bool, animatesExit: Bool, source: VideoCardAnimationSource, category: CardAnimationCategory,
        fetch: @MainActor () async -> Bool,
        commit: @MainActor () -> Void,
        discard: @MainActor () -> Void
    ) async {
        let requestID = UUID()
        refreshID = requestID
        isRefreshing = true
        let duration = animatesExit && hasContent ? FeedRefreshTuning.fadeExit : 0
        let exitStart = ProcessInfo.processInfo.systemUptime
        if duration > 0 { withAnimation(.easeOut(duration: duration)) { contentOpacity = 0 } }
        defer {
            if refreshID == requestID {
                discard()
                withAnimation(nil) {
                    contentOpacity = 1
                    isRefreshing = false
                }
            }
        }
        // 请求失败时 defer 直接恢复旧内容。
        guard await fetch(), !Task.isCancelled, refreshID == requestID else { return }
        if duration > 0 {
            let remaining = max(0, duration - (ProcessInfo.processInfo.systemUptime - exitStart))
            do {
                try await CardAnimationSettings.waitWhileEnabled(
                    for: remaining, category: category, phase: .exit, source: source)
            } catch { return }
        }
        guard !Task.isCancelled, refreshID == requestID else { return }
        withAnimation(nil) {
            commit()
            contentOpacity = 1
        }
    }
}

/// 放在 ScrollView 内容的背景里，观察现有滚动手势，达到「推荐流」设置的距离时触发刷新。
struct ListPullRefresh: View {
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    let enabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        ShortPullRefresh(threshold: refreshDistance, enabled: enabled, onProgress: { _, _ in }, onRefresh: onRefresh)
    }
}

private struct ListEntranceModifier: ViewModifier {
    let ids: [String]
    let generation: Int
    private var animations: VideoCardAnimationPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = VideoEntranceClock()
    @State private var previousGeneration: Int?

    private struct Batch: Hashable {
        let ids: [String]
        let generation: Int
    }

    init(ids: [String], generation: Int, source: VideoCardAnimationSource) {
        self.ids = ids
        self.generation = generation
        animations = VideoCardAnimationPreferences(source: source)
    }

    private var animatesEnter: Bool { !reduceMotion && animations.isEnabled(phase: .enter) }

    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.videoEntranceClocks) {
                $0.append(VideoEntranceScope(ids: Set(ids), generation: generation, clock: clock))
            }
            .task(id: Batch(ids: ids, generation: generation)) {
                clock.prepare(ids: Set(ids), generation: generation, reset: previousGeneration != generation)
                clock.admit(ids, animated: animatesEnter)
                previousGeneration = generation
            }
            .onChange(of: animatesEnter) { _, enabled in
                if !enabled { clock.finishAnimations() }
            }
    }
}

extension View {
    /// 列表卡片的进入动画：每张卡片用 `videoEntranceIdentity` 报上自己的标识，
    /// `generation` 变化（首次加载、刷新换入）时整批重新计时，分页追加的卡片只淡入自己。
    func listEntrance(ids: [String], generation: Int, source: VideoCardAnimationSource) -> some View {
        modifier(ListEntranceModifier(ids: ids, generation: generation, source: source))
    }
}
