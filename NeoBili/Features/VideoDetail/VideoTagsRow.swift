import SwiftUI

/// 稿件标签，横向一排胶囊。
///
/// 标签数量不定，长标签也常见，所以整行可以横向滚动而不是折行——折行会让
/// 简介区高度随视频不同上下跳。左右留白用 `.contentMargins` 而不是给内容加
/// padding，这样滚到两端时胶囊不会被容器边缘切掉。
struct VideoTagsRow: View {
    let tags: [VideoTag]
    /// 和正文一致的左右留白。
    let horizontalInset: CGFloat
    let onSelect: (VideoTag) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            // 相邻玻璃按钮统一合成，上下预留按压形变和光晕的空间。
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        Button { onSelect(tag) } label: {
                            Text(tag.tagName)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .contentShape(Capsule())
                        .controlSize(.small)
                        .tint(.primary)
                        .accessibilityLabel("搜索标签：\(tag.tagName)")
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
    }
}

struct VideoTagSearchRoute: Hashable {
    let keyword: String
}

struct VideoTagSearchPage: View {
    let keyword: String
    @State private var search = SearchViewModel()
    @State private var initialKeyword: String?

    var body: some View {
        Group {
            if search.hasSubmittedSearch {
                SearchResultsView(viewModel: search)
            } else {
                ContentUnavailableView("搜索视频", systemImage: "magnifyingglass",
                                       description: Text("输入关键词开始搜索"))
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .searchable(text: $search.query, placement: .toolbarPrincipal, prompt: "搜索视频")
        .searchSuggestions {
            if search.isShowingSuggestions {
                ForEach(search.suggestions) { suggestion in
                    Text(suggestion.value)
                        .foregroundStyle(.primary)
                        .searchCompletion(suggestion.value)
                }
            }
        }
        .onSubmit(of: .search) { search.submit() }
        .task(id: search.trimmedQuery) { await search.loadSuggestions() }
        .onChange(of: search.trimmedQuery) {
            if search.trimmedQuery.isEmpty { search.reset() }
        }
        .task(id: keyword) {
            guard initialKeyword != keyword else { return }
            initialKeyword = keyword
            search.submit(keyword: keyword)
        }
    }
}
