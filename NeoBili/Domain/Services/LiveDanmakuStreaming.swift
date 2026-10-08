import Foundation

enum LiveDanmakuConnectionState: Equatable, Sendable {
    case idle, connecting, connected
}

enum LiveDanmakuEvent: Sendable {
    case connection(LiveDanmakuConnectionState)
    case popularity(Int)
    case message(Data)
}

@MainActor
protocol LiveDanmakuStreaming: AnyObject {
    func start(roomID: Int, onEvent: @escaping @MainActor (LiveDanmakuEvent) -> Void)
    func stop()
}
