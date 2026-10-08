# Neuron Protobuf 日志通道

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## Neuron Protobuf 日志通道

### 编码与缓存时点

`BFCNeuron.trackEvent:trackPolicy:`（0x1161e9da8）先处理 logId，并询问 delegate 是否
采集该 logId/eventId；被接纳时记录时间，将 blockOperation 放入 trackQueue。真正的
公共信息与 Protobuf 构造发生在 block（0x1161ea030）内：preferences.sn 加一，然后读取
appInfo、appRuntimeInfo、delegate.mid，填入 AppEvent。这些身份/运行时字段不是全部
在业务调用入口提前快照；排队期间账号或状态变化的影响需另外验证。

字符串 getter 有 nil 兜底；AppInfo.uid 在该路径显式设 0。extendedFields 可变复制后
加入 event_policy（trackPolicy 的十进制字符串），pageType 和 snGenTime 分别设置。
enable_public_parameters 开启时，extra 中加 polaris_action_id 与 start_session_id。
随后调用 observers，把序列化 data 和分类、SN、ctime、mid 等构造成 CacheItem，先
saveCacheItem，再按 delegate 的即时上报判断或 didTrackItem 调度。磁盘失败回退、配额、
完整计时策略未逐项解码，跨账号处理属**运行期账号切换、静态不可定**；下一步
`$PY disassemble.py 0x1161ec634 0x1161ec980`（updateCacheItem）并反汇编配额分支。

原始分类值在该构造器中为：Other=0、Pageview=1、Click=2、Exposure=3、System=4、
Tracker=5、Custom=7、Compatible=8、Player=9；未见 6 不表示协议禁止该值。
Click 子消息在该版本是空结构，点击扩展信息放在 AppEvent.extendedFields。
Exposure 子消息重复保存内容的 eventId 和扩展字段，不能当作普通单条 click。
Player分支有具体编码链：operation执行时对捕获event做BFCNeuronPlayerEvent
class检查（0x1161eaedc–0x1161eaef8），通过后设eventCategory=9，创建
BFCNeuron_AppPlayerInfo，逐getter/setter复制下表18字段，再挂AppEvent
（0x1161eaf04–0x1161eb144）。这里保留原event中的progress/playerSessionId等，
没有重新从Tracker/current playback取值；与同一operation更早读取delegate.mid
的时点不同。字段getter自身的String nil兜底见具体event类，不据PB声明统一成整数。

**对象身份与第二条转换链（本轮闭合）**：`BFCNeuronPlayerEvent` 是 **ObjC 协议**
（`_OBJC_PROTOCOL_$_BFCNeuronPlayerEvent` 0x11d88fec0），协议属性名与具体类
`_TtC6Neuron11PlayerEvent`（Swift `Neuron.PlayerEvent`）完全一致；该类的 type metadata
accessor 0x104967fa0 只引用 classref 槽 0x120490ad8，而该槽全镜像只有 1 处 ADRP+ADD
（即 accessor 自身，find_data_refs_root 扫描）→ **不存在 ObjC `[[PlayerEvent alloc] init…]`
形式的主程序构造点**，实例只能经 Swift 侧 `initWithId:`（0x104967e84→sub_104967E1C）
或 unserialize 产生。第二条 PlayerEvent→protobuf 转换在 `sub_104974BE0`
（0x104974be0，由 0x1049745d8/0x104974848 调用）：先按类分派 eventCategory
（0x104974dc0 TrackerEvent→5、0x104974de8 CustomEvent→7、0x104974e10 CompatibleEvent→8、
0x104974e38 PlayerEvent→9，与上表同值），再 `allocWithZone` `BFCNeuron_AppPlayerInfo`
（0x104974e70）并按序 setPlayFromSpmid / setSeasonId / setType / setSubType / setEpId /
setProgress / setAvid / setCid / setNetworkType / setDanmaku / setStatus / setPlayMethod /
setPlayType / setPlayerSessionId / setSpeed / setPlayerClarity / setIsAutoplay / setVideoFormat
（0x104974eb0–0x10497520c），最后 setAppPlayerInfo（0x104975214）挂到外层事件。
**四个 bloc 不是构造者**（按共享 stub 判据复核）：`-[UserCardBloc logToNeuronWithPlayerEvent:entries:]`
0x101eb063c 与 `-[TopRightMoreBloc …]` 0x101ee97a0 的函数体各只有一条 `ret`
（0x101eb0640 起为新函数）；`-[TopAreaBloc …]` 0x101e0a9c8 是尾跳 `b 0x101e0a5d8`
且 x4=selref `logToNeuronGeneralWithEvent:extries:`（0x11f78d508）；
`-[BBLiveRoomTrackerBloc …]` 0x101f0f548 只做
`String._unconditionallyBridgeFromObjectiveC` / `Dictionary._unconditionallyBridgeFromObjectiveC`
后调 sub_101F0F240，同区另一入口 0x101f0f5f0 用 selref `neuronWithEventId:extries:category:`。
四者都在 `logToNeuronGeneral*` / `neuronWithEventId:` 一族，不构造 BFCNeuronPlayerEvent，
也不在 `_objc_msgSend$trackPlayerEvent:extendsFields:`（0x1176ead60）的调用方里。

