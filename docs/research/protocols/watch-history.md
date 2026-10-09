# 播放历史同步与播放器心跳

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 播放历史同步与播放器心跳

### 历史请求的校验和字段

`BBHD2MPHistoryReport.reportPlayHistory`（0x10cb17ff4）要求 cid >=1，然后调用
CloudSyncHelper.reportPlayHistoryWithParams；block 填 type/subType/avid/cid/seasonId/
epid/currentTime/duration/localDeviceTime/localStartTime，并设 syncLocalType=3。
随后检查 BFCAccount.currentUser；没有用户时调用 saveLocalWatchWithReportModel。
这个入口没有先以登录状态拒绝 helper 调用，不能将其描述为“仅登录才构造请求”。

helper（0x104a80850）同步创建 ParamsModel、执行传入 block，再进入 Swift 实现
0x104a80fcc。实现拒绝空 model、cid <1、avid <0、epid <0、duration <1；
ignoreTimeVerify 为假时还拒绝 currentTime <1。通过校验后，若整数
`duration - currentTime <=4`，直接将 model.currentTime 改成 -1。这是距结尾的判断，
包含超过 duration 的输入；不是累计观看四秒或恰好播放完成的证明。整数减法有溢出
trap 分支，异常输入不能按无限精度公式处理。

请求字典含 type、sub_type、cid、aid（来自 avid）、sid（来自 seasonId）、epid、
progress（经过上述改写的 currentTime）和 duration，均转为十进制字符串。
localStartTime 非零时加入 start_ts 与 device_ts，double 转整数使用向零截断，且有
有限值和整数范围检查。sourceType 属性（getter 0x104a83330，Swift ivar slot 0x12049a310）
是整数；raw0于104a81b2c省略source，非0调用104a82c64按21项跳表转换来源字符串，返回非空才写source。映射见下表。ParamsModel getter/setter是纯整数ivar，不代表序列化无映射。CloudSyncService getReportParams114452990的x20是服务self，读服务_sourceType（getter114453990/setter1144539a0）写新ParamsModel，非“源model”。另外四场景是独立新建receiver：Story OGV=17，非OGV按isSingle=7/8，StoryMiniScreen=1，EduMiniScreen=20；它们不证明服务的预填源。Interactive及OGV服务proxy另有赋值，proxy已绑定同history-service类，经manager按class缓存/创建，weak目标非nil且active才forward，Interactive1/OGV传入bizSourceType（root-static-session/last-tail.md）。

| sourceType | source |
| --- | --- |
| 1 | player-old |
| 2 | media-list |
| 3 | tianma-inline |
| 4 | dynamic-inline |
| 5 | search-inline |
| 6 | activity-inline |
| 7 | story-single |
| 8 | story-series |
| 9 | space |
| 10 | feed-inline |
| 11 | view-together |
| 12 | listener-single |
| 13 | listener-series |
| 14 | banner-inline |
| 15 | subscribe-inline |
| 16 | vertical-inline |
| 17 | story-ogv |
| 18 | baike-inline |
| 19 | movie-inline |
| 20 | player-window |
| 21 | game-inline |

0不发字段，1..21之外经helper转换unknown。表仅8.89所选函数，不能当9.13取值验证。
阳性对照 0x113f03318 `-[BFCCommentConfiguration setSourceType:]` 同 stub 但 receiver 为自有类。
**本入口构造的 model 装哪些键已逐条读出**：`BBHD2MPHistoryReport.reportPlayHistory` 的 block
（0x10cb180f8–0x10cb181b0）只调 setType:、setSubType:、setAvid:、setCid:、setSeasonId:、
setEpid:、setCurrentTime:、setDuration:、setLocalDeviceTime:、setLocalStartTime:、
setSyncLocalType:，**没有 setSourceType:/setExtendFields:/setReportScene:**；该 block 所在
0x10cb1xxxx 区间内也没有 `setSourceType:` 的 selref 调用点（全镜像该选择子 25 处调用点均不在
此区间）。因此纯播放历史链不会产生 `source` 键、不走 extendFields 合并、也不加 `report_scene`；
这三者只可能由其它调用方预填 model 后交给公共 helper（0x104a80850），不能把本入口当作它们的
固定 producer。
scene 按 UIApplication.applicationState 为 0 取 front，否则取 background；
extendFields 在标准字段之后、report_scene 之前逐键覆盖：0x104a81cec–0x104a81d08
进入 sub_104E46224 的 Sequence.forEach（0x104e462dc），不是 Dictionary.merge
冲突闭包。0x104e46330 的 x28 是 value metadata 的 Swift value-witness table，
0x104e463a4 BLR 调 initializeWithCopy；随后 0x104e463d0 明确 Dictionary.updateValue。
因此 extendFields 同名值覆盖基础参数；其后reportScene整数非0时才写 report_scene 并覆盖该同名扩展值。
原 team-c22/T2 的“捕获冲突闭包/keep-new-old 静态不可判”撤回。
原始补证 root-static-remaining/findings.md 与0x104a81c90/0x104e46224/0x104e4636c.asm。
reportScene 非零时加 report_scene。

BFCApiOptions.requestMethod 设原始值 1，reportScene=0 使用
`https://api.bilibili.com/x/v2/history/report`，非零使用同主机的
`/x/v2/history/report_scene`；设置 params/modelDescriptions 后创建 BFCApiRequest 并
requestAsync。该业务方法还根据 syncLocalType 写入本地缓存，发生在异步请求启动后，
没有在此入口等服务端成功才写入。具体枚举、缓存实现与响应处理未逐项核对（下一步 `disassemble 0x104a80fcc 0x104a82500`）；也不能据
requestAsync 就断言服务端已接受或首页兴趣已更新。

### 历史服务的计时与触发

`BBPlayerPlayHistoryCloudSyncService.currentPlayDuration`（0x114452694）在
inQueuePlay 为真时取 currentItem.itemDurationByCid，否则取 playback.duration。
currentPlayTime（0x114452770）取 offsetTime 加播放位置：队列播放取
currentItem.itemCurrentTimeByCid:playbackCurrentTime:，其他取 playback.currentTime；
两条分支都用 frintp 向正无穷取整。这里读取媒体位置，不能当作累计真实观看时间。
currentProgress（0x1144528a4）另在剩余时长 <=5 秒时返回 0；它不是请求 helper
上述 <=4 秒、-1 的同一个规则，调用方必须分开追踪。

shouldReport（0x1144528ec）拒绝 cid <1；reportPolicy=1 且实验
ff_player_history_report（入口 presetHitValue=1）命中时拒绝，其余条件返回真。
实验命中已闭合到具体调用：shouldReport 仅在 reportPolicy==1 时才问实验，0x114452910 调
`reportPolicy`、0x114452914 `cmp #0x1` / 0x114452918 `b.ne` 直接返回真；命中路径
0x11445291c–0x114452934 取 classref `_OBJC_CLASS_$_BFCMemexABTest`（0x11f7b6000+0x658），
以 CFString `ff_player_history_report`（0x11d359470）与 `presetHitValue`=w3=1 调
`hitExperimentalGroupForKey:presetHitValue:`；返回非 0 才在 0x114452938 落到拒绝分支，
以 `main.player.core` tag 打 `[PlayHistory]|report limit|cid = %lld`（0x11445295c–0x11445296c，
取当时 cid 入参）后返回假。故 preset=1 只是该 getter 的兜底入参，**不是当前命中状态**；
reportPolicy 在本镜像 __text 内**直接载入该 selref 的调用点**有 7 处（0x10187b7d0、
0x1019a7020、0x101a261c0、0x1029e2d28、0x103a716ec、0x103b3dc40、0x103f5c27c）；
另有共享 stub `_objc_msgSend$setReportPolicy:`，经该 stub 的调用点未逐条枚举，
故不能把这 7 处写成全部可写入口。另有已定位的直接写者见下（service init raw1、Story raw3、
Inline 复制），策略枚举来源不能由 preset 值代替。
getReportParams（0x114452990）复制业务 ID/类型，currentTime/duration 来自上述
播放位置与媒体时长，localDeviceTime 来自 BFCServerTimeChecker.realTimeInterval，
localStartTime 来自 tracker.heartBeat.curHeartBeatContext.getLocalStartTimestamp；
ignoreTimeVerify 设为 playback.inQueuePlay。服务端校时与开始时间生成还需下钻。

