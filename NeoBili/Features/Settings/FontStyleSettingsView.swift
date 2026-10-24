import SwiftUI

/// 字体风格：默认字体或宋体。字体在启动时确定，改动后重新打开 App 生效。
struct FontStyleSettingsView: View {
    @AppStorage(AppFontStyle.storageKey) private var selection = AppFontStyle.standard.rawValue

    private var style: AppFontStyle { AppFontStyle(rawValue: selection) ?? .standard }

    var body: some View {
        Form {
            Section {
                Picker("字体风格", selection: $selection) {
                    ForEach(AppFontStyle.allCases) { option in
                        Text(verbatim: option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                if style != AppFontStyle.launched {
                    Text("完全退出并重新打开 NeoBili 后生效。")
                        .foregroundStyle(.orange)
                }
            }
            Section("预览") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "视频标题：夜航星与远方的灯")
                        .font(.app(.headline, style: style))
                    Text(verbatim: "Midnight Voyage — A Quiet Reflection")
                        .font(.app(.subheadline, style: style))
                    Text(verbatim: "正文预览：这段文字用于对比字体风格，中文、English 与 1234567890 混排。")
                        .font(.app(.footnote, style: style))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .settingsPage("字体风格")
    }
}
