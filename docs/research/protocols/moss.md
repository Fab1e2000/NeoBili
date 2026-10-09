# Moss 服务选择、原生 metadata 与流重连

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## Moss 服务选择、原生 metadata 与流重连

Wrapper注入初始化0x100151830构造MossServiceRealImpl，witness0x11b0b47a8
写入global0x121073840；模块setup入口0x100150ef4。后述ticket注册章节已闭合
RunnableTaskProvider库存index115、moduleInitialize/main/priority1000及launch桥接。
服务构造0x100151260检查KntrKMossFeature.enableMossIgnet：false选原生
BFCMossService；true再查package+'.'+service是否在列表，命中仍原生，否则
KMossServiceImpl。列表getter0x10015101c从配置moss.ignet_downgrade_services读String，
逗号split，nil为空数组，lazy缓存self+70；开关每次建service读，列表不会每次重读。
不能把原生规则推广至所有Moss。
Wrapper RPC witness+8（0x100151a60）设responseClass、取GPB.data，nil不发，
非nil向所选service发autoRPCToMethod:rawData:responseHandler:。

KMoss构造0x100154dcc将传入GRPC timeout有限/范围检查后向零截Int64，直接作
KntrMossComponentWrapper.timeoutInMs；该处未乘1000。Kotlin service.init
0x10be4240c存component和lazy engine；0x105ce6204首次经Foundation查MossEngineService，
0x105ce617c复用lazy结果，缺服务抛错。RPC0x10be425d4构造KMossServiceComponent/
KCallOptions和KMethodDescriptor（不是两个String），NSData转ByteArray，再调engine。

Root注册0x10b92f040将MossEngineService接supplier+3a0/id118；factory0x105cdf880的
wrapper vtable+a8=0x105ce01cc，Foundation调用0x105346bf8接到cached producer。
MossEntryPointProducer构造0x105ce02e0缓存enableMossIgnet：true只选moss-ignet标签，
false按moss-platform、moss-ignet顺序查IPlatformMoss；首个非nil返回，全缺时再无标签
查找，仍nil则抛错（0x105ce0884）。该缓存选择与Swift每次建service读开关不同。
已定位GrpcEngine/平台桥两个实现，实际注册服务与外层启动时序仍限制覆盖结论。

平台桥0x10aaa25bc在extra REST描述非nil时build(rest:true)，否则false；分别调用
asyncUnaryRestCall/asyncUnaryGrpcCall。桥0x10aaa4318将boxed timeout写原生
BFCMossCallOptions.timeoutInMs，setter0x1050a4b84纯存。builder0x1001508d4从
vtable+58（metadata0x11ff49338+58→getter0x1050a4b44）读该整数，signed除1000
向零截断后转Double，写GRPC timeout；两分支直接建BFCMossService，不重新选KMoss。
合成算术20→0、20000→20只证明转换。与入口不乘1000合看存在单位不一致可能，
未运行包，不能声称实际发生超时或所有KMoss走这个平台桥。

GrpcEngine候选实现的CommonHeaderInterceptor0x10aa42178（moss-common-headers）
另按ASCII producers、binary producers两轮逐次取值，nil跳过；写GrpcMutableRequest的
两个独立map，再chain.proceed（0x10aa42628）。factory0x10aa2c178缓存的是producer
对象列表，不是所有字段值；binary setter0x10aa2eddc未作Base64。
AccessKey producer0x10aa22478每次读account接口，nil省略，非nil拼identify_v1空格前缀
写authorization，未见空String检查；accessKey producer 0x10aa22478 的具体 account 实现与引擎注册范围属间接派发、静态不可定；下一步 = disassemble.py 0x10aa42178 0x10aa42664（类名由 0x10aa42570/0x10aa425a8 的 binary loop 定位；索引里没有 `CommonHeaderInterceptor` 这个符号名，别用该 GLOB 找），并对 provider 装载点跑 scan_callers_set.py 0x10aa22478。
CommonHeader另有flattened helper0x10aa41b88将binary Base64到普通map，与typed
Grpc map不同；需继续transport消费证明，不能把二者当同一header转换路径。

