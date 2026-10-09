# ticket 拦截与更新入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## ticket 拦截与更新入口

HTTP 拦截器 canInitWithRequest 返回 true（0x1051f24f8）。请求拷贝后调用
BFCNetworkTickets.ticket.onTicketReq，将结果或空字符串写为 x-bili-ticket。
响应从 HTTP header 中取 x-ticket-status 传给 onTicketResp。Moss 拦截器复制
extraHTTPHeader 后加同样的请求头，并从 responseHeader 读同样的状态。
本结论只覆盖这两个拦截器。native Moss模块initializer0x100151830解析
MossService.BFCMossGatewayInterceptor数组，逐项registerGateway；Ticket模块
factory0x100134b40向同协议绑定provider，公开producer0x1001345a0返回native
BFCMossTicketInterceptor。provider conformance witness0x12028cbf0的关联类型为该
Moss协议，方法槽0x12028cc00指向producer0x1001345a0，非仅凭类名判断。
注册参数w5=1选择multibinding集合：0x1051364c0将lazy provider加入锁保护数组
（0x1051379f0）；集合读取0x105134860逐项调用member witness+0x10。
Lazy provider0x105136008取得缓存factory provider，0x105136110再调上述producer，
因此注册list到物化具体interceptor的静态链已闭合。334项service component表中，
index198（0x1202732a8）为MossModule._$GripperMossModule，index212
（0x120273388）为NetworkTicketModule._$GripperNetworkTicketModule。
root constructor0x1051313a0调用component witness+8；Ticket witness0x11b0b2c90
该槽指向0x10013461c，再进入0x100134a30注册。Moss执行则来自184项task provider表
index115（0x120274280），task witness0x11b0b4768的priority getter返回raw1000，
trigger getter0x100150e3c返回moduleInitialize（producer0x105138060），thread getter
0x100150e5c为main，execute0x100150ef4进入上述0x100151830。
GripperBridgeModule.onModuleInitialize0x100027e84以同一trigger调用公共桥接
0x1000282a0；桥接在main立即执行，off-main异步排main，再进入dispatcher0x100027210。
module manager触发也有静态前沿：base launch0x11597b65c调用self.registerModules
（0x11597b750），Bili override0x105139388的Phone/Pad分支均把GripperBridgeModule
注册为system module（0x1051393ec/0x1051394b8）；registerSystemModule0x11597ca1c
设置level1。随后base调用createModules0x11597b7b4与class.initModules0x11597b940，
后者0x11597d1a0取shared manager→instance init0x11597df90，在mainQueue排operation。
其block0x11597e558以level1执行runForEachModule（0x11597e5c0）；block0x11597e60c
检查onModuleInitialize，再以event2/level1进入_onAppEvent（0x11597e648），最终
0x11597e890实际调用该selector，接上述bridge。Bili先在0x105139108执行Gripper startup，
UserAgreement.setup0x1051391a8后的consent/safemode block0x1051391e4才经Super2
0x105139268进入base；不能省略该时序边界。base initModules调用后立即
0x11597b95c调用launchFinish，并不等待异步任务。
这闭合了登记、注册表、任务与触发器的静态对应；raw priority不能单独证明所有
gateway的最终执行次序，运行时缺失component与触发实际送达仍是独立边界。
这两个任务之间另有排序证据：TicketUpdate priority0x100095b64→0x105138008读取
0x1184440a0的raw750；Moss为raw1000，两者同moduleInitialize/main。
每trigger任务数组经0x100024cb4→0x100025364→0x100025bfc排序，record stride72、
priority在+0x20；比较0x100025ca4/0x100025ca8在previous>=current时保持，
previous<current时交换完整record，large-run比较0x100025f50采用同向条件，故降序。
merge helper0x1000264a8的forward分支0x100026568/0x10002656c比较priority，向前
复制较大项；backward分支0x100026628/0x10002662c向后复制较小项，保持同一降序，
并非只由small insertion分支推断全数组排序。
dispatcher从首元素前向+72遍历（0x10002741c/0x100027490），main且当前为main时
即时调用execute witness+0x28（0x100026e64→0x1000241cc）。因此两task都解析成功且
task interceptor允许时，Moss登记执行先于TicketUpdate setup尝试；后者随后另排
global async，不能据此推广异步完成或所有gateway顺序。interceptor false
（0x100026d90）仍可跳过任务；人工priority模型只验证比较数学。
controller0x115e0c710同步gateway数组后逐项调用canonicalGatewayRequest
（0x115e0c870），只有结果response非nil才停止；检查到的方法无URL/service白名单。
因此已初始化并注册该ticket interceptor时，native Ticket/GetTicket也可走同一网关，
getter可能再排更新；in-progress锁仍是独立门禁，不能据此断言必然无限重试。
HTTP注册范围及其他gateway次序不从此Moss注册链外推。原生HTTP侧的次序来源已闭合为
registry的append次序：BFCApiGatewayController.appendClass0x11609919c锁内仅addObject
（0x1160991dc，无排序去重），每request先copy全局数组（0x1160994fc）再按0x1160994a4遍历。
注册来自ApiClientModule注入的Swift.Array<any BFCNetworkService.BFCApiGatewayInterceptor>
（mangled name 0x11976b8fe，惰性accessor 0x1049be984/0x1049be988），循环
0x1049bea1c–0x1049bea3c逐元素调+[BFCApiGateway registerClass:]0x11609916c；贡献者已定位
BaseInterceptorModule0x10008e380、NetInfoInjectModule0x100092388、
MemexProvidersModule0x104950fa4、AccountInfoModule0x104c6f134、
DDUpdatePlugins0x10003e53c、NetworkTimestamp0x100094758。决定相对次序的指令已定位为：
Resolver注册wrapper0x10513162c（全镜像621个BL点、237个外层函数）→唯一调用0x1051316c4
→sub_1051362F0建LazyDependencyProvider（alloc 80B，0x105136334–0x105136374）→两条append
（0x105136404→sub_1051364C0、0x105136480→sub_1051379F0）；多绑定集合读取0x105134860在
provider锁内按[+0x10]count、元素起点[+0x20]、步长0x28（0x1051348d8）顺序逐项append，
无二次排序；组次序由0x1051313a0（及近同构sub_105133CE8）在0x1051314f8用sub_100025118
选组后按[容器+0x38]数组、0x105131524–0x105131544调用注册见证决定。
**重要更正**：334项service component表（0x120272648，stride16）在本镜像中**无任何代码/数据引用**
——全__text ADRP+ADD落点扫描该区间0命中，全域exact-8/tagged-8/rel-4指针扫描亦0命中；
阳性对照是184项runnable表（0x120273b50）被0x1000245ec与0x1000246e4两处引用。
因此**不能用该表的token序号当组件注册次序**（表本身仍可作名字索引：token序号=i+1，
锚点198=MossModule、212=NetworkTicketModule、213=NetworkTimestampModule）。
已完成：621个注册点→237个模块register(in:)函数的映射见站点表
（DerivedData/Validation/team-t1/reg-module-map2.json，工具map_reg2.py）；gateway相关模块的
register函数与注册点为 Base0x10008e010/0x10008e15c、NetInfo0x1000921ac/0x10009227c、
Memex0x104950654/0x104950898、Account0x104c6f164/0x104c6f234、DDUpdate0x10003e144/0x10003e198、
Timestamp0x100094758/0x100094828、FlowControl0x10495b948/0x10495ba18、
NetworkTicket0x100134a30/0x100134b00(http)/0x100134b7c(moss)，模块内次序=函数内地址顺序。
**跨模块相对次序不可静态定序**：模块组件类既无classRef也无任何ADRP+ADD/LDR代码引用
（4类抽样全0），register witness只在__const（13槽，如Base0x11b0a8020）且全镜像无数据指针指向它们，
容器以__swiftEmptyArrayStorage空起步（0x105133ef4/0x105133f08，helper在count==0时0x105133b00/
0x105133c0c立即退出）；最小原因=组件列表由运行期元数据/witness装配，镜像内无静态顺序表。
原生HTTP canonicalRequest0x1051f2500无条件setValue，nil ticket改空字符串，
没有已有值保留、empty或host门禁。原生Moss0x1051f26b4先合入旧extraHTTPHeader，
再以exact dictionary key覆盖ticket，nil也改空；它不同于Kotlin Moss的nonempty门禁。
HTTP响应入口0x1051f25d4要求NSHTTPURLResponse类型，再从allHeaderFields字典取键；
原生Moss从responseHeader字典取键。Foundation/transport 对响应 header 大小写与重复头的归一化在 NSURLSession 实现内（本镜像不含），静态不可判定，不能据 exact subscript 断言 wire 大小写变体一定失败；下一步 = 9.13 抓包核对同一 key 的大小写变体与重复头合并，静态侧对照读取点 0x1051f25d4（HTTP）。

