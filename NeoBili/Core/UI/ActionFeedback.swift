import SwiftUI

/// 全局的一句话操作反馈。
///
/// 「加入稍后再看」「已取消收藏」这类提示到处都要用，如果每个页面各自养一个
/// `@State` + `.alert`，同一段样板会在五六处重复。这里统一放在根视图上弹一次，
/// 各处只管往里写文案。
@MainActor
@Observable
final class ActionFeedback {
    /// 有值时根视图会弹出提示；用户点掉后自动置回 nil。
    var message: String?

    func show(_ text: String) {
        message = text
    }

    /// 写操作的统一出口：成功报一句，失败把接口原话透出来。
    func report(_ error: Error?, successText: String) {
        message = error.map { $0.localizedDescription } ?? successText
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
                        Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.black.opacity(0.82), in: Capsule())
                        .padding(.horizontal, 32)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        // 看完就自己走，不用用户去点掉。
                        .task(id: message) {
                            try? await Task.sleep(for: .seconds(2))
                            feedback.message = nil
                        }
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
                feedback.show("请先登录")
                return
            }
            Task {
                do {
                    try await BiliAPI.addWatchLater(aid: aid, bvid: bvid)
                    feedback.show("已加入稍后再看")
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
