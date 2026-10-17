import Foundation

/// 一条弹幕的最小渲染必需信息。
/// mode 只保留能渲染的三类：1/2/3 滚动、4 底部、5 顶部；
/// 6/7/8/9（逆向、高级、代码、BAS）照 PiliPlus 的做法直接丢弃。
/// 弹幕出现的位置，取值即接口的 mode。
public enum DanmakuMode: Int, CaseIterable, Identifiable, Sendable {
    case scroll = 1
    case top = 5
    case bottom = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .scroll: String(localized: "滚动")
        case .top: String(localized: "顶部")
        case .bottom: String(localized: "底部")
        }
    }
}

public struct DanmakuItem: Sendable {
    public let time: TimeInterval
    public let text: String
    public let isScroll: Bool
    public let isTop: Bool
    public let color: UInt32
    /// 自己发送的弹幕，上屏时带一个方框（与官方客户端、PiliPlus 一致）。
    public let isSelf: Bool

    public init(time: TimeInterval, text: String, mode: Int, color: UInt32, isSelf: Bool = false) {
        self.time = time
        self.text = text
        self.isScroll = mode == 1 || mode == 2 || mode == 3
        self.isTop = mode == 5
        self.color = color
        self.isSelf = isSelf
    }
}
