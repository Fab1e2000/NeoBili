# 架构

NeoBili 是 SwiftUI / Swift 6 的 iOS 26+ 客户端，播放内核为 MPVKit。
`project.yml` 管理 App 与 XCTest target；源码目录使用 synchronized folder，新增 Swift
文件无需逐个登记。开发、测试和设备使用规则统一见 [开发与测试](DEVELOPMENT.md)。

## 模块与状态所有权

| 目录 | 职责与主要入口 |
| --- | --- |
| `App` | `NeoBiliApp` 初始化，`RootView` 持有全局 store、标签及页面呈现，`AppDelegate` 输出方向约束 |
| `Core/Networking` | `APIClient`、领域化 `BiliAPI`、`LiveAPI`、登录和签名、设备身份与凭据 |
| `Core/Models` | 值模型、宽松解码、内容过滤、画幅查询及共享业务规则 |
| `Core/UI` | 图片管线、标题栏、卡片、动画、主题、语言、交互基础设施 |
| `Core/Platform` | 屏幕方向控制 |
| `Core/Diagnostics` | 按启动参数开启的性能采集、回放与交互探针 |
| `Features/Home`、`Following`、`Live`、`Search` | 推荐、关注动态、直播和搜索的页面与请求状态 |
| `Features/VideoDetail`、`Player`、`Danmaku` | 详情、评论、互动、播放会话、内核渲染及弹幕 |
| `Features/NowPlaying` | `NowPlayingStore` 拥有当前播放页面，协调详情呈现与缩略播放器 |
| `Features/Account`、`Library`、`Mine`、`Settings` | 会话恢复、资料库、个人入口与设置 |

`NowPlayingStore` 从打开到关闭持有路由、播放器、详情/评论及返回历史。
`PlayerViewModel` 管播放状态、画质切换、备用源、观看上报和休眠，依次持有
`MPVPlayerSession`、`MPVEngine`。旧内核事件按标识过滤，迟到回调不能更新新会话。
页面模型持有加载任务；共享缓存持有共享任务，卡片退出只取消自己的等待。

## 网络与账号

主要接口经过 `APIClient` 组装 UA、Referer、显式 Cookie 与业务信封；登录、直播和图片
各有独立入口，默认 HTTP 传输统一使用 `AppNetwork.session`。WBI 与 App 签名各自维护。
非零业务码先于成功数据解码，列表用宽松解码避免单条异常拖垮整页。

`DeviceIdentity` actor 管设备标识、凭据快照及登录会话版本；生产凭据存 Keychain，
测试可注入内存存储、独立 defaults 并关闭设备标识联网补取。
`AccountStore` 区分本地有凭据与服务端已确认登录；暂时网络失败不等同于凭据失效。

写操作不自动重试，包括形式为 GET 的推荐反馈。观看上报、推荐反馈和播放准备绑定
调用时的登录会话；账号切换后的迟到响应不能使用新凭据、返回旧播放清单或回填新缓存。

## 播放与观看记录

打开视频经 `VideoPreparationCache` 获取详情与播放地址，`PlayerViewModel` 选择媒体源，
详情额外信息和评论独立加载。缓存按登录会话去重，取消按请求所有者处理，避免旧页面关闭
误取消刚重新打开的视频。滑动预取默认关闭；开启时只预取接口元数据，不下载媒体。

本地续播与服务端观看记录分离。`PlaybackWatchProgress` 只认可首帧后、播放中且非缓冲
的连续推进；拖动目标和未播放的续播位置不能作为观看证据。首次累计真实观看 5 秒、
随后每 15 秒发心跳，暂停/退出补已确认进度。完成标记要求片尾真实推进。
同会话、视频和分 P 共用串行发送队列，慢请求合并待发值。

## 列表、图片与取消

画幅/最低时长过滤通过 `VideoDimensionProviders` 适配列表模型；已知信息直接判断，
缺失信息通过 `PortraitVideoStore` 合并查询。补查最多 6 并发，成功缓存 7 天，失败冷却
5 分钟；按批次后台串行持久化，旧快照不能覆盖新快照。过滤关闭或元数据齐全时不补查。

图片消费者共享传输及单份位图 LRU（64 MiB / 300 项）。最后一个消费者退出后取消传输
和排队解码，其他消费者不受影响；内存告警统一清空缓存。已进入 ImageIO 的同步解码
不能中途抢占，取消后不能回填结果。HTTP 缓存与解码位图缓存分工不同。

分页与刷新使用请求代号防止旧响应覆盖新状态；取消应退出等待而非显示业务错误。
环境动作盒子用于稳定回调身份，闭包只捕获必要 Binding 或独立数据，避免引用宿主形成环。
实际更新次数、帧率、耗时必须运行测量，不从代码结构推断。

## 扩展与测试边界

新增领域接口放入 `BiliAPI+领域`，列表模型放入 `Core/Models`，页面状态由对应 feature
持有；设置接线见 [设置开发](SETTINGS.md)。界面字面量使用本地化资源，动态传递文字使用
`String(localized:)`；避免把服务端文字当成本地翻译键。

Regression 是独立 App 沙盒，关闭真实网络与业务根页面启动。测试注入传输、身份、
加载器或播放器会话，窗口测试仍挂载真实生产组件。添加网络或持久化通道时，同时验证
测试隔离；完整测试入口与专项选择统一由开发指南和 `Config/*.xctestplan` 定义。