BFCTicket.onTicketReq（0x100096328）的内部函数 0x100096170 在锁内读取 ticket 与
expireAtInS，解锁后比较当前 Unix 秒。当 expireAtInS 为零或剩余秒数不足配置中的
提前量时调用 0x100099678 安排异步更新，同时返回读出的旧 ticket；更新不阻塞这个 getter。
服务内部禁用状态会返回空字符串。提前量来自运行时配置，默认 1800 秒。
原生facade getter BFCNetworkTickets.ticket0x1051f2864转
BFCNetworkTicketConstWrapper.ticket0x100134fec，以once token0x120899958缓存解析到的
service强引用。getter本体不按当前账号重新解析service；账号变化是否另处reset此
service或sharedTicketPrefs仍须独立核对，不能从单例复用推出账号绑定或解绑。

onTicketResp（0x1000964d4 → 0x100096380）在内部启用且状态等于字符串 `1` 时，
记录服务端判定到期并调用同一异步更新入口。0x100099678 分派任务到 queue，实际更新
路径含锁保护的进行中标志（0x10009988c 附近），避免同时重复更新。
TicketInternal状态有三类：构造0x100099108把feature开关保存到+10
（0x1000991b0，输入是BFCTicketConfig单例槽0x1210643d8的+0x10，0x10009918c/0x1000991ac），
该字节由BFCTicketRuntime0x10009ae38读实验ticket_enable得到（键是内联小字符串
0x10009af30–0x10009af4c，hitExperimentalGroupForKey:presetHitValue:1在0x10009af5c/0x10009af6c，
落[sp+0x2c] 0x10009af70，打包0x10009b36c），presetHitValue=1只是无分组时的预设值；
TicketInternal的唯一构造调用点是-[BFCTicket init]0x100095ec8。
startup0x10009937c只设置setup-ready +20=1（0x1000993f4）；
worker0x100099880在锁内要求setup-ready==1且inProgress +21最低位==0后，才置
inProgress=1（0x1000998d8）。feature启用与setup完成不能混称一个开关。getter先要求
feature==1，再读缓存；提前量比较严格为expiry-now<threshold，相等不触发更新。
即使已经过期仍返回读出的旧ticket，没有硬到期清空分支。

