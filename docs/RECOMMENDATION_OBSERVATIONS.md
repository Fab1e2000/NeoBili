# 官方推荐流采集记录

本文汇集官方 App 抓包、本地请求对照、NeoBili 代码及用户手机操作反馈。只记录观察到的现象、字段关联和当前实现，不给出推荐差异的根因判断。字段取值限于已有样本；相同账号、不同 App 版本、不同会话的记录分别说明。

完整字段清单和用户选定的发送策略见 [NOTSURE.md](../NOTSURE.md)。实现结构见 [架构](ARCHITECTURE.md)，采集与验证入口见 [开发与测试](DEVELOPMENT.md#官方推荐请求对比)。本文不包含手机号、验证码、账号凭据、真实设备编号、票据或安全验证 URL。

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

已观察到 `/x/report/click/ios` 和其他日志、曝光流量；二进制点击回执及完整曝光事件尚未解码，NeoBili 当前未发送这些事件。

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

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)：曾对照推荐参数、客户端标识和观看上报实现。
- [公开 B 站接口资料](https://github.com/pskdje/bilibili-API-collect)：曾查询短信、签名和视频能力字段资料。
- [bilive_client 的 app_client.ts](https://github.com/bilive/bilive_client/blob/master/bilive/lib/app_client.ts)：包含 Android guest/reg 设备资料相关实现；采集对象中的 iOS 加密字段尚未取得对应规则。
- [analyze-feed-capture.py](../scripts/analyze-feed-capture.py)：按用户操作组分析首页请求，脱敏输出。
- 手机 Debug 日志入口：“设置 → 推荐流 → 推荐实验日志”。保存选定请求字段、推荐卡片和响应结果；不保存原始网络正文、登录凭据或真实设备编号，容量上限为 2 MiB。

未采集的信息包括服务器推荐策略与实验分组、完整本地推荐调用、官方设备编号首次生成过程、跨网络地区标签规则、完整点击/曝光编码、指纹加密、访客资料加密及票据内部签名。本文没有这些项目的取值或规则记录。
