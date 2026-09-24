import SwiftUI

struct DisplaySettingsView: View {
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex

    private static let labels = [String(localized: "最小"), String(localized: "较小"), String(localized: "小"), String(localized: "标准"), String(localized: "大"), String(localized: "较大"), String(localized: "最大")]

    static func label(for index: Int) -> String {
        labels[min(max(index, 0), labels.count - 1)]
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("当前档位", value: Self.label(for: textSizeIndex))
                Text("正文预览：这段文字会随档位一起变化")
                    .font(.body)
                    .dynamicTypeSize(AppTextSize.size(at: textSizeIndex))
                    .padding(.vertical, 12)
                HStack(spacing: 12) {
                    Text("小").font(.footnote)
                    Slider(
                        value: Binding(get: { Double(textSizeIndex) }, set: { textSizeIndex = Int($0.rounded()) }),
                        in: 0...Double(AppTextSize.steps.count - 1), step: 1
                    )
                    .accessibilityLabel("文字大小")
                    .accessibilityValue(String(localized: "第 \(textSizeIndex + 1) 档，共 \(AppTextSize.steps.count) 档"))
                    Text("大").font(.title3)
                }
                .dynamicTypeSize(.large)
                Button("恢复标准") { textSizeIndex = AppTextSize.defaultIndex }
                    .disabled(textSizeIndex == AppTextSize.defaultIndex)
            } footer: {
                Text("App 内统一使用这里的文字大小，不跟随系统设置。")
            }
        }
        .settingsPage("文字大小")
    }
}
