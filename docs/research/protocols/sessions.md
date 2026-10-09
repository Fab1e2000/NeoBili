# 会话来源与旧活动上报

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 会话来源与旧活动上报

公共请求的 BFCBuildConfig.sessionID（0x1161e56b0）在无旧静态值时转向
BFCBuildConfigWrapper.sessionID（0x10506a5d4），后者调用注入服务的 sessionId。
DeviceServiceImp.sessionId（0x1049573a4）→BFCDevice.getSessionId（0x115fd3960）
→KntrSessionIdProvider.shared.sessionId。BFCDevice.getSessionId 本身有 dispatch_once
与静态强引用缓存；初始化 block 0x115fd3990 只读取一次 Kotlin provider，后续请求
复用该值，不能描述成每次请求动态刷新。**登录切换的静态边界（team-c21）**：
`query_index '*SessionId*'` 未见 sessionId 的 setter/reset 方法，也未见对该静态槽的写点，
⇒ 样本内不存在登录/登出驱动的 sessionId 重新生成路径；阳性对照：同层 `getXTraceId`
0x115fd39e4 无 once/cache、每次重算（13 次 arc4random + 时间格式化 0x115fd3a68/0x115fd3a90/
0x115fd3af8），说明“可重算 getter”形态在该层确实存在而 sessionId 不属于它。换号后请求头是否
携带旧 session 属运行期（需真机换号抓包）。

KntrSessionIdProvider 的 Objective-C classData 没有普通方法列表，但 Kotlin 导出表
0x11ccf8660 附近给出了 shared（桥接 0x10be2c54c）和 sessionId（0x10be2c6dc）。
前者关联初始化函数 0x10539d3c8，创建 SynchronizedLazyImpl；后者经 0x10539d514
读取 lazy value。initializer 对象 0x11c53e648 的类型接口表 0x11bd56918 指向
0x10539d59c：向随机服务申请 16 字节，逐字节执行 64 位 FNV-1a，初值
0xcbf29ce484222325、乘数 0x100000001b3，取结果低 32 位，按 radix=16 转字符串。
此整数在传入 0x105213310 时零扩展，转换器 0x10bfce70c 使用小写十六进制且不补零。
随机服务是 Kotlin Random.Default，委托 NativeRandom。初始化 0x10522aa74 使用
steady_clock.now 返回值的低 48 位 xor 0x5deece66d 作为状态；nextBits
（0x10522ac4c）按 `(state×0x5deece66d+11) & 0xffffffffffff` 更新，再右移
`48-bitCount`。该时钟是 Kotlin/Native steady_clock（初始化 0x10522aa74 取 now 低 48 位），其系统 tick 单位与并发状态行为在 Kotlin runtime prebuilt 内、静态不可定；下一步 = query_index.py '*steady_clock*' 并 9.13 抓包比对 session id 变化，不能当作 Unix 时间
或安全随机源。nextBytes 的实际填充器 0x105290994 按 4 字节组调用 nextInt，按低字节
在前写入数组；16 字节消耗四个 32 位输出，随后仍调用 nextBits(0)，推进一次状态而
不写入尾字节。因此重现同一随机序列时也需计入这第五次状态更新。没有看到此链
持久化会话或随前后台刷新。
邻接的字符串、getXTraceId 的 `...:0:0` 格式均不能当作该 sessionId 的生成规则。
getXTraceId0x115fd39e4的实际生成与Session_ID独立：方法没有once/cache，每次13次
arc4random取low8，以%02x追加26个lowercase hex字符；NSDate Unix秒经FCVTZS w8
截断为signed32（0x115fd3a68），以%08x格式化，再substringToIndex:6
（0x115fd3a90）追加。对于可表示的正epoch秒，这是8位hex的前6位，丢弃低8位时间，
不是完整四字节epoch。32字符trace的后半16字符作为span，再格式化为trace:span:0:0
（0x115fd3af8）。DeviceServiceImp.getXTraceId0x1049573b8每次转此getter；DI服务对象
缓存不代表trace值缓存，最终header覆盖及调用频次仍由请求路径决定。
DeviceTrace service注册同样来自334项component表index100（0x120272c88）
DeviceModule._$GripperDeviceTraceModule；conformance0x1183ef680对应witness
0x11b2ee368，+8为注册入口0x104957210，type cache0x120280330为BFCDeviceTraceService。
provider getter0x104957110缓存实例于+0x10，nil时分配DeviceServiceImp后保存
（0x104957138/0x104957140）。这是服务对象复用；其session/trace来自上述独立getter，
不能把对象缓存等同两个字段同生命周期。witness+0x10的unregister0x1049572b4
尚无账号caller证据，不能据方法存在认定注销清理DI。
这些unregister有真实component销毁入口：deinit0x10513123c枚举component witness
+0x10（0x1051312d4），AppState/DeviceTrace分别进入0x105037b84/0x1049572b4，
再经0x105131718→Resolver0x105136b14。Resolver在锁内按协议metatype文字与optional
name组成key，从provider dictionary实际remove（0x105137918→0x1051379a8）；这是
component销毁卸载，不是已证账号/session重置。默认root由once global0x121073918
强持有，尚无账号驱动deinit caller。注册wrapper0x10513162c调用Resolver后若throw
非零只release error（0x1051316f4），不传播或fatal；静态注册可达也不证明运行时
必成功解析服务。
相邻sessionId0x1049573a4走另一个带once的BFCDevice getter。公共桥接helper
0x1049573cc遇nil会BRK（0x10495745c），不是此层空字符串fallback；调用方的非空header
门禁是另一层。六组人工字节/正Int32秒仅验证上述格式与截断数学，不执行官方getter、
不取真实随机值或标识，也不证明服务端接受或Int32范围外转换。
这是 8.89 包内的生成和进程复用证据，属静态生成证据；运行期取值与服务端接受不可静态判定（需同版本运行样本或 9.13 抓包，见样本与证据边界章节）。