更新enqueue0x100099718、Moss延迟请求0x1000985b4及响应转发0x100098884都读取
once0x12027cf60和同一queue槽0x1210643c8。构造0x100098eac以空Attributes、
target=nil调用queue.init0x100099048，未供concurrent属性，支持同一串行队列。
TicketInternal self+0x18为锁，不是该queue。两个getSpecific调用
0x1000983e0/0x100098be8只释放结果继续，未构成线程断言、拒绝或队内直接执行门禁；
真正去重仍由ready/inProgress锁保护，不能仅凭串行队列排除先后多次刷新。

整个二进制直接B/BL扫描到更新入口0x100099678仅发现getter0x1000962bc、状态1处理
0x1000964a0和startup0x100099554三个调用点；不排除间接动态入口。worker不复查
排队后最新expiry，只检查setup/inProgress；先前排队的worker若在成功清inProgress后
运行，仍可能再开一次RPC，这是控制流可能性而非已实测重复请求。
内部 RPC 构造函数 0x100096814 创建 GetTicketRequest：context=1 是 string→bytes
map，keyId=2 是固定键标识，sign=3 是 bytes，token=4 为 string，此构造器未赋 token。
这不代表没有公共账号 metadata。context 实验启用时加入 x-fingerprint（设备指纹二进制
材料）及 x-exbadaset（安全模块材料）；其值不写入研究资料。调用
0x100098d48→BAPIApiTicketV1Ticket.getTicketWithRequest:handler:，默认 gRPC host 为
grpc.biliapi.net，package=bilibili.api.ticket.v1、service=Ticket、method=GetTicket；
此默认路由不是所有网关或实验分支的实测结果。

该调用receiver是Ticket类：classmethod0x10518e5f0先defaultService，再调用instance
getTicket；defaultService0x10518e51c每次alloc/init，没有once service。wrapper创建
0x10509f93c在REST=false时取注入service implementation的options witness+0x20；
已闭合MossServiceRealImpl的0x100151544→0x107c24fa0→0x10f82fcac→0x115e06c20，
最后helper每次重读当前accessToken及Device/Network metadata。所以native刷新RPC
service创建时取当前账号资料，并非TicketMoss长期缓存一套旧service options；
KMoss分支仍由其engine提供metadata，不能外推同一最终header。
这与成功时保存共享TicketPrefs是两个边界：刷新可读新账号，保存仍无可见
account-generation检查，尚无实机切账号行为结论。