reportPlayHistory（0x114452b64）经 shouldReport 再调用 helper。**回执侧已逐指令确认：
该链不安装任何本地回执**——0x114452b64 先按 tag `main.player.core` 记
`[PlayHistory]|report online|cid = %lld`（0x11d3594b0，行 194），再 `shouldReport`
（0x114452bac，为假直接 return 0x114452c34），随后只把 `getReportParams` 结果交给
类方法 `+[BBPlayerPlayHistoryCloudSyncHelper reportPlayHistory:]`（0x1174e48e0）并记
`params = %@`（0x11d3594d0，行 201）；helper 实现 sub_104A80FCC 只做
`BFCApiOptions`(requestMethod/setBaseUrl/modelDescriptions) + `setParams:` +
`BFCApiRequest initWithOptions:` + **无参 `requestAsync`（0x104a81fa0/0x104a81fb0，未传
completion/error block）**，其后只拼日志 `history report aid:`。因此历史校验/上报的
结果处理若存在，只能在公共 BFCApiRequest 层（T1 区间），本链无业务回执分支、
也无 `_start_verify_ts` 之类的回执写入。另有明确区分的
reportPlayHistoryOnlyMemory 与 reportPlayHistoryToMemoryAndDB：后者先调内存历史
入口，再调用 setCurrentTime:cid: 和 setDuration:cid:；不能将所有保存行为等同于云请求。
_addObserver（0x114452ebc）观察 playbackState 与 playerDestroyed。状态原始值 5 时，
reportWhenStoped 为真走云历史入口，否则仅内存；原始值 3 分支用于历史提示。
playerDestroyed 为真且 reportWhenStoped 为真时也调用云历史入口。状态枚举业务含义、
观察者安装方、重复触发处理与其他调用方未穷举（下一步 `find_callers.py 0x114452ebc` 与 `query_index.py '*CloudSync*' 40`）。
**安装方已收窄但未定位**：0x114452ebc 的 __objc_const 方法表项为
(name `_addObserver` @0x11f15f6a0、types `v16@0:8` @0x11f15f6a8、imp 0x114452ebc @0x11f15f6b0)，
即 selector 确实指向本方法；但（a）全 __text 的 BL/B 目标扫描
（`(inst&0x7c000000)==0x14000000` 解码目标 == 0x114452ebc）命中 0 处，
（b）`_addObserver` 的 __objc_selrefs 槽 0x11f5fc030 只被共享 stub
`_objc_msgSend$_addObserver`（0x117144640）引用，而该 stub 的 33 个 BL 调用点
（含 `-[BBLiveInternalRoomViewModel initWithRoomID:]`、`-[BBEduPlayerTrebleRateService serviceOnStart]`
等）**没有一处落在本服务所在的 0x1144xxxx/0x1148xxxx 区间**。下一步见下句：find_callers.py 0x117144640。
故该服务的 `_addObserver` 安装方**已定位（task-38）**：stub 0x117144640 共 **33 处**调用边，云同步服务的安装点 = `-[BBPlayerPlayHistoryCloudSyncService initWithContext:]` @0x114451e00；注意不能再用"selref 无 ADRP+LDR 引用"当作
无调用点的判据（共享 stub 必须再查其 BL 调用方，见旧 V2 段的订正说明）。
addSupplementSyncObserver 是紧邻的下一方法表项（imp 0x11445324c），另接补同步 manager 和
reportScene；补同步调度待继续追踪。

未登录入口的 saveLocalWatchWithReportModel（0x10cb181c8）创建 BFCHistoryAVModel，
data_id 为 avid 字符串，view_at 为当前 Unix 秒向零截断后写回 double，progress 将
currentTime 用 fcvtps 向正无穷转整数，duration 保存原媒体时长；同时写入 cid、
总分 P 数、当前 P、标题/封面、UP 名称/MID、part 和 uri。
uri 格式为 `/av/%@/?page=%@&trace=play_history`，最后交给
BFCHistoryDataManager.engine.saveHistoryDataWithModel。此方法未看到将近结尾进度
**持久化已闭合（task-38）**：写入点 `saveHistoryDataWithModel:`（0x10cb1851c）+ `BBHD2MPAvLocalDataManager getHistoryDict` → `containsObject` 去重 → NSUserDefaults 键 `BBHD2MPAvLocalDataManagerUserDefaultKey`（0x10cb18710 装载键，0x10cb18718 才调用 setObject:forKey:）；view_at 为 fcvtzs 整数秒。残余=读取与登录后合并尚需继续追静态调用链，实际磁盘成功/账号交错须运行期验证。

### 播放器心跳的边界

`BBPlayerHeartBeatServiceV2.playStart/playEnd`（0x114889414/0x11488956c）先验证
播放准备状态、context/meta 有效性与完成状态；开始路径包含 resumeTrackerMetaInfo。
_playStartReport/_playEndReport 根据 v8.48.0_heart_beat_update_meta_info 条件更新
质量/语言等信息，再调用下层 heartBeat 的 playStart 或 playEnd:withSyncImmediately:。
因此历史同步、播放心跳对象和 Neuron PlayerEvent 描述符不是同一个请求。
底层计时、会话和发送队列见下节；Tracker创建本服务和观察触发已有静态链，
其他scene的采用范围及实际调用频率仍需核对。
BFCAtomicHeartbeat有独立的应用事件路径，不能仅凭同名“心跳”推断它走播放历史
端点或具有相同节奏。两条链的时间来源也已分开：Atomic 的 startBeating（0x1149f29fc）先读
standardUserDefaults 的 `infra_heartbeat_terminate`（CFString 0x11d387390，
0x1149f2a20–0x1149f2a44 doubleForKey:）作 lastBegin，再取 `[NSDate date]`（0x1149f2a54 载
classref 0x11f7b5000+0xd88 → 0x1172a6740 msgSend$date）作 begin，即设备墙钟；而历史上报的
localDeviceTime 与心跳上下文 setupDefaultConfig 的计时基准走 `+[BFCServerTimeChecker realTimeInterval]`
（0x115dab1a8 尾调 `realTimeIntervalWithSyncServer:` 且 w2=1；实现在 0x115dab1b0 起：
先 `BFCServerTime.time`（0x115dab1c8/0x1176d44e0），非 nil 直接采用；否则 `canUseNetwork`
（0x1172365a0）为真时 `getLocalRealTimeIntervalWithSyncServer:`（0x1173340a0），返回非 0 时
`dateWithTimeIntervalSince1970:`（0x115dab204/0x1172a6ea0），为 0 返回 nil；不可用网络时回退
`localTime`（0x1174028a0）），是服务器校时链路。两条时间来源不可互代；公共时间辅助请求的
端点与缓存属公共层区间（T1），此处只固定其与 Atomic 墙钟的分离关系。
普通service.trackMetaInfo:在建立context后将self赋给
atomicHeartbeatProxy.dataSource（0x1148892e8/0x1148892fc）；appendSliceContext也
做同样赋值（0x1148893b8/0x1148893cc）。proxy首次getter0x11488b364通过context的
serviceManager.createProxyAndBindService创建BBPlayerAtomicHeartbeatServiceV2，随后缓存。
Atomic serviceOnStart/Stop分别add/removeListener，向BFCAtomicHeartbeat.shared
add/removeDelegate（0x11487ea74/0x11487eab4）。heartBeatDictParams0x11487eac8
先要求playback.isGetFocus、dataSource非nil且响应trackMetaInfo，否则返回nil。

普通service的无参trackMetaInfo0x11488acb0从当前curHeartBeatContext.metaInfo构造
BBPlayerAtomicHeartbeatMetaInfo，复制avid/cid/sid/epid/trackid/spmid/from_spmid，
trackid仅在nil时替为空String。scene由getCurrentSceneValueWithMap0x11488ae28按
context.status.isFullScreen/isVerticalScreen选择sceneMap的四个键：
landscape_full_screen_key、portrait_full_screen_key、landscape_half_screen_key、
portrait_half_screen_key；nil/非dictionary map返回nil。不是从播放器整数状态
直接生成固定scene值。Atomic字典写avid、cid、seasonid、epid、playback_status、
playback_time、playback_rate、video_quality、is_buffering、track_id、scene、spmid、
from_spmid、playerSessionId（0x11487f108–0x11487f230）；最后session从当前tracker
getter取，未另建atomic session。playback_status的本方法静态表0x11cf91e38将
raw0/5/6→stopped、1/2/4→paused、3→playing，unsigned>6→unknown；这是上报文本
分组，不能代替所有业务状态枚举。video_quality先取qualityProxy.currentQuality
十进制String，只有等于"0"（0x11487ef5c）才改取currentItem.ijkItem.currentQn；
并非所有nil/异常quality都会走fallback。

