import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @AppStorage(PlaybackQuality.videoStorageKey) private var preferredQuality = PlaybackQuality.defaultVideoQuality
    @AppStorage(PlaybackQuality.audioStorageKey) private var preferredAudioQuality = PlaybackQuality.defaultAudioQuality

    var body: some View {
        Form {
            Section("默认画质") {
                Picker("分辨率", selection: $preferredQuality) {
                    ForEach(PlaybackQuality.videoOptions, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                Picker("音质", selection: $preferredAudioQuality) {
                    ForEach(PlaybackQuality.audioOptions, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }
            Section {
                Toggle("缩略播放器", isOn: $miniPlayerEnabled)
            } header: {
                Text("播放方式")
            } footer: {
                Text(miniPlayerEnabled ? "退出视频页面后在底部继续播放，底部标签栏可随滚动收缩。" : "退出视频页面后停止播放，底部标签栏始终保持展开。")
            }
        }
        .settingsPage("播放与画质")
    }
}
