# 架构

NeoBili 是使用 SwiftUI、UIKit 和 MPVKit 的 iOS 客户端，没有单独部署的服务器。“前后端解耦”在本项目中指：页面和业务状态依赖服务契约，网络、签名及存储实现通过适配器提供。值与服务契约由静态框架 `NeoBiliDomain` 编译，通用缓存、共享请求池与日期格式化由 `NeoBiliCore` 编译；两个模块均没有项目内依赖。网络、身份、签名、上报和媒体缓存由 `NeoBiliData` 编译，依赖 Domain 与 Core。其余层由 `NeoBili` App target 编译；App 组装 Data 适配器，Application / Features 只使用领域契约，其目录边界继续由检查脚本维护。

构建、测试和设备使用统一见[开发与测试](DEVELOPMENT.md)。

## 目录与依赖方向

| 目录 | 负责什么 | 不应放入什么 |
| --- | --- | --- |
| `App` | 启动、根路由、生产依赖组装 `ApplicationServices+Live` | 接口字段和响应解析 |
| `Features` | SwiftUI 页面、UIKit 列表、交互和展示组件 | HTTP 请求、签名、凭据读取 |
| `Application` | 页面状态、加载任务、分页、缓存及播放协调 | URLSession、接口地址和传输协议 |
| `Domain/Services` | 按业务划分的可注入操作、账号快照、实时通道协议 | 生产客户端单例和网络实现 |
| `Domain/Models` | 共享值、解码模型、筛选规则和设置值 | 页面类型、播放器实例、网络访问 |
| `Data/Services` | 将服务契约连接到生产实现的适配器 | SwiftUI 页面状态 |
| `Data/Networking` | 端点、传输、身份、签名、响应解析及上报 | View / ViewModel 依赖 |
| `Data/Media` | 图片传输与缓存、弹幕下载 | 页面导航 |
| `Platform` | mpv、系统媒体控制等平台适配 | 业务页面 |
| `Core/Caching`、`Core/Formatting` | 不依赖业务的请求合并、内存缓存与日期格式化（NeoBiliCore） | 页面、账号、生产默认实例 |
| `Core/UI`、`Core/Extensions` | 共享组件、主题、格式化和交互工具 | 业务接口调用 |
| `App/Diagnostics`、`Core/Diagnostics` | 显式启用的业务诊断/回放与通用滚动测量 | 默认后台探测 |

通常的请求路径是：`View → Application model → Domain service → Data adapter → APIClient`。简单的一次性操作可以由 View 使用环境中的服务完成；分页、重试和长任务由状态模型持有。

Domain 服务操作全部是 `@Sendable` 闭包（架构检查禁止 `*Operation` 标注 `@MainActor`）。网络会话、签名、JSON/Protobuf 解码，以及直播二进制帧的 zlib 解压、粘包拆分和消息 JSON 解析都在主线程之外执行；Application 只把结果写回页面状态。首页推荐等大列表的过滤与分组结果按列表、设置和元数据修订号记忆化，刷新淡入等无关状态变化不会重复全量扫描。

编译模块依赖如下；Domain 与 Core 没有项目内依赖：

```mermaid
flowchart LR
    App[NeoBili App] --> Data[NeoBiliData]
    App --> Domain[NeoBiliDomain]
    App --> Core[NeoBiliCore]
    Data --> Domain
    Data --> Core
```

App target 包含 App、Application、Features、Platform 和共享 UI。Application 禁止依赖 Features，Core/UI 禁止依赖 Features 与 Data，Application 和 Features 禁止依赖 Data。生产组装位于 App，平台媒体适配可使用 Data 的窄接口。图片查看器通过文件读写闭包访问由 App 组装的磁盘缓存。内部端点、编码器细节和队列模型不作为公共 API，测试通过 `@testable import NeoBiliData` 验证。

## 服务如何注入

`ApplicationServices` 是按业务分组的值类型。`App/ApplicationServices+Live.swift` 组装生产实现；页面通过 `EnvironmentValues.applicationServices` 取得依赖。模型通过初始化参数接收服务或更小的 loader / writer 闭包。已有的默认初始化方式仍使用生产组装，方便普通页面创建。网络客户端、传输、WBI 签名器与身份的生产便利初始化器位于 `App/NetworkingDefaults.swift`，转发到 Data 的显式依赖初始化器。生产网络会话由 App 持有；Data 的会话工厂保留编译期 Regression 隔离，端点和缓存显式接收 session 或传输闭包。

`ApplicationStores` 统一持有点赞差量、关注已读和搜索历史，生产图由 App 组装。关注入口从环境取得服务和状态，全部关注、UP 主空间与动态详情沿导航链继承同一份依赖。关注和空间里的视频与图文动态使用同一会话的点赞差量，详情沿用打开它的动态模型。搜索页面显示与模型写入同一历史实例。

测试为当前模型创建独立依赖，不替换全局单例。只实现该测试需要的操作；未配置操作抛出明确错误，不能假装成功。测试创建的服务应随模型传入其子模型，避免子模型意外使用生产默认值。`AccountSessionClient` 管理登录存储边界；`LiveDanmakuStreaming` 管理实时通道，展示模型接收连接状态、热度及消息事件。

服务契约与线上协议名有部分对应，便于核对研究证据；调用方不接触 `APIClient`、`DeviceIdentity` 或端点 URL。`Live*Service` 负责将领域操作映射到现有协议实现；工厂与端点接收显式客户端、身份及上报依赖，生产默认入口仅在 App 组装层提供。测试若要验证传输行为，应直接注入端点的客户端；服务单元测试则替换操作闭包。

