<div align="center">

<img src="design/app-icon-2026/NMark-production.png" width="128" height="128" alt="NeoBili 图标">

# NeoBili

**为 iPhone 打造的第三方哔哩哔哩客户端**

SwiftUI 原生构建 · iOS 26 液态玻璃 · MPVKit 播放内核

[![Release](https://img.shields.io/github/v/release/Fab1e2000/NeoBili?style=flat-square&color=FB7AB3&label=release)](https://github.com/Fab1e2000/NeoBili/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Fab1e2000/NeoBili/total?style=flat-square&color=FB7AB3)](https://github.com/Fab1e2000/NeoBili/releases)
[![iOS 26+](https://img.shields.io/badge/iOS-26%2B-111111?style=flat-square&logo=apple&logoColor=white)](#安装)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://www.swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![License: MIT](https://img.shields.io/badge/license-MIT-8A8F98?style=flat-square)](LICENSE)

[English](README.md) · **简体中文**

[下载](#安装) · [功能](#功能亮点) · [从源码构建](#从源码构建) · [使用手册](docs/USAGE.md) · [更新日志](docs/releases)

</div>

<br>

## 应用截图

<table>
  <tr>
    <td align="center"><img src="docs/images/home.webp" width="200" alt="推荐页"><br><sub><b>推荐</b></sub></td>
    <td align="center"><img src="docs/images/following.webp" width="200" alt="关注页"><br><sub><b>关注</b></sub></td>
    <td align="center"><img src="docs/images/live.webp" width="200" alt="直播页"><br><sub><b>直播</b></sub></td>
    <td align="center"><img src="docs/images/video.webp" width="200" alt="视频页"><br><sub><b>视频与弹幕</b></sub></td>
  </tr>
</table>

> [!IMPORTANT]
> NeoBili 是个人开发的非官方第三方客户端，与哔哩哔哩（bilibili）无任何关联，仅供学习与交流，免费且不得用于商业用途。使用前请阅读 [免责声明](DISCLAIMER.zh-CN.md)。

## 功能亮点

### 发现

- **双列推荐流**：封面、时长、播放量一目了然；再点一次「推荐」回到顶部，已在顶部则刷新
- **搜索**：集成在底部标签栏，热搜一行一条
- **内容过滤**：可隐藏竖屏视频、过滤短于指定时长的视频，列表先过滤再显示，不会先出现再消失

### 关注与直播

- **横向头像条**：正在直播和刚有动态的 UP 主排在前面，轻点头像立即切换动态；「全部关注」一页看完所有关注
- **红点与 B 站同步**：点开有更新的 UP 主即清除红点，并按网页动态页的方式通知 B 站
- **LIVE 标记**：正在直播的 UP 主一眼可见，长按头像直接进直播间
- **独立直播页**：推荐与关注两个列表，支持清晰度切换、重新连接和分享；优先直连 FLV，保留 HLS 备用线路

### 观看

- **持续播放**：退出视频或直播后缩为底部缩略播放器，随标签栏一起收起，点一下标题就展开回来
- **发弹幕**：视频页和全屏播放器都能发，自己发的带绿色边框；支持彩色弹幕开关
- **原生玻璃控件**：全屏控件避开屏幕圆角与灵动岛，位置可调；分辨率、音质各有独立菜单
- **按画幅适配**：播放区跟随视频实际比例，竖屏视频上滑即可收起；按视频和分 P 记忆播放进度
- **手势**：亮度、全屏、音量三个竖向区域，分界可自定义，横向滑动调整进度

### 个性化

- **24 种主题色**：桌面图标同步切换
- **标题栏**：固定在顶部或随内容滚走，各主页面统一生效
- **标签栏**：调整顺序、隐藏标签、选择启动页，稍后再看、收藏、历史也能放进来
- **中文 / English 界面**：默认跟随系统语言，英文界面沿用 B 站说法（UP、Danmaku、Coin）
- **细节可调**：7 档文字大小、逐页开关卡片动画、下拉刷新距离、左缘防误触区域

更完整的行为说明见 [使用手册](docs/USAGE.md)。

## 运行环境

- iOS 26.0 或更高版本的 iPhone（暂不支持 iPad）
- 从源码构建：Xcode 26.2 或更高版本，Swift 6
- 安装到真机：可用于签名的 Apple ID 或开发者账号

## 安装

NeoBili 目前以**未签名 IPA** 的形式发布，需要用你自己的方式签名后安装。

1. 在 [Releases](https://github.com/Fab1e2000/NeoBili/releases/latest) 下载 `NeoBili-vX.Y.Z-unsigned.ipa`
2. 用同一页的 `SHA256SUMS.txt` 校验文件
   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```
3. 使用你自己的开发者证书或常用的签名工具签名，然后安装到设备

## 从源码构建

**环境**：Xcode 26.2 或更高版本。依赖通过 Swift Package Manager 自动解析，目前只有 [MPVKit](https://github.com/mpvkit/MPVKit)。

```sh
git clone https://github.com/Fab1e2000/NeoBili.git
cd NeoBili
open NeoBili.xcodeproj
```

1. 等待 Swift Package Manager 解析完 MPVKit
2. 在 **Signing & Capabilities** 中选择自己的开发团队，按需修改 Bundle Identifier
3. 选择 `NeoBili` scheme 和目标设备，构建运行

只编译真机目标、不签名：

```sh
xcodebuild -project NeoBili.xcodeproj -scheme NeoBili \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成，需要重新生成时运行 `xcodegen`。

## 项目结构

```text
.
├── NeoBili/
│   ├── App/              # 应用入口、根视图与标签栏设置
│   ├── Core/
│   │   ├── Models/       # 数据模型与设置项
│   │   ├── Networking/   # 接口客户端、请求签名与各业务接口
│   │   ├── Platform/     # 屏幕方向控制
│   │   ├── UI/           # 主题、玻璃控件与通用视图
│   │   └── …             # 诊断与扩展
│   ├── Features/         # 推荐、关注、直播、搜索、播放器、弹幕、
│   │                     # 视频详情、媒体库、我的、设置等功能
│   └── Resources/        # 24 个主题色图标、资源与多语言文本
├── NeoBiliTests/         # 单元测试
├── offline-harness/      # 可在 macOS 上直接运行的离线逻辑测试
├── design/               # App 图标设计源文件
├── scripts/              # 图标生成等脚本
└── docs/                 # 架构说明、使用手册与版本说明
```

- **架构**：目录职责、数据流与状态所有权见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **测试**：离线回归套件运行 `zsh offline-harness/run.sh`，无需设备或模拟器
- **图标**：白底立体挤出的 N 字图标，可编辑源文件在 [`design/app-icon-2026/`](design/app-icon-2026/)，由 `scripts/generate-app-icons.py` 生成全部 24 个主题色版本

## 文档

| 文档 | 内容 |
| --- | --- |
| [使用手册](docs/USAGE.md) | 播放、直播、关注、动画、手势等设置的详细行为 |
| [架构说明](docs/ARCHITECTURE.md) | 模块地图与新功能的落点 |
| [设置开发说明](docs/SETTINGS.md) | 设置键的兼容与接线 |
| [版本说明](docs/releases) | 每个版本的更新内容 |
| [第三方声明](THIRD_PARTY_NOTICES.md) | 依赖与参考项目的许可信息 |
| [免责声明](DISCLAIMER.zh-CN.md) | 与哔哩哔哩的关系、内容与数据、使用者责任 |

## 已知限制

- 哔哩哔哩没有公开或保证这些接口，服务端变更可能导致部分功能失效，需等待 NeoBili 更新
- 清晰度、音质和部分内容取决于账号、大会员、版权与地区
- NeoBili 不提供视频下载，也不以绕过付费、会员或地区限制为目标
- 仅发布未签名 IPA，没有 App Store 或 TestFlight 版本
- 目前只支持 iPhone

## 免责声明

- NeoBili 是个人独立开发的**非官方**第三方客户端，与哔哩哔哩没有任何隶属、合作或授权关系。「哔哩哔哩」「bilibili」及相关标识归其权利人所有。
- 本项目**不托管、不转载、不分发**任何内容；应用内的视频、直播、评论等均由设备直接向哔哩哔哩公开服务请求，版权归原作者所有。
- **不提供**视频下载、绕过付费或会员限制等功能；**不设服务器**，不收集用户数据，登录凭据只保存在本机钥匙串。
- 仅供个人学习与交流，免费提供，**不得用于商业用途**。使用者需自行遵守法律法规与《哔哩哔哩用户协议》，并自行承担使用风险。
- 权利人如认为本项目侵犯其权益，请通过 [Issues](https://github.com/Fab1e2000/NeoBili/issues) 联系，核实后会及时处理。

完整条款见 [DISCLAIMER.zh-CN.md](DISCLAIMER.zh-CN.md)。

## 许可证

本项目源代码以 [MIT 许可证](LICENSE) 发布。许可证只覆盖本项目自身的代码，不涉及哔哩哔哩的任何内容、商标或服务；第三方依赖以各自的许可证为准，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 致谢

- [youshen2/MeloX](https://github.com/youshen2/MeloX)：SwiftUI 原生、液态玻璃风格的第三方网易云音乐客户端，本 README 的结构参考
- [guozhigq/pilipala](https://github.com/guozhigq/pilipala)：PiliPlus 的前身，Flutter 编写的第三方哔哩哔哩客户端；NeoBili 的立体 N 字图标参考了它的 logo
- [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)：接口与播放行为的实现参考，锁定的参考版本见 [references/README.md](references/README.md)
- [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit)：基于 libmpv 的播放内核（使用 LGPL 构建）

以上项目的代码与资源仍分别受其原始许可证约束。