BFCAtomicHeartbeat._fireDelegates0x1149f2f10建立app_running_status等公共字段，
对app.app.new_heartbeat.1.other加hb_moment，对app.app.new_heartbeat.0.other加
heartbeat_new/heartbeat_begin/heartbeat_last_begin/last_begin_interval，然后枚举
hashTable.allObjects。回调0x1149f3338只对支持heartBeatDictParams且返回非空字典的
delegate做addEntriesFromDictionary（0x1149f33b8），所以字段可被后枚举delegate覆盖，
未在这段排序或按session过滤。之后才调用injection.trackHeartEvent:dict:
（0x1149f31f0）。已定位BFCAtomicHeartbeatInjection0x1001298ec桥到helper
0x100129684，其调用注入tracker.customEvent、setExtendedFields、trackEvent:trackPolicy:
（policy raw0；0x1001298c0），不是直接构造播放历史HTTP。**该桥本轮逐指令读出**：
`-[BFCAtomicHeartbeatInjection trackHeartEvent:dict:]`（0x1001298ec）先经 sub_105134D98
打一条带文件/行号的诊断（`BFCAtomicHeartbeatModule.swift` 行 55、行 61、
`srcs/common/BFCAtomicHeartbeat/BFCAtomicHeartbeatModule.swift` 行 61），
再 0x1001299c4 `bl sub_100129684`；后者对注入的 tracker 依次发
`customEvent:` 事件名 **`p_event_count`**（小字符串立即数 x24=0x5f746e6576655f70 + x23=0xed00000000746e75，
判别位 0xED=0xE0|13）、`setLogId:@"006638"`（立即数 0x3030/0x3636/0x3833 + 判别位 0xE6）、
读 `productEventSuccessCount`（0x10012973c）与 `techMetricSuccessCount`（0x1001297c8）、
`setExtendedFields:`（0x100129868），最后 `trackEvent:trackPolicy:`（0x1001298b0/0x1001298c0，
policy raw0）。注入实例 `-[BFCAtomicHeartbeatInjection init]`（0x100129b64）只调 super.init、
不在此给 tracker 赋值，故 tracker 的实例子类身份需运行期确认（真机断点 sub_100129684 入口读 x19）。
解析所用type缓存
0x12028bf70指向0x1196c3a8a的So16BFCNeuronService_p；0x12028bf78是该协议的
Optional包装，而非NetTracker。NetTracker另由本模块lazy initializer0x100129654构造，
不能把注入service与额外心跳delegate混为同一角色。NeuronModule.register
0x104976d08以同一type缓存0x12028bf70、w5=0注册provider witness0x120491e60
（0x104976d90）；witness+0x10为0x104976c18，明确返回BFCNeuron.shared
（0x104976c3c），其模块根清单index214可达。因此已有具体原生Neuron来源，仍保留
注册失败/替换/动态实现边界；最终上传覆盖继续核对，不把入队调用当成服务端成功。

Atomic计时局部已闭合：startWith:0x1149f2868保存injection后startBeating；后者
0x1149f29fc先将实例_newHeartBeat字节置true，此方法没有先读该字节拒绝重复调用；读取
standardDefaults.infra_heartbeat_terminate为
lastBegin，保存当前NSDate Unix秒为begin并写回同键。setup0x1149f2b74以
arc4random()%30秒排主队列block0x1149f2c58，再启动always timer；同时将pointState
置0并立即启动point timer。两timer均为NSTimer+BFCWeakProxy、mainRunLoop common
modes、repeats=true，添加后fireDate置distantPast；always interval=30秒
（0x1149f2cc0），point interval=1秒（0x1149f2dcc），不能称首个事件必等30秒。
_reportHeartBeat直接发app.app.new_heartbeat.0.other；_pointTransition
0x1149f2e88仅pointState=3/10/20发app.app.new_heartbeat.1.other，之后state+1，
state=21时invalidate并清point timer。该state不是播放器playbackState。
heartbeat_new直接取_newHeartBeat字节（0x1149f304c）转Bool String，begin/lastBegin
及两者差用"%.0f"格式写String；发0.other后在本方法尾清_newHeartBeat
（0x1149f32cc–0x1149f32ec），不等待上传回执。1.other不清此字节。名称不表示
每次event均新建session或已被服务端识别为首次。
endBeating0x1149f2b20 invalidate两timer并置pointState=21；先前setup排出的
block0x1149f2c58直接调用_timerAlwaysStart，没有在此block看到取消/generation
复查。队列生命周期与实际模块调用继续核对，不能将end本身视为已撤销所有排队工作。

Atomic模块false根服务清单index56（0x1202729c8），service conformance
0x118259480→witness0x11b0b1da8，+8注册0x10012935c；这里注册的是
MossStreamTrackerService（type缓存0x12028bfb8→descriptor0x1196b1974），provider
0x100129278构造StreamTracker，不是NetTracker delegate或前述BFCNeuronService。
独立184任务清单index29（0x120273d20），entry witness0x11b0b1dc0为priority450、
moduleInitialize/main，exec0x1001295b0→0x100129c50；这将初始化绑定到已证明的
Gripper派发链。执行读取enable_bfcatomic_heartbeat(default=true；调用点0x100129e00)，
**该地址↔flag 名的绑定已逐指令闭合**：0x100129dcc/0x100129dd0 `adrp x8,0x117783000` +
`add x8,x8,#0xf90` 取包内 Swift 字符串字面量 `enable_bfcatomic_heartbeat`，
0x100129dd4/0x100129dd8 减 0x20 并 `orr #0x8000000000000000` 成大字符串，
0x100129ddc/0x100129de0 `mov x0,#0x1a`+`movk #0xd000,lsl#48` 给出长度 26（与该键字符数一致），
0x100129de4 `String._bridgeToObjectiveC()` 得 NSString；0x100129dec/0x100129df0 载
selref `getBoolForKey:defaultValue:`（槽 **x19+0x250**，即验证席位指出的间接载入槽），
0x100129df4–0x100129dfc 把该 NSString 作 key、w3=1 作 defaultValue，
0x100129e00 `objc_msgSend`。因此 w3=1 是 defaultValue 而不是命中值，
键名与地址的绑定由上述字符串构造指令直接给出、非地址层猜测。返回非 0（0x100129e18 `cbz`）
才创建 BFCAtomicHeartbeatInjection 并 `shared.startWith:`（0x100129e20–0x100129e68）。
该开关 false 在 0x10012a064 退出，也不继续读取下面 nettrack 开关。
bfcheartbeat_nettrack_enable(default=false；0x100129ed4)通过时，才在main队列
now+20秒（0x100129f0c/0x10012a018）执行0x100129bd0，将独立lazy NetTracker
加为delegate。默认值只是该配置getter的参数，不代表实际配置命中或已观察启动成功。
NetTracker与StreamTracker的字段/发送消费者继续核对，三个角色保持来源边界。

延迟加入的NetTracker.heartBeatDictParams0x10012bd68→0x10012a910读取注入
apiClient.metrics与reachability状态，构造outer key stream，其value为一个对象数组
的UTF8 JSON String。内层六个String字段：timestamp=Date Unix秒向零转Int64的
十进制，stream_event字面stream_reachable，stream_code=共享Bool的"0"/"1"，
http_code=metrics.http_code按base10 Int解码的十进制（缺/解析失败→0），
http_error_code=metrics.exception_msg（缺→"0"），reachability=原始status十进制。
JSON或UTF8转换失败只省略stream键，未在这段中止整个应用心跳。没有读取实际metrics。

StreamTracker的协议witness0x11b0b1f08的+8为空return；+0x10→0x10012a748→
0x10012c574把输入Bool最低位通过共享utility queue0x12028c288的sync写入
RAM byte0x12028c290（0x10012c6fc），NetTracker经同queue.sync0x10012c7d4读取。
因此多个provider实例共享这一状态，而非每个请求独立记录。实际消费者已闭合：
BFCMossStreamReachability.setCurrentReachable0x1149ee25c仅值改变时写自身byte+8，
发kBFCMossStreamReachabilityChangedNotification（0x1149ee2c0）后经
BFCMossStreamConst.trackStreamReachable0x1149eee1c转Wrapper.streamWithReachable
0x104e2dff8→0x104e2eec4，解析[MossStreamTrackerService]并逐witness+0x10，
进入上述StreamTracker共享RAM写入。native stream auth0x1149ed520要求
status.code==0且channel+0x38.shared=true才传1（0x1149ed5b0）；close0x1149edc68
在trackNet/heartbeat.stop后，同shared=true才传0（0x1149eddfc）。channel+0x38是
initWithHandler:meta:frameBuilder:tracker:0x1149ec350的meta参数x3，strong保存于
0x1149ec3e0/0x1149ec3e8；类型与sharedCenter构造已在公共Moss节闭合，其他中心
setter 未穷举（下一步 `find_data_refs_root.py` 扫 RAM byte 0x12028c290）；不能从这些受 meta.shared 门禁的状态或 stream_reachable 字面
推出全部连接及实测网络畅通。另一个Wrapper.trackWithParameters:isHit路径true时
逐witness+8，但Atomic StreamTracker的这个witness为空return，不能归因该字典上报
给此StreamTracker实现。该Wrapper.trackWithParameters:isHit实现0x104e2eb70对
nil字典或isHit最低位false跳过fanout和后续报告；true即使tracker数组为空也继续
解析BFCMikotoService，trackTech ops.misaka.app-broadcast、原字典、policy raw2/
rate100（0x104e2ed44）。它不是直接Neuron调用。相邻netTrackWithUrl:parameters:
0x104e2df34→0x104e2edac解析同Mikoto，trackNetWithURL:extendedFields:
（0x104e2ee94）传原URL/字典，不经过StreamTracker数组。