### 消息描述符

descriptor 方法（0x116202cd0–0x11620303c）使用 32 字节字段项，恢复了以下 68 项；
下表的编号来自声明，不能由声明推断所有字段在每次请求中均出现。

| 消息 | 编号:字段 |
| --- | --- |
| AppInfo（15） | 1:appId, 2:platform, 3:buvid, 4:chid, 5:brand, 6:deviceId, 7:model, 8:osver, 9:fts, 10:buvidShared, 11:uid, 12:apiLevel, 13:abi, 14:bilifp, 15:sessionId |
| AppRuntimeInfo（9） | 1:network, 2:oid, 3:longitude, 4:latitude, 5:version, 6:versionCode, 7:logver, 8:abtest, 9:ffVersion |
| AppEvent（18） | 1:eventId, 2:appInfo, 3:runtimeInfo, 4:mid, 5:ctime, 6:logId, 7:retrySendCount, 8:sn, 9:eventCategory, 10:appPageViewInfo, 11:appClickInfo, 12:appExposureInfo, 13:extendedFields, 14:pageType, 15:snGenTime, 16:uploadTime, 17:appPlayerInfo, 18:extra |
| AppPageViewInfo（5） | 1:eventIdFrom, 4:loadType, 5:duration, 6:pvstart, 7:pvend |
| AppExposureInfo（1） | 1:contentInfosArray（重复子消息） |
| AppExposureContentInfo（2） | 1:eventId, 2:extendedFields |
| AppClickInfo（0） | 空声明 |
| AppPlayerInfo（18） | 1:playFromSpmid, 2:seasonId, 3:type, 4:subType, 5:epId, 6:progress, 7:avid, 8:cid, 9:networkType, 10:danmaku, 11:status, 12:playMethod, 13:playType, 14:playerSessionId, 15:speed, 16:playerClarity, 17:isAutoplay, 18:videoFormat |

fts/ctime/SN/时间字段的声明均为整数类型；部分播放器值如 progress、speed、avid、cid
声明为字符串，不能根据业务含义统一改成整数。经纬度为 double，network/eventCategory
为枚举；extendedFields/extra 是 map 结构，仍需核对生成器具体类型元信息和所有取值。

### 请求分帧与回执