## 状态与任务所有权

`NowPlayingStore` 从打开到关闭持有当前媒体、详情模型和返回历史。`PlayerViewModel` 协调播放、画质、备用源与本地续播；`PlaybackReportingCoordinator` 管理观看累计、心跳和播放行为边界，平台会话负责内核。账号切换或媒体切换后，旧标识的回调不能修改新状态。

在线章节由当前视频和分 P 的 `PlayerViewModel` 异步加载，请求随模型停止而取消。播放器控件中只有进度条读取高频播放位置，章节标题和选中状态在该视图内计算。

本机播放和投屏分别校验结束事件的来源并处理睡眠与循环，需要切集时复用同一组导航动作。

历史记录、收藏夹详情和稍后再看的列表模型分别定义分页规则，由 `LibraryListState` 协调刷新暂存与提交、旧请求失效、移除与回滚。页面在刷新动画完成后提交新列表。稍后再看的会话归属和刷新失败重试由其模型管理。播放器首次打开与切换画质共用轨道选择逻辑，播放会话仍由播放器模型持有。

离线缓存的入队、暂停、取消及删除先写入清单，再执行对应的传输操作。旧文件通过清单记录清理，正在播放的版本保留至播放租约释放。

缓存准备与在线播放共用 `x/player/v2` 的正式章节解析。缓存项随资源保存章节，离线播放器直接读取清单，旧清单缺少章节字段时按空列表处理。

页面模型持有自己的加载任务。共享缓存持有共享下载任务，单张卡片退出只取消自己的等待。直播实时连接拥有认证、心跳和重连任务，`stop()` 统一终止；展示模型拥有列表合并和 SC 历史任务。

离线封面、锁屏封面和列表图片共用 `BiliImageLoader` 的下采样与缓存。相关视频预取沿用可见卡片的图片管线，并受共用预取并发限制约束。

视频详情用常驻横向分页承载简介与评论。两页共享折叠距离，各自保存阅读位置。外层无滚动轴的原生视口从底部对齐固定高度画布，裁切时由 SwiftUI 直接传递环境。播放器画幅已知时，渲染宿主保持展开尺寸，画面居中等比缩放，控件和字幕跟随可见视口布局。

详细规则按问题阅读：

- [账号、身份与请求](architecture/accounts.md)
- [播放与观看记录](architecture/playback.md)
- [列表、图片与取消](architecture/lists-images.md)
- [设置分类与持久化](SETTINGS.md)

## 如何扩展

1. 在 `Domain` 定义调用方需要的数据和操作，避免引用页面嵌套类型。
2. 在 `Data` 实现接口适配，复用现有身份校验、错误处理和取消机制。
3. 在 `App` 组装生产依赖，在 `Application` 管理操作状态，在 `Features` 呈现结果。
4. 测试业务状态时注入受控服务；测试端点时使用受控传输。不要为了运行单元测试读写真实账号。
5. 移动源码后同步离线测试的输入路径，并运行 `python3 scripts/check-architecture.py` 和开发指南中的相关检查。

`project.yml` 是工程配置来源；各层分别采用 synchronized folder。Domain 文件只属于 `NeoBiliDomain`，Core/Caching 与 Core/Formatting 属于 `NeoBiliCore`，Data 属于 `NeoBiliData`，其余层属于 App；同一层新增或移动 Swift 文件无需手工登记。跨模块移动需同步配置并重新生成工程。App、测试和离线 harness 都直接导入项目模块。离线 harness 从同一批源码构建三个同名静态库，再链接所需的 App 层源码和场景入口。

播放器事件、画质与手势设置值属于 Domain；mpv 加载和渲染宿主、窗口方向属于 Platform。观看上报、列表删除/入场状态以及设置持久化属于 Application。Domain 不持有 UserDefaults；设备偏好的读取适配位于 Data，纯 URL 归一化位于 Domain。

UP 主空间按「投稿 / 合集 / 动态」组织三栏，各栏独立滚动和刷新，共享资料头部的折叠位置。
`SpaceViewModel` 组合 `SpaceCollectionsModel` 和 `DynamicFeedModel`，首次进入「合集」时加载合集和系列。
`SpaceCollectionDetailModel` 随导航继承服务与视频过滤依赖，根据合集或系列类型调用 `CommunityService` 的分集操作，
与目录共用分页和暂存刷新，排序切换使前一排序的请求失效。目录和分集均复用 `VideoListCard`。
空间页资料头部和关注动态内容使用独立展示组件，滚动协调、导航和刷新任务由空间页持有。全部关注分页状态由 Application 的 `FollowingAllUpsModel` 管理。首页图片预取消费者由 `HomeFeedImagePrefetcher` 在索引路径与显示中的 cell 之间转交，并沿用快照切换和离屏取消入口。

显式启用的性能演示和搜索诊断属于 App 诊断组装。首页模型始终使用传入的 loader，App 根据演示启动参数选择生产默认 loader；诊断模式不会覆盖调用方注入的数据源。窗口方向锁仍是 AppDelegate 与窗口适配共用的进程级系统状态，由 App 创建。

账号凭据变化的通知名属于 Domain 的 `AccountSessionEvents`；Data 发布状态变化，Application 订阅同一通知契约。