NetTracker另有诊断分支，与返回stream字段分开：bfcheartbeat_analysis_close
(default=false；0x10012b21c)命中直接跳过diagnoser，仍返回心跳字典；否则
bfcheartbeat_analysis_force(default=false；0x10012b2c8)读取后，仅当stream=false，
或http_code不在200–399，或force=true时调用diagnoser（0x10012b3b0）。close优先
于force，HTTP门禁包含3xx而不只2xx。
_diagnoser的type缓存0x12028c390解析为DiagnoserService；callback
0x10012c838→0x10012b9f8仅result tag bit8=0时继续，bit8=1直接不track
（0x10012ba70）。继续时将诊断payload经JSON(options0)/UTF8
转String，成功添analysis到发起诊断时捕获的六字段inner字典；序列化失败省略
analysis，仍由_mikoto.trackTech报告public.heart.net.track（0x10012bd14），
policy raw2、rate100。这里extendedFields直接是六字段+可选analysis，区别于应用
心跳outer stream键包裹的JSON String；时间/网络字段未在诊断回调重新采样。
具体DiagnoserService conformance0x11825a260→NetworkDiagnoser descriptor
0x11948072c→witness0x11b0b3728，+8方法0x100141190→0x10013f028弱capture自身
再queue.async到0x10013f280。内部取lastDiagnosisTime计算Date.timeIntervalSince，
距上次<10秒时仅在main.queue.async回传skip tag0x100；它不是asyncAfter延迟重试。
通过间隔后先更新lastDiagnosisTime（0x10013f804），再检查diagnoser_close
(default=false；0x10013f8a8)及in-flight byte+0x130（0x10013faa0）；这两种skip
都回tag0x102。包装helper0x1001420d8把context byte+0x30 OR0x100后回调，故这些
skip正好被NetTracker的bit8门禁排除，不能写成所有diagnoser callback都上报。
skip分支未见回滚lastDiagnosisTime。
DI生命周期已闭合：334 service表index207、slot0x120273338为NetDiagnoser模块，
conformance0x11825a250→witness0x11b0b3710，register0x10013e400经公共DI路径
raw w5=0注册DiagnoserService。factory0x100142e84创建provider；getter
0x10013e314→0x10013e1ec首次分配NetworkDiagnoser并缓存provider+0x10
（0x10013e264/0x10013e2bc），后续复用。constructor0x10013ec9c初始化间隔10秒、
lastDate none、in-flight=false和URL缓存nil，队列com.diagnoser.network.queue。
因此lastDate及上述URL缓存随该provider实例复用，不是每次diagnosis重建；
unregister0x10013e4a4 经真实 witness0x11b0b3710+0x10 被 component deinit 间接调用，公共 resolver 用 exact type key 移除诊断服务；并非因为 direct caller/pointer 零就无静态调用证据。所选 body 无直接 probe 状态 reset，这条注销正链也不证明 logout 必触发或取消在途任务；具体账号退出绑定仍在本有限范围外。证据 root-static-exposure/auth-action-diagnoser.md。
accepted probe置in-flight=true（0x10013fc7c）并取retriveDNSAddress
（0x10013fe68）。正式probe创建dispatch
group和初值5的semaphore（0x10013fd00/0x10013fd08），DNS结果join后写dns_info；
innerAll逐host作TCP端口443，dataFree逐host作TCP端口809，outNet逐URL调用
BFCNetSpeedTool.speedTestWithURL:downloadSource:completionBlock:，downloadSource
raw0（0x100140030/0x1001400fc/0x10014029c）。每项先wait/enter，回调先在
com.diagnoser.network.resultQueue异步写结果，才signal/leave
（TCP 0x100140a34/0x100140a3c；speed 0x100140c5c/0x100140c64）。group.notify
亦在同resultQueue，汇总由FIFO排在这些写入之后；0x100140c88构造dns_info标量、
tcp数组、speed String:String字典，再main.async回传dictionary、tag0
（0x1001422a4/0x1001422ec），进入前述NetTracker上传分支。weakself已失效时不回调。
in-flight实际在安排group.notify之后立即清false（0x100140520），不等待probe完成。
三个URL/host列表为实例惰性缓存，首次读Decision的diagnoser_outnet_urls、
diagnoser_inner_urls、diagnoser_free_urls。mapper0x10007a790要求每个Any都可转
String，任一失败整个返回nil再用静态fallback；空configured array非nil，保留并
缓存，不能写成compactMap或空数组必fallback。静态fallback分别为
http://www.qq.com、http://www.baidu.com、http://cn.aliyun.com；
www.bilibili.com、api.bilibili.com、grpc.biliapi.net；
dir.v.wo.cn、dir1.v.wo.cn、dir2.v.wo.cn，未请求这些地址或读取实际配置。
TCP helper0x100141b04转BFCNetSniffer.tcpSnifferHost:port:count:timeout:progress:
completionBlock:（0x100141e10），count1、timeout raw3。progress0x100142914
写ip（model.ipAddr或"Unknown IP"），仅status raw1写rtt/dnsTime，秒值×1000
后格式"%.2f"。completion0x10014273c有errorString写error，否则model存在时
packetLoss×100后格式"%.2f"写packetLoss，两者皆无写"Unknown Error"。
收集字典由专用syncQueue保护。TCP outer结果先写host再合并收集字段，nil payload
写status="TCP - Failed"（0x100142b88）。speed callback0x100141f90仅当Bool
最低位true且第三String存在时取该String，否则"Error: "+第二String或"No data"，
最后speed[inputURL]=resultString（0x100142340）。实际downloadSource raw0走
BFCNetSpeedTool0x113912d1c：NSURLRequest cachePolicy1、timeout10秒，
NSURLSession.sharedSession.dataTask并resume（0x113912e1c/0x113912e2c），计时为
NSDate wall-time差。error非nil返回localizedDescription；无error但HTTP不是恰200
返回"code=%ld"；200时data.length/elapsed秒的Double收窄Float，再由userSpeed
0x113913020格式化。<1024为"%.2f B/s"；≤1MiB为除1024的"%.2f KB/s"；
>1MiB且≤1GiB为除1MiB的"%.2f MB/s"；>1GiB除1GiB却仍标"MB/s"，这是样本
字面行为，不能擅自改成GB/s。等于1MiB显示1024.00 KB/s，等于1GiB显示
1024.00 MB/s。已用六个假边界输入验证计算，不执行下载。该body未见elapsed零/负
保护；空URL先回failure "Invalid url"却继续测速分支（0x113912884/0x1139128a0），
没有early return。Sniffer短入口0x113911a80另注入dnsTimeout3，再将count1、
connect timeout3交实例并排global queue start。DNS失败/超时读出空IP时completion
返回"DNS解析失败"、nil report；非空IP起1秒repeatingTimer。connect前repeatCount
加1，>count停，==count完成后停timer并回BFCPingReport，故这里最多一次connect，
不是三次重试（0x113911d88–0x113912060）。report进度raw status1为connect返回0，
status2为非0；status2带的"建连失败:%d"进度errorString在Swift adapter中被丢弃，
只消费model（0x100142430），最终非nil report仍生成packetLoss。BFCPingReport
0x113916810仅status1计成功，packetLoss=Float(1-success/allCount)
（0x11391699c–0x1139169b8）；count1成功→"0.00"，connect失败/超时→"100.00"。
DNS失败error
则进入error字段，两类失败格式不同。
底层connect0x113912200创建byref结果-1001和semaphore，global worker执行IPv4
blocking socket/connect，写raw0/-1（非errno）、close并signal。caller只wait
timeout×1e9，忽略wait返回后读取byref，没有在这段取消worker/socket；超时可读到
初值-1001。DNS helper0x1139123dc同样限时wait并忽略返回，worker先inet_addr，
否则gethostbyname取首IPv4。上述wait超时不能当作底层connect/DNS已经停止；
本轮没有执行 DNS 或探测网络，OS 实际超时/回调次数属运行期、静态不可定（下一步 `disassemble 0x113912200 0x113912400` 复核限时 wait 分支）。


### 心跳上下文、会话与发送队列