Kotlin公共 `session_id` header 的另一条消费者已闭合：AppNetParamsKt 的
provideGDeviceHeader lambda（0x10aac31bc）创建捕获服务的对象，执行入口
0x10aac47ac 在0x10aac48b0 经IFoundation接口取session，再在0x10aac48c0组pair。
root+0x210 provider经0x10b93c388→0x10aac0038，使用root+0x130的Foundation。
后者id47→0x10b93c550→0x1053a2bf0，FoundationLambda的0x1053a29ac实际
分配IFoundationImpl（0x1053a2a18）。该实现0x1053a3910→KDevice→
0x10539cdbc→platformDeviceImpl→0x10539beb8→上述0x10539d514 lazy值。
这证明此公共header消费者与上述Kotlin生成器相连，不将结论扩展为所有请求都启用该provider。

GAppRequest（名称literal=`app`）另有header写入：root+0x1f8 id71→
0x10b93c4cc→0x10aabfd28；consumer0x10aac466c从request.virtual+0xc0克隆
MutableRequest，再读取同Foundation session（0x10aac474c），以virtual+0x108
写session_id（0x10aac4774）。具象MutableRequest实现toRequest$1的
0x10a9b2b54创建HttpRequestBuilder再包装；其0x10a9b285c从builder+0x18取
HeadersBuilder，调用0x105cfbdec覆盖name/value。builder构造0x105d429c8确实
分配io.ktor.http.HeadersBuilder并存+0x18，所以这是header，不是query字段。
此处HeadersBuilder构造0x10a9aff48设置caseInsensitive=true并创建CaseInsensitiveMap；
其get/put均以CaseInsensitiveString包装header名，equals逐字符大小写转换比较。
所以Session_ID/session_id在此为同一键。setter0x105cfbdec先clear旧values再add新value，
替换原值而非追加多值；是否到达该setter还受下述write-once门禁控制。
执行方向也已闭合：builder0x10a9af3c4按sorted iterator顺序append，public hook先于
普通集合，transport最后加入；chain初始index=0，proceed0x105d55590先将next index+1，
再取list[current]并intercept。ticker/app共用0x105d5334c，其request closure在proceed前
执行。因此EnableGInterceptor=true的请求阶段确实先ticker后app；其它成员与 transport 后续覆盖属运行期装配、静态不可定，下一步 = disassemble.py 0x10a9af3c4 0x10a9af600 与 0x10b93c044 0x10b93cb00 收齐成员顺序（入口 0x10b93c044，0x10b93c814 是其内 +0x7d0）；因此不能称最终线上header绝无再写入。
ticker请求closure0x10aad280c先调用GTicket getter（可排异步refresh），再经同一
request setter写x-bili-ticket。即使write-once=true且已有该header而最终保留旧值，
getter也已执行；nil/false则替换。此HTTP closure没有空String门禁，feature关闭时
getter空串也可到setter；Moss closure0x10aad2234另有nonempty检查，不能混成同一规则。
ticker响应closure0x10aad29d4经response.headers及Headers.get取得单个String；
HeadersImpl0x105cfda9c→0x105cfe2b8返回values的首项，空列表回nil。
只有该返回值exact=="1"才调用更新，未检查HTTP status、body业务code或expiry，
也未回放原业务请求。wire 重复 header 的归一化在 NSURLSession/Ktor 引擎实现内（本镜像不含），静态不可判定，不能写成扫描任意一个"1"；下一步 = 9.13 抓包核对重复 x-ticket-status 的合并结果。
setHeader还有`Enable header write once`属性（key初始化0x105d5a8cc）：显式true且
已有header时不覆盖，nil/false才set。两处消费者值来源相同，但最终覆盖顺序、
此write-once配置及普通hook启用仍受门控，不能称app每次无条件覆盖header。

