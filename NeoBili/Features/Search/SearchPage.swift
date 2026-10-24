import SwiftUI

/// 独立搜索 Tab 的内容；输入框只挂在本 Tab 的导航栈上。
struct SearchPage: View {
    let viewModel: SearchViewModel
    @Binding var isFocused: Bool
    @Environment(\.appThemeColor) private var themeColor
    let onSubmit: (String?) -> Void
    private var history: SearchHistory { viewModel.history }

    /// 只在搜索首页（历史/热搜）显示标题；输入、联想和结果页让搜索框顶到最上方。
    private var showsHeader: Bool {
        !isFocused && !viewModel.hasSubmittedSearch
    }

    var body: some View {
        // Keep the search bar and its lifecycle above a stable container.
        // Group distributes modifiers onto the changing content branch, which
        // can recreate the input and invoke onDisappear on the first character.
        VStack(spacing: 0) {
            if isFocused && viewModel.trimmedQuery.isEmpty {
                Color.clear
            } else if isFocused {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if viewModel.suggestions.isEmpty {
                            searchRow(String(localized: "搜索：\(viewModel.trimmedQuery)"), keyword: viewModel.trimmedQuery)
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
                    VStack(alignment: .leading, spacing: 12) {
                        historySection
                        hotSearchSection
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 仅背景越过键盘安全区；列表仍正常避让键盘和搜索栏。
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            HomeSearchBar(text: Binding(get: { viewModel.query }, set: { viewModel.query = $0 }),
                          isFocused: $isFocused,
                          onSubmit: { onSubmit(nil) },
                          onCancel: { isFocused = false })
                .frame(height: 56)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
        }
        .scrollEdgeEffectStyle(.hard, for: .top)
        .task { await viewModel.loadHotSearches() }
        .onDisappear { isFocused = false }
        // 输入、联想和结果页隐藏导航栏，让搜索框顶到最上方。
        .rootPageChrome(title: String(localized: "搜索"))
        .toolbarVisibility(showsHeader ? .visible : .hidden, for: .navigationBar)
        .onAppear { OrientationController.enterPortrait() }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle(String(localized: "搜索历史"))
                Spacer()
                Button("清空", systemImage: "trash") { history.clear() }
                    .font(.app(.caption))
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 36)
                    .disabled(history.keywords.isEmpty)
                    .accessibilityLabel("清空搜索历史")
                    .accessibilityIdentifier("search.clearHistory")
            }
            if history.keywords.isEmpty {
                Text("暂无搜索历史").font(.app(.caption)).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                WrappingCapsuleLayout(spacing: 8) {
                    ForEach(history.keywords, id: \.self) { keyword in
                        Button { onSubmit(keyword) } label: {
                            Text(keyword)
                                .font(.app(.caption))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(keyword)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.app(.subheadline, weight: .semibold))
            .frame(height: 36, alignment: .leading)
    }

    private var hotSearchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(String(localized: "热搜"))
            if viewModel.isLoadingHotSearches {
                ProgressView().frame(maxWidth: .infinity).padding(8)
            } else if let error = viewModel.hotSearchError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.app(.caption)).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await viewModel.loadHotSearches() } }
                        .font(.app(.caption))
                }.padding(.vertical, 8)
            } else if viewModel.hotSearches.isEmpty {
                Text("暂无热搜").font(.app(.caption)).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            // 一行一条，字号与推荐页卡片标题一致。
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.hotSearches.enumerated()), id: \.element.id) { index, item in
                    Button { onSubmit(item.keyword) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(index + 1)).font(.app(.subheadline, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(index < 3 ? themeColor : Color.secondary)
                                .frame(minWidth: 22, alignment: .leading)
                            Text(item.title).font(.app(.subheadline)).foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(String(localized: "第\(index + 1)名，\(item.title)"))
                    if index < viewModel.hotSearches.count - 1 {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
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
