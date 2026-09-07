# 首次搜索键盘卡顿：真机诊断

设备：用户已连接的 iPhone 17，iOS 27.0 (24A5430a)。测试使用 Debug 构建。

## 方法

诊断开关 `--search-latency-probe` 在首页出现后等待 15 秒，自动请求搜索焦点，4 秒后收起，间隔 2 秒再次请求。记录请求焦点、键盘通知、超过 50 ms 的 CADisplayLink 回调间隔及视图 body 次数。每次测试均重新启动应用进程，没有重启手机或重置系统键盘服务。这个方法测量应用请求键盘的路径，不包含手指按下到事件分发的时间。

JSON 是直接从手机应用沙盒取回的原始记录。帧间隔是可见卡顿的代理指标，不是逐帧渲染器 hitch 时长，也不等同于整段键盘动画耗时。系统键盘显示通知可能重复，`DidShow` 时间不能单独当作完整动画耗时。

## 基线和尝试

| 版本 | 首次最大帧间隔 | 第二次最大帧间隔 | 说明 |
|---|---:|---:|---|
| 原实现 | 181.6 ms | 74.3 ms | baseline.json，无 Instruments |
| 原实现，带 Time Profiler | 218.0 ms | 124.6 ms | baseline-profiled.json；采样有额外开销 |
| 仅改 `.keyboardType(.webSearch)` | 176.6 ms | 77.1 ms | 无明显改善，未作为独立修复保留 |
| 原生搜索输入框 | 151.7 ms | 56.9 ms | native-field.json |
| 原生输入框 + 网格不跟随键盘缩放 | 86.0 ms | 52.4 ms | native-stable-grid.json |
| 最终版本复测 | 81.6 ms | 56.6 ms | final-repeat-and-interaction.json |

这些是同一设备上的逐次实测，不是统计分布；系统缓存、调度和推荐内容可能影响结果，不能把每次差值都归因于单个改动。

## 调用栈证据

Time Profiler 完整基线在 `/tmp/neobili-search-baseline-full.trace`，导出在 `/tmp/neobili-search-baseline-full-profile.xml`。

首次请求焦点附近的主线程样本可见 `TUISystemInputAssistantView initWithFrame:`、`TUIKeyboardTrackingProvider`、`AFUITargetDetectionController`、`TIGetInputModeProperties` 和 `_sl_dlopen`。16.3–16.8 秒区间的 222 个主线程 CPU 样本中，69 个叶帧来自 dyld；存在输入助手、自动填充、动态加载及 SwiftUI 更新工作。部分系统符号无法完整还原，不能据此精确分摊整个停顿。

该结果支持系统输入初始化和界面更新共同参与，不能将原因完全归咎于推荐卡片或搜索网络。应用中的搜索请求尚未在本轮聚焦时发出。

## 保留的实现

- `HomeSearchTextField` 使用 UISearchTextField，直接同步原生 first responder 和 SwiftUI 绑定，支持搜索返回键和现有清空/取消逻辑。
- 更新绑定时保留输入法 marked text，避免中文组合输入被重写。
- 推荐网格忽略键盘底部安全区变化；搜索结果和联想列表继续使用其正常布局。
- `SearchLatencyProbe` 只在 Debug 且显式传诊断启动参数时安装监听器。普通启动不会自动弹键盘；Release 不包含该诊断类。

## 验证限制

XCUITest 真机测试进程两次在建立 IDE 连接之前退出（code 74），尚未执行测试步骤；这不是应用断言失败，也不能报告为界面测试通过。对应测试源码保存在 SearchInteractionTests.swift，临时工程在 /tmp/NeoBiliSearchUITest，失败结果包在 /tmp/neobili-search-ui-tests.xcresult 和 /tmp/neobili-search-ui-tests-retry.xcresult。已移除手机上的测试 runner。

后续使用 `--search-interaction-probe` 在应用内对实际挂载的原生输入框执行组合文本、清空和提交事件，检查绑定和搜索状态。这种自检不替代真实触摸、第三方输入法或完整 XCUITest。

## 最终结果

最终版本两次冷启动应用进程的首次最大帧间隔为 86.0 ms 和 81.6 ms，低于未采样基线 181.6 ms。单次连续卡住的时间明显缩短，但首次键盘初始化没有完全消除：首次请求到 WillShow 仍约 152–155 ms。不能将帧间隔下降表述成整个键盘启动耗时减半。

最终真机应用内六项自检全部通过：取得焦点、保留拼音组合文本、提交中文组合文本、清空、提交搜索并收键盘、取消并回到推荐。原始 `check_*` 事件保存在 final-repeat-and-interaction.json。自检不依赖搜索接口必须成功返回视频，检验的是输入到页面状态的连接。

最终 Debug 构建已安装到手机，并以不带诊断参数的普通模式重新启动。用户登录和应用数据随覆盖安装保留。

Debug 真机构建和 Release 无签名编译均通过，`git diff --check` 通过。
