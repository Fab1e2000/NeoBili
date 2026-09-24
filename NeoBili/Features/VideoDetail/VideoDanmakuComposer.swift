import SwiftUI

/// 发弹幕的输入面板（参考 PiliPlus 的 SendDanmakuPanel）：一行输入框、发送按钮和弹幕位置。
///
/// 打开时视频暂停、关闭后恢复由调用方负责；草稿和位置由调用方持有，
/// 没发出去就关掉面板时下次打开还在。
struct VideoDanmakuComposer: View {
    /// 接口限制：弹幕文本少于 100 个字符。
    static let maxLength = 100

    @Binding var draft: String
    @Binding var mode: DanmakuMode
    /// 发送并在成功后把弹幕加到画面上；失败时抛出错误，面板显示原因。
    let send: (String, DanmakuMode) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var isSending = false
    @State private var errorMessage: String?

    private var message: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("发个友善的弹幕见证当下", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .focused($isFocused)
                        .disabled(isSending)
                        .onSubmit(submit)
                        .onChange(of: draft) { _, text in
                            if text.count > Self.maxLength { draft = String(text.prefix(Self.maxLength)) }
                            errorMessage = nil
                        }
                    Button(action: submit) {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(message.isEmpty || isSending)
                    .accessibilityLabel("发送弹幕")
                }

                Picker("弹幕位置", selection: $mode) {
                    ForEach(DanmakuMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("发弹幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.height(210)])
        .presentationDragIndicator(.visible)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let text = message
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await send(text, mode)
                draft = ""
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 全屏（横屏）时的发弹幕输入：键盘上方一条玻璃输入栏。
///
/// 横屏全屏时弹出系统卡片会遮住大半画面，所以改为浮在视频上的一层；点输入栏以外的地方关闭。
struct FullscreenDanmakuInput: View {
    @Binding var draft: String
    @Binding var mode: DanmakuMode
    let send: (String, DanmakuMode) async throws -> Void
    let onClose: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isSending = false
    @State private var errorMessage: String?

    private var message: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            // 压暗画面，输入时不受画面和正在飘的弹幕干扰。
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("关闭发弹幕")

            VStack(spacing: 12) {
                Spacer(minLength: 0)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.8), in: Capsule())
                }
                inputBar
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { isFocused = true }
        .onChange(of: draft) { _, text in
            if text.count > VideoDanmakuComposer.maxLength {
                draft = String(text.prefix(VideoDanmakuComposer.maxLength))
            }
            errorMessage = nil
        }
    }

    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Picker("弹幕位置", selection: $mode) {
                        ForEach(DanmakuMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .accessibilityLabel("弹幕位置：\(mode.title)")

                TextField("发个友善的弹幕见证当下", text: $draft)
                    .foregroundStyle(.white)
                    .submitLabel(.send)
                    .focused($isFocused)
                    .disabled(isSending)
                    .onSubmit(submit)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .glassEffect(.regular, in: Capsule())

                Button(action: submit) {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(message.isEmpty || isSending)
                .opacity(message.isEmpty ? 0.5 : 1)
                .accessibilityLabel("发送弹幕")
            }
        }
    }

    private func submit() {
        let text = message
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await send(text, mode)
                draft = ""
                onClose()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 视频页挂载发弹幕输入的修饰符：竖屏用系统卡片，全屏用浮在画面上的输入栏。
/// 单独拆出来以减轻视频页主体的类型推断负担。
struct DanmakuComposerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var isFullScreenInputPresented: Bool
    let isFullScreen: Bool
    @Binding var draft: String
    @Binding var mode: DanmakuMode
    let send: (String, DanmakuMode) async throws -> Void
    /// 输入关闭（发送成功或放弃）后调用，用于恢复播放。
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                VideoDanmakuComposer(draft: $draft, mode: $mode, send: send)
                    .appTextSize()
            }
            .overlay {
                if isFullScreenInputPresented {
                    FullscreenDanmakuInput(draft: $draft, mode: $mode, send: send,
                                           onClose: { isFullScreenInputPresented = false })
                }
            }
            .onChange(of: isFullScreenInputPresented) { _, presented in
                if !presented { onDismiss() }
            }
            // 退出全屏时收起全屏输入栏。
            .onChange(of: isFullScreen) { _, fullScreen in
                if !fullScreen { isFullScreenInputPresented = false }
            }
    }
}