假输入离线核对通过：3 个已知 FNV-1a 向量及 1,003 个 16 字节输入的低位/格式规则，
1,003 个 LCG 状态的指令溢出与模运算等价，以及所有 1,000,000 个合法微秒值的
Neuron.init 整数除法。结果只验证算术，不验证实际种子、运行生命周期或服务端接受。

BFCActiveReport.sessionId（0x115fcfe7c）是另一条旧路径：进程 once 初始化，调用
NSString.bfc_uniqueString 并保存静态强引用，nil 兜底空字符串。bfc_uniqueString
（0x1167a5928）创建 CFUUID 字符串，追加 `.%d.%lld.%p`（rand、bfc_getTickHR、
字符串对象指针），取 MD5 并 uppercase，最后追加 `.1`。这是其生成代码证据，
不是原 UUID，也不是设备 BUVID。sessionId getter本身不持久化；下面活动记录的id另调用该生成函数。

applicationDidBecomeActive（0x115fcfefc）并行保留旧数字事件 000225 与 Neuron 系统
启动事件路径。后者组装 openudid、idfa、session_id、buvid_ext、平台/屏幕/VPN 等字段，
异步 block（0x115fd0414）取广告归因 token、mergeCAIDParams 后调用 trackInstantly。
UserDefaults 的 bfc_start_opened 为假时，额外记录 app.active.first_open.sys，并立即
把该 flag 置真；它不等待网络回执，所以“首次打开已标记”不等于服务端已收事件。
归因 token/CAID 的生成和权限条件另列广告/设备来源缺口，本文不保存实际值。

appWillEnterForeground（0x115fd04dc）读取 UserDefaults.app_active 的上一段活动记录；
有记录且包含 end 时，构造旧数字事件 000093 和 Neuron duration 事件。扩展字段包括
eid、start_time/end_time/duration、session_id、buvid_ext、buvid_fp（localBUVID）、
deviceid_fp（serverBUVID）、启动状态和另一组 *_new 时间。没有完成全部字段缺省、
防重及崩溃恢复分支验证，不应按名称推断 shumei_fingerprint 的真实 SDK 来源。
随后新建活动字典，id 调用 bfc_uniqueString，start/start_new 取两种时钟，保存
UserDefaults.app_active 并 synchronize；这个 id 与进程静态 sessionId 是两次生成。

