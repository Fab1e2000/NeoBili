# 官方推荐流采集记录

本文汇集官方 App 抓包、本地请求对照、NeoBili 代码及用户手机操作反馈。只记录观察到的现象、字段关联和当前实现，不给出推荐差异的根因判断。字段取值限于已有样本；相同账号、不同 App 版本、不同会话的记录分别说明。

全客户端静态网络研究与分模块覆盖深度见 [客户端网络协议研究](CLIENT_NETWORK_PROTOCOLS.md)。

完整字段清单和用户选定的发送策略见 [NOTSURE.md](../NOTSURE.md)。实现结构见 [架构](ARCHITECTURE.md)，采集与验证入口见 [开发与测试](DEVELOPMENT.md#官方推荐请求对比)。本文不包含手机号、验证码、账号凭据、真实设备编号、票据或安全验证 URL。

当前实现已采用已解码的首页视频卡点击事件通道，将移动心跳调整为真实播放开始/结束边界，
并拆分页面与播放会话。事件队列保留创建时的身份与会话快照。具体处理及尚未实现的字段见
NOTSURE.md 的“已落实的点击、观看与会话策略”；下文“当时未修改生产实现”等句子描述采样时
的状态，不表示当前代码仍未处理。本次没有新增推荐效果实验或官方曝光门槛结论。

## 采集对象与方式

- 官方中国版 iPhone App 的首页、设置、观看和请求样本。
- 官方国际版 iPhone App 的两次安装登录样本；用户设备管理分别显示“哔哩哔哩”和“bilibili”。国际版样本与此前中国版使用的 BUVID 不同，两次国际版样本之间相同。
- NeoBili 的首页、播放、登录及本地日志。
- iPhone 经 Mac HTTP 代理采集时，曾看到日志和广告请求，却没有首页推荐列表；当时手机首页正常更新。
- 数据线网络记录中出现未经过 HTTP 代理的连接。改用 WireGuard 采集后读到了首页推荐响应。
- Wi-Fi 手动代理未关闭时曾出现 NeoBili 搜索、历史等页面无法加载；用户关闭该代理后报告恢复。另一次开启采集后加载异常，经过连接处理后继续实验。

原始抓包留在仓库外。仓库中的分析脚本只输出白名单协议字段；账号、设备和未知内容以本次分析内的相同/不同标记及长度表示。

## 首页响应与手机展示

推荐入口为 `/x/v2/feed/index`，首页请求的参数放在 URL 查询串中。

首次读到的三批响应分别包含 11、9、10 张卡片。用户报告首页前四个位置为 Kimi 视频、广告、图文、“突发新闻”视频；对照的服务器响应前四个位置相同。

用户随后念出的以下内容均在已采集的服务器推荐响应中找到：

| 用户提供的标题或片段 | 采集记录 |
| --- | --- |
| “AI：我其实比论文作者更懂他写的这篇数学论文” | 推荐响应包含对应卡片 |
| “我为何强烈支持耿同学进行学术打假” | 推荐响应包含对应卡片 |
| “我的头舌超强”“美甲时的社恐日常” | 推荐响应包含匹配标题 |
| “我填报化学专业时的热爱都是脑子里进的水” | 推荐响应包含对应卡片 |
| “居然真有甲方要资助智能学派民间数学家做科研” | 推荐响应包含对应卡片；早期口头回复的批次编号前后不一致，本文不采用该编号 |
| “提醒，虽然小米……” | 推荐响应包含用户所指的小米与 AirPods 适配图文 |

上述记录包含用户说明的旧推荐。没有逐帧记录所有页面，也没有完整离线缓存与本地排序调用记录。

## 首页参数随操作的变化

| 操作或字段 | 官方样本中的值或关系 |
| --- | --- |
| 首批 / 手动下拉 / 翻页 | `flush=0/6/8`，`pull=1/1/0` |
| 双列 → 单列 → 双列 | `column=4/3/4`；布局切换请求 `flush=2`，随后手动刷新 `flush=6` |
| 冷启动 / 普通刷新 / 后台返回 | `open_event=cold/空/hot`；返回后标记可保留到随后手动请求 |
| `login_event` | 冷启动样本为 2，后续为 0 |
| 自动刷新开启 → 关闭 → 再开启 | `auto_refresh_state=1/4/3`；后续刷新和重启仍见 3 |
| 静音 → 有声 → 静音，每次按设置要求重启 | `inline_sound=1/3/1`，`inline_sound_cold_state=4/3/4` |
| 首页自动播放关闭 → 开启 → 关闭，不重启 | `autoplay_card=4/10/4`，同轮 `video_mode=1/1/1` |
| `inline_danmu` | 冷启动、声音和自动播放切换、刷新与翻页样本均为 2；未找到对应设置入口 |
| `banner_hash` | 本批首次冷启动为空，后续与此前服务器横幅响应的 hash 相同 |
| 开屏字段 | `splash_id/splash_ids` 在本批为空；`splash_creative_id` 偶尔出现并匹配开屏响应 |
| `ad_extra` | 同次启动保持，重启后变化；Base64 解码为二进制内容 |
| `widgets` | 混合操作的 12 条请求中有 1 条携带 |

同一 Wi-Fi、同一账号的混合操作批次包含刷新、翻页、观看、暂停、跳转、搜索和历史入口、布局切换、后台返回及重启，共 12 条推荐请求，业务码均为 0。该批次以下字段保持不变：

| 字段 | 样本值 |
| --- | --- |
| `client_attr`、`qn_policy`、`player_net`、`guidance`、`fourk` | 1 |
| `soft_fnval` | 2 |
| `teenagers_age` | 16 |
| `fnval` | 84948 |
| `qn` | 32 |
| `fnver`、`force_host`、`https_url_req`、`voice_balance`、`disable_rcmd`、`recsys_mode` | 0 |

其他已记录字段包括自身分页 `idx`、真实屏幕信息的 `player_extra_content`、语言参数、时间戳、签名及请求追踪号。请求头的 `x-bili-network-bin` 和地区标签在混合批次中发生过变化或携带状态变化。

## 请求身份、设备编号与本地对照

NeoBili 早期 App 请求使用 Android 身份；当前使用 `mobi_app=iphone`、`build=91300100`、`platform=ios` 及版本 9.13.0。国际版样本使用 `mobi_app=iphone_i`、`build=91300300`。国际版短信登录及授权兑换样本的 appkey 为 `0ac1706090f12cfc`；安全中心请求样本另有 `27eb53fc9058f8c3`。当前 NeoBili 登录和业务使用后一组 iOS appkey。

NeoBili 默认 App BUVID 由随机 UUID 的 MD5 摘要组成 `XY…` 格式，保存在本地；已有值直接复用。代码注释参考 PiliPlus 的 App BUVID 与网页 buvid3 分开保存做法。Debug 对照实验可通过本机设置覆盖成采集到的官方 BUVID，原始编号没有写入源码，Release 不读取该覆盖。重新登录没有重新生成 App BUVID。

在同账号基准请求上，以内存中的真实值替换选定字段，重新生成时间戳和签名，两轮采用相反顺序。记录的 30 次请求均 HTTP 200、业务码 0。标题关键词统计使用 ASMR、助眠、掏耳、采耳、哄睡：

| 对照操作 | 两轮统计结果 |
| --- | --- |
| Neo 原样基准 | 0、0 |
| 只替换 `access_key` | 0、0 |
| 同时替换令牌与票据 | 0、1 |
| 只增加 `x-bili-ticket` | 0、0 |
| 只替换 `buvid` | 2、2 |
| 统一 `flush=6/pull=1` 后，Neo 基准 / 只替换 BUVID | 基准 0、0；替换后 1、1 |
| 只替换 `guestid` | 0、0 |
| 只替换 `session_id` | 0、0 |
| 官方完整请求 / 改为 Neo BUVID | 官方基准 2、0；替换后 0、0 |

统计对象仅为标题关键词，不是完整内容分类；重复请求过程中时间、候选内容及服务器状态没有冻结。实验保留各自基准游标及其他状态。

测试版使用官方 BUVID 后，用户使用一段时间并报告“更接近官方了”。这是用户体验反馈，没有同一时间、同一候选池的逐条一致率测量。

## 观看、入口与相关推荐

| 已采集项目 | 记录 |
| --- | --- |
| 同一视频：首页 → 搜索 → 历史 | `from=7/3/64`；另有 3 个历史视频、6 条上报均为 64，业务码均为 0 |
| 相应 `from_spmid` | `tm.recommend.0.0` / `search.search-result.0.0` / `main.my-history.0.0` |
| 普通视频 `spmid` | 本轮三个入口均为 `united.player-video-detail.0.0` |
| `track_id/report_flow_data` | 本轮首页、搜索播放携带；历史播放为空或缺失 |
| 播放 `session/sessionID` | 每次重新进入同一视频换新编号，同次开始和退出一致；本轮两字段相等 |
| 手机连续观看 ASMR | 用户报告官方观看后，Neo 刷新变化不大，官方刷新变化较大 |
| 手机连续观看 Apple Watch | 用户在 NeoBili 观看后刷新，报告未看到相关内容 |
| 本地长程播放实验 | 刷新记录基线，随后真实连续播放园艺类视频并穿插互动，再刷新；后续响应中出现了该类标题 |
| 相关推荐接口 | 已采集 gRPC `bilibili.app.viewunite.v1.View/View`；解析样本包含 40 张普通相关视频卡片 |

当前实现将累计真实观看时间与播放位置分开；暂停、缓冲、拖动和续播不直接增加累计观看时间。有 App 凭据且 aid 已知时发送 `/x/report/heartbeat/mobile`，另用 `/x/v2/history/report` 同步历史；仅 Cookie 或 aid 尚未取得时保留网页历史同步通道。

相关推荐使用 `View` 与 `RelatesFeed`，保留响应卡片的追踪字段与分页游标。用户曾报告相关推荐不显示；代码检查发现请求使用了 VideoLikeStore 的本地点赞会话编号，而网络层检查 DeviceIdentity 登录会话。当前已分别绑定这两个会话。请求和解析的回归验证不代替手机界面验收。

#### 设备编号与相关模块的返回差异

本机受控请求使用 iPhone 协议身份 `91300100`，保持视频、来源、播放会话和客户端身份不变；账号凭据及设备值仅从仓库外读取，不在文档中记录。对照改变 gRPC metadata 的 BUVID 及对应 HTTP BUVID 头，观察 `ViewReply.tab` 内是否存在相关模块（Module 类型 28、字段 22），不把成功状态码等同于返回了相关卡片。

| 条件 | `View` 中观察到的相关卡片 |
| --- | --- |
| 原 IPA 保存的 BUVID，交替重复请求两次 | 两次均为 0，相关模块缺失 |
| 对照 BUVID，交替重复请求两次 | 两次均为 43，相关模块存在 |
| 原编号与对照编号，均移除账号认证和账号头 | 原编号为 0，对照编号为 43 |
| 四个按现有规则新生成的编号，未预先调用设备登记 | 均有相关模块，分别为 42、43、43、43 |
| 原编号只改末尾一个字符并保持格式合法 | 43 |
| 原编号改为小写（仅用于对照，不作为生成策略） | 43 |
| 原编号只把 Y 前缀改为 Z（仅用于对照） | 0 |
| 原编号省略请求中的 Relate，或将其 device_type 设为 1 | 均为 0 |
| 换第二个普通视频，分别用原编号与对照编号 | 原编号为 0，对照编号为 43 |

原 IPA 编号为符合本地生成规则的 36 字符编号，未发现残留旧 `XY` 格式或 Debug 覆盖。原编号直接请求 `RelatesFeed` 首批可返回 43 张卡片；它并非在所有相关接口中均取不到内容。相关请求的方法与字段定义可对照[公开 ViewUnite schema](https://github.com/bilibili-plugins/bilibili-api-collect/blob/master/grpc_api/bilibili/app/viewunite/v1/viewunite.proto)，该社区 schema 不能证明服务端当前的分组规则。

这些样本证明 BUVID 的取值能影响本次 `View` 是否附带相关模块，且差异在所测两个视频及登录/未登录状态下保持；“新编号必须先显式登记才有相关模块”与这四个新编号的结果不符。样本未证明原因是 A/B 分组、设备历史状态、风控或其他服务端规则，也没有证明它与首页兴趣更新采用同一套逻辑。不能据此判定签名证书优劣、账号被拒绝，或认定换编号能改善首页推荐。

实现适配响应差异：`View` 缺少相关模块时补取一次 App `RelatesFeed` 首批；明确存在空模块时不额外请求，不改写用户的设备编号。真实设备上的登记缓存位于 Keychain，本次读取偏好设置未取得其内容，因此未宣称完成登记状态的直接核验。


已观察到 `/x/report/click/ios` 和其他日志、曝光流量；click/ios 二进制用途仍未解清。基础曝光封装、卡片关联、时间单位及原始位置现已解码，生产尚未发送曝光事件；精细门槛和全部状态枚举仍未知。

### 首页手动观看与暂停样本

用户从首页进入《有一个宇宙里，所有人都在狗斗！》，依次播放、暂停、继续播放、返回和刷新。选中视频开始与结束的移动心跳返回业务码 0，结束 played_time/actual_played_time=53、paused_time=12、total_time=65，最后与最大播放位置为 52，历史 progress=52。初次与返回后的首页响应均为 flush=6/pull=1，各 9 张卡片。

首页卡片、该视频 View 请求和移动心跳的 track_id 相同；首页卡片与心跳的 report_flow_data 相同。心跳 session/sessionID 相等且在本次播放内不变；View 请求字段 6 则是另一个 32 字符值。请求头 session_id 是独立的 8 字符值。这批选中视频只记录到开始与结束移动心跳。

选中视频心跳的 from=7、auto_play=0、play_status=0；同批其他视频还出现 from=76、auto_play=2、play_status=1 的首页位置心跳。这些其他视频没有计入选中视频的时间统计。暂停附近出现 PlayPause，进出视频附近出现 ViewProgress 和 click/ios，完整消息含义尚未取得。

### 同一视频从历史重复进入

用户从历史记录两次打开同一条“狗斗”视频，播放后返回。两次 from=64、from_spmid=main.my-history.0.0，track_id/report_flow_data 没有有效值。每次 View 请求字段 6 都换新，移动心跳 session/sessionID 也换新；同次两个心跳的编号相同，但与 View 字段 6 不同。两次共四个 32 字符编号各不相同，App 请求头的 8 字符 session_id 保持不变。

两次结束的累计观看时间分别为 48、37 秒，播放位置及历史 progress 为 98、132 秒；暂停时间均为 0。两次均只抓到开始和结束移动心跳，业务码均为 0。play_type=1、play_mode=1、play_status=0、auto_play=0 在这两次手动播放中相同。

### 前台连续播放样本

用户从历史打开同一视频连续播放后返回。本批开始、结束移动心跳请求相隔约 168.3 秒，结束实际观看时间为 169 秒，暂停时间为 0；并非精确 180 秒样本。只抓到这两条移动心跳，均业务码 0。结束播放位置及历史 progress 为 298，累计观看时间与续播位置分开。另有一条 ViewProgress、一条 click/ios 和一条历史同步请求。

本次心跳 session/sessionID 全程相等且不变，View 请求字段 6 与心跳编号不同。此前首页暂停与历史重入样本也只见开始、结束移动心跳。NeoBili 当前累计 5 秒后首次、随后每 15 秒的发送策略与这些捕获记录不同；其他日志流量未据此归类为观看心跳。

### 暂停、后台与恢复样本

用户按播放、暂停、恢复、再次暂停后切桌面、返回 App、恢复及退出的顺序操作。本批实际记录约 209 秒。移动心跳只捕获到开始、退出两条；PlayPause 共三条，分别约在进入后 28.0、105.8、208.5 秒，最后一条临近退出。独立历史上报约在 109.1、209.6 秒，progress 分别 380、420；尚无逐动作时间标记将中途历史上报唯一归属于切后台。

退出心跳的 played_time/actual_played_time=126、paused_time=83、total_time=209，播放位置为 420；开始、退出的心跳 session/sessionID 相同，View 字段 6 与它们不同，App 请求头会话也保持不变。该批移动心跳与历史同步业务码均为 0，PlayPause HTTP 为 200。中途没有捕获额外移动心跳，暂停 RPC 的完整字段语义尚未取得。

## 设备资料、访客登记与票据样本

| 请求或字段 | 官方国际版样本记录 |
| --- | --- |
| BUVID | 最早捕获的请求已经携带，登录前后相同 |
| POST `/x/resource/fingerprint` | Content-Type 为 text/plain，JSON 正文含 `key/content`；业务码 0，返回 `data.bili_deviceId` |
| POST `/x/passport-user/guest/reg` | 包含 `device_info/dt/sdk_ver` 等；业务码 0，返回 `data.guest_id` |
| 登录表单 `device_id` | 等于此前响应的 `bili_deviceId` |
| 登录表单 `device_tourist_id` | 等于此前响应的 `guest_id` |
| 登录与兑换表单 `local_id` | 等于同次请求的 BUVID；正文 BUVID 与请求头相同 |
| `bili_local_id` | 64 字符十六进制值 |
| `login_session_id` | 32 字符十六进制值 |
| `device_info/device_meta/dt` | 前两者为十六进制内容，dt 可 Base64 解码为 128 字节 |
| gRPC `bilibili.api.ticket.v1.Ticket/GetTicket` | 响应字段 1 为 ticket，后续 x-bili-ticket 相同；字段 2 为创建时间，字段 3 为 ttl，样本为 28800 秒，grpc-status 为 0 |
| GetTicket 请求 | context 包含 x-fingerprint/x-exbadbasket，并见 key_id、32 字节 sign；该样本未携带 token |

当前未取得上述加密内容的完整生成规则。NeoBili 没有实现 App fingerprint、访客登记和 GetTicket 的申请/续期；生产不发送对应的 device_id、device_tourist_id、device_info/device_meta/dt、bili_local_id、guestid 和 x-bili-ticket。

## 短信登录与设备管理

官方样本包含短信直接成功分支，以及 `status=5` 后进入安全验证的分支。当前生产登录入口仅提供短信验证码；原扫码和密码协议代码仍在仓库内，但不作为生产登录入口。界面回归截图：[浅色竖屏](images/sms-login-light.png)、[深色横屏大字号](images/sms-login-accessibility-dark.png)，使用隔离测试数据。

| 环节 | 已观察的请求与返回 |
| --- | --- |
| 发送验证码 | POST `/x/passport-login/sms/send`；Neo 发送 `cid=1` 时业务码 86005“手机号格式错误”，当时号码为 11 位 ASCII 数字且无空白；改为 `cid=86` 后成功 |
| 提交验证码 | POST `/x/passport-login/login/sms`；成功响应含 token_info 和 cookie_info，或返回 status=5 与安全验证 URL |
| 安全验证页面 | `/h5/project-msg-auth/auth/entry`；URL 含 tmp_token/tmp_ticket/cid/tel/source，source 样本为 sms |
| 安全问答 | `/x/safecenter/answer/questions` 与 `/x/safecenter/answer/submit`；提交成功返回授权 code |
| App 授权兑换 | POST `/x/passport-login/oauth2/access_token`，grant_type 为 authorization_code |
| Neo 的一次失败 | 用户从设备管理踢掉此前中国版条目后重新登录；短信提交返回 status=5，问答成功，授权兑换返回 86033“appID不匹配” |
| 请求格式对照 | 上述失败时 Neo 安全页请求没有 App 身份及签名；官方安全中心样本有这些字段 |
| 修正后的手机反馈 | 为指定安全中心请求补同次 App 身份和签名并安装后，用户报告登录成功，设备管理新增“哔哩哔哩”条目 |

当前验证码发送与提交把地区列表的 country_id 转为电话区号，列表 id 只用于界面选择。短信发送、提交、安全验证及兑换共用本次登录的 BUVID 和会话，追踪号每次更新。写请求不自动重试；本地重发限制 60 秒，验证码本地有效期五分钟，服务器仍检查实际有效性。

安全页面采用隔离 WebKit 存储，桥接仅处理 passport HTTPS 主框架与指定 api.bilibili.com 安全中心路径，不自动回答问答。登录成功保存账号一致的 token 和 Cookie；旧 Cookie 会话保留，没有后台扫码换授权过程。

## 资料与工具

### 首页只浏览的日志样本

用户按首页刷新、停留、向下浏览、不点击视频的步骤操作。分组中捕获 19 条 pbmobile/realtime、9 条 pbmobile/unrealtime、2 条 log/mobile，以及 3 条 click/ios；实时日志正文包含 `tm.recommend.feed-card.0.show`、`tm.recommend.feed-card.duration.show`、`tm.recommend.inline.start-play.show` 三种完整事件名。事件参数、卡片对应关系、时长单位及封装尚未完整解码。其他日志中还见导航、登录及其他页面事件，存在缓存补发的可能；没有将这些事件全部归属于本批浏览，也没有根据 click/ios 的名称将其认定为卡片点击。本批未改生产代码。

### 首页卡片点击与曝光关联

用户指定“神人电台 217：都差球不多”，首页响应含完整标题“【纯净版】【熟肉】神人电台 217：都差球不多”。非实时日志中识别到 `tm.recommend.main-card.0.click`，实时日志中识别到 feed-card.0.show 和 feed-card.duration.show；三个事件局部 Protobuf 消息的字段 13 都包含与该首页卡片相同的 param 和 track_id，追踪值长 52 字符。点击记录 card_type 为 small_cover_v2，时长记录另含 13 位数字的 card_start_time/card_end_time。事件名字段为 1，扩展 key/value 字段为 13，另见字段 18 的 start_session_id/polaris_action_id。外层封装、全部基础字段、时长单位及发送/去重规则尚未完整解码；原始字符串中的事件名重复出现没有算作重复点击。本批未改生产代码，未从这些关联推断服务端推荐权重。

### 点击与曝光日志封装及时间关系

两批日志的原始 HTTP 正文为 gzip，解压后为 RecordIO 记录串，格式与 [Apache brpc 实现](https://github.com/apache/brpc/blob/master/src/butil/recordio.cc) 一致。34 个请求、383 条记录全部完成边界与长度 CRC 校验，重新编码与解压正文逐字节一致。每条记录的元数据含 appId/platform/eventId/logId/appVersionCode，正文为完整事件 Protobuf；eventId 与正文事件名相同，解释了原始字符串中同一事件名出现两次。点击批次 main-card 点击事件实际为一条。未联网重放这些上报。

本次采集为官方国际版：推荐请求 mobi_app=iphone_i、build=91300300、statistics appId=14/version=6.6.0；日志 appId=14/platform=1/appVersionCode=91300300。此版本配置与中国版分别记录。

目标卡片时长起止数字按 Unix 毫秒换算与上传时刻一致，差值 11593 对应 11.593 秒。展示与时长 event_policy=1，点击 event_policy=0；展示上传约在首页请求后 1.44 秒，时长约 13.62 秒，点击约 14.18 秒，View 请求约 12.50 秒。没有据此认定固定发送周期或 event_policy 的完整功能。可匹配的卡片中，88 组只浏览记录和 4 组点击批次记录的时长 position 均比展示 position 大 1。只浏览批次有 6 组相同 param/track_id 各有两条时长记录，两批相关事件正文没有完全相同的重发；去重触发条件仍未知。start_session_id 批次内不变，目标点击记录的该值与 HTTP session_id 不同。完整封装已解码，基础字段语义及调度规则尚未全部解清，未改生产实现。

### 卡片滑回样本的操作边界

用户指定“反差？如何融合在工业设计中？”，匹配响应标题“反差？如何融入在工业设计中？”。本文件中目标卡片仅有一次展示和一段 16.662 秒的展示时长，param/track_id 与响应相同，展示 position=3、时长 position=4。另包含不同视频“【IGN】Switch 2与PC版《巫师3：狂猎 — 重制版》画面对比”的点击事件，字段 5 时间在本分组开始后约 41.579 秒。九个日志请求、68 条记录完整校验通过。用户随后确认已滑回并完整显示同一卡片；未将缺少第二段时长认定为不重新计时，仍在显示的时段也可能尚未结算，待补离开视野操作。本批未改生产实现。

### 同一卡片再次离开视野后的时长结算

用户补做目标卡片显示后滑出的操作，没有刷新。分析引用前一分组的目标卡片编号及追踪值，在两个实时日志请求的 26 条完整校验记录中找到一条新增目标展示时长，param/track_id 相同，position=4，未见目标再次展示事件。统一两组时间后，第一段为 14.603 至 31.265 秒，第二段为 43.249 至 279.956 秒，两段间隔 11.984 秒；第二段长 236.707 秒，包含交流间隔，结束后约 0.375 秒上传。此例为同一卡片一次展示事件、两段独立展示时长；没有将它推及跨刷新/跨会话去重，也未确认可见门槛、后台计时规则。未改生产实现。

### 日志设备、账号与会话字段的关联

在点击、滑回与补充结算三个分组共 153 条 tm.recommend 事件中，事件内嵌设备消息字段 3 和 6 均与 HTTP BUVID/gRPC 设备字段 3 相同；其字段 14 为另一个 64 字符值，与 gRPC 设备字段 14 相同，字段 15 则与 HTTP session_id 相同（8 字符）。事件顶层字段 4 与观看心跳 mid 相同。事件字段 3 内嵌消息的版本、构建为 6.6.0/91300300，与这次国际版请求配置相同。品牌、型号也与 gRPC 设备元数据匹配。

字段 18 的 start_session_id 为另一个 8 字符值，三组内相同，但不等于上述请求头编号，也未匹配视频页和观看会话。字段 6 与 RecordIO logId 相同且为同一个六位数字值，没有将其认作每事件唯一编号。其他基础字段及会话重启生命周期尚未完全确定。公开 [Device 定义](https://lxb007981.github.io/bilibili-API-collect/grpc_api/bilibili/metadata/device/device.proto) 将 gRPC 字段 14 标为 fp，但该命名和共享关系不证明推荐依赖。未保存这些真实标识，未改变生产实现或发送新的上报。

### 真实重启与旧事件补发的会话关系

用户在同一账号下完成首页刷新、后台划掉官方 App、重新打开及再次刷新的步骤。22 个 pbmobile 请求、231 条 RecordIO 记录完整解码并重新编码一致。重启前请求头 session_id 与日志设备消息字段 15 为编号 A，start_session_id 为独立编号 B；重启后新事件变为 C/D，四个 8 字符值各不相同。冷启动首页请求约在本分组开始后 32.229 秒（flush=0/pull=1/open_event=cold），同期含多种 app.active.startup 事件；后续手动刷新继续使用 C。BUVID、账号号、64 字符设备指纹重启前后均未改变。

重启后的两包上传同时装有重启前与重启后事件：共 15 条旧事件（其中 7 条 tm.recommend）仍保留 A/B，而当时上传请求头已经变为 C。旧事件字段 5 时间早于本次 cold 请求。日志内会话与上传请求头相同不适用于跨会话补发；事件发生时的身份与会话快照不能在补发时全部重写。普通后台/前台、换账号及会话生成算法尚未验证，未改生产实现。

### 普通后台返回的会话关系

用户完成普通后台/前台切换的一批操作，19 个 pbmobile 请求、105 条 RecordIO 记录完整解码并重新编码一致。全批 HTTP session_id 与日志设备字段 15 保持同一编号 A，start_session_id 保持另一个编号 B；BUVID、账号 mid、64 字符指纹均不变。两个推荐请求为 flush=6/pull=1/open_event=hot。本批同样包含 startup-copy.sys/startup-infra.sys，不能只凭这些事件名认定真实进程重启；非实时日志也有早于上传时刻的旧事件。与冷启动两编号均变化的样本分别记录，未推及长时间后台、系统回收或换账号。未改生产实现。

### 三次暂停请求字段

用户从历史进入同一“狗斗”视频，三次播放后暂停，最后停在暂停的视频页。捕获三条 ViewUnite/PlayPause，距 View 请求约 17.5、54.7、91.6 秒；HTTP 200、grpc-status=0，解码后的响应为空消息。以下为本批观察，未调整生产实现。

| 字段 | 三次请求的值或关系 |
| --- | --- |
| 字段 1 / 2 | 同一视频 aid / cid |
| 字段 5 | 同一份 2528 字节内容，非明文 JSON；未在本批 View 响应的递归解码字节字段中找到相同内容，生成方式未知 |
| 字段 6 map 的 stop_ts | 436、462、484；与续播后的播放位置相符，不是 Unix 时间戳 |
| 字段 6 map 的 session_play_ts | 16、42、64；与 stop_ts 的差始终为 420，等于上一批结束历史位置；拖动、倍速及完整计时规则未验证 |
| player_is_vertical | 三次均为 2；枚举含义未知 |
| non_player_area_width / non_player_area_height | 三次均为 402 / 437；单位、计算方式及横屏变化未验证 |
| 字段 7 | 三次相同，与 View 请求字段 6 相等，与移动心跳 session 不同 |

本批只有进入时的零观看时间移动心跳，操作结束仍在暂停页。PlayPause 的业务用途尚未确定；暂停时出现请求不等同于已确认观看反馈协议，也未排除暂停广告相关用途。

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)：曾对照推荐参数、客户端标识和观看上报实现。
- [公开 B 站接口资料](https://github.com/pskdje/bilibili-API-collect)：曾查询短信、签名和视频能力字段资料。
- [bilive_client 的 app_client.ts](https://github.com/bilive/bilive_client/blob/master/bilive/lib/app_client.ts)：包含 Android guest/reg 设备资料相关实现；采集对象中的 iOS 加密字段尚未取得对应规则。
- [analyze-feed-capture.py](../scripts/analyze-feed-capture.py)：按用户操作组分析首页请求，脱敏输出。
- 手机 Debug 日志入口：“设置 → 推荐流 → 推荐实验日志”。保存选定请求字段、推荐卡片和响应结果；不保存原始网络正文、登录凭据或真实设备编号，容量上限为 2 MiB。

## 基础曝光及设备指纹的补齐依据

按原始 param/track_id 重新关联既有中国版和国际版样本：882 条可匹配展示记录的 position 均为对应推荐响应 `data.items` 零起始下标 +1，1440 条可匹配时长记录均为下标 +2。统计包含翻页以及随后被客户端过滤的卡片；仅匹配同文件中的已捕获响应，未以缺少匹配认定错误或未曝光。当前位置应保留每批服务器原始序号，不以过滤后列表或整个累计列表的下标代替。匹配日志还见封面试验字段来自卡片 `extra_rpt_fields`；is_background 与 flush 不存在一对一关系，完整枚举仍未知。

新测试版实际首页点击的两条视频分别产生一次 main-card 点击和两端移动观看记录：实际观看时间为 0→61 秒及 0→86 秒。点击上传 HTTP 200，响应没有 JSON 业务码；四条移动心跳均 HTTP 200、业务码 0。卡片 track_id/report_flow_data 和页面、播放、请求会话的已实现关联吻合；该文件没有上述两种曝光事件。没有开展推荐变化验收。

中国版样本 19 次 fingerprint 的 key/content 各有 19 个不同值，bili_deviceId 响应仅一个值，并与该样本日志设备字段 2.14、gRPC Device 字段 14 相等。国际版重装和后续冷启动样本同样找到上述对应，国际版登录 device_id 也匹配响应；登录 bili_local_id 是另一编号。guest/reg 的三个响应中，两项在后续 device_tourist_id/guestid 中找到对应。原始登记分组可能包括多个客户端的活动及缓存日志，不将文件名称当成所有请求来源的证明，也不将这些相等关系当作首次生成规则。

fingerprint 的 key 为十六进制编码的 128 字节内容，content 为 496–544 字节、整 16 字节块；访客 device_info 为 192 字节，登录 device_meta 为 1136 字节，dt 为 Base64 编码的 128 字节内容。本批 web/key 返回 1024 位 RSA 公钥。已见 64 字符 device_id/fp/bili_local_id 符合 32 位 hex、14 位可解析日期时间、16 位 hex、2 位校验的候选结构，最后一段匹配前面 hex 字节求和模 256。没有由长度和校验关系认定完整的 iOS 加密或标识生成算法。

当前已从旧版 iOS 分析样本取得部分生成代码的函数体证据，尚未完整证明当前版本的明文资料与生命周期；[bilive_client](https://github.com/bilive/bilive_client/blob/master/bilive/lib/app_client.ts) 的 Android AES/RSA 实现仅作研究候选。基础曝光可复用已验收的日志包装，另外接入实际可见时段和 realtime 通道；设备登记需完成字段和版本核对后，用自身资料取得、持久化并复用对应服务器响应。细节与实施边界见 [NOTSURE.md](../NOTSURE.md#基础曝光的字段来源与补齐方案)。当前生产仍未增加曝光和设备登记请求。

已下载 [BiliBiliMApp 发布的 8.89.0 目标包](https://github.com/TouchFriend/BiliBiliMApp/releases/tag/3.1.0)，文件摘要匹配发布资产，包内 build 为 88900100。主程序加密标志 cryptid=0；同时加载第三方 BilibiliVideoTools 插件，因此不把它视为未经修改的官方原包。现已通过定向提取代码绕开坏符号表，并分析设备标识、fingerprint、访客和短信登录函数体；版本不同于当前采集的 9.13.0，不据此声明当前客户端完整等价。文件与核验摘要留在忽略的研究目录；原始源码和服务器端推荐算法不包含在此包中。

本包的 HTTP 跟踪身份与内部指纹为两套标识。BFCBuvid 优先复用 Preferences/Keychain，缺失时从 IDFA 或 IDFV 的 32 字符主体派生 `Z/Y+三个抽取字符+主体` 的 36 字符值。对既有三个采集文件的序列化 buvid 条目做脱敏结构核对，3,893 项 Y/Z 形态均符合主体第 2/12/22 个零起始字符组成前缀的关系；重复条目不是独立设备样本，混合文件还含 82 项 37 字符值。此前交接将官方 36 字符值称为 UUID 形态不准确；不能只凭长度认定 UUID，也没有据此确定当前客户端首次创建或重装来源。

BFCDeviceToken.localBUVID 则是 64 字符本地指纹：设备标识、型号、Apple 的 MD5 + 当前本地日期时间 + 首次运行时间派生的 MD5 片段 + 求和校验。它与服务器响应分开保存，currentBUVID 优先服务器值。短信参数调用链将跟踪 BUVID 放入 buvid/local_id，本地指纹放入 bili_local_id，当前指纹放入 device_id，与既有抓包的不同编号关系吻合。fingerprint 读取过程按调用时机异步更新，旧包发起时节流 120 秒、非空成功响应后为此次发起时间+86400 秒；不是主动定时刷新任务。

旧包 fingerprint 明文是有 54 项描述符字段的 Protobuf；其 content 使用 AES-128-ECB + PKCS#7，随机 16 字节 key 每字节为 1–127。key 先转 hex 字符串，再经包内 1024 位公钥与 Apple RSAEncryptionPKCS1 包装，密文转 hex。访客明文则是 IDFV、IDFA、DeviceType、Buvid、fts 五项 JSON；访客和登录 device_meta 使用 AES-128-CBC + PKCS#7，随机 16 字符字母数字 key 同时作 IV，RSA 包装后 Base64 为 dt。登录资料通过另一设备模型生成 JSON，不能与指纹 Protobuf 或访客五项 JSON 共用正文。访客/登录的 CRSA 入口已定位 padding=1，但静态 RSA 内部函数与完整更新调用方尚未追完。

假资料、已知 AES 向量、CommonCrypto/OpenSSL 交叉校验及包内公钥的 Apple Security 调用均已离线验证；假访客正文 178 字节，经填充加密为 192 字节，公钥包装结果为 128 字节。这支持旧包规则可复现和已采集长度相容，没有解密当前抓包、申请自身登记结果或验证推荐变化。字段来源、缺省值、首次运行时间保存及当前版本差异仍需完成核对。完整地址证据和限制见 [NOTSURE.md](../NOTSURE.md#ios-分析样本中的生成与加密规则)。手机采集保持关闭，实际准备好测试版并需要验证时再启用。

尚未确认的信息包括服务器推荐策略与实验分组、完整本地推荐调用、当前官方版本设备编号首次生成与重装生命周期、跨网络地区标签规则、曝光完整状态/门槛/调度规则、当前版本完整指纹和登录资料、登记兼容性及票据内部签名。旧包静态证据不能补足这些项目的当前取值与验收。

## 收藏夹进入普通视频

用户确认从官方收藏夹打开《【狗蛋的游戏评测】皇牌空战8 希孚之翼—长空颂歌》。
国际版 `iphone_i` 样本中，View 请求字段3为 `6`、字段4为
`united.player-video-detail.0.0`、字段5为 `main.my-fav.0.0`；对应开始和结束
移动心跳均为 `from=6/from_spmid=main.my-fav.0.0/auto_play=0`，结束 played_time=21。
两条移动心跳及独立历史写入均返回业务码0。此样本与前面首页自动播放及首页手动打开
的请求分开核对，未把它们归为收藏入口。原始材料留在仓库外
`~/Documents/NeoBiliCapture/current/official_library_entry.flows`，不提交账号或设备凭据。
这是国际版样本的观察，不代表其他入口或所有版本均使用同一来源值。

### 稍后再看与空间投稿进入普通视频

官方国际版 9.13 的本批操作中，稍后再看 View 请求与移动心跳均携带
`from=6/from_spmid=main.later-watch.0.0`；空间投稿均携带
`from=66/from_spmid=main.space-contribution.0.0`。两者详情 `spmid` 均为
`united.player-video-detail.0.0`，手动播放 `auto_play=0`，开始及结束心跳业务码均为 0。

同批动态快速消费自动播放出现 `from=default-value`、
`from_spmid=spmid=dt.dt-video-quick-cosume.video.0` 和 `auto_play=1`。
这不等同于点击进入普通详情；本批最后一条手动详情仍带首页来源，不能据此确定动态详情常量。

后续单独从动态点击《鉴定网传电脑事件，消磨看官吃饭时间5》，View 请求及观看开始心跳
均为 `from=6/from_spmid=dt.dt.video.0`，详情 `spmid=united.player-video-detail.0.0`、
`auto_play=0`，开始心跳业务码 0。该映射用于动态流直接进入普通视频；
动态文字详情内视频、空间动态等入口仍分别保留证据边界。
