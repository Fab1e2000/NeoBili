import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: appVersion)
                LabeledContent("播放内核", value: "mpv (MPVKit)")
                LabeledContent("接口与交互参考", value: "PiliPlus / MeloX")
            }
        }
        .settingsPage("关于")
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
