import SwiftUI
import UIKit

@MainActor
@Observable
final class CommentDraft {
    var text = ""
    var target: CommentReplyTarget?
}

struct CommentReplyTarget {
    let root: Int
    let parent: Int
    let name: String
}

extension EnvironmentValues {
    @Entry var commentBottomInset: CGFloat = 0
    @Entry var replyToComment: ((Comment) -> Void)? = nil
}

extension View {
    func commentComposer(viewModel: CommentsViewModel, root: Comment? = nil) -> some View {
        modifier(CommentComposerHost(viewModel: viewModel, root: root))
    }
}

private struct CommentComposerHost: ViewModifier {
    let viewModel: CommentsViewModel
    let root: Comment?
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.commentBottomInset) private var bottomInset
    @State private var barHeight: CGFloat = 64
    private var savedDraft: CommentDraft { viewModel.commentDraft(root: root?.rpid ?? 0) }
    @State private var sending = false
    @State private var sendError: String?
    @FocusState private var focused: Bool

    // 键盘收起时适当进入底部安全区；编辑时恢复避让，不侵入键盘。
    private var inputBottomInset: CGFloat {
        focused ? bottomInset : max(0, bottomInset - 10)
    }

    private var destination: CommentReplyTarget? {
        savedDraft.target ?? root.map { CommentReplyTarget(root: $0.rpid, parent: $0.rpid, name: $0.member.uname) }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.replyToComment) { comment in
                guard !sending else { return }
                savedDraft.target = CommentReplyTarget(root: root?.rpid ?? comment.rpid,
                                            parent: comment.rpid, name: comment.member.uname)
                focused = true
            }
            .contentMargins(.bottom, barHeight + inputBottomInset, for: .scrollContent)
            .overlay(alignment: .bottom) {
                inputBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                    .padding(.bottom, inputBottomInset)
            }
            .onChange(of: account.sessionID) {
                viewModel.clearCommentDrafts()
                sendError = nil
                focused = false
            }
    }

    private var inputBar: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    if let destination {
                        HStack {
                            Text("回复 @\(destination.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if savedDraft.target != nil {
                                Button("取消") { savedDraft.target = nil }
                                    .font(.caption)
                                    .disabled(sending)
                            }
                        }
                    }
                    if let sendError {
                        Text(sendError).font(.caption).foregroundStyle(.red)
                    }
                    TextField(account.isLoggedIn ? "写下你的评论…" : "登录后发表评论",
                              text: Binding(get: { savedDraft.text }, set: { savedDraft.text = $0 }), axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .disabled(sending)
                        .accessibilityLabel(destination == nil ? "评论内容" : "回复内容")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Button(action: send) {
                    Group {
                        if sending { ProgressView() } else { Image(systemName: "arrow.up").font(.headline) }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(CommentSendButtonStyle())
                .disabled(sending || savedDraft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送评论")
            }
        }
        .background {
            CommentOutsideTapObserver(enabled: focused) { focused = false }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func send() {
        guard account.isLoggedIn else { sendError = "请先登录"; return }
        let message = savedDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sending, !message.isEmpty else { return }
        guard message.count <= 1000 else { sendError = "评论不能超过1000字"; return }
        let reply = destination
        let session = account.sessionID
        sending = true
        sendError = nil
        Task { @MainActor in
            defer { sending = false }
            do {
                let result = try await BiliAPI.sendComment(oid: viewModel.oid, type: viewModel.type,
                    message: message, root: reply?.root ?? 0, parent: reply?.parent ?? 0)
                guard session == account.sessionID else { return }
                viewModel.acceptSubmission(result.reply, root: reply?.root)
                savedDraft.text = ""
                savedDraft.target = nil
                focused = false
                feedback.show(result.successToast ?? "发送成功")
            } catch {
                guard session == account.sessionID else { return }
                sendError = error.localizedDescription
            }
        }
    }
}

/// 编辑时接住输入栏外的首次点击，避免收起键盘的同时触发底层按钮。
private struct CommentOutsideTapObserver: UIViewRepresentable {
    let enabled: Bool
    let onOutside: () -> Void
    func makeUIView(context: Context) -> Observer { Observer() }
    func updateUIView(_ view: Observer, context: Context) {
        view.onOutside = onOutside
        view.setEnabled(enabled)
    }
    static func dismantleUIView(_ view: Observer, coordinator: ()) { view.detach() }

    final class Observer: UIView {
        var onOutside: (() -> Void)?
        private var editing = false
        private lazy var shield: DismissShield = {
            let control = DismissShield()
            control.owner = self
            control.backgroundColor = .clear
            control.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            control.addTarget(self, action: #selector(dismissInput), for: .touchUpInside)
            control.isAccessibilityElement = true
            control.accessibilityLabel = "收起评论输入"
            control.accessibilityTraits = .button
            return control
        }()

        func setEnabled(_ enabled: Bool) {
            editing = enabled
            updateShield()
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateShield()
        }
        private func updateShield() {
            guard editing, let window else { detach(); return }
            if shield.superview !== window {
                shield.removeFromSuperview()
                shield.frame = window.bounds
                window.addSubview(shield)
            }
        }
        func detach() { shield.removeFromSuperview() }
        @objc private func dismissInput() { onOutside?() }
    }

    private final class DismissShield: UIControl {
        weak var owner: Observer?
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard let owner, owner.window != nil else { return false }
            let inputFrame = owner.convert(owner.bounds, to: self)
            // 输入框、发送按钮以及其下方的系统键盘仍正常接收触摸。
            guard !inputFrame.contains(point), point.y < inputFrame.maxY else { return false }
            return super.point(inside: point, with: event)
        }
        override func accessibilityActivate() -> Bool {
            sendActions(for: .touchUpInside)
            return true
        }
    }
}

/// 与单行输入框共用 48pt 外径，不叠加系统 controlSize 的额外内边距。
private struct CommentSendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 48, height: 48)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .glassEffect(.regular.tint(isEnabled ? Color.accentColor : Color.clear).interactive(), in: Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
