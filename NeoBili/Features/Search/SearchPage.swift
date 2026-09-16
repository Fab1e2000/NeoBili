import SwiftUI

/// 独立搜索 Tab 的内容；输入框只挂在本 Tab 的导航栈上。
struct SearchPage: View {
    let viewModel: SearchViewModel
    let onSubmit: (String?) -> Void
    @State private var history = SearchHistory.shared

    var body: some View {
        Group {
            if viewModel.isShowingSuggestions {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if viewModel.suggestions.isEmpty {
                            searchRow("搜索：\(viewModel.trimmedQuery)", keyword: viewModel.trimmedQuery)
                        } else {
                            ForEach(viewModel.suggestions) { suggestion in
                                searchRow(suggestion.value, keyword: suggestion.value)
                                Divider().padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            } else if viewModel.hasSubmittedSearch {
                SearchResultsView(viewModel: viewModel)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("搜索历史").font(.headline)
                            Spacer()
                            Button("清空", systemImage: "trash") { history.clear() }
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 44)
                                .disabled(history.keywords.isEmpty)
                                .accessibilityLabel("清空搜索历史")
                                .accessibilityIdentifier("search.clearHistory")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        if history.keywords.isEmpty {
                            Text("暂无搜索历史")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                        }
                        ForEach(history.keywords, id: \.self) { keyword in
                            searchRow(keyword, keyword: keyword, symbol: "clock.arrow.circlepath")
                            Divider().padding(.horizontal, 20)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 仅背景越过键盘安全区；列表仍正常避让键盘和搜索栏。
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { OrientationController.enterPortrait() }
    }

    private func searchRow(_ title: String, keyword: String, symbol: String? = nil) -> some View {
        Button { onSubmit(keyword) } label: {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
                Text(title).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
