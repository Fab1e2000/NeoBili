import Foundation

/// 主页面。搜索是系统的搜索标签，固定在标签栏末尾，不参与排序。
enum MainTab: String, Hashable, CaseIterable, Identifiable {
    case live, home, following, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "直播"
        case .home: "推荐"
        case .following: "关注"
        case .search: "搜索"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .home: "house.fill"
        case .following: "person.2.fill"
        case .search: "magnifyingglass"
        }
    }

    /// 可以排序、也可以设为启动页的标签。
    static let reorderable: [MainTab] = [.live, .home, .following]
}

/// 标签栏的排序和启动时打开的页面。
enum MainTabSettings {
    static let orderKey = "neobili.tabOrder"
    static let launchKey = "neobili.launchTab"
    static let defaultOrder = MainTab.reorderable
    static let defaultLaunch = MainTab.home

    /// 存储格式为逗号分隔的 rawValue。未知项丢弃、缺项按默认顺序补到末尾，
    /// 以后增删标签时旧设置仍然可用。
    static func order(from stored: String) -> [MainTab] {
        var result: [MainTab] = []
        for tab in stored.split(separator: ",").compactMap({ MainTab(rawValue: String($0)) })
        where MainTab.reorderable.contains(tab) && !result.contains(tab) {
            result.append(tab)
        }
        return result + defaultOrder.filter { !result.contains($0) }
    }

    static func stored(_ order: [MainTab]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    static func launchTab(from stored: String) -> MainTab {
        MainTab(rawValue: stored).flatMap { MainTab.reorderable.contains($0) ? $0 : nil } ?? defaultLaunch
    }
}
