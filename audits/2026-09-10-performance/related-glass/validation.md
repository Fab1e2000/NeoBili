# 详情页推荐玻璃容器与收缩圆角

2026-09-10，iPhone 17 真机验证，无 Simulator。

- RelatedVideosSection 使用整列表原生玻璃背景，所有行取消独立实色底，直接显示（animatesEntrance=false），移除详情页进入动画设置入口。旧偏好数据不影响这一固定行为。
- 内容页上方两个圆角外侧共用收缩进度染色；播放/加载仍为原背景，完全收缩时与粉色栏一致。
- 测试结果：`/tmp/NeoBiliRelatedGlass-20260910.xcresult`，10 项通过、0 失败、0 跳过。包括动画设置7项、7态收缩像素与触摸检查1项、简介浅深/展开/大字五态1项，以及4K网络实播1项。
- 上次受设备锁屏影响的简介快照复查已通过并人工看图；本次截图中的界面布局使用生产组件与本地静态数据。
- 4K实播：BV1po4y177z8 / cid1163679532，正常账号返回并选择qn120，DASH轨道3840×2160，mpv实际解码3840×2160，firstFrame=true、isPlaying=true。证据见video-4k-safe-evidence.txt，无凭据或签名媒体地址。

Release构建通过，已安装并成功启动：安装序号5260，启动PID26867。devicectl结果为`/tmp/neobili-related-glass-install.json`和`/tmp/neobili-related-glass-launch.json`。
