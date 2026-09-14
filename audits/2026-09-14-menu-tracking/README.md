# 播放器菜单长按跟踪实验（尚未运行）

用户观察：持续按住并滑动时，画质、音质菜单偶尔不高亮指下选项；更多菜单较少发生；暂停播放后恢复。

当前结论：播放状态更新是待验证因素，尚未确认根因。不能将 SwiftUI body 重算等同于原生菜单重建或触摸取消。

## 已完成

- 创建独立 `MenuTrackingProbe`，复制当前 `PlayerGlassChrome.swift`、`PlayerChromeLayout.swift`、`VideoScrubber.swift`，不引入 MPV、网络、弹幕或返回手势。
- 三组对照：暂停时间更新；10Hz 时间更新；10Hz 更新但使用 Equatable 实验边界阻止更新进入整个 chrome。
- 自动化脚本对三个菜单做连续长按、拖动、松手，并记录选择结果及展开/松手后的截图。
- ARM64 Simulator SDK 的 `build-for-testing` 已通过；单任务编译，派生目录 `/tmp/NeoBiliMenuTrackingProbe-build`，构建日志 `/tmp/NeoBiliMenuTrackingProbe-build.log`。
- 没有修改生产代码。

## 未完成与限制

- 本机无可用 Simulator runtime。iOS 27 ARM64 runtime 下载已按用户要求停止；没有启动模拟器，没有执行测试。
- 选择结果是辅助证据，不能替代“手指保持按下时是否高亮”的直接观察。运行时应另观察连续触摸过程；如需录像，只记录少量失败/成功对照，控制资源占用。
- `FrozenChrome` 的恒等比较仅用于隔离实验，会冻结进度条等全部 chrome 更新，不能作为生产修复。
- 暂停组只停止时间更新，其他控件参数保持相同，以隔离变量。此工程没有自动隐藏定时器，若无法复现，应继续对照完整播放器的生命周期和自动隐藏逻辑。
- 必须先复现原始组异常，再比较隔离组，不能把隔离组成功直接当作根因证明。

## 后续运行

安装运行时后，只启动一台 iPhone Simulator，关闭测试并行和设备克隆。工程是 `MenuTrackingProbe/MenuTrackingProbe.xcodeproj`，Scheme 为 `MenuTrackingProbe`。测试循环按三种模式、三个控件分别记录六次结果。

构建命令（从实验工程目录执行）：

```sh
nice -n 10 xcodebuild build-for-testing \
  -project MenuTrackingProbe.xcodeproj -scheme MenuTrackingProbe \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/NeoBiliMenuTrackingProbe-build \
  -jobs 1 -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

运行测试时将 destination 换成实际模拟器 ID，并使用 `test-without-building`；保持 `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`。测试结束后关闭此次启动的模拟器。
