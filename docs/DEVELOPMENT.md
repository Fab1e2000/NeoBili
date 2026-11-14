# 开发与测试

## 分支与合并

- `develop` 用于日常开发和集成，普通功能、修复、文档和翻译 PR 的目标分支均为 `develop`。
- 外部贡献者从最新的 `develop` 创建自己的工作分支，完成相关改动后向 `develop` 提 PR。
- `main` 保留稳定发布版本；维护者准备发版时，确认相关测试与 CI 通过后，将 `develop`
  合入 `main`，再创建版本标签和发布产物。
- 紧急修复等需要直接向 `main` 提 PR 的情况，先与维护者确认；修复合入后同步回 `develop`。

提交问题和 PR 的说明要求见根目录 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 环境与入口

使用 Xcode 27.1 或更新版本（应用用到 iOS 27 SDK 的 API；部署目标仍是 iOS 26），安装 iOS Simulator runtime，并让 Command Line Tools
指向完整 Xcode。打开 `NeoBili.xcodeproj`，等待 Swift Package Manager 解析 MPVKit。
修改工程配置时编辑 `project.yml`，运行 `xcodegen generate` 并提交生成工程。

日常使用 `NeoBili` scheme：Run 为 Debug + LLDB，Test 为 Regression，Profile 为 Release。
选择 iPhone Simulator 后，`⌘R` 运行、`⌘U` 回归、`⌘I` 分析。模拟器不需要个人签名配置。

```sh
bash scripts/simulator.sh list
bash scripts/simulator.sh run
bash scripts/verify.sh quick
bash scripts/verify.sh targeted AccountSessionTests
bash scripts/verify.sh full
```

验证统一使用 `scripts/verify.sh`，底层离线与 Simulator 脚本继续可单独调用：

| 模式 | 执行内容 | 使用时机 |
| --- | --- | --- |
| `quick` | 源码依赖边界、本地文档链接、已暂存与未暂存差异格式、工作流脚本回归 | 开发中快速检查、每次推送；不编译 Swift、不启动 Simulator |
| `offline` | 宿主机离线回归（含源码边界与文档检查） | 纯逻辑修改后的验证 |
| `targeted TestClass[/testMethod] ...` | 指定 Simulator 测试，可传多个选择器 | 开发中验证受影响行为；必须指定测试 |
| `full` | `quick` 与完整确定性 Simulator 回归 | 跨模块改动、测试基础设施变更、发布前；PR 由 Xcode Cloud 执行同等检查 |
| `network` | 显式联网 Simulator 验收 | 需要验证真实接口时 |
| `performance` | 宿主机确定性性能检查 | 性能改动的相关验证 |

`full` 中某一步失败仍继续收集其余步骤的结果，任一步失败则整体失败。
业务回归统一由 Regression 计划执行；宿主机 `offline` 是按需定位工具，不在 `full` 或 CI 中重复编译。每次调用生成独立的
`DerivedData/Validation/*-verify-模式/`，包含环境、逐步日志和 `summary.tsv`；
Simulator 的环境、`.xcresult` 与测试数量摘要由底层脚本保存在另一个独立运行目录，路径见
验证入口的 Simulator 日志。联网、性能和真机专项使用独立入口。
底层日志中的跳过项仍需在交付时说明。

本地推送检查使用仓库中的 `.githooks/pre-push`，每个克隆启用一次：

```sh
git config --local core.hooksPath .githooks
```

启用后，每次 `git push` 只执行 `bash scripts/verify.sh quick`；任一步失败都会阻止推送，
日志保存在 `DerivedData/Validation/`。hook 不启动 Simulator，不重复任务完成阶段的完整回归。
检查使用当前工作区，推送前应先提交修改并检出要推送的版本；它不验证其他待推送 ref，
也不替代相关功能测试或 CI。本地完成受影响的 `targeted` 测试即可提交普通 PR，
完整回归交给 Xcode Cloud。跨模块重构、测试入口或计划变更、准备发布时，本地运行一次 `full`。
同一代码和环境下复用已通过的结果；后续只重跑受改动影响的检查。

脚本默认选择唯一可用的 `iPhone 18 Pro`。用 `NEOBILI_SIMULATOR_ID` 指定 UDID，或用
`NEOBILI_SIMULATOR_NAME` 与 `NEOBILI_SIMULATOR_RUNTIME`（例如 `iOS-27-0`）指定机型和系统。
找不到或存在多个匹配时停止，不猜测其他设备。`NEOBILI_DERIVED_DATA` 可覆盖编译缓存路径。

