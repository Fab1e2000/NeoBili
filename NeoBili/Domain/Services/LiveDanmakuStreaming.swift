import Foundation

public enum LiveDanmakuConnectionState: Equatable, Sendable {
    case idle, connecting, connected
}

public enum LiveDanmakuEvent: Sendable {
    case connection(LiveDanmakuConnectionState)
    case popularity(Int)
    case message(Data)
}

@MainActor
public protocol LiveDanmakuStreaming: AnyObject {
    func start(roomID: Int, onEvent: @escaping @MainActor (LiveDanmakuEvent) -> Void)
    func stop()
}
