import SwiftUI

/// 独立搜索 Tab 的内容；使用原生 `.searchable` 承载搜索会话，
/// 页面按「发现（历史 + 热搜）/ 联想 / 结果」三态切换，避免与键盘焦点耦合。
struct SearchPage: View {
    private enum Phase {
        case discover
        case suggestions
        case results
    }

    let viewModel: SearchViewModel
    @Binding var isFocused: Bool
    @Environment(\.appThemeColor) private var themeColor
    let onSubmit: (String?) -> Void
    private var history: SearchHistory { viewModel.history }

    private var phase: Phase {
        if viewModel.isShowingSuggestions {
            return .suggestions
        }
        if viewModel.hasSubmittedSearch {
            return .results
        }
        return .discover
    }

    var body: some View {
        // Keep `.searchable` above a stable container so switching between
        // discover, suggestions and results preserves UISearchTextField identity and IME state.
        VStack(spacing: 0) {
            switch phase {
            case .discover:
                discoverList
            case .suggestions:
                suggestionsList
            case .results:
                SearchResultsView(viewModel: viewModel)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            let color: UIColor = phase == .results ? .systemGroupedBackground : .systemBackground
            Color(uiColor: color).ignoresSafeArea()
        }
        .searchable(
            text: Binding(get: { viewModel.query }, set: { viewModel.query = $0 }),
            isPresented: $isFocused,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: String(localized: "搜索视频")
        )
        .onSubmit(of: .search) { onSubmit(nil) }
        .onChange(of: isFocused) { wasFocused, nowFocused in
            // 用户点击搜索栏右侧取消按钮退出搜索会话时，干净回到发现页。
            if wasFocused, !nowFocused {
                if !viewModel.query.isEmpty { viewModel.query = "" }
                viewModel.reset()
            }
        }
        .task { await viewModel.loadHotSearches() }
        .rootPageChrome(title: String(localized: "搜索"))
        .onAppear { OrientationController.enterPortrait() }
    }

    // MARK: - 发现页（历史 + 热搜）

    private var discoverList: some View {
        List {
            historySection
            hotSearchSection
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 36)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private var historySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionTitle(String(localized: "搜索历史"))
                    Spacer()
                    Button("清空", systemImage: "trash") { history.clear() }
                        .font(.app(.subheadline))
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .disabled(history.keywords.isEmpty)
                        .accessibilityLabel("清空搜索历史")
                        .accessibilityIdentifier("search.clearHistory")
                }
                if history.keywords.isEmpty {
                    Text("暂无搜索历史")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    WrappingCapsuleLayout(spacing: 8) {
                        ForEach(history.keywords, id: \.self) { keyword in
                            Button { onSubmit(keyword) } label: {
                                Text(keyword)
                                    .font(.app(.subheadline))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                                    .frame(minHeight: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(keyword)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color(uiColor: .systemBackground))
            .listRowSeparator(.hidden)
        }
    }

    private var hotSearchSection: some View {
        Section {
            sectionTitle(String(localized: "热搜"))
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color(uiColor: .systemBackground))
                .listRowSeparator(.hidden)
                .accessibilityAddTraits(.isHeader)

            if viewModel.isLoadingHotSearches {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color(uiColor: .systemBackground))
                    .listRowSeparator(.hidden)
            } else if let error = viewModel.hotSearchError {
                InlineLoadFailure(title: "热搜加载失败", message: error) {
                    Task { await viewModel.loadHotSearches() }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color(uiColor: .systemBackground))
                .listRowSeparator(.hidden)
            } else if viewModel.hotSearches.isEmpty {
                Text("暂无热搜")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color(uiColor: .systemBackground))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(viewModel.hotSearches.enumerated()), id: \.element.id) { index, item in
                    Button { onSubmit(item.keyword) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: HotSearchRowMetrics.rankSpacing) {
                            Text(String(index + 1))
                                .font(.app(.subheadline, weight: index < 3 ? .bold : .medium))
                                .monospacedDigit()
                                .lineLimit(1)
                                .foregroundStyle(index < 3 ? themeColor : Color.secondary)
                                .frame(width: HotSearchRowMetrics.rankWidth, alignment: .trailing)
                            Text(item.title)
                                .font(.app(.subheadline))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    .listRowBackground(Color(uiColor: .systemBackground))
                    .listRowSeparator(index == 0 ? .hidden : .visible, edges: .top)
                    .listRowSeparator(index == viewModel.hotSearches.count - 1 ? .hidden : .visible, edges: .bottom)
                    .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                        dimensions[.leading] + HotSearchRowMetrics.separatorLeading
                    }
                    .accessibilityLabel(String(localized: "第\(index + 1)名，\(item.title)"))
                }
            }
        }
    }

    // MARK: - 联想列表

    private var suggestionsList: some View {
        List {
            if viewModel.suggestions.isEmpty {
                suggestionRow(
                    String(localized: "搜索：\(viewModel.trimmedQuery)"),
                    keyword: viewModel.trimmedQuery,
                    isFirst: true,
                    isLast: true
                )
            } else {
                ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    suggestionRow(
                        suggestion.value,
                        keyword: suggestion.value,
                        isFirst: index == 0,
                        isLast: index == viewModel.suggestions.count - 1
                    )
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 40)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private func suggestionRow(_ title: String, keyword: String, isFirst: Bool, isLast: Bool) -> some View {
        Button { onSubmit(keyword) } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                Text(title)
                    .font(.app(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color(uiColor: .systemBackground))
        .listRowSeparator(isFirst ? .hidden : .visible, edges: .top)
        .listRowSeparator(isLast ? .hidden : .visible, edges: .bottom)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + 28
        }
        .accessibilityLabel(title)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.app(.headline))
            .foregroundStyle(.primary)
    }
}

private enum HotSearchRowMetrics {
    static let rankWidth: CGFloat = 24
    static let rankSpacing: CGFloat = 10
    static let separatorLeading: CGFloat = rankWidth + rankSpacing
}
