import Foundation

/// 「关注」页的数据：顶上那排 UP 主头像，加上他们的动态流。
///
/// 动态本身由 `DynamicFeedModel` 管（关注页和 UP 主空间页共用那一套翻页和
/// 点赞逻辑），这里只额外负责头像行。
@MainActor
@Observable
final class FollowingViewModel {
    let feed = DynamicFeedModel(source: .following)
    private(set) var ups: [FollowedUp] = []

    /// 头像行里选中的那个 UP。选中之后下面的列表就地换成他一个人的动态，
    /// 和官方客户端一样——不跳页，再点一次或者点关掉就回到全部关注。
    private(set) var selectedUp: FollowedUp?
    private(set) var upFeed: DynamicFeedModel?

    /// 列表当前用的数据源。
    var activeFeed: DynamicFeedModel { upFeed ?? feed }

    /// 点头像。点的是已经选中的那个人就取消选择。
    func select(_ up: FollowedUp) async {
        if selectedUp?.mid == up.mid {
            clearSelection()
            return
        }
        selectedUp = up
        let model = DynamicFeedModel(source: .space(hostMid: up.mid))
        upFeed = model
        await model.loadInitial()
    }

    func clearSelection() {
        selectedUp = nil
        upFeed = nil
    }

    func loadInitial() async {
        async let upList: Void = loadUpsIfNeeded()
        await feed.loadInitial()
        await upList
    }

    func refresh() async {
        // 选中某个 UP 时，下拉刷新刷的是他那一份，不去动整条关注流。
        if let upFeed {
            await upFeed.refresh()
            return
        }
        async let upList: Void = loadUps()
        await feed.refresh()
        await upList
    }

    private func loadUpsIfNeeded() async {
        guard ups.isEmpty else { return }
        await loadUps()
    }

    /// 头像行失败不该让整页变成错误页，所以这里把错误吞掉：
    /// 动态流本身还能正常显示。
    private func loadUps() async {
        guard let list = try? await BiliAPI.followedUps(), !Task.isCancelled else { return }
        ups = list
    }
}
