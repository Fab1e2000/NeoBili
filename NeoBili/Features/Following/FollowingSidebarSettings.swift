import SwiftUI
import UIKit

/// 偏好同时供设置页和关注页使用，左右两侧采用相同的命中范围。
enum FollowingSidebarSide: String, CaseIterable, Identifiable {
    case left, right
    static let storageKey = "neobili.followingSidebarSide"
    var id: String { rawValue }
    var title: String { self == .left ? "左侧" : "右侧" }
    var alignment: Alignment { self == .left ? .leading : .trailing }
}

enum FollowingSidebarDwellSettings {
    static let storageKey = "neobili.followingSidebarDwellDuration"
    static let defaultDuration = 0.5
    static let range = 0.1...2.0

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultDuration
    }
}

enum FollowingSidebarLayout {
    static let transitionDuration: TimeInterval = 0.24
    static let countKey = "neobili.followingSidebarCount"
    static let counts = [5, 7, 9, 11]
    static let defaultCount = 7

    static func count(_ stored: Int) -> Int { counts.contains(stored) ? stored : defaultCount }
    static func height(count: Int, available: CGFloat) -> CGFloat {
        min(CGFloat(Self.count(count)) * 64, max(64, available - 48))
    }

    static func occupiedBounds(count: Int, rowHeight: CGFloat, offset: CGFloat, viewport: CGFloat) -> ClosedRange<CGFloat> {
        let padding = max(40, rowHeight / 2)
        let firstCenter = rowHeight / 2 - offset
        let lastCenter = CGFloat(max(0, count - 1)) * rowHeight + rowHeight / 2 - offset
        return max(0, min(viewport / 2 - 30, firstCenter - padding))...min(viewport, max(viewport / 2 + 30, lastCenter + padding))
    }
}
