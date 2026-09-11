# 全屏控件精简与黑边利用

2026-09-10，实体 iPhone 17，未使用 Simulator。

- 全屏底部统一为一行：当前时间、进度、总时长与退出全屏；移除播放器分享按钮。
- 分辨率和音质各自成为顶部的原生 Menu，按钮文字来自实际选中的轨道。空间足够时保留标题；极矮非全屏在更多菜单中保留画质入口。直播提供一个独立清晰度菜单。
- 省略号菜单去除前后 10 秒，增加稍后再看，沿用登录检查与现有 API；进行中禁止重复提交，并隔离账号切换后的反馈。验收未替用户添加任何测试视频。
- 全屏控件沿整个窗口排布，视频继续等比显示。横屏上下控件行使用左右各 28 pt 的圆角留白，避免把侧边中段的刘海安全区套在整行上。16:9 和 4:3 视频的返回、更多及退出全屏按钮因此可以放进侧边黑区。
- 主要按钮、菜单至少 48 pt 高，图标按钮为完整 48×48 pt 矩形触摸区，进度条操作高度为 48 pt；原生 Menu 的按下状态负责暂停控件自动隐藏，移除额外点击手势。纯观察用途的返回手势视图明确透传 UIKit 触摸。

## 验证

`/tmp/NeoBiliPlayerToolbar-20260910.xcresult`：55 项全部通过。

| 套件 | 通过 |
| --- | ---: |
| PlayerGlassStyleTests | 8 |
| PlayerPlaybackTests | 16 |
| LivePlayerTests | 15 |
| MiniPlayerTests | 16 |

布局断言覆盖全屏/非全屏、4 种音视频菜单组合、3 种宽度、字号和高度边界。真机静态截图覆盖 12 种基础状态、3 种真实等比黑边/长档位名称及三种小窗大小。测量整个控件层和视频图像在 UIWindow 中的实际坐标；按钮区域断言来自布局模型，不等同于自动边缘点按验收。另一个 UIKit 命中测试验证非视觉观察层不会挡住下层按钮的角落和中心。

截图检查发现错误态的装饰图标与禁用的画质菜单重叠，已将不可用的独立画质菜单在错误状态隐藏；`/tmp/NeoBiliPlayerToolbarError-20260910.xcresult` 单独复验该 12 状态截图测试通过，并确认最终错误图无重叠。没有把静态菜单样本称为实际网络画质切换或稍后再看写入测试。

最终 Debug 与 Release 构建成功，`git diff --check` 通过。

最终 Release 已安装并启动在 iPhone 17：`/tmp/neobili-player-toolbar-final-install.json`（安装序号 5220）、`/tmp/neobili-player-toolbar-final-launch.json`。安装包 bundle ID 为 `com.elsterlee.NeoBili`。

使用的原生接口参考：[Apple Menu indicator](https://developer.apple.com/documentation/swiftui/view/menuindicator(_:))、[Apple content shape](https://developer.apple.com/documentation/swiftui/view/contentshape(_:_:eofill:))。