原生callOptions helper0x115e070e4→0x115e06c20复制缓存Metadata，每次此helper
调用重新读BFCMossConst.accessToken（nil空），调用fresh Device/Network builder，
把三个GPB.data放入x-bili-metadata-bin/device-bin/network-bin。restriction/fawkes
可选；extraHeader先合入，随后非空device.buvid覆盖buvid，非空accessKey写
`authorization: identify_v1 <accessKey>`，非空trace覆盖x-bili-trace-id。
基础options once0x115e07054：timeout/keepaliveInterval/keepaliveTimeout均20，
transportType/compressionAlgorithm原始enum均2，未推枚举名。**压缩（本轮补）**：逐指令看该 once——
`alloc/init GRPCMutableCallOptions`(0x115e07064) 存全局0x120dd1328，三个时间值均`fmov d0,#20.0`
写 0x115e07084/0x115e07090/0x115e0709c，`setTransportType:`(0x115e070a8，`mov w2,#0x2`)、
`setCompressionAlgorithm:`(0x115e070b4，`mov w2,#0x2`)，随后调 metadata 缓存初始化
`sub_115E0D0D4` 并存入 0x120dd1338；setter `-[GRPCMutableCallOptions setCompressionAlgorithm:]`
（0x1164ad19c 区）只是把该 raw 值写对象 +0x58 的小桩，**镜像内没有枚举名常量**，不能把 2 直接写成
“gzip 常量”。**有效编码由 9.13 抓包闭合**：全部 1,248 个 gRPC 请求带 `grpc-encoding: gzip`
（`DerivedData/Validation/team-c12/engine-headers.jsonl`），Neuron 日志请求带
`content-encoding: gzip` ⇒ 客户端实际协商/发送的压缩是 gzip；raw enum 2 的枚举名仍属
GRPCMutableCallOptions 语义，静态不可判（取证=运行期读该 setter 入参或对照 gRPC 头文件）。
**枚举名穷举结果（本轮）**：镜像内既无 `GRPCCompressionAlgorithm` 之类的符号，也无
`gzip`/`deflate` 的 ASCII/UTF-16 字面量（`query_index '*Compression*'` 只返回 KSCrash、
`BFCLogDataCompression`、WebRTC、UIKit 等无关项）⇒ 只能写 **“raw enum 2、无符号名”**；
`setTransportType:` 同为 2（0x115e070a8/0x115e070b4 两条 `mov w2,#0x2`），setter 家族
（`-[GRPCMutableCallOptions setCompressionAlgorithm:]` 等）都在 0x1164acd28–0x1164ad140 这一段。
Metadata缓存initializer0x115e0d0d4取build/buvid/channel/mobiApp，platform=ios，
idiom1→pad否则phone；不要把其缓存字段与fresh Device/Network混同。
原生Service.init0x115e08040保存传入options，defaultAutoRPC0x115e0862c仅copy
该存储，因此“helper每次更新token”不能改写成“每次RPC都重读token”。