requestForItems（0x1161ecea4）对 batchReport 和 scheduleReport 使用
`https://dataflow.biliapi.com/log/pbmobile/unrealtime?ios`，其他 report 对象使用 realtime
路径。**两个 URL 都是主程序内的硬编码 CFString 常量，不走服务端配置下发**：
0x1161ecf34–0x1161ecf40 载 `https://dataflow.biliapi.com/log/pbmobile/realtime?ios`
（0x11d3dac90）与 `https://dataflow.biliapi.com/log/pbmobile/unrealtime?ios`（0x11d3dacb0），
选择指令是 0x1161ecf08 `cmp x0(batchReport),x23(arg)` + 0x1161ecf44 `cmp x22(scheduleReport),x23`
+ 0x1161ecf48 `csel x2,x9,x8,eq`：report==batchReport（0x1161ecf50 分支）或 ==scheduleReport
→ unrealtime，否则 realtime；随后 `[NSURL URLWithString:]`（0x11713edc0）+ NSMutableURLRequest
`requestWithURL:`（0x1174f36e0）。先将缓存 data 解析为 AppEvent，设 uploadTime 为当前 Unix 毫秒，再序列化。
每条消息单独调用 packagePayload（0x1161eb154）；元信息字典包括 logId、eventId、
appId、appVersionCode、platform，后三者是十进制/版本字符串。字典 allKeys 没有显式排序。

分帧由指令恢复为：`RDIO` 四字节、四字节大端长度/标志、一个校验字节、body。
body 是元信息逐项编码后拼接 Protobuf：单字节 key 长度 + key，再四字节大端 value
长度/标志 + value。value 长度最高位置 1 表示还有下一元信息项；外层长度最高位置 1
表示含元信息。其余 31 位表示 body 长度。body 超过 0x4000000 的分支会清空 body；
0x4000000 = 64 MiB 检查的是**单条事件 payload+meta 的 body**：
packagePayload:metaDict: 0x1161eb154 在0x1161eb2e8–2fc超限置nil；requestForItems
循环每条在0x1161ed278调用，再0x1161ed290拼帧。原“调大batchSize/packageSize
才可达”的推论错误撤回；它们调整批量数量，不等于单事件体积。真实超限输入与
进程内存/传输可达性另验；配置默认数量不能作为单帧安全上限的证明。


校验只作用于外层四字节长度/标志字，并按从低到高四个字节查包内 256 项表：
`a=T[b0]; a=T[b1 xor a]; a=T[b2 xor a]; checksum=T[b3 xor a]`。不要将其误写为
body 校验或未经证明的标准 CRC。代码对元信息取 NSString.length，却写 UTF8String
指针；当前已知键和值为 ASCII，非 ASCII 或超长键的边界行为未校正。

多条完整 frame 直接拼接为 POST body；delegate.gzipEnableForNeuron 决定是否整体 gzip。
请求头 Content-Type=`application/octet-stream`，启用时 Content-Encoding=`gzip`，
Neuron-Events 为 items.count 十进制字符串。最后可由 requestInjector 再改写。
reportItems（0x1161f2280）分包后可走 client.taskWithRequest 或 httpService.startRequest，
由 delegate.switchReportSchemes 选择；该层记录开始/结束、发送/接收字节数，再通知回执。

didFinishTask（0x1161ed618）仅在无 error、响应为 HTTP 且 status=200 时删除缓存，
未在此层解析响应 body。status=449 或 500–599 先 handleFlowControl，再更新缓存；
其他失败直接更新缓存。updateCacheItem（0x1161ec634）的更新 block（0x1161ec850）
解析原 data，retrySendCount 加一后重序列化；不是重新生成 AppInfo/mid 的完整事件。
每次发送则刷新 uploadTime。重试时保留哪些业务身份与哪些时间变化已可分开描述，
但最终调度间隔、次数上限和过期清理已能分项定性：间隔由 Configuration.init（0x1161ee904）
默认 interval=3 / maxInterval=30 与 handleFlowControl 的 interval+arc4random_uniform(interval>>1)
决定；**次数上限在本镜像内没有找到**——updateCacheItem 的更新 block（0x1161ec850）在
0x1161ec87c 只 `retrySendCount` 读一次后加一重序列化，附近没有与上限常量的比较，
全镜像按 `maxRetry*` 与 `retrySendCount` 检索也未见 Neuron 事件缓存侧的静态上限，
故不应写成存在固定重试次数；过期清理的静态依据是 expireDays=7 与 isClearOverdue=false
（0x1161ee904 默认值），**mainDelayAB/disk_cache_delay 分支已闭合**（见下节），精确残余只剩
过期清理的触发时机。