Context.setupSession（0x1148859c8）优先采用 metaInfo.sessionID 非空字符串，否则调用
BBPlayerSessionManager.createSessionID（0x11487f6b8）。后者将 BFCBuvid.buvid 与
`NSNumber(double(Date.timeIntervalSince1970 ×1000))` 用 `%@%@` 拼接，取 bfc_md5String
再 lowercaseString。结果是小写 MD5 形状；不是 UUID，也未看到随机数。NSNumber 的
文本格式在样本内已闭合到指令：0x11487f700 取 `[NSDate date]`（classref 0x11f7b5000+0xd88）、
0x11487f710 `timeIntervalSince1970`、0x11487f718 载常量 0x1182e7c00（=1000.0）后 fmul、
0x11487f724 `numberWithDouble:`、0x11487f73c CFString `%@%@`（0x11d0d0450）与
BFCBuvid.buvid（0x11722b880）拼接、0x117210da0 `bfc_md5String`、0x117409820 `lowercaseString`。
样本内没有自定义数字格式化，故该毫秒数文本由 Foundation 的 `NSNumber.description` 决定，
不能离线假定为纯整数毫秒串。同毫秒并发碰撞与 9.13 现版是否同算法属运行时/跨版本项，
保留为残余（同毫秒并发属运行期、静态不可定；下一步 `disassemble 0x11487f6b8 0x11487f7c0` 复核格式）。
该播放会话与前述公共请求会话/传统活动记录 ID 来源不同；显式传入的 session 还会复用。
显式传入有具体优先级：service.trackMetaInfo:0x1148891e8取
context.tracker.playerSessionId，传给新HeartbeatContext.initWithMetaInfo:session:
（0x114889248/0x114889264）。constructor0x114884dbc先按入参metaInfo.isValid设置
context有效位；非空显式session会先写入原metaInfo.sessionID（0x114884e48），
然后copy metaInfo、再setupSession。因此这个入口的tracker session可覆盖原metaInfo
已有session，不能只写成setupSession直接优先原业务metaInfo字段。
metaInfo.isValid0x114886cfc的实际门禁是avid>0或cid>0即true；两者都不满足时，
仅type raw4/10且(sid>0或epid>=1)才true。此方法不要求mid>0、session非空或
avid与cid同时为正，不能把登录态或完整UGC ID pair当作这段valid的定义。
MetaInfo.init0x114886a64安装默认sceneMap0x114886ad8，四个*_screen_key对应去掉
_key后缀的固定文本；后续业务/迁移仍可替换map。copyWithZone0x114886b8c新建
MetaInfo后逐字段setter复制，包括sceneMap、extra、legacyExtra，不是新读当前账号
或深拷贝所有嵌套字典的证据。
视频详情业务入口BBVDPlayerScene.heartBeatTrackMetaInfoWith:0x103f5695c转
0x103f563a4：取flow.sceneImp，向其发送heartBeatWithContext:response:
（0x103f5660c），再把返回MetaInfo交context.tracker.heartBeat.trackMetaInfo:
（0x103f56694）。不能把统一service当成全部业务字段的构造源。
普通UGC的实现是BBUGCVideoDetail.VDPlayerSceneImp（class0x12043c1d0），
selector入口0x103b1adf4转builder0x103b1d87c；同名MallUGC实现是另一class
0x120418708/入口0x10352ea00，不能仅用短类名混为同一路径。
普通UGC builder要求context.director.currentScene存在，否则返回nil；新建MetaInfo后
立即读取BFCAccount.currentUser.mid（0x103b1d90c/0x103b1d928），currentUser为nil
时写mid=0（0x103b1d944/0x103b1d958）。avid/cid取currentScene.scene_avid/scene_cid，
type=3、play_type=1；applicationState raw2映射play_mode=8，其余映射1。
network_type仅在WWAN且isFreeBandwidthActive时为3，否则为1
（0x103b1da34–0x103b1da74），不是全部网络状态枚举。auto_play、from、spmid、
from_spmid、trackid、extra、legacyExtra来自当时currentScene.model；quality优先
currentScene.videoMetaInfo.currentQn，缺videoMetaInfo则取model.resolverModel.qn
（0x103b1de4c–0x103b1dee0）。legacyExtra另经0x103b1d154加工：nil输入先成空字典，
response.supplement.ugc.clip.hasClipInfo为true且clipInfo存在时，将materialNo十进制
String写current_material_no（0x103b1d1fc/0x103b1d2b0/0x103b1d2f8）；同键替换，
前述可选对象缺失或门禁false时保留输入字典。
因此这里的mid与来源是构造时快照，不是每次generateDict重新读取账号的证据。
详情更新入口0x103f56efc转0x103f569b0，仅在sceneImp响应
updateHeartBeatMetaInfoWithContext:response:时取该字典（0x103f56c34），再向现有
curHeartBeatContext发送updateMetaInfoWithParams:（0x103f56cf4/0x103f56d60）。
已读统一更新helper的有限字段范围见下文；不能据此断言更新会刷新MID、视频ID或session。
OGV业务实现BBOGVPlayerSceneBiz.heartBeatWithContext:response:0x1121c7724也是
新建MetaInfo，但先验证self.commonModel是BBPgcPlayerCommonModel、resolverModel是
BBResolverPGCParsModel，否则跳出业务填充段（0x1121c7788–0x1121c77e0）。该段
分别在0x1121c7870读取currentUser.mid并setMid0x1121c788c，在0x1121c7c78再次
读取currentUser.vip.isValidVip并setUser_status0x1121c7ca4；两次读取间没有在此方法
看到账号锁/epoch一致性门禁，不能称一个原子账号快照。avid/cid取当时
self.context.playback.currentItem.oid/cid；self.scene_cid等于前面取得的currentItem.cid
时才从commonModel.epItem填sid/epid，否则显式置0（0x1121c7954–0x1121c79cc）。
quality另在方法末尾再次取currentItem.ijkItem.currentQn（0x1121c8288–0x1121c82d8），
也不是完整播放资料一次性快照的证据。OGV更新字典入口
updateHeartBeatMetaInfoWithContext:response:0x1121d0b24仅在self.fragmentVideo.count>0
时返回单键attachedAvid=self.scene_avid（0x1121d0b60/0x1121d0b8c/0x1121d0bc0），
否则为空字典；该业务更新没有MID、cid、epid或session字段。片段视频初始构造分支、
extra 组装未逐项闭合（下一步 `disassemble 0x1121c7724 0x1121c8400`）；不能把普通 UGC type/play_mode/network_type 规则推广到 OGV。
OGV的heartBeatNetwokType0x1121c84e8另先读self+0x238对象.isLocalVideo，true返回
raw2（0x1121c84f4/0x1121c84fc）；否则仅WWAN且免流active返回3，其余1
（0x1121c850c–0x1121c8530）。这闭合了此业务的本地视频分支，raw2的全局语义
与该对象的创建/更新范围仍不能从这一方法外推。
推荐内联BPInlinePlayableScene.trackMetaInfoForHeartBeat0x1141fd2fc另从
self.model.params.meta取得业务tracker；meta.isVaild=false或isLiveSourceType=true
直接退出（0x1141fd35c/0x1141fd368），通过才新建MetaInfo并读currentUser.mid
（0x1141fd39c/0x1141fd3b8）。avid/cid取playViewModel.playArc，sid/epid先取
meta.tracker，UniteResponse的PGC/教育supplement分支还可覆盖sid/epid，不能只说
内联永远是UGC。playArc.videoType raw2→type4/play_type2，raw3→type3/play_type1，
其他→type10/play_type=原始videoType（0x1141fd4b0–0x1141fd4e8），保留原始枚举。
sub_type/play_mode/auto_play/from/spmid/from_spmid/trackid/extra/legacyExtra来自
业务tracker，extra及legacyExtra先copy；scene_type取其heartBeatType，quality取
playViewModel.videoInfo.currentQn，最终交context.tracker.heartBeat.trackMetaInfo:
（0x1141fd984）。构造后统一服务仍按前述显式tracker session建context。
内联sceneMap helper0x1141fdb80给四个*_screen_key写同一个值；表
0x11cf86cf8的raw0/1→inline，2/4→mini_screen，3及unsigned>4→空String。
这不是MetaInfo默认四种不同screen文本。内联VIP helper0x1141fdc54分别重读
currentUser.vip.type与status，仅type raw1/2且status raw1返回true；MID加这两次读取
同样未见同一账号原子快照门禁。此helper与OGV调用的vip.isValidVip不是相同实现。
具体构造caller是startPlayWithPlayViewModel:0x1141fb3fc：先setPlayViewModel
（0x1141fb6c0），后仅model.isShared=false才调用trackMetaInfoForHeartBeat
（0x1141fbd6c/0x1141fbd7c/0x1141fbd84）。它与前一ClickCounter的门禁不同：
ClickCounter还要求业务tracker.isSkipVVReport=false（0x1141fbd1c/0x1141fbd4c），
该skip flag未用于随后此Heartbeat构造判断。shared播放跳过这次新MetaInfo构造，
不能从startPlay本身断言新账号资料或新session；共享迁移须结合前述graft路径。
内联的另一条开播报告入口reportStartPlayerEventAndConfigTracker0x1141fdd94在
UGC/PGC/EDU source时generateParams:nil、configTracker，再向当前context.tracker调用
trackPlayerEvent:extendsFields:，eventId=player.player.start.all.player
（0x1141fe03c）。调用方扩展字典为四个String字段：idfa=BFCIDFA.idfaString或空，
max_system_volume字面"1"，original_system_volume=sharedInstance.outputVolume经
NSNumber.stringValue，track_id=业务tracker.trackid或空；没有读取/保存实际IDFA。
EDU通过0x1141fe0d0/0x1141fe0f0回到相同报告body；其他source跳过。
state caller0x1141fc6c4先要求old/new不同；经过graft/item正确性分支后，只有
newState raw2/3且_isPrepared=false才先置_isPrepared=true，再配置播放选项并调用
上述开播报告（0x1141fc9fc–0x1141fca1c/0x1141fcb50）。这是一段本地防重复门禁，
完整 item/graft 分支及 _isPrepared 重置未穷举（已定位 reload 0x1141ff058 清零；下一步 `find_data_refs_root.py 0x11f89e168`）。
已读reload0x1141ff058先清_isPrepared（0x1141ff074–0x1141ff07c），随后才调用
reportOfSceneDidEndWhenAlreadyPrepared:false并重新_loadVideoWithParsModel；stopPlay
0x1141fc2d8只stop/removeCurrentPlayerItem，没有在该body清此标记。全__text限定
ADRP+LDRSW ivar slot0x11f89e168的扫描只找到状态consumer的读/置true、结束helper
的读及reload的清零三个直接引用（地址清单保存在忽略目录），不排除其他寻址、间接
写入或对象重建。因此这里只闭合这条reload重置，不声称枚举完所有实例生命周期。
replay0x1141ff16c则是另一路：先清_end（0x1141ff18c），直接调用开播报告
（0x1141ff190），再reportFirstFrameTime、trackMetaInfoForHeartBeat
（0x1141ff198/0x1141ff1a0），随后才设置replayPosition/cleanAllPauseAndPlay/seek。
此入口没有前述_isPrepared门禁，也没有model.isShared判断包住Heartbeat构造调用；
构造helper内部仍有meta valid/Live门禁。因此startPlay shared跳过不能推广为replay
也跳过。开播Neuron事件在这次新HeartbeatContext创建之前，已读这段replay及
configTracker0x1141fe4dc没有resetPlayerSessionID调用；最终session仍取现有manager
缓存/其他外部reset，不能从replay直接断言新的session。
统一Tracker的2参数入口0x114880e88显式转instantly=false；3参数入口
0x114880e90验证eventId非空、构造BFCNeuronPlayerEvent，取当前播放进度/状态、
填公共Player字段和当时playerSessionId（0x1148810cc/0x1148810e4），复制调用方
扩展字典，再合入可选event callback字典（0x11488113c）及普通扩展公共字段，最后
false走event.track（0x1148811e8），true才trackInstantly（0x1148811e0）。不同报告
方法读取session的时机不等于HeartbeatContext中已有session的重写。
BFCNeuronPlayerEvent.category0x1161ef0b8固定raw9；继承的BaseEvent.track
0x1161eea60向BFCNeuron.shared交policy0，trackInstantly0x1161eeab0交policy1。
**同名候选方法已逐条排除**（不是同一 PlayerEvent 链）：
`-[UserCardBloc logToNeuronWithPlayerEvent:entries:]` 0x101eb063c 与
`-[TopRightMoreBloc logToNeuronWithPlayerEvent:entries:]` 0x101ee97a0 的实现体都是单条
`ret`（各 4 字节，紧随的 0x101eb0640/0x101ee97a4 只把两个入参
`static_String._unconditionallyBridgeFromObjectiveC` 后立即 release，无转发）；
`-[TopAreaBloc logToNeuronWithPlayerEvent:entries:]` 0x101e0a9c8 是尾跳
`b 0x101e0a5d8` 且 x4 载 selref `logToNeuronGeneralWithEvent:extries:`（0x11f78d508，原字面拼写如此）；
`-[BBLiveRoomTrackerBloc logToNeuronWithPlayerEvent:entries:]` 0x101f0f548 经
sub_101F0F240（0x101f0f5b8）走 selref `logToNeuronGeneralParameters`（0x11f...528），
同区 0x101f0f5f4 另有 selref `neuronWithEventId:extries:category:`。
四者都属通用 Neuron 事件族，均未构造 BFCNeuronPlayerEvent，也未调用
`BBPlayerTracker.trackPlayerEvent:`，故不能与前文 raw9 链合并描述。
即时选择只改变日志策略，不绕过下文公共构造/缓存。trackEvent接纳后将原event
retain到block（0x1161e9fa8/0x1161e9fac），没有在此处copy事件快照，返回true
也仅表明operation已入队（0x1161e9fe4/0x1161ea000），不是磁盘/上传成功。
字段取值顺序另须保留：Tracker先向自己的CommonFieldsModel设置播放进度
（0x114881048/0x11488104c/0x114881050），并非先设置event。进度来源为currentTime，
queue分支则仅当前cid匹配时取itemCurrentTime，否则0；秒值×1000（常量
0x1182e7c00）再fcvtzs到Int32（0x114881034/0x114881038），不是累计观看时长。随后
CommonFieldsModel.fillPlayerEventCommonFields:0x114881900从+0x18 Int32取刚存的
progress，再写event（0x11488198c/0x1148819b8）；不能误写成旧model覆盖已算event。
该helper先给event写model自身playerSessionId，Tracker才在之后用当前manager session再次覆盖
（0x1148810cc/0x1148810e4）。其他字段的已读构造如下。
已读common配置0x11487fe20把业务入参avid/cid/epid/seasonID/qualityNO/videoFormat/
playerType/videoType/videoSubType/videoDataSource/videoDirection/autoPlayState/
fromSpmid/playerSpmid/playbackMode/playerScene存新model；configCommonFieldsModel
0x114880070则更新已有model的danmaku config、poolState、playbackRate、
applicationState、Settings.playbackMode映射的listType及currentScene.response语言，
不在该body重建model。fillPlayerEventCommonFields现场取BFCReachability.currentStatus，
raw1→networkType1；raw2再按Bandwidth raw11/12→4、21/22→5、31→6、其余→2；
其他Reachability raw→3（0x114881a5c–0x114881ac4）。它与播放心跳的network_type
业务映射不同，不共享枚举含义。speed经stringFromPlaybackRate0x114882374：整数
倍率格式"%0.1f"，非整数用NSNumber(double).stringValue，不统一固定小数位。
quality经playbackQualityFromVal0x11488242c，仅15/16/32/64/74/80/100/112/116/120/129
原值保留，其他→0，再转十进制String；非直接所有currentQn透传。
autoPlayState非0原值保留，0才读Settings.shouldAutoPlay true→1/false→2
（0x11488250c）；fromSpmid空时写"default-value"（0x114881bcc/0x114881bd8）。
上述 field 构造与 AppPlayerInfo 的 18 项编码已闭合，其他业务配置与 observer 更新未穷举（下一步 `disassemble 0x114880314 0x114880400`）。
registCommonFieldsValueChangedListener0x114880314已见六组更新：quality proxy的
currentQuality→qualityNO；danmaku.config.enableShowDanmaku true→1/false→2；
danmaku.poolState仅unsigned raw≤2更新dmServiceState；context.status.fullScreen
true→playbackMode2/false→1；playback.playbackRate→model Double；Settings.playbackMode
经表raw0/1/2/3→listType1/3/2/5，其他→0（0x119074fa0）。前五组
bbp_observeObj options raw3，Settings组rac_valuesForKeyPath/subscribeNext。
callback弱取原Tracker后读其当时_commonFields，不是捕获旧model对象；这些更新
不在该body重置seq/session或直接发请求。重复注册与observer更高层解绑仍需核对。
appendCommonFieldsToExtends:0x114881bf4的输入为nil或通过class门禁时会copy输入
字典并补12个内部键；非nil且不通过则返回原对象（0x114881c34/0x114881f64）。所有键
仅objectForKeyedSubscript结果为nil时才补，调用方已给空String也保留。键包括
$player_playback_state/$player_is_vertical/$is_background_play/$is_local_video/
$dm_service_switch/$player_event_seq/$playerSpmid/$player_scene/$idfa/$idfv/
$cur_language/$perfer_type（静态key表0x11cf91e70–0x11cf91ec8），不能与外部无$
的 idfa/track_id 等键混同。$idfa/$idfv 缺失才读 VKIdentifier，实际标识值未读取（设备凭据不输出；下一步 `disassemble 0x114881bf4 0x114881f80`）。
$player_event_seq缺失时取model+8旧Int32转十进制String，再把缓存+1
（0x114881ed8–0x114881f10）；提供该键则不递增。model.initWithPlaySession:
0x114881884初始化seq=0（0x1148818dc），这是实例报告次序而非推荐report编号、
请求次数或服务器 ack 计数；其他业务配置调用与 session reset/继承关系未穷举（下一步 `disassemble 0x11487fe20 0x11487ff00`）。
其中common配置入口0x11487fe20已闭合：每次无条件读取manager.playerSessionId
（0x11487fec8），调用modelWithPlaySession:（0x11487fee0）并替换_commonFields
（0x11487fef0/0x11487fef8）。工厂0x114881838实际alloc/init新model
（0x114881858/0x114881864），不是按session查缓存。因此即使manager仍返回相同
session，重新config也会使新model的seq从0开始；内联replay先调用的开播事件入口
经configTracker走该配置链，不能把seq归零当成新播放session的证据。
同一个内联UGC/PGC/EDU开播入口随后调用BFCAppsFlyerWrapper.logEvent("media_play",nil)
（0x1141fe070）；但本8.89改动样本的实际wrapper实现0x115ee2918仅单条ret。
这条已读路径未形成AppsFlyer上传链，不能从SDK命名/调用字面断言真实发送，也不能
把此样本no-op推广为未修改官方包或其他版本的行为。
Tracker.initWithContext0x11487f818创建自己的BBPlayerSessionManager；tracker getter
0x114880040转manager.playerSessionId0x11487f53c，已有非空缓存直接返回，nil/空才
createSessionID并保存实例+8。resetPlayerSessionID:0x11487f5c8只把旧缓存置nil，
传入String仅供日志，不拿它作为新session；inheritSessionID:0x11487f630才在入参
非空时strong保存为缓存，不能把实例缓存误写成整个应用process-once或每个心跳都新建。
已见reset caller包括CommonVideoScene.on_scene_did_complete0x11487c530：model.isShared
为false且传入完成BOOL非零才取context.tracker并reset（0x11487c59c）。Tracker自己的
playerDestroyed observer0x114881510则要求old=false/new=true才reset
（0x114881578）；它不同于HeartbeatService的“bool改变即符合”结束条件。
继承caller包括BBPlayerContext.rebindSessionID:0x11481f9ac，参数是另一context，
从参数.tracker.playerSessionId取值再交self的弱tracker.inheritSessionID
（0x11481f9d8/0x11481fa00），nil参数直接返回。Tracker.attach:params:
0x11487fc68另要求传入对象是BBPlayerTrackerGraft，取其playerSessionId继承
（0x11487fcdc），随后把graft.heartBeatContext交appendSliceContext、更新params并
markSliceResumed。这里存在明确复用路径；其他reset caller及迁移后的全部业务字段
未穷举（下一步 `find_callers.py 0x11487f5c8` 与 `disassemble 0x11487fc68 0x11487fd80`），不能从重建播放器对象断言新 session。
appendSliceContext0x11488931c拒绝nil及与当前context同一对象，否则直接strong保存
传入context（0x114889364），makeSliceNode（0x11488936c）后才bind当前新playback
（0x1148893a0），不是复制后新建HeartbeatContext。makeSliceNode0x114885254置
isSliceNode +0x37=true，先calculateTotalTime(false)，从仍绑定的旧weak playback取
rate，单精度计算actual_played_time=played_time×rate再向零转整数
（0x114885294–0x1148852a8）；scene_type==1时另复制played_time到list_played_time。
此方法未重建session、未清wire start_ts或调用setupDefaultConfig。service的
markSliceCompleted/Resumed0x1148893f0/0x114889404只置/清service.isCompleted，
不能把它们当作context.invalidate或session reset。
attach:params:随后取curHeartBeatContext并updateMetaInfoWithParams:
（0x11487fd48/0x11487fd5c），再markSliceResumed。更新helper0x114884ea8对nil params
返回；from、spmid、fromSpmid、curLanguage、curLanguageSource仅length非0才覆盖；
sceneType/playMode/attachedAvid须通过相应class门禁再intValue/longLongValue赋值，
sceneMap/extraInfo也有class门禁。extraInfo通过时复制现有legacyExtra，再
addEntriesFromDictionary输入（0x114885170/0x11488519c）并setLegacyExtra
（0x1148851a8），同键由新输入覆盖。此已读helper没有avid/cid/epid/session/start_ts
setter，缺失字段保留旧meta；不能把迁移params当成完整新播放元信息替换。

