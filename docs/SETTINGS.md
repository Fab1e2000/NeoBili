# 设置开发

用户操作见 [使用手册](USAGE.md)，验证流程见 [开发与测试](DEVELOPMENT.md)。

## 分类

| 分类 | 设置 |
| --- | --- |
| 外观 | 主题色、文字大小、语言、动画 |
| 浏览 | 标签栏、内容过滤、推荐流、滚动与防误触 |
| 播放 | 播放与画质、弹幕、播放器手势、控件位置 |
| 账号 | 登录和账号管理 |
| 高级 | 设备编号；Debug 构建另有推荐实验日志 |
| 关于 | 应用信息 |

内容过滤是筛选条件的统一入口，包括通用的画幅/时长，以及推荐专用的点赞率、播放量和关键词。推荐流页面只管理来源、授权和观看记录，并提供同一推荐过滤页的快捷入口。移动入口不改存储键、默认值或已有偏好。

新增目的地时同时更新 `SettingsDestination`、类别列表和 `SettingsView.destinationView`；目的地标识用于无障碍和测试，应保持稳定。

设置页以选项为主，说明性文字放入使用手册；需要立即处理的错误、授权状态和重新打开生效提示保留在页面中。

## 存储与接线

设置入口为 `Features/Settings/SettingsView.swift`，分类和顺序统一由 `SettingsCatalog.swift` 定义。
个人页导航栏的设置入口不依赖账号资料成功加载，访客、恢复中和资料失败均可打开。
推荐过滤页同时管理本地 `blockedMids` 的解除；它不自动同步服务端黑名单，界面明确区分
官方解除与本机过滤，保留其他筛选偏好。
默认值、存储键、合法范围放在对应设置类型中；页面通过 `@AppStorage`、环境或共享模型
消费。持久化键保持兼容，新增设置应有缺失值默认和边界处理，不通过重置全局偏好迁移。

可注入 UserDefaults 的模型测试应使用独立 suite 并清理该 suite；窗口测试中依赖
`UserDefaults.standard` / `@AppStorage` 的部分由 Regression 应用沙盒隔离。

## 详情页自动播放

「详情页直接播放」使用 `neobili.detailAutoPlay`，默认开启。`NowPlayingStore` 每次
打开新视频（包括相关视频、合集及历史返回）时读取偏好；关闭后等待用户点击播放键。
未开始播放时切换分 P 只更新待播放分段，播放后切换仍直接播放。列表预取播放地址是
独立设置，不因关闭自动播放而清除或禁用缓存。

## 动画能力与偏好

`VideoCardAnimationSource.supportedPhases` 定义页面实际支持的阶段，先检查能力，
再应用总开关和来源偏好。当前推荐与直播支持进入/退出，搜索支持进入；空间、相关视频、
收藏、历史、稍后再看及合集没有自定义卡片阶段。旧偏好不能重新启用已不存在的效果。

视频来源键为 `neobili.videoCardAnimation.<source>.<phase>`。未保存来源选择时回退
`neobili.videoCardEnterAnimation` / `neobili.videoCardExitAnimation`，再回退默认开启。
来源之间独立，总开关优先；系统减弱动效由视图层共同处理。

动态单卡支持退出；关注刷新后整列进入使用独立的 `dynamicRefreshEnterKey`，不受旧单卡
进入键影响。页面淡入独立控制，系统导航、菜单与 Picker 不受自定义动画总开关影响。

调用 `.videoCardAnimationSource(...)` 时保持列表、过滤批次和动画等待使用同一来源。
关闭对应效果应立即释放等待任务；不得用动画开关绕过内容过滤或补查。

## 显示与导航

主题、字号、语言由 `AppTheme`、`AppTextSize`、`AppLanguage` 管理。语言在启动时确定，
修改后重新打开生效；新增界面文字同步维护 String Catalog。
标签顺序、隐藏与启动页由 `MainTabSettings` 约束。主页面标题没有设置项：推荐、搜索、资料库、关注、直播
均通过 `rootPageChrome` 使用原生 `inlineLarge` 标题并随下滑收起，头像入口放在导航栏右侧。
字体风格由 `AppFontStyle` 管理，选项为默认字体和宋体，保存到 `neobili.fontStyle`，启动时确定，
改动后重新打开生效。宋体使用内置的思源宋体（SIL OFL，Regular 与 SemiBold 两个字重，中等及以下用
Regular，半粗及以上用 SemiBold），同一套字形覆盖拉丁字母与简体汉字，不依赖系统的中文回退。新代码用
`Font.app(_:weight:)`、`AppFont.uiFont` 与 `AppFont.preferred` 取字体，不直接使用系统文字样式；图标符号和
弹幕保留系统字体。
播放器手势和控件位置保留各自合法范围及恢复默认逻辑，避免在调用点重复定义常量。

## 推荐来源

“推荐流 → 推荐来源”提供移动端、网页、混合三种模式，保存后完全退出并重新打开应用生效。
`neobili.rcmd.source` 保存 `app` / `web` / `merged`；缺失或无效时沿用旧
`neobili.rcmd.useApp`（未设置则移动端）。启动时固定来源，设置变化不会触发当前首页刷新。

网页模式采用 BiliPai 的 `fresh_type=3`、毫秒时间戳 `feed_version` 和 `y_num`；混合模式的
网页分支使用 `V8` / `fresh_type=4`。混合模式并行获取两路、移动端优先交错、按视频标识去重，
两路分别推进分页；单路网络失败保留成功结果并在下次分页重试失败位置，两路结束才停止。
已登录但缺少 App 凭据时，移动端和混合模式提示授权，不自动改成匿名请求。
移动端保留现有 iOS 身份、签名及服务器游标，没有移植 BiliPai 的 TV/Android HD 登录身份、
静态 fingerprint 或 session。此实现是合并策略的 iOS 适配，不代表复现 Android 推荐效果。
参考 [BiliPai 推荐实现](https://github.com/jay3-yy/BiliPai/blob/fba155c985dcf9ba2d4d354ad976f3e89a9f035f/app/src/main/java/com/android/purebilibili/data/repository/VideoRepository.kt)。

## 设备编号

首次进入显示推荐影响与自有 BUVID 导入提示，确认后通过 `neobili.deviceIdentity.introductionSeen` 持久化，不因重新打开页面或修改编号再次弹出。

高级 → 设备编号提供 BUVID 输入与保存。`neobili.appBuvid.custom` 保存用户填写的编号，去除首尾空白并校验 16–128 位 ASCII 字母、数字或连字符；空值使用首次生成后固定保存的随机编号。旧 system/random 偏好不再决定普通应用身份，既有原编号和随机编号缓存保留。进程启动时固定选择，保存后重新打开生效。不同自定义编号的访客登记、fingerprint 和 ticket 按编号隔离，账号登录凭据共用；不混用旧设备回执。
