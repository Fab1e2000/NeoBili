import Foundation

// 主题图标请求循环的宿主机回归。swiftc 直接编译生产 ThemeIconController.swift，
// 这里只有 AppTheme 的形状桩（它的 SwiftUI Color 与图标请求无关）。
//
// 核心回归：请求成功提交后，即使系统上报的图标名滞后（部分系统上
// alternateIconName 在成功 setAlternateIconName 之后仍返回旧值），
// 也必须立即结束，不得把「上报不一致」当成重试理由无限重复提交——
// 每次提交都是一次跨进程图标更换，无界循环会持续烧 CPU 导致发热。

struct AppTheme {
    static let defaultID = "pink"
    let id: String
    static func selected(_ id: String) -> AppTheme { AppTheme(id: id) }
}

@MainActor
private final class IconSystem {
    var supports = true
    /// 模拟上报滞后：提交成功后 reportedName 保持不变。
    var laggingReporter = false
    var reportedName: String?
    /// 每次提交先挂起在门闩上，由测试决定放行时机与成败。
    var holdSubmissions = false
    /// 接下来 N 次提交抛错。
    var failNext = 0
    private(set) var submissions: [String?] = []
    private var gates: [CheckedContinuation<Void, any Error>] = []

    func endpoint() -> ThemeIconController.IconEndpoint {
        ThemeIconController.IconEndpoint(
            supportsAlternateIcons: { self.supports },
            reportedIconName: { self.reportedName },
            setAlternateIconName: { name in
                // 真实 UIKit 调用是跨进程请求，必然挂起；先让出执行器，
                // 否则缺陷代码的活锁会饿死守门犬，测试只能挂死而非报警。
                await Task.yield()
                self.submissions.append(name)
                if self.holdSubmissions {
                    try await withCheckedThrowingContinuation { self.gates.append($0) }
                }
                if self.failNext > 0 {
                    self.failNext -= 1
                    throw URLError(.cannotConnectToHost)
                }
                if !self.laggingReporter { self.reportedName = name }
            }
        )
    }

    func releaseAll(success: Bool) {
        let pending = gates
        gates.removeAll()
        for gate in pending {
            if success { gate.resume(returning: ()) } else { gate.resume(throwing: URLError(.cannotConnectToHost)) }
        }
    }
}

@main @MainActor
enum ThemeIconRegression {
    static func main() async {
        await alreadyMatchingIconMakesNoRequest()
        await laggingReporterFinishesAfterOneSubmission()
        await themeChangeMidFlightIsAppliedNext()
        await failureSurfacesErrorWithoutResubmitting()
        await failureThenNewThemeRetriesNewTarget()
        await unsupportedDevicesShowMessageWithoutRequesting()
        await defaultThemeRequestsPrimaryIconOnce()
        print("Theme icon regression passed: fast path, single submission under lagging reporter, mid-flight theme handoff, failure without retry storm, retry only for a newer theme, unsupported message, primary-icon reset")
    }

    /// 已一致的图标不再发起系统请求。
    private static func alreadyMatchingIconMakesNoRequest() async {
        let system = IconSystem()
        system.reportedName = "NeoBiliIcon-rose"
        let controller = ThemeIconController(endpoint: system.endpoint())
        await runWithWatchdog("already-matching fast path") { await controller.apply(themeID: "rose") }
        precondition(system.submissions.isEmpty, "A matching reported icon must not trigger a system request")
        precondition(controller.errorMessage == nil)
    }

    /// 上报滞后（成功后仍报旧名）时只允许提交一次并正常返回。
    /// 修复前的代码在这里无限重复提交——即发热根因。
    private static func laggingReporterFinishesAfterOneSubmission() async {
        let system = IconSystem()
        system.laggingReporter = true
        system.reportedName = "NeoBiliIcon-old"
        let controller = ThemeIconController(endpoint: system.endpoint())
        await runWithWatchdog("lagging-reporter apply") { await controller.apply(themeID: "rose") }
        precondition(system.submissions.count == 1 && system.submissions[0] == "NeoBiliIcon-rose",
                     "An accepted request must not be resubmitted when the reported name lags")
        precondition(controller.errorMessage == nil)
    }