离线验证以包内校验表和指令等价实现检查了 10,000 个随机长度/标志字、21 个假 ASCII
元信息/负载往返及损坏校验拒绝，核对上述 68 项描述符。产物保存在分析目录的
neuron-offline-validation.json；未执行官方二进制函数、未发送请求，不能算服务器接受
或 9.13 同版本验证。

### 调度、后台与流控

Configuration.init（0x1161ee904）的内置默认值由实例存储偏移和常量共同确认：
batchSize=120、packageSize=30、minPackageSize=15、interval=3、maxInterval=30、
mobileQuota=3145728、waitingThreshold=20、waitingMinutes=10、expireDays=7、
batchSizeFactor=1；isMainClear/isClearOverdue/isTesting 为假、testInProdFlag 为真。
这是新配置对象的默认值，运行时覆盖仍需逐项追踪；quota/等待属性的单位和使用位置
见后续条件链，不能仅从名称推断。

Neuron.init（0x1161e94d8）创建串行 track/report operationQueue（各并发数 1）、串行
report.build dispatchQueue、信号量、缓存及三种 report 对象。runWithConfiguration
（0x1161e9848）将 interval 最小设为 1，复制 batch/package size，将 timer 加入
主 RunLoop 的 CommonModes，首次 fireDate 设为当前时间 +1 秒，并实际注册
UIApplicationDidEnterBackgroundNotification。mainDelayAB/disk_cache_delay 的延迟分支**已闭合**
（team-c21，证据 DerivedData/Validation/team-c21/findings.md N1）：两者唯一消费者都是本方法；本轮补到真实事务清理（root-static-fnval/neuron-u12.md）：
openCacheWithExpireDays 0x1161eca54 忽略入口days、锁内重读configuration.expireDays；
cache 0x1161ef6f8 在diskCacheEnabled=false时跳过。true计算cutoff为unsigned截断
now秒×1000−uint32(expireDays×86400000)，注意32位乘法；disk open0x1161f08d8→
transaction0x1161f09ec，CREATE成功后0x1161f0a78–88执行DELETE FROM
neuron_scheduled_report_data WHERE _ctime < ?，失败rollback。真实DB结果/队列竞态另验。
Memex初始化读取neuron.enable_main_clear_v2、neuron.enable_clear_overdue_v2（preset0）；
neuron.expire_days经getConfig/updateValue→KVC setValue，setter STRH，执行时可变，
不能写死默认7。
（0x1161e98fc / 0x1161e99a8）。`isClearOverdue` 为真跳过旧openCache分支到0x1161e9994，后续调度仍继续；原“直接结束”撤回（0x1161e9884）；`isMainClear` 为真
改走 global queue 异步 block 0x1161e9c80（0x1161e98e0）。`mainDelayAB == 0` 时
`dispatch_time(0, 0x2540be400 = 10s)` 后 main 队列 block 0x1161e9c3c 调
`openCacheWithExpireDays:[configuration expireDays]`（0x1161e9940–0x1161e9990），`!= 0` 则同一调用
**立即**执行（0x1161e9910–0x1161e9930）；`disk_cache_delay == 0` 时先
`[self.cache setDiskCacheEnabled:0]` 再 `dispatch_time(0, 0xb2d05e00 = 3s)` 后 main 队列 block
0x1161e9cc4 置回 1（0x1161e99d0–0x1161e9a2c），`!= 0` 不做开关（0x1161e99b8）。随后
`setEnable_public_parameters:`、`setTimeInterval:max(1, interval)`（0x1161e9a80 `cmp #1` + `csinc`）、
`setBatchSize:`/`setPackageSize:` 与 fireDate=now+1s 都在同方法内；后台观察者 0x1161e9cfc 依次
`closeDiskCache`、fireDate=distantFuture、removeObserver(UIApplicationDidEnterBackgroundNotification)、
置 self+8=0。两个 getter 的实验键分别是 `neuron_main_delay`（0x114551774）与
`neuron_disk_cache_delay`（0x114551798）；键名与取值极性不能互推（`hitExperimentalGroupForKey:`
返回真=命中实验组）。

