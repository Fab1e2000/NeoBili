import Foundation

public enum PlayerGestureSettings {
    public static let leftKey = "neobili.playerGesture.leftBoundary"
    public static let rightKey = "neobili.playerGesture.rightBoundary"
    public static let reverseKey = "neobili.playerGesture.reverseVertical"
    public static func boundaries(left: Double, right: Double) -> (Double, Double) {
        let first = min(max(left.isFinite ? left : 0.33, 0.1), 0.75)
        let second = min(max(right.isFinite ? right : 0.67, first + 0.15), 0.9)
        return (first, second)
    }
}