### Sanitizer 与严格并发检查

底层 Simulator 入口接受 `--` 后逐个传递的 xcodebuild 参数，仍使用同一设备选择、
Regression 数据隔离和 UDID 锁。参数不经过 shell 求值。诊断运行与普通回归分开记录：

```sh
NEOBILI_FAIL_RUNTIME_ISSUES=1 bash scripts/simulator.sh test -- -enableThreadSanitizer YES
NEOBILI_FAIL_RUNTIME_ISSUES=1 bash scripts/simulator.sh test -- -enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES
```

诊断命令将 Main Thread Checker 和 sanitizer 的运行时报告视为失败；XCTest 默认加载 Main Thread Checker。
不要同时开启 Thread Sanitizer 和 Address Sanitizer。额外参数记录在该次运行的
`environment.txt`，不要通过参数传入凭据。临时编译检查可传
`SWIFT_STRICT_CONCURRENCY=complete`。诊断采集阻塞时可显式设置
`NEOBILI_TEST_DIAGNOSTICS=never`，只跳过额外系统诊断，仍保留日志及结果包；默认值为 `on-failure`。Swift 6 本身已启用完整并发安全检查。

## 验证分层

| 层级 | 入口 | 数据与用途 |
| --- | --- | --- |
| 宿主机离线 | `bash scripts/verify.sh offline` | 生产纯逻辑、受控请求响应，无需启动模拟器 |
| 确定性回归 | `bash scripts/verify.sh full`（含快速检查） / `⌘U`（仅 Simulator） | 隔离存储、假身份、注入数据；包括 UIKit/SwiftUI 窗口测试 |
| 联网验收 | `bash scripts/verify.sh network` / `NeoBili-Network` scheme | 显式开启推荐接口与直播弹幕检查，可在 Simulator 运行 |
| 真机专项 | `NeoBili-Device` scheme | 显式开启直播播放和授权 4K 解码验收 |

`Config/*.xctestplan` 是测试选择的共同来源。默认回归排除联网与硬件专项，不把它们计为已通过。
Regression 固定使用简体中文与中国区域，保证文案断言不受宿主机语言影响。
网络故障应报告失败，缺少账号权限可以说明原因后跳过；跳过不等于验收成功。
不要为修复环境问题扩大跳过列表。布局测试使用本地数据和前台窗口，不因玻璃外观就限定真机。

## 数据与前台隔离

Regression 安装为 `com.elsterlee.NeoBili.regression`，与日常应用共用模拟器、使用不同沙盒。
它不包含本地签名覆盖；账号使用内存 `CredentialStorage`，测试可注入独立身份和 UserDefaults。
应用测试宿主保留窗口但不加载业务根页面或预热真实接口。

App 持有的默认网络入口 `AppNetwork.session` 由 Data 工厂创建，在 Regression 中拦截请求并返回离线错误，不带 Cookie
或磁盘缓存；测试需要响应时注入专用 session 或 loader。原生 mpv 加载与直播 WebSocket
在此配置下禁用，播放器状态机使用注入会话验证。新增网络通道必须遵守同样的隔离边界。

联网/真机方案使用 Debug 和正常应用数据，可能读取已登录账号，必须显式选择；不能混入默认回归。
账号单元测试必须创建独立内存凭据，禁止写入生产 Keychain 后再“恢复”。

自动界面测试独占前台，期间不要手动操作或在另一个任务运行同一模拟器。
脚本以模拟器 UDID 加锁；直接从 Xcode 运行时由操作者协调。残留锁报错会给出位置，
核实记录的 PID 已退出后才移除。不要抹掉整个模拟器、卸载日常应用或清除正常账号来让测试通过。

## 结构与文档检查

`quick`、`full` 和云端编译前检查均验证源码依赖边界与本地文档链接。也可以单独执行：

```sh
python3 scripts/check-architecture.py
python3 scripts/check-doc-links.py
```

`NeoBiliDomain`、`NeoBiliCore` 和 `NeoBiliData` 是独立静态框架，Debug / Regression / Release 与 App 使用相同配置；Regression 的隔离编译条件也传入模块。测试可以 `@testable import NeoBiliDomain` / `NeoBiliCore` / `NeoBiliData`，离线 harness 则直接编译所需源码。