    /// 等待中的提交完成后，中途切换的主题要获得自己的提交，然后结束。
    private static func themeChangeMidFlightIsAppliedNext() async {
        let system = IconSystem()
        system.holdSubmissions = true
        let controller = ThemeIconController(endpoint: system.endpoint())
        let first = Task { await controller.apply(themeID: "rose") }
        await waitUntil("first submission pending") { system.submissions.count == 1 }
        await controller.apply(themeID: "sky")
        precondition(system.submissions.count == 1, "A queued second apply must not submit while the first is in flight")
        system.releaseAll(success: true)
        await waitUntil("second submission pending") { system.submissions.count == 2 }
        system.releaseAll(success: true)
        await runWithWatchdog("mid-flight handoff") { await first.value }
        precondition(system.submissions == ["NeoBiliIcon-rose", "NeoBiliIcon-sky"])
        precondition(system.reportedName == "NeoBiliIcon-sky" && controller.errorMessage == nil)
    }

    /// 失败上报错误文案，不重试、不风暴。
    private static func failureSurfacesErrorWithoutResubmitting() async {
        let system = IconSystem()
        system.failNext = 100
        let controller = ThemeIconController(endpoint: system.endpoint())
        await runWithWatchdog("failure path") { await controller.apply(themeID: "rose") }
        precondition(system.submissions.count == 1, "A failed request must surface an error, not retry in a loop")
        precondition(controller.errorMessage != nil)
    }

    /// 失败发生时主题已再次切换：新主题获得一次自己的提交且成功结束。
    /// 失败完全由门闩的抛错放行注入（与 failNext 计数互斥，避免双重失败）。
    private static func failureThenNewThemeRetriesNewTarget() async {
        let system = IconSystem()
        system.holdSubmissions = true
        let controller = ThemeIconController(endpoint: system.endpoint())
        let first = Task { await controller.apply(themeID: "rose") }
        await waitUntil("first submission pending") { system.submissions.count == 1 }
        await controller.apply(themeID: "sky")
        system.releaseAll(success: false)
        await waitUntil("retry for new theme pending") { system.submissions.count == 2 }
        system.releaseAll(success: true)
        await runWithWatchdog("retry-after-failure") { await first.value }
        precondition(system.submissions == ["NeoBiliIcon-rose", "NeoBiliIcon-sky"])
        precondition(controller.errorMessage == nil)
    }

    private static func unsupportedDevicesShowMessageWithoutRequesting() async {
        let system = IconSystem()
        system.supports = false
        let controller = ThemeIconController(endpoint: system.endpoint())
        await runWithWatchdog("unsupported path") { await controller.apply(themeID: "rose") }
        precondition(system.submissions.isEmpty)
        precondition(controller.errorMessage != nil)
    }

    /// 回到默认主题 = 请求主图标（nil），仅一次。
    private static func defaultThemeRequestsPrimaryIconOnce() async {
        let system = IconSystem()
        system.reportedName = "NeoBiliIcon-rose"
        let controller = ThemeIconController(endpoint: system.endpoint())
        await runWithWatchdog("primary-icon reset") { await controller.apply(themeID: "pink") }
        precondition(system.submissions.count == 1 && system.submissions[0] == nil)
        precondition(system.reportedName == nil && controller.errorMessage == nil)
    }

    /// 守门犬：apply 必须在限时内返回。无限重提交循环（发热回归）会在此失败，
    /// 而不是让整个 harness 挂死。
    private static func runWithWatchdog(_ label: String, _ operation: @escaping @MainActor () async -> Void) async {
        let finished = Box()
        let task = Task { @MainActor in
            await operation()
            finished.value = true
        }
        for _ in 0..<4_000 {
            if finished.value { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        precondition(finished.value, "\(label) did not return — icon-change requests are being resubmitted without bound")
        _ = await task.value
    }

    private static func waitUntil(_ message: String, _ condition: @MainActor () -> Bool) async {
        for _ in 0..<4_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure(message)
    }
}

@MainActor
private final class Box {
    var value = false
}
