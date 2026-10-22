#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

struct ContentFilterSettingsView: View {
    @Environment(\.videoFiltering) private var filtering
    private var durationFilter: VideoDurationFilterSettings { filtering.duration }
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue

    var body: some View {
        @Bindable var durationFilter = filtering.duration
        Form {
            Section {
                Toggle("隐藏竖屏视频", isOn: $hidesPortraitVideos)
            } header: {
                Text("画幅")
            }
            Section {
                // 原来是 1 分钟一档的步进器，想设到 10 分钟要连点十次；改为常用档位。
                Picker("最短视频时长", selection: $durationFilter.minimumMinutes) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? String(localized: "不限制") : String(localized: "\(minutes) 分钟")).tag(minutes)
                    }
                }
            } header: {
                Text("时长")
            }
            Section {
                NavigationLink("推荐内容过滤") { RecommendationFilterSettingsView() }
            } header: {
                Text("首页推荐")
            }
        }
        .settingsPage("内容过滤")
    }

    /// 常用档位；旧版本步进器存下的非整档值也保留为一个选项，不会被悄悄改掉。
    private var durationOptions: [Int] {
        let presets = [0, 1, 2, 3, 5, 10, 15, 20, 30, 60]
        let current = durationFilter.minimumMinutes
        return presets.contains(current) ? presets : (presets + [current]).sorted()
    }
}
