#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 界面语言：跟随系统、简体中文或 English。系统的本地化在启动时确定，改动下次打开 App 生效。
struct LanguageSettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var selection = AppLanguage.system

    var body: some View {
        Form {
            Section {
                Picker("语言", selection: Binding(get: { selection }, set: { value in
                    selection = value
                    AppLanguage.apply(value)
                })) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if selection != AppLanguage.launched {
                        Text("完全退出并重新打开 NeoBili 后生效。")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .settingsPage("语言")
    }
}
