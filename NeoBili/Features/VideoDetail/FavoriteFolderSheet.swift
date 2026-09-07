import SwiftUI

/// 收藏夹选择弹窗。
///
/// 一个视频可以同时收在多个收藏夹里，所以这里是多选而不是单选；打开时已经
/// 收进去的那几个默认打勾（靠 `list-all` 带回来的 `fav_state`），确认时只提交
/// 勾选状态发生变化的部分。
struct FavoriteFolderSheet: View {
    /// 当前账号的 mid，用来查自己的收藏夹。
    let ownerMid: Int
    /// 要收藏的稿件 avid。
    let videoAid: Int
    /// 确认时回调：分别是要加入和要移出的收藏夹 id。
    let onConfirm: ([Int], [Int]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var folders: [FavFolder] = []
    /// 打开弹窗那一刻已经收藏的收藏夹，用来算出最终的增删差集。
    @State private var originalSelection: Set<Int> = []
    @State private var selection: Set<Int> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingTaskAnchor().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if folders.isEmpty {
                    ContentUnavailableView(
                        "没有收藏夹",
                        systemImage: "star",
                        description: Text("请先在哔哩哔哩 App 里创建一个收藏夹")
                    )
                } else {
                    folderList
                }
            }
            // 左缘触控死区：防止边缘误触误选收藏夹。
            .leftEdgeTapDeadZone()
            .navigationTitle("收藏到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onConfirm(
                            Array(selection.subtracting(originalSelection)),
                            Array(originalSelection.subtracting(selection))
                        )
                        dismiss()
                    }
                    .disabled(isLoading || selection == originalSelection)
                }
            }
            .task { await loadFolders() }
        }
        .presentationDetents([.medium, .large])
    }

    private var folderList: some View {
        List(folders) { folder in
            Button {
                if selection.contains(folder.id) {
                    selection.remove(folder.id)
                } else {
                    selection.insert(folder.id)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.title)
                            .foregroundStyle(.primary)
                        Text("\(folder.mediaCount) 个内容")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selection.contains(folder.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func loadFolders() async {
        isLoading = true
        do {
            let loaded = try await BiliAPI.favoriteFolders(ownerMid: ownerMid, videoAid: videoAid)
            folders = loaded
            let existing = Set(loaded.filter(\.containsQueriedVideo).map(\.id))
            originalSelection = existing
            selection = existing
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
