import Foundation

/// 关注页轮盘中的一个选择目标。视觉焦点和真正用来筛选动态的
/// 目标分开保存，快速滑过头像时才不会逐个发起请求。
enum FollowingSelection: Hashable, Identifiable, Sendable {
    enum ID: Hashable, Sendable {
        case all
        case up(Int)
    }

    case all
    case up(FollowedUp)

    var id: ID {
        switch self {
        case .all: .all
        case .up(let up): .up(up.mid)
        }
    }

    var title: String {
        switch self {
        case .all: "全部动态"
        case .up(let up): up.uname
        }
    }

    var up: FollowedUp? {
        guard case .up(let up) = self else { return nil }
        return up
    }
}

/// 「关注」页的数据：顶上那排 UP 主头像，加上他们的动态流。
///
/// 动态本身由 `DynamicFeedModel` 管（关注页和 UP 主空间页共用那一套翻页和
/// 点赞逻辑），这里只额外负责头像行。
@MainActor
@Observable
final class FollowingViewModel {
    private(set) var feed = DynamicFeedModel(source: .following)
    private(set) var ups: [FollowedUp] = []

    /// 轮盘停稳后真正提交给下方列表的选择。
    private(set) var selectedTarget: FollowingSelection = .all

    /// 本次进入关注页后看过的 UP 动态。切回时复用已有数据，
    /// 页面本身负责把纵向滚动位置送回顶部。
    private var upFeeds: [Int: DynamicFeedModel] = [:]

    var carouselItems: [FollowingSelection] {
        [.all] + ups.map(FollowingSelection.up)
    }

    var selectedUp: FollowedUp? { selectedTarget.up }

    /// 列表当前用的数据源。
    var activeFeed: DynamicFeedModel {
        switch selectedTarget {
        case .all:
            feed
        case .up(let up):
            upFeeds[up.mid] ?? feed
        }
    }

    /// 轮盘停稳时只提交选择；数据加载由视图生命周期任务调用，
    /// 便于在页面消失或下一次选择时正常取消等待。
    func select(_ target: FollowingSelection) {
        selectedTarget = target
        if case .up(let up) = target, upFeeds[up.mid] == nil {
            upFeeds[up.mid] = DynamicFeedModel(source: .space(hostMid: up.mid))
        }
    }

    func loadSelectedIfNeeded() async {
        let model = activeFeed
        await model.loadInitial()
    }

    func loadInitial() async {
        async let upList: Void = loadUpsIfNeeded()
        await feed.loadInitial()
        await upList
    }

    func refresh() async {
        // 选中某个 UP 时，下拉刷新刷的是他那一份，不去动整条关注流。
        if selectedUp != nil {
            await activeFeed.refresh()
            return
        }
        async let upList: Void = loadUps()
        await feed.refresh()
        await upList
    }

    /// 账号变化后不能继续展示上一个账号的头像或缓存动态。
    func resetForAccountChange() {
        feed = DynamicFeedModel(source: .following)
        ups = []
        upFeeds = [:]
        selectedTarget = .all
    }

    private func loadUpsIfNeeded() async {
        guard ups.isEmpty else { return }
        await loadUps()
    }

    /// 头像行失败不该让整页变成错误页，所以这里把错误吞掉：
    /// 动态流本身还能正常显示。
    private func loadUps() async {
        guard let list = try? await BiliAPI.followedUps(), !Task.isCancelled else { return }
        replaceUps(list)
    }

    /// 服务端列表刷新时保留同一个 mid 的选择；如果它已不在轮盘里，
    /// 回退到「全部动态」。这个入口也让纯状态行为可以不经网络地测试。
    func replaceUps(_ list: [FollowedUp]) {
        var seen = Set<Int>()
        ups = list.filter { seen.insert($0.mid).inserted }

        guard case .up(let selected) = selectedTarget else { return }
        if let refreshed = ups.first(where: { $0.mid == selected.mid }) {
            selectedTarget = .up(refreshed)
        } else {
            selectedTarget = .all
        }
    }

}
