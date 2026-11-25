import NeoBiliDomain
import SwiftUI

/// 首页专用过滤。全局画幅与时长过滤继续独立生效。
struct RecommendationFilterSettingsView: View {
    @AppStorage(RecommendationFilter.minLikeRatioKey) private var minLikeRatio = 0
    @AppStorage(RecommendationFilter.minDurationKey) private var minDuration = 0
    @AppStorage(RecommendationFilter.minPlayKey) private var minPlay = 0
    @AppStorage(RecommendationFilter.titleBanWordKey) private var titleBanWord = ""
    @AppStorage(RecommendationFilter.zoneBanWordKey) private var zoneBanWord = ""
    @AppStorage(RecommendationFilter.exemptFollowedKey) private var exemptsFollowed = true
    @State private var blockedMids: [Int] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimations = CardAnimationSettings.defaultValue

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
            }

            Section {
                TextField("标题关键词（使用 | 隔开）", text: $titleBanWord, axis: .vertical)
                TextField("分区关键词（使用 | 隔开）", text: $zoneBanWord, axis: .vertical)
            } header: {
                Text("关键词过滤")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Section {
                if blockedMids.isEmpty {
                    Text("没有本地屏蔽的 UP 主").foregroundStyle(.secondary)
                } else {
                    ForEach(blockedMids, id: \.self) { mid in
                        HStack {
                            LabeledContent("UID", value: String(mid))
                            Button("解除本地屏蔽") {
                                RecommendationFilter.unblock(mid)
                                let next = RecommendationFilter.current().blockedMids.sorted()
                                if cardAnimations && !reduceMotion {
                                    withAnimation(RemovalFill.animation) { blockedMids = next }
                                } else {
                                    blockedMids = next
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("本地屏蔽名单")
            }
        }
        .settingsPage("推荐内容过滤")
        .onAppear { blockedMids = RecommendationFilter.current().blockedMids.sorted() }
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
