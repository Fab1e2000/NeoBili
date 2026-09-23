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

/// 视频页挂载发弹幕面板用的修饰符，单独拆出来以减轻视频页主体的类型推断负担。
struct DanmakuComposerPresentation: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var draft: String
    @Binding var mode: DanmakuMode
    let send: (String, DanmakuMode) async throws -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            VideoDanmakuComposer(draft: $draft, mode: $mode, send: send)
                .appTextSize()
        }
    }
}
