#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 稿件标签，横向一排浅灰填充的圆角标签（内容里的按钮不用玻璃）。圆角与操作按钮、合集、分P 入口在视觉上一致。
///
/// 标签数量不定，长标签也常见，所以整行可以横向滚动而不是折行——折行会让
/// 简介区高度随视频不同上下跳。左右留白用 `.contentMargins` 而不是给内容加
/// padding，这样滚到两端时标签不会被容器边缘切掉。
struct VideoTagsRow: View {
    let tags: [VideoTag]
    /// 和正文一致的左右留白。
    let horizontalInset: CGFloat
    let onSelect: (VideoTag) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(tags) { tag in
                    Button { onSelect(tag) } label: {
                        Text(tag.tagName)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 26)
                            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索标签：\(tag.tagName)")
                }
            }
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
