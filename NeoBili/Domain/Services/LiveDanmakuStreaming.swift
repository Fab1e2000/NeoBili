import Foundation

public enum LiveDanmakuConnectionState: Equatable, Sendable {
    case idle, connecting, connected
}

public enum LiveDanmakuEvent: Sendable {
    case connection(LiveDanmakuConnectionState)
    case popularity(Int)
    /// 已在数据层解析完成的消息；展示模型只应用，不接触原始 JSON。
    case parsed(LiveDanmakuParsedEvent)
}

@MainActor
public protocol LiveDanmakuStreaming: AnyObject {
    func start(roomID: Int, onEvent: @escaping @MainActor (LiveDanmakuEvent) -> Void)
    func stop()
}
