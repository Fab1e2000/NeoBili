import SwiftUI

/// 首页专用过滤。全局画幅与时长过滤继续独立生效。
struct RecommendationFilterSettingsView: View {
    @AppStorage(RecommendationFilter.minLikeRatioKey) private var minLikeRatio = 0
    @AppStorage(RecommendationFilter.minDurationKey) private var minDuration = 0
    @AppStorage(RecommendationFilter.minPlayKey) private var minPlay = 0
    @AppStorage(RecommendationFilter.titleBanWordKey) private var titleBanWord = ""
    @AppStorage(RecommendationFilter.zoneBanWordKey) private var zoneBanWord = ""
    @AppStorage(RecommendationFilter.exemptFollowedKey) private var exemptsFollowed = true

    var body: some View {
        Form {
            Section {
                picker("点赞率", selection: $minLikeRatio, options: RecommendationFilter.likeRatioOptions) { "\($0)%" }
                picker("视频时长", selection: $minDuration, options: RecommendationFilter.durationOptions) {
                    String(localized: "\($0) 秒")
                }
                picker("播放量", selection: $minPlay, options: RecommendationFilter.playOptions) { "\($0)" }
                Toggle("已关注 UP 豁免推荐过滤", isOn: $exemptsFollowed)
            } header: {
                Text("过滤")
            } footer: {
                Text("低于所选值的推荐会被隐藏。已关注 UP 发布的内容可以不受这些条件和标题关键词影响。")
            }

            Section {
                TextField("标题关键词", text: $titleBanWord, axis: .vertical)
                TextField("分区关键词", text: $zoneBanWord, axis: .vertical)
            } header: {
                Text("关键词过滤")
            } footer: {
                Text("使用 | 隔开，如：尝试|测试。标题或分区名包含这些词的推荐会被隐藏；网页端推荐不提供分区名，分区关键词只对 App 端推荐生效。")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .settingsPage("推荐内容过滤")
    }

    /// 档位与 PiliPlus 相同；0 表示不过滤。
    private func picker(_ title: LocalizedStringKey, selection: Binding<Int>, options: [Int],
                        label: @escaping (Int) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(options.contains(selection.wrappedValue) ? options : (options + [selection.wrappedValue]).sorted(),
                    id: \.self) { value in
                Text(value == 0 ? String(localized: "不限制") : label(value)).tag(value)
            }
        }
    }
}
