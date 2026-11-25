import NeoBiliDomain
import SwiftUI

/// 共用的短距离下拉刷新，阈值来自「浏览 → 滚动与防误触」。
/// 松手后旧内容淡出与请求并行，均完成后提交新内容，不显示系统转圈。
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
        fadeIn: Bool = false,
        fetch: @escaping @MainActor () async -> Bool,
        commit: @escaping @MainActor () -> Void,
        discard: @escaping @MainActor () -> Void
    ) {
        guard !isRefreshing else { return }
        task = Task { [self] in
            await run(hasContent: hasContent, animatesExit: animatesExit, source: source, category: category,
                      fadeIn: fadeIn, fetch: fetch, commit: commit, discard: discard)
        }
    }

    /// 动画设置或减弱动态效果中途关闭时恢复可见内容，请求与任务继续。
    func restoreContent() {
        guard isRefreshing, contentOpacity < 1 else { return }
        withAnimation(nil) { contentOpacity = 1 }
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
        fadeIn: Bool,
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
        var committed = false
        defer {
            if refreshID == requestID {
                discard()
                withAnimation(nil) {
                    // 提交后正常结束时模型值已是 1，不再改写以保留正在进行的换入淡入；
                    // 淡入等待期间被取消时仍要恢复可见。
                    if !committed || contentOpacity < 1 { contentOpacity = 1 }
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
        committed = true
        withAnimation(nil) {
            commit()
            contentOpacity = fadeIn ? 0 : 1
        }
        if fadeIn {
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard !Task.isCancelled, refreshID == requestID else { return }
            withAnimation(.easeIn(duration: FeedRefreshTuning.fadeIn)) { contentOpacity = 1 }
        }
    }
}

/// 观察现有滚动手势，达到「滚动与防误触」设置的距离后触发刷新。
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
