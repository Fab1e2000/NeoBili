import SwiftUI

struct DynamicVoteCard: View {
    let vote: DynamicVote
    let dynamicID: String
    @State private var selectedVote: DynamicVote?

    var body: some View {
        Button { selectedVote = vote } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(vote.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text("\(vote.participantCount.biliCountText) 人参与 · 查看投票")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .sheet(item: $selectedVote) { vote in
            DynamicVoteSheet(vote: vote, dynamicID: dynamicID)
        }
    }
}

private struct DynamicVoteSheet: View {
    let vote: DynamicVote
    let dynamicID: String
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var response: DynamicVoteResponse?
    @State private var selection: Set<Int> = []
    @State private var message: String?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(response?.voteInfo.title ?? vote.title).font(.headline)
                    if let response {
                        let info = response.voteInfo
                        let locked = info.hasEnded || !response.myVotes.isEmpty || submitted
                        Text("\(info.participantCount.biliCountText) 人参与 · \(info.hasEnded ? "已结束" : locked ? "已投票" : "最多选择 \(info.choiceCount) 项")")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(info.options) { option in
                            Button {
                                if selection.contains(option.id) { selection.remove(option.id) }
                                else if info.choiceCount == 1 { selection = [option.id] }
                                else if selection.count < info.choiceCount { selection.insert(option.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    if !option.imageURL.isEmpty {
                                        CoverThumbnail(url: URL.biliSecure(option.imageURL), aspectRatio: 1)
                                            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    Text(option.text).frame(maxWidth: .infinity, alignment: .leading)
                                    if locked { Text("\(option.count.biliCountText) 票").font(.caption).foregroundStyle(.secondary) }
                                    Image(systemName: selection.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selection.contains(option.id) ? Color.accentColor : Color.secondary)
                                }
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(locked || isSubmitting)
                        }
                        if !locked {
                            Button(isSubmitting ? "正在投票…" : "投票") { Task { await submit() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(selection.isEmpty || isSubmitting)
                        }
                    }
                    if isLoading { LoadingTaskAnchor() }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        if response == nil {
                            Button("重试") { Task { await load() } }.disabled(isLoading)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("投票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await BiliAPI.dynamicVoteInfo(id: vote.id)
            response = result
            if !submitted { selection = Set(result.myVotes) }
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func submit() async {
        guard account.isLoggedIn, let mid = account.profile?.mid else { message = "请先登录"; return }
        guard !isSubmitting, !selection.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await BiliAPI.submitDynamicVote(id: vote.id, options: selection.sorted(), voterMID: mid, dynamicID: dynamicID)
            submitted = true
            await load()
        } catch { message = error.localizedDescription }
    }
}
