# 开发与测试

## 分支与合并

- `develop` 用于日常开发和集成，普通功能、修复、文档和翻译 PR 的目标分支均为 `develop`。
- 外部贡献者从最新的 `develop` 创建自己的工作分支，完成相关改动后向 `develop` 提 PR。
- `main` 保留稳定发布版本；维护者准备发版时，确认相关测试与 CI 通过后，将 `develop`
  合入 `main`，再创建版本标签和发布产物。
- 紧急修复等需要直接向 `main` 提 PR 的情况，先与维护者确认；修复合入后同步回 `develop`。

提交问题和 PR 的说明要求见根目录 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 环境与入口

使用 Xcode 26.2 或更新版本，安装 iOS Simulator runtime，并让 Command Line Tools
指向完整 Xcode。打开 `NeoBili.xcodeproj`，等待 Swift Package Manager 解析 MPVKit。
修改工程配置时编辑 `project.yml`，运行 `xcodegen generate` 并提交生成工程。

日常使用 `NeoBili` scheme：Run 为 Debug + LLDB，Test 为 Regression，Profile 为 Release。
选择 iPhone Simulator 后，`⌘R` 运行、`⌘U` 回归、`⌘I` 分析。模拟器不需要个人签名配置。

```sh
bash scripts/simulator.sh list
bash scripts/simulator.sh run
bash scripts/simulator.sh test
bash scripts/simulator.sh test AccountSessionTests
zsh offline-harness/run.sh
```

本地推送检查使用仓库中的 `.githooks/pre-push`，每个克隆启用一次：

```sh
git config --local core.hooksPath .githooks
```

启用后，每次 `git push` 依次执行离线检查和完整 Simulator 回归；任一步失败都会阻止推送，
日志保存在 `DerivedData/Validation/`。检查使用当前工作区、当前 Xcode 和下述模拟器选择，
推送前应先提交修改并检出要推送的版本。它不安装或切换工具链，也不替代 CI 的多版本验证。

脚本默认选择唯一可用的 `iPhone 18 Pro`。用 `NEOBILI_SIMULATOR_ID` 指定 UDID，或用
`NEOBILI_SIMULATOR_NAME` 与 `NEOBILI_SIMULATOR_RUNTIME`（例如 `iOS-27-0`）指定机型和系统。
找不到或存在多个匹配时停止，不猜测其他设备。`NEOBILI_DERIVED_DATA` 可覆盖编译缓存路径。

## 验证分层

| 层级 | 入口 | 数据与用途 |
| --- | --- | --- |
| 宿主机离线 | `zsh offline-harness/run.sh` | 生产纯逻辑、受控请求响应，无需启动模拟器 |
| 确定性回归 | `bash scripts/simulator.sh test` / `⌘U` | 隔离存储、假身份、注入数据；包括 UIKit/SwiftUI 窗口测试 |
| 联网验收 | `bash scripts/simulator.sh network` / `NeoBili-Network` scheme | 显式开启推荐接口与直播弹幕检查，可在 Simulator 运行 |
| 真机专项 | `NeoBili-Device` scheme | 显式开启直播播放和授权 4K 解码验收 |

`Config/*.xctestplan` 是测试选择的共同来源。默认回归排除联网与硬件专项，不把它们计为已通过。
Regression 固定使用简体中文与中国区域，保证文案断言不受宿主机语言影响。
网络故障应报告失败，缺少账号权限可以说明原因后跳过；跳过不等于验收成功。
不要为修复环境问题扩大跳过列表。布局测试使用本地数据和前台窗口，不因玻璃外观就限定真机。

## 数据与前台隔离

Regression 安装为 `com.elsterlee.NeoBili.regression`，与日常应用共用模拟器、使用不同沙盒。
它不包含本地签名覆盖；账号使用内存 `CredentialStorage`，测试可注入独立身份和 UserDefaults。
应用测试宿主保留窗口但不加载业务根页面或预热真实接口。

默认网络入口 `AppNetwork.session` 在 Regression 中拦截请求并返回离线错误，不带 Cookie
或磁盘缓存；测试需要响应时注入专用 session 或 loader。原生 mpv 加载与直播 WebSocket
在此配置下禁用，播放器状态机使用注入会话验证。新增网络通道必须遵守同样的隔离边界。

