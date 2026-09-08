# NeoBili 模块地图

> 面向维护者的架构速览：目录职责、关键数据流、状态与任务的所有权、新功能的落点。
> 描述的是当前实现；改动相关模块时请同步更新本文。

## 总览

第三方 B 站客户端（SwiftUI + Swift 6 严格并发，iOS 26+）。工程用 XcodeGen 生成
（`project.yml`），两个 target：

- **NeoBili**：App。`sources` 是 `NeoBili/` 的 syncedFolder——新增 `.swift` 文件自动进编译，不需要登记。
- **NeoBiliTests**：单元测试（iOS bundle，需要设备/Simulator 运行）。纯逻辑另有一套宿主机离线测试，见文末。

依赖只有 [MPVKit](https://github.com/mpvkit/MPVKit)（播放内核）。

## 目录职责

```
NeoBili/
  App/            进程入口。NeoBiliApp（预热设备标识与 WBI 密钥、音频会话）、
                  RootView（三 Tab + 全局 store 环境 + 视频页 fullScreenCover）、
                  AppDelegate（方向锁的 UIKit 出口）。
  Core/
    Networking/   传输与接口。APIClient 负责主要业务 API（公共头、Cookie、
                  信封解码）；BiliAPI/BiliPassport 按 endpoint 分文件；WBISigner、
                  AppSigner 负责两套签名；DeviceIdentity（actor）管 buvid 与登录凭据
                  （Keychain）；KeychainStore 是最小 Keychain 封装。
    Models/       值类型模型 + 跨页共享的业务规则：VideoDimension（画幅/旋转）、
                  VideoDurationFilterSettings（最低时长设置）、PortraitVideoStore
                  （画幅/时长补查缓存，全 App 共享）、VideoLikeStore（点赞差量）、
                  FollowingReadStore（关注已读状态，按账号持久化）、ListRemovalState
                  （删除动效 + 回滚保护）。列表接口一律宽松解码（LenientList +
                  flexibleInt/String/Bool，一条坏数据不拖垮整页）。
    Platform/     方向控制（OrientationController / OrientationLock）。
    UI/           共享视图与列表展示基础设施：BiliImage（带头像的取图 + 内存缓存）、
                  VideoListCard、FeedRefreshAnimation（三段式刷新动画 + 入场时钟）、
                  VideoVisibilityEnvironment（整批画幅判断 + 补位 + 统一动画起点）、
                  EnvironmentAction（环境值里的动作盒子）、ImageViewer（QuickLook）、
                  ShortPullRefresh、LeftEdgeTapDeadZone、ActionFeedback（全局浮层）。
  Features/
    Home/         推荐/热门流 + 站内搜索（搜索框在首页顶部，结果直接替换推荐流）。
    Following/    关注动态：FollowingViewModel（头像行）+ DynamicFeedModel（关注流与
                  UP 主动态共用的翻页/点赞）+ FollowingCarousel（侧边头像选择器，
                  UICollectionView 实现）+ SpaceView/SpaceViewModel（UP 主空间页）。
    VideoDetail/  视频页：VideoDetailView（页面骨架）、VideoDetailViewModel（详情、
                  互动）、CommentsView/CommentsViewModel（评论 + 楼中楼）、评论输入、
                  相关视频、合集与分 P、收藏夹弹窗。
    Player/       播放器：PlayerViewModel（状态机 + 备用地址恢复）、MPVPlayerSession
                  （mpv 内核封装 + PlaybackSourceBuilder 选流）、PlayerControlsOverlay、
                  PlayerVerticalGestureLayer（分区手势）、SystemNowPlayingCenter（锁屏/
                  控制中心桥接）、NowPlayingStore（视频页全局状态，见下）。
    Mine/         我的、收藏、历史、稍后再看、设置。
    Account/      账号：AccountStore（会话恢复/资料/登出）、扫码与密码登录。
    NowPlaying/   NowPlayingStore：当前视频页的唯一所有者（见下）。
  Resources/
```

## 关键数据流

### 1. 打开一个视频

```
卡片点击 → NowPlayingStore.open(route)
  ├─ VideoDetailViewModel.load()            详情（经 VideoPreparationCache 去重）
  ├─ VideoPreparationCache.prefetch 已把     播放地址（卡片露面时已预取）
  │   playURL 缓存好 → PlayerViewModel.load()
  └─ 详情回来后 → loadExtras()（标签/互动关系/名片并行）+ 评论模型
```

- **NowPlayingStore**（`Features/NowPlaying/`，挂在 RootView 环境上）拥有视频页的全部
  状态：route、播放器、详情/评论模型、分 P、滚动位置、返回历史。相关视频/合集是
  「就地换片 + 历史栈」；`close()` 负责停播放器并取消全部加载任务。
- **PlayerViewModel** 只管播放本身：加载、画质切换（不换 session 就地重开）、备用
  地址逐个尝试（`PlaybackSource.candidates`）、心跳上报、定时休眠。内核事件经
  `engineID` 过滤，旧内核的迟到事件不会污染新会话。

### 2. 列表与内容过滤

竖屏/最低时长过滤的入口是根视图注入的环境值 `hidesPortraitVideos` +
`VideoDurationFilterSettings.shared`。列表通过
`.resolvePortraitVideos(videos, batchID:)`（`Core/UI/VideoVisibilityEnvironment.swift`）
统一处理：

1. 对整批视频算 `metadataRequest`（列表已知的直接用；缺的查
   `PortraitVideoStore`，还没有的经 `VideoPreparationCache.detail` 补查，同 bvid 全
   App 合并，最多 50 并发，成功缓存 7 天、失败冷却 5 分钟）；
2. 全部判断/补位（最多 8 页）结束后才发布统一的入场动画起点
   （`VideoEntranceClock`），屏幕外卡片共用同一批起点；
3. 关闭过滤或全部已知时零请求。

各数据源到「画幅/时长」的适配都在 `Core/Models/VideoDimensionProviders.swift`：
新增一种列表模型时，在这里加两个 extension 即可接入过滤。

### 3. 网络层约定

- 主要业务请求走 `APIClient`（图片、登录等还存在独立请求路径）：手写 Cookie 头（关共享 Cookie 罐）、
  UA/Referer、`{code,message,data}` 信封。WBI 签名由 `WBISigner` 提供（密钥按自然日
  持久化，并发签名合并为一次 nav 请求）。
- 风控（v_voucher）在取流和搜索两个口子上有专门处理：换格式重试 / 报「被风控拦截」。
- 写操作不回读：接口成功即认为本地乐观值正确（服务端写入有延迟，回读会闪回旧值）。
- 取消语义：结构化任务与独立共享任务要分别处理。`PortraitVideoStore` 按等待者登记取消：
  排队且无人等待的请求移除；仍有人等待的请求保留；已开始的请求继续完成并缓存。
  页面取消可以立即退出等待，不必等待共享下载结束。
  错误处理使用 `Error.isCancellation`；分页/刷新用请求代号（UUID）防止旧响应覆盖新状态。

### 4. 账号与会话

`AccountStore` 区分「有凭据未验证」（`isLoggedIn` 先行，缓存资料兜底）与「已确认登
录」，网络恢复/回前台/手动入口都能重试 `refreshProfile`；明确失效（-101 /
`isLogin==false`）才清凭据。会话换代（登录/登出）时 `sessionID` 更新：视频页关闭、
关注页重建、`VideoLikeStore` 差量清空、旧请求的回包按 sessionID 丢弃。

## 状态与任务所有权

| 状态 | 所有者 | 生命周期 |
| --- | --- | --- |
| 三 Tab、全局环境 | `RootView` | 进程 |
| 视频页全部状态 | `NowPlayingStore`（RootView 持有） | 从 `open` 到 `close` |
| 播放内核 | `PlayerViewModel` → `MPVPlayerSession` → `MPVEngine` | 视频页/换片 |
| 详情/评论 | `VideoDetailViewModel` / `CommentsViewModel` | 视频页 |
| 关注流/UP 主动态 | `DynamicFeedModel`（各持一份，翻页点赞共用） | 页面可见 + 账号会话 |
| 点赞差量 | `VideoLikeStore.shared`（会话版本号） | 登录会话 |
| 画幅/时长补查缓存 | `PortraitVideoStore.shared`（MainActor，7 天持久化） | 进程 + 磁盘 |
| 播放地址/详情预取 | `VideoPreparationCache.shared`（actor，5 分钟，预取并发 2） | 进程 |
| 图片内存缓存 | `BiliImageCache.shared`（actor，300 张 LRU 逐出，在途合并） | 进程 |

网络任务一律由 **ViewModel 或全局缓存** 持有（`HomeViewModel.activeLoadTask`、
`DynamicFeedModel.reloadTask`、`NowPlayingStore.loadTasks` 等），不依附单个卡片视图；
视图的 `.task` 只做触发。取消来自两层：视图生命周期（SwiftUI 自动）和
「新请求替换旧请求」（显式 `cancel()` + 代号校验）。

## 新功能放哪里

- **新列表页**：模型（宽松解码）→ `Core/Models`；适配过滤 →
  `VideoDimensionProviders`；页面用 `VideoListCard`/`FeedDropInRow` +
  `.resolvePortraitVideos`，翻页失败给「重试加载」，不要把网络失败当成到底。
- **新接口**：endpoint 加进 `BiliAPI`；需要 WBI 就 `requiresWBI: true`；来源校验严的
  接口带对应的 Origin/Referer（参考 `DynamicRequest.headers`、`SearchRequest`）。
- **新设置项**：存储键与 clamp 放 `Core`（像 `HomeRefreshSettings`），设置页一行
  `@AppStorage`，跨页生效的走根视图环境值。
- **新动效参数**：集中在 `FeedRefreshTuning` / `CardRemovalAnimation` / 各
  `*Layout` 枚举，不要散在调用点。
- **新的环境动作回调**（列表行要触发弹层）：用 `EnvironmentAction` 盒子 +
  `@State` 持有，宿主在 body 里 `setHandler`——不要往 `@Entry` 里塞裸闭包。

## 离线测试（不需要 Simulator/真机）

`offline-harness/run.sh`：把纯逻辑模块（画幅/时长过滤、PortraitVideoStore、
动态解码、首页行分组、EnvironmentAction、WBI 缓存）复制到临时目录，用 swiftc 编译成
macOS 可执行文件直接断言运行。每次运行都取仓库当前源码，副本不漂移；新增纯逻辑回归
就往 `offline-harness/src/Tests.swift` 里加用例。依赖 UI/UIKit 的测试在
`NeoBiliTests/`（需要设备运行）。


## 审查与验证边界

- 环境动作盒子只保证身份稳定，不保证所有子视图都不再更新。闭包必须显式捕获需要的
  Binding 或独立数据，禁止捕获拥有动作盒子的宿主整体，以免形成循环引用。
- `PageOffsetBox` 只消除滚动位置字典造成的状态失效；`headerCollapse` 等状态仍会变化。
  首页、空间页、评论区的实际 body 更新次数及帧率，需要运行时测量，不能由 diff 推算成实测值。
- 离线测试覆盖请求去重、50 并发、缓存、排队取消、共享等待者和在途完成语义；
  独立的 `EnvironmentActionLifetime.swift` 在 macOS 上检查相同 Binding 捕获结构的 ARC 释放，
  不启动界面。这不替代真实 SwiftUI 页面生命周期与性能验证。
- 夜间改动的基线提交是 `30c70b5`，`9.8-Night` 是提交消息，不是 Git 引用。
  `git diff 30c70b5` 只包含已跟踪文件；审阅还应结合 `git status --short` 查看未跟踪文件。
  回退前应保存当前工作，并逐项确认范围，不使用全目录清理命令代替审阅。