签名输入（0x100096d40）先 append 新构造的 BAPIMetadataDeviceDevice 的 Protobuf
bytes，再按 context key 字符串升序逐项 append UTF-8(key)+raw(value)，没有在这些
append 之间加长度或分隔符；空 key 整项跳过，空 value 仍保留 key。设备 metadata
来自构建、设备、guest 及指纹服务，与 Neuron AppInfo 的字段来源不同。0x100099f3c
调用 CCHmac SHA256，将固定客户端签名材料作为 key，输出 raw 32 bytes 写 sign；
空消息或空 key 在此函数返回空 Data。本文不保存实际签名材料，也不把客户端请求
签名当成服务端 ticket 铸造算法。

GetTicketResponse 描述符为 ticket=1/string、createdAt=2/int64、ttl=3/int64、
context=4/message。成功回调 0x100099934 根据 response 非 nil 进入 0x100099978，
没有在此分支同时要求 error 为 nil。expiry 使用回调时 Date Unix 秒+ttl；配置
ttlOverwrite 非零时替换 ttl（没有限定必须为正），createdAt 未参与该计算。锁内
分别写 TicketPrefs.ticket/expireAtInS 并清进行中标志。失败 0x100099cdc 只清该标志，
保留旧票据和旧 expiry。TicketPrefs 是 BFCPreferences 子类，动态属性由通用层安装
读写方法，使用 BFCTicket UserDefaults suite；两属性独立写入，没有证明事务性落盘。
这些局部路径均使用TicketPrefs全局singleton槽0x12027d090和固定suite，没有按UID/
access-token选命名空间，也没有成功保存前的account-generation检查；只能证明这里
共享一份本地缓存（TicketPrefs 单例槽 0x12027d090）。有界槽引用扫描命中 4 个载入点：
BFCTicket init 0x100096208、TicketPrefs shared 0x100096764、startup 0x10009943c、
成功保存 0x100099c10；未在该扫描形态发现直接置 nil/替换该槽。
这不覆盖 swift_once 初始化、对象内部字段清理、间接寻址及存储后端删除，
因此撤回“静态不存在登录/登出 reset”全链结论。跨账号复用、实际失效策略和
9.13 生命周期仍未证，应分别追清对象 setter/清理调用与运行期样本。
【9.13 抓包观测（线级，team-c12；build 91300100；证据 DerivedData/Validation/team-c12/
auth-planes.jsonl、engine-headers.jsonl、endpoint-inventory.json）】ticket 头的**出现面**已可判：
`x-bili-ticket` 在 `dataflow.biliapi.com`（Neuron 日志通道）1,439 条、`grpc.biliapi.net` 1,234 条、
`api.bilibili.com` 924 条、`app.bilibili.com` 727 条、`passport.bilibili.com` 258 条均出现，
而在 `cm.bilibili.com`（广告）与 `data.bilibili.com`（旧 V2 日志）为 **0**——即"并非全部请求都带
ticket"在现版成立，覆盖面与拦截器注册范围同形。`x-ticket-status` **响应头只在 webview 请求
见到 22 次且取值恒为 `1`**（`/x/click-interface/web/heartbeat` 20、`/x/web-dynamic/v1/detail` 1、
`/x/v2/reply/reply` 1），官方 App 原生请求 0 次。全语料 `POST /bilibili.api.ticket.v1.Ticket/GetTicket`
仅 **3** 次，且无"失败后连续多次 GetTicket"样本，故 `get_max_tries` 是否被消费仍不可判（弱否定）。
`magent` 头给出的现版版本串为 `…9.13.0_91300100`（海外 `…6.6.0_91300300`）。
"跨账号复用同一份缓存"需换号前后对照，本次样本不含。

