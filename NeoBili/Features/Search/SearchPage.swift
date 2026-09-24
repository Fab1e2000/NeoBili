import SwiftUI

/// 独立搜索 Tab 的内容；输入框只挂在本 Tab 的导航栈上。
struct SearchPage: View {
    let viewModel: SearchViewModel
    @Binding var isFocused: Bool
    @Environment(\.appThemeColor) private var themeColor
    let onSubmit: (String?) -> Void
    @State private var history = SearchHistory.shared
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 标题栏随内容滚动时，热搜页上滑后收起标题，只留搜索框。
    @State private var isHeaderCollapsed = false
    @State private var headerHeight: CGFloat = 0
    @State private var homePosition = ScrollPosition(edge: .top)

    /// 只在搜索首页（历史/热搜）显示标题；输入、联想和结果页让搜索框顶到最上方。
    private var showsHeader: Bool {
        !isFocused && !viewModel.isShowingSuggestions && !viewModel.hasSubmittedSearch
    }

    /// 标题固定时常驻；随内容滚动时，上滑后收起。
    private var displaysHeader: Bool {
        showsHeader && (pinsTitleBar || !isHeaderCollapsed)
    }

    var body: some View {
        // Keep the search bar and its lifecycle above a stable container.
        // Group distributes modifiers onto the changing content branch, which
        // can recreate the input and invoke onDisappear on the first character.
        VStack(spacing: 0) {
            if viewModel.isShowingSuggestions {
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
                .scrollPosition($homePosition)
                .scrollDismissesKeyboard(.interactively)
                // 标题和搜索框都在顶部栏里：标题收起只改变顶部栏高度，内容的滚动位置不动。
                // 用「离当前顶端的距离」加回差判断，收起/展开后都不会立刻反向触发。
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, distance in
                    guard !pinsTitleBar, showsHeader else { return }
                    if !isHeaderCollapsed, distance > headerHeight + 16 {
                        isHeaderCollapsed = true
                    } else if isHeaderCollapsed, distance < 1 {
                        isHeaderCollapsed = false
                        // 标题回来时列表跟着下移，不让标题盖住最上面的搜索历史。
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                            homePosition.scrollTo(edge: .top)
                        }
                    }
                }
                .onAppear { isHeaderCollapsed = false }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // 仅背景越过键盘安全区；列表仍正常避让键盘和搜索栏。
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if displaysHeader {
                    PageHeader(title: String(localized: "搜索"))
                        .padding(.horizontal, 20)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                HomeSearchBar(text: Binding(get: { viewModel.query }, set: { viewModel.query = $0 }),
                              isFocused: $isFocused,
                              onSubmit: { onSubmit(nil) },
                              onCancel: { isFocused = false })
                    .frame(height: 56)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: displaysHeader)
        }
        .task { await viewModel.loadHotSearches() }
        .onDisappear { isFocused = false }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { OrientationController.enterPortrait() }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle(String(localized: "搜索历史"))
                Spacer()
                Button("清空", systemImage: "trash") { history.clear() }
                    .font(.caption)
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 36)
                    .disabled(history.keywords.isEmpty)
                    .accessibilityLabel("清空搜索历史")
                    .accessibilityIdentifier("search.clearHistory")
            }
            if history.keywords.isEmpty {
                Text("暂无搜索历史").font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                WrappingCapsuleLayout(spacing: 8) {
                    ForEach(history.keywords, id: \.self) { keyword in
                        Button { onSubmit(keyword) } label: {
                            Text(keyword)
                                .font(.caption)
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
        Text(title).font(.subheadline.weight(.semibold))
            .frame(height: 36, alignment: .leading)
    }

    private var hotSearchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(String(localized: "热搜"))
            if viewModel.isLoadingHotSearches {
                ProgressView().frame(maxWidth: .infinity).padding(8)
            } else if let error = viewModel.hotSearchError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await viewModel.loadHotSearches() } }
                        .font(.caption)
                }.padding(.vertical, 8)
            } else if viewModel.hotSearches.isEmpty {
                Text("暂无热搜").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            // 一行一条，字号与推荐页卡片标题一致。
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.hotSearches.enumerated()), id: \.element.id) { index, item in
                    Button { onSubmit(item.keyword) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(index + 1)).font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(index < 3 ? themeColor : Color.secondary)
                                .frame(minWidth: 22, alignment: .leading)
                            Text(item.title).font(.subheadline).foregroundStyle(.primary)
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
