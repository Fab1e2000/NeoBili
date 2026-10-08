# 索引

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 索引

<!-- 口径：本索引表的数据行数必须与下方 `### ` 条目数严格相等（当前 56 = 56）。
     文末「表 ①」的 U-01…U-17 是另一张表的行，**不计入索引**；统计时不要按“形如 ID 的行”全文件计数，
     否则会把 17 行 U 项算进来得出 68/73 的错误分母（team-c30 曾据此误报 1:1 不成立）。 -->
| ID | 端点/服务方法 | 主文档章节 |
| --- | --- | --- |
| FEED-01 | `app.bilibili.com/x/v2/feed/index` | [首页请求的业务组装](../protocols/home-feed.md#首页请求的业务组装) |
| FEED-02 | `app.bilibili.com/x/v2/feed/index/interest` | [推荐点击、展示与可见时长](../protocols/home-feed.md#推荐点击展示与可见时长的业务触发) |
| FEED-03 | `app.bilibili.com/x/v2/feed/second/interest` | 同上 |
| FEED-04 | `app.bilibili.com/x/v2/feed/index/story` | [功能、设置与首页请求参数](../protocols/settings-parameters.md#功能设置与首页请求参数) |
| FEED-05 | `app.bilibili.com/x/feed/dislike`、`/x/feed/dislike/cancel` | [不感兴趣的本地操作与请求](../protocols/home-feed.md#不感兴趣的本地操作与请求) |
| FEED-06 | 官方事件 `[from_spmid_v2].main-card.0.click` + 旧链 `001365`（NeoBili 侧现用 `tm.recommend.main-card.0.click`/`001538`，是自身取值，不是官方标识） | [推荐点击、展示与可见时长](../protocols/home-feed.md#推荐点击展示与可见时长的业务触发) |
| FEED-07 | Neuron `tm.recommend.feed-card.0.show` / `tm.recommend.feed-card.duration.show` | 同上 |
| FEED-08 | Neuron 兴趣选择 show/click/submit（`interest.*`） | 同上 |
| DEV-01 | `+[BFCBuvid buvid]` 本地生成与存储链（非 HTTP） | [传统 HTTP 参数与请求构造](../protocols/http-requests.md#传统-http-参数与请求构造) |
| DEV-02 | `POST https://app.bilibili.com/x/resource/fingerprint`（Ktor，54 项指纹 payload） | [设备登记与访客生命周期](../protocols/device-registration.md#设备登记与访客生命周期) |
| DEV-03 | `POST https://passport.bilibili.com/x/passport-user/guest/reg`（`+[BFCAccountGuest loadGuestIdWithCompletionBlock:]`） | 同上 |
| DEV-08 | 设备资料三字段 `isVpn`/`ip`/`userAgent` 在所选 generateInfo 中未赋值（不推广全程序；GPB presence/wire 另核） | 同上 |
| DEV-09 | `GET https://passport.bilibili.com/x/passport-login/web/key`（访客 RSA 公钥+hash 取回，`+[BFCAccountGolangApi requestPublicKeyWithCompletionBlock:]` 0x116047568） | 同上 |
| DEV-04 | 账号刷新 `x/passport-login/oauth2/refresh_token` + `x/passport-login/confirm/refresh` | [账号校验、刷新、注册与退出](../protocols/device-registration.md#账号校验刷新注册与退出) |
| DEV-05 | 新用户注册 + `x/passport-login/oauth2/access_token` 换 token | 同上 |
| DEV-06 | 退出/撤销 单条与批量 revoke | 同上 |
| DEV-07 | 短信 UI `login_session_id` 本地派生（非 HTTP） | [短信 UI 的 login_session_id](../protocols/device-registration.md#短信-ui-的-login_session_id) |
| TICKET-01 | gRPC `grpc.biliapi.net` / `bilibili.api.ticket.v1` / `Ticket.GetTicket` | [ticket 拦截与更新入口](../protocols/tickets.md#ticket-拦截与更新入口) |
| TICKET-02 | HTTP 与 Moss 的 `x-bili-ticket` / `x-ticket-status` 拦截器 | 同上 |
| HB-01 | `api.bilibili.com/x/report/heartbeat/mobile` | [播放历史同步与播放器心跳](../protocols/watch-history.md#播放历史同步与播放器心跳) |
| HB-02 | `api.bilibili.com/x/v2/history/report`（`/x/v2/history/report_scene`） | 同上 |
| HB-03 | Atomic 应用心跳与 NetTracker（Neuron 事件，非独立端点） | [心跳上下文、会话与发送队列](../protocols/watch-history.md#心跳上下文会话与发送队列) |
| HB-04 | `api.bilibili.com/x/report/click/now`（公共时间辅助） | [公共服务端时间辅助请求](../protocols/http-options.md#公共服务端时间辅助请求) |
| LOG-01 | `dataflow.biliapi.com/log/pbmobile/unrealtime?ios`（realtime 为硬编码 CFString，无服务端下发） | [Neuron Protobuf 日志通道](../protocols/neuron.md#neuron-protobuf-日志通道) |
| LOG-02 | `data.bilibili.com/log/mobile?ios`（旧 V2 文本通道） | [旧 V2 文本日志通道](../protocols/legacy-logs.md#旧-v2-文本日志通道) |
| PUSH-01 | `api.bilibili.com/x/push/report`（Center，12 字段） | [推送注册、权限状态与设备上报](../protocols/push.md#推送注册权限状态与设备上报) |
| PUSH-02 | `api.bilibili.com/x/push/report`（ActivityKit，7 字段） | [ActivityKit 两种 token 的独立上报](../protocols/push.md#activitykit-两种-token-的独立上报) |
| PUSH-03 | `/x/push/callback/click` | [通知点击、延后导航与 badge 回执](../protocols/push.md#通知点击延后导航与-badge-回执) |
| PUSH-04 | `/x/push/callback/badge` | 同上 |
| UP-01 | `member.bilibili.com/preupload`（UPOS Pre 阶段） | [日志附件 Laser：实际按钮、归档、上传与结果反馈](../protocols/advertising.md#日志附件laser实际按钮归档上传与结果反馈) |
| UP-02 | UPOS `https:%@/%@%@` Initial / Merge / SinglePart | [UPOS 各阶段配置、分片状态适配与取消通知](../protocols/advertising.md#upos-各阶段配置分片状态适配与取消通知) |
| UP-03 | Laser 反馈回执 `LaserApi`（主机未闭合） | [日志附件 Laser](../protocols/advertising.md#日志附件laser实际按钮归档上传与结果反馈) |
| PLAY-01 | gRPC `grpc.biliapi.net` PlayURLReq / PlayViewReq | [UGC 播放地址请求入口](../protocols/playback.md#ugc-播放地址请求入口) |
| PLAY-02 | 预加载播放能力参数（本地生成，随各业务请求下发） | [预加载播放能力参数](../protocols/preloading.md#预加载播放能力参数) |
| WL-01 | `x/v2/history/toview/add`、`/del`、`/x/v2/history/toview` | [稍后再看的旧 Phone 请求族](../protocols/watch-later.md#稍后再看的旧-phone-请求族) |
| WL-02 | `x/v2/history/toview/v2/list`、`/clear`、`/v2/dels` | [新版 WatchLater v2 列表、清空与删除 builders](../protocols/watch-later.md#新版-watchlater-v2-列表清空与删除-builders) |
| SEARCH-01 | `app.bilibili.com/x/v2/search` 与 gRPC `Search.SearchAll` | [搜索请求与查询会话](../protocols/search.md#搜索请求与查询会话) |
| CMT-01 | gRPC `/bilibili.main.community.reply.v1.Reply/MainList` | [评论列表 RPC、发布与互动](../protocols/comments.md#评论列表-rpc发布与互动) |
| CMT-02 | `x/v2/reply/add`、`/x/v2/reply/action`、`/x/v2/reply/top`、H5 举报 | 同上 |
| ACT-01 | `/x/v2/view/like/triple`、`/x/v2/view/like`、`/x/v2/view/coin/add`、PGC `like/triple` | [收藏业务参数的入口](../protocols/video-actions.md#收藏业务参数的入口) |
| FAV-01 | `/x/v3/fav/resource/deal`、`/x/v3/fav/resource/batch-deal` | 同上 |
| DYN-01 | Moss RPC `BAPIAppDynamicV2Dynamic`（DynAll / DynAllPersonal / DynVideo / dynDetails / dynVideoUpdOffset） | [动态综合页请求](../protocols/dynamics.md#动态综合页请求) |
| LIVE-INFO-01 | 直播 playInfo/roomInfo 双请求 + `/xlive/data-interface/v1/heartbeat/mobileEntry`、`mobileHeartBeat` | [直播播放信息与房间信息入口](../protocols/live.md#直播播放信息与房间信息入口) |
| AD-REPORT-01 | `/x/v2/dm/ad`、`cm/api/conversion/mobile/v2`、`cm/api/fees/wise`、MMA 宏 GET | [广告加载与归因的静态入口](../protocols/advertising.md#广告加载与归因的静态入口) |
| VIP-MAT-01 | `/x/vip/ads/materials`、`/x/vip/ads/material/report`、`/pgc/vipinfo/get`、`/x/vip/privilege/remind`、`/x/vip/v1/order/status` | [VIP HD 素材请求、响应模型、入口点击与首页回执](../protocols/advertising.md#vip-hd-素材请求响应模型入口点击与首页回执) |
| COMIC-01 | `manga.bilibili.com/twirp/column.v1.ColumnPay/GetComic` | [漫画/游戏/创作请求族入口](../protocols/advertising.md#漫画商城支付游戏创作请求族入口) |
| GAME-01 | H5 spm 注册表 `small_game_list_*` + BBTrack `001556` | 同上 |
| CREATIVE-01 | `member.bilibili.com/x2/creative/app/seasons` | 同上 |
| SDK-01 | App 间跳转（AlipaySDK/WXApi）+ CDN + `BFCWKWebViewV2` | [第三方 SDK、CDN 与网页容器的静态入口](../protocols/external-services.md#第三方-sdkcdn-与网页容器的静态入口) |
| IM-SYNC-01 | `ImInterface/SyncRelation`、`ImGatewayApi/GetTotalUnread`、`UpdateAck` | [IM 未读/同步的字段级链](../protocols/push.md#im-未读同步的字段级链task-18-补) |
| CRASH-01 | Laser 五端点 + BLog/UPOS + KSCrash 路径 | [Crash/KSCrash 提交路径与 Laser 回执端点](../protocols/crash-reporting.md#crashkscrash-提交路径与-laser-回执端点task-18-补) |
| SETTINGS-UP-01 | `PlayURL/PlayConfEdit` + `Distribution/SetUserPreference` | [设置配置同步、上传与缓存](../protocols/settings-sync.md#设置配置同步上传与缓存) |
| PGC-01 | `pgc/view/v2/app/season` + VIP/商城/支付请求族 | [漫画/商城/支付/游戏/创作请求族入口](../protocols/advertising.md#漫画商城支付游戏创作请求族入口) |
| DANMAKU-01 | `DM/DmSegMobile` + `/x/v2/dm/list/seg.so` | [弹幕请求族与传输分支](../protocols/playback.md#弹幕请求族与传输分支task-29-补) |
| DYN-02 | `bilibili.main.dynamic.feed.v1.Feed/CreateDyn` | [动态综合页请求](../protocols/dynamics.md#动态综合页请求) |
| CMT-03 | `/bilibili.main.community.reply.v1.Reply/ShareReplyMaterial` | [评论失败恢复与分享链](../protocols/comments.md#评论失败恢复与分享链task-29-补) |
