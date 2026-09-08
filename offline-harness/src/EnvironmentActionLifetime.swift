import SwiftUI

// 与三个宿主相同的 @State 所有权结构；只在 macOS 运行 ARC 验证，不创建窗口。
private struct PresentationHost {
    @State var presented: Int?
    @State var action = EnvironmentAction<Int> { _ in }

    func configure() {
        action.setHandler { [presented = $presented] in presented.wrappedValue = $0 }
    }
}

private final class Draft { var target = 0 }
private struct ReplyHost {
    let draft = Draft()
    @State var sending = false
    @State var focused = false
    @State var action = EnvironmentAction<Int> { _ in }

    func configure() {
        action.setHandler { [draft, sending = $sending, focused = $focused] value in
            guard !sending.wrappedValue else { return }
            draft.target = value
            focused.wrappedValue = true
        }
    }
}

@main struct EnvironmentActionLifetime {
    static func main() {
        weak var presentationAction: EnvironmentAction<Int>?
        do {
            let host = PresentationHost()
            presentationAction = host.action
            host.configure()
        }
        guard presentationAction == nil else { fatalError("弹层动作盒子没有释放") }
        print("PASS  弹层 Binding 捕获不保留宿主动作盒子")

        weak var replyAction: EnvironmentAction<Int>?
        weak var draft: Draft?
        do {
            let host = ReplyHost()
            replyAction = host.action
            draft = host.draft
            host.configure()
        }
        guard replyAction == nil, draft == nil else { fatalError("回复动作盒子或草稿没有释放") }
        print("PASS  回复动作盒子与草稿随宿主释放")
    }
}
