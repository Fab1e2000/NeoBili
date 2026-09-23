import Foundation

/// 一条弹幕的最小渲染必需信息。
/// mode 只保留能渲染的三类：1/2/3 滚动、4 底部、5 顶部；
/// 6/7/8/9（逆向、高级、代码、BAS）照 PiliPlus 的做法直接丢弃。
/// 弹幕出现的位置，取值即接口的 mode。
enum DanmakuMode: Int, CaseIterable, Identifiable {
    case scroll = 1
    case top = 5
    case bottom = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .scroll: "滚动"
        case .top: "顶部"
        case .bottom: "底部"
        }
    }
}

struct DanmakuItem: Sendable {
    let time: TimeInterval
    let text: String
    let isScroll: Bool
    let isTop: Bool
    let color: UInt32

    init(time: TimeInterval, text: String, mode: Int, color: UInt32) {
        self.time = time
        self.text = text
        self.isScroll = mode == 1 || mode == 2 || mode == 3
        self.isTop = mode == 5
        self.color = color
    }
}
