#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 所有关注的 UP 主，每行五个头像、下方名字；轻点进入个人主页。
struct FollowingAllUpsView: View {
    /// 头像条已知的直播与未读状态，用来给同一位 UP 主补上 LIVE 与红点。
    let decorated: [Int: FollowedUp]
    let onOpenUp: (FollowedUp) -> Void

    @State private var model: FollowingAllUpsModel

    init(mid: Int, decorated: [Int: FollowedUp], onOpenUp: @escaping (FollowedUp) -> Void) {
        self.decorated = decorated
        self.onOpenUp = onOpenUp
        _model = State(initialValue: FollowingAllUpsModel(mid: mid))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 5)

    var body: some View {
        ScrollView {
            if model.ups.isEmpty {
                initialState
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.ups) { up in
                        cell(decorated[up.mid] ?? up)
                            .task { await model.loadMoreIfNeeded(current: up) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
                footer
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("全部关注")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .task { await model.loadInitial() }
    }

    private func cell(_ up: FollowedUp) -> some View {
        Button { onOpenUp(up) } label: {
            VStack(spacing: 6) {
                FollowingUpAvatar(item: .up(up), size: 52)
                Text(up.uname)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(up.uname + (up.liveRoomID != nil ? String(localized: "，正在直播") : ""))
        .accessibilityHint("打开 UP 主主页")
    }

    @ViewBuilder
    private var initialState: some View {
        if let message = model.errorMessage {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await model.loadMore() } }
            }
        } else if model.isLoading || model.hasMore {
            LoadingTaskAnchor()
        } else {
            ContentUnavailableView("还没有关注任何 UP 主", systemImage: "person.2")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoading {
            LoadingTaskAnchor().padding(.bottom, 16)
        } else if let message = model.errorMessage {
            VStack(spacing: 6) {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("重试") { Task { await model.loadMore() } }.frame(minHeight: 44)
            }
            .padding(.bottom, 16)
        }
    }
}