TicketMoss（0x1000982b0）按 `min(failureCount×baseDelay,maxDelay)` 安排下一次请求，
值小于 1 时立即安排且无 jitter，否则再加 [0,maxJitter] 的浮点均匀样本。乘法与失败
计数递增带溢出 trap。回调 0x100098ac8 在 response 非 nil 时清失败计数，否则加一。
RPC wrapper0x100098a1c→捕获回调0x100098dd8→0x1000987d0先转发到同一queue，
queued thunk0x100098e14再调用0x100098ac8，先写failureCount（0x100098af4），
后调internal callback（0x100098af8）保存/清inProgress。response非nil的计数重置
不同时要求独立error为nil；这里只证明串行响应leg中的顺序。
失败回调不自动递归重发（下文并证实配置里的重试上限从不被读取），因此不能将其描述为一次刷新会自动重试四次；
下文证实配置里的重试上限根本不被读取，这一点不依赖运行期观测。
配置默认 baseDelay=1、maxDelay=15、maxJitter=1 秒，均由BFCTicketRuntime0x10009ae38以
getIntegerForKey:defaultValue:读入（ticket.get_max_jitter_in_seconds0x10009b1f4、
ticket.get_max_tries0x10009b25c默认4、ticket.get_retry_base_delay_in_seconds0x10009b2c4、
ticket.get_retry_max_delay_in_seconds0x10009b330），再打包进BFCTicketConfig
（0x10009b380/0x10009b384/0x10009b388）。get_max_tries落cfg+0x30，但加载该配置槽
0x1210643d8的全部7处（0x1000962a4/0x1000968d0/0x100096a18/0x100099194/0x1000994a4/
0x10009ab1c/0x10009abf4）只读+0x10..+0x13、+0x18、+0x20、+0x28；整个ticket区
（0x100095000–0x10009b500）内的非栈[x,#0x30]访问只有0x100098e68（dispatch queue
attributes）与0x100099ff8（CCHmac上下文）。因此8.89里这个上限只被存储、从不比较，
重试次数不由此值约束。（复查：全镜像读取键 `ticket.get_max_tries` 的代码仍只有 0x10009b25c
这一处加载点，无新增消费路径；Kotlin/Native 引擎是否自行按 tries 限制重试静态不可判——
Kotlin 桥 0x10aad2b54/0x10aad2e90 之后无可读消费符号，属运行期装配，
取证方式=真机断点 worker 入口 0x100099880 数 GetTicket 频次，或抓包对照连续失败样本。）
ticket_enable 与三个 context/security 实验的 presetHitValue=1，只是默认参数，不证明
实际命中。TicketUpdateModuleModuleInitialize（0x100095c5c）经注入的 TicketSetup
协议见证函数 0x100096584，调用 0x100095f08 安排 global/default QoS 异步任务；
block 0x1000965a4→0x10009935c→startup 0x10009937c。在锁内标记setup-ready，并按缓存
expiry 决定是否异步刷新。根清单、moduleInitialize派发和Moss-before-TicketSetup
尝试顺序已在上文闭合；实际异步完成时序仍未执行验证。

KTicketServiceImpl.onTicketWithHost:path:（0x100134734→0x100134d58）不使用传入的
host/path，直接调用注入 ticket.onTicketReq；update（0x100134848→0x10013478c）
以状态字符串 `1` 调用 onTicketResp。Kotlin 的 provideTicketRequest$2 函数指针
0x11c350818 对应 native 桥 0x10aad2b54，内部调用上述 getter；邻接桥 0x10aad2e90
用于 update。协议桥接已证（native getter 0x100134734→0x100134d58、update 0x100134848→0x10013478c、Kotlin 桥 0x10aad2b54/0x10aad2e90），引擎何时调用属运行期装配、静态不可定；下一步 = scan_callers_set.py 0x10aad2b54 0x10aad2e90，
不能据此认定全部 Ktor 请求都携带 ticket。
Kotlin coroutine 0x10aad2234 的父接口实际为 kntr.base.moss.MossInterceptor，
只在 ticket 非 null 且非空时加 x-bili-ticket；响应 x-ticket-status 精确等于 `1`
时调用 update。另一 provideTicketRequest$1 的请求/响应回调（0x10aad280c/
0x10aad29d4）同样调用 GTicket，前者未见相同的空值检查，后者也只识别 `1`。
这两个回调（0x10aad280c/0x10aad29d4）的安装方就是 provideTicketRequest 0x10aad1ab8 构造的 RequestResponseHook，进入 18 成员集合的路径已闭合（注册读取点 0x10b92111c）；残余= Enable GInterceptor request attrs实际写入；key槽0x120c5e410间接初始化写已定位，不再援引0写点，因此不能因 Kotlin 桥名就归类为所有 HTTP 请求。

离线假数据验证通过：Python 与 CommonCrypto HMAC-SHA256 2,000 组对照、24 个
context 排列的拼接结果及 100 个退避边界。只验证原语和已推导规则，尚无同版本
官方执行或服务端验收证据。
