import Foundation

enum PlayerGestureSettings {
    static let leftKey = "neobili.playerGesture.leftBoundary"
    static let rightKey = "neobili.playerGesture.rightBoundary"
    static let reverseKey = "neobili.playerGesture.reverseVertical"
    static func boundaries(left: Double, right: Double) -> (Double, Double) {
        let first = min(max(left.isFinite ? left : 0.33, 0.1), 0.75)
        let second = min(max(right.isFinite ? right : 0.67, first + 0.15), 0.9)
        return (first, second)
    }
}