appDidEnterBackground（0x115fd0e40）向uploadAppEndWithEndType传NSString "0"，
appWillTerminate（0x115fd0e4c）传NSString "1"，不是整数枚举。结束函数
0x115fd0e58只要求app_active及id非nil，没有检查已有end、登录状态或eid是否曾上传；
两种类型均计算当前end/duration并记录000093与Neuron duration事件。只有
[endType isEqualToString:"0"]才写end/duration/end_new/duration_new并保存、synchronize；
"1"及其他字符串不更新记录。随后foreground可能以同一个已保存eid再次提交duration；
这里没有ack或去重判断，下游是否去重未证；本轮复核（team-c21）**未在旧活动上报侧找到任何本地
幂等键或重复提交门禁**（同一已保存 eid 可再次提交 duration），去重若存在只可能在服务端或
Neuron 通道侧，静态不可判（运行期取证：9.13 抓 `data.bilibili.com/log/mobile` 看同一 eid 的
000093 是否被服务端去重）。foreground无旧记录或旧记录无end时跳过
旧duration，但无论是否提交旧记录都新建并覆盖app_active。连续foreground不会复用
当前未结束记录；崩溃后无end的记录也只是被替换，不能宣称完整崩溃恢复。

已闭合旧生命周期入口：BFCApplicationDelegate.foreground0x11597bba8→
ModulesManager0x11597d7b0→runForEachModule block0x11597d7f4；active
0x11597bbb4→0x11597d834→block0x11597d8c4。block先检查respondsToSelector再调用
对应模块。_checkSystemCallBack0x11597f138在初始化未完成时把回调名加入RAM列表，
未拦截当前派发；后续重放顺序未证。BBPhoneModule四个旧callback只在
runnableTaskOptEnable=false时调用setup。setupDidBecomeActive0x10f26ad24先调用
ActiveReport.applicationDidBecomeActive，再调用appWillEnterForeground；
setupWillEnterForeground0x10f26a96c也调用appWillEnterForeground，继而页面/PV与
AppInfo.install。不能把AppInfo.install仅凭名称归为设备注册。后台setup
0x10f26a834调用appDidEnterBackground，终止setup0x10f26ad98调用appWillTerminate。

对应PhoneGripper四个runnable body0x1001ce2ec/0x1001ce3c0/0x1001ce494/0x1001ce568
经common0x1001ce790要求UIDevice.userInterfaceIdiom==0且同一个RAM优化flag==1，
再动态调用BBPhoneModule相应setup；与旧callback是同flag的互补路径。provider
0x1001ce934从0x1001ce834固定九条任务中包含这四条。首次generated dispatch触发
once0x120272508，initializer0x1000245c0扫描184个静态provider名；entry137
0x1202743e0明确是PhoneGripperModule的RunnableTaskProvider。NSClassFromString
和协议conformance通过后，以witness+8调用该getter，把任务名/priority/trigger/thread
及执行见证建成RAM trigger map0x120272510。此处是首次派发lazy发现，不是每次
前台重复注册；任务执行仍检查当前优化flag。
GripperBridgeModule生命周期callback经0x1000282a0将对应application*触发串交给
generated dispatcher0x100027210：已在main立即执行，否则main.async。此证据闭合
生命周期触发名与任务执行体。engine 0x100027210 无一次性消费门禁（取任务→runner 0x100026bcc，未删除 map 或写"已执行"flag），因此条件稳定的重复 dispatch 在该层可重复达到 setup；实际回调频次与当前运行 flag 属运行期、静态不可定，下一步 = 9.13 抓包/日志计数 lifecycle dispatch，
也不能从静态入口推断系统可靠提供每种退出回调。
engine自身已读派发链也没有一次性消费门禁：0x100027210从RAM map按trigger取任务，
循环交runner0x100026bcc，未删除map或写task已执行flag。Phone任务thread="main"；
runner已在main立即调用0x1000240bc，否则main.async。helper依次执行pre hooks，
忽略返回值后无条件调用task.execution witness+0x28，再执行post hooks。registry的
once只缓存发现结果，不能当执行一次。条件稳定的重复生命周期dispatch在这里可
重复达到setup；这只是静态可达，实际回调频次和上游抑制属运行期，下一步 = 9.13 抓包/日志计数上游抑制点（对照 0x100027210/0x100026bcc）。