reportByTimer（0x1161ebdec）先暂停 timer 到 distantFuture，再按 common/schedule
计数触发 reportWithCommonCount；完成 block 将 fireDate 设为现在 +timeInterval。
因此这里是完成后再安排时间，不能简单描述成固定每 3 秒发一次请求。进入后台会创建
UIKit background task，并以最大计数请求排空上报；完成或过期 block 结束后台任务。
这不保证系统允许全部网络任务在后台完成。

handleFlowControl（0x1161ebbdc）在当前 timeInterval <maxInterval 时，加基础 interval，
再加 arc4random_uniform(interval >>1)；未看到对加完结果再次 clamp 到 maxInterval，
不能写成严格上限。batchSize >minPackageSize 时按整数除 2 缩小，packageSize 大于
minPackageSize 时直接设为 minPackageSize。这是加法退避与分包缩小，没有在此方法
实现指数退避或立即重发。流控恢复、移动网络配额与缓存等待策略未逐一解码（下一步 `disassemble 0x1161ebbdc 0x1161ebe80` 与 0x1161ee904）。

shouldReportItems（0x1161ecc70）首先拒绝空数组和 network=3；对非 batchReport 返回真。
batchReport 在 network=2 时还要求 mobileFlow <mobileQuota。无论 network=1/2，
满足配额条件后，items.count >=waitingThreshold 可发；数量不足时要求 sendTime 非零，
且距上次开始发送达到 waitingMinutes ×60000 毫秒。sendTime=0 且数量不足不会仅因
首次 timer 触发就放行。force/schedule 的不同许可条件说明不能把批量等待门槛施加到
所有事件类别。

network=2 的配额日界线由整数算术确认：
`floor((now_ms + 28800000)/86400000)*86400000 - 28800000`，对应固定 UTC+8 午夜，
不读取系统时区。当 flowUpdateTime 早于该界线时，mobileFlow 清零并记当前时间。
didStartTask（0x1161ed4ac）仅对 batchReport 记录 sendTime；network=2 时把
request.HTTPBody.length 加到 mobileFlow 并更新 flowUpdateTime。因此默认配额是
3 MiB 的已组装 body（启用 gzip 时为压缩后）发送尝试字节，未等成功回执，不是事件数
或全应用流量。该层未包含其他报告对象、请求头或传输协议开销。

UTC+8 日界线的乘高位/移位指令与除法公式另外对 10,005 个非负假时间值进行了离线
等价核对。异常系统时间、整数溢出、配额持久化与客户端重启属运行期/环境依赖，静态不可定（需真机采集；下一步 `disassemble 0x1161ec634 0x1161ec980`）。

### 公共信息与采样配置

`BFCNeuronInfoDelegate`（0x114551764–0x1145517c8）从实验服务查询
neuron_post_gzip、neuron_main_delay、neuron_switch_net（此入口 presetHitValue=0）、
neuron_disk_cache_delay、neuron_enable_public_parameters；scheduleTimeInterval 从远程
配置 neuron.track_polling_seconds 取整数，默认 0。是否命中及配置服务自己的默认逻辑
是否命中及配置服务默认逻辑未贯通（服务端下发值，静态不可定；下一步 `query_index.py '*neuron*' 60` + `disassemble 0x1161ee904 0x1161ef000`），不能据实验键存在推断开关当前开启。

shouldCaptureLogID（0x11455188c）仅对配置 neuron.trackt_log_id 指定的 logId 采样，
该配置默认字面值为 002312；其他 logId 返回真。对应 neuron.trackt_rate 默认 1.0。
shouldCaptureEventID（0x114551978）查 neuron.event_rates 字典，缺字典或缺该 eventId
返回真，有值时采用同一判断：`arc4random() / 4294967295.0 <= rate.doubleValue`。
比较包含等号，不是严格小于；没有在此两函数看到把 rate clamp 到 [0,1]。
这两道判断在事件进入 trackQueue 之前执行，因此被采样丢弃的事件不会走上述编码链。

