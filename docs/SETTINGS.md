# 设置开发说明

用户设置和手势说明见 [使用手册](USAGE.md)。

## 旧设置兼容与开发接线

既有设置键保持不变。新版逐页视频动画键为 `neobili.videoCardAnimation.<source>.<phase>`；`source` 由 `VideoCardAnimationSource` 定义，`phase` 为 `enter` 或 `exit`。

「详情页直接播放」使用 `neobili.detailAutoPlay`，未保存时默认为开启。`NowPlayingStore` 每次打开新视频时读取这个值；关闭时仍加载详情和相关内容，播放请求等用户点击播放键后发起。列表里的「滑过视频时预取播放地址」是独立设置。

某页尚未保存单独选择时，继续使用旧的 `neobili.videoCardEnterAnimation` 或 `neobili.videoCardExitAnimation`；旧键也未设置时默认为开启。用户为单页保存选择后，该页独立生效，不会修改其他页面或动态设置。总开关优先于所有来源选择。

列表入口在批次解析修饰符外侧调用 `.videoCardAnimationSource(...)`，同时向共享入场、过滤完成时钟和移除视图提供来源。首页刷新及收藏、历史、稍后再看的移除任务须向等待/动画函数显式传入相同 `source`。动态仍使用 `.dynamic` 类别，忽略视频来源。合集保留 `.collection` 来源供未来扩展，其当前原生 Picker 行不应用自定义入场或退出。
