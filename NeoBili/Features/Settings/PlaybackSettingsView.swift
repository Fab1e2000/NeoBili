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
            Section {
                Toggle("详情页直接播放", isOn: $detailAutoPlay)
            } footer: {
                Text("关闭后打开视频详情页只加载页面内容，点击播放键后才开始播放。")
            }
            Section {
                Toggle("缩略播放器", isOn: $miniPlayerEnabled)
            } header: {
                Text("播放方式")
            } footer: {
                Text(miniPlayerEnabled ? "退出视频页面后在底部继续播放，底部标签栏可随滚动收缩。" : "退出视频页面后停止播放，底部标签栏始终保持展开。")
            }
            Section {
                Toggle("滑过视频时预取播放地址", isOn: $prefetchesOnScroll)
            } footer: {
                Text("打开后，在列表里停留过的视频点开会更快，但会以你的账号向 B 站请求这些没点开的视频，可能影响推荐。关闭时和 PiliPlus 一样，点开才请求。")
            }
        }
        .settingsPage("播放与画质")
    }
}
