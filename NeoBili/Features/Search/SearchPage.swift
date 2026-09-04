import SwiftUI

/// 搜索页。首页顶部那颗搜索胶囊推进来的。
///
/// 页面本身只负责「还没搜」和「搜到了」两种内容，搜索框、候选词浮层、
/// 取消按钮全部交给系统的 `.searchable`——进页面就自动聚焦、弹键盘。
struct SearchPage: View {
    @State private var viewModel = SearchViewModel()
    @State private var isSearchPresented = false

    var body: some View {
        Group {
            if viewModel.hasSubmittedSearch {
                SearchResultsView(viewModel: viewModel)
            } else {
                ContentUnavailableView {
                    Label("搜索视频", systemImage: "magnifyingglass")
                } description: {
                    Text("输入关键词，或从下面的候选词里挑一个。")
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.query,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "搜索视频"
        )
        // 系统原生的候选词浮层。点中一条由 searchCompletion 填回输入框
        // 并触发下面的 onSubmit，不需要自己处理点击。
        .searchSuggestions {
            if viewModel.isShowingSuggestions {
                ForEach(viewModel.suggestions) { suggestion in
                    // 就是一行黑字：放大镜图标去掉，只留一点左边距。
                    Text(suggestion.value)
                        .foregroundStyle(.primary)
                        .padding(.leading, 6)
                        .searchCompletion(suggestion.value)
                }
            }
        }
        .onSubmit(of: .search) { viewModel.submit() }
        // 输入一变就重新取候选词。上一次的任务会被 SwiftUI 取消，
        // 所以视图模型里那个 250 毫秒的等待就等于防抖。
        .task(id: viewModel.trimmedQuery) { await viewModel.loadSuggestions() }
        // 清空输入就回到「还没搜」的状态。
        .onChange(of: viewModel.trimmedQuery) {
            if viewModel.trimmedQuery.isEmpty { viewModel.reset() }
        }
        // 等推场动画走完再要焦点。转场途中要焦点，系统会把它丢掉，键盘不弹。
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            isSearchPresented = true
        }
        .onAppear { OrientationController.enterPortrait() }
    }
}

#Preview {
    NavigationStack {
        SearchPage()
            .environment(NowPlayingStore())
            .environment(AccountStore())
            .environment(ActionFeedback())
    }
}