updatePlayedTime（0x114885674）仅在 context 有效标志为 1 时执行：取当前墙钟 Unix 秒
向零截断，减去上次计时秒；played_time 加该整数差，actual_played_time 用
单精度 `delta × playbackRate + previousActual`（fmadd）后向零转整数，并更新计时基点。
所以此实现中 played_time 是播放状态下的墙钟增量，actual_played_time 是倍率加权值；
名称不能代替含义。负时间差、单精度误差和逐段截断仍可能影响结果，没有在此方法看到
把负差 clamp 为零。updatePausedTime 以相同墙钟基点累加 paused_time。
setupDefaultConfig0x114885aa4先把NSDate Unix秒向零截断存_start_anchor_ts（+0x10），
再把BFCServerTimeChecker.realTimeInterval同样截断存_start_verify_ts（+0x18），
_last_action_ts（+0x20）复用前者。实验ff_player_vt_start_ts_862（preset0）命中时才
再次取realTimeInterval初始化wire start_ts（+0x50），未命中设0，后续仍可由HTTP回执
覆盖。getLocalStartTimestamp0x114885230读取的是_start_verify_ts，并非NSDate那份；
不能只凭“Local”方法名推断所有时间字段同源。此方法还清零各累计时长、取playbackRate
并初始化duration/quality，开始报告的generateMutableDictForEvent会调用它。
calculateTotalTime（0x1148863a8）对 playbackState=3 走 updatePlayedTime；其他状态经
verifyPlaybackState（位掩码原始值 30）及传入参数决定播放/暂停分支。随后令
`total_time = played_time + paused_time`，并更新媒体位置。完整状态枚举与计时调用频率
未穷举状态分支（下一步 `disassemble 0x1148863a8 0x114886500`），不能仅凭这组方法断言暂停、缓冲、seek 的所有行为。