原生autoRPC先遍历middleware，首个canInit为true即接管。默认路径若fallbackList
含fullMethod直接走HTTP backup；否则先canonicalGatewayRequest，已有响应则直接
回调initial=nil/close，未命中再将gateway extraHTTPHeader合入metadata，启动unary。
此later merge具体在0x115e08ff0默认gateway路径：0x115e09110以addEntries将
gateway extraHTTPHeader后合入options.initialMetadata，0x115e09124保存后才创建/start
unary RPC。因此前述helper内的buvid/account/trace覆盖只是局部优先级；gateway
same-exact-key仍可覆盖它，不能称helper输出全局最终metadata。GRPCCall2库的
reserved header 与大小写归一化位于 gRPC core prebuilt（本镜像只含调用面，query_index.py '*GRPC*'），静态不可穷尽，不推广至 StandaloneGrpcEngine 或 KMoss；下一步 = find_string_refs.py 对 '-bin' 与 'grpc-' 字面量收齐消费点，并用 9.13 抓包核对重复头合并。
RPCCall.start0x115e15550执行GRPCCall2.start→receiveNextMessages(1)→writeData→finish。
raw响应handler0x115e09d74回传并设terminal标志；close0x115e09fc8对流控或特定
business metadata（bili-status-code/grpc-status-details-bin及配置门控）也设terminal。
无错误却无raw可合成code29；追踪后仅terminal=false走一次backUpRPC。
这证明降级分支，不证明unary递归指数重试。
native初始回执0x115e09bcc将metadata合入共享byref字典，close0x115e09fc8再把
trailing metadata后合入（0x115e0a5a4），随后canonicalGatewayResponse
（0x115e0a5e4）；相同精确键由trailing覆盖initial，**已闭合（task-38）**：0x115e0a600 处 canonical responseHeader 以 mutableCopy **整体替换**共享 metadata（str @0x115e0a620）；本函数内**无大小写归一化**（objectForKeyedSubscript: 用精确键 @0x115e0a33c/0x115e0a400，全函数无 lowercaseString）；wire 层归一化属 gRPC core/prebuilt，需抓包核对。
【9.13 抓包观测（线级，team-c12；build 91300100；证据 DerivedData/Validation/team-c12/
metadata-bin.jsonl、header-names.jsonl、auth-planes.jsonl）】wire 上 gRPC 请求（`grpc.biliapi.net`，
HTTP/2，1,248 条）的 `:path` 形如 `/bilibili.app.playurl.v1.PlayURL/PlayConf`、`/bilibili.app.playerunite.v1.Player/PlayViewUnite`、
`/bilibili.app.viewunite.v1.View/View` 等；**每个请求上的自定义头都只有一个值，不存在同名头并存**
（全语料重复头只有 webview 的 `cookie`）；头名大小写由 transport 决定：HTTP/2 一律小写
（`session_id`/`buvid`/`guestid`/`app-key`/`env`），HTTP/1.1 出现混合大小写
（`Session_ID`/`Buvid`/`GuestId`/`APP-KEY`/`ENV`，80 条，78 条为 `/x/vip/ads/material/report`），
故"同一 key 的大小写变体"在现版 wire 上**不会与另一变体同时出现**。身份材料按通道分流：
`authorization` 只随 Moss/gRPC（1,248 条）出现且这些请求无 query `access_key`，HTTP 侧反之。
`x-bili-metadata-bin` 在全部 gRPC 请求上存在，base64 解码后为 7 字段 protobuf
（field 1 220B、field 2 6/8B ASCII、field 3 5B、**field 4 varint = App build**、field 5 13B、
field 6 36B、field 7 3B），**形状在所有方法上一致**（缺 field 1 时解码总长 80B），
即它不是方法级 metadata；同族头的形状见 `metadata-bin-deep.jsonl`
（`x-bili-device-bin` 16 字段、`x-bili-network-bin` f1/f5 内嵌 f2=9900 与 epoch 毫秒、
`x-bili-locale-bin` 两段嵌套 {1:2B,2:4B,3:2B}+f4/f5/f8、`x-bili-restriction-bin` f7=16）。
重复头合并与 reserved header 的大小写归一化属 gRPC core，本次样本只能证明"发出去的是什么"。
普通terminal及流控分支的downstream didClose调用（0x115e0a57c/0x115e0a2fc）
在此gateway处理之前，不能将同步调用顺序等同业务异步completion完成顺序。
Ticket所用MossServiceRealImpl wrapper0x100151a60创建的是plain
BFCMossResponseHandler（initWithUnaryHandler0x100151b38），不是另一raw API的
ResponseHandlerAdapter。plain handler的dispatchQueue0x115e079a4返回main；
raw解析成功/失败及close均转_callMessage:error:0x115e07e8c，该helper总是
dispatch_async到该队列（0x115e07f28），没有“已在main则立即调用”的分支。
queued block0x115e07f68读当前unary block，nil则丢弃；message/error同时nil则造
code29。业务callback0x115e07fd8返回后才清block（0x115e07fe4），后续main队列
block通常不再交付；嵌套/重入执行的全部情况未证。
随后ticket wrapper才经0x1000987d0再次async共享serial ticketqueue，计数及缓存
保存发生在该队列。因此native close先于gateway只证明入队前沿，不能证明ticket
保存先于gateway；较早的parsed raw也可能已经排队成为winning result。下述backup
gateway先于close同样不能排除此前raw结果的排队/保存。
backup initial callback0x115e0937c仅log；其close0x115e09764先把收到的close
metadata交gateway0x115e09aa4，再通知downstream0x115e09b6c，不套用native的
initial+trailing合并和先后。因此ticket response可能读取的metadata来源需按引擎区分。

