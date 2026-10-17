import Foundation

/// Freeze the part being viewed when a route is pushed; return in LIFO order.
struct PlaybackNavigationHistory {
    private var routes: [VideoDetailRoute] = []
    var canGoBack: Bool { !routes.isEmpty }

    mutating func record(_ route: VideoDetailRoute, activeCid: Int?) {
        var snapshot = route
        snapshot.cid = activeCid ?? route.cid
        routes.append(snapshot)
    }

    mutating func pop() -> VideoDetailRoute? { routes.popLast() }
    mutating func reset() { routes.removeAll() }
}