InfoApp.brand 返回 Apple，chid 来自 BFCAppChannel.channel，buvidShared/abi 返回 nil，
apiLevel 返回 0，bilifp 调用注入 device 对象的 fingerprint。

包内 NeuronModuleApplicationLaunch 任务桥接到 Swift 入口 0x1049774a0；其初始化段
（0x1049779e0–0x104978458）创建 InfoApp，并逐项赋值：appId 从注入的 ProductID
字符串转十进制整数，platform 按 UIDevice.bfc_isIPad 取 2/1，buvid 与 deviceId
分别调用 BFCBuvid.buvid，model/osver 取 UIDevice 的 bfc_platformString/
bfc_systemVersion，fts 取 BFCNeuron.shared.firstTrackTime，sessionId 取注入设备
服务的 sessionId。因此这里的 deviceId 是跟踪编号，不是 serverBUVID；fts 也不能
直接替换为设备服务的 firstRunTime。ProductID 的转换异常分支还需继续核对。
Neuron.init（0x1161e94d8）从
BFCNeuronPreferences.shared.fts 读取有符号整数；值大于 0 时复用，否则使用
gettimeofday 的秒×1000 加微秒整数除以 1000，并 setFts 保存。Preferences 使用
configName=BFCNeuronPreferencesName 的 UserDefaults suite，动态属性 fts 为整数。
因此它记录该存储域中的首次 Neuron 初始化时间，单位毫秒；重置存储后的语义、
异常系统时间和套件迁移属运行期/跨版本项，静态不可定（下一步 `disassemble 0x1161e94d8 0x1161e9600` 复核该 suite 读取点）。

