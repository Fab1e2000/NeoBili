import Foundation

/// 环境值里传递「打开某个弹层」这类动作时用的引用盒子。
///
/// 对象身份保持稳定，避免宿主更新时仅因创建新闭包而改变环境动作的身份。
/// 实际视图更新频率还取决于其它状态和环境依赖，需在运行时测量。
///
/// handler 不得捕获持有本盒子的宿主整体，否则会形成循环引用。
/// 请显式捕获所需 Binding、值或独立模型；不要隐式捕获 self。
final class EnvironmentAction<Argument> {
    private var handler: (Argument) -> Void

    init(handler: @escaping (Argument) -> Void) {
        self.handler = handler
    }

    /// body 里调用，让盒子始终持有最新一轮的处理闭包。
    func setHandler(_ handler: @escaping (Argument) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ argument: Argument) {
        handler(argument)
    }
}

extension EnvironmentAction: Equatable {
    static func == (lhs: EnvironmentAction, rhs: EnvironmentAction) -> Bool {
        lhs === rhs
    }
}