边界检查禁止页面/业务模型引用网络实现，也禁止网络层引用页面状态。Domain / Core / Data 分别编译；脚本同时检查模块导入方向、禁止 UI 层直接使用传输，以及尚在 App target 内的目录边界。源码检查不代替行为测试。文档检查验证本地目标文件存在，不联网检查外部站点。

## 修改后的检查

- 文档和脚本修改运行 `quick`；功能修改运行受影响的 `targeted` 回归。纯逻辑定位可按需用
  `offline`。跨模块、测试基础设施与发布前运行 `full`；普通 PR 的完整回归由 CI 负责。
- 界面修改：验证受影响操作和实际布局断言，用代表性的深浅色、字号和方向组合覆盖不同
  布局分支。截图用于明确要求的视觉验收或失败诊断，不为同一行为展开所有组合。
- 性能修改：用可复现内容及相同配置比较耗时、内存、滚动或播放器生命周期；记录工具链、
  系统、机型、配置、场景及指标。宿主机确定性性能检查入口为 `bash scripts/verify.sh performance`；
  上报身份缓存、事件序号迁移与凭据读取次数可单独运行 `zsh offline-harness/behavior-performance.sh`，
  使用隔离偏好域和内存凭据，不访问真实账号。宿主性能入口同时检查位图 LRU 的确定性
  随机操作及日期格式化的语言/时区并发隔离，并输出日期列表格式化前后对照；这些是热点
  操作的成本，不替代相同页面内容的帧率、内存或真机功耗验收。
- Simulator 分析可使用 Instruments Time Profiler、Allocations 等；结果用于定位和回归。
  手机功耗、热状态、硬件解码和实际后台行为必须单独实机验证，不从模拟器数值推断。

脚本把日志、环境信息、`.xcresult` 和摘要写入 `DerivedData/Validation/` 的独立运行目录。
交付说明必须区分失败、跳过、未执行及通过；未跑专项时不宣称专项通过。不要将运行流水写回规范文档。

### 测试维护

每个回归用例对应一个可观察的失败：请求或状态错误、数据丢失、交互失效、布局遮挡等。
新增前先查现有用例，优先补充断言或输入样例；相同业务规则在一处维护。
删除已被覆盖的重复测试、只检查测试夹具自身状态的断言，以及只生成截图却不判断产品行为的测试。
截图、性能实验和联网验收按任务需要执行；计时实验应有比较目标，不放进默认功能回归。

## 官方推荐请求对比

先录官方 App 的操作样本，按操作分别保存 `.flows`；原始抓包包含凭据，留在仓库外。
分组边界必须由实际手机操作确认，不能仅按 flush 或时间给旧样本补标签。
建议最少四组，固定同一账号，其余条件每次只改一项：

1. `cold`：彻底关闭官方 App 后打开首页，记录首次请求；随后下拉两次并翻两页，分别保存为 `pull`、`page`。
2. `watch_return`：打开一条视频，真实播放约 20 秒后返回首页再下拉；与直接返回/下拉比较。
3. `settings`：切换首页自动播放/静音/弹幕设置（以官方实际提供为准），每次切换后下拉；记录每个设置值，随后恢复。
4. `warm_network`：后台/前台一次并下拉；再切换 Wi-Fi/蜂窝并下拉。分别标记 warm、wifi、cellular。

不要求退出正常账号。`login_event` 的登录生命周期、广告与 ticket 过期可能仍无法在这四组中
确认；需要发生对应真实事件再补样本，不把缺失证据当成常量。地区头需要跨网络对比及字段格式
研究，屏幕尺寸/方向可补横竖屏样本。抓包用于校验已实现的真实观看上报；新增协议以明确用户授权为前提。验证时区分累计观看
时间和播放位置、播放 session 和 App 请求头会话；不得复制官方 token、ticket 或会话。设备编号默认使用自身编号；经设备所有者明确授权的本地 Debug 对照实验可通过启动环境注入官方编号，保存在独立实验设置中，可恢复自身编号，禁止硬编码或进入分发构建。
移动心跳成功仅代表接口接受，兴趣是否更新必须用真实播放后刷新进行验收。