随后创建 RuntimeInfo，version/versionCode 分别读取 mainBundle 的
CFBundleShortVersionString/CFBundleVersion，字符串转换失败用空字符串；logver
读取注入服务的 version。任务设置 shared Neuron 的 AppInfo、RuntimeInfo、delegate，
再调用 runWithConfiguration。这证明了模块任务内部的初始化链（0x1161e9848）；全局注册器在每种启动场景是否都会执行它属运行期调度，静态不可定，下一步 `disassemble 0x120273d20 0x120274400` 核对任务清单派发（entry123 @0x120274300）；后续会话变更的同步更新属运行期账号事件、静态不可定，下一步 `find_callers.py 0x114551324`。
注册发现边已补：184-provider静态表entry123（0x120274300）是
BFCNeuronModule._$GripperRunnableTaskProviderNeuronModule，conformance witness
0x11b2f03f8的getter0x104976fb0返回唯一任务；task witness0x11b2f03c8的execution
0x104976f5c转0x1049774a0，trigger为applicationLaunch，thread为main、priority raw750。
因此首轮generated dispatcher具备发现并按该trigger调度任务的具体边，不是仅凭任务名。
实际每种启动是否发该trigger仍是独立门禁。InfoApp.sessionId getter0x11455131c
是ivar+0x40，setter0x114551324做nonatomic copy；初始化0x104977e34保存注入值快照，
异步Neuron事件读取该ivar。当前有界selector扫描未找到另一Neuron写者，但直接ivar
写入与外部账号/设备通知尚未全局穷举。初始化 0x104977e34 是已证写点；
有界 selector 扫描未找到另一针对 `BFCNeuronInfoApp` 的写者，不证明该任务只执行一次，
也不覆盖任意直接 STR、间接调用或整个 AppInfo 替换。共享 stub 0x117623200 有 34 处
直接调用、j_ stub 0x10f880db0 有 18 处，不能合计成原 team-c40 所述的 18。
0x1161ea470 的 setSessionId 接收者是新建 `BFCNeuron_AppInfo` protobuf，取源于共享
appInfo，不是改写上述运行期对象。DeviceServiceImp.sessionId 0x1049573a4 →
BFCDevice.getSessionId 0x115fd3960 有 once/lazy 静态缓存 0x120e623a8，初始化
0x115fd39c8 写入；已读普通访问路径不会每次登录重算，但隐藏写入/替换、任务复入
及 9.13 生命周期仍未证。证据 `DerivedData/Validation/independent-dsh-review/c40.md`；
撤回 team-c40 的“一生只写一次/不存在账号改写路径”全局推论。
另一个startup session有独立来源：StartTraceServiceImp.startSessionId0x105037bbc
调用AppStateManager.getStartToken0x105038814。constructor0x105037d98把
UUID.uuidString经Swift String.hashValue取低32位、零扩展，以%lx格式保存RAM token；
不是UUID文本或稳定hash，检查到的构造/生成/读取方法没有落盘writer。
它注册willEnterForeground通知；Monitor.premainStart调用mainStart时，只有环境
ActivePrewarm恰为"1"才通过自身并发queue的async barrier置isPrewarm。
前台回调0x1050387ec经barrier进入0x10503869c，要求isPrewarm==1且refreshed=false
才重新生成并置refreshed=true；普通前台不更新，已标预热的路径只更新一次。
`setStartToken:` 0x105037d5c 的直接调用/专用 stub 未命中，不排除动态 setter。
读取与更新链必须分开：getStartToken 0x105038814 → queue.sync 0x10503885c →
closure 0x1050389ac → 0x1050388ec → 0x105038960 在 0x105038978 仅读 token。
生成/更新另由前台通知和预热门禁进入 0x10503869c，不能将读取称重新生成。
原“ivar全枚举/静态无外部setter/账号重置只能重入”推论收窄为已读路径局部证据；
见 root-static-audit/recovery/review.md 及独立 asm。
Neuron Runtime.startSessionId0x114551618转取注入service；enable_public_parameters
分支在异步事件block执行时读取0x1161ea9c8，nil转空后写Message.extra.start_session_id。
这是读取时点不同的另一字段，不能与初始化copy的PBAppInfo.sessionId合并。
StartTrace类型与provider已对上：Neuron初始化0x104977f1c解析
BFCStartTraceService协议的注入对象，0x104977f8c传Runtime；注册factory
0x105037ae0以同协议注册_$GripperProvideStartSessionIDDependencyProvider。
其lazy getter0x10503798c创建StartTraceServiceImp并缓存provider实例+0x10。
全局component静态可达性也已闭合：AppDelegate先调用GripperWrapper.startup
0x100026938，构建独立service component表（14类true、334类false），不是前述
184 RunnableTask表。false表0x120272628的entry26是AppStateModule，entry214是
NeuronModule；解析0x1051319dc逐项NSClassFromString并检查GripperModule conformance，
缺类/不符合则跳过。AppState witness0x11b344370的+8是注册factory0x105037ae0。
root lazy initializer0x1051315b4调用constructor0x1051313a0，选raw0表并于
0x105131538逐项执行注册witness+8；Neuron start依赖读取0x104977f30→0x105134e98，
空cache会初始化该root并resolve，成功Optional再缓存，后续命中直接返回。
这贯通了component表→协议witness→root构造→StartTrace provider→Neuron consumer，
仍为静态证据，实际启动lookup/OS通知成功未执行验证。
这里不输出或生成实际UUID/hash/设备值。
InfoAppRuntime.network（0x11455144c）对 reachability 原始值 1→1、2→2、其他→3，
枚举的业务含义尚需核对。oid（0x114551478）取蜂窝运营商 MCC/MNC 拼接，有空值兜底；
多卡路径取 providers.allValues.firstObject，不能声称总是特定 SIM。abtest 在该 getter
返回空字符串；ffVersion/configVersion/DDVersion/startSessionId 则向注入服务转取。
这些字段来源与传统 HTTP statistics、Session_ID 需要分别核对，不能假设完全相同。

checkReportInstantlyByEventId（0x114551d94）读取 neuron.high_priority_list 数组，返回
是否包含该 eventId；缺数组返回假。即时报告仍会经过上述 report 的发送许可判断，
“高优先级”不等于绕过无网络条件。
