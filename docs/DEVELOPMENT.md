# 开发与测试

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
  系统、机型、配置、场景及指标。宿主机确定性性能检查入口为 `zsh offline-harness/performance.sh`。
- Simulator 分析可使用 Instruments Time Profiler、Allocations 等；结果用于定位和回归。
  手机功耗、热状态、硬件解码和实际后台行为必须单独实机验证，不从模拟器数值推断。

脚本把日志、环境信息、`.xcresult` 和摘要写入 `DerivedData/Validation/` 的独立运行目录。
交付说明必须区分失败、跳过、未执行及通过；未跑专项时不宣称专项通过。不要将运行流水写回规范文档。

## CI

每次 push/PR 在 Xcode 26.2、26.6 编译模拟器目标；26.6 单独执行离线与确定性模拟器回归。
CI 固定选择 iOS 26.5 runtime 的 iPhone，记录选中的设备；缺少工具链/runtime 时失败，
不自动改用其他版本。结果作为 Actions artifact 上传。CI 不配置真实账号或签名凭据。
工具链可用性以 [runner 官方清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
和任务中的预检为准。发布仍使用现有未签名 IPA 流程与版本说明。

## 真机与签名

Agent 仅在用户当次明确要求后操作真机，且先说明具体需要验收的行为。
手机的硬件播放、功耗、热状态及系统集成可作为专项理由，日常回归不需要真机。

授权后可选择 `NeoBili-Device` scheme 和指定手机执行专项。4K 需要账号具备相应权限，
不要把无权限跳过当作成功。普通 Debug 部署使用 `bash scripts/deploy-device.sh Debug`，
无参数也为 Debug；`Release --no-launch` 仅安装。多设备时指定 `NEOBILI_DEVICE`。

本地配置写入被忽略的 `signing/Local.xcconfig`，覆盖键为 `NEOBILI_BUNDLE_IDENTIFIER`、
`NEOBILI_DEVELOPMENT_TEAM`、`NEOBILI_CODE_SIGN_STYLE`、`NEOBILI_CODE_SIGN_IDENTITY`、
`NEOBILI_PROVISIONING_PROFILE`。覆盖使用 `[sdk=iphoneos*]`，避免改变正常模拟器的应用标识。
证书与描述文件留在本机，不把个人标识、迁移记录或凭据写入项目文档。
