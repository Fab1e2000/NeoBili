# 未决证据与维护范围

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 未决证据与维护范围

本节把此前点名的各条线索逐条收敛。分类只有三种，结论各自带证据版本
（8.89 静态 / 9.13 抓包 / 本地实测 / 当前源码）；顺序不代表优先级。

本轮消费的官方侧新证据来自 S1 各区的证据明细（`DerivedData/Validation/team-t1`、
`team-t2`、`team-g1`、`team-g3` 的 findings，含 t1/t2 第二轮与 g3 尾部），本文只引用其中的
地址与指令结论，并另行核对 NeoBili 源码侧调用；findings 里的复现命令不在此重复。
独立验证席位（`DerivedData/Validation/team-g2/verify-report.md`，含第二轮）复核了本文与本轮
证据：基线抽样 0 错误；增量结论可复现 35／部分 5／**不可复现 1**／未复核 1；R01–R25 齐全、
相对链接无死链、未发现证据等级被越权提升。其中不可复现的一条（Q4/V20）是“`setCanceled:`
不主动置位”，已按反证改写（见 R12 与「已闭合」表）；Q3 指出 R11 编号证据只到“存在 +1
循环”，已收敛为 P0 残余；Q5/Q6 属协议文档覆盖清单措辞，已由对应席位处理。

- **已闭合**：源码锚点与官方侧锚点齐备，判定可直接引用，不再单列。
- **明确残余**：仍缺一侧证据，写出下一步可执行动作；缺证据处不补结论。
- **不成立**：作为本文的实施缺口不成立，说明原先为什么会被列成差异。

### 已闭合

