import SwiftUI

/// 全局的一句话操作反馈。
///
/// 「加入稍后再看」「已取消收藏」这类提示到处都要用，如果每个页面各自养一个
/// `@State` + `.alert`，同一段样板会在五六处重复。这里统一放在根视图上弹一次，
/// 各处只管往里写文案。
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

/// 把一句话反馈画成浮层。
///
/// 这里**不能**用 `.alert`。视频页是根视图用 `fullScreenCover` 弹出来的，而在
/// 根视图上再présenter一个 alert 时，SwiftUI 会先把已有的 cover 关掉——表现就是
/// 长按卡片加稍后再看之后整个视频页被弹走、提示也没看见，播放器在半途被拆掉，
/// 再进去就只剩声音没有画面。alert 同样会打断列表删除时正在跑的动画。
///
/// 浮层是非模态的，不参与「谁该被 present」的争夺，上面两个问题都不会发生。
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
                        .font(.subheadline)
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

/// 放进视频卡片 `contextMenu` 里的「稍后再看」。
///
/// 首页、搜索、相关视频、收藏、历史五处都要这一项，做成独立视图后各处只写
/// 一行；登录检查和提示文案也就只有一份。
struct WatchLaterMenuButton: View {
    /// 稿件 avid。搜索结果没有 avid，只能靠 bvid。两者给一个即可。
    var aid: Int?
    var bvid: String?

    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback

    var body: some View {
        Button {
            guard account.isLoggedIn else {
                feedback.show(String(localized: "请先登录"))
                return
            }
            Task {
                do {
                    try await BiliAPI.addWatchLater(aid: aid, bvid: bvid)
                    feedback.show(String(localized: "已加入稍后再看"))
                } catch {
                    feedback.show(error.localizedDescription)
                }
            }
        } label: {
            Label("稍后再看", systemImage: "flag")
        }
        .disabled(aid == nil && bvid == nil)
    }
}

extension Error {
    /// 这次失败是不是「请求被取消」。
    ///
    /// 下拉刷新的闭包跑在 SwiftUI 自己的任务里，列表内容变化时这个任务会被取消，
    /// URLSession 随之抛出取消错误。它不是真的失败，却会被写进错误状态，于是
    /// 页面弹出「加载失败」——而用户点一下「重试」（一个不受牵连的新任务）就成功了。
    /// 凡是要落进错误提示的地方，先用它把这种情况滤掉。
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
