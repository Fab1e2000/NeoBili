# 小窗、设置和加载收缩修订验证

2026-09-10，iPhone 17 真机运行 **110 项 XCTest，0 失败**，测试用例合计耗时约 25.3 秒。Debug 测试包与 Release 真机构建均通过，未使用 Simulator。

本轮新增或强化的检查包括：

- 小窗在退出请求中同步出现，不再等待旧页面的 `onDisappear`；同一播放器、进度和停靠位置保留。
- 使用真实 UIKit 小窗容器执行拖动、吸附、中途停止动画、再次拖动。停止位置取自 presentation layer，新拖动从显示位置继续；测试容许误差为 1 pt。
- 页面与小窗轮流接管同一个渲染控制器，旧宿主迟到的布局与更新不得抢回或移除当前画面；重试及备用播放源继承小窗归属。
- 小窗之外的透明区域不拦截触摸；渲染尺寸随画幅调整，移动过程中不重复创建内容宿主。
- 视频动画逐页独立、继承旧设置、关闭总开关及分来源取消等待；动态动画保持统一设置。
- 首帧前的 `playing` 事件仍属于加载，横屏加载不能隐藏，竖屏最多收至标准高度。暂停才可继续隐藏；迟到画幅与重新加载不会短暂显示粉色栏。

`offline-harness/run.sh` 同样通过，包括 7 组收缩回归和 6 组动画设置回归。

结果包：`/tmp/NeoBiliMiniRefinementVerified-20260910.xcresult`。测试日志：`/tmp/neobili-mini-refinement-tests-verified.log`。Release 日志：`/tmp/neobili-mini-refinement-release.log`。

最终 Release 已安装并成功启动于 iPhone 17（`com.elsterlee.NeoBili`）。安装和启动记录分别为 `/tmp/neobili-mini-refinement-install.json`、`/tmp/neobili-mini-refinement-launch.json`。

下图来自真机测试中的真实 UIKit 小窗容器，使用本地红色 SwiftUI 内容验证尺寸、位置和命中区域；它是布局测试截图，不是视频播放截图，也不代表已测得整 App 帧率或转场延迟。

![真机小窗容器布局](mini-player-container-device.png)

加载布局参考了本项目保留的 PiliPlus 源码：`lib/pages/video/view.dart` 中的标准最小高度和 `lib/pages/video/controller.dart` 的画幅变化处理；首帧之前的独立限制按用户要求实现。用户说明集中于根目录 README，设置键与接线说明位于 `docs/SETTINGS.md`。