联网/真机方案使用 Debug 和正常应用数据，可能读取已登录账号，必须显式选择；不能混入默认回归。
账号单元测试必须创建独立内存凭据，禁止写入生产 Keychain 后再“恢复”。

自动界面测试独占前台，期间不要手动操作或在另一个任务运行同一模拟器。
脚本以模拟器 UDID 加锁；直接从 Xcode 运行时由操作者协调。残留锁报错会给出位置，
核实记录的 PID 已退出后才移除。不要抹掉整个模拟器、卸载日常应用或清除正常账号来让测试通过。

## 修改后的检查

- 逻辑或接口修改：运行相关离线/定向回归；阶段完成运行离线与完整模拟器回归。
- 界面修改：补受影响操作、布局截图、相关深浅色/字号/方向验证，确认前台窗口和显示缩放。
- 性能修改：用可复现内容及相同配置比较耗时、内存、滚动或播放器生命周期；记录工具链、
  系统、机型、配置、场景及指标。宿主机确定性性能检查入口为 `zsh offline-harness/performance.sh`；
  上报身份缓存、事件序号迁移与凭据读取次数可单独运行 `zsh offline-harness/behavior-performance.sh`，
  使用隔离偏好域和内存凭据，不访问真实账号。宿主性能入口同时检查位图 LRU 的确定性
  随机操作及日期格式化的语言/时区并发隔离，并输出日期列表格式化前后对照；这些是热点
  操作的成本，不替代相同页面内容的帧率、内存或真机功耗验收。
- Simulator 分析可使用 Instruments Time Profiler、Allocations 等；结果用于定位和回归。
  手机功耗、热状态、硬件解码和实际后台行为必须单独实机验证，不从模拟器数值推断。

脚本把日志、环境信息、`.xcresult` 和摘要写入 `DerivedData/Validation/` 的独立运行目录。
交付说明必须区分失败、跳过、未执行及通过；未跑专项时不宣称专项通过。不要将运行流水写回规范文档。

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

设备编号可在“设置 → 高级 → 设备编号”切换，重启后生效，普通构建默认沿用系统派生编号。
旧实验产物的 Swift 条件 `NEOBILI_RANDOM_BUVID_EXPERIMENT` 仅决定未设置偏好时的默认模式。实验版用随机 UUID 作为种子，保持 iPhone BUVID 格式；编号首次生成后保存并复用，
不携带预制编号、不覆盖原 `neobili.appBuvid`。实验的访客登记、fingerprint 和 ticket 使用独立存储，
账号登录凭据继续复用。切回系统派生模式恢复原编号与其登记缓存，之后仍按原有有效期和作用域校验。
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

研究契约的检查范围与边界见 [推荐实现核查](RECOMMENDATION_IMPLEMENTATION_REVIEW.md#本机校验范围与入口)。
`zsh offline-harness/protocol-check.sh` 使用当前生产编码器跑独立签名样本及首页操作参数检查。
显式加 `--network` 才执行少量真实 GET；可用 `NEOBILI_PROBE_CONTEXT` 指向仓库外的私有上下文JSON。
无上下文时只验证公共公钥和时间接口，个性化推荐标为未执行。不要将真实上下文加入源码或终端输出。

## CI

每次 PR 或手动运行 Build 在 Xcode 26.2、26.6 编译模拟器目标；26.6 单独执行离线与确定性模拟器回归。
CI 固定选择 iOS 26.5 runtime 的 iPhone，记录选中的设备；缺少工具链/runtime 时失败，
不自动改用其他版本。结果作为 Actions artifact 上传。CI 不配置真实账号或签名凭据。
工具链可用性以 [runner 官方清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
和任务中的预检为准。发布仍使用现有未签名 IPA 流程与版本说明。

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
2. 功能/修复 PR 经当前离线、Simulator 和 CI 验证后合入 `develop`，再通过发布 PR 合入 `main`。
3. 在通过 CI 的 `main` 提交创建并推送 `vX.Y.Z` 标签。Release workflow 校验标签和
   `CFBundleShortVersionString` 一致，构建未签名 IPA、校验和与 **Release 草稿**。
4. 检查草稿的目标提交、版本说明及附件。发布草稿是独立动作，不能把创建草稿当作已发布。

分发构建不携带个人签名文件、采集材料或账号上下文。手动运行 Release workflow 只产出
Actions artifact，不创建公开版本；具体命令和行为以 `.github/workflows/release.yml` 为准。