设备编号可在“设置 → 高级 → 设备编号”填写并保存自己的 BUVID，重启后生效；留空则使用首次生成后保存的随机编号。普通构建不再提供系统派生/随机模式选择。自定义编号按 BUVID 隔离访客登记、fingerprint 和 ticket，登录凭据继续复用；清空后恢复原随机编号及其缓存。既有系统编号保留但不作为普通应用默认身份。私人官方编号不写入源码或分发包。
Regression 不自动启用实验，测试通过注入策略使用隔离存储。不要将实验宏加入正式 Release workflow。

```sh
python3 scripts/analyze-feed-capture.py --group cold=/private/cold.flows \
  --group pull=/private/pull.flows --group page=/private/page.flows \
  --output DerivedData/Validation/feed-differences.json
python3 -m unittest discover -s offline-harness/src -p 'test_feed_capture.py'
```

工具需要现有 `mitmdump`，只重放 `/x/v2/feed/index`，不联网请求。输出协议白名单字段，
账号、设备、票据、广告及未知字段只输出本次分析内的相同/不同编号和长度；不会输出 token、
Cookie 或原始值的持久化哈希。原始重放错误输出不转发。相同编号不能跨分析运行比较。
按操作看差异后，再区分固定版本配置、设置状态、账号设备、会话、网络及服务端动态值。
样本不变只是观察结果；只有明确协议/功能证据支持的固定配置才写死。

## 本机协议校验

