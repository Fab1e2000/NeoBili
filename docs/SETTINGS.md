# 设置开发

用户操作见 [使用手册](USAGE.md)，验证流程见 [开发与测试](DEVELOPMENT.md)。

## 存储与接线

设置入口为 `Features/Settings/SettingsView.swift`，按外观、浏览、播放、高级、账号分组。
默认值、存储键、合法范围放在对应设置类型中；页面通过 `@AppStorage`、环境或共享模型
消费。持久化键保持兼容，新增设置应有缺失值默认和边界处理，不通过重置全局偏好迁移。

可注入 UserDefaults 的模型测试应使用独立 suite 并清理该 suite；窗口测试中依赖
`UserDefaults.standard` / `@AppStorage` 的部分由 Regression 应用沙盒隔离。

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
标签顺序、隐藏与启动页由 `MainTabSettings` 约束，标题栏由 `TitleBarSettings` 统一消费。
播放器手势和控件位置保留各自合法范围及恢复默认逻辑，避免在调用点重复定义常量。