playStart/playEnd 先构造可变计时字典，再合并 metaInfo.generateDict 与扩展字典，最后
调用 reportEvent。结束路径包含 invalidate，重复/无效开始和缺少开始的结束另走
player.heartbeat.start-assert/end-assert 技术事件。catchAndStorePlayEndData 构造结束
数据交给 ReportManager.stashItem，clearStorePlayEndData 则移除 stash；缓存快照不等于
已经实际发送一次结束请求。

BBPlayerHeartBeatReportManager.init（0x11488770c）创建内存数组、递归锁和串行 API
队列。reportWith（0x114887940）将非空 item 加入内存；syncToFileCacheImmediately 为
真时同步文件后退出这个入口，为假时仅在 reachability.currentStatus 非零时触发发送。
“立即同步”指文件缓存，在这条分支不意味着立即联网。
loadFileCache 在同一串行队列读取归档数组、合入内存后触发 reportWith:nil；实际caller
为BBPlayerCoreModule.onModuleInitializedConfig0x1147ddd4c，先取sharedManager再
loadFileCache（0x1147ddd60/0x1147ddd70），该调用在后续hasLogined检查之前。
这闭合恢复发起方，模块初始化实际送达及网络reachability仍是独立门禁。
syncFileCache 对内存数组加上最后一条 stash 做 NSKeyedArchiver
归档；路径来自系统目录原始枚举 13，文件名 heartbeat.v2.cache 与
heartbeat.v2.cache.copy，并有写临时副本/移除/移动分支。**清理触发时机本轮逐分支读出**
（0x114887b6c–0x114887f60，日志 tag 均为 CFString `main.player.core` 0x11d3879d0，
logger sub_1167AA048 w0=7）：无缓存分支 0x114887cc0 `cbz x0` → 0x114887d58 起对两条路径
各发 `removeItemAtPath:error:`（0x114887d78、0x114887da0），随后记
`[HEARTBEAT] ERROR: no cache to sync`（0x11d387d30，行 119）并退出；
有 lastItem 分支则先 `createCacheFile:`（0x114887d50 或 0x114887dd8，失败 0x114887de0
`tbz` 退出），再用 `fileExistsAtPath:`（0x114887df8）+ `csel x0,x21,x20,ne`（0x114887e10）
选源路径，`removeItemAtPath:`（0x114887ea0）清理后 `moveItemAtPath:toPath:error:`
（0x114887ee0）落盘：失败记 `[HEARTBEAT] ERROR: move file failed %@`（0x11d387d90）、
成功记 `[HEARTBEAT] ERROR: sync file cache success`（0x11d387d50，行 143）、
缺文件记 `[HEARTBEAT] ERROR: not found file cache`（0x11d387d70，行 147）。
即 **文件删除只发生在 `syncFileCache` 内**（不是 loadFileCache/loadCachedReportItems，
后两者只读）。完整异常恢复、存储保护和
loadCachedReportItems0x114888570检查文件存在/NSData非空，再unarchive；该方法未
读取当前时间、item年龄或账号。loadFileCache的排队block0x114887854将返回数组
直接addObjectsFromArray到memCache（0x1148878bc），非空时reportWith:nil、
syncToFileCacheImmediately=false、apiCallback=nil（0x114887920），没有在这段
恢复包装按 TTL/账号过滤。这里只限定已读恢复路径：**文件删除时机已在上文 syncFileCache 三条分支闭合**，
仍未闭合的是这些缓存项的 TTL/账号过滤本身（loadCachedReportItems 0x114888570 已证不读时间/年龄/账号；
`disassemble 0x114888570 0x114888640` 可复核该点），
没有读取实际缓存文件或将缺少TTL门禁外推为永久保存。

