#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage(DetailPlaybackSettings.storageKey) private var detailAutoPlay = DetailPlaybackSettings.defaultValue
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @AppStorage(PlaybackQuality.videoStorageKey) private var preferredQuality = PlaybackQuality.defaultVideoQuality
    @AppStorage(PlaybackQuality.audioStorageKey) private var preferredAudioQuality = PlaybackQuality.defaultAudioQuality
    @AppStorage(VideoPreparationCache.scrollPrefetchKey) private var prefetchesOnScroll = false

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
            Section("播放方式") {
                Toggle("详情页直接播放", isOn: $detailAutoPlay)
                Toggle("缩略播放器", isOn: $miniPlayerEnabled)
                Toggle("滑过视频时预取播放地址", isOn: $prefetchesOnScroll)
            }
        }
        .settingsPage("播放与画质")
    }
}
