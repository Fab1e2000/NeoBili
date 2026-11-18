#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 根页面和媒体详情共用的一句话操作反馈。
@MainActor
@Observable
final class ActionFeedback {
    private(set) var message: String?
    private(set) var canUndo = false
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var pending: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var token = UUID()

    func show(_ text: String) {
        finish(commit: true)
        message = text
        announce(text)
        scheduleExpiry(after: .seconds(2))
    }

    /// true 才提交网络请求；撤销或任务取消时由调用方恢复原条目。
    func confirmRemoval(_ text: String, duration: Duration = .seconds(5)) async -> Bool {
        guard !Task.isCancelled else { return false }
        finish(commit: true)
        let request = UUID()
        token = request
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = continuation
                message = text
                canUndo = true
                announce(text)
                scheduleExpiry(after: duration, token: request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.token == request else { return }
                self.finish(commit: false)
            }
        }
    }

    func undo() { finish(commit: false) }

    /// 浮层不抢 VoiceOver 焦点，提示内容单独播报一次。浮层挂在两处，播报放在这里才不会念两遍。
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    private func scheduleExpiry(after duration: Duration, token request: UUID? = nil) {
        let request = request ?? UUID()
        token = request
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.token == request else { return }
            self.finish(commit: true)
        }
    }

    private func finish(commit: Bool) {
        expiry?.cancel()
        expiry = nil
        token = UUID()
        message = nil
        canUndo = false
        let continuation = pending
        pending = nil
        continuation?.resume(returning: commit)
    }
}

/// 非模态反馈浮层，避免打断媒体详情的 fullScreenCover 和列表动画。
struct ActionFeedbackOverlay: ViewModifier {
    @Environment(ActionFeedback.self) private var feedback

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // 动画写在浮层这一层里，而不是挂在 content 外面。挂在外面时
                // 每次提示进出都会给整棵被包住的视图树开一次动画事务，影响范围
                // 远超一个提示条该有的样子。
                ZStack {
                    if let message = feedback.message {
                        HStack(spacing: 16) {
                            Text(message)
                            if feedback.canUndo {
                                Button("撤销") { feedback.undo() }
                                    .fontWeight(.semibold)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("feedback.undo")
                            }
                        }
                        .font(.app(.subheadline))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        // 系统玻璃随浅色／深色外观和下方内容自动调整，深色模式下也能和背景分开。
                        .glassEffect(.regular, in: Capsule())
                        .padding(.horizontal, 32)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                    }
                }
                .animation(.spring(duration: 0.3), value: feedback.message)
            }
    }
}

extension View {
    /// 挂上一句话反馈的浮层。
    ///
    /// 需要挂**两处**：根视图，以及视频页——视频页是 `fullScreenCover`，
    /// 盖在根视图上面，根视图那层浮层在它下面看不见。
    func actionFeedbackOverlay() -> some View {
        modifier(ActionFeedbackOverlay())
    }
}

/// 视频卡片菜单共用的「稍后再看」操作，集中处理登录检查和结果提示。
struct WatchLaterMenuButton: View {
    @Environment(\.applicationServices) private var services
    /// 稿件 avid。搜索结果没有 avid，只能靠 bvid。两者给一个即可。
    var aid: Int?
    var bvid: String?

    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback

    var body: some View {
        Button {
            WatchLaterAction.add(aid: aid, bvid: bvid, services: services, account: account, feedback: feedback)
        } label: {
            Label("稍后再看", systemImage: "flag")
        }
        .disabled(aid == nil && bvid == nil)
    }
}

@MainActor
enum WatchLaterAction {
    static func add(aid: Int?, bvid: String?, services: ApplicationServices, account: AccountStore, feedback: ActionFeedback) {
        guard aid != nil || bvid != nil else { return }
        guard account.isLoggedIn else {
            feedback.show(String(localized: "请先登录"))
            return
        }
        Task {
            do {
                try await services.library.addWatchLater(aid: aid, bvid: bvid)
                feedback.show(String(localized: "已加入稍后再看"))
            } catch {
                feedback.show(error.localizedDescription)
            }
        }
    }
}

extension Error {
    /// 统一识别 Swift 任务取消与 URLSession 取消，调用方据此跳过错误提示。
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        return nsError.domain == "NSPOSIXErrorDomain" && nsError.code == 89
    }
}

#Preview("操作提示") {
    @Previewable @State var feedback = ActionFeedback()
    VStack(spacing: 16) {
        Button("显示提示") { feedback.show("已加入稍后再看") }
        Button("显示可撤销的提示") { Task { _ = await feedback.confirmRemoval("已移除") } }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
    .actionFeedbackOverlay()
    .environment(feedback)
}
