# 评论、标题、小窗转场及直播优化验收

设备：iPhone 17，UDID 00008150-001059D21A03C01C。仅物理设备，无 Simulator。

## 界面与交互

- 评论玻璃胶囊标准字号可见高度约 26 pt，文字固有宽度 + 水平内边距；外部独立保留至少 44 pt 点击范围。点赞数与回复不再套系统 glass button 额外的最小高度。
- 标题完整显示；简介箭头不再撑高单行标题，箭头对齐首行且单独保留点击范围。
- 标题、按钮图片为物理设备渲染的生产组件，使用本地静态样例，不代表网络评论操作测试。
- 卡片进入转场保留原入口，viewDidAppear 后将原生 zoom 退出目标更新为实际停靠小窗。渲染层在 fullScreenCover onDismiss 后交接。
- `native-dismissal.png` 是真实原生 zoom 的中间帧（彩色静态视图用于分离几何）；测试断言缩小时的实际像素位置接近下方小窗，而非顶部卡片，不是只断言 sourceID。

## 第一轮回归

`/tmp/NeoBiliMiniLiveRefinement-20260910.xcresult`：59 项通过，0 失败。包含评论间距、表情间距、明暗外观、单行/多行标题、直播播放器 20 项、小窗 store/运动/渲染层、滚动展开。

## 联网与原生转场

`/tmp/NeoBiliMiniLiveSmoke-20260910.xcresult`：43 项中 42 项通过、1 项失败。

- Live API 14、feed 6、player 20、原生转场 1、真实直播播放 1 通过。
- 真实直播间 6 解析为 7734200；主机显示至解码首帧 1.1228 秒，100 ms 采样，一次 FLV 地址连接。画幅 16:9，画质 10000，4 档可选，暂停/继续播放通过。这里只是单次网络测量，没有同网络 A/B 基线，不据此声称稳定提升百分比。
- 正常手机账号同时存在网页会话与 App 凭据；推荐返回 20 个房间、关注返回 2 个直播房间、分区目录返回 12 项。
- **失败仍保留**：一级分区 parent=2、area=0 首次请求返回 -352。随即停止后续分区请求。WBI 与保留正常 Cookie 没有解除此次服务端拦截，不能将此项写为已通过。

## 官方分区网页回退

`/tmp/NeoBiliOfficialAreaRouting-20260910.xcresult`：6 项通过、0 失败，含路由/Cookie 4 项、6 种原生列表状态视觉检查、官方网页呈现与实际 WebKit 导航承接。

- 使用普通会话、原生 WKWebView，无自定义 UA/注入脚本；网页数据存储为非持久。
- `official-area-page.png` 已人工查看：英雄联盟分区明确显示多行真实房间卡片。测试代码谨慎保留 `roomListingVerified=false`，因为没有读取 DOM 或把 didFinish 当数据成功；此处的列表显示结论来自截图观察。
- 程序调用 WKWebView.load 官方房间 6，生产 WKNavigationDelegate 在请求发出前将其交给原生打开回调；断言通过。不是模拟用户点击，不代表所有分区/所有验证状态都可用。
- 首次网页检查暴露 SDK completion handler 的 actor 签名不匹配，已修正并添加实际 ObjC selector 响应断言；最终构建没有该 nearly-matches 警告。

## 最终安装

Release 构建 `/tmp/neobili-mini-live-install-release.log` 成功，分区 WebKit 可选代理签名警告已消失。安装 `/tmp/neobili-mini-live-final-install.json` 成功，bundle `com.elsterlee.NeoBili`，安装序号 5364；随后 `/tmp/neobili-mini-live-final-launch.json` 启动成功。

README 已同步小窗转场、评论胶囊、直播启动及官方分区入口。原生分区 API 的 -352 仍是明确限制，未改写失败结果。
