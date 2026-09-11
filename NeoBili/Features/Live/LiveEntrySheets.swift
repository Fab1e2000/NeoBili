import SwiftUI

struct LiveRoomEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var input = ""
    @State private var showsValidation = false
    let onOpenRoom: (LiveRoom) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("房间号或直播链接", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($isFocused)
                        .onSubmit(openRoom)
                        .accessibilityIdentifier("live.roomInput")
                } footer: {
                    Text("输入房间号，或粘贴 live.bilibili.com 的直播间链接。")
                }

                if showsValidation {
                    Text("请输入有效的房间号或哔哩哔哩直播间链接。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button("进入直播间", systemImage: "play.rectangle") { openRoom() }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("live.openEnteredRoom")
            }
            .navigationTitle("打开直播间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onChange(of: input) { showsValidation = false }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func openRoom() {
        guard let id = LiveRoomLinkParser.roomID(from: input) else {
            showsValidation = true
            return
        }
        onOpenRoom(LiveRoom(roomID: id, title: "直播间 \(id)", username: ""))
        dismiss()
    }
}