研究契约的检查范围与边界见 [推荐实现核查](research/implementation/validation.md#本机校验范围与入口)。
`zsh offline-harness/protocol-check.sh` 使用当前生产编码器跑独立签名样本及首页操作参数检查。
显式加 `--network` 才执行少量真实 GET；可用 `NEOBILI_PROBE_CONTEXT` 指向仓库外的私有上下文JSON。
无上下文时只验证公共公钥和时间接口，个性化推荐标为未执行。不要将真实上下文加入源码或终端输出。

## CI

Xcode Cloud 使用 GitHub 仓库中的共享工程与 scheme，不在云端重新运行 XcodeGen。
工作流由 Xcode 的 Report navigator → Cloud 或 App Store Connect 管理，
仓库中的 `ci_scripts` 提供共同检查和发布动作。工作流名称固定为 `Build`、`Release`。

| 工作流 | 环境与动作 | 结果 |
| --- | --- | --- |
| `Build` | Xcode 27.2；`NeoBili` scheme；Test 动作，指定 `Regression` 计划；iPhone 18 Pro / iOS 27.2 | 快速检查和完整确定性模拟器回归 |
| `Release` | Xcode 27.2；`NeoBili-Release` scheme；Build 动作，Any iOS Device | ad-hoc 签名的侧载 IPA、SHA256SUMS.txt 与 GitHub Release 草稿 |

`Build` 的编译测试阶段先执行 `bash scripts/verify.sh quick`，检查源码边界、文档和工作流
脚本；随后由 Xcode Cloud 原生 Test 动作编译并运行 Regression。业务代码只编译这一轮。
测试运行阶段使用云端保存的测试产物。Regression 必须通过。
Build 只启用 Manual Start 的 Branch 与 Pull Request，自动启动由 GitHub 审批入口负责。
Build 不配置账号或发布凭据。
日志与 `.xcresult` 在 Xcode Cloud 的构建报告中下载；宿主检查输出在自定义脚本日志中。
本地按上面的改动范围选择验证入口，普通 PR 不要求再跑一次本机全量回归。

[GitHub Build](../.github/workflows/build.yml) 在 Ubuntu 上执行审批与结果回写，不进行 Xcode 编译。
仓库所有者从本仓库提交的 PR 使用 `ci-trusted`；其他 PR 和手动运行使用 `ci-approval`，
沿用该 Environment 的 required reviewers。审批后运行受信任目标分支上的
[调用脚本](../scripts/xcode_cloud.py)，启动对应 PR 的 Xcode Cloud Build，等待结果并写入
`Xcode Cloud / Build` 状态。脚本核对审批时的源提交和目标提交；提交变化时需重新运行。
GitHub 取消等待后，可在 Xcode Cloud 报告中取消仍在运行的构建。

GitHub Actions Secrets 配置 `ASC_ISSUER_ID`、`ASC_KEY_ID`、`ASC_PRIVATE_KEY`；
仓库变量 `CLOUD_BUILD_WORKFLOW_ID` 指向 Build 工作流。Apple 团队 API 密钥使用 Developer
权限，只供审批入口调用；不要传入云端 Build。PR 代码只在不含发布凭据的云端环境执行。

`Release` 使用 `v` 开头的 Tag Changes 和 Manual Start，关闭 Auto-cancel Builds。
只在该工作流的 Environment 中配置 secret `NEOBILI_RELEASE_TOKEN`：GitHub fine-grained
personal access token，仅选择 NeoBili 仓库并授予 Contents 的读写权限。不要配置成产品共享
变量，也不要放入 Build 工作流。令牌到期后在 Release 的环境设置中更新。

[发布脚本](../ci_scripts/release.py)在编译前检查版本、标签对应提交、说明文件和草稿状态。
构建失败时停止上传。成功后复制 App、恢复仓库中的构建号、移除描述文件并做 ad-hoc 签名，
将 IPA 和校验和上传到未公开的 GitHub 草稿。重跑只替换相同提交草稿中的同名附件；
已公开版本和其他提交的草稿保留原样，并报告失败。

手动构建保存为独立的 `cloud-build-N` 预览草稿，保持未公开。正式版本使用 `vX.Y.Z`
标签草稿。Xcode Cloud 自定义脚本生成的 IPA 从 GitHub 草稿下载，原生构建产物从云端报告下载。

## 真机与签名

日常回归默认使用 Simulator。用户已授权每次完成代码改动和相关验证后，使用 Apple Development
证书构建 Debug、安装到其已配对的 iPhone 并启动，无需重复确认；部署前说明本次更新内容。
设备未连接、锁定或存在多个候选时报告阻碍，不擅自卸载应用或清除数据。
真机专项测试仍需明确授权，手机的硬件播放、功耗、热状态及系统集成可作为专项理由。

授权后可选择 `NeoBili-Device` scheme 和指定手机执行专项。4K 需要账号具备相应权限，
不要把无权限跳过当作成功。普通 Debug 部署使用 `bash scripts/deploy-device.sh Debug`，
无参数也为 Debug；`Release --no-launch` 仅安装。多设备时指定 `NEOBILI_DEVICE`。

本地配置写入被忽略的 `signing/Local.xcconfig`，覆盖键为 `NEOBILI_BUNDLE_IDENTIFIER`、
`NEOBILI_DEVELOPMENT_TEAM`、`NEOBILI_CODE_SIGN_STYLE`、`NEOBILI_CODE_SIGN_IDENTITY`、
`NEOBILI_PROVISIONING_PROFILE`。覆盖使用 `[sdk=iphoneos*]`，避免改变正常模拟器的应用标识。
证书与描述文件留在本机，不把个人标识、迁移记录或凭据写入项目文档。

## 发布

1. 在待合并分支更新 `project.yml` 的版本和递增的构建号，运行 `xcodegen generate`，
   同时提交生成的 `Info.plist` 与工程变化；编写 `docs/releases/vX.Y.Z.md`。
2. 功能/修复 PR 经受影响的本机测试和 CI 验证后合入 `develop`，再通过发布 PR 合入 `main`。
3. 在通过 CI 的 `main` 提交创建并推送 `vX.Y.Z` 标签。Xcode Cloud 的 Release 工作流校验标签和
   `CFBundleShortVersionString` 一致，构建 IPA、做 ad-hoc 签名、生成校验和与 **Release 草稿**。
   安装包没有 Apple 开发者证书；ad-hoc 签名是为了让 SideStore、Sideloadly 能用用户自己的 Apple ID 重签。
4. 检查草稿的目标提交、版本说明及附件。发布草稿是独立动作，不能把创建草稿当作已发布。
5. 草稿公开后，[SideStore 工作流](../.github/workflows/sidestore.yml)读取该版本的 IPA 大小和
   `docs/releases/vX.Y.Z.md`，更新 `main` 与 `develop` 上的 `sidestore/apps.json`。
   用户添加的地址是 `https://n015.top/neobili/apps.json`。公开后，工作流把 IPA、图标和这份
   文件上传到 `n015.top`，手机不再从 GitHub 下载安装包。
   草稿附件不能公开下载，所以公开之前不要改这份文件。需要补写时，在 Actions 里手动运行
   SideStore source，并填入已公开的标签。

分发构建不携带个人签名文件、采集材料或账号上下文。手动运行 Release 生成独立预览草稿，
不创建公开版本，也不更新软件源。具体命令和行为以
[`ci_scripts/release.py`](../ci_scripts/release.py) 与
[`.github/workflows/sidestore.yml`](../.github/workflows/sidestore.yml) 为准。