backup0x115e0ac7c为POST application/grpc，合入metadata及gateway extra；所有-bin
header经0x115e0b330→0x115e0b380转Base64。body为1字节压缩标记+BE32长度+data；
仅raw.length>200且http1Gzip时gzip。gzip失败code27直接close，不在本分支退raw重发。

广播通用stream另有重连状态机。_initTunnel0x1149ec700取上述options并timeout=0，
host/port构造tunnel。_maybeConnect0x1149ecd44在connecting/valid/closing任一true时
返回；_connect无call才create/start，再创建connId UUID、取tracker.SessionID以及
shared lastMessageID（缺省0），构造Broadcast/Auth frame。builder0x1149ef33c只写
AuthReq.guid/connId/lastMsgId→Any→frame，token在原生metadata，未见独立frame签名。
Auth回执0x1149ed520 status.code非0取消call；0才设置reachable/valid，通知started，
retrying时再通知restarted，清connecting并reset backoff和heartbeat。
InitialMetadata0x1149ed790仅日志，不代表认证成功。

meta.shared来源已追到中心构造：sharedCenter的once initializer0x1149ea204→
0x1149ea25c以shared=1、hp=0、tag="shared"、host=broadcast.chat.bilibili.com、
port=7824调用initWithShared:hp:tag:host:port:0x1149ea284；该constructor创建
BFCMossStreamMetadata并把入参写shared/hp/tag/host/port（0x1149ea34c–0x1149ea37c），
singleton存在RAM0x120da5308。setup0x1149ea3fc以实例flag防重复，创建stream并
start，把相同meta传给channel。这是中心种类标记。另一concrete producer
MossStreamServiceBuilderImpl.buildWithHp:tag:host:port:0x100155684→0x100155724
以generic objc_msgSend调用同initWithShared，shared固定0、hp/tag/host来自caller、
Int32 port转NSNumber；每次创建新center，未见缓存。getShared0x100155770则取
sharedCenter。因此custom center走meta.shared=false的采样/Atomic门禁；具体业务
custom center 的业务 caller 属间接 selector 调用、静态不可定（当前 direct selector stub 只有 singleton caller）；下一步 = scan_callers_set.py 0x100155684 0x100155770 并 disassemble.py 0x100155684 0x100155770 回溯 buildWithHp:tag:host:port: 调用方（0x100155770 起是下一符号 +getShared，不要越过）。
Kotlin桥的concrete type也已定位：TypeInfo0x11bb3e740的package/name分别为
kntr.base.moss.epoch.impl/platformMossStreamBuilder$1，function table
0x11c3499e8含build0x10aaa7f44、getShared0x10aaa8324。build经native selector
load0x10aaa8148→generic调用0x10aaa8160转发四项入参；platform initializer
0x10aaa6ddc分配该type，存RAM builder global0x120c6cb68。该桥证据仍不等于
某个业务consumer已使用custom center，业务调用尚待闭合。
公共KMossStream shared的实际DI binding已另闭合：Companion initializer
0x105c45164读lateinit provider global0x120c5d980，经hash0xa01调用provider，
再经IPlatformMossStreamBuilder hash0x11880/slot+8 getShared
（0x105c45334/0x105c4538c），保存wrapped platform stream。initKMoss
0x105cdfcf4创建initKMoss$2 TypeInfo0x11b4e1990，捕获MossEntryPoint于+8，
0x105cdff10写上述global；invoke0x105ce1490经hash0x11d80/slot+8进入
MossEntryPointProducer0x105ce0c58，按KClass key0x11c6394a0
（IPlatformMossStreamBuilder）查Gripper scoped producer。
SingletonC registration0x10b92db54将component+0x538绑定该key
（0x10b92dbd0/0x10b92dbd4）；field initializer0x10b935984包裹
SwitchingProvider TypeInfo0x11bd1aea0、raw id166。invoke0x10b945250按百位
进入group1 0x10b93d954，jumptable0x118652f3a[index66] raw0xde分支
0x10b93ddbc→0x10aa9e6a0，singleton raw producer0x11cb3d010的getter
0x10aa9f840返回epoch builder global0x120c6cb68。因此这个root binding确实
选择上述epoch native builder，不是另有的ignet factory。scoped lookup穷尽后的
generic container lookup不是AB引擎切换；bootstrap实际执行、scope顺序和custom
build 的业务 consumer 经 Kotlin 桥间接调用（0x10aaa7f44 build / 0x10aaa8324 getShared），静态不可定；下一步 = disassemble.py 0x10aaa7f44 0x10aaa8400 并对该桥跑 scan_callers_set.py 0x10aaa7f44。
公共wrapper TypeInfo0x11b4cdb40的function table+0x30为空，仅持有platform+8；
可见register0x105c45420/unregister0x105c454dc分别经hash0x11800/slot0及slot3。
针对该hash的同寄存器MOVZ/MOVK构造扫描仅四site，都在这两个方法，未见slot1/
slot2 setup/teardown消费者；epoch桥0x10aaa7320/0x10aaa74e8的direct BL/B扫描
也未见caller。此有界编译形式扫描不排除其他间接/ObjC/reflection调用，不是运行时
从不setup/teardown的证明；明确启动证据仍是下述native任务。
名称也不能代替行为：BFCMossCenter.connectActive0x1149eb7c0只读取shared
Reachability.isReachable（0x1149eb7e4），不发起连接或表示前台激活。
channel.start0x1149ec844分别在自身queue排_maybeConnect（0x1149ec8f4）、
global queue排Reporter.START raw0（0x1149ec8fc）；没有两队列之间的等待关系，
不能保证START计时复位早于实际连接。finish0x1149ec9a0也分别排_disconnect与
Reporter.FINISH raw2，同时在caller栈remove通知observer、dispose并清空网络
disposable、remove账号observer（0x1149eca54–0x1149eca80）。异步_disconnect
0x1149ecab8才置isClosing=true并call.finish，未调用cancel。start自身不清closing
或重新登记这些监听；同一finished channel再start受_maybeConnect门禁，实际业务
同一 finished channel 再 start 受 _maybeConnect 0x1149ecd44 门禁，是否另处 reset 属运行期分支、静态不可定；下一步 = scan_callers_set.py 0x1149ec844（channel.start）与 0x1149ea4c8（teardown）收齐调用方。
已确认center自身的重建路径并非重用finished channel：teardown0x1149ea4c8
stream.stop0x1149ea544→channel.finish，随后center.stream=nil、setupflag=false。
下次setup创建新Stream0x1149ea4a0→新Channel0x1149eb958，重建backoff与监听。
center原metadata/frameBuilder/reporter仍保留。Reporter.initWithMetadata
0x1149efcc4不创建UUID；实际Channel._connect0x1149ecaf8每次生成UUIDString并
依次写connId/Reporter.sessionID，再写Auth frame同connId
（0x1149ecb7c–0x1149ecc0c）。若call不存在，call.start0x1149ecb68先于UUID
写入；独立global START与连接没有队列依赖，故不能保证START观察到新的session。
调度验证属运行期（本样本不含执行证据），不能把 center 复用直接等同 session 保持不变；下一步 = 9.13 抓包比对 Auth frame 的 connId 与 Reporter.START 时序，静态侧对照 0x1149ec844/0x1149ec8f4/0x1149ec8fc 两队列入队点。
独立MossStreaming启动任务也已定位：service array的index200/slot0x1202732c8、
runnable array的index115/slot0x1202742a0登记MossStreamingModule。entry
0x100155c2c→0x100155cd0，moduleInitialize、main、priority450；任务检查
moss_stream_enable（presetHitValue=1，0x100155d8c），命中才sharedCenter.setup
（0x100155db4/0x100155dcc），未命中仍继续metadata缓存。此任务与NativeMoss
gateway module分开。已检查的原生Center/Stream/Channel已命名方法和构造/启停
body未见application前后台通知addObserver；finish的removeObserver不能证明曾登记。
Kotlin epoch PlatformMossStream（TypeInfo0x11bb3e600）另有setup/teardown桥
0x10aaa7320→0x10aaa7408、0x10aaa74e8→0x10aaa75d0，但只有函数表间接引用，
该桥的业务调用与前后台 listener 属间接派发、静态不可定，不把桥存在写成自动前后台断连；下一步 = scan_callers_set.py 0x10aaa7320 0x10aaa74e8 收齐调用方，并 find_callers.py 0x105cdf880 核对 engine 装载。
channel constructor0x1149ec350先排初次_initTunnel，再保存handler、订阅网络、
订阅账号（0x1149ec644/0x1149ec650/0x1149ec658/0x1149ec660）；只是调度顺序，
不能当实际队列执行先后。observerAccount0x1149ece9c向BFCAccountNotification
登记type raw3；callback的action raw1仅决定登录日志Bool，两个action分支均排
channel queue，报告AUTH_CHANGED、isRetrying=true、cancel当前call、重建tunnel
service（0x1149ecfec–0x1149ed0c8）。Notification.postAction0x11605d05c用
(observer.type & action)!=0匹配（0x11605d16c），再main.async交原action/current
SSO；type3是mask1|2。logout completion0x11604c3b8在清cookie、SSO/user置nil
后notify raw2（0x11604c468）；SSO handle completion的notify raw1有captured flag
false且local result<1门禁（0x1160502c8/0x11605054c）。因此已闭合登录1/退出2
均触发该channel处理，但不保证每次SSO更新都发登录通知。重建service未直接_connect，
也不重新构造backoff/
heartbeat配置；取消触发的close仍进入下述延迟路径。
syncReachability0x1149ed0cc使用statusSignal.skip1.distinctUntilChanged，takeUntil
channel dealloc，保存scopedDisposable；回调同样排channel queue。raw status0仅
日志“Network unreachable”，此body未cancel/重连；非零报告NETWORK_CHANGED，
backoff.reset后_retryConnect:0（0x1149ed2f8–0x1149ed3c0）。_retryConnect:
0x1149ecd9c只报告RETRY及delay十进制String、置isRetrying=true、_maybeConnect；
该helper自身不等待delay。故非零网络变更也可能被connecting/valid/closing门禁
挡住，不证明每次重建连接。close按nextAttemptTime后addAttempt、先安排重试再
channelDidClosed；延迟closure0x1149ee000强捕获channel，无自有generation检查，
之后_maybeConnect仍检查上述状态。旧/新 call 回调的身份隔离属运行期时序（延迟 closure 0x1149ee000 无 generation 检查），静态不可定；下一步 = disassemble.py 0x1149ee000 0x1149ee0a0 并从 0x1149edc68（close）回溯 call 捕获点。
**流生命周期各入口的调用方枚举（本轮复核，含方法学纪律）**：把本节点名的“下一步 = find_callers/
scan_callers_set 收齐调用方”逐个复跑，结果**全部 0 命中**——`channel.start` 0x1149ec844、
`center.teardown` 0x1149ea4c8、Kotlin epoch PlatformMossStream setup/teardown 桥
0x10aaa7320 / 0x10aaa74e8、`buildWithHp:tag:host:port:` 0x100155684、`+getShared` 0x100155770、
Kotlin build 桥 0x10aaa7f44 均为 0。原因是这些入口经 **ObjC msgSend 或 Kotlin vtable/函数表**
派发，而 `find_callers.py` 只匹配 BL/B 精确目标 ⇒ **“0 命中”不能读作“无调用”**（selref 零引用 ≠
无调用）。正确取证：ObjC 形态先取 `_objc_msgSend$<selector>` stub 或 `selRef_*` 槽再扫装载点
（例：`_objc_msgSend$setOnlineParams:` 不存在，`setOnlineParams:` 的 selref 0x11f783e30 装载点为
0x10008c06c，即用此法则定位）；Kotlin 虚调用需解析 vtable/witness 槽（当前工具链缺 vtable 解析器，
属方法学缺口）。仍需运行期取证、本轮不闭合的项：两台列（自身 queue 的 `_maybeConnect`
0x1149ec8f4 与 global queue 的 Reporter.START 0x1149ec8fc）谁先执行；同一 finished channel 再 start
是否另处 reset；延迟 closure 0x1149ee000 的旧/新 call 身份隔离。取证=真机/模拟器日志，或 9.13 抓包
比对 Auth frame 的 connId 与 Reporter.START 时序。

