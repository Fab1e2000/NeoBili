import Foundation

/// 主页面。搜索是系统的搜索标签，固定在标签栏末尾，不参与排序和隐藏。
enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case live, home, following, watchLater, favorites, history, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: String(localized: "直播")
        case .home: String(localized: "推荐")
        case .following: String(localized: "关注")
        case .watchLater: String(localized: "稍后再看")
        case .favorites: String(localized: "收藏")
        case .history: String(localized: "历史")
        case .search: String(localized: "搜索")
        }
    }

    /// 页头上的完整标题；标签栏空间有限，用上面的短标题。
    var pageTitle: String {
        switch self {
        case .favorites: String(localized: "我的收藏")
        case .history: String(localized: "历史记录")
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .home: "house.fill"
        case .following: "person.2.fill"
        case .watchLater: "flag.checkered"
        case .favorites: "star.fill"
        case .history: "clock.arrow.circlepath"
        case .search: "magnifyingglass"
        }
    }

    /// 可以排序、隐藏、设为启动页的标签。
    static let reorderable: [MainTab] = [.live, .home, .following, .watchLater, .favorites, .history]
}

/// 标签栏的排序、隐藏和启动时打开的页面。
enum MainTabSettings {
    static let orderKey = "neobili.tabOrder"
    static let hiddenKey = "neobili.hiddenTabs"
    static let launchKey = "neobili.launchTab"
    static let defaultOrder = MainTab.reorderable
    /// 新加入的列表页默认收起，保持原来的三个主页面。
    static let defaultHidden: Set<MainTab> = [.watchLater, .favorites, .history]
    static let defaultLaunch = MainTab.home
    /// 标签栏最多 5 个：超过 5 个时系统会自动生成「更多」并把搜索挤出末尾，所以不允许超出。
    /// 搜索占一个，其余最多 4 个。
    static let maxVisible = 4

    /// 存储格式为逗号分隔的 rawValue。未知项丢弃、缺项按默认顺序补到末尾，
    /// 以后增删标签时旧设置仍然可用。
    static func order(from stored: String) -> [MainTab] {
        let result = tabs(from: stored)
        return result + defaultOrder.filter { !result.contains($0) }
    }

    /// 未保存过时用默认隐藏项；保存过（包括全部显示时的空串）就以保存的为准。
    static func hidden(from stored: String?) -> Set<MainTab> {
        guard let stored else { return defaultHidden }
        return Set(tabs(from: stored))
    }

    /// 实际隐藏的标签：用户隐藏的，加上超出上限、排在后面的。
    static func effectiveHidden(order: String, hidden: String?) -> Set<MainTab> {
        let hidden = self.hidden(from: hidden)
        let overflow = self.order(from: order).filter { !hidden.contains($0) }.dropFirst(maxVisible)
        return hidden.union(overflow)
    }

    static func stored(_ tabs: some Sequence<MainTab>) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }

    /// 标签栏实际显示的页面。至少保留一个，全部隐藏时退回推荐页。
    static func visible(order: String, hidden: String?) -> [MainTab] {
        let hidden = effectiveHidden(order: order, hidden: hidden)
        let visible = self.order(from: order).filter { !hidden.contains($0) }
        return visible.isEmpty ? [defaultLaunch] : visible
    }

    /// 启动页若被隐藏，就打开第一个显示的标签。
    static func launchTab(from stored: String, visible: [MainTab]) -> MainTab {
        let preferred = MainTab(rawValue: stored) ?? defaultLaunch
        return visible.contains(preferred) ? preferred : visible.first ?? defaultLaunch
    }

    private static func tabs(from stored: String) -> [MainTab] {
        var result: [MainTab] = []
        for tab in stored.split(separator: ",").compactMap({ MainTab(rawValue: String($0)) })
        where MainTab.reorderable.contains(tab) && !result.contains(tab) {
            result.append(tab)
        }
        return result
    }
}