早期active回调还存在条件重放：ModulesManager初始化completion block
0x11597e2d8先执行level1/10模块回调，置isInitialized，再调用外部completion，然后
_handleSystemCallBack0x11597ee48，最后flushURLs。isModuleInitFinish则在
createModules0x11597cbe4内更早设置，两者不能混称。重放开关
launch_active_callback_enable（preset=true）关闭时直接返回并保留RAM队列；开启时，
只有队列非空、moduleInitFinish=true且非newInstall才逐selector回放。它通过
methodForSelector取得IMP直接调用各模块，不再次进入manager的append检查。
开启路径随后removeAllObjects，包含未重放的新安装/未完成分支；没有selector去重，
也不是持久可靠重试队列。newInstall还写bfcmodule_first_active_time=ceil(CACurrentMediaTime×1000)的NSString，
但此处不读取实际值。isNewInstall getter0x1167d338c实际是RAM byte；updateVersion
0x1167d31a0只有旧currentVersion=="0.0"且inReview非0才置该byte并写firstStartTime。
默认currentVersion="0.0"/inReview=true属于初值，不证明每次启动都是新安装。
FawkesConfigFawkesSetup任务0x100122d70会调用updateVersion，更具体启动边：BiliAppDelegate.launchingModules0x1051390c8依次Gripper.startup、
runWithTask FawkesSetup、SDKSetup，再UserAgreement setup；runWithTask0x100027dc4
直接generated dispatcher。Fawkes任务thread=main，故调用本就在main时updateVersion
同步先于后续setup；off-main仅排main队列，不能无条件推完成顺序。consent回调另在
safeMode=false时performOnceOnBecomeActive发送custom trigger becomeActive，再走
super模块launch；becomeActive不同于每次applicationDidBecomeActive。
BFCAppStateMonitor.performOnceOnBecomeActive0x1160207f4在first-active flag已true时
立即在caller thread执行新注册block，不再检查当前applicationState；false时复制入RAM
数组。becomeActive执行器0x1160208fc先置flag=true，再调用现有blocks、清数组并post
BFCAppStateMonitorDidBecomeActiveOnceNotification；数组为空也置flag。
因此该API是首次active前的等待屏障，之后重复注册仍会重复立即执行，不是全局拒绝
再次运行该block。BFCApplicationDelegate实际先通知monitor，再派发ModulesManager
active；custom becomeActive与module applicationDidBecomeActive入口仍分开。
这个局部解释早期恢复机制，不证明实际OS回调次数或下游事件去重。

currentMsecTimeStamp（0x115fd1788）来自 Date.timeIntervalSince1970 ×1000；
currentTikTokTimeStamp（0x115fd1808）来自 CACurrentMediaTime ×1000，两者分别是
墙钟和单调时间戳。跨重启恢复时的单调时间有效性依赖 OS（CACurrentMediaTime 跨重启不单调）、静态不可判定；下一步 = 9.13 抓包比对 currentMsecTimeStamp 0x115fd1788 与 currentTikTokTimeStamp 0x115fd1808 的差值。
_startTrackName/_durationTrackName（0x115fd29d4/0x115fd2a08）按 enable_tik_exchange
选择 startup-infra/duration-infra 或 startup-copy/duration；该配置 getter 的完整语义
未解码，不把输入常量 1 当作现版必然启用。

### 启动性能诊断的节点、采样与本地接收边界