reportTrigger（0x114888230）复制内存快照，逐条同步调用 postApiWith；失败时最多再试
两次，先 sleep(5)，再 sleep(10)，即每轮至多三次尝试，发生在串行 API 队列。
成功后按 item.hash 匹配移除内存项；失败用尽会停止这轮，后续触发/缓存同步另有条件。
这里不是通用 HTTP 层的全局重试，也不是 Neuron 的间隔退避。

postApiWith（0x1148888b0）要求非空 item 与非空 session；复制参数后补当前 idfv/idfa
和 polaris_action_id，删掉内部 hash/isStart，使用 BFCApiOptions 原始 requestMethod=1
向 `https://api.bilibili.com/x/report/heartbeat/mobile` 发送 requestSync。
completionHandler 从映射的 /data 取 ts 并记成功；errorHandler 另有 response 为 HTTP
对象且 statusCode=200 时也记成功的分支，其他情况记录错误 code。由此不能把
BFCApiRequest 的 error callback 一律当作本队列失败；正常 completion 的业务错误解析
仍依赖公共响应层。成功回执只证明该层完成条件，不证明推荐兴趣已生效。

服务端ts有具体反馈点：reportTrigger的同步postApiWith成功后，仅snapshot index0
且apiCallback非nil时把serverTs排到main（0x11488843c/0x114888484/0x114888494），
block0x114888560调用捕获callback。Context.reportEvent0x1148866e0安装的callback
0x114886910弱取原context，非nil就写start_ts（实例+0x50，0x11488692c）；没有
captured session/hash/current start比较或ts>0门禁。每次调用postApiWith前先把serverTs
out初始化0（0x11488836c）；HTTP200错误分支也可被判成功，故这个成功判据不保证
callback取得正ts。该反馈写入与队列首项有关，不能补成整播放器全局校时或按session
匹配回执；真实并发交错属运行期、静态不可定，其他 start_ts writer 未穷举（下一步 `find_data_refs_root.py` 扫 +0x50 槽）。
当前仍缺 metaInfo 创建方完整赋值、文件缓存 hash 的冲突处理、整个播放器生命周期
触发频率，以及与 9.13 抓包同版本核对。


Context.generateMutableDictForEvent（0x114885bcc）输出 session、start_ts、
video_duration、total_time、played_time、paused_time、actual_played_time、list_play_time、
miniplayer_play_time、last_play_progress_time、max_play_progress_time、quality、is_auto_qn。
开始/结束分支分别初始化或读取计时状态，不可把全部字段视作每次新计算的播放位置。
MetaInfo.generateDict（0x114886d4c）再输出 mid/aid/cid/sid/epid/type/play_type/sub_type/
play_mode/network_type/auto_play/epid_status/play_status/user_status，以及 from/spmid/
from_spmid/track_id/sessionID。字符串 from/spmid/from_spmid 缺失时填 default-value，
track_id/sessionID 缺失时填空；attached_avid 受 playerDefaultQueue 分支控制，
cur_language/perfer_type 有空字符串兜底（perfer_type 是原字面拼写）。字段可定位到
MetaInfo 属性，但多数属性仍需追踪赋值方，不能仅根据常见参数表填常量。

Context.generateExtDictForEvent（0x114886290）生成内部 isStart（开始 1、结束 0）与
hash（NSUUID.UUID.UUIDString，nil 时空字符串）。hash 用于缓存匹配，发送前删除；
它与基于 BUVID/时间的播放 session 分工不同。currentVideoInfoMergeToExtraForPlayEnd
在 v8.73.0_heart_beat_add_extra_video_info 条件下，从当前播放 URL 获取去 query 的末尾
路径与 qn_dyeid，写 video_file_name/video_dye_id 到扩展资料；不是把整个播放 URL
直接作为业务上报字段。extra/legacyExtra 的条件合并与 JSON 串、sceneMap 的实际使用
未穷举（下一步 `disassemble 0x114886290 0x114886400`），不把这一层看到的键视为整个应用心跳字段全集。

服务创建也有具体来源：BBPlayerTracker.initWithContext0x11487f818从context取
serviceManager，以BBPlayerHeartBeatServiceV2 class调用createService
（0x11487f8fc/0x11487f90c），将返回对象weak保存为heartBeat（0x11487f92c）；getter
0x114881790 weak-load该成员。service init0x1148890dc设reportPolicy raw1和completed=false。
BPInlinePlayableContainer.updatePlayerConfiguration在0x1141f7474把当时config.reportPolicy
复制给context.tracker.heartBeat；不能用service默认值替代Inline配置。
StoryPlayerContainer.reportHeartBeatEnd0x1132fed5c先排除isLiveSourceType，随后将同一路径
heartBeat.reportPolicy设raw3（0x1132fedf4）再playEnd（0x1132fee44）。raw1/3的bit2均0，
但不能由这两个caller排除其他动态写入或所有入口的其他policy。
Service.serviceOnStart0x114889130调用super后addObservers；serviceOnStop
0x114889178调用super、removeObservers、unbindServiceProxy及checkExceptionBeforeExit。
addObservers0x114889990观察playback的playbackRate、itemDuration、buffering、
itemPlaybackState与playerDestroyed，再观察qualityProxy.currentQuality、设置seekProxy
的seekToTimeHandler，并以object=nil注册UIApplication前后台通知。状态观察options
raw7，其余所列KVO为raw3。BBPlayerObject的观察wrapper0x114820764从change取OldKey/
NewKey（0x11482082c/0x11482084c），在main直接按old/new顺序调用block
（0x114820880/0x114820884），off-main排main（0x1148208ec）；线程与参数顺序来自
实际wrapper，不从邻接回调名猜测。
itemPlaybackState block0x11488a2c0先要求弱service存在、old!=new、当前heartbeat
context.isValid。new raw3先updatePausedTime，old raw2或5才_playStartReport；
new raw4先updatePlayedTime，old raw2才同样报告开始。new raw5按old raw3更新played，
否则更新paused。结束报告条件为new raw6，或new raw5且old!=1，或new raw0且old为3/4；
传给_playEndReport的withSyncImmediately=false，其中最后一组old=3才传首个BOOL true，
其他结束分支为false。这些是原始状态值与不同报告门禁，尚不为全部raw值补业务名称。
playerDestroyed block0x11488a414只在bool变化且context有效、verifyPlaybackStatePrepared
通过时报告结束（两个BOOL均false）；已检查分支未要求新bool必为true。
seek block0x11488a5b0要求isMatchOriginCid及有效context才updatePlayProgressTime，
不是独立HTTP。rate、duration、buffering及quality回调还分别比较old/new并要求
isMatchOriginCid与有效context，计时/字段同步不能视为每次都立即发送网络请求。

前后台也不是统一结束：applicationDidEnterBackground0x11488b0b8先要求!isSuspend、
verifyPlaybackStatePrepared、有效context及未completed；reportPolicy bit2为0时仅
catchAndStorePlayEndData（0x11488b1a4），为1时调用service.playEnd
（0x11488b1bc）。applicationWillEnterForeground0x11488af54先排除isSuspend：有效且
未completed时clearStorePlayEndData；若context无效且reportPolicy bit2=1，则先
resumeTrackerMetaInfo，重新确认有效且未completed后_playStartReport
（0x11488b0b4）。两种policy决定stash清理或重新开始，不能把系统通知本身当成功回执。