| 条目 | 证据（源码 + 官方锚点） | 现判定 |
| --- | --- | --- |
| 普通网络刷新与缓存恢复的 compactMap 编号 | 8.89 HD回调0x10df59978、Swift DataFactory 0x101a3e1dc→0x101a4340c→0x101a3e5a4、缓存恢复同链；源码 [AppRecommendationPage](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationPage.swift) | NeoBili 不保存批次/原下标是已证事实，不是缺证据；9.13 编号选择机制另见残余（R11/R20） |
| 播放 stash、tracker 继承与时间回执的差异 | R13/R16/R17/R22 各自的 8.89 地址与源码锚点（见[源码锚点索引](differences.md#源码锚点索引本轮逐条核查)） | 差异方向与缺失实现已判定；9.13 是否要求这些字段另列残余 |
| 应用定时心跳 | 8.89 Atomic 0x11487eac8、_fireDelegates 0x1149f2f10、startBeating；源码无对应实现（[AppBehaviorEncoder](../../../NeoBili/Data/Networking/Reporting/AppBehaviorEncoder.swift)） | 缺口事实成立且可判定（R23）；不再追同一条链 |
| Series/HD2 的请求与响应锚点 | 0x10411a640/0x10411a6e4/0x10411af68、HD2 0x10df58a10/0x10df58dfc；见[覆盖清单](../protocols/coverage.md#覆盖清单) | 请求与响应配置层已闭合；Series producer 已由 c2 §5 定位（loadBlocRequest→STLoadBloc requestWith:tab:→共享方法体 0x10411af6c），残余转“线上实验取值/tab 来源” |
| 三次 feed/index 本地实测 | 本地实测：`DerivedData/Validation/recommendation-network-s1/` | 已闭合到“该端点与参数组合未拒绝错误 sign”；不能升级为签名被校验、ticket 有效或个性化已证 |
| 公共时间辅助的错误路径与缓存持久化 | 8.89 `getLocalRealTimeIntervalWithSyncServer:` 0x115dab37c 只有成功 completion 在 0x115dab68c 清 flag；`requestWithOptions`(0x115dab524) 与 `requestAsync`(0x115dab544) 之间无第二次 handler 写入⇒errorHandler 为 nil，失败分支 0x116093d0c 直接退出。持久化经 BFCPreferences 动态属性层写 suite `BFCLaunchTimePreferences`，key=属性名 `boottime`/`slinterval`，两次独立 setter 非事务；suite 名字面量唯一引用 0x115dab184 | 已闭合（T1 findings P2）：失败或在途不清 flag，且不存在超时清 flag 路径。残余只剩非 ADRP 间接写入与运行期断点确认 |
| ticket 的执行 enable 与 tries 消费 | 8.89 `sub_10009AE38` 读 `ticket_enable` 等配置；`sub_100099108` 0x1000991ac 把 cfg+0x10（=`ticket_enable` 实验命中）写入 TicketInternal feature 位，其唯一构造点 0x100095ec8；`ticket.get_max_tries` 默认 4 只写入 cfg+0x30，7 处配置槽加载点全枚举后无 `+0x30` 读取 | 已闭合（T1 P1）：执行 enable 输入是实验命中而非 `presetHitValue`；tries 只存不读，**不得写成“会重试 4 次”**。gateway 跨模块次序另列残余 |
| BUVID 的调用方与重装来源 | 8.89 `BFCBuvid.buvid` 0x1167cbe68：prefs 未命中→Keychain(service=`trackId`、key=`buvid`)→读回后回写 prefs→IDFA→IDFV；classref 邻近∩BL 得 117 个 `+[BFCBuvid buvid]` 调用点 | 已闭合到地址级（T1 findings P5）；54 项指纹赋值不属该区，另列残余 |
| 心跳时间回执与公共时间辅助是两条链 | 8.89 Atomic `startBeating` 0x1149f29fc 用设备墙钟；历史/心跳上下文走 `+[BFCServerTimeChecker realTimeInterval]` 0x115dab1a8；服务端 ts 回执写 Context +0x50，与 `getLocalStartTimestamp` 的 `_start_verify_ts`(+0x18) 不同槽 | 已闭合（T2 findings C-5）：R22 的“两种时间不可互代”有指令级证据 |
| 分享 forbidden 的真实 delegate 规则 | 8.89 ShareBaseModule 初始化体 `sub_10018CDA8` 把 ShareCoreInject 实例交给 `BFCShareInjector.setDelegate:`（调用点 0x10018cdec；与 classref 交叉扫描唯一命中 0x10018cde4）；`isForbiddenAPIError:` 要求 nonZero domain 且 code==110000 | 已闭合（T2 findings C-7）：原先只到“规则未知”的 delegate 已定位到唯一装配点与 110000 判据。Neo 仍用系统分享，不因此新增实施项 |
| Monitor 外部重试入口与 producer | 8.89 `BCMReport retryFailedEvents` 块 0x11416fd94 的三个 `retryFailures` 出口依次为 ui/feeAd/feeMMA，无 Monitor；`BCMMonitorUIAdEvent`/`BCMMonitorUITrackEvent` 的 class/RO 引用扫描为 0 | 已闭合（G1 findings 1）：本镜像内 Monitor 无构造点，其重传链静态不可达；残余只剩运行期动态构造 |
| 旧 V2 再次触发与 Neuron 重试/过期 | 8.89 `addReportWithItem:` 块 0x1141c66f0 在 count>=20 直接 `trySendReport`、否则 3 秒 `dispatch_after`；共享 stub 0x11754e3c0 的调用方 0x1141c6808/0x1141c7124 在 scheduler 数组遍历里 `mov w2,#1` 置 canceled（原文“不主动置位”已被独立复核 V20/Q4 反证）；Neuron `Configuration.init` 默认 expireDays=7，`updateCacheItem` 0x1161ec850 只增 `retrySendCount`、无上限比较 | 已闭合（T2 C-8/C-9 + 更正 V20）：R12 的“不照搬 7 天与无条件重试”现有所本，且旧包 3 秒延迟补发会被成功路径取消；64 MiB 分支可达性另列残余 |
| gateway 注册次序机制（334 表更正） | 8.89 单一漏斗 `registerClass:` 0x11609916c→`appendClass:` 0x11609919c 锁内只 addObject；多绑定读取 0x105134860 按数组序；root 构造 0x1051313a0/sub_105133CE8 由容器 `*(0x1204ced28)` 的组数组驱动。334 项表 0x120272648 经区间扫描与三条全域指针扫描 **0 命中**，同方法对 184 项 runnable 表有阳性对照命中 | 已闭合机制层（T1 R2-1）：append-only 与组数组次序已证；**模块内次序可定、跨模块不可静态定序**（组件类无 classRef/指针引用，运行期 witness 装配）；334 项表只能当名字索引，token 序号不得当次序依据 |
| Ktor 请求不安装 native HttpSign listener；Enable 三键只读 | 8.89 旧 BFCHttpTask `requestType`==2 → 0x1000aaea0 `cmp w8,#2`、0x1000aaea4 `b.eq 0x1000aafcc` 整体跳过 listener 遍历；native 门控是 `dd.http_sign_buvid` 0x117776190；三个 Enable 键共用槽 0x120c5e410，6 读 0 写（含阳性对照），GInterceptor 缺省 false；`bfc_http_disable_ktor` 只有 1 处读取，阳性对照 `bfc_http_disable_common_params` 有写入点 0x105034bdc | 已闭合（T1 R2-2/R2-3）：“Ktor 走 native HttpSign”不成立；Swift 侧无业务 enable writer（键由 Kotlin 创建/写入），且“缺省值”不等于运行期生效状态 |
| 指纹 54 项的描述符与赋值来源 | `+[BFCDeviceIosDeviceInfo descriptor]` 0x115fd895c `mov w6,#0x36`⇒fieldCount=54；`-[BFCDeviceToken generateInfo]` 0x115fd5b54 的 54 个 setter 中 **51 项已映射来源**，isVpn/ip/userAgent **在本 payload 类内**无赋值点（`setIp:` 全镜像 9 处 / `setUserAgent:` 29 处接收者均非登记类；team-c3 S1）；姊妹类 `BFCAccountDeviceInfo` 0x116058d3c 须排除 | 已闭合到描述符/来源层（T1 R2-4 + team-c3 S1）；运行期取值与 wire 缺省另列残余 |
| guestId 偏好的唯一写入者 | `-[BFCAccountGuest saveGuestIdWithData:]_block` 0x11605a474 是唯一写入点（阳性对照）；登录/退出路径不写；`guestIdCanAddToNetCoreHeader` flag 变化不重选已注册 class | 已闭合（T1 R2-5）：所选官方路径保留 guestId；Neo 已由 AppGuestRegistration 持久化并在可用时加入 guestid 头，设备作用域与迟到响应另查当前实现 |
| LatestHistory 缺项运行可达性与 uri 消费 | 8.89 prepare helper 0x1002395d8 只有两个直接调用方 0x1002397a8（HomeResumePlayView.didBecomeActive）与 0x100242ea4（HomeViewController.viewWillAppear:，且在 view 非空判断之后）；发送方唯一（selref 0x11f784aa0→0x1002396d4）；uri 非 nil 走 BFCRouter `processUrl` 0x1002390c4 | 已闭合（G3 §1）；Neo 无该 RPC 的判定不变，不作为实施前置 |
| 翻译设置外部清理（官方侧） | 8.89 `userEnabled` setter 0x105c2f870 只有 2 个直接调用方（Kotlin export thunk 0x105c30ffc、UI helper 0x10a49f878），无 Logout/账号观察者；suite 级清除不存在（`removePersistentDomainForName:` 仅 UASDKStorage 0x1167b4a5c） | 已闭合（G3 §2）：官方同样没有外部换号清理 ⇒ 原先设想的“差异”不成立 |
| 结果缓存整体失效入口 | 8.89 `+[FallbackCacheOCBridge clearAllWithCompletion:]` 0x102127a34；物理触发唯一 0x10f2fff94（BBPhoneSettingMainVC 清理缓存链），受 `pegasus_disk_cache_enable`（缺省 false）门控；未发现设备属性/账号事件直接触发 clearAll | 已闭合（G3 §3）：设备属性事件到结果缓存失效不成立 |
| DD 更新结果归属 | 8.89 `DDUpdateEngineDidUpdatedNotification` 的 Swift accessor 静态无 `addObserver` 消费者；gateway interceptor 以 completion=nil 调 `updateWith:force:false:from:http:`（火后不管）；V2 返回值只按 Success 动态转换 | 已闭合（G3 §5）：通知归属与结果透传边界已证，动态注册另列残余 |
| 设备三字段与登记请求/回执/落盘 | team-c3 S1/S2/S3.1/S3.2（8.89 静态）：`isVpn` 无 stub；`ip`/`userAgent` 在 payload 类内无赋值点（classRef_BFCDeviceIosDeviceInfo 0x11f7f02b8 全镜像 1 处＝0x115fd5b98 ∈ `generateInfo` 0x115fd5b54；阳性对照 classRef_BFCDeviceToken 0x11f7b5ca8 33 处；`setIp:` 9 处 / `setUserAgent:` 29 处接收者抽样全为无关类）；POST `https://app.bilibili.com/x/resource/fingerprint`，AES-128-ECB/PKCS7（16 字节随机 key 1..127）+ RSA-PKCS1v1.5（内置 BFCDevice.pem，2048）包 key；回执门禁=error nil＋HTTP 200＋顶层与 data 均 NSDictionary＋`bili_deviceId` 非 nil，**不校验 code、失败不调 completion**（0x115fd82d0→0x115fd83e0）；保存 `BFCDevicePreferences.setServerBuvid` 0x115fd74a4 + Keychain(service 3,key `serverBUVID`) 0x115fd74d4，仅值变化写，内存 expiry=发起+86400 | 已闭合（静态）；只剩运行期取值与 wire 缺省 |
| ticket 缓存的 reset 边界 | team-c3 S3.5（8.89 静态）：单例槽 0x12027d090 全镜像恰 4 处载入（0x100096208 `-[BFCTicket init]`、0x100096764 `+[TicketPrefs shared]`、0x10009943c startup、0x100099c10 成功保存腿），无 STR / `objc_storeStrong` 写点 | 已闭合为“静态无登录/登出 reset 路径”；**这不等于运行期一定不重置**（跨账号复用同一份缓存需 9.13 抓包） |
| 响应侧回执族（Neuron/历史/点击上报/feed 消费） | team-c2 §7/§10（8.89 静态）：Neuron `-[BFCNeuron report:didFinishTask:data:error:]` 0x1161ed618——error/非 NSHTTPURLResponse→`updateCacheItem:`；statusCode==200→`deleteCacheItems:`（0x1172afa40）并跳过 update；449/500–599→`handleFlowControl`（0x11734e600）+`updateCacheItem:`；播放历史校验链 helper sub_104A80FCC 以**无参 `requestAsync`** 发送、**无本地回执分支**；点击/展示上报复用同一 Neuron 回执（事件 id 001365 不是独立 HTTP 回执）；feed/index MainApi completion 0x101a340c0 键序 `/data/config`→`/data/interest_choose`→`/data/items`、形参 (items,config,interestChoose,flag=0)、config 缺失/错型走 Mikoto `list.pgs.tech.error.config`（policy=100/rate=0，sub_104E4AA7C）非终止分支、**响应侧无 offset 游标写回** | 已闭合（静态）；公共层 gateway 错误加工与本层交界未复核 |
| 访客登记与账号校验回执 | team-c3 S3.3/S3.4（8.89 静态）：仅 guestId 为 0/-2 才登记；body `{device_info: GuestInfo.info, dt: base64(RSA(guestInfo.key))}`、sdk_ver `0.1.15`、apiKeySecretType=1/ignoreCodeNonZero=1，URL `https://passport.bilibili.com/x/passport-user/guest/reg`（RSA 公钥由 `requestPublicKeyWithCompletionBlock:` 运行期取回，非本地 PEM）；回执信封 JSON{code:NSNumber,message:NSString,data}；账号校验 code==61000 时先取 tokenInfo.mid 与 ssoModel.mid **相等才** `logoutWithApi:`（0x116052750/0x116052948，参数=请求 absoluteString，nil 用 `BFCAccount_validate`），code==0 读 data.mid/expires_in/refresh | 已闭合（静态）；9.13 未核 |
| 广告响应模型、第三方 SDK 与网页容器边界 | team-c4 块 2/3（8.89 静态）：`BBAdPlayerAdModel` mapper（mixList←ads、foreverFloatList←permanent_floating）+ `BBAdPlayerAdIconModel`/`BBAdPlayerAdInfoModel` 字段表 + `BBAdPlayerAdPanelHelper viewTypeWithClickType:mixListModel:` 0x1133e7b54 分派族、`_detailIsH5WithData:` 0x1133e8054/`_realUrlWithData:` 0x1133e8114；广告卡片内商城 cell 可直达 addToShoppingCart（0x1133c0e44）。依赖边界：app 包 PlugIns=0、Frameworks 仅 BGM.framework 与 BilibiliVideoTools.dylib，AlipaySDK/WXApi/TCLoginViewKit 等符号均在主二进制（非独立库）；主容器 `BFCWKWebViewV2` 0x115dd9ed0 同时设 navigationDelegate/UIDelegate 并替换 userContentController | 已闭合为“响应模型/分派族/依赖与容器清单”级（静态）；DetailModel 字段清单与 SDK 是否共享主 session 属残余/运行期 |
| IM 未读链、直播重连与账号清理、搜索字段否定（含降级） | team-c5（8.89 静态）：BBLinkConnectManager install 0x10e5f3368、Ack 取值优先级 `ackSeqno = maxSeqno 非 nil 时直传、否则 locSeqno.unsignedLongLongValue`（入口 0x10e5f3d48，判定点 0x10e43e42c；**不是拼接**，task-18 更正）、未读映射 0x10e62c154、anchor 角标消费 0x10e5e5184（**Blink 引擎本体不在主二进制**，连接/心跳/重连参数静态不可判）；BBLiveSocketReconnectScheduler 0x10edac53c（60 秒阈值/5 秒兜底/socketRefreshDuration，构造点 0x10ed19f08）、`_dropAllLocalWatchTime` 唯一调用点 0x10f0eee9c（无登出清理入口）。**降级更正**：c5 的“SearchAllRequest needOgvExtraWord/foldable/isWideScreen 静态可证否定”已被验证席推翻——selRef 0x11f787d88 全镜像 8 处引用，其中 2 处在 `ResultViewController collectionView:willDisplayCell:`、1 处在 `BBListSearchChildDataService cancel`（经 `j__objc_msgSend` 动态派发）⇒ 只能写“未见直接赋值点，存在动态派发命中” | 已闭合为入口级；搜索该项已降级，其余传输实体/账号生命周期属运行期 |

### 明确残余

| 条目 | 现有证据 | 下一步可执行动作 |
| --- | --- | --- |
| **R11-2 CardData witness +0x40 的字段归属（P0，阻挡曝光定稿；R11-1 已定稿）** | R11-1 定稿：0x101a3ed5c 的 +1 循环在 sub_101A3ECAC，是 Swift 标准库 sort 的归并 run 记账（0x101a3ecd4 `_minimumMergeRunLength`、0x101a3ed18 `_allocateBufferUninitialized`），不写任何卡片字段；`sub_101A3E5A4` 内 0x101a3e95c `add x26,x26,#1` 把 1-based 序号作 x0 传给 CardData 协议 witness 表 +0x40（0x101a3e98c `ldr x28,[x22,#0x40]`、0x101a3e9b0 `blr x28`）。**为什么不可判**：该 requirement 经协议 witness 间接派发，静态无法定位其写入字段 | `disassemble.py 0x101a40040 0x101a40180` 读 compactMap 里 CardData 的 allocObject/init 确定 +0x20/+0x28 是哪个协议 existential；再 `query_index.py '*CardData*WP*' 30` 枚举 +0x40 槽实现并反汇编；真机断点 0x101a3e9b0 读 x28 落到哪个实现 |
| 设置功能/设置→参数的剩余同步与覆盖 | R01 表已到 8.89 builder 读值层；源码 [AppRecommendationProtocol](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationProtocol.swift) 无对应状态源；T1 已证 gateway append-only 漏斗与组数组驱动，模块内次序可定、跨模块不可静态定序（组件由运行期元数据/witness 装配，无静态顺序表）；334 项表零引用。**为什么不可判**：跨模块次序属运行期；9.13 每项最终规则需抓包 | 追账号同步/覆盖次序与 9.13 每项最终规则；gateway 跨模块次序用运行期打印 `appendClass:` 入参（0x11609919c 下断点），静态映射不是替代 |
| Swift 兴趣选择与重编号范围 | R11-1 已定稿（sub_101A3ECAC 的 +1 循环是 stdlib sort 记账，不写卡片字段）；sub_101A3E5A4 内以 1-based 序号调 CardData witness +0x40，字段归属见上方 P0 行。T2 S-1 把 helper 语义闭合到 `sub_101A538D8` 的三种提前返回与 `setContentOffset:` 调用。**为什么不可判**：编号循环边界未读出；回执账号所有权需运行期样本 | 反汇编 `0x101a53fd0–0x101a55004` 与 `0x101a5a800–0x101a5b600` 读编号循环边界；回执账号所有权追 `setSourceType:` 写入者 |
| 缓存后端过期与活 VM 取消/账号边界 | R20 已有 flush 门控、key、weak-load 与 commit 点地址；T2 C-10 固定写入点 0x101a5a914（scene/version/expirationTime=0）与 FallbackCache 承接。**为什么不可判**：后端过期语义需服务端确认，跨账号污染未实测 | 过期语义交尾部 FallbackCache 章节（task-6）；本项只保留“活 VM 取消防串扰”追查 |
| 登记资料的运行期取值与 wire 缺省（三字段/请求/回执/落盘已闭合） | 静态部分见「已闭合」表：classRef 0x11f7f02b8 仅 1 处引用；POST /x/resource/fingerprint；门禁 error nil+HTTP 200+data+bili_deviceId、不校验 code；保存 0x115fd74a4 + Keychain service 3。**为什么不可判**：GPB“未设置的可选标量不写 wire”属库语义推断、本镜像未验证，实际取值需运行期 | 真机断点 dump：`-[BFCDeviceToken serverBUVID]_block` 0x115fd72e4 的 `getDeviceInfo` 返回处读 AES 明文；9.13 抓包核回执字段；见[设备登记与访客生命周期](../protocols/device-registration.md#设备登记与访客生命周期) |
| Atomic 注入 tracker 的实例子类身份（注册/上传链已闭合） | c2 §6.1 闭合注入→上传链：BFCAtomicHeartbeatModule 0x100129e40 `allocWithZone`+`init` → 0x100129e58 `[BFCAtomicHeartbeat.shared startWith:]`；`trackHeartEvent:dict:` 0x1001298ec → sub_100129684 依序 `customEvent:p_event_count`、`setLogId:006638`、`setExtendedFields:`、`trackEvent:trackPolicy:`(policy raw0)；注册侧 NeuronModule.register 0x104976d08，witness+0x10=0x104976c18 返回 `BFCNeuron.shared`。**为什么不可判**：注入 tracker 的实例子类由谁提供未静态闭合 | `disassemble.py 0x1001299a0 0x100129a10` 看调用点寄存器来源，或真机断点 0x1001298ec 读 x0；见[播放器心跳的边界](../protocols/watch-history.md#播放器心跳的边界) |
| 兴趣回执账号/请求所有权 | R24 已有 guide 闭包次序、finisher 差异与 T34 子对象 marker；账号边界与全局 reset 未证。**为什么不可判**：跨账号交付与全局 reset 只能取运行期样本 | 追 second/guide 回执的账号代际与全局 reset；按 R24 的验证清单取样本 |
| PlayerEvent 的构造者（身份与转换链已闭合） | c2 §3 证 `BFCNeuronPlayerEvent` 是 ObjC 协议 0x11d88fec0（具体类 `_TtC6Neuron11PlayerEvent` 无 ObjC alloc 构造点）；转换链 B sub_104974BE0 按 category 5/7/8/9 分派并逐项 set `BFCNeuron_AppPlayerInfo`（0x104974eb0–0x104975220）；点名的四个 bloc 0x101eb063c/0x101ee97a0/0x101e0a9c8/0x101f0f548 都不构造 PlayerEvent、不调 `trackPlayerEvent:`。**为什么不可判**：Swift `PlayerEvent` 的 `initWithId:` 0x104967e84 无 BL 调用者（msgSend/间接派发） | 枚举 `initWithId:` stub 的调用方，或真机断点 0x104967e84；先确认 9.13 是否需要该事件 |
| Series/Story 的线上实验取值与 tab 来源（producer 已闭合，撤销 T2 S-2） | c2 §5：`-[BBPhoneMPStoryFeedVC loadBlocRequest:]` 0x1132e6728 → stub 0x1174f2ec0（全镜像唯一调用点）→ `-[STLoadBloc requestWith:tab:]` 0x104115284，门禁 Memex `ff_united_story`==1 且 tab==1，命中后经 lazy `seriesLoader` 直调共享方法体 0x10411af6c（与 `-[STSeriesLoader requestWith:config:]` 0x10411b300 同一地址）；selector 无调用点是直接 BL 方法体所致，**不是生产者不存在**。**为什么不可判**：`ff_united_story` 的线上命中值属服务端下发；tab 取值来源未逐条读 | 真机读 `BFCMemexABTest` 命中结果；`disassemble.py 0x1132e6728 0x1132e6800` 读 tab 来源；见[SeriesLoader 参数与响应证据](../protocols/settings-parameters.md#seriesloader-参数与响应证据) |
| 广告归因的剩余边界（展示分派与响应模型已闭合） | c4 块 3 闭合响应模型与展示分派族：`BBAdPlayerAdModel` mapper（mixList←ads、foreverFloatList←permanent_floating，元素类 `BBAdPlayerAdDetailModel`）、Icon/Info 字段表、`+[BBAdPlayerAdPanelHelper viewTypeWithClickType:mixListModel:]` 0x1133e7b54 及 `_viewTypeClickIcon/Danmaku/ListCell`、`_detailIsH5WithData:` 0x1133e8054、`_realUrlWithData:` 0x1133e8114。**为什么不可判**：`BBAdPlayerAdDetailModel` 是纯 Swift 存储属性（无 ObjC 元数据），字段清单需解 fieldmd；真实加载触发与采样默认值属运行期/服务端下发 | 解 DetailModel 的 nominal descriptor（`query_index.py '*BBAdPlayerAdDetailModel*'` + `read_constants.py` 沿 _classData 0x11ed0be58）；采样 producer 追 0x107aba324→sub_10BFCDFEC provider；见[广告加载与归因的静态入口](../protocols/advertising.md#广告加载与归因的静态入口) |
| Ktor Locale byte 序列化与引擎覆盖 | R18 已证独立 Locale hook 与 write-once 门禁；T1 P4 把**原生 `BFCApiSignHelper.baseParams`** 的 `c_locale`/`s_locale` 追到 `BFCApiConst` 注入服务；c3 S4.3 把 Locale 元数据收窄到唯一构造点（`BAPIMetadataLocaleLocale` 0x11f7be570 全镜像 1 处＝0x105060fec，`KntrLocale` 2 处＝0x1050628a8/0x105063710），采用侧是 `LocaleRegionService` 绑定 + `DeepBlueGRPCInterceptor.metadataInjector`。**两层不可合并**：原生 baseParams 是 NSDictionary 值层，尾部 Kotlin `KLocale` hook 写 `x-bili-locale-bin` 属另一层。**为什么不可判**：各 engine 是否实际带上 Locale 取决于运行期 Gripper 绑定与 interceptor chain；0x120c5e410 无写点（读点计数依扫描口径，第三轮验证记为 5–7） | 核 registrar 0x10008e098 与各 engine chain，或 9.13 抓包比对 Grpc/Ktor/stream 三 transport 的 metadata；Ktor 侧 sign 适配器需解 0x10b93c814 的 18 成员集合；见[Ktor 公共参数签名与编码](../protocols/ktor.md#ktor-公共参数签名与编码) |

跨版本与运行期类残余和上表性质不同，静态逆向无法闭合，单列：9.13 新版函数体、登记兼容、
访客完整生命周期、日志跨账号官方策略、推荐因果，以及播放会话 ID 同毫秒碰撞（T2 S-5）、
Neuron 64 MiB 分支可达性（S-6）、心跳文件缓存 TTL/账号过滤（S-7）、CloudSync observer
安装方（S-8）、`extendFields` 冲突优先级（S-4）、`sourceType` 写入者（S-3）、
gateway 跨模块相对次序（T1 R2-1，需运行期 `appendClass:` 入参）、Kotlin 共享 property writer 路径（G3 §2）、
DD 通知的动态注册路径（G3 §5）与以运行期字符串为参数的整 suite 清除（T1 R2-5）。
国际版可用于字段关系线索，不能替换中国版身份配置。

### 不成立

| 条目 | 判为不成立的理由 |
| --- | --- |
| 语言 cleanup 导航时序 | [LanguageSettingsView](../../../NeoBili/Features/Settings/LanguageSettingsView.swift) 在选择回调里直接 [AppLanguage.apply](../../../NeoBili/Domain/Models/AppLanguage.swift)，没有离开页面才提交的编辑事务；“点击日志≠生效偏好”的差异在 Neo 不存在 |
| 画质 UI 实际呈现 | 8.89 静态接线只证明菜单绑定与门禁，不验收 Neo 的画质行为；Neo 画质菜单有自己的状态门禁（R02）。T2 C-11 已把实现类钉到 `BBPlayerVideoQualityListWidget makeQualityData:` 0x114535648、选择回调 0x114536030 与 `_switchToExpectQn:isAuto:needUpdate:preferToast:` 0x11453d23c（另有 UGC/HD2MP 两个同类），但 present 安装方、trial 生命周期与 CURRENT quality 更新仍是 S-10 残余。该链不产生 Neo 实施项；真正的残余是需另行授权的 HDR/权限/解码专项，不靠静态逆向闭合 |

原先另列的四条已由第二批证据闭合官方侧，移入上面的「已闭合」表并在该表注明
“对 Neo 不构成实施前置”：翻译设置外部清理、设备属性事件到结果缓存失效、
LatestHistory 可达性/uri 消费、DD 更新结果归属。

9.13 抓包/实测类新的闭合证据会继续按同样规则并入上表；本文不重做整份逆向，收到新证据后
核对实际调用与最终赋值，再更新相关 R 项判定。

当前覆盖首页请求、身份登记、卡片点击/观看关联、曝光与缓存补发、过滤去重；搜索、
动态、推送、评论等业务只有在S1证明与这条推荐链有关时才转为实施建议，不建议照搬
所有网络请求。普通会话跟进不等于后台永久监控或无人值守唤醒。