这是独立的 `ops.misaka.app-launcher` 技术事件，不能当推荐兴趣事件。
BFCAppStateMonitor.setNodeState0x116020a60只在 `(node & ~0x80)==0x7f`
时进入process dispatch_once（token0x120e627c8）。低七位分别对应module、layout、
splash、brand splash、first frame、home、home tasks完成；user first frame与system
first frame都设置同一bit4，home images的bit7不参与门禁。其他高位仍参与比较。
reportMonitor0x116020ae4还要求disableReport=false、reportStauts=0、appState!=2、
launchState=0，接受后先置reportStauts=1再构造事件。内层拒绝也消耗once；
launchFinish0x11601fc3c虽重置reportStauts，却不重置该once token。这些函数没有
网络ack驱动的重试，不能从节点完成推出一定上传。

计时来源是_currentMediaTime0x116021d2c的CACurrentMediaTime×1000，以FCVTPS
向正无穷取整；差值以max(diff,0)变成十进制字符串。_reportTrackTech0x116020c9c
先生成8项timing dictionary，再转成`{name,duration}`数组JSON放进tasks_info。
八项是premain_time、main_time、launch_time、module_time、sys_first_frame_time、
user_first_frame_time、brand_splash_time、total_splash_time；allKeys遍历不保证顺序，
它们不是Gripper任务名称，也不是额外八个顶层字段。

顶层dictionary在0x1160219d8计数28：launch_option、first_launch、has_privacy、
splash_time、gripper_time、visited_time、tasks_info、prewarm、has_business_splash、
home_finish_success、home_request_prefetch、home_request_retry、premain_launch_state、
layout_time、home_tab_visible_time、home_time、home_visible_time、home_visited_time、
home_request_time、home_request_prefetch_over_time、home_request_prepare_time、
home_tasks_time、mi_premain_time、mi_main_time、mi_launch_time、mi_module_time、
mi_sys_first_frame_time、mi_brand_splash_time。mi_*仍用同一monitor时间戳。
prewarm先来自environment ActivePrewarm（nil→"0"），报告时还能按
misaka.launch_prewarm_extra（此调用默认1000.0）阈值修改。first_launch来自
_handleFirstLaunch0x116021c48：固定standard defaults键bfc_appstate_monitor_firstlaunch
读取旧Bool，旧false时先写true，RAM firstLaunch=!old；它独立于isNewInstall，
标记写入也先于事件接受与发送。调查没有读取实际环境或defaults。

trackTech0x1161e74a8转logId002312、trackPolicy1、samplePolicy0，sampleRate取
Memex misaka.launch_report_rate（该调用未给显式默认）。trackEvent0x1161e7c44
复制业务字段后加入app_key、config_version、dd_version及非nil cachedJobID的build_id；
这里只记录来源，不执行getter或输出值。getKMikotoSimpler0x1161e8418只接受原始
业务字典kmikoto::simpler的exact "1"/"0"，这28项没有该键，确定走nil分支。
白名单命中强制接受并写rate="1"；否则rate为sampleRate/100的%.4f字符串，
signed sampleRate>=100接受，其他值以arc4random()%100<sampleRate决定，<=0拒绝。
未看到clamp，不能补一个猜测的默认采样率。

