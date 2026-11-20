# 推荐实现与协议差异

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

各项保留官方样本的版本与可定位证据，并单列当前源码的实现范围。8.89 的函数地址只用于
对应二进制；当前 App 身份、设置与请求策略见[网络与账号](../../architecture/accounts.md)。
R 编号及旧锚点保持稳定，剩余研究问题按实际产品需求处理。

<a id="r01-首页参数必须分版本配置能力设置和操作状态p1"></a>
### R01 首页请求按当前国际版模板和操作状态组装

**证据**：8.89 `BBHD2PhonePegasusMainApi.params` 0x10df56ed4 取对象状态、Reachability、
广告服务、播放器 helper 和窗口类型；不是固定字段模板。`loadData` 0x10df58a10、
`loadMore` 0x10df5a4c0 设置不同刷新状态。9.13 的首批/下拉/翻页及混合操作观察见
[观察文档](../../RECOMMENDATION_OBSERVATIONS.md#首页参数随操作的变化)。

**NeoBili 当前实现**：[AppRecommendationProtocol](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationProtocol.swift)
使用 `iphone_i/91300300`，首批、布局、手动刷新、分页分别生成 `flush=0/2/14/8`，
首批请求 `pull=1`、分页 `pull=0`。当前模板为 `column=2`、`auto_refresh_state=1`、
`autoplay_card=11`、`inline_sound=1`、`inline_sound_cold_state=2`、`inline_danmu=2`、
`voice_balance=1`、`client_attr=0`、`qn_policy=1`、`video_mode=1`、`recsys_mode=0`、
`disable_rcmd=0`；`widgets` 为空，`teenagers_age` 省略。
网络、首尾游标、cold/hot 和横幅 hash 来自自身状态；编码器最后加入凭据、时间戳和签名。
8.89 设置到字段的完整来源保留在[设置参数研究](../protocols/settings-parameters.md)。

**剩余范围**：当前产品没有官方首页布局、播放样式和云端偏好同步入口。固定模板的其他动态取值需按版本采集。

<a id="r02-播放能力和画质不能由一个首页常量代表p1"></a>
### R02 各取流通道独立声明播放能力

**证据**：8.89 `supportFnval` 0x114a0be60 按 UHD/EAC3/HDR/DV/AV1/HEVC/H266 能力
及实验组合；`preloadUrlDeviceParams` 0x114a0c21c 将 player_net、fourk、force_host
关联网络/能力/HTTPS 设置。`preferredQnForResolver` 0x11482101c 在自动画质下取32，
否则取设置并经过登录态限制；client_attr 还依赖 HDR 实验、偏好及 VIP。

**NeoBili 当前实现**：首页发送 `fnval=17364`、`qn=32`、`fourk=1`、`force_host=0`、`soft_fnval=0`。
`AppRecommendationPlaybackCapabilities.fnval=2448` 供直播推荐列表使用；普通视频经
[BiliAPI+Playback](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Playback.swift) 的网页 WBI
通道依次尝试 `fnval=4048/16/1`。相关推荐使用独立 gRPC PlayerArgs。
画质菜单在播放器可操作时选择已有轨道或重新取流，实际结果写入播放器状态。

**剩余范围**：渲染层尚无显式 EDR/色彩空间接线；HDR、杜比视界与 HDR Vivid 输出需要对应设备、权限和素材验收。

<a id="r03-屏幕附加内容有已证实结构差异p2"></a>
### R03 屏幕附加内容使用当前屏幕像素边长

**证据**：8.89 `extraContent` 0x1143982d8 以 screenHeight/screenWidth 分别写
long_edge/short_edge，另写 translateLanguage→cur_language；函数本身不排序边长。

**NeoBili 当前实现**：[AppRecommendationDisplay](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationDisplay.swift)
从当前 scene 的 `screen.nativeBounds` 取长短边，向下取整；JSON 仅含 `short_edge` 和
`long_edge`。`currentScale()` 单独读取逻辑显示缩放，供其他显示元数据使用。

**剩余范围**：8.89 样本使用 bounds×scale 的 getter，并有翻译语言字段；当前应用未接入内容翻译。

<a id="r04-登录事件启动消费和横幅失效不是同一生命周期p1"></a>
### R04 启动标记和横幅缓存绑定请求会话

**证据**：8.89 MainVM.init 0x10df58690 按登录/访客设 login_event=2/1，登录/退出
观察者重设，成功回调0x10df59104清零。helper.open_event 0x10df57b60 的 getter 消费
cold/hot；后台间隔严格超过1800秒时清 banner_hash（0x10df579ec 后续方法链，完整
通知安装链已闭合，锚点 0x10df579ec）。重试复用 loadDataOptions，不再次消费 getter。

**NeoBili 当前实现**：[AppRecommendationSession](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationSession.swift)
持有 cold/hot、banner hash 和账号会话。前台恢复记录 hot，下一次 App 推荐请求消费；
首页保持现有列表，用户刷新或分页时才请求。缺少已登录账号的 App 授权时先提示补授权。
换会话清空横幅，迟到响应按请求上下文过滤；`login_event` 固定为 0。

**剩余范围**：完整官方登录事件、活动段与通知启动来源仍未接入。

<a id="r05-自身-buvid-生成与官方跟踪编号不同p0"></a>
### R05 普通应用使用持久随机或自定义 BUVID

**证据**：8.89 `BFCBuvid.buvid` 0x1167cbe68 先读Preferences/Keychain，失败后用
IDFA或IDFV去连字符，生成 Z/Y +主体第2/12/22字符+32字符主体。既有样本的36字符
Y/Z值符合这个结构；不是带连字符UUID，也不能由重复条目数量推算独立设备数。
**补充（8.89 静态，T1 findings P5）**：取值链已到指令级——BFCBuvidPreferences.trackID
未命中后走 Keychain（service=`trackId`、key=`buvid`，0x1167cbf7c），读回成功会
`setTrackID:` 回写 prefs，之后才退到 IDFA（0x1167cbfe4）与 IDFV（0x1167cc0ec）；
classref 邻近∩BL 匹配得 117 个 `+[BFCBuvid buvid]` 调用点，覆盖认证头 0x11609d4b8、
Tracker trackID 0x115fd2ac0、UserAgent 0x115e04170 与 BFCActiveReport 0x115fd0a30。
代码把 Keychain 排在 IDFA/IDFV 之前，所以重装后的来源只可能是 Keychain 或重新生成；
Keychain 跨重装保留属 OS 语义，本样本不能证明“实际重装后仍命中”。

**NeoBili 当前实现**：生产组装优先使用用户保存的自定义 BUVID；留空时加载或生成持久随机编号。
选择在启动时固定，换登录保持设备编号；设备登记、访客和票据按编号使用独立存储。
[DeviceIdentity](../../../NeoBili/Data/Networking/Identity/DeviceIdentity.swift) 仍保留偏好/Keychain
优先、自身 IDFV 的 Y 分支和进程内兜底，供隔离测试与诊断路径使用。
设置键及输入范围见[设置开发](../../SETTINGS.md#设备编号)。

**剩余范围**：8.89 的 IDFA/IDFV 生成证据保留原版本，普通应用采用上述用户可选身份策略。

<a id="r06-指纹访客登录资料需要保存各自真实结果p0"></a>
### R06 设备登记、访客与登录复用各自的真实回执

**证据**：8.89 BFCDeviceToken.localBUVID 0x115fd6c80生成64字符本地指纹；
requestUpdateBuvidWithData 0x115fd7ed0 的Protobuf经AES-128-ECB/PKCS#7，再以包内
RSA包装随机key的hex UTF-8，返回data.bili_deviceId。currentBUVID优先服务器值。
Guest.load 0x11605a5a0只在0/-2登记，setup及DidBecomeActive调用；失败可在后续active再试，
不是每次前台无条件登记。serverBUVID getter有120秒节流，非空成功延至请求发起时+86400秒，
失败保留旧值；expiry为内存状态。GuestInfo 0x11605a924 是独立JSON→CBC/key=IV；登录DeviceToken 0x116058af4又是另一份
JSON。SMS 0x116048e54将跟踪BUVID→buvid/local_id、本地指纹→bili_local_id、当前指纹→
device_id、guest响应→device_tourist_id。既有日志2.14/gRPC Device14与响应指纹相等。
**补充（8.89 静态，T1 第二轮 R2-4）**：指纹 payload 的权威描述符是
`+[BFCDeviceIosDeviceInfo descriptor]` 0x115fd895c（`mov w6,#0x36`⇒**fieldCount=54**、
storageSize 400、messageName `IosDeviceInfo`），字段号 1..54 已逐项列出；赋值点集中在
`-[BFCDeviceToken generateInfo]` 0x115fd5b54 的 54 个 setter，**51 项已映射到具体来源**
（os/platform/osver/t/idfa/idfv/model/brand/oid/freeSpace/battery/root/brightness/languages/
totalSpace/network/countryIso/sysname/memory/name/track/appId/appVersion/appVersionCode/mid/
chid/fts/buvidLocal/corefile*/systemvolume/strBattery/isRoot/strBrightness/strAppId/freeMemory/
deviceAngleArray/biometric/biometricsArray/lastDumpTs/batterystate/batterytemperature/camcnt/
camlight/campx/cpucount/kernelversion/screen/sim/issimulatorIos 等），**isVpn/ip/userAgent
在本 payload 类内无赋值点**（不是全镜像：`setIp:` 全镜像 9 处、`setUserAgent:` 29 处，
接收者均非登记类；详见 team-c3 S1）。警告：姊妹类 `-[BFCAccountDeviceToken generateInfo]` 0x116058d3c 构造的是
另一个类 `BFCAccountDeviceInfo`，字段重名；按 `_objc_msgSend$setXxx:` 全镜像计数会被污染，
本项以上述描述符与 0x115fd5b54 的站点表为准。

**NeoBili 当前实现**：`AppDeviceRegistration` 用已实现的本机资料子集提交加密 fingerprint 并缓存真实
`bili_deviceId`；`AppGuestRegistration` 独立获取公钥、登记并保存 `guest_id`。
短信登录复用可用设备/访客结果，公共请求与行为日志使用同一份登记快照。
生命周期及当前差异见[网络与账号](../../architecture/accounts.md)和[本机校验范围](validation.md)。

**剩余范围**：完整 54 字段、可选安全资料及当前服务器的所有风控分支仍待有条件的运行验收。

<a id="r07-ticket-是独立服务且有启用边界p1依赖r06"></a>
### R07 App ticket 已接入缓存、续期和响应失效处理

**证据**：8.89 BFCTicket.onTicketReq 0x100096170返回旧值并异步刷新，默认提前量
1800秒；x-ticket-status=1触发更新。GetTicket签名0x100096d40组合Device metadata与
排序context，HMAC输出32bytes。回调按回调时间+ttl保存，失败保留旧值。Ktor安装ticker
并不证明Enable GInterceptor的全部上游开启，不能推导所有HTTP必带ticket。
**补充（8.89 静态，T1 findings P1）**：`ticket_enable` 等配置由 BFCTicketRuntime
`sub_10009AE38` 读入（阈值 `ttl_about_to_expire_threshold_in_seconds` 默认 1800、
`get_max_tries` 默认 4、jitter 默认 1、retry base/max 默认 1/15）；“执行 enable”的输入
就是 cfg+0x10 的实验命中（`sub_100099108` 0x1000991ac→TicketInternal feature 位），
TicketInternal 全镜像唯一构造点是 `-[BFCTicket init]` 0x100095ec8，`presetHitValue=1`
只是无分组时的预设值、不是命中。材料门禁：cfg+0x11 命中才加
`BFCDeviceToken.fingerprintMaterialBin`，cfg+0x12/+0x13 命中才加
`BFCSecurity.gaiaMaterialBinWithIgnoreNormal:`。`ticket.get_max_tries` 只写入 cfg+0x30，
7 处配置槽加载点全枚举后无 `+0x30` 读取⇒本样本重试上限未被消费。
**gateway 次序（8.89 静态，T1 第二轮 R2-1，含重要更正）**：注册是单一漏斗——
`+[BFCApiGateway registerClass:]` 0x11609916c → `appendClass:` 0x11609919c 锁内只 addObject
（无排序/去重），每个 request 先复制全局 registry 再遍历；Resolver 侧 wrapper 0x10513162c
（621 个调用点）→ 0x1051362F0 建 `LazyDependencyProvider` → 两条 append 路径；多绑定集合
读取 0x105134860 按数组顺序 append，无二次排序；root 作用域构造 0x1051313a0/sub_105133CE8
用容器 `*(0x1204ced28)` 的组数组逐个调用注册见证。**模块内次序可定**（组数组 append 次序与
组内 (context,witness) 次序），**跨模块次序不可静态定序**：组件由运行期元数据/witness 装配，
模块组件类本身没有任何 classRef 或 ADRP+ADD/ADRP+LDR 引用，镜像里不存在静态顺序表。
更正：早先设想的“334 项组件表”（0x120272648 起）经 ADRP+ADD 区间扫描与三条全域指针扫描均为
**0 命中**，而同方法对 184 项 runnable 表有阳性对照命中⇒该表在本镜像无任何代码/数据引用，
只能当名字索引（token 序号=i+1），**不能用它推注册/执行次序**，也不要用“按类引用点回溯组件
创建处”这类静态方案。
**ticket 缓存 reset 边界（8.89 静态，team-c3 S3.5）**：单例槽 0x12027d090 全镜像恰 4 处载入（0x100096208 `-[BFCTicket init]`、0x100096764 `+[TicketPrefs shared]`、0x10009943c startup、0x100099c10 成功保存腿），无 STR / `objc_storeStrong` 写点 ⇒ 静态上没有登录/登出 reset 该缓存的路径；跨账号是否复用同一份缓存需运行期/9.13 抓包。

**NeoBili 当前实现**：`AppTicketService` 用同次 Device protobuf 字节签名获取票据，缓存于 Keychain。
公共 App 请求携带可用票据；剩余不足 1800 秒时异步续期，失败保留旧值并退避。
`HTTPTransport` 与 SMS 传输按实际发送的 ticket 处理 `x-ticket-status=1`，
账号代际及 BUVID 控制存储作用域。

**剩余范围**：可选安全 context 未填。历史三组 GET 的具体结果保留在[本地对照](device-comparison.md)。

<a id="r08-卡片追踪到观看关联已接通但曝光上下文不完整p0p1"></a>
### R08 卡片追踪随真实路由进入观看上报

**证据**：9.13已有样本按原始param/track_id关联首页卡片、点击与观看；8.89专用点击
直接取model.track_id，不能套HD args fallback。

**NeoBili 当前实现**：卡片保留 `track_id/report_flow_data`，返回时绑定登录会话。首页实际点击触发
`RecommendationClick` 并传递路由；`NowPlayingStore` 将 entry 交给播放器。
[PlaybackReportingCoordinator](../../../NeoBili/Application/Player/PlaybackReportingCoordinator.swift)
组合观看事实与来源字段，`AppWatchProtocol` 编码，`BiliAPI+History` 补账号及视频标识。
换登录会话后清除旧追踪字段，保留入口映射。点击上传异步执行，播放另受详情和播放准入控制。

**剩余范围**：当前支持普通视频路由和首页静音预览；Story 专属入口及其事件未接入。

<a id="r09-点击字段不能直接套某套通用模板p1"></a>
### R09 点击保留已解析的卡片字段和封面实验字段

**证据**：8.89 SmallCoverV2专用reporter 0x101a974c0初始22字段**没有position**，
直接取model.track_id，OptionalString关系/素材编号；extra_rpt_fields/additionalDic可覆盖。
HD HomeData 0x10df30fd8另有position和track_id fallback。两条链不可混用。

**NeoBili 当前实现**：`AppRecommendationCard` 保存根字段、`args.tid/rid`，并从 `extra_rpt_fields` 白名单
提取 `cover_id/is_cover_test`。`RecommendationClick.make` 校验普通视频来源、登录会话
和非空 track，加入 `event=card_click/event_policy=0/page_from=1`。
字段上限为 40 项、单值 4096 字节。直播/图文卡和预载没有该点击事件。

**剩余范围**：其余扩展字段及未知的内联播放枚举保持缺省，新增字段需明确来源与版本。

<a id="r10-展示及每段可见时长的采集和发送p1依赖r08r11"></a>
### R10 曝光按有效视口和响应门槛计量

**证据**：9.13已有show/duration事件走realtime、policy=1；8.89 RealExposure/ExposureV2
0x103eb9998、0x101b6cf80以可见比例阈值和minimum结算，写card_start_time/card_end_time
Unix毫秒。后台/终止会结算；默认start/end各0.8、minimum默认0秒，但可远程覆盖，普通show
阈值与duration不同。VC0x101a37618/0x101a37628的出现/离开经VM.isShowing与
splashStyle==0生成真实出现/离开；raw8回调0x101b60644移除duration contexts并
结算，返回重新建段。raw36/inactive受配置控制，raw33/background与raw37/terminate
直接结算且仍受minimum门槛；普通show去重池是否重置未闭合（清除链锚点 0x101b60644）。

**NeoBili 当前实现**：[HomeFeedCollection](../../../NeoBili/Features/Home/HomeFeedCollection.swift) 计算卡片与有效
视口的相交面积比例；选中标签、弹窗、播放页、窗口和前后台状态共同控制采集。
`RecommendationExposurePolicy` 解析 show 和 duration 的独立门槛，默认 show 要求非空
可见区域，duration 开始/结束比例均为 0.8、最小时长为 0。离屏或状态切换结算时段，
show 去重，重新可见另记时长；事件由 `AppBehaviorReporter` 发送到 realtime 通道。

**剩余范围**：当前测试覆盖比例门槛和生命周期；官方其他卡型的曝光集合仍按样本分别研究。

<a id="r11-position-必须保存来源不能一律按ui行号生成p0阻挡曝光定稿"></a>
### R11 曝光位置保留过滤前的原始下标

**证据**：8.89 HD回调0x10df59978按原始单批输入下标+1，过滤项占位；Swift
DataFactory 0x101a3e1dc→0x101a4340c先compactMap为CardData，再进入 0x101a3e5a4，
无report model的成功项仍占号。
**证据收敛（8.89 静态；R11-1 已定稿，独立复核 g2 Q3 后第二轮定案）**：0x101a3ed5c 那个
“+1 append 循环”**不在** 0x101a3e5a4（函数体 0x101a3e5a4–0x101a3ebf4）内，而在
sub_101A3ECAC（0x101a3ecac–0x101a3eebc），是 Swift 标准库 sort 的归并 run 记账——
0x101a3ecd4 `bl _minimumMergeRunLength(_:)`（0x107c2b8b0，符号 `_$ss22_minimumMergeRunLengthyS2iF`）、
0x101a3ed18 `bl static_Array._allocateBufferUninitialized(minimumCapacity:)`、0x101a3ed28/30
把 [sp+0x18] 初始化为 `__swiftEmptyArrayStorage`。故 x28=run 起点、x8=x28+1 只是单元素 run
边界比较、x27=x24+1 是 run 数组 count；`stp x28,x23,[x8,#0x20]` 写的是 sort 自己的
(runStart,runEnd) 临时缓冲（stride 0x10）。该函数体内无任何卡片 setter，排序结果唯一写出点是
`_TtC14BBPegasusSwift15FeedMixinAction.tmpCardDatas`（ivar 0x7a8，0x101a3df28/0x101a3df44）。
⇒ 该循环**无卡型门禁、不写 position/flush_idx/report_flush_idx**，不能再当作“从 1 编号”的证据。

真正的 1-based 递增在 sub_101A3E5A4 自己的循环：0x101a3e95c `add x26,x26,#1`，把 1-based 序号
作 x0 传给 CardData 的协议 witness 表 **+0x40**（0x101a3e98c `ldr x28,[x22,#0x40]`、
0x101a3e9b0 `blr x28`）；门禁是 CardData ivar +0x20 非 nil，递增无条件。该 requirement 对应哪个
字段属间接派发，仍未闭合（残余 R11-2；witness 槽 0x101a3e98c、间接调用点 0x101a3e9b0）。

未识别card_type返回41是哨兵，不是有效枚举case；合法unknown
为0。SmallCoverV2 duration builder0x101a7b6a0直接模型Optional值（含0），fallback才
flushIndex+1。Optional值来自associated object BBListPegasusSettings_flushIndex，不是已证明直接
解码的服务器位置。普通show、专用click分别有自己的规则。网络普通refresh和loadmore
都走同一 DataFactory 路径（0x101a3e1dc→0x101a4340c→0x101a3e5a4）；该路径内 +1 循环的
写入字段与卡型范围见上方残余。兴趣选择render是独立分支。缓存恢复也经普通render、
compactMap后进入同一路径；replumeFlushIndex目前只证实BannerV8替换调用，不能泛化。
9.13可匹配样本的show=原下标+1、
duration=原下标+2是观测关系，不证明完整跨卡型算法。
HD2 getCurrentTimestamp0x10df9166c为NSDate epoch秒向零转Int64的String，刷新/分页
解析各卡分别取值，banner复制父值；同秒卡可同timestamp。report_flush_idx仍是单次
输入ordinal+1，保留旧卡保留其旧字段。timestamp不是唯一请求代际；完整标识还依赖
track/ordinal/App状态，静态精度不等于已观察到运行时碰撞。

**NeoBili 当前实现**：`AppRecommendationPage` 在解码原始 items 时保存 1-based `recommendationPosition`，
广告、坏卡及本地过滤留下的间隔保留。show 使用该位置，duration 使用位置加一；
布局补位和去重保持原卡片字段。当前没有单独的官方批次编号或 CardData witness 字段。
`HomeViewModel` 用 loadID、取消状态和账号会话控制响应及游标回写。

**剩余范围**：8.89 Swift CardData witness 的字段归属仍是研究问题；当前原始下标策略已实现。

<a id="r12-日志公共字段与事件缓存策略有明确差异p1"></a>
### R12 点击与曝光操作日志分别持久化

**证据**：8.89 Neuron0x1161ea030在trackQueue编码时读取公共信息、递增sn；描述符
有osver/fts/bilifp、network/logver、eventCategory/pageType/sn等。fts来自首次Neuron初始化
的持久毫秒值，不是设备firstRunTime。失败0x1161ec850更新retrySendCount，保留原事件；
发送刷新uploadTime，加Neuron-Events。HTTP200即删缓存，此层不解析body。9.13重启补发样本
显示原事件会话与当前上传会话可不同，不能按上传时间给动作重标。
**补充（8.89 静态，T2 findings C-8/C-9）**：`Configuration.init` 0x1161ee904 默认
batchSize=120、packageSize=30、minPackageSize=15、interval=3、maxInterval=30、
mobileQuota=3145728、waitingThreshold=20、waitingMinutes=10、**expireDays=7**；
`updateCacheItem` 0x1161ec850 只把 `retrySendCount` 加一后重序列化，附近无上限比较，
按 `maxRetry*`/`retrySendCount` 全镜像检索也未见事件缓存侧的静态上限 ⇒ 应把“次数上限”
写成“未发现静态上限”。旧 V2 侧再次触发也已闭合：`addReportWithItem:` 块 0x1141c66f0
在 count>=20 时直接 `trySendReport`、否则 3 秒 `dispatch_after` 一个可取消 scheduler。

**更正（独立复核 V20/Q4，反证前文）**：据单个 selref 槽 0x11f6fe798 零引用写成
“`setCanceled:` 本镜像不主动置位”是结论性错误——同一 selector 可有多个 selref 槽，
单槽零引用≠无调用。共享 stub 0x11754e3c0 有 8 个调用方，其中 0x1141c6808
（`addReportWithItem:]_block_1` 0x1141c66f0 内）与 0x1141c7124
（`reportSuccessWithCode:]_block_1` 0x1141c6fac 内）在遍历 scheduler 数组元素后
`mov w2,#1; bl _objc_msgSend$setCanceled:`。实际语义因此相反：**镜像会在重发成功路径主动
置 canceled=1，取消挂起项的 3 秒延迟块**，方向仍是防重复触发，但不是“不主动置位”。
这条语义只属旧 V2 文本日志通道：它不改变 Neo 点击队列也没有旧包重试节奏的判定，
也不能把“3 秒后必发”套到 R17 的观看报告发送器上。
**回执（8.89 静态，team-c2 §7/§10）**：`-[BFCNeuron report:didFinishTask:data:error:]` 0x1161ed618 中 error 或非 NSHTTPURLResponse → `updateCacheItem:`；statusCode==200 → `deleteCacheItems:`（0x1172afa40）并跳过 update；449（`cmp #0x1c1`）或 500–599 → `handleFlowControl`（0x11734e600）后 `updateCacheItem:`，最后转 delegate。旧链 001365 同属 Neuron 事件 id，不是独立 HTTP 回执。

**NeoBili 当前实现**：`AppBehaviorEncoder` 编码设备、账号、请求/启动会话、版本、实际 fingerprint、
eventCategory 和持久事件序号；category 2/3/9 分别承载点击、曝光和播放器资料。
未知 osver/fts 等字段保持缺省，上传使用当前凭据，事件保留发生时快照。
`RecommendationClickReporter` 保存最多 100 条/24 小时，按账号代际过滤；新点击及 App
首页请求触发 flush。`AppBehaviorReporter` 使用独立的 `BehaviorQueue/pending.json`，
后台检查点与发送准备时落盘，恢复按账号、BUVID 和时间过滤；限制 100 条、24 小时及
约 512 KiB 的估算内容，每批最多 20 项。即时/普通事件分别合并等待 0.25/3 秒，
前台激活也触发 flush；发送前持久移除，只恢复明确发生在连接建立前的失败。
两者都使用 RecordIO+gzip 和实际记录数量；协议版本与应用发布版本分别维护。

**剩余范围**：当前实现采用本地有界队列和失败策略，官方完整字段、缓存调度与服务端消费另有版本边界。

<a id="r13-观看事实与历史位置已分开触发补全仍须逐项对照p1"></a>
### R13 观看时长、倍率累计和历史位置分别计量

**证据**：9.13已采集开始/结束、暂停/后台/历史入口；8.89Context0x114885bcc输出
累计计时和位置，MetaInfo0x114886d4c另含播放模式、网络、自动播放等属性；多数赋值方未闭合。
历史helper0x104a80fcc可将距结尾<=4秒的progress改-1，历史服务使用媒体位置而非观看累计。
8.89普通HeartBeatServiceV2后台入口0x11488b0b8还要求!isSuspend、已准备、有效且
未completed；reportPolicy bit2=0仅stash结束保护快照，bit2=1才playEnd。前台入口
0x11488af54在有效且未completed时清stash；无效且bit2=1才恢复tracker资料并尝试
开始。Inline可覆盖service默认policy（写入口 0x1148890dc 等），状态raw值尚未全部映射业务名称，不能断言
所有暂停都结束或所有后台都发finish/前台都发start；这些是8.89方法证据。

**NeoBili 当前实现**：`PlaybackWatchProgress` 只累计首帧后、播放中、非缓冲的真实推进。
`played_time` 记录经过时间，`actual_played_time` 按每段倍率累计，当前位置、最大位置
和暂停时长分别保存。首次累计 5 秒、随后每 15 秒同步历史，暂停/退出可结算短段。
移动报告只发送真实起播后的全零开始及结束；历史 checkpoint 独立发送。App 凭据与
有效 aid/cid 就绪时采用 App 通道，仅 Cookie 或 aid 未齐时使用网页历史。
后台本地续播保存和服务端报告分别由所属生命周期管理。

**剩余范围**：官方旧包的分段截断、全部播放状态及应用级活动事件未逐项复刻。

<a id="r14-过滤去重和预加载会改变展示不能被误算成服务端推荐p1"></a>
### R14 过滤、布局和预载保持各自职责

**证据**：8.89 buildObjects0x10df5a28c有本地合并、刷新卡和数量/偶数处理；Swift转卡
先过滤失败项。没有证据表明客户端另做个性化重排。

**NeoBili 当前实现**：解析层排除广告、坏卡和不支持的卡型，视频要求 `can_play=1`；原始游标在过滤前保存。
推荐过滤后再做跨页去重，刷新可保留旧卡；空过滤批仍推进有效游标。
列表地址预取默认关闭，开启后延迟取接口元数据，取消按消费者处理。
首页大卡静音预览独立要求 80% 可见并停留 250 毫秒，取流成功后创建播放器；
离屏、遮挡、后台和换会话停止。具体布局和过滤规则见[列表与图片](../../architecture/lists-images.md)。

**剩余范围**：首页离线磁盘卡片兜底未实现，见 R20。

<a id="r15-不感兴趣上下文最小化且旧卡缺来源代际校验p1"></a>
### R15 不感兴趣保留卡片归属并校验来源会话

**证据**：8.89 params0x10df563d8条件合入track_id、from_spmid、UP mid、rid/tid、
reason/feedback及广告字段；extraParams最后覆盖。此处mid来自args.up_id，不是登录mid。

**NeoBili 当前实现**：`RecommendationFeedbackOptions.requestContext` 保存卡片来源会话及已解析的归属字段。
`feedbackOptions` 在响应绑定和提交时核对 `PlaybackEntry.loginSessionID`；
`feedbackParameters` 只转发 `track_id/from_spmid/mid/rid` 白名单，按理由类型选择
`reason_id` 或 `feedback_id`。提交及撤销均为零重试写请求，旧会话卡片被拒绝。

**剩余范围**：其他负反馈扩展字段按明确协议证据逐项接入。

<a id="r16-公共登录播放和启动会话要分别命名p1"></a>
### R16 请求、启动、登录、页面和播放会话独立

**证据**：8.89公共session经BFCDevice.getSessionId 0x115fd3960/Kntr lazy复用，
以16随机字节的FNV-1a低32位转小写hex、不补零。Ktor GAppRequest consumer
0x10aac466c→0x10a9b285c实际写克隆请求HeadersBuilder.session_id，不是query；
该写入与公共设备头取同一进程lazy来源，最终hook启用/覆盖范围仍未闭合（Ktor 门控键槽 0x120c5e410；native listener 在 0x1000aaea4 跳过 type2）。短信UI
helper0x104cf8968对BUVID+
FRINTA毫秒取大写MD5，发送/重发/提交复用入口值（T1 补充：该 helper 的全二进制 BL 调用点
只有 4 处——`+[Login updateLastLoginInfo]` 0x104cec0c8、`+[StrictLogin
overseaForceStrictLoginWithCompletion:toolView:]` 的 0x104d1a710/0x104d1b0a4、StrictLogin
类内 0x104d1d820；objc_msgSend 派发不在扫描内）；播放Context.setupSession0x1148859c8
setup阶段优先metaInfo.sessionID，否则createSessionID0x11487f6b8取BUVID+NSNumber
毫秒文本的MD5。但trackMetaInfo0x1148891e8先取tracker.playerSessionId，非空显式
session会写入原metaInfo再copy/setup，因此该入口优先tracker缓存，不能只归为业务字段。
tracker manager0x11487f53c为实例缓存，reset0x11487f5c8只清旧值、日志参数不作新值；
inherit0x11487f630非空时保存。普通非shared场景完成及playerDestroyed假→真可reset，
rebindSessionID与graft attach另有继承路径，重建对象不必意味着新session。
Neuron启动会话与这些编号分别解释；BFCActiveReport.sessionId0x115fcfe7c为进程
once值，活动段id/eid在foreground另调用bfc_uniqueString0x1167a5928生成，两个
角色不互换（见R21）。9.13短后台保留、进程重启更新的样本不证明生成算法。

**NeoBili 当前实现**：`DeviceIdentity` 的公共请求 session 为 8 位随机十六进制，换登录或退出时更新；
独立的 8 位 startSession 在普通前后台切换中保留。短信尝试使用小写 UUID32。
页面及播放器分别创建 32 位 session，暂停续播保留播放 session，重新进入或重播重建。
`AppRecommendationSession` 另持有 cold/hot、banner 与账号会话。

**剩余范围**：官方 tracker 的跨容器继承及 App 活动段 eid 未接入。

<a id="r17-观看结束报告没有官方旧包的持久补发层p1"></a>
### R17 观看历史发送器保持内存队列

**证据**：8.89 ReportManager.reportWith0x114887940有内存/文件缓存分支，stash保留
结束快照，loadFileCache可合入重发；reportTrigger0x114888230串行发送，失败再等5/10秒
最多重试两次。postApiWith0x1148888b0发送前去hash/isStart、补当前idfv/idfa等；回执含
HTTP200 error分支。恢复caller已闭合：BBPlayerCoreModule.onModuleInitializedConfig
0x1147ddd4c取sharedManager并loadFileCache，位于后续hasLogined检查之前；不证明
未登录旧报告必能发出。模块初始化实际送达、reachability、缓存异常恢复/过期、跨账号
策略与9.13同链仍未确认（reportPolicy 写入口 0x1148890dc 等）。回执ts另见R22。

**NeoBili 当前实现**：`PlaybackWatchReportSender` 按账号、视频及分 P 串行处理，合并同一播放 session
相邻的历史 checkpoint，保留 start/finish 边界。发送前移出队列，失败不恢复，
`postApp` 为零重试；账号会话校验阻止旧队列使用新凭据。
该队列与 R12 的持久行为日志队列分别管理。

**剩余范围**：进程被终止时，尚未生成或发送的观看末段没有磁盘补发。

<a id="r18-公共身份头locale和网络资料需按通道补齐p2身份部分依赖r06"></a>
### R18 公共身份与首页专用请求头分层组装

**证据**：8.89 BFCApiSignHelper.baseParams0x11609c68c分公共platform/device/build/
locale/statistics，NetParamImp有GuestId/SessionId和个性化设置getter；
**访客标识（8.89 静态，T1 第二轮 R2-5）**：`guestId` 偏好只有一个写入者——
`-[BFCAccountGuest saveGuestIdWithData:]_block` 0x11605a474（注册成功保存链，带阳性对照，
另有 Moss 模型同名字段与 stub 别名已排除）⇒**登录/退出路径不写 guestId 偏好**；
`guestIdCanAddToNetCoreHeader` flag 变化也不会重选已注册 class（注册只在 ApiClient
moduleInitialize 遍历注入数组，0x1049bea1c–0x1049bea3c）。官方 guestId 因此跨账号切换
持久保留；Neo 没有该字段，也不能声称“退出即清 guestId”。其中
`c_locale`←`+[BFCApiConst clientLocale]`（0x11609c814，非 nil 才写 0x11609c850）、
`s_locale`←`+[BFCApiConst sysLocale]`（0x11609c860/0x11609c87c，同样非 nil 门禁），两者最终
字符串来自注入服务的运行期 locale、静态不可得（T1 findings P4）。**这一层是原生
NSDictionary 值层，字节编码在下游；不要与尾部 Kotlin `KLocale` request hook 写
`x-bili-locale-bin` 合并成一条结论。**原生callOptions helper0x115e070e4→0x115e06c20
复制缓存Metadata并刷新accessToken，构建fresh Device/Network，将三个PB.data写入
metadata-bin/device-bin/network-bin；extraHeader先合入，再由非空buvid/token/trace
覆盖对应头。Metadata缓存初始化0x115e0d0d4取客户端配置，不能混同fresh设备/网络。
Service初始化保存options，defaultAutoRPC仅复制，不能把helper每次取值说成每次RPC
都重读；KMoss/GrpcEngine的typed binary与flattened Base64路径、注册覆盖分别核对。
完整字段取值、引擎选择与transport覆盖仍未闭合（helper 0x115e070e4→0x115e06c20）。9.13已采集App/系统locale可能不同，locale附加5/8与network-bin
嵌套字段语义、地区头来源仍待确认（device/network PB 写入点 0x115e070e4）。已有gRPC Device14与登记指纹关联不证明所有请求
应携带同一完整metadata包。
独立Ktor Locale RequestHook 0x10aae9400克隆请求，从KLocale序列化值写
x-bili-locale-bin，采用受Enable GInterceptor门禁；header setter仅write once显式
true且同名头已存在时保留，否则替换，空String无额外门禁。它不是已证Swift
MetadataStore adapter，也没有证据表明普通首页采用同链；序列化byte变体仍待证（hook 锚点 0x10aae9400）。
KntrTranslation的userEnabled与alwaysTranslate分开：false开关或SYSTEM locale使
派生值false，否则按dd_localization_language_config的localeIdentifier exact匹配，
first wins，无配置/匹配为false；locale与开关变化均重算派生flow。user-enabled经
序列化property写NSUserDefaults的translation suite，此链不拼MID；**外部清理已由 G3 §2
闭合为不存在**（setter 0x105c2f870 仅 2 个调用方、无 Logout/账号观察者，
`removePersistentDomainForName:` 只命中 UASDKStorage），setter 返回时是否已落盘见
0x105c2f870；配置JSON字段、顶层导航可达性及精确提交时序属官方实现细节，
在 Neo 未实现内容翻译前不构成实施前置（见[已闭合与残余](maintenance.md#已闭合)）。
实际候选行与switch的onClick先写remember编辑holder，再记录incoming编辑值；
DisposableEffect离开composition时cleanup才读holder当前值交全局setter。因此点击
日志可暂时不同于请求生效偏好，always_translate_switch也不是派生effective值，
不能将recomposition当点击、所有导航/消失名称当已证提交入口。
**更正（8.89 静态，team-c3 S4.2）**：账号通知不走 `NSNotificationCenter`——`BFCAccountNotification` 用自有注册表（`addActionObserver:type:block:` 0x11605e5a8、`addUpdateObserver:type:block:` 0x11605e7cc 等；已枚举注册点 70+25+6+7+1），对 `addObserver:` stub 扫描只会命中无关 KVO/通知中心调用，因此“用 addObserver stub 收全账号观察者”不是可行下一步。
设备决策PropertyCenter也须分开：账号通知调用propertyChangedFor("mid")后异步
按name查entry，eligible时重求值，仅值变化写该name缓存，缺资格/provider时删该
name，再发property name事件；不是清全部决策cache。账号callback返回不等Bool
决策已更新，不取消HTTP或迁移once client；事件到依赖结果缓存失效仍未闭合（DD 通知 accessor 0x1051306d4；官方侧该通知无 addObserver 消费者，见 G3 §5）。
DD原生响应gateway0x100135830需HTTP response、本地request-header字典及响应头
非空，dd-v缺失/nil不更新；存在值优先String，其次Int，均cast失败生成"0"，非空
才以force=false/from=http触发update。空String跳过，"0"触发不等于业务ACK或更新
成功；本native分支及注册不证明所有引擎同样采用，缺header也不是清配置指令。

**NeoBili 当前实现**：公共 App 头包含自身 BUVID、会话、locale 及可用的 guestid、ticket、Device protobuf。
网络类型来自系统快照；gRPC metadata 使用同一账号上下文。首页 `alignFeedHeaders`
在最终合并后移除 Referer、aurora-zone、device-bin，加入 CN 的 IP/法定地区头和 redirect=1。
当前界面语言偏好由 [AppLanguage+Preferences](../../../NeoBili/Application/Settings/AppLanguage+Preferences.swift)
管理，下次启动生效；网络 locale 使用固定模板。

**剩余范围**：动态地区来源、内容翻译、Ktor 实验切换和 dd-v 决策版本同步未接入。

<a id="r19-app签名的保留字符与旧包存在差异p1当前版本待验证"></a>
### R19 签名与传输共用明确的编码规则

**证据**：8.89 BFCApiSignHelper.createSign0x11609ce34排序键、对值description编码后
计算摘要；_encodeUrl0x11609d68c明确转义`!*'();:@&=+$,/?%#[]`。
S1新增Ktor CommonParams消费链0x10a9aca6c经排序器0x10a9b38b8及编码器
0x105d0b070(false)，键和值仅保留ASCII字母/数字/-._~，空格%20、加号%2B、星号%2A，
MD5为小写hex；多value逗号合并。Enable sign缺省true，ts缺失才补且有秒/毫秒配置，
不等于native HttpSign adapter覆盖范围已闭合。
**补充（8.89 静态，T1 第二轮 R2-2/R2-3）**：native listener 在旧 BFCHttpTask 分发处按
`requestType` 门控——0x1000aaea0 `cmp w8,#2`、0x1000aaea4 `b.eq 0x1000aafcc` **整体跳过
listener 遍历**，即 Ktor 请求（type2）不走 native HttpSign listener；native HttpSign 自身的
门控是 `dd.http_sign_buvid`（0x117776190），与 Ktor 的 Enable sign/common params 无关。
三个 Enable 键（GInterceptor @0x11c6434d2、common params @0x11c6433b2、sign @0x11c6433f2，
都是 Kotlin UTF-16 常量）共用键槽 0x120c5e410：读取 6 处、写入 0 处（两种扫描形式并带阳性
对照），GInterceptor 缺省 false ⇒ 本镜像里“缺省值”只是缺省，不能当运行期生效状态。
同批的另一处门控同样只是读：`bfc_http_disable_ktor` 字面量全镜像只有 1 处读取，
而阳性对照 `bfc_http_disable_common_params` 有真实写入点 0x105034bdc ⇒ **Swift 侧没有业务
enable writer，这些键由 Kotlin 侧创建/写入**，静态只能给出“本镜像未写”的边界。
[社区App签名页](https://janson20.github.io/bilibili-api-collect-mirror/docs/misc/sign/APP.html)
提供排序与摘要线索，但不同语言示例采用不同编码器，Swift示例使用.urlQueryAllowed，
不能视作当前iPhone逐字节规范；其跨平台appkey示例也不能直接移入当前身份配置。

**NeoBili 当前实现**：[AppSigner](../../../NeoBili/Data/Networking/Identity/AppSigner.swift) 排序字符串键，保留空值
等号，签名与传输共用编码后的 query。默认保留 `-_.!~*'()`；登录续期显式选择
`nativeEncoding=true`，只保留 `-_.~` 和字母数字。旧 sign 被替换，ts 使用调用时间。
离线 golden 验证和历史样本的适用范围见[本地校验](validation.md)与[本地对照](device-comparison.md)。

**剩余范围**：协议未提供字符串字典以外的数组输入；新增端点应明确选用的编码模式。

<a id="r20-首页磁盘兜底不同于保留内存旧卡p2账号来源隔离为实施前置"></a>
### R20 首页保留内存旧卡，尚无磁盘卡片兜底

**证据**：8.89普通refresh失败0x101a5b3b0仅在缓存开关开启、flush属于mask0x1f7dff、
VM.cards空且open_event不为cold_back时调用0x101a54d44读兜底，不是发起网络重试。
正常响应同样受缓存开关与上述flush范围门控，在转卡之前经0x101a5a13c工作副本给extra_rpt_fields加is_cache_local_data="1"，
config剔除scene_uri/interest_guide后写datas/config。scene为tm.recommend.0.0，key
0x101a5a02c取发起查询时账号mid和style，version为VM.diskCacheVersion；expirationTime=0
实际后端语义未证。读回0x101a54878仅weak-load VM，未见MID/request-generation比较。
有效JSON即使datas/config缺失或类型不符也退空数组/字典并返回非nil；缓存恢复再走普通
编号/render，不等于一定显示了卡。Producer.subscribe0x1050e78d0两路分别返回ScheduledItem或SinkDisposer，析构只释放
成员，Optional替换/释放均不自动dispose；只有显式调用才取消，dealloc确有此调用。
普通refresh0x101a4893c在isLoading=true时拒绝新刷新，不dispose旧cacheRead。最终
FeedUpdater apply在默认分支受semaphore串行约束，实验true可绕过wait；commit点
0x101a44560/0x101a447f0只weak-load捕获updater后写datas，未见账号/代次或
before==current检查。串行和weak引用不能使旧响应自动失效；活VM切账号/替换、
外部diff引擎与额外取消防串扰仍待追踪（写入点 0x101a44560/0x101a447f0），不能宣称已实测跨账号污染。

**NeoBili 当前实现**：`HomeViewModel` 请求失败保留内存卡，成功的空过滤批推进游标。
当前没有官方式 datas/config 磁盘恢复、账号+style 缓存或 `is_cache_local_data` 标记。
网络响应按 loadID、账号会话及取消状态保护。

**剩余范围**：离线首页属于尚未实现的可选产品能力，采用时需定义缓存版本、来源和账号生命周期。

<a id="r21-app启动与活动段缺实现旧包再次提交不应直接复制p2需-913-样本"></a>
### R21 应用生命周期已驱动队列，活动段事件未接入

**证据**：8.89 BFCActiveReport.applicationDidBecomeActive0x115fcfefc记录旧事件与
Neuron启动事件，first_open本地flag在事件生成后立即写true，不等网络回执。
foreground0x115fd04dc读取有end的旧app_active，可能再次生成同一eid的duration，
随后新建/覆盖活动段；background0x115fd0e40以字符串"0"结束并保存end，terminate
0x115fd0e4c以"1"生成结束但不保存新end。0x115fd0e58没有已有end/已上传复核，
无end记录在foreground被替换，不能称完整崩溃恢复；下游去重与9.13同链没有验证证据。
首页模块回调0x11597d438以once同步枚举，亦可由默认3000ms延后入口触发，不要求
推荐成功；homeTasksStart/Finish量的是同步枚举，不是所有异步任务或网络回执。
Swift feedDataChanged/raw24消费者0x101a4a164只检查VM.dataFactory.datas与本地
layout flag，非空调用homeFinish:YES并置flag，空调用NO而不置flag；不是业务code
消费者。相邻ops.misaka.app-launcher是独立技术诊断，不作为推荐兴趣事件。

**NeoBili 当前实现**：[NeoBiliApp](../../../NeoBili/App/NeoBiliApp.swift) 将后台/前台状态传给推荐会话及
`AppBehaviorReporter`，触发检查点、恢复发送和设备服务检查。根页面与视频页另保存本地续播。
当前编码器支持点击、曝光及播放器事件，没有 app_active、first_open 或活动段持久状态。

**剩余范围**：官方启动/活动业务及重复提交语义保留为研究材料。

<a id="r22-心跳时间回执缺实现公共时间辅助与观看计时须分开p1辅助来源-p2-需-913-样本"></a>
### R22 移动起播回执按播放会话更新时间

**证据**：8.89 reportTrigger0x114888230对同步发送快照仅index0成功且apiCallback非nil
时把serverTs排main，0x114888560调用捕获callback；Context回调0x114886910弱取原
context后写start_ts（0x11488692c），没有session/hash/当前start匹配或ts>0门禁。
发送前out ts初始化0，HTTP200错误分支也可判成功，因此callback不保证取得正时间。
setupDefaultConfig0x114885aa4分别取NSDate、BFCServerTimeChecker.realTimeInterval，
wire start_ts仅实验命中才用后者，否则0，后续可由该回执覆盖，不能统称全局校时。
独立时间辅助0x115dab238先用BFCServerTime，次选boottime/slinterval缓存；冷缓存
可异步请求x/report/click/now（timeout2秒）却立即返回0。completion只在now>0时保存
差值，无往返时延补偿；completion清flag。
**补充（8.89 静态，T1 findings P2）**：error 路径到不了 completion——`requestWithOptions` 与
`requestAsync` 之间没有第二次 handler 写入⇒errorHandler 为 nil，失败分支 0x116093d0c 直接
退出；flag 在异步请求前置真（0x115dab470），只有成功 completion 在 0x115dab68c 清，不存在
超时/取消清 flag 的路径（全 __text 只有 LDRB 0x115dab464、STRB 0x115dab470、STRB 0x115dab690
三处）。持久化经 BFCPreferences 动态属性层（`_defaultsKeyForSelector:`⇒key=属性名
`boottime`/`slinterval`）写 suite `BFCLaunchTimePreferences`，两次独立 setter 非事务提交；
suite 名字面量唯一引用 0x115dab184、prefs classref 只有 3 处引用，未发现针对该 suite 的
`removePersistentDomainForName:`/`removeSuiteNamed:` 调用（方法存在性边界，不是“会被清”的证据）。原生模块已注册
三个API类provider；BFCTimestampGateway0x10518ce44遍历响应头、忽略大小写匹配
x-bili-app-ts，doubleValue>0直接当Unix秒写BFCServerTime，未检查HTTP状态/error。
NetworkTimestamp多绑定注册及ApiClient moduleInitialize解析/登记类数组已闭合；
原生controller逐request按canInit实例化gateway，响应canonical先于rawDataHandler。
请求/响应各自重读ktorEnable，true跳过相应原生链，不能外推Ktor/Moss或假定flag
全程不变。它与heartbeat的data.ts回执不是同一个通道。

**NeoBili 当前实现**：移动开始报告的 `start_ts=0`；`PlaybackWatchReportSender` 接收成功起播响应的
有效 `data.ts`，只更新对应播放 session 后续移动报告。历史仍使用 `localStartTimestamp`。
真实累计由单调时钟计算；登录续期独立使用服务器时间请求。

**剩余范围**：官方全部响应时间网关和公共校时缓存未接入；迟到、无效和跨会话回执属于本地回归项。

<a id="r23-应用定时心跳未实现不能用历史checkpoint替代p2"></a>
### R23 应用级定时心跳未接入

**证据**：8.89普通HeartbeatService在trackMetaInfo/appendSliceContext把自身绑定为
AtomicHeartbeat proxy数据源。Atomic字典入口0x11487eac8要求播放器取得focus、数据源
存在且响应trackMetaInfo；读取当前位置、倍率、画质、缓冲、sceneMap及同一个tracker
session，没有另建Atomic session。BFCAtomicHeartbeat._fireDelegates0x1149f2f10
合入各非空delegate字典，后枚举项可覆盖字段，本段未排序或按session过滤；经注入
helper0x100129684调用BFCNeuronService customEvent/setExtendedFields/trackEvent，
policy raw0（_fireDelegates 0x1149f2f10）；**注册/上传链已闭合**（team-c2 §6.1：NeuronModule.register 0x104976d08、witness+0x10=0x104976c18 返回 `BFCNeuron.shared`；注入侧 sub_100129684 依序 `customEvent:p_event_count`/`setLogId:006638`/`setExtendedFields:`/`trackEvent:trackPolicy:`），不是直接调用播放历史 HTTP。
startBeating排随机0–29秒的always启动工作，同时启动point timer；两者mainRunLoop
common/repeats且fireDate=distantPast，always间隔30秒，point在state3/10/20发事件。
该state不是播放器状态；end会invalidate现有timer，先前排队启动block未见代际复查。

**NeoBili 当前实现**：当前没有 `new_heartbeat`、Atomic 数据源或应用级循环 timer。
播放器历史 checkpoint 随真实观看推进，由 `PlaybackWatchProgress` 和发送器处理；
App 行为队列由事件及生命周期驱动。

**剩余范围**：新增应用事件需要现版字段来源和实际产品需求，当前无需增加轮询。

<a id="r24-兴趣引导为独立可选功能安装标记与迟到回执须另建所有权p2条件性"></a>
### R24 兴趣选择引导尚未接入

**证据**：8.89 guide物理action先调用网络closure，再track/dismiss；发送index/interest
的action="1"，close走独立cancelClosure。guide失败/success finisher为bare ret，与
launch的Unavailable/token.done策略不同。second/interest独立builder编码unique_id、
选中结果及source映射half/full，device_type读安装以来首次feed成功标记的String，
缺值"0"；该标记默认Bool false，feed nil-error链置true，IPA未显式完成Bool→String
编码。它不是机型，也不是当前登录状态或请求已成功的证明。
T37首屏确认成功回调先排0.5秒清loading，再处理response；原view释放仍可更新共享
manager model，随后才弱gate UI。本段未见account/request/current-model检查；
空items及网络失败回退捕获原model，不能据此断言实测跨账号交付。
T34 S1 willDisplay对display child._isExposed去重，false才track兴趣show，track返回
即将同child置true，不等待网络成功，也不因发送失败恢复资格。SubItem新建false，
YYModel黑名单排除该marker；S1 configure直接保留输入model/items，没有deep copy
或reset，因此同model重建及失败fallback保留它。全局reset、新响应对象复用及账号
边界证据不足；这是子对象曝光标记，不是MID/ID/IndexPath持久去重池。

**NeoBili 当前实现**：首页解析卡片、游标和曝光策略，没有 `interest_choose`、
启动/二次兴趣选择 endpoint、引导界面或安装成功标记。
现有“不感兴趣”使用独立 dislike 通道；直播的 `device_type=0` 只属于直播请求。

**剩余范围**：兴趣引导属于可选功能，若接入需定义账号、请求代次及引导实例的所有权。

<a id="r25-播放器操作日志已接入子集单位与观看报告分开p2"></a>
### R25 播放器操作日志使用毫秒和独立事件序号

**证据**：8.89 Tracker0x114880e90 走 `BFCNeuronPlayerEvent`——team-c2 §3 证它是 **ObjC 协议 0x11d88fec0**（不是类），具体类 `_TtC6Neuron11PlayerEvent` 无 ObjC alloc 构造点，转换链 B `sub_104974BE0` 按 category 9 组装 `BFCNeuron_AppPlayerInfo`；category raw9，默认
track policy0、instantly才policy1。currentTime秒×1000再向零转Int32，先写
CommonFieldsModel，再填event；queue仅cid匹配才取itemCurrentTime，否则0。
quality映射0x11488242c只保留15/16/32/64/74/80/100/112/116/120/129，其余0。
model自身session先填入，后由当前tracker session覆盖；seq为实例报告顺序，缺该
扩展键时才补旧值并递增。operation入队返回true不是磁盘或上传成功。

**NeoBili 当前实现**：[AppPlayerBehavior](../../../NeoBili/Data/Networking/Reporting/AppPlayerBehavior.swift) 构造
category=9 的播放器资料，位置使用毫秒并限制 Int32 上界；非法位置被拒绝，未知画质编码 0。
`PlaybackReportingCoordinator` 在真实起播、暂停、恢复和结束时提供会话、实际画质、倍率
及递增的 `$player_event_seq`，交 `AppBehaviorReporter` 排队。
历史 progress 与移动播放位置保持整数秒，观看累计另有字段。

**剩余范围**：官方其他 tracker 操作和跨容器序号继承尚未实现。

<a id="源码锚点索引本轮逐条核查"></a>
## 源码入口

| 主题 | 所属实现 |
| --- | --- |
| R01–R04：首页参数与生命周期 | [Recommendation](../../../NeoBili/Data/Networking/Recommendation) |
| R05–R07：身份、登记与票据 | [Identity](../../../NeoBili/Data/Networking/Identity) |
| R08–R12：卡片和行为事件 | [Reporting](../../../NeoBili/Data/Networking/Reporting)、[Home](../../../NeoBili/Features/Home) |
| R13、R16、R17、R22、R25：观看与播放会话 | [Player](../../../NeoBili/Application/Player) |
| R14、R15、R20：首页状态与反馈 | [HomeViewModel](../../../NeoBili/Application/Home/HomeViewModel.swift)、[BiliAPI+Recommendation](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Recommendation.swift) |
| R18、R19：传输与签名 | [Transport](../../../NeoBili/Data/Networking/Transport)、[AppSigner](../../../NeoBili/Data/Networking/Identity/AppSigner.swift) |
| R21、R23、R24：应用生命周期与功能范围 | [NeoBiliApp](../../../NeoBili/App/NeoBiliApp.swift)、[AppRecommendationPage](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationPage.swift) |

验证入口统一见[开发与测试](../../DEVELOPMENT.md)。当前运行结果保存在忽略的构建目录，
研究中的历史测试和网络观察保留原始条件。