close0x1149edc68先通知error、停心跳、清reachable/call/valid/connecting；closing或
backoff.exceeded时停止，否则nextAttemptTime→addAttempt→channel queue延迟retry。
正常/hp配置getter0x1149eeb24/0x1149eecb4 once缓存远程值，fallback分别为
limit10/initial5/max60/factor1.5/jitter0.2/heartbeatLimit3/interval60/retryInterval20。
Config ctor的max50不是正式getter fallback60，不能把远端可覆盖值视为恒定。
integer/float Wrapper0x104e2e000/0x104e2e0fc解析BFCMemexConfigService缓存
0x120279480，getInteger/getFloatForKey:defaultValue后直接返回；这两个wrapper
未加范围校验。各参数最终合法性不能单凭getter名称推断。

backoff0x1149ee3e0在attempt>0时更新base为
truncFloat32(min(max(oldBase,initial)*factor,max))，加inclusive整数均匀偏移
[trunc(-jitter*base),trunc(+jitter*base)]。attempt0主线程取applicationState，最多等1秒，
初值1；state==1（含超时仍保留1）延迟0，否则initial加同样jitter。
reset0x1149ee3d8只清attempt，未清base；exceeded比较attempt>=limit，成功auth reset。
这是stream传输重连；room业务重入还受观察者/room状态控制，不能归为所有RPC重试。
stream Reporter.trackWithEvent:error:params:0x1149efd44另映射raw事件
0START/1STOP/2FINISH/3NETWORK_CHANGED/4AUTH_CHANGED/5RETRY/6RESTART/
7HEARTBEAT_LOST/8UNHEALTHY，其余空String；0/5/6先重设_startTime。
报告字典先合metadatas，再写六个String字段session/time/event/code/sample_rate/
message：time=bfc_getTickHR减_startTime的十进制毫秒，code为
NSError.code（nil→0），message为localizedDescription或空；sample_rate经单精度
rate/10000转Double再用"%.4f"格式化。最后caller params可覆盖所有前字段
（0x1149f001c），不能把六字段或metadatas看作不可覆盖。
hit=(signed rate > arc4random()%10000)（0x1149f0028–0x1149f0048），miss也构造
字典再转Const.trackWithParams:hitReport（0x1149f0054）；前述Wrapper的false门禁
才抑制fanout/Mikoto报告。clock0x1167a47f4正常用mach_absolute_time×timebase换
纳秒再向下取整除1000000；timebase初始化失败才取gettimeofday的墙钟毫秒。
9个合成数值边界验证除法等价，没有执行官方样本或读取实际timebase。
Reporter的rate getter0x1149f1218/0x1149f12a0按meta.shared选择stream或liveStream
event/biz rate；非空event/path再查rule，非负rule覆盖rate。规则统一来自eventRule，
JSON必须NSArray，依序用event或path pattern对输入rangeOfString:options:raw1024；
首匹配取sample.integerValue并stop（缺sample→0），无匹配保留-1默认门禁。
没有在该body看到clamp，不能按API字段名推断它是正则或百分比范围。
Const每个rate/rule getter独立检查ff_net_monitor_wl（preset0）；命中rate=10000、
rule=nil，禁止rule覆盖。非live另支持default/event/biz/rule四个可选override block
（0x120da5340/0x120da5348/0x120da5350/0x120da5358），live没有该组block分支。
普通Wrapper通过BFCMemexConfigService读grpc.broadcast_{def,event,biz,event_rule}_
report_rate2及grpc.broadcast_live_{def,event,biz,event_rule}_report_rate八键，缺值先
转空String再桥nonnull NSString。因此普通缺event/biz配置会得到integerValue=0，
不会走Const仅针对nil结果的defaultRate回退；非live override block返回nil则能回退。
具体配置值、白名单命中、meta全字段及外部override安装未知，未把getter默认转换
当成运行时必然0采样。

stream guid getter0x1149ec2e8缓存独立UUID（global0x120da5318），不是设备编号；
每次_connect的connId另建UUID。defaultOption0x1149efba0用截断Unix秒×1000，
sequence0x1149ef300加锁先返回旧值再递增。收到frame0x1149ed898先将正messageId
保存lastMessageID，再按targetPath分派；Heartbeat回包直接reset心跳。
options.isAck为true时自动构造ACK：复制原messageId/ackOrigin/targetPath/msgType，
bizPath为原targetPath，重建defaultOption，再write（0x1149edb54）。本地写不证明服务收到。
Heartbeat.reset0x1149eef6c清heartbeatTime并启main common modes每秒timer；
sync0x1149ef08c用unsigned时间差、retryInterval和起始时间判断重发/超时，
不是简单递减三次计数。timeout0x1149ed4dc取消call，close回调才负责重连。