被采样拒绝或Neuron不存在时，Mikoto仍可调用EventNotifier.postEvent0x1161e89ac
并返回1：该函数在自己的postQueue异步设置ctime，再通知本地observers，不能当HTTP成功。
Neuron接受分支也有self状态、appInfo.fts/appId与delegate捕获门禁；trackEvent
0x1161e9da8接受后只将NSBlockOperation加入trackQueue0x1161e9fe4即返回1。
消息构造在异步block0x1161ea030内重新读取appInfo.sessionId以及设备公共字段。
已核实该block的setSessionId:/setFts:（0x1161ea470/0x1161ea340）只是把共享appInfo
字段拷入本地BFCNeuron_AppRuntimeInfo副本；BFCNeuronInfoApp.sessionId静态唯一写点
是初始化快照（0x104977e34），无其他写者（stub 0x117623200调用方均为其他类），
账号/设备切换是否重建仍属运行期事实。
AppStateMonitor忽略返回值，先前once已消耗；最终发送、缓存/重试及本地observer
可能的后续传输仍须按Neuron独立链追踪，不以这个返回值替代服务器回执。
EventNotifier.addObserver0x1161e8b7c在自己的queue异步注册，以containsObject
（0x1161e8c2c）去重。已定位的native onEventWithEvent实现为NeuronObserverWrapper
0x100206904→0x1002065e4：allowEventIds须含exact eventId或"*"，接受后排global QoS
block0x1002068a4，再在NSLock保护下向局部observer fanout（0x10020704c）；该实现
没有直接track、HTTP或retry。wrapper init0x10020600c按neuron.kt_observer_enable与
mikoto.kt_observer_enable（此调用preset1）分别注册NeuronService0x10020629c和
MikotoService0x100206354，再读取neuron.kt_observer_allow_event_ids：非nil按逗号拆分，
nil默认infra.net、infra.webimage、player.player.clarity-type.0.player三个值。
因此启动事件ops.misaka.app-launcher默认不通过此wrapper。实际创建caller现已定位到
epoch mPlatformNeuron$1 initializer0x10aab1a68，注册addObserverWithObserver:
0x10aab2158并保存observer于+0x20；这闭合创建关系，不代表每次启动必执行该DI
初始化。配置覆盖与其他observer仍可能改变本地消费范围。
Neuron接受后的block0x1161eaaa4也会notify，故本地fanout
既不独占采样拒绝分支，也不能证明上传成功。
home tasks的实际节点还有重要边界：ModulesManager.onHomePageInitialized
0x11597d438经once token0x120db4388调用block0x11597d460，先homeTasksStart，
再同步runForEachModule，随后homeTasksFinish。因此home_tasks_time量的是同步模块
回调枚举，不证明所有异步首页任务完成。onHomeFinish0x11597d5f4在main立即执行，
off-main排main，再先Monitor.homeFinish:BOOL、后onHomePageInitialized，后者没有success
BOOL门槛。module init completion还读取launcher.home_task_max_delay_time（默认3000ms）；
换算秒>0.001时main.dispatch_after先homeFinishDelay、再同一homepage入口，
<=0.001直接homepage入口而不调用homeFinishDelay。该once防止重复模块回调，
同时允许无真实首页网络回执时兜底触发，不能以它作为推荐数据成功证据。
Phone Swift的具体消费者在VM registry0x101a49934订阅feedDataChanged raw24，
经0x101a5cbd0→0x101a4a164：weak VM存在且isLayoutFinished=false时读取当前
FeedUpdater.dataFactory.datas，非空调用onHomeFinish:YES并置flag=true；空调用NO但
不置flag。因此空数据通知可重复更新Monitor.homeFinish，模块初始化回调则仍受once；
它也不是HTTP业务code成功的直接消费者。
启动门禁写者也有具体来源：UserAgreement.setup0x111e19db4在
needShowAgreementView=true时先调用Monitor class hasPrivacyAlert，写RAM true后
才present agreement；不展示则直接consent completion。Launcher.setup0x113d033f8
在isInReviewDisabled=false且AppPreferences.inReview=true时调用Monitor class
disableReport，写RAM true后显示inReview controller。这些class writer不同于同名
instance getter；不能用其它类的同名selector推该monitor状态。
实际时间入口：LC_MAIN entry0x100024000在UIApplicationMain之前调用Monitor
mainStart；willFinish delegate0x11597b4d4调用launchStart；base模块launch先发起
initModules，后onLaunchFinish→launchFinishWithOptions，后者不等待所有异步模块。
homeFinishDelay只在现有homeFinishTS<=0时写兜底TS，仍设置bit5而不写success；
真实homeFinish:BOOL则总是覆盖TS和success。真实finish晚于兜底能改本地值，但
process report once已消耗时没有第二个修正启动事件。
