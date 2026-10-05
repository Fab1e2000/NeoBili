# iOS 客户端网络协议研究

本文维护客户端请求及上报的覆盖范围、静态调用证据和缺口。推荐样本与当前 NeoBili 行为见
[推荐观察](RECOMMENDATION_OBSERVATIONS.md)，身份字段详解见 [NOTSURE.md](../NOTSURE.md)。
本文是研究参考，不是官方接口规范，也不表示 NeoBili 已实现这些机制。

## 样本与证据边界

静态对象是第三方提供的解密 iOS 8.89.0（build 88900100）主程序。包中还包含第三方
BilibiliVideoTools 动态库，不能保证包与官方分发版本完全一致。现有抓包含其他版本，
尤其 9.13；跨版本一致性必须逐项核对。没有安装或运行这个分析包，也没有恢复实时采集。

地址均为该 Mach-O 的未滑动虚拟地址。符号恢复有同地址别名；结论需要指令、selector、
常量或调用链共同支持，不能只看函数名称。Objective-C 动态分派、Swift 协议调用、Kotlin
桥接、运行时配置及拼接 URL 会留下盲区，字符串数量不能作为全部请求已覆盖的分母。

地址交叉引用索引另外保存了 5,890 处 ADRP+ADD 引用，涉及 3,003 个 URL/路径字面量，
附最近的前置 Objective-C 方法候选。这只是入口定位辅助；存在中间跳转和寄存器覆盖
可能，需定向反汇编确认，不能视为已证明发送或函数归属。

大体积符号、字符串、端点候选索引、原始反汇编和离线验证产物保存在忽略目录
`DerivedData/Validation/official-ios-package/analysis/`。原始抓包仍在仓库外。本文不保存
实际账号、设备、token、ticket、密钥常量或包含安全验证内容的 URL。

### 本地联网对照的当前边界

用户已授权基于既有本人账号及设备资料做少量本地脚本请求；第三方处理的App仍
不执行，手机采集仍关闭，也不扩大到曝光、观看或互动。本轮独占实验资料在忽略目录
`DerivedData/Validation/recommendation-network-s1/`，S1串行执行，S2离线复核。
本轮限定三次feed/index GET：正确签名且不带ticket、仅改变sign的负控制、恢复正确
sign并加入捕获ticket；设置最少15秒间隔，固定同一个ts与既有业务参数/游标。
读取本身可能推进推荐状态，因此列表差异不是单参数推荐因果证明。

离线前置核对已用既有官方9.13（build 91300300）样本复算原sign，与本地
AppSigner所用key/secret在内存中匹配；严格iOS转义和当前JS保留字符两种复算
均匹配，但输入值没有那五个争议字符，不能据此确认两种编码规则等价。
这也不是8.89静态机制已在9.13完整复现的证明。捕获ticket的实际签发时间及当前
有效性尚未确认；加入后即使成功，也不能直接证明票据被验证或参与了推荐。

用户开启本聊天完全访问并要求继续后，既定三次请求已执行完毕；先前沙盒尝试
未取得HTTP响应及自动审批拒绝保留为独立记录，不混入服务器响应。三组相对基线
变化如下，ts在循环前统一生成，第二/第三组分别晚约18/36秒，旧flush/pull/idx
仍沿用样本；第三组相对第二组还恢复了正确sign，不能说相邻请求只改ticket。

| 顺序 | 相对基线的变化 | HTTP | 业务code | items结构/数量 |
| --- | --- | --- | --- | --- |
| 1 | 新ts、复算sign，不带ticket | 200 | 0 | 对象数组，10项 |
| 2 | 仅把sign首字符改成不同值 | 200 | 0 | 对象数组，10项 |
| 3 | 正确sign，加入已有捕获ticket | 200 | 0 | 对象数组，10项 |

三组都含10个goto=av项；后两组各自与基线的唯一视频编号重合数均为0。
这里每组不是同一推荐状态的重放，没有额外曝光上报；仍不能把列表变化归因于
sign或ticket。错误sign的负控制同样被接受，明确限制了“成功即证明签名校验”
的结论：本次端点/身份/参数组合没有拒绝该错误sign，不推广为其他端点或所有
认证通道都不检查sign。未另调用账号校验接口，不能由列表成功证明服务端使用了
access_key对应的个性化身份；带ticket成功亦不证明其有效或被使用。原始输入、
响应头/正文保存在权限0600的忽略目录，脱敏摘要为summary.json；未扩大请求数。

### 社区镜像辅助索引

用户提供的保留资料可用于定位遗漏字段和消息，但不提升上述证据等级。
[API-collect 推荐页](https://github.com/melon-444/bilibili-API-collect-fork/blob/master/docs/video/recommend.md)
把 feed/index 放在短视频模式章节，承认部分参数备注不确定；不能将其说明直接作为
8.89 iOS 首页的生成规则，也不能补出本页未证明的 flush 生命周期。
[App 签名页](https://janson20.github.io/bilibili-api-collect-mirror/docs/misc/sign/APP.html)
可作为排序、编码及摘要的比对索引；平台、功能与版本的差异、编码边界仍以具体
调用链核对。社区描述与 IPA、既有抓包或当前源码冲突时分别记录，不覆盖强证据。
这里只读取文档，不执行其中的真实请求或互动样例，不保存凭据示例。

## 覆盖清单

覆盖等级分别记录：**定位**（入口/模型/端点候选）、**字段**（字段结构及来源）、
**流程**（生成、触发、发送、响应、存储和复用）、**复现**（假数据离线验证）、
**现版**（同版本实际行为验证）。局部完成只表示该子项，不能提升整个模块的等级。

配置核查入口：[SeriesLoader 参数与响应](#seriesloader-参数与响应证据)列出各kind的config/当前item/edge来源、URL与filter门禁；[HD2 首页请求与响应](#首页-vm-的首次请求重试与响应状态)列出MainVM builder/send/retry及服务器config应用，[HD2 follow模式持久化](#hd2-follow_mode-响应持久化与-logout-清理)区分响应follow_mode、本地feed_mode和请求recsys_mode。三者均限8.89静态样本，设置UI或服务端配置发送条件未闭合处各自保留。

这些是配置/请求证据，不是名为“Series/HD2日志”的新独立章节。Series锚点为
URL getter0x10411a640、params0x10411a6e4、response0x10411af68→0x104118064；
HD2锚点为MainVM.loadData0x10df58a10、apiProcess0x10df58dfc、success
0x10df59104、error0x10df59ab8。业务事件另见[推荐点击、展示与可见时长](#推荐点击展示与可见时长的业务触发)
和[HD2卡报告精度与序号](#hd2-卡报告时间精度与请求局部序号)，通用发送另见
[旧V2文本日志](#旧-v2-文本日志通道)及[Neuron](#neuron-protobuf-日志通道)。
Series焦点曝光producer已在请求章节内追加具体链（0x10410aa94→0x10410befc→
0x1041eede8/0x1041ee0a0），全部日志producer及配置到全部字段映射仍未闭，不把请求章节当整体完成。

全局索引当前含 5,018,163 条带地址符号、715,673 条 Objective-C 方法项、2,117 条 URL
字面量及 1,053 条路径候选。这些是索引条目数，含重复、资源、网页和 SDK 内容。
主机候选包括 api/app/passport、动态/直播/会员/漫画/游戏/商城/支付、日志/广告及 CDN。
下面所有“候选”都还需要入口和实际发送路径确认；缺项不等于无请求。
RunnableTask库存的zero-based index从首String pair0x120273b50开始，stride16；
array header0x120273b30的count184位于0x120273b40，不把header计作provider。

| 模块 | 定位 | 字段 | 流程 | 复现 | 现版 | 下一项缺口 |
| --- | --- | --- | --- | --- | --- | --- |
| 传统 HTTP 公共层 | BFCApiRequest / BFCApiSignHelper | 参数与头合并顺序、默认回调队列 | 构造/缓存、operation取消与结束回调局部 | 未做 | 未做 | 配置更新、缓存调用方、gateway错误加工与外部全局取消/重试 |
| Ktor 公共层 | KtorClientObjc / HttpClientOpt / CommonParamsPlugin | 桥接选项、公共参数、签名编码及拦截器开关 | Root factory/ticker安装、双transport选择与门控；Locale hook/独立缓存与编码；MD5局部 | 合成签名边界算术 | 未做 | 业务 enable 写入、body分支、native adapter 与回退 |
| Moss/gRPC 公共层 | BFCMossConstWrapper / RestConstWrapper、DeepBlue interceptor | 身份/会话、native metadata与Locale map采用范围 | ticket、native unary/回退及gateway覆盖次序；GrpcEngine binary Locale局部 | 未做 | 未做 | 其他platform/stream Locale采用、压缩与完整重试/流生命周期 |
| HTTP 跟踪 BUVID | BFCBuvid | 36 字符格式 | 初始化与持久化已解码 | 假数据及现有样本形状 | 未验证首次生成 | 各调用方、重装与现版来源 |
| 指纹登记 | BFCDeviceToken | 54 项 Protobuf 描述符；字段赋值局部 | 加密、缓存、登记回调/节流已解码 | AES/RSA/校验和通过 | 未做 | 54 项实际取值、全部调用方、版本兼容 |
| 访客与登录资料 | BFCAccountGuest / DeviceToken / GuestInfo | 访客五项、登录字段与 UI 会话 | 登记回执/保存、SMS 复用与通知局部 | CBC/会话边界假数据通过 | 未做 | 间接重置、RSA 内部与资料默认值 |
| ticket | BFCTicket / HTTP 与 Moss 拦截器 | 头、RPC PB、签名拼接及配置 | 系统module/Gripper注册触发、刷新退避、回执保存；Ktor 注册 | 假数据原语/拼接通过 | 未做 | gateway实际次序、执行 enable、tries 消费及实际配置 |
| 会话与生命周期 | DeviceService/KntrSessionIdProvider、BFCActiveReport | 来源分流、Kotlin 会话、native trace、StartTrace、活动记录 | DI/lazy复用、prewarm刷新、任务注册派发、活动保存及早期回放局部 | 会话/trace算术假数据通过 | 仅已有抓包观察 | 实际flag/OS回调、登录切换、下游去重与现版验证 |
| 业务日志公共层 | BFCTracker / 旧 V2 / BFCNeuron | 文本结构及 Neuron 68 项描述符 | 两类发送/回执局部；Neuron 入队编码 | Neuron 假数据分帧/校验 | 未做 | 注册、调度配置、缓存与业务事件触发 |
| 首页/相关推荐及曝光点击 | feed/index、feed/index/interest、Pegasus、View/RelatesFeed 候选 | 请求、事件扩展与阈值、批次编号、缓存/兴趣marker；T10/18/19/33/34/35/37选择编码局部 | show/click/duration、页面/后台结算、refresh/cache恢复、兴趣启动事务/guide、second门禁/回执/所有权、编号/dislike局部 | 现有协议分析 | 跨版本样本；三次GET结构成功，验签/个性化未证 | 去重池、新请求/账号归属、accepted事务完成、其他兴趣UI、设置/实验余项 |
| 视频详情/播放/心跳/弹幕 | ResolverUGCHelper、HeartBeatServiceV2/AtomicHeartbeat | 播放 PB、能力参数、历史/心跳/Atomic及内联事件字段局部 | 计时/会话迁移、UGC/OGV/内联资料构造及replay、心跳缓存重试、Atomic注册/timer/delegate、Moss状态及诊断probe/队列 | 能力/会话/画质/时钟假数据局部 | 仅已有抓包局部 | 其他详情/UI 源、解析选择、弹幕、诊断OS实效、统一接口余项 |
| 搜索/历史/稍后再看 | SearchResultVM/ApiV2、CloudSyncHelper/Service、旧Phone/BBList WatchLater | HTTP/gRPC 综合搜索日期/游标、历史校验、WatchLater旧add/del/list、新single/bulk add与v2列表/删除字段 | 查询会话/实现once选择/取消边界；历史写入；WatchLater回执/展示、行点击/选择、Rx/appearance/刷新/游标、reducer与缓存注入/文件IO/失效局部 | 未做 | 未做 | 搜索筛选UI/旧回执归属/其他回退、历史补同步/存储、WatchLater完整账号生命周期与资源来源、缓存并发与取消实效 |
| 动态/关注/用户空间 | DFSumViewController / Dynamic RPC | DynAll/Personal/Video PB、会话与播放参数局部 | 刷新/排序/自动补页、账号 baseline 与缓存读取局部 | 时区算术假数据通过 | 未做 | 缓存后端/恢复、过期回执、发布与关注变更 |
| 互动/评论/收藏/分享 | CommentMossAPI / PosterApi / Broadcast与键盘VM | 主列表/详情/折叠/补取/广播PB、发布、赞踩/删除/置顶、收藏入口 | 列表分页/会话、广播插入/room、发布验证码/草稿/局部插入与操作确认 | 未做 | 未做 | 草稿DI注册/完整UI、错误恢复、通知刷新消费者、收藏余项/分享 |
| 直播 | ProcessScheduler / BaseHTTPClient / OnlineConfig / WatchDurationReporter；长连接候选 | 播放/房间、保护头、mapper；观看26项body/签名来源 | 双请求/cancel/scatter、验证码续发；观看开始/退出/timer、失败重发/补交及播放器触发局部 | delay/签名枚举边界假数据 | 未做 | 入房权限消费者、配置存储、长连接、观看并发/账号清理与现版验证 |
| 消息/推送 | BBCPushCenter / BFCPushService / ActivityTokenMonitor | APNs12、ActivityKit7、点击/角标、收包/路由/growth字段 | 调度事件、权限/账号、token重试、静默/点击路由与本地通知局部 | 未做 | 未做 | 全局事件排序、扩展动作、消息未读/同步 |
| 设置/远程配置/实验 | 设置页/InlinePreferences/Device与MidConfig | 自动刷新/声音/弹幕/均衡/自动播放/布局/模式/HDR/画质/禁个性化来源 | 设置写入/默认、请求缓存/覆盖、生命周期刷新；翻译UI编辑/退出提交/current与SYSTEM区别/KVO；Phone模式PB/通知/退出重置、Story手动模式/gesture/画质控件与解析回执、引导路由/曝光/timer及HD2 follow/idx局部 | 未做 | 仅已有抓包观察 | upload持久与账号余边、Phone模式实例/本地恢复、SYSTEM外部reset、HD2设置路由映射、其他参数/实验 |
| 会员/番剧/漫画/商城/支付/游戏/创作 | 全局索引候选；VIP HD materials/report | VIP三个position、响应模型及点击参数 | PGC base发送/类注入/Gripper；HD续播RPC、toast/TopBar/UserCenter列表回执及账户通知；素材上报/失败队列、动态module/真实按钮/appearance/严格曝光scheduler局部 | 未做 | 未做 | 动态路由目标、其他素材入口/账号队列reset；其他子模块请求族及 SDK 边界 |
| 广告 | UGC播放器AdManager / BBAdReport / UIReport / BCMReport；cm候选 | dm/ad四项、ad_extra字段/类型及AES包装、conversion/fee/Monitor POST、MMA宏GET、BCM source/覆盖顺序、AdTrack/AdAlarm分类及采样 | aid匹配/cancel/回执、双16秒等待、独立缓存/批量重传、Once、App前后台/callup成功标记及回调门禁、Kotlin→epoch Mikoto/账号DI局部 | 假数据采样/参数合并边界 | 仅已有抓包局部 | 实际触发/UI验证、展示/点击/归因及Monitor producer、其他callup入口、Monitor外部retry |
| 性能/崩溃/诊断 | BFCTrackerCrash / Analytics / 日志上传候选 | Crash字段/Tech→Mikoto、LogService JSON/双本地出口 | AB门禁/两秒启动缓存重放/本地完成及删缓存、DI/backend配置snapshot、BLog文件队列、Laser附件/上传/回执及UPOS阶段/取消/过期局部 | 未做 | 未做 | UPOS取消后的Laser completion、Laser任务过期/外部clear、其他业务可达性 |
| 第三方 SDK/CDN/网页 | 依赖和 URL 候选 | 未系统解码 | 未系统解码 | 未做 | 未做 | 所有者、实际加载与独立传输协议 |

## 传统 HTTP 参数与请求构造

`BFCApiSignHelper.baseParams`（0x11609c68c）创建可变字典，包含 platform=`ios`、
device（phone/pad）、Bundle build、mobi_app、appkey、actionKey=`appkey`（字面字符串），以及有值时的
c_locale/s_locale。statistics 是 JSON 字符串，内部有 appId、platform、version、abtest；
它不是外层 platform 字符串的复用。青少年、课堂、海外青少年与关闭个性化参数带条件分支。
customParams 最后合并，可覆盖已有键；随后审核分支可再写 appver、filtered=`1`。
这些 getter 的实际运行时取值尚未全部追到最终来源。

`authenticationParams`（0x11609cc58）在基础参数上加整数 Unix 秒字符串 ts，
accessToken 长度非零时加 access_key。`authenticationParamsWithoutTs`（0x11609cd80）
只加同样的 access_key，不加 ts。

`BFCApiRequest._queryString`（0x116097308）在 Ktor 未启用时按 signType 分支：

| signType 原始值 | 初始参数 | 本层加 sign |
| --- | --- | --- |
| 0 | authenticationParams | 是 |
| 1 | baseParams | 否 |
| 2 | authenticationParamsWithoutTs | 是 |
| 3 | 空字典 | 否 |
| 其他 | 空字典 | 由本层条件决定，尚未证明有调用方 |

随后按 apiKeySecretType 切换已有 appkey，按 enableDeviceNameParam 补 device_name，
再合并 options.params，因此业务参数能覆盖公共参数。对 0/2，本层在合并后生成 sign。
Ktor 启用时初始字典为空，本层不生成 sign；不能由此推断最终请求无签名。

`createSign:`（0x11609ce34）按键的 compare: 顺序排序，将各值 description 进行 URL
编码，拼成 key=value，用 & 连接且去掉末尾 &，追加按 appkey 选择的 secret，再取 MD5
小写字符串。`_encodeUrl:`（0x11609d68c）调用 CFURL percent escape，UTF-8，显式转义
`!*'();:@&=+$,/?%#[]`。没有将实际 secret 常量写入本文。

`buildQueryString:`（0x11609d0f8）是另一条序列化逻辑：排序键、跳过 api、对以 []
结尾的数组键走数组分支。不能假定它与 createSign 的输入处理完全一致；数组、空值、
非字符串的确切行为及离线向量还需验证。

`_buildRequestOperation:afterRequest:`（0x11609537c）支持 customRequest。通常路径创建
请求后依次写 User-Agent、非空 Session_ID、非空 x-bili-trace-id、options.extraHTTPHeader、
authenticationHeaderParams；后者目前仅返回非 nil 的 BFCBuvid 作为 Buvid。
因此认证 Buvid 可以覆盖 extraHTTPHeader 中同名字段。正文后还会执行 requestInjection，
再进入 gateway canonicalization/suspend 拦截。这里不是最终发包头的完整列表。

## options 默认值、缓存与响应入口

BFCApiOptions.init（0x116091c20）只显式设 timeoutInterval 为 20 秒，getter 下限为
5 秒；其余原始值来自零初始化，业务构造器仍可修改。taskType getter（0x116091cac）
还检查 Cronet 白名单、fallbackList 与 IgHttpEngine.enable，满足条件时返回 2，
否则返回存储值。这是引擎选择入口，并非固定常量。
requestMethod getter（0x116091dec）读零初始化存储；公共 builder 0x116095540 将
0 走默认 GET 构造（拼非空 query、未另设 HTTPMethod），1 走 baseURL POST，
2 先将 query 拼 URL 再 POST，其他值返回 nil request。customRequest 和后续
requestInjection 可覆盖，不能只看默认值断言所有实际请求方法。

BFCApiRequest._getKey（0x116093000）在 ignoreCache 为真时返回 nil，否则从
options.params 建字典，加 apiPath（实际是 baseUrl）、signType 与 Bundle 短版本，
JSON 序列化后取 MD5。这个函数没有自动加入公共 access_key、BUVID 或 Session_ID；
账号是否隔离取决于业务 params 和其他清理调用，仍需逐项追踪。代码中的 allKeys 遍历
没有观察到移除字段的操作，也没有显式 JSON sortedKeys 选项，不能用排序查询串替代缓存键。

_queryLocalCache（0x1160932f8）从 BFCApiCacheKVDB 取字符串与保存时间，转 UTF-8 后
走同样的反序列化；解析失败清空返回对象。新鲜判据是当前时间严格晚于保存时间，且
差值严格小于 cacheValidLife；旧对象存在不等于返回“缓存有效”。_query 的本地 block
0x1160927dc 只有在有 completionHandler 时先读缓存；fresh 且 ORM 无错误、对象
非 nil 时完成回调并返回 false，短路本次网络。fresh 映射失败仍可进入
customResponseBeforeRequest；stale 且有 cachedHandler、ORM 成功时先交缓存，随后
继续网络，不能把所有缓存回调都当作网络被跳过。

网络 block 0x116092b74 在 raw 反序列化成功，且 responseAbleToCache 缺省或允许、
cacheValidLife>0、UTF-8 raw 与 _getKey 非 nil 时，将 raw 写入 BFCApiCacheKVDB。
setValue 的 logicKey 是空字符串，写入在 ORM 之前；后续模型映射失败不等于没有
写缓存。AccountNotiInfoModule.logout（0x104c6b418）调用 cleanAllApiCache，属于
独立账号通知链；注册与其他账号清理路径仍待核对。

_serializationFromRawData（0x116093474）可先执行 preProcessRawData，再用 JSON parser。
解析失败包装 BFCApiParseErrorDomain；随后可调用 customResponseAfterRequest。除非
ignoreCodeNonZero，顶层 code 非零走 BFCApiNonZeroErrorDomain，读取 message 或 error
中的 message，并按 disableDefaultErrorMessage 决定兜底文案。_ormResponse
（0x116093fe4）随后按 modelDescriptions 映射，处理 keyPath 与 isOptional。
_queryRemoteEnd（0x116093a00）将成功/失败回调交给 responseQueue 或立即回调，并提供
httpHeaderHandler。没有从这些局部方法推断全局自动重试。
requestAsync0x1160921a0先检查started（self+0x3a），首次置true后调用_query(false)，
已经started则直接返回。responseQueue0x11609782c优先取custom asyncRequestResponseQueue，
nil时返回__dispatch_main_q（0x11609786c/0x116097870）。异步成功路径0x116093d8c取队列，
0x116093de0排block0x116093fa4；失败路径0x116093eb4取队列，0x116093f24排
block0x116093f50。两个queued block在实际调用completion/error时未见cancel/account
二次门禁，不能仅凭取消旧请求认定已入队业务回调被撤销。
Request.cancel0x1160920a4在锁内检查cancelled（+0x39），首次置true并调用其operation.cancel。
init0x116091ff0创建operation保存+8，delegate=self；Operation.cancel0x11609c16c先
super.cancel，再cancelTask0x11609c1a0，分别取消并清理BFCRequestTask、BFCHttpTask及
URLSessionTask，后者先unbindTask。Operation.main0x11609a8c0发现已取消时生成
NSURLErrorDomain/-999并交afterCallback；网络结束0x11609b2f0也检查取消，若原error
不是-999则替换为该错误再回调，因此取消不等于丢弃全部callbacks。
afterwrapper尾部0x1160971b8锁Request，释放operation+8与成员+0x40，再置cancelled=true
（0x1160971e4）和finished=true（0x1160971ec）。正常结束也写cancelled位，不能把
isCancelled单独当用户/账号主动取消证据。manager init0x1160916f8已检查的本体没有
账号observer；外部全局账号取消及gateway对error的加工仍须独立证明。
Operation还有单request的首回执/超时门禁：底层callback0x11609b498/0x11609b88c
在NSCondition锁内读取共享byref Bool+0x18，已true则跳过payload/error写入，只signal；
第一次置true后保存结果。因此不能由queued业务callback无账号检查反推底层任何晚
completion都会再次交付。URLSession分支wait deadline为timeoutInterval+1秒
（0x11609ae94→0x11609aebc），wait后仍未claimed时先置true
（0x11609aee0），再构造NSURLErrorDomain/-1001；后来底层completion可被该Bool屏蔽。
非URLSession分支deadline为timeout+cronetTimeoutPatch（0x11609b120→0x11609b158），
同样先claim（0x11609b17c）；其中taskType raw2才构造-1104，其他已检查分支传nil
domain/code0，不能统称所有transport超时都是-1001。这是同一个request的首回执门禁，
不包含账号代际，也不撤销先前已排main队列的业务block。

### HTTP 候选域名回退

BFCRequest.handleFinish（0x11609eff0）在 IgHttpTask.needDomainGrade 为真且还有
候选时，从 BFCMultiDomainConfig.multiDomainsWithKey 顺序取 host；proceedRequest
只修改 NSURLComponents.host，重建 IgHttpTask 并 start、递增候选 index，暂不交付
completion，耗尽后才完成。最终 error=nil 且选中 host 非空时，setAlterHost:key
将成功 host 保存进程字典，后续初始化可复用。keyWithRequest（0x11609e8fc）要求
net_multi_domain_enable（default=0）开启且原 host 属于已注册 multiDomains.allKeys。
needDomainGrade 经 getter 0x1160a4278 读取底层 C++ response 的状态字节；其赋值
条件尚未还原，不能把任意 HTTP 错误都说成会自动换域名重试，也不能与 ticket
退避或首页 VM 的一次额外尝试合并成一个策略。

### 公共服务端时间辅助请求

BFCServerTimeChecker.realTimeInterval0x115dab1a8固定以syncServer=true进入
realTimeIntervalWithSyncServer0x115dab238，优先返回BFCServerTime.timeInterval的非零值。
若为0，canUseNetwork0x115dab6a4仅检查注入apiOptions/apiRequest/apiModelDescription
三个类非nil，不是reachability检查：允许则走getLocalRealTimeIntervalWithSyncServer，
不允许才回localTimeInterval。helper0x115dab37c比较preferences.boottime与当前
boottime（0x115dab3e8）：exact相等即返回NSDate Unix秒+缓存slinterval，不另要求
boottime>0；不同且syncServer=false返回0。不同且允许同步时，锁class并用RAM flag
0x120dd11d0阻止并发更新，先置true，再创建指向
https://api.bilibili.com/x/report/click/now的options（0x115dab484），timeout=2秒，
映射/data/now为数值，安装completion，调用requestAsync（0x115dab544）。此调用
不等待网络，冷缓存返回值仍是0；不能把名字realTime当同步校时成功。
completion0x115dab5c4要求返回now>0，才保存当前boottime及
slinterval=now-回调当时NSDate Unix秒（0x115dab634/0x115dab678），没有往返时延折半补偿。
无论now是否通过门禁，completion尾0x115dab690都清flag；该请求构造体未设置
errorHandler。注册的BFCApiRequest通用完成路径在incoming NSError、ORM error或
remote model为nil时走失败分支（0x116093ac8–0x116093ad0），errorHandler为nil
便退出（0x116093d0c/0x116093d18），不调用成功completion。因此该失败路径不会
执行这里的清flag。全__text针对0x120dd11d0的ADRP+byte LDR/STR扫描仅核实
0x115dab464读、0x115dab470置true和0x115dab690置false；不能据此宣称自动重试，
也不把有限指令形式扫描外推为运行时永久卡死或排除动态清理。
boottime helper0x115dab2f4以MIB原始[1,21]、16字节buffer调用sysctl，取首个signed64
转Double，返回-1时用0，未加入buffer后半部分微秒。这里未读取实际系统结果或prefs。

首选BFCServerTime是另一RAM来源：setServerTime0x115daadfc锁class，保存传入date和
当时uptime（0x115daae44/0x115daae54）；time0x115daae90要求date非nil及保存uptime>0，
返回date+(当前uptime-保存uptime)，否则nil。uptime0x115daaf98实际用gettimeofday与
同一sysctl的秒/微秒差，微秒差除1000000（常数0x1182ebd00），失败/boot首字为0时
返回-1，不能仅凭名字称为独立单调时钟。
ConstWrapper的三个类getter（0x104e63454/0x104e63534/0x104e63570）对应type缓存
0x120280d90/0x120280d98/0x120280da0；ApiClientModule.register0x1049be564
分别注册provider witness0x1204972e0/0x1204972c8/0x1204972b0，其+0x10实现
0x1049bdf30/0x1049bdf68/0x1049bdfa0返回BFCApiOptions、BFCApiRequest、
BFCApiModelDescription具体类metadata。false/raw0根服务清单index23
（0x1202727b8）包含该模块。类存在门禁因而有原生注册来源，仍保留动态重绑定边界。
上游有BFCTimestampGateway.canonicalGatewayResponse0x10518ce44：从wrapper.response
（0x10518ce80；stub最终为response）要求NSHTTPURLResponse，再遍历allHeaderFields
原key。将key lowercaseString后比较x-bili-app-ts（0x10518cf3c/0x10518cf50），
用原key objectForKey取值，doubleValue>0时直接dateWithTimeIntervalSince1970
（0x10518cf98）并调用BFCServerTime.setServerTime（0x10518cfb0）。这里未除1000，
未检查HTTP状态或error，也未对已匹配key提前break；返回仍为原wrapper
（0x10518d024）。其canInitWithRequest0x10518ce34恒true，canonicalGatewayRequest
0x10518ce3c原request返回。注册来源已闭合：NetworkTimestamp模块在false服务清单
index213（0x120273398），register0x100094758以BFCApiGatewayInterceptor_pXp
注册w5=1多绑定（0x10009485c），provider witness0x12027c568的+0x10→0x100094624
经classref0x11f7b5c70返回BFCTimestampGateway类metadata。ApiClient的
moduleInitialize/main任务priority997（184任务清单index14/0x120273c30），exec
0x1049be324→0x1049be96c解析注入类数组，逐项转ObjC类并BFCApiGateway.registerClass
（0x1049bea30）。Timestamp.setup0x10518ce30仅RET，并非该注册的实际来源。

原生controller对每request执行canInit，再alloc/add gateway
（0x116099578/0x116099584/0x1160995a4），响应遍历同controller的gateways
（0x11609984c→0x1160998b4），没有在这一遍历加status/error门禁。
所用registry.registerClass0x11609916c→appendClass0x11609919c锁内仅addObject
（0x1160991dc），未在此去重或排序；removeClass另锁内removeObject。
request先copy全局registry数组（0x1160994fc）再实例化保存，所以后来registry变化
不直接替换已选controller响应实例。重复注册可重复append，不能从服务清单index
直接推全局interceptor顺序。Request afterwrapper
0x116095de4重新读取ktorEnable（0x116095e5c），true跳过native canonical response，
false才调用controller.canonical（0x116095e74），发生在rawDataHandler之前。
请求canonical也独立重读ktorEnable；不能外推Ktor/Moss同样校时或把两次flag读取
视为不可变快照。
时钟preferences也有具体存储来源：BFCServerTimePreferences的superclass为
BFCPreferences（class metadata0x120230b58）；init0x115dab0b4先super.init，另以
configName创建NSUserDefaults suite并保存_defaults（0x115dab118/0x115dab128），
再registerDefaults(defaultConfig)。configName0x115dab180固定为
BFCLaunchTimePreferences，不能按类名猜成另一个suite；shared0x115dab058为once
实例。通用层另有_userDefaults：BFCPreferences.userDefaults0x1167d4ccc在nil时
同样用self.configName创建suite（0x1167d4cfc/0x1167d4d14），不是把子类_defaults
ivar名称当成动态属性的直接读取指令。前述boottime/slinterval走通用动态属性层；
这里未见MID命名空间
或两值事务性提交，也没有读取实际存值。其他suite清理/同步成功及动态writer仍待核对。
该响应头与辅助请求均独立于播放器heartbeat的start_ts回执。

## Ktor 桥接与公共参数

`KtorClientObjc.request:priority:method:signType:bodyData:completionHandler:`
（0x10502edb0）桥接到 Swift 构造函数 0x10503031c，创建 HttpClientOpt，传入 method、
signType、bodyWithData、priority 和完成回调，metricsType 固定为 0，再 request。
另一构造变体（0x1050304f8）传入 signType=3；不能据此概括所有业务请求。

NetParamImp 的 SessionId/GuestId 为服务 getter 的桥接，缺值回空字符串；
getDisableRcmd（0x1000b3e08）读取 disablePersonalizedRcmd 设置，getFiltered
（0x1000b3eb8）读取 inReview。这些入口证明设置会进入公共参数来源，尚未证明所有
Ktor 请求最终都带它们。Moss 的常量 wrapper 另提供 accessToken、guestID、xTrackID、
deviceToken、网络代码、restriction、gaia 与回退配置入口，待逐个追到编码器。

BFCHttpSignModule 的原生 HttpSign listener（0x1000b2860）通过 0x1000b5484 组装
Buvid=BFCBuvid.buvid、Session_ID=注入 BFCDeviceTraceService.sessionId、x-bili-trace-id=
同服务.getXTraceId，再逐项 setHttpHeader。dd.http_sign_buvid 配置影响赋值顺序：
flag 为真先注入，再检查 requestSignType==3 并返回；flag 为假时，只有
requestSignType!=3 才后注入。因此 signType=3 并不在所有配置下都省略这些头。
listener 在 Ktor 引擎中的安装范围仍待验证；BFCDeviceTraceService 的实际注册实现
仍需核对；DeviceServiceImp 的 Objective-C protocol list（0x11d88cdf8）确实同时
声明 BFCDeviceTraceService/BFCDeviceService，证明它可作为这两个协议的实现，
但声明本身不证明此次注入对象就是它。

### Ktor 实际请求桥接与普通拦截器门控

运输选择有两个独立配置。BFCHttpModule的client provider（0x10009be10）读
dd.http_client_opt，默认false：true选HttpClientOpt，false选旧BFCHttpClient。
前者task使用0x10503376c的新构造；旧client.task用0x1000a9b90的旧task。
旧task.request（0x1000a9f48）另读dd_http_client_use_ktor，默认false；true且attrs
没有bfc_http_disable_ktor才把requestType设2。其application interceptor分发
0x1000aae78先检查type2并跳过旧client的遍历/排序/witness调用，所以不能声称原生
HttpSign随旧task切换而自动进入Ktor。
运输入口0x10009fb10在type2构造KtorRequest（0x1000a4100）；它也在signType=3
写禁公共参数attrs，Bridge0x1000a205c把attrs传入KntrKtorRequest，再接下面的
request$1消费。这两条桥共享Kotlin消费，但client替换与旧task改运输不是同一开关。

BFCHttpTask（0x10503376c）经 KtorRequestBridge（0x105030f8c）读取 URLRequest 的
method/headers/body，body 转 Kotlin ByteArray，构造 KntrKtorRequest 并调用
requestAsyncReq（0x105031540）。Kotlin export 0x10bf1763c 进入 request$1
coroutine 0x105d5e158，经 factory create 到内部 client；配置 closure
0x105d5c788 先安装 ContentNegotiation，再逐个安装 provider 产出的非 nil plugins。
provider 收集点为 0x105346404。Root 注册 infra.ktor.client/factory
（0x10b94752c/0x10b94783c），factory 的 collection provider 位于 root+0x2f8，
SwitchingProvider id38→0x10b93d490，明确只组入 CommonParamsPlugin 与 DummyPlugin。
CommonParams 的 id39→0x10b93d2d0 再取 root+0x2e0 的 GInterceptor collection；
id58→0x10b93c814 构造18成员集合，其中 root+0x1b8 getter 0x10b92111c 取
provideTicketRequest provider，id62→0x10b93d068→0x10aad0bb0。由此已闭合
ticket hook→CommonParamsPlugin→Root Ktor factory 的静态安装，原生 HttpSign adapter
与每项 listener 的实际安装仍需分别证明。

CommonParamsPlugin 的 provider（0x10a9abca4）收集 GInterceptor，按 order 升序、
同 order 时 name 降序排序，再创建实际 Ktor plugin（0x10a9ac394，名称
CommonParamsPlugin；邻近net.interceptor字面量不单独证明注册标识）。第三 hook 0x10a9af618 读 attributes 的 `Enable GInterceptor`，
缺失退 false；链首 NetPublicParam hook 将该布尔封装为 GInterceptorEnable typed tag
（0x10a9b1ab8/0x10a9b1ad8）。普通 wrapper 0x105d559a0 只有 tag=true 才调用底层
GInterceptor；false/nil 则 chain.proceed，公共参数特殊 hook 与最终 transport
仍在链中。因此 plugin 已安装不等于每次请求都运行全部普通拦截器。

新版 BFCHttpTask.signType:（0x105034bc0）在值为 3 时向 task attrs 写
`bfc_http_disable_common_params`=`1`；非 3 分支未见删除旧 key。桥接保留 attrs，
request$1 在 0x105d5ebc8 读 key，仅字符串等于 `1` 才设置 Ktor attribute
`Enable common params`=false。CommonParamsPlugin predicate（0x10a9ac5ac）
对该 attribute 缺值默认 true；false 跳过公共参数生成。Enable GInterceptor
随后仍单独读取并传播，因此 signType=3 不能直接等同于禁用 ticker 或全部 headers；
同一 task 改回非 3 也不能凭 setter 断言此前禁用属性已撤销。

具体业务来源是Moss HTTP fallback的BFCMossHTTPWrapper.initWithRequest:completionHandler:
0x115e070e8：取得BFCMossConst.httpClient（0x115e0729c/0x115e072a0），以构造的request
调用task:（0x115e072b4），保存返回task到wrapper+0x18（0x115e072c8），再读取同一task
并调用signType:3（0x115e072f0/0x115e072f4/0x115e072f8）。若选择新版BFCHttp，接上述
setter；若为legacy KtorRequest，接其type3比较及同key写入
（0x1000a43b4/0x1000a440c/0x1000a4428）。这是receiver已证明的fallback入口，不概括
全部Moss传输。BFCMossConst.httpClient 0x115e0680c经0x104fe4d24/0x104fe4d9c解析Inject，
本处不推实际运行时client实例。Enable GInterceptor=true及bfc_http_disable_ktor的业务
writer仍未闭合；有界直接引用/IMP调用扫描不覆盖间接属性或动态key写入。

provideTicketRequest（0x10aad1ab8）以 GTicket provider 构造 RequestResponseHook，
request/response closures 分别为 0x10aad280c/0x10aad29d4，名称实际为 `ticker`，
并实现 GInterceptor，进入上述18成员集合的注册关系已闭合。每个业务请求将
Enable GInterceptor 置 true 的上游来源及原生 HttpSign adapter 仍需核对；当前找到的
该 attribute 直接引用主要是读取与 key 初始化，不能将未找到写入当作永不启用。
因此不能宣称全部 HTTP 请求都带 ticket。

### Ktor 公共参数签名与编码

CommonParams另外读取`Enable sign`（global 0x120c5e400，predicate 0x10a9ac8ec），
缺值默认true；0x10a9aca6c在0x10a9acdb4检查它。false跳过ts/签名尾段，
前段公共参数处理并不因此全部关闭；与Enable common params/GInterceptor分别记录。
true时仅缺失ts才添加，dd.sign_ts_use_milliseconds默认false用秒；true用
seconds*1000+nanoseconds/1000000，已有ts保留。appkey/mobi_app在
0x10a9ad744/0x10a9ad7a0是读取以选择摘要后缀，不能据此声称无条件覆盖appkey。

实际串生成按Map.Entry.key排序（comparator 0x10a9b38b8），多value先以逗号合并，
key/value均经0x105d0b070(false)编码，再各项key=value、以&连接并追加选择的后缀。
编码允许ASCII字母/数字/-._~原样，其他byte用%和大写两位hex；false分支空格
为%20，字面+为%2B、星号为%2A、~保留。MD5消费链0x107705570→provider算法
对象0x11b6edbf0→digest→Kotlin HexFormat.Default；uppercase=0选择小写hex。
结果在0x10a9ad9fc直接写sign。这里未读取或输出实际appkey/secret值，亦不是
native HttpSign adapter已安装到Ktor的证明。

摘要helper的特定异常捕获范围返回空串（0x107705820），范围外重抛；caller
仍写sign，未见非空校验，不能概括为所有签名错误均吞掉。合成参数离线算术检查
覆盖空值、多value及上述编码边界，只验证公式，不表示执行了包或服务端验收。
与授权[社区签名镜像](https://janson20.github.io/bilibili-api-collect-mirror/docs/misc/sign/APP.html)
相比，排序/连接/MD5框架可作索引，但其部分form编码示例的空格+及Swift示例
只编码value的边界不同；不能替代本Ktor严格编码证据。

签名transform先snapshot entries，清ParametersBuilder底层map，再按原key排序逐项
append（0x10a9acfc0/0x10a9ad00c）；不是只排序旁路摘要字符串。该范围没有按sign
名字删除原entry，旧sign若上游未清理会保留，不能声称所有入口都排除旧sign。
摘要string→UTF8（0x1077056d8→0x10bfc627c）处理surrogate pair为4byte，
无效surrogate替U+FFFD，再供digest；不是对UTF16内存直接MD5。

body处理0x10a9ae754仅POST：FormDataContent直接读Parameters、transform后重建；
application/x-www-form-urlencoded且body为ByteArray时，先转String、按&拆分，再按=
limit2，key保留、仅value decode，然后builder.set。同key会覆盖，不能等同原生
Parameters多value保留。application/json的String分支包装为TextContent保留body，
没有这段解析JSON字段加入签名的证据。classId3e1为String，12f为ByteArray。

URLquery控制0x10a9af074读取COMMON_PARAMS_TO_QUERY：-1删除控制key后返回，
1强制transform；其他值GET进入、非GET+JSON返回、其他进入。transform前删除该
控制key，再读EnableSign并调签名；这是已证明移除的控制字段，不是移除旧sign。
仍受plugin注册及总开关约束，不能把这个局部函数写成全部请求必走。

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
写authorization，未见空String检查；具体account实现与引擎注册范围仍待确认。
CommonHeader另有flattened helper0x10aa41b88将binary Base64到普通map，与typed
Grpc map不同；需继续transport消费证明，不能把二者当同一header转换路径。

原生callOptions helper0x115e070e4→0x115e06c20复制缓存Metadata，每次此helper
调用重新读BFCMossConst.accessToken（nil空），调用fresh Device/Network builder，
把三个GPB.data放入x-bili-metadata-bin/device-bin/network-bin。restriction/fawkes
可选；extraHeader先合入，随后非空device.buvid覆盖buvid，非空accessKey写
`authorization: identify_v1 <accessKey>`，非空trace覆盖x-bili-trace-id。
基础options once0x115e07054：timeout/keepaliveInterval/keepaliveTimeout均20，
transportType/compressionAlgorithm原始enum均2，未推枚举名。
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
reserved header/大小写处理另未穷尽，不推广至StandaloneGrpcEngine或KMoss。
RPCCall.start0x115e15550执行GRPCCall2.start→receiveNextMessages(1)→writeData→finish。
raw响应handler0x115e09d74回传并设terminal标志；close0x115e09fc8对流控或特定
business metadata（bili-status-code/grpc-status-details-bin及配置门控）也设terminal。
无错误却无raw可合成code29；追踪后仅terminal=false走一次backUpRPC。
这证明降级分支，不证明unary递归指数重试。
native初始回执0x115e09bcc将metadata合入共享byref字典，close0x115e09fc8再把
trailing metadata后合入（0x115e0a5a4），随后canonicalGatewayResponse
（0x115e0a5e4）；相同精确键由trailing覆盖initial，未证明大小写归一化。
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
caller仍待核对，不能把direct selectorstub只有singleton caller当唯一创建路径。
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
build业务consumer仍待另证，不据DI静态绑定宣称所有stream都已运行。
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
是否重用/另有reset仍未证明，不推广成所有stream的生命周期结论。
已确认center自身的重建路径并非重用finished channel：teardown0x1149ea4c8
stream.stop0x1149ea544→channel.finish，随后center.stream=nil、setupflag=false。
下次setup创建新Stream0x1149ea4a0→新Channel0x1149eb958，重建backoff与监听。
center原metadata/frameBuilder/reporter仍保留。Reporter.initWithMetadata
0x1149efcc4不创建UUID；实际Channel._connect0x1149ecaf8每次生成UUIDString并
依次写connId/Reporter.sessionID，再写Auth frame同connId
（0x1149ecb7c–0x1149ecc0c）。若call不存在，call.start0x1149ecb68先于UUID
写入；独立global START与连接没有队列依赖，故不能保证START观察到新的session。
尚未运行调度验证，也不能把center复用直接等同session保持不变。
独立MossStreaming启动任务也已定位：service array的index200/slot0x1202732c8、
runnable array的index115/slot0x1202742a0登记MossStreamingModule。entry
0x100155c2c→0x100155cd0，moduleInitialize、main、priority450；任务检查
moss_stream_enable（presetHitValue=1，0x100155d8c），命中才sharedCenter.setup
（0x100155db4/0x100155dcc），未命中仍继续metadata缓存。此任务与NativeMoss
gateway module分开。已检查的原生Center/Stream/Channel已命名方法和构造/启停
body未见application前后台通知addObserver；finish的removeObserver不能证明曾登记。
Kotlin epoch PlatformMossStream（TypeInfo0x11bb3e600）另有setup/teardown桥
0x10aaa7320→0x10aaa7408、0x10aaa74e8→0x10aaa75d0，但只有函数表间接引用，
业务调用与前后台listener尚未闭合，不把桥存在写成自动前后台断连。
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
之后_maybeConnect仍检查上述状态。旧/新call回调身份隔离尚未证。

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

## 公共 HTTP 网关流控

公共 JSON 响应的 hook 与错误顺序另已闭合：_serializationFromRawData:error:
（0x116093474）解析 JSON/SKVObject 后，若有 customResponseAfterRequest，先同步
调用它（0x116093744），返回值替换解析对象（0x116093764），随后才读
ignoreCodeNonZero/code；未忽略且 code 非0，生成 BFCApiNonZeroErrorDomain NSError
并返回 nil。network completion（0x116092c3c）调用该 serialization 后才到
_queryRemoteEnd（0x116093a00），正常对象再 ORM，错误交 errorHandler：immediately
分支同步调用，其他分支 dispatch 到 responseQueue。transport error、nil raw 和
JSON 解析失败跳过此 custom hook。因此评论 code12015 hook 保存 needCaptcha/URL
先于 VM.parseErr 发信号，有公共层顺序支持，不能把两者当独立竞速。

`BFCFlowControlGateway.canInitWithRequest`（0x1145508a4）返回真。请求拦截
（0x1145508ac）询问 isControlWithURL；命中时生成 status=429 的 HTTP 响应和
domain=`com.bilibili.bfc.flowcontrol`、code=429 的 NSError，将其包装进 gateway 响应。
这条分支是本地阻断，不足以证明服务器刚刚返回了 429；实际 gateway 注册/执行顺序
仍需核对。

响应拦截（0x114550a88）的 isFlowControl（0x114550eb0）只识别 429 和 503。
提取 x-bili-retry-after 的辅助函数（0x114550488）遍历 allHeaderFields 的 key，用
isEqualToString 与该小写字面值比较，值取 intValue；没在此看到大小写归一化或标准
Retry-After 日期解析。缺值路径回 0，后续仍交给配置约束。响应 body 若可解析为 JSON，
取 message 作为错误文案，否则有资源文案兜底；保存 error.userInfo 供后续本地阻断复用。
非流控 HTTP 状态会调用 disableControl。网络错误/非 HTTP 响应的分支和 HTTP/Moss
差异仍需完整核对。

URL 规范化辅助函数（0x11454fe9c）通过 NSURLComponents 取 host 和 path，path 非空
时拼成 host+path；查询参数不在该键内，并检查 disableList。enableControl
（0x114550004）记当前 Unix 秒为 lastVisitTime，controlTime 为
`min(max(retryAfter, minRetryAfter), maxRetryAfter)`。isControlWithURL
（0x11454fb60）在当前时间不晚于 lastVisitTime+controlTime 时认为受控；另有
localPeriods 的 begin/end 和 localList 分支。缓存清理、列表匹配与时间边界还需进一步
验证，不应由这一局部链推断限制跨进程持久化。

FlowControlConst.config（0x1145506dc）由 BFCNetworkFlowControlConstWrapper 的
isNetFlowControlEabled、minRetryAfter/maxRetryAfter、localPeriods/localList 构造；
disableList 是 wrapper 返回字符串按 `|` 分隔。这些 getter 的配置来源、默认值、更新
时机未全部解码。wrapper（0x10495c480–0x10495cb10）已确认如下入口：实验键
net_flow_control_enabled 的 presetHitValue=1；远程整数
net.flow_control_min_retry_after 默认 3、net.flow_control_max_retry_after 默认 15；
flowcontrol.block.api.time 与 flowcontrol.block.api 分别取数组用于 localPeriods/localList。
这些 wrapper 有 Swift once/缓存入口，不能假设每次请求都会重新读取远程配置。
重试等待使用 Unix 秒差，因此上述 3/15 的单位是秒；最终运行值仍可能被覆盖。

Moss 网关请求（0x114550ec4）复用 isControlWithURL，命中时生成 code=1346 的错误和
BFCMossGatewayResponse；响应（0x114551030）依据 error.moss_maybeFlowControl 和
moss_isFlowControl 分支，读取相同 x-bili-retry-after 并更新/取消限制。两个 NSError
扩展方法进一步确认：moss_maybeFlowControl（0x115e0fe74）等于
moss_isResourceExhausted 或 moss_isUnavailable；moss_isFlowControl（0x115e0feac）
检查 domain=`io.grpc` 且 code=1346。这一自定义错误码不能原样当作 gRPC status；
ResourceExhausted（0x115e0fdb4）检查 io.grpc/code=8，Unavailable（0x115e0fe14）
检查 io.grpc/code=14；该入口只用 domain/code 分类。
这套网关与 Neuron.handleFlowControl 是独立机制，状态码、作用域和调度不可互换。

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
HTTP注册范围及其他gateway次序不从此Moss注册链外推。
原生HTTP canonicalRequest0x1051f2500无条件setValue，nil ticket改空字符串，
没有已有值保留、empty或host门禁。原生Moss0x1051f26b4先合入旧extraHTTPHeader，
再以exact dictionary key覆盖ticket，nil也改空；它不同于Kotlin Moss的nonempty门禁。
HTTP响应入口0x1051f25d4要求NSHTTPURLResponse类型，再从allHeaderFields字典取键；
原生Moss从responseHeader字典取键。这里未证明Foundation/transport对响应header
大小写的归一化方式，不能据exact subscript断言wire大小写变体一定失败。

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
（0x1000991b0），startup0x10009937c只设置setup-ready +20=1（0x1000993f4）；
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
共享一份本地缓存，外部登录/登出是否另行reset仍未定位，不宣称实机跨账号复用已验证。

TicketMoss（0x1000982b0）按 `min(failureCount×baseDelay,maxDelay)` 安排下一次请求，
值小于 1 时立即安排且无 jitter，否则再加 [0,maxJitter] 的浮点均匀样本。乘法与失败
计数递增带溢出 trap。回调 0x100098ac8 在 response 非 nil 时清失败计数，否则加一。
RPC wrapper0x100098a1c→捕获回调0x100098dd8→0x1000987d0先转发到同一queue，
queued thunk0x100098e14再调用0x100098ac8，先写failureCount（0x100098af4），
后调internal callback（0x100098af8）保存/清inProgress。response非nil的计数重置
不同时要求独立error为nil；这里只证明串行响应leg中的顺序。
尚未发现当前失败回调自动递归重发，因此不能将其描述为一次刷新会自动重试四次。
配置默认 baseDelay=1、maxDelay=15、maxJitter=1 秒，get_max_tries=4 的消费方未定位。
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
用于 update。已证明协议桥接，具体引擎何时调用、请求覆盖范围和拦截顺序仍待追踪，
不能据此认定全部 Ktor 请求都携带 ticket。
Kotlin coroutine 0x10aad2234 的父接口实际为 kntr.base.moss.MossInterceptor，
只在 ticket 非 null 且非空时加 x-bili-ticket；响应 x-ticket-status 精确等于 `1`
时调用 update。另一 provideTicketRequest$1 的请求/响应回调（0x10aad280c/
0x10aad29d4）同样调用 GTicket，前者未见相同的空值检查，后者也只识别 `1`。
这两个回调的插件安装方仍待定位，不能因 Kotlin 桥名就归类为所有 HTTP 请求。

离线假数据验证通过：Python 与 CommonCrypto HMAC-SHA256 2,000 组对照、24 个
context 排列的拼接结果及 100 个退避边界。只验证原语和已推导规则，尚无同版本
官方执行或服务端验收证据。

## 设备登记与访客生命周期

设备指纹加密和五项 guest 资料结构见 [身份研究](../NOTSURE.md#ios-分析样本中的生成与加密规则)。
登记请求 BFCDeviceUpdateBuvidRequest.requestUpdateBuvidWithData:completion:
（0x115fd7ed0）使用 Ktor，method=1/signType=0/priority=0，body 是 key/content JSON，
Content-Type=text/plain。该构造段没有根据 CCCrypt 返回状态或 JSON error 直接中止。
回调 0x115fd82d0 要求 error=nil、body 非 nil、HTTP 200、顶层与 data 是 NSDictionary，
再取非 nil data.bili_deviceId；未检查业务 code==0，也未在该回调检验编号类型/长度。

serverBUVID getter（0x115fd7224）在 expiry<now 时先设置 now+120，再异步申请并
立即返回旧值；相等时不申请。Token 回调 0x115fd7398 另要求 length>0，将内存 expiry
设为请求发起时刻+86400。值相同也延期，但不重复替换/保存；值变化时保存 Preferences
及 Keychain。失败不清旧值且保留 120 秒窗口。loadServerBUVID（0x115fd706c）读取
Preferences→Keychain 时会 validateBUVID，因此本次回调的接受条件与重启后加载条件
并不相同；expiry 在上述路径没有持久化，也未发现主动定时登记。

Guest.load（0x11605a5a0）只在 guestId 为 0 或 -2 时登记，其余值直接返回。
请求回调 0x11605a658 在 transport error 或非零 API code 时返回错误及 -2、不保存；
code=0 后取 data.guest_id.longLongValue，只拒绝 0/-2，不能把此层验证写成“必须正数”。
成功经 barrier_sync 写 Guest 对象与 GuestPreferences。该函数未发现定期过期或
并发请求合并标志；其他层是否另有调度仍需核对。

AccountModuleModuleInitialize 的 Swift setup（0x104c6daf4）分别注册两个主队列通知：
DidBecomeActive→0x104c6cbf0→loadGuestId，WillEnterForeground→0x104c6cb88
仅在 hasLogined 时 validateToken/updateCurrentUser。setup 还直接调用一次 loadGuestId。
因此登记失败可在后续 active 通知再次触发，不是每次前台都无条件重新登记。
active completion（0x104c6cc80）忽略 error 参数，trackTech `infra.ids`，扩展字段是
guest_id（含失败哨兵 -2）与 total_memory（NSProcessInfo.physicalMemory），policy=2、
rate=100。实验 account.guestid_can_add_in_netcore（preset=1）传入 guest header 控制器；
网关消费已如下闭合，全局启动顺序仍待串联，preset 不证明实际开启。

GuestId header有两条不同链。HttpSign helper0x1000b5484要求guest控制依赖与
account依赖非nil、guestIdCanAddToNetCoreHeader=true，随后每次读guestId写GuestId；
无本段登录、正数或非空检查。dd.http_sign_buvid=true时该helper先于signType判断，
false时仅signType!=3调用（0x1000b2b50/0x1000b2dd4），并非所有引擎必走。

Account provider0x104c6efc0按同flag选AccountApiGatewayInterceptor或Nothing的
class metadata；缓存0x1204a6d28/30是类，不是实例。Gripper0x104c6f268注册协议class
provider，ApiClientModule0x1049be96c解析同协议class数组、逐项registerClass；
append0x11609919c同步追加无去重。flag变化是否重选已注册class未证明。
原生BFCApiRequest每次build0x1160953dc新建GatewayController，canonical
0x1160994a4逐class alloc/init。Account interceptor.init0x1160548a4当时snapshot
guestId，canonical0x116054980用setValue写GuestId，无本段login/host门控；已有response
会停止后续gateway。ktorRequestEnable=true明确跳过该canonical调用
（0x116095ab8→0x116095bb8），故不能把Account gateway头推广至Ktor或全部Moss。
关闭flag/跳过链也不证明移除调用方原有GuestId。

GuestPreferences继承BFCPreferences，configName为NSStringFromClass，固定suite
BFCAccountGuestPreferences，动态Int64 key guestId；没有该偏好层MID分区切换或
账号observer。singleton仅firstRunTime==0时写首次时间，不覆盖guestId。
saveGuestIdWithData的直接BL/B扫描仅成功load链命中，setter无自身编号合法性检查；
未发现具体login/logout清guest caller。动态调用或外部整suite清除仍未排除，不能写成
退出一定保留/从不重置。Moss模型的setGuestId是另一NSString字段，不是此偏好setter。

DevicePreferences、AccountDevicePreferences、GuestPreferences 在各自 singleton 初始化
且 firstRunTime==0 时才写 Int64(trunc(DateUnix×1000))。它们使用独立的 UserDefaults
suite，不能假设三个首次时间相同，亦不能用它们替代 Neuron.fts。
logout 的主队列 block（0x11604c3b8）清 SSO/Cookie/用户与快速登录资料并发出
账号通知；该函数体没有直接清 guest 或 BUVID。通知分派 0x11605e2d8 将原始值
1/2/4/8 分别映射到 accountDidLogin/Logout/Update/Change。DeviceConfigNotify 的
logout（0x100126f08→0x100126cc0）清的是 universal config 缓存并重新同步，不能
将其当作 guest 重置。其他通知观察者仍需核对，尚不能断言全局退出流程保留所有
设备资料；同版本运行未验证。

### 短信 UI 的 login_session_id

UI 入口 helper 0x104cf8968 重建全局扩展参数字典，将跟踪 BUVID 与十进制毫秒时间
直接拼接，再取 UTF-8 MD5 的 **32 位大写 hex**。毫秒 helper 0x104cf86e8 使用
DateUnix×1000→FRINTA（最近整数、半值远离零）→有边界检查的 Int64 转换，不是
向零截断。已定位四个 UI 入口调用点；其他登录 UI 是否共用此 helper 尚未确认。

SmsAlert2Controller 的发送分支（0x104d9ece0）和重发分支（0x104d9f800）读取同一
全局字典、合入 BFCAccountSMSContext.extendedParams，再 sendSMSWithContext。
提交分支 0x104da0400 将同一字典与 scene=popup/from_pv 合并到 LoginContext，
经 0x104da0588 loginWithContext 发起登录。因此这条链是在 UI 入口换新，发送、
重发与提交复用；不是每个 HTTP 请求重新生成。Golang SMS send（0x116048be0）
与 login/sms（0x116048e54）最后合入 extendedFields，证明该字段进入表单，
而非仅供统计。SMSSendResponse.isNew 控制 RegisterRequest/LoginSMSRequest 分支；
注册分支的表单与后续换 token 见下节。FastAlertController.loginRegCheck
（0x104d5b174）同样把此全局字典合入 fastContext.extendedParams 后 loginWithContext；
该证据尚未闭合 fastContext 的实际 HTTP 表单。OAuth2 入口的对应字典引用仅已证
用于 telemetry，不能据此扩展到 OAuth 请求。

离线假 BUVID 验证通过 12 个 post-Date 毫秒 Double 的 x.49/x.5/x.51 边界（含负数）、
大写 MD5 格式与同一舍入毫秒复用关系。验证的是 FRINTA 消费值；不声称任意秒数经
Foundation Date 内部 epoch 转换后都精确保留小数半值，也没有执行官方包或验证服务端。

### 账号校验、刷新、注册与退出

validateTokenRealWithSSOModel（0x1160521b8）拒绝 nil SSO（61000），否则将旧 accessToken
交给 info 请求。回调 0x1160524d4 的 transport/API 错误返回 needRefresh=false；业务
61000 只有被校验模型 mid 与当前账号 mid 相同时才调用退出。code=0 仅检验返回
mid/expires_in 非零，未在此层拒绝负值或比较新旧 mid；保留旧 token/cookie/sso，更新
expiresIn 并 updateSSOModel(type=0)。validateAndRefresh（0x116051cc0）根据服务端
refresh 布尔值决定刷新，这条链未证明本地提前若干秒的过期阈值。

refresh（0x116052f78）先请求服务器时间，回调忽略时间请求 error，返回 0 时把 sts
改为 -1，否则沿用返回整数。Golang builder（0x116047d98）向
x/passport-login/oauth2/refresh_token 发送旧 refresh_token/access_key、
sts、local_id/buvid（跟踪 BUVID）、bili_local_id（localBUVID）、device_id（currentBUVID）、
device_name/device_platform；此 builder 没有 device_meta 或 extendedFields 合并。
响应 0x1160533dc 的 transport/非零业务码失败不保存；code=0 解码 SSO 后没有额外
模型有效性检查。新 mid 与当前 mid 相同才刷新当前 cookies；cookie 回调
0x116053734 忽略其 error，更新 SSO(type=1)，以捕获的**旧 SSO**与 sts 发 confirm，
随后返回成功，不等待 confirm。其他 mid 仅更新对应已保存账号，不刷新当前 cookies。
confirm（0x116051660/0x1160488d4）向 x/passport-login/confirm/refresh 发旧 cookie
DedeUserID/SESSDATA 对应 mid/session、旧 token、revoke_api=REFRESH_CONFIRM_REVOKE、
sts 及上述设备字段；缺失字符串退空。

updateSSOModel（0x116050f90）只在 mid 匹配时更新当前 SSO，并在已保存列表中查找
同 mid 替换，未在该 updater 插入未知账号。saveSSOModel（0x11605072c）同步更新
shared.ssoModel、保存 accessToken 副本及 JSON；StorageHelper（0x116056c4c）写
Preferences 并明确调用 BFCAccountKntrStorage save/remove，adapter 初始化
KntrAccountStorage；不能仅凭旧接口名称称其为物理 Keychain，Kotlin saveAccountAccount 经 0x10be565f0→0x105d619ac，传逻辑键 account 给
0x1053e2a2c；构造器 0x1053e0058 明确创建 suite=bili_account 的 NSUserDefaults，
setter 0x1053e2c10 调用 setObject:forKey:。保存前 String 的 virtual +0x90
已定位到 0x105211918，仅将原 String 写至返回槽，因此 supplied SSO JSON 在这条
链没有应用层加密，直接保存到 suite=bili_account/key=account；这不描述 OS 磁盘加密，
也不保证与另一份 Preferences 写入原子一致。未读取实际存值。

读取与写入的路由不同：StorageHelper.getSSO（0x116056d30）在 shared 缓存的
isKntrAccountCacheEnable=false 时只读 native Preferences；true 时先读 KntrStorage，
返回字符串 length>0 才使用，否则回退 native Preferences。shared 初始化
0x116056274 把 getUseKntrAccountCacheInfo 的结果缓存；其 enable 算法
0x116057d6c 为 `(kmm || rollback) && nativeMarker`，nativeMarker 是
suite=bili_account_migrate/key=accountMigrate 等于字符串 `1`。kmm/rollback
两个 DD 开关缺值均为 false，不能由默认值推断本次运行实际开关。
这里缓存的 migrated 采用 nativeMarker；另一个 convenience 方法
isUseKntrAccountCache（0x116057d10）采用 KntrStorage.isMigrated，不能混写。
decisionAccountInfoStorage（0x116056320）使用缓存 snapshot：rollback 且 migrated
则取回五项写到 native Preferences，取不到模型清 native cache，并 finishRollback；
否则 kmm 且未 migrated 时把 native 五项迁入 KntrStorage。迁移的启动调用顺序及
marker 写入时机尚未闭合，不能把双写描述为始终从同一后端读。

迁移标记写入也与完整提交不同：startMigrateData（0x10be56e9c）在已经 migrated
时直接成功；data=nil 时写 marker=`1` 并成功。有模型时首项 SSO 字符串 length>0
才保存 account，随后立即写 marker=`1`（0x10be5727c），再条件保存其余四项；
首项为空则失败且不写 marker。finishRollback（0x10be54d10）写 marker=`0`。
AccountStorageModuleModuleInitialize（0x104c6d760）调用 decision；与 AccountModule
在模块 scheduler 中的全局启动顺序仍未闭合，不把 marker 当成五项存储的原子提交。

后台 validateTokenWithAutoRefresh（0x11604d444）经 validateSerialQueue 运行，当前
SSO 非 nil 才对保存账号列表逐项建 operation，然后 group wait 等待全部完成；当前
账号并非另行追加。autoRefresh=false 只校验，true 才校验后按返回标志刷新。
Operation.start 在开始前检查取消；cancel 仅调用 superclass，没有在此处取消已开始的
网络请求或阻止后续保存。shared 初始化 0x11604ade0 明确设置
validateQueue.maxConcurrentOperationCount=1；批次串行与单 operation 并发不等于请求去重。

新用户 SMS register（0x116049374）表单为 cid/tel/code/captcha_key、四种设备编号
local_id/buvid/bili_local_id/device_id、device_name/platform、device_tourist_id；存在
旧 accessToken 时加 from_access_key。extendedFields 最后覆盖这些字段，随后 RSA
回调 0x116049794 再赋 device_meta/dt，因此它们又能覆盖扩展参数。注册响应 code=0
解码 RegisterResponse，SMS 服务用其中 code 继续 exchange，未直接将注册响应保存为
SSO。exchange（0x116047fdc）向 x/passport-login/oauth2/access_token 仅发送
code/grant_type/local_id/bili_local_id/device_id/buvid 六项；空 grantType 在上层退为
authorization_code，注册扩展参数不会自动沿用至这个 builder。

LoginSMSRequest 回调（0x11604131c）先检查 response 是否存在；存在时解析 SMSResponse，
status 只接受 NSNumber，url/message 只接受 NSString。code=0 且 status!=0 时直接
completion(nil,SMSResponse)，没有保存 SSO；status=0 才解码并交 delegate 处理账号。
缺失/错误类型 status 保留对象默认 0，这层没有 required-status 校验。Session UI 回调（0x1149661d0）只有 status=0 才 setLoginSucceed=10；任何
非空 response.url 都会设置 nextBlock。next（0x114966778）在 status=2 时带 message
调用 showSecurity，其他值不带 message；showSecurity 有 message 先 alert，否则直接
构造 BFCAccountWebViewController，设置 URL/session/closeHandler，经注入 handler 或
root navigation push。非零 status 无 URL 没有这条 next，不能称为已登录或已展示挑战。
exchange 与普通 SMS 的 handleSSOModel
（0x11604fcf0）若先 fetchUserModel，fetch error 会阻止保存；cookie refresh callback
则忽略错误并保存 SSO/user/登录日期与账号列表，按此前账号数/切换标志发通知。

退出入口 0x11604b964 可被 logoutIntercept 阻止（错误 -2）。通过后 revoke_type 在
saveCurrentAccount=false/true 时分别为 1/2；只有 deleteAllAccount 且已保存账号数>1
才发 batch/revoke，否则 revoke。单撤销 builder（0x1160481d0）12 项为
mid/access_key/refresh_token/session/revoke_api/revoke_type/local_id/bili_local_id/
device_id/buvid/device_name/device_platform；批量另加 need_delete_account_info（保存
账号 revokes JSON）、is_self_revoke、device_tourist_id 共 15 项。请求回调
0x11604c3b0/3b4 都为空：发起网络后立即 dispatch 本地 cleanup，再
completion(true,nil)，不等待 transport/API 结果、不因失败回滚。本地成功不能证明
服务端撤销成功；已定位的 AccountNotiInfoModule.login/update 为 RET，logout 清全部 API cache，
change 清 cache 并更新 Bugly userID；DeviceConfigNotify.update 为 RET。其他观察者
与存储转换尚有缺口。同版本运行与服务器验收未执行。

## 会话来源与旧活动上报

公共请求的 BFCBuildConfig.sessionID（0x1161e56b0）在无旧静态值时转向
BFCBuildConfigWrapper.sessionID（0x10506a5d4），后者调用注入服务的 sessionId。
DeviceServiceImp.sessionId（0x1049573a4）→BFCDevice.getSessionId（0x115fd3960）
→KntrSessionIdProvider.shared.sessionId。BFCDevice.getSessionId 本身有 dispatch_once
与静态强引用缓存；初始化 block 0x115fd3990 只读取一次 Kotlin provider，后续请求
复用该值，不能描述成每次请求动态刷新。

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
`48-bitCount`。该时钟的系统 tick 单位及并发状态行为尚未验证，不能当作 Unix 时间
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
这是 8.89 包内的生成和进程复用证据，尚未用同版本运行样本验证，不能覆盖 9.13。

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
执行。因此EnableGInterceptor=true的请求阶段确实先ticker后app；未穷尽其它成员或
transport后续覆盖，不能称最终线上header绝无再写入。
ticker请求closure0x10aad280c先调用GTicket getter（可排异步refresh），再经同一
request setter写x-bili-ticket。即使write-once=true且已有该header而最终保留旧值，
getter也已执行；nil/false则替换。此HTTP closure没有空String门禁，feature关闭时
getter空串也可到setter；Moss closure0x10aad2234另有nonempty检查，不能混成同一规则。
ticker响应closure0x10aad29d4经response.headers及Headers.get取得单个String；
HeadersImpl0x105cfda9c→0x105cfe2b8返回values的首项，空列表回nil。
只有该返回值exact=="1"才调用更新，未检查HTTP status、body业务code或expiry，
也未回放原业务请求。wire重复header如何归一化仍未证明，不能写成扫描任意一个"1"。
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
这里没有ack或去重判断，下游是否去重未证。foreground无旧记录或旧记录无end时跳过
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
生命周期触发名与任务执行体，尚未证明全局dispatcher去重、重放或当前运行flag，
也不能从静态入口推断系统可靠提供每种退出回调。
engine自身已读派发链也没有一次性消费门禁：0x100027210从RAM map按trigger取任务，
循环交runner0x100026bcc，未删除map或写task已执行flag。Phone任务thread="main"；
runner已在main立即调用0x1000240bc，否则main.async。helper依次执行pre hooks，
忽略返回值后无条件调用task.execution witness+0x28，再执行post hooks。registry的
once只缓存发现结果，不能当执行一次。条件稳定的重复生命周期dispatch在这里可
重复达到setup；这只是静态可达，实际回调频次和上游抑制仍未实测。


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
墙钟和单调时钟。跨重启恢复时的单调时间有效性仍未验证。
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

## 旧 V2 文本日志通道

这是包内明确存在的一套实现；还没有证明它在本样本启动时的实际注册，更没有证明它就是
9.13 抓包中的 Protobuf 业务埋点通道。BFCTracker 支持多个 trackPlatforms 和
separatePlatforms，存在并行上报机制的入口。

BFCReportHandlerV2.trackCustomEvent（0x1141c7f70）要求参数键能以 integerValue 转换并
往返成同样的字符串，随后按数值比较器排序，将对应值转为有序数组。isRealTime 选择
ReportRealV2 或 ReportDelayV2。ReportItemV2 初始化记录日期字符串和 Unix 毫秒。
encodedParas（0x1141c83c8）拒绝空 taskId/空 params，值 description 中的 `|` 替换为空格，
再 URL 编码；最终各列用 `|` 连接。公共部分分 staticPublicPars（进程 once）与
publicPars（每次计算），分别含设备/首次跟踪/渠道信息及账号、版本、网络状态等；
完整列顺序与 BUVID 拼接部分仍需逐列复现。

ReportBaseV2 的请求/保存队列并发数均为 1；对象自己还有串行 dispatch queue。
入队先计算并保存编码字符串，再异步分配到 sendingReports 或 cachedReports。
trySendReport 先 saveReport，再判断 isSending、网络可达及非空发送数组。
默认一批上限 30 条，单条分流门槛 1024 个 NSString 字符，保存有效期 604800 秒，
默认延迟值 600 秒。DelayV2 大于等于门槛的项改入 LargeV2；Large/Real 批量上限为 1，
Real 延迟值为 0。Delay 的 reportDelayTime 有 requestInjector 时也返回 0，因此默认
600 不能直接当作运行时发送间隔。Delay/Large 的发送判断包含 Wi-Fi 条件。

sendReport（0x1141c6a04）去掉每项前 14 字符的保存日期前缀，以控制字符格式串组合为
文本（每条后加字节 0x03）、UTF-8 编码并 gzip。POST 到 data.bilibili.com/log/mobile?ios，设置 Content-Encoding
为 gzip、Content-Length 为压缩后 NSData 字节数；bili_debug_mode 为真选 HTTP，否则 HTTPS。随后可经 requestInjector 修改请求，
用 sendAsynchronousRequest 在串行 requestQueue 完成。注入器具体头尚待核对，不能作为完整可复用封包。

完成回调（0x1141c6e2c）按 HTTP 状态处理，没有解析响应业务正文；状态 200 进入成功，
无响应或其他状态进入失败。成功异步清空 sendingReports，再从 cachedReports 补下一批、
安排下一次检查；失败把发送项追加回 cachedReports 后重新取一批，没有在此失败块中直接
安排重发定时器。是否由新事件、生命周期或其他调度再次触发，仍待追调用方。

保存时将 sendingReports 与 cachedReports 拼接为数组，串行原子写文件；加载时读取数组，
用前 14 字符 yyyyMMddHHmmss 解析日期并过滤过期项，再分配发送和缓存数组。路径位于
Documents/reportv2 下的 delayv2、largev2、realv2。它保存的是已编码事件字符串；
不能推断跨账号缓存会重新绑定身份，字段编码阶段与登录变更需要进一步核对。

## 首页请求的业务组装

`BBHD2PhonePegasusMainApi.baseUrl`（0x10df57790）返回 app.bilibili.com/x/v2/feed/index。
其 getApiOptions 继承 BBHD2PegasusBaseApi 的 BFCApiOptions 构造，再打开
 enableDeviceNameParam。init 只显式初始化 helper，没有在此方法给业务整数属性设非零默认值；
必须继续看调用者赋值。

params（0x10df56ed4）明确分离如下来源和条件：

| 字段 | 来源/条件 |
| --- | --- |
| pull | pullType=0 → `0`，=1 → `1`，其他值不加 |
| idx / column | 对象整数属性转字符串 |
| network | BFCReachability.currentStatus 映射，wifi/mobile/空值分支 |
| login_event | 对象属性非零才加 |
| open_event | helper getter 的返回值，nil 兜底空字符串 |
| banner_hash | helper 属性，nil 兜底空字符串 |
| ad_extra | BBAdReport.requestAdExtra，nil 兜底空字符串 |
| splash_id | 对象属性，nil 兜底空字符串 |
| 首次额外参数 | 将 helper.firstRequestInfo 的键值逐项合入 |
| flush / recsys_mode / autoplay_card | 对象整数属性转字符串 |
| fnval/fnver/qn/fourk/force_host/player_extra_content | getPlayerParams 合并，底层 BBPlayerPreloadUrlParamsHelper.preloadUrlParams |
| interest | 已有合并值优先；未出现时用对象属性或空字符串 |
| interest_v2 | 对象属性非 nil 才加 |
| device_type | isFirstCall 为真才加 `1` |
| https_url_req | httpsPlayurlEnabled 设置映射为 `1`/`0` |
| guidance | needShowGuidance 映射为 `1`/`0` |
| screen_window_type | BBHD2ScreenSwitchHelper.windowType 转字符串 |

这不是最终请求全字段表：之后仍有公共参数、签名与拦截器。尤其兴趣、广告、播放设置、
窗口状态均有真实来源，不应由抓包中一次值写成固定常量。上游赋值和响应处理见下文；
曝光、点击与播放事件的关系仍需继续追踪。

extraHTTPHeader（0x10df56d34）只在 BFCAppPreferences.isNewInstall 且
PegasusConfig.isFeedReqSuccessOnce 为假时加 DeviceInfo。明文是 idfa 单键 JSON，nil IDFA
退为空字符串，通过 BBHD2PegasusEncrypt.AES128Encrypt:key: 再 Base64。加密函数
（0x10df06d08）调用 CCCrypt 的 op=0、algorithm=0、options=3、keyLength=16、IV=nil，
即 AES-128-ECB + PKCS#7，key 来自调用处的包内常量。本文不记录该常量，也不能据此
推断现版新安装登记仍相同。

helper 单例初始化（0x10df579ec）设 isColdLaunch、isFirstRefresh、willFisrtLoad 为真，
读取 Documents/chooseInterest.plist 到 firstRequestInfo，随后删除该文件。
open_event（0x10df57b60）每次先清空保存值：isFirstRefresh 为真时按 isColdLaunch 返回
cold/hot，然后无论分支都置 isFirstRefresh 为假。**读取 getter 本身消费状态**，因此不能
先为日志/诊断读取，再期待实际请求仍得到首次值。

willResignActive 将 isColdLaunch 置假、isFirstRefresh 置真；didEnterBackground 保存当前
时间；willEnterForeground 检查该时间的 timeIntervalSinceNow，当为负且绝对值严格大于
1800 秒时清空 banner_hash。尚未追到这些方法的所有注册/调用时机，不能把方法名当作已
验证的系统通知响应。返回前台是否触发请求是另一项待查链。

Swift首页另有独立banner_hash链，不能套用上述HDhelper时间条件：BannerV8Model
customMapper0x101ae5a88把属性banner_hash映射原响应键hash（0x101ae6024），
卡片JSON转换0x101afaab8→model→VM；layout准备0x101af5a24读model.banner_hash并
存MainApiMarker+20/+28，新API首建读取，nil为空。不是收到任意响应立即写请求。
Swift注册前台通知到0x101a35b18，对timeIntervalSinceNow取fabs，abs严格>1800秒
才清banner（0x101a35ca8/0x101a35cb4），没有负值先决，等于不清；另有账号observer
清理，类型mask含义待核对。两种实现及各自缓存时机需保留区别。

Swift首页caid又是另一条首次上传链：Marker0x101a3515c检查
hasUploadedCaidSinceInstallation=false才global queue调用BBDeviceInfo.mergeCAIDParams
（0x101a35e0c），再main queue转JSON字符串保存Marker+48/+50（0x101a35ff0）；
MainApi0x101a33a34非nil才写caid，覆盖已有同键。key22无error事件0x101a35058在
flag尚false时先持久置true，再清该Optional；flag已true时不清。异步writer未复查flag，
存在成功事件先于写回的静态竞态可能，不能断言严格恰一次。不是HD firstRequestInfo/
chooseInterest文件；未读取或输出设备实际CAID，JSON失败/具体合并字段仍待核对。

响应 modelDescriptions（0x10df575e4）包括 /data/items（数组、必需）、/data/config
（非数组、可选）、/data/config/auto_refresh_time（非数组、可选）。完整卡片映射、配置
应用、本地缓存/过滤/重排仍未证明。

### 首页 VM 的首次请求、重试与响应状态

`BBHD2PhonePegasusMainVM.init`（0x10df58690）按 hasLogin 初始化 login_event：
登录为 2、未登录为 1。账号 action observer 仅对原始 action 值 1/2 更新同一映射；
账号通知分派 0x11605e2d8 已确认 1/2 对应 Login/Logout；该观察者只处理这两类。

loadData（0x10df58a10）在 helper.willFisrtLoad 为真时，以 isNewInstall 设置
isFirstCall；设置 pullType=1、splash_id、列布局、login_event、播放自动播放设置及
FeedStateManager.followState。idx 来自首卡或本地保存的 Pegasus feed index，具体分支
仍需完整复核。VM 的 flush=-555 是内部已派发标志，该值进入下一次 loadData 时先改为 0。
选择兴趣的两个 VM 属性赋给请求对象后清空；getApiOptions 的结果保存为 loadDataOptions。

apiProcess（0x10df58dfc）用已保存 options 创建 BFCApiRequest 并异步发送，随后将
VM.flush 置 -555、helper.willFisrtLoad 置假。错误回调（0x10df59ab8）在 retry 标志为真时
将 retry 改假，读取**原VM当前loadDataOptions属性**（0x10df59d44）再调用
apiProcess（0x10df59d64）。该options不是此请求block强捕获的快照；只有属性未被后续
load改写时才是同一options。这条retry不调用参数builder，不能据此说再次读取消费型
open_event getter，也不能排除后续load替换属性。这是业务层一次额外尝试，不能外推为所有请求
或传输引擎都遵循相同重试策略。

成功回调（0x10df59104）应用服务器配置中的 follow_mode、auto_refresh_time、列布局、
自动播放等属性，置 isFeedReqSuccessOnce；清空 helper.firstRequestInfo，并把
VM.login_event 置 0。converted array非空后取**第一张**卡
（0x10df5969c、objectAtIndexedSubscript index0@0x10df596a8/0x10df596ac），
且isKindOf CardBaseModel才读idx（0x10df596fc），经 DataManager.savePegasusFeedIndex
（0x10df59714）
保存到配置属性（setter入口0x10df2b6ec，写入0x10df2b718）；配置固定suite与默认值见后段，动态Int64 IMP见后段，落盘时序仍待追踪。下一次 DeviceInfo
条件因此会受首次成功状态影响，而不是简单按进程首次请求判断。

loadMore（0x10df5a4c0）有正在加载和审核模式分支；另建 MainApi，设置 pullType=0、
flush=8，取末卡 idx、当前布局/自动播放/推荐模式后发送。首次刷新与加载更多的 idx 来源
不同。buildObjects（0x10df5a28c）存在新旧数组合并、刷新卡处理、数量上限及有条件的布局prefix裁剪；
这些是本地展示处理的证据，尚不足以证明客户端执行了个性化算法重排。

### 推荐点击、展示与可见时长的业务触发

旧包同时包含 UIKit HD 与 Swift 实现，以下按实际函数体区分；运行时选择与 9.13
一致性未验证。MainV2VC.didSelect（0x10df3e318）对 bangumi_rcmd 卡路由后调用
HomeData.reportCardClick；其他卡走 superclass（0x10dee967c）。super 在实际 cell
支持 jumpDetail 时调用该方法，另行处理广告 click；只有 cell 的 **精确类名**属于
LargeCoverV1Cell、SmallCoverV1Cell、SmallCoverV9Cell、SmallCoverV5Cell 白名单
（0x10df18c40）才调 HomeData 点击报告，不是按继承关系匹配全部卡。

HomeData 通用报告器（0x10df30fd8）要求 ReportProtocol，actionType=1/2 分别建
Click/ExposureEvent，事件名由 from_spmid_v2/neuronEvent/submodule 与 click/show
拼接。22 个默认扩展键为 event/style/param/title/goto/sub_goto/sub_param/page_from/
page_id/from_type/state/up_id/rid/tid/type/track_id/converge_type/extra_info/card_type/
card_rel_id/card_material_id/position。字符串 nil 退空，args 的数值转十进制；
track_id 优先**非nil** report_args.track_id（空串也保留），否则 report_track_id；position 取
report_flush_idx。extraDic 最后覆盖默认值。track 后还发旧链 001365，并清
report_click_position；两个通道不能作为同一事件重发统计。
逐寄存器补证：click wrapper0x10df30338给neuronEvent=main-card、submodule nil
（字符串0）、action1/privateEvent=card_click，所以ID是
`[from_spmid_v2].main-card.0.click`（0x10df31728–0x10df31784）；from_spmid_v2
本体没有显式nil fallback。style只在page_from严格字符串1时取
FormatManager.getPegasusStyle（0x10df3109c/0x10df310b8）；page_from是
Config.reportPageFromForPage(model.page_from.integerValue)，type固定traffic。
param/title/goto/sub_goto/sub_param/from_type来自对应report_* getter；state来自
caller，up_id/rid/tid来自report_args十进制，converge_type及extra_info也来自args，
后者yy_modelToJSONString；card_type/rel_id来自report_card_*，material_id非零转
decimal否则空。22字段base在0x10df315a4，extra覆盖0x10df316b8。
随后001365用numeric String key0..13另组14字段：privateEvent/style/report_param/
report_title/report_goto/report_sub_goto/report_sub_param/mapped page_from/page_id/
report_from_type/privateState/args.up_id/rid/tid（0x10df317d8–0x10df31a2c），
重新读getter且不合extraDic，不能把22字段直接复制给旧链。

BaseEvent.initWithId（0x1161eebb4）设 logId=001538、pageType=1，Click/Exposure
没有在这里另行覆盖初始化。track（0x1161eea60）转 Neuron policy=0，trackInstantly
（0x1161eeab0）转 policy=1。HD real show（0x10df3083c）单独构造
`tm.recommend.feed-card.0.show` 并 trackInstantly，九个默认键为 card_type/card_goto/
goto/param/track_id/position/card_rel_id/card_material_id/is_background，extraDic
仍覆盖默认值；不能把它与上述通用 show 的全部字段合为一个固定表。
real-show track_id则要求args.track_id.length>0才使用，否则report_track_id
（0x10df308c4–0x10df30910）；card_goto取card_goto、goto取gotoType、param取
report_param，card_material_id仍非零decimal/否则空。getAppstate0x10df31b44每次
读UIApplication.applicationState，raw0/1/2分别映射String2/3/1，其他空；
is_background不是Bool，也不能据字段名写固定后台值。

HD MainV2 exposureRatio=visible_area/100，isRepeatedExposure=false；manager.enabled
受 isShow 与 splashStyle==0 控制。BBListExposureManager（0x103eb3744）检查
enabled/rootView、可选 throttleInterval 与可见 cell/subview。单项检查 0x103eb523c
要求非空 identifier、view 存在且未 hidden、alpha>0、有 superview、非空 bounds 与
intersection；可见比例为交集宽/自身宽×交集高/自身高。比例 >= item/delegate 阈值
才 exposedIn:item 并加入 identifier pool。HD identifier（0x10df31ba4）包含
时间戳/track_id/flush_idx/Appstate；普通离开不会按重复曝光机制清池，全部重置
调用方仍在追踪。

Swift RealExposure 的 durationDelegate 见证表 0x11b173da8 与 weak setter
0x103eb7410→0x103eb74f4 已核对。ExposureV2.Manager raw policy=3 时，visible
比例 >= startRatio 才建 Context 并保存 Date.now；已有 Context 在比例 < endRatio
时移出池并结算（等于阈值仍保留）。结算 0x103eb9998 要求 elapsed>=minimum，
通过才调用同一见证表的 duration 回调。hidden/空 view 或交集也有结算路径；
其他 policy 与完整池生命周期仍未闭合。
后台 observer 的枚举值已用 field descriptor 和 Dispatcher 双重核对：
raw36=willResignActive、raw33=didEnterBackground、raw37=willTerminate。
RealExposure 的 raw36 handler（0x101b60ab0）受 durationRematchEndWithNonActive
控制才结算；raw33（0x101b60b18）与 raw37（0x101b60b70）都调用结算
0x101b60e7c→Manager 0x103eb9294。raw3 项先从池移除，再走同一 minimum
检查及 duration 回调，不能把进入后台视为仅暂停检查而保留未结算时长。

RealExposure 从 MainConfig 读取 exposure_duration_start_ratio/end_ratio，缺失或类型
错误各默认 0.8；exposure_duration_min_ms 读 Int 后除以 1000，默认 0 秒。普通
展示比例 visible_area/100 默认 0，与时长比例不同。Memex 的
pegasus.pgs_expose_check_interval 默认 Float=0，不能写成固定 0.3 秒检查周期；
durationRematchEndWithNonActive 默认 true，消费路径见上述 raw36 handler。
回调 0x101b6cf80 复制扩展字典，将两端 DateUnix×1000 有边界检查地向零截断为
Int64 十进制 card_start_time/card_end_time，再发
`tm.recommend.feed-card.duration.show` / policy=1，未单独添加 duration 秒字段。

首页离开也有具体duration结算入口：VC.viewDidAppear0x101a37618与
viewWillDisappear0x101a37628在super之后publish raw2/3；lazy创建的同一MainVM
在0x101a36540注册listeners，raw2/3分别经0x101a5cb98/0x101a5cbb4写
isShowing=true/false（0x101a4a114）。_checkReallyShow0x101a4a274用
isShowing && BFCSplashManager.splashStyle==0，只有真实显示状态改变才publish
raw7/8（viewRealAppear/viewRealDisappear）。RealExposure监听raw8的callback
0x101b60644先做可选manager check，随后无条件调用0x101b60e7c结算并移除duration
contexts，仍受前述最小时长门槛。因而已有duration在实际离开时结束，返回之后再建
context，不是暂停后累计；show identifier全局去重池是否重置另待核对。
raw7则走0x101b60494的条件检查，不能把显示事件本身等同于已产生曝光记录。
apply completion0x101a44530另发布feedDataChanged raw24，包含账号empty Diff应用。
RealExposure订阅该事件，经0x101b6070c排main.async再进入0x101b60900；它忽略
Diff payload，读取执行时的共享provider/config，要求config非nil、witness+0x38
BOOL为true、manager非nil，才调用Manager.check。这不是直接全池reset。
具体check0x103eb78e4要求enabled==1且rootView存在；已有上次check时还要求
elapsed超过delegate throttle，无delegate则elapsed>0。未通过时保留旧状态。
成功收集当时可见items后，静态比较配置0x12044e608唯一元素为2，选择
0x103ebaddc计算old items减current items；按identifier匹配，不按位置/账号/模型身份。
departed项policy原值3（或5经delegate解析为3），identifier非nil且池中有context时，
0x103eba88c移除该context，再由0x103eb9998执行前述最小时长门槛及duration回调。
最后更新_lastCheckExposeItems。因而账号清空后成功check若实际可见items为空，
可以结算旧duration，即使header refresh被loading挡住；仍保留UI/config/节流/上下文
存在与多实例归属的门禁，不把每次raw24当作无条件结算或运行时空可见集证明。

Swift 普通 show（0x101b6b8c8）的 position 在配置字节 0x12106a631 为 true 且
模型 OptionalInt 非 nil 时直接取模型值（含 0）；其他情况调用 MainEventOperator.flushIndex，
此事件 builder 没有额外 +1。VC 初始化 0x101a366a8 实际绑定该 closure；实现
0x101a4e914 按卡片 uniqueID 字符串查 VM.cards，读取匹配模型 OptionalInt，
不符合协议/未找到/nil 都退 -1，不是 UICollectionView 行号。另一个只返回字典的
builder 0x101b6d3ac 在 fallback 后 +1，模型直接分支不加。具体 SmallCoverV2Cell 的
ItemsContainerProtocol witness 0x11b16f5b0→0x101ac6554 已闭合 duration 分支：
它调用专用同规则 builder 0x101a7b6a0，将字典赋给 receiver，按 raw policy=3
构造 ExposureV2.Item（0x101ac6884），最终进入上述时长结算。不能把所有时长
position 归为无条件 +1。SmallCoverV2ViewModel 的 OptionalInt getter/setter
（0x1035a2400/0x1035a2540）使用 associated object 键
BBListPegasusSettings_flushIndex，不应仅称为直接解码的服务器字段。
DataFactory 0x101a3e5a4 遍历 CardData 输入数组，在取得 report model 前递增下标，
再通过 witness+0x40 写下标+1；没有 report model 的条目仍占输入编号。异步 setup 0x101a3e1dc
在编号前调用 0x101a4340c compactMap，逐字典转 CardData，转换返回 nil 的项先丢弃，
成功数组才进入 0x101a3e5a4。转换 0x101a3feec 拒绝空字典、缺失/非 String card_type、
未识别 card_type 哨兵 raw0x29、缺少 provider，以及需要但不存在的 operator。
解析函数 0x1018bb498 在返回前将 unsigned index<41 的值保留，否则返回41；
reflection 共41合法 cases，unknown 为0，因此41不是一个合法的 unsupported case。
MainApi completion（0x101a340c0）从 /data/items cast 到 [[String:Any]]，缺失/类型
不符退空；0x101a5bcc0→0x101a55f8c 将数组交原 callback。正常 loadmore
0x101a52dbc 的 callback 0x101a5c1e4→0x101a55250 将同数组交 DataFactory
0x101a42b64；同步分支用同一个 compactMap，再从1编号，异步分支进入上述
0x101a3e1dc。故这条网络 loadmore 的编号按成功 CardData，不保留失败的原始
输入空洞，也不是累计显示行号。refresh callback 0x101a5bc64→0x101a55004→
0x101a5b3b0 已读的 0x101a5b990 分支将同数组交 0x101a40c40，同步分支也先
compactMap 后从1编号。正常refresh在error-tag=false时更新VM.config
（0x101a5b554），调用interestChoose/rawitems helper0x101a538d8；helper=true走单独
兴趣选择render而不进入0x101a53fd0，helper=false且额外CardData为空才走普通编号链。
网络refresh wrapper0x101a55004显式传空额外数组，不能将兴趣选择分支外推为同一render。

兴趣响应有独立的共享状态链：MainApi从/data/interest_choose取dictionary
（0x101a342a4/0x101a342ec），类型不符退nil。VM helper0x101a538d8要求非nil、
非空，依次调用InterestManager的!hasShown、processJson/cards、fake-card门禁
（metadata0x11fde2d98的+0x188/+0x1e8/+0x190）。这不是另外的isRequestEnabled
新安装/preferences门禁。process0x103c74660在model解析前已经将source置raw1
（0x103c7468c）并替换共享tmpPegasusCards（0x103c746b0），因此拒绝模型也可能
改变临时卡片。支持style为17、22、23、24、26–38，且!hasShown时才prepare；
prepare0x103c74cf4遇已有model立即返回，process仍可返回true。已有token直接
显示，否则借BBSerialGroup.addEvent排队。fake-card门禁0x103c73dc4对35–38返回
false，32返回!isLowActivityScene，其他样式或nil model返回true；经理处理/显示
与是否替换首页卡片是不同条件。
另一个启动消费者MainVM setup0x101a49e68调用metadata+0x180的
isRequestEnabled0x103c73c7c：!hasShown且（isNewInstall为true，或
InterestPreferences.disableActionOpenHomepage=true且hasSubmitedInterest=false）。
BFCAppPreferences.shared为nil时走非new-install分支，不直接返回true。
true时调用manager的metadata+0x1d8方法0x103c74308
（0x101a49eb8/0x101a49ec4），注册BBPegasusLaunchTransactionProtocol item并保存
返回token（0x103c743c0）；false改走showOverseasAgeGateIfNeeded0x101a49ee8。
这闭合的是launch transaction的本地启动门禁，不能直接当作推荐HTTP字段或把它
替换为上述响应消费的!hasShown门禁；具体请求及后续状态见下一段。
launch item的scene0x103c763b4为raw2，process0x103c766fc→0x103c763bc置source=0，
把空String字典交统一interest builder0x103c6e0d0（0x103c764b4）。该builder请求
https://app.bilibili.com/x/v2/feed/index/interest，requestMethod raw0（公共builder默认GET）
（0x103c6e13c/0x103c6e17c），与首页feed响应中附带interest_choose是不同入口。
自有参数顺序为非空manager CAID→caid；cny_info JSON String；合并调用方字典；
最后条件性dp_status。调用方字典同键覆盖caid/cny_info，但生成的dp_status后写覆盖
同键；本launch caller给空字典。没有读取或保存实际CAID。
cny_info始终由两键对象生成：cny_active=TabDisplayManager.isCnyTabDefaultSelected
的Bool转Int，ab_test_vars=cnyAbTestVars字典（nil→空）；helper0x103c6f200用
NSJSONSerialization options0及UTF8，失败返回空String，不请求sortedKeys。
这也闭合上文T10 click数组/字典转String的JSON格式，不保证字典键稳定序列。
builder每次先递增进程counter0x120442df8，再取BFCLauncherContext.hasAction；
hasAction=true且count1→dp_status="1"，count2→"2"，其他省略（0x103c6e4d4–528）。
该值捕获到completion，不是账号epoch，也不代表HTTP已经成功发出。
modelDescription三条optional/nonarray路径为/data/interest_choose、
/data/config/close_small_window、/data/config/interest_popup_logic_exp；安装
completion0x103c6e868/error0x103c6e8e8后requestAsync0x103c6e900，未在此body设置
timeout/auth/cache/responseQueue，也未把request存manager ivar，公共默认仍适用。
回执0x103c6d610先消费config：close_small_window Int1→自动小窗helper
0x104b1ae2c，2→自动PiP0x104b1ae04，3两者；对应helper先检查手动操作标记，
已手动则return，未手动才setIsAuto*Enabled(false)（0x104b1ae40–0x104b1ae98）。
interest_popup_logic_exp Int先写共享manager。随后captured dp_status=="1"直接
success(nil)并discard兴趣内容（0x103c6d7bc–0x103c6d838），不parse/prepare，
不能把此主动discard归因为防旧账号回执。其他dp_status才解析InterestModel；
成功先写固定suite的disableActionOpenHomepage，再用model非nil的
interest_popup_logic_exp覆盖config实验值，最后success(model)
（0x103c6d930–0x103c6d9b4）。解析缺失/失败也是success(nil)，不走errorhandler。
launch success0x103c74508还检查showOverseasAgeGateIfNeeded/model/style/hasShown；
拒绝或HTTP失败走finisher0x103c764f4：发Unavailable通知（message="error"），
取manager当前transactionToken.done（0x103c766a0）后清token（0x103c766d4）。
这里没有request-owned token一致性或账号epoch门禁。具体token.done
0x113c3c018转operator.finishItem0x113c3c2d8移除item，再start下一个item
（0x113c3c338）；accepted prepare本体未见对应done/clear，外围完成仍待核对。
同一builder另有guide入口processWithGuide0x103c7489c：hasGuideShown已true直接
返回，首次先置true（0x103c748c8），后续guide action0x103c74bac带静态
{"action":"1"}、source raw1进入builder（0x103c74c00/0x103c74c74）。
它与launch共享上述counter/参数和config消费，但其error callback0x103c7465c
及success捕获的finisher0x103c74ca0均为bare ret；不能把全部interest请求失败
都写成launch的Unavailable/token.done。物理actionButtonDidTap0x103c7226c
选择actionClosure，common helper0x103c722a4在track/dismiss之前调用closure
（0x103c722ec/0x103c72318）；manager创建guide时将0x103c78cd0存为action
（0x103c74b00），thunk直接转0x103c74bac，因此上述action="1"有UI来源。
close按钮选择独立cancelClosure，不经过该网络action。
cancel closure0x103c78cd8取manager另一个serial token.end（0x103c78cfc）并清
该token（0x103c78d04），不是上述launch transactionToken.done。
prepareIfNeeded0x103c741f8另经background helper0x103c75c60/0x103c75f2c，
调用BBDeviceInfo.mergeCAIDParams(empty)（0x103c76028），再排main closure将
JSON String存manager.caid（0x103c7621c/0x103c76240）；该入口本体不直接请求，
已读链没有launch等待CAID完成的同步屏障。完整manager有界范围
0x103c73950–0x103c76724及token.done/finish/start链中，accepted prepare与dismiss
均未见显式done；外围动态完成仍未知，不能据此宣称事务永不结束。

二次兴趣有独立builder0x103c6e96c，URL为
https://app.bilibili.com/x/v2/feed/second/interest，requestMethod raw0。
参数为可选非空manager.caid；interest_id=model.unique_id的Int64十进制；
interest_result=传入String；interest_type=传入Bool true→half/false→full；
device_type=固定suite BBPhonePegasusConfig中stringForKey
isFeedReqSuccessOnceSinceInstallation的原String，缺值→"0"
（0x103c6ecd8–0x103c6ed9c）。该字段不是硬件型号；此builder不递增index counter，
没有cny_info/dp_status或任意调用方字典合并。optional/nonarray描述路径为
/data/interest_choose及/data/config/close_small_window；requestAsync
0x103c6f0a0未设置自有timeout/cache/auth/responseQueue或manager持有cancel。
回执0x103c6dbdc只解析interest_choose，经YYModel与nested-model归一化
0x103c77974后success(model)，缺失/失败success(nil)。该body没有消费
close_small_window，也没有index parser的disableActionOpenHomepage/popupLogicExp
写入或dp_status discard，不能把两个endpoint的响应策略混为一条。
其中device_type标记默认在LocalPreferences.defaultConfig0x101b8aa78以Bool false
初始化（0x101b8ab10），配置名固定BBPhonePegasusConfig。首页已有nil OptionalError
成功链0x101a34fcc→0x101a35058先读该标记，false才set true（0x101a35108）。
二次兴趣却用NSUserDefaults.stringForKey读取；不能把系统对Bool→String的行为
写成IPA内显式编码，未实际读取此suite。
T37实际caller0x103d86e74要求model非nil且style37；其他style仅本地展开。
_isRequesting=true时返回，否则先置true，再将选中sids commajoin交builder
（0x103d86f3c/0x103d870c8）。
SID helper0x103d858a8保留selectedItems数组顺序：Item.sub_items为空时用Item.id；
非空时按selectedSubItems数组顺序筛weak SubItem.item.id匹配parent id，生成
parentId.SubItemId（0x103d85c64–0x103d860d4），没有匹配项则不回退parent-only id。
之后追加gender/age再commajoin，无id排序/去重。S2 didSelect0x103d96fe4→0x103d968fc
按NSObject equality搜索已选SubItem；新选追加尾部，取消稳定移除，重选移到尾部
（0x103d96a58–0x103d96a8c），不能根据展示网格顺序推断编码顺序。
interest_type Bool来自共享manager.source，
raw1→half，已读raw0→full；不是屏幕尺寸。callback context捕获原model，同时保留
weak查找box与strong原T37View；不能描述成仅弱持有UI。
success/error context在0x103d8701c/0x103d8705c存weakbox与strong原view，原view
retain于0x103d87074/0x103d8708c；completion Block copy后retain业务context
（0x103c6efdc/0x103c6efec）。thunk0x103d9f57c只转发到body，析构
0x103d9f588才release strongview（0x103d9f59c）；parser调用业务callback前未释放
context。因此这条持有链保留原view到callback body，而weak读取不提供账号归属隔离。
物理首屏_confirmButtonDidTap0x103d87d9c直接调用此入口（0x103d87db0），与
S2最终确认0x103d97798→0x103d8a940不同。
成功0x103d87134先安排main now+0.5秒清_isRequesting
（0x103d87258/0x103d87370→0x103d875f4），nil response随后直接返回。
非空items先在原view仍存在时写absoluteModel，再无条件向共享manager写response
（0x103d87418/0x103d874d8–0x103d87508），之后才弱gate原UI更新。
weaknil分支结构上仍写共享model，但strong原view双捕获不能证明请求持有期内会
自然析构；无request/account epoch或current-model比较，实际跨账号交付未验证。
空items构造NSError domain interest.second.api.items.empty、
code -1234，回退捕获的原model并reload/report。network error0x103d87648则立即
清_isRequesting，可转NSError才原model fallback/reload/report。延迟success clear
只弱取原view，没有请求身份门禁，不能写成取消或自有loading token。

T37原始selection物理入口0x103d8dd88→0x103d87dc4：gender/age替换所选index，
同index早退；Item以NSObject equality查已有选择，新选仅在当前数量低于正值
select_num_limit时追加尾部（≤0用Int.max），达到限制只toast；取消稳定移除
（0x103d88050–0x103d8814c）。取消parent后按parent id删除匹配子项，weak parent
nil的子项保留。S1物理selection0x103d92930→0x103d92208沿用相同限制/追加/
稳定移除，但child清理修改弱delegate原T37View的selectedSubItems，原view失效
时跳过child清理（0x103d923e4–0x103d92434）。这些局部变更不直接发HTTP。
S1 confirm0x103d92d60弱delegate有效才交父helper0x103d87740；该helper先筛当前
children，只保留weak parent非nil且与incoming selectedItems中某个NSObject-equal
者，再按原顺序复制incoming父数组（0x103d87788/0x103d877cc）。这个过滤与取消
parent时的id比较/nil保留规则不同，不能统一成一类选择清理。
选中父项sub_items总数为0（包括空父数组）时，直接调用最终Confirmed builder
0x103d8a940、dismiss raw1、立即setHasSubmitedInterest:YES
（0x103d87898/0x103d878c4/0x103d878f4），不创建S2或在此请求second HTTP。
总数>0只保留有sub_items的父项、保持父项顺序，helper0x103d898b0构造S2并传
当前model/父数组/保留children。S2 configure0x103d95958分别存这三项
（0x103d9598c/0x103d959b0/0x103d959e8），未见自动追加默认选中child；不能把
展示子项等同用户已选。configure完整body至0x103d95c48只retain这些输入，未
deep copy或reset曝光flag；随后readiness0x103d95c28，再菜单show helper
0x103d97adc（0x103d95c2c）。后者要求model存在且show_skip_three_point字节
恰1（0x103d97b08/0x103d97b1c/0x103d97b20），发three-point.0.show
（0x103d97ccc）三String style/unique_id/strategy，没有hasShown/_isExposed
门禁；每次eligible configure都安排该事件，不套用子项一次曝光规则。
T37首屏parent Item曝光独立willDisplay0x103d8de8c→0x103d9d094：raw section
0/1是Gender/Age，其他取current model.items；Item._isExposed
（ivar0x120443a70，0x103d9d264/0x103d9d268）为true省事件。false发
interest.0.show（0x103d9d920）六String interest_name/interest_id/pos/style/
unique_id/strategy，没有S1子项字段。pos用current model.items的NSObject equality
search0x103d810d0（0x103d9d74c），first match+1/missing0
（0x103d9d760–0x103d9d768），不是物理index或absoluteModel。track后同Item置true
（0x103d9d940）。Item.init0x103c799e4→0x103c79910置markerfalse
（0x103c799bc），blacklist0x103c797d0静态array0x120442fd8仅_isExposed；
customTransformFrom0x103c79908只返回true，没有reset。动态setter0x103c797c0
仍可写Bool，其他重置未穷尽。T37数据选择→编码顺序与首屏/second/S1/S2提交边界
已配对，具体响应对象是否重用另须逐consumer判断。
T37 S1 parent show也独立willDisplay0x103d9293c→0x103d9e350，取S1.items
物理item对应Item，flag0x120443a70 true时省事件（0x103d9e3d8–0x103d9e3dc）。
false发同六字段interest.0.show（0x103d9e6d8），track后同Item置true
（0x103d9e6f8）；pos取S1.items equality search（0x103d9e50c）first+1/missing0，
不是原页面物理位置。configure0x103d91b18直接retain同model/items
（0x103d91b44/0x103d91b68），完整body至0x103d91dcc只菜单/text/button/reload/
readiness0x103d92e28，未自动选parents/deep copy/reset marker。
second-error fallback0x103d88f60使用captured原model.items，因此首屏已曝光的同Item
可压掉fallback S1 show；换view不等于换对象。成功response的新对象分配仍属parser
边界，不能据此声明全局无dynamic setter/reset。
S2 readiness0x103d97880→mapper0x103d9c69c为每个display parent检查其
sub_items与selectedSubItems是否有NSObject-equal交集
（0x103d9c760/0x103d9c870/0x103d9c8a4/0x103d9c8e0）；任一匹配返回true，
空或穷尽返回false。true数量恰等display parents.count才setEnabled
（0x103d979b8/0x103d979d8），不是min_limit/parent ID门禁；程序态空parents的
0==0也可启用。该检查不修改选择或曝光标记。
S2 child show独立willDisplay0x103d970bc→0x103d9e988：先从current S2
model.items逐parent取sub_items，按原序flatten全部children
（0x103d9ea54–0x103d9ecc4），无sort/dedup/无子项时父ID替代。随后读
same display child._isExposed（0x103d9ede8/0x103d9edec），false才发九String
interest.0.show（0x103d9f258），track后同child=true（0x103d9f284）。
interest_pos为display selected parents数组的first NSObject-equal位置+1/missing0
（0x103d9ef34–0x103d9ef7c）；sub_interest_pos为上述**全model扁平child**数组
的first equal位置+1/missing0（0x103d9f088–0x103d9f0cc），不是组内物理item。
flatten在flag门禁前，重复show被抑制也先执行数组构造；同SubItem跨页/重建保留
marker的结论依赖对象复用，不推广成相同数字ID自动去重。
S2 child click不使用show的扁平位置：实际mutation后reload
（0x103d96ad0）、readiness（0x103d96ad8）再发十String interest.0.click
（0x103d96f10）。parent pos仍为display selected parents的first equal+1/missing0
（0x103d96bdc–0x103d96c20），child pos却在**display parent.sub_items**中找
tapped child（0x103d96adc/0x103d96d20），first equal+1/missing0
（0x103d96d34–0x103d96d64）。因此第二组以后show/click子位置可不同，不能
共用一个位置公式。action select/cancel来自实际append/remove；无曝光flag门禁
或child click weak-parent门禁，九个共同字段外加action_type。

其他style不可套用T37的请求中门禁。T35物理confirm0x103d6c1c4→0x103d6b5b4
只有model.style35走同second builder（0x103d6b7c0），其余本地展开；同source
raw1→half/raw0→full。完整admission body到0x103d6b808未见_isRequesting读写或
owned request cancel，按钮交互层门禁尚未排除，故不宣称实际重复tap必然并发。
成功context0x103d6b740同时存weakbox/strong原view，0x103d6b744存原model；error
context0x103d6b760也强捕获原view/model。因此不是仅弱持有UI，weaknil只作结构
分支记录。成功0x103d6b824 nil response直接返回；非空items先弱gate原view.absoluteModel，
随后即弱view失效也写共享manager.model（0x103d6b8c4/0x103d6b8f4），再弱gate
原UI/reload；没有T37的0.5秒清loading，也未见账号/请求身份比较。
T35 lazy confirm按钮0x103d67ce0→0x103d77b88→0x103d73ad4直接addTarget
_confirmButtonDidTap/ControlEvents raw0x40（0x103d73d5c–0x103d73d74），未见Rx
throttle。已闭合selection-readiness helper0x103d6a87c：非style35要求已选数量
≥1且≥select_num_min_limit；style35要求实际呈现的gender/age section已选index
≥0，缺title/空section作为neutral，最终AND设enabled（0x103d6af00）。已读请求/
回执/error未按in-flight disable；这些只是有界静态按钮链，不排除外部交互限制。
T35空items构造interest.second.api.items.empty/-1234，HTTP error可cast NSError
才同样回退捕获原model、reload并经0x103d6bf50报告
main.interest-select.client.0.show（0x103d6c194），五个String字段style/unique_id/
strategy来自原model、code/msg来自NSError；不是使用非空响应model或提交成功事件。

T18/T19的physical second路径又有不同payload：T19 confirm0x103d24370→
0x103d23ba8调用sids helper0x103d22568时传Bool=true（0x103d23be0/0x103d23be4），
跳过selectedItems reducer和selectedMixedItems，只顺序追加符合title/非空数组/
selectedIndex≥0条件的gender.id、age.id（0x103d225a0–0x103d225b4、
0x103d227e4→0x103d22850），commajoin后交second builder0x103d23d58。
T18 confirm0x103cff000→0x103cfe838独立传true给0x103cfd1f8
（0x103cfe870/0x103cfe874）；同样跳过items/mixedItems，仅追加gender/age，
second builder调用0x103cfe9e8。两个admission body只检查model非nil，未见style/
_isRequesting gate；不据此推断按钮外部交互。这里的interest_result是人口属性
子集，不能统一表述为全部当前选择；同helper的Bool=false其他caller不套此结论。

T33/T34 physical confirm分别0x103d45a84→0x103d44fa0、0x103d58390→
0x103d578ac；model非nil且_isRequesting=false才入，先置busy=true再调second
（0x103d45050/0x103d45198、0x103d5795c/0x103d57aa4）。其sids helper
0x103d443f4/0x103d56d00直接按selectedSubItems顺序生成parentID+"."+childID，
弱parent缺失取parentID=0，再追加符合条件的gender/age。不按selectedItems分组，
没有裸parentID项或排序/去重，区别于T35/T37的父项分组编码。
成功0x103d45204/0x103d57b10在nil/items判断前安排main+0.5秒弱取原view清busy
（0x103d45700/0x103d5800c），nil success也安排清除；error
0x103d45718/0x103d58024则在nil/NSError cast前立即清busy
（0x103d45764/0x103d58070）。非空items对原absoluteModel/UI弱gate，但仍写共享
manager.model（0x103d455d8/0x103d57ee4），没有账号/请求epoch比较。空items
-1234及可cast HTTP error回退捕获原model，报告同五字段client exposure；两者
callback context也同时持weakbox、strong原view与strong原model，不能把weaknil
结构分支解释为请求仅弱持有UI。这里busy解除及模型替换都不代表最终兴趣提交回执。

T33实际child选择入口在S1子view：0x103d4ed6c→0x103d4e554取
items[section].sub_items[item]，NSObject equality查找；未选项追加到
selectedSubItems尾部（0x103d4e708/0x103d4e70c），已选项稳定删除
（0x103d4e748）。正select_num_limit限制整个child数组，<=0取Int.max；重选追加
到末尾。outer didSelect0x103d49c4c→0x103d45aac只改gender/age index。
T34独立S1入口0x103d60a58→0x103d60240，追加0x103d603f4/0x103d603f8、
删除0x103d60434，具有同样选择顺序和全局数量门禁。S1 confirm T33
0x103d4f28c→0x103d4f164、T34 0x103d60f78→0x103d60e50均弱取delegate，
live时原序复制child数组到outer，调各自final builder，再dismiss raw1，立即设置
本地submitted=true（0x103d4f234/0x103d60f20），此body不再发second HTTP。

T33 final builder0x103d46e48另要求current model和absoluteModel同时非nil
（0x103d46e74/0x103d46e84）。缺失时直接返回，而S1 caller仍dismiss并设本地
submitted，故该标记不能证明Confirmed已经发出。通过门禁后Confirmed通知
0x103d48280恰有三个String字段：unique_id取current model，sids复用
0x103d443f4的child点分ID和符合条件的人口属性，interest_pos_ids则取
**完整absoluteModel展示ID列表**，并非已选位置。具体flatten按absoluteModel.items
原序，parent.sub_items非空时加入其全部children，否则加入parent
（0x103d478a4–0x103d47aac）；Item输出自身ID，SubItem输出弱parentID+"."+childID，
弱parent缺失/错型compact掉（0x103d47cec–0x103d47f9c）。该数组commajoin
0x103d480c4→通知字段0x103d48204，不筛选当前选择、不按max_subitems_show_count
截断、不包含人口属性。它与下述click位置列表独立。

随后T33发BFCNeuronClickEvent main.interest-select.submit.0.click
（0x103d48c0c）。base八字段interest_id_list、interest_list、interest_pos_list、
content_cnt、extra_select、style、unique_id、strategy；后三个取current model。
前两个列表分别从selectedSubItems的弱parent ID/name构造（缺失取0/空字符串），
位置列表0x103d51278取弱parent在absoluteModel.items的首次NSObject相等索引+1，
缺失取0；三列表均经Set<String>→array→JSON（0x100066c38/0x103d9cae8/
0x103d6f200），去重且不保证tap/server顺序。content_cnt取去重parent ID数量
（0x103d4873c），不是child数量。extra_select是String:String字典JSON：每个
人口属性section要求title非nil、候选非空、selected index>=0，以实际section title
为key、所选Gender/Age.title为value（nil取空）；age后写，同key覆盖gender
（0x103d482b0–0x103d4851c），并非固定gender/age key或数字ID。
最多再有四个非空child字段：sub_interest_id_list取child ID decimal经Set→JSON
（0x103d48904）；sub_interest_list取child name原序JSON（0x103d48988），不去重；
sub_interest_pos_list用0x103d5155c生成parentPosition.childPosition，分别在
absoluteModel.items与live parent.sub_items取首次NSObject相等索引+1，缺失索引
取0，弱parent缺失compact掉，保留其余选择顺序后JSON（0x103d48a4c）；
sub_content_cnt取原selectedSubItems.count decimal（0x103d48b30），不去重。
这些click字段不能代替通知sids或interest_pos_ids序列。
T34独立final builder0x103d592a8也要求current model/absoluteModel同时存在
（0x103d592d4/0x103d592e4），S1同样不检查返回后设置submitted。其Confirmed
0x103d5a750有四字段：unique_id、sids、全部absoluteModel flatten的
interest_pos_ids，以及额外Bool disable_refresh_after_submit。该Bool来自
**current view.model**（0x103d592f4→0x103d5a5f0→0x103d5a6c4，boxed
0x103d5a6d0/0x103d5a6d4），非absoluteModel/global配置。sids helper
0x103d56d00→commajoin0x103d5a514，完整展示ID flatten
0x103d59d08→commajoin0x103d5a540；click0x103d5b088另行构造位置字段。
这一额外Bool对应下述MainVM typed Bool消费门禁；缺失时的false行为不能推广到T34。

T33 S1 MoreAction0x103d4f2b4先清outer child数组0x103d4f2f4，再呈现Feedback
controller；callback0x103d462cc弱取原view、cast InterestMoreActionItem，raw Bool
true分支0x103d46374要求current model存在，发Skipped通知0x103d465a0，仅
unique_id/current helper sids两String字段。因为child先清，此时sids可仅含符合条件
人口属性；随后dismiss raw2和事件helper0x103d48ce0，没有second HTTP或本地
submitted setter。Bool=false分支0x103d493c0仅发
main.interest-select.continue.0.click，三个current model字段style/unique_id/
strategy（0x103d49590），没有dismiss、通知、submitted setter或请求。
Bool=true后close click0x103d48ce0有current model三字段、is_initiative="1"和
reason="three_point"（0x103d48f68）。另outer S0 more入口0x103d495c4→
0x103d4608c不清child数组；仅上述S1 More先清，所以相同menu回调发Skipped时，
outer入口的sids仍可保留孩子，不能统一写成人口属性子集。
T34独立child click position helper0x103d631b0已核实同一索引规则：weak parent
缺失Optional nil（0x103d633b0），parent/child首次NSObject相等索引+1，缺失
分别取0（0x103d63298/0x103d63308），与Confirmed完整展示ID列表分开。
T34人口属性物理didSelect0x103d5bd48→0x103d583b8要求model非nil，点击当前
index直接返回，不toggle-off；变化才写index、readiness/reload，发
main.interest-select.extra-btn.0.click（0x103d588f8）。八String字段name取所选
Age/Gender.title、interest_id取其ID decimal、title取对应model section title，
nil title/name取空；pos=item index+1，style/unique_id/strategy取current model，
action_type固定select。body未见busy gate或网络请求。
T34 S1 child变化完成后先reload/readiness（0x103d60464/0x103d6046c），再弱取
parent；parent缺失省略事件但不撤销选择（0x103d60480/0x103d60484）。数量上限
拒绝则toast并退出，无该事件。live parent才发
main.interest-select.interest.0.click（0x103d60988），十String：interest_name/id
取weak parent Item，interest_pos取它在当前S1.items首次NSObject相等索引+1
（缺失0），sub_interest_name/id取本次tapped child，sub_interest_pos取物理
IndexPath.item+1；style/unique_id/strategy取捕获S1.model，action_type按追加/
删除为select/cancel（0x103d60404–0x103d60454）。不取shared/absoluteModel，
也不把tap pos、submit JSON positions、Confirmed全展示IDs统一编码。
T33 S1同样已由物理入口独立核实，0x103d4ed6c→0x103d4e554，变化后
readiness0x103d4e780、弱取parent0x103d4e794；parent缺失保留选择但不发事件，
上限拒绝toast0x103d4e92c也不发事件。十字段同族事件实际report
0x103d4ec9c；parent位置从S1.items首次相等索引+1（0x103d4e9b0/
0x103d4e9cc，缺失0），child位置取物理IndexPath.item+1
（0x103d4eadc/0x103d4eae0），三身份字段取S1.model。select/cancel取本次
追加/删除分支，不用提交后的去重ID数组推导tap位置。
T34 S1 readiness0x103d60fa0以raw selectedSubItems.count>=1且
count>=model.select_num_min_limit决定setEnabled（0x103d61004–0x103d61054）；
model nil则直接返回、不改旧按钮状态。min<=0仍不允许空选择；此计算不按parent
去重，也不检查人口属性/busy。文案独立按min<1或enabled选
subpage_confirm_text，否则格式化剩余数量（0x103d61104–0x103d61160）。
物理confirm body0x103d60e50没有重读enabled/count，不能把UI按钮门禁推广为
程序调用final函数的同等拒绝条件。

T34空白区关闭的物理触发也已闭合到继承PopupViewController：
touchesBegan0x104e236bc→0x104e23514，首touch坐标与container.frame做
CGRectContainsPoint（0x104e23638）；inside返回，outside调用动态slot+0x1e8。
T34 metadata0x11fdef978对应0x104e22a5c固定true，再slot+0x200调用
0x104e22df0启动animated dismiss，随后slot+0x1d8同步进T34 body
0x103d569d4，不等待animation completion。该body要求current model，先清
selectedSubItems（0x103d56a1c）；仅pageIndex==0再清age/gender index为-1
（0x103d56a38–0x103d56a58），非零页保留人口属性。Skipped通知
0x103d56c40带current unique_id及helper0x103d56d00的sids，故孩子必排除，
非零页仍可含eligible demos，并非所有blank close都空sids。随后close helper
0x103d5b1b0以is_initiative="1"、reason="blank_click"发
main.interest-select.close.0.click（0x103d5b438），其余style/unique_id/strategy
取current model，再manager dismiss raw2（0x103d56cac）。没有submitted setter、
second HTTP或请求取消。另forwarding thunk0x103d5b800传is_initiative=false和
传入reason进入相同helper，其物理caller未闭合，不归因swipe/back。
T34 S1返回物理入口_previousButtonClick0x103d60e28，经0.25秒UIView animation
0x103d60d28、completion0x103d65160→0x103d60dd0；completion不检查finished
Bool，先removeFromSuperview0x103d60dec再弱取delegate，调用outer
0x103d5c180（0x103d60e08）。动画closure强捕获S1（0x103d60cbc/
0x103d60cfc）；parent nil则不执行outer reset。
outer两models非nil分支先发main.interest-select.step-btn.0.click
（0x103d5cf30），九字段：current style/unique_id/strategy、action_type="2"；
interest_id_list/name list/position list三项均由**outer旧selectedSubItems**的
weak parent映射、分别Set→array→JSON，无排序承诺。位置helper0x103d62ecc查
absoluteModel.items首次相等索引+1（缺失0）；content_cnt为去重parent IDs count，
extra_select按前述人口属性门禁构JSON（同section key时age覆盖gender）。没有
child list/sub_content字段，不读取当前S1 pending child数组。
随后explicit EmptyArray（0x103d5cdc0/0x103d5cdc4）写outer selectedSubItems
（0x103d5cf54）；model/absoluteModel nil分支0x103d5c34c也清选择但不发上述
事件。两路最终absoluteModel=current model、pageIndex=0
（0x103d5cf68/0x103d5cf80）。相对进入S1 helper0x103d58998在安排animation
后同步写pageIndex=1（0x103d58bf8），second error fallback也复用这个helper。
T34 S1 willDisplay0x103d60b18→0x103d646d0（0x103d60bbc）先查display child
SubItem._isExposed（0x103d64aa0/0x103d64aa4），true省事件；false发
main.interest-select.interest.0.show（0x103d64eac），九String：display parent
name/id/位置、display child name/id/位置，以及S1.model style/unique_id/strategy。
这条曝光用display parent，不借child click的weak parent门禁。track返回后直接
same child._isExposed=true（0x103d64ed4），不等网络ack；同对象再次willDisplay
被抑制，不因后续发送失败恢复业务曝光资格。它不是按MID/ID/IndexPath保存key。
SubItem init0x103d79f7c置false，modelPropertyBlacklist0x103d79eb0的静态array
0x120443080唯一项_isExposed，普通YYModel输入JSON不赋该marker；动态setter
0x103d79ea0仍可写，未闭合全局reset。
S1创建0x103d58998直接取input model.items（0x103d58b10），将同array/model
传configure0x103d5f4bc（0x103d58b24）；configure分别保存model/items
（0x103d5f4e8/0x103d5f50c），retains array0x103d5f514，reload后readiness
（0x103d5f700/0x103d5f720），未deep copy child、重parse或reset _isExposed。
因此同model重建S1（包括second失败沿用原model）保留子对象marker；新HTTP响应
的YYModel分配/对象复用策略另属边界，不把此结论推广为所有新model永不重报。
T33 S1也由独立物理willDisplay0x103d4ee2c→helper0x103d52ba4核实：读same
SubItem._isExposed（0x103d52f74/0x103d52f78），false才发同名interest show
九字段（0x103d53380），track后置true（0x103d533a8），不等HTTP回执。
这里只闭合T33标记接受时序，不以T34 configure证据替代T33视图重建/重置链。
T34原页人口属性willDisplay0x103d5be4c→0x103d637d8（0x103d5be50）按raw
section bit1选择Age、bit0选择Gender，以物理IndexPath.item取display对象；
Age._isExposed（0x103d63898/0x103d6389c）或Gender._isExposed
（0x103d63948/0x103d6394c）为true省事件。false发
main.interest-select.extra-btn.0.show（0x103d63d00），七String：name/displayed
title、interest_id/displayed ID decimal、title/model section title、pos=item+1、
current model style/unique_id/strategy。没有click的action_type，也不检查该项是否
selectedIndex。track后same Age/Gender marker=true（0x103d63d20），不等HTTP
回执。Gender.init0x103c79b94置false（0x103c79bf0），Age.init0x103c79cfc
置false（0x103c79d34）；各自blacklist0x103c79b88/0x103c79cf0分别引用
0x120443010/0x120443048，均仅含_isExposed并转公共0x103c79ebc。
因此新对象未曝光，普通blacklist-aware JSON不赋marker；同对象的post-track标记
保留。动态setter0x103c79b78/0x103c79ce0仍可写Bool，外部reset未全部排除。
T33首屏独立链willDisplay0x103d49d50→0x103d51ca0同样按raw section bit
选择Age/Gender；flag0x103d51d60/0x103d51d64或0x103d51e10/0x103d51e14
为true省事件。false发相同七String extra-btn show（0x103d521c8），pos来自
实际IndexPath.item+1（0x103d52058），无action_type/selectedIndex门禁；track后
同对象置true（0x103d521e8）。这是对象标记，不是view/session/key级去重。

三个门禁均通过时，helper滚动到(0,0)，构造20个LocalSmallLoadingViweModel，
CardData raw25、无report编号，Diff before空/after占位卡、flags=0。同步路径
0x101a53c68–0x101a53f90与默认异步producer0x101a57be4均已核实；helper返回true
只代表此分支被安排。经理dismiss0x103c7578c清view/model，排主队列工作，才在
0x103c75a34将hasShown置true并发Dismissed通知，不是在首次构造弹窗时置true。
已核实该ivar0x120443898的直接写仅init false与dismiss true；动态或账号reset未知。

MainVM0x101a49c40注册object=nil的Dismissed、Confirmed、Skipped通知观察者。
Confirm0x101a4b104将disable_refresh_after_submit按Bool解码，缺失/错型为false。
true且共享tmpPegasusCards非空时，交DataFactory0x101a41f10恢复卡片，不调用refresh
operator。同步分支先compactMap0x101a4340c再由0x101a42638从成功数组的1开始编号；
默认异步分支0x101a42130→0x101a43844→0x101a41524→0x101a3e1dc使用同规则。
回传Diff0x101a43724→0x101a4bad4弱取原VM/updater，实验同步开直接0x101a43a90，
否则经队列0x101a5830c安排apply；该包装无账号代际门禁。其他confirm条件先清空
卡片，completion0x101a4bf00保存选择，再读当时共享MainEventOperator+0x30并调用
raw reason4（0x101a4bf2c/0x101a4bf3c）。前述UI/loading门禁仍可拒绝实际新请求。

选择marker写入0x101a4b8cc要求unique_id与sids都为String，才写
0x12106a5c8的+0x68/+0x70和+0x78/+0x80；缺失/错型保留旧值。Skipped消费者
0x101a5becc同样写这两值，但没有卡片更新或refresh调用。MainApi首次惰性构造
params时读取marker为interest_id、interest_result（0x101a32f58/0x101a32ffc），
已缓存params并不每次发送重读。Dismiss消费者0x101a4aa3c要求typed DismissReason，
raw1直接返回，raw3另有first CardData类型门禁，详见下文具体UI链；不凭raw值
命名未核实的全局UI语义。通知、
共享tmp cards与marker均未带账号过滤，这只是已读路径边界，不证明运行时跨账号显示。

具体T10View确认动作0x103c83500→0x103c82294有可核对的UI来源，不能泛化所有style。
didSelect0x103c8590c→0x103c84914按section raw0/1/其余分别选gender/age/item；
相同gender或age再次点击直接返回。item将cell选择Bool异或1，新选IndexPath追加
数组尾，取消稳定过滤移除，重选追加末尾。换gender经0x103c8153c通常清item路径，
首次显式选择gender0才保留；这是UI实例状态，未证明落盘设置。
确认helper0x103c86900按当前选择路径顺序取chosenGender.items[item].id十进制，
不排序；追加gender.id（未选gender index=-1归0），age仅ages非空且index>=0才
追加。sids逗号join；interest_pos_ids独立由选中item位置+1组成，不包含gender/age。
Confirmed通知0x103c82ad0只有unique_id、sids、interest_pos_ids三个字段，
unique_id为model Int64的十进制String；没有disable_refresh_after_submit，因此这个
UI变体走默认false的清卡→marker→refresh operator路径，不走上述直接恢复分支。
T10 skip动作0x103c8226c→0x103c82044的Skipped通知0x103c821cc只有unique_id，
未带sids；因此具体落到0x101a5becc时缺第二String而返回，保留旧marker，不能把
“存在skip writer”外推为这次UI跳过会保存interest_result。之后dismiss raw2
（0x103c8220c），随后由关闭通知另行触发页面处理。
Dismissed消费者0x101a4aa3c中raw2直接进入清卡路径；raw3另要求当前first CardData
经0x1035a4648映射为local_small_loading才继续，raw1返回。清卡producer
0x101a571e8构造before=当前卡片、after=空、flags=0，同步0x101a4ae6c→
0x101a43a90或默认异步0x101a5ce28→0x101a58314应用；completion0x101a4b084
读CURRENT MainEventOperator函数对并调用raw reason1，仍受loading/UI门禁。
因此T10 skip的页面处理是清卡再尝试刷新，不是直接恢复tmp cards。
该UI后续0x103c83528(true,nil,nil)还报告close click，is_initiative="1"并带style、
unique_id；reason参数nil所以不带reason字段，不能从事件名字推一个服务器跳过回执。
另一T37View more面板不是相同通知形状：0x103d889e8构造两item，action回调
0x103d88bd4要求弱view有效、类型匹配且所选item+0x20 Bool=true，才进入
0x103d88c7c。这里Skipped通知0x103d88ea8同时带unique_id与sids（helper
0x103d858a8的结果commajoin），能满足首页marker writer的双String门禁；之后
dismiss raw3（0x103d88eec），再发reason=three_point的close click。
raw3仍受首卡local_small_loading门禁，所以该T37路径也不能保证清卡/刷新。
T37ItemS2View物理more入口0x103d97858→0x103d977c0→0x103d977cc经
delegate ivar0x120446290弱取parent T37View，先清selectedItems/SubItems
（0x103d9781c/0x103d97830），再present上述more面板。因此这一路后续sids的item
选择已清空，而不是仍携之前的全部选中item。其他子面板仍待核对；T10 skip与
T37 more的字段和动作不同，不能合并成一种确认或跳过协议。
T37的S2确认物理入口0x103d97798转0x103d97670，弱parent有效时先复制S2的
selectedSubItems到parent（0x103d976c8），调用0x103d8a940构造Confirmed；其
userInfo除unique_id/sids/interest_pos_ids外，还把InterestModel ivar
disable_refresh_after_submit（0x1204439d0）读成Swift Bool并透传
（0x103d8bd9c/0x103d8bddc/0x103d8bdec，post0x103d8be68）。这个Bool来自
前述yy_modelWithJSON解析的模型，不是UI硬置true；只有实际为true且共享临时卡片
非空时才满足首页Confirm恢复卡片的分支。T10的3字段默认false与此不同。
随后dismiss raw1（0x103d97710），直接向InterestPreferences设置
hasSubmitedInterest=true（0x103d97740）；这一本地标记没有HTTP成功回执门禁。
具体偏好receiver是BBPegasusInterest.Preferences（metadata0x11fde22f8），继承
BFCPreferences；configName0x103c6f864固定返回BBPegasusInterestPreferences，默认
hasSubmitedInterest=false（defaultConfig0x103c6f808→0x103c6fbc8）。property list
0x11d7e9318明确该属性为动态Bool（TB,N,D）；processAllProperties0x1167d3798为
它安装Bool getter0x1167d4adc/setter0x1167d4b5c，getter与setter都映射原始属性名
hasSubmitedInterest作为存储key。setter先更新实例configCache，再向这个固定suite的
NSUserDefaults setObject（0x1167d355c/0x1167d357c），不走Universal/HTTP回执。
初始化持久值非nil优先于默认值；随后getter仅加锁读取cache。这条闭合链没有MID/
账号分区参数，也没有显式synchronize；OS磁盘完成时刻及别处账号切换清理未知。
其他style是否同样透传/写标记仍待分别核对。

通知后，T10动作调用BFCNeuronClickEvent.trackEventWithId:extendedFields:
（0x103c83184），事件main.interest-select.submit.0.click。七字段来源为
content_cnt=选中item数、interest_list=选中item.name、pos_list=item位置数组、
extra_select=已选gender_title/age_title字典、style、unique_id，以及
interest_id_list=所选gender的全部items.id，后者不能与仅选中项组成的sids混同。
数组/字典经helper0x103c6f200转String，其JSON细节继续核对。最后dismiss raw1
（0x103c831bc）才将hasShown置true；这闭合raw1与T10确认的关系，而非所有样式的
全局枚举语义。该动作未另写Universal preference或直接发选择专用HTTP；后续feed
请求与Neuron发送各有自己的门禁，不把通知/点击调用视为兴趣已在服务端生效。

refresh失败时，0x101a5b3b0的x1是Error而非rawitems，w4为Result失败tag；
0x101a57e20的true分支仅swift_errorRetain，不是发起重试。失败先从本次params读取
open_event并比较cold_back。只有配置字节0x12106a633为true、flush原始值属于
mask0x1f7dff（0–8、10–14、16–20）、当前VM.cards空、open_event!=cold_back时，
才调用兜底缓存helper0x101a54d44，否则立即呈错0x101a54b70。

缓存producer也有具体正常响应入口：refresh在配置字节0x12106a633=true且flush属于
同一mask0x1f7dff时，0x101a5b540将rawitems/config交0x101a5a13c，发生在VM.config
更新和卡片转换之前。helper逐输入字典复制extra_rpt_fields，将
is_cache_local_data设为String "1"（已有键覆盖），写回工作数组；此工作数组经Swift
COW独立于继续网络渲染的原数组，不能称为当前卡片model setter。它构造顶层
JSON的datas/config两键，经writeAsync:scene:id:data:version:expirationTime:
0x101a5a914写入：scene=tm.recommend.0.0、id同0x101a5a02c当前账号+style，
version为VM.diskCacheVersion（初始化String "1"），expirationTime明确传0。
返回订阅保存cacheWriteDisposable（0x101a5aadc），其dealloc dispose已闭合。
config先经0x101a59e50→0x101a59bb4过滤，明确剔除scene_uri与interest_guide两键；
其他配置键保留。真实存储服务与expirationTime=0语义仍待核对，
不能据此称永久缓存。读出的cacheitems再经普通render，所以该缓存标记可随
extra_rpt_fields进入Reporter合并；不是另发一种网络推荐请求。

helper调用KntrFallbackCacheNativeKt.readAsync（0x101a54df4），scene=tm.recommend.0.0，
id由0x101a5a02c读取发起缓存查询时currentUser.mid与当前style生成，version取
VM.diskCacheVersion；不记录真实MID。它切到MainScheduler，continuation
0x101a5ba94→0x101a54878仅weak-load原VM；VM已释放则返回。cacheitems非nil时
以cacheconfig替换VM.config（0x101a54938），publish key26，再将cacheitems交普通
render0x101a53fd0（0x101a549ec），仍先compactMap并从1编号；nil缓存走错误呈现。
这条路径没有创建新MainApi，不是重新请求推荐服务。
读结果parser0x101a56628在Result失败或无有效success/data时回(nil,nil,nil)；
有效JSON dictionary即使datas缺失/不能cast仍用emptyArray，config缺失/不能cast用
emptyDictionary并回非nil，因此空datas也可走缓存恢复分支，不能把非nil缓存当非空卡片。
原VM的_transactionToken在0x101a49dc8来自LaunchTransaction.registerWithItem，
0x101a57198调用done，是启动事务句柄，不是request-generation凭证。
缓存readAsync桥0x101363a5c返回cancel closure0x1013648e0，但替换Optional订阅本身不是cancel。已读Rx AnonymousDisposable.destroy
0x1050a867c仅释放disposeAction context，BinaryDisposable.destroy0x1050b0980仅
销毁两个existential，SinkDisposer.destroy0x1050e87d0仅销毁optional sink/subscription，
这些析构都未调用dispose。具体Observable经Producer.subscribe0x1050e78d0分两路：
已有CurrentThreadScheduler队列时返回ScheduledItem；否则同步创建并返回SinkDisposer。
前者metadata0x1196b7870的destroy0x1050f51b0只释放action context、state及
SingleAssignmentDisposable，后者destroy也只释放成员；两路在Optional替换/释放时
都不会自动dispose。ScheduledItem另有显式Disposable witness0x11b356640，
经0x1050f58c0→0x1050f5894调用SingleAssignmentDisposable.dispose0x1050fb8d0。
因此必须证明显式dispose的调用，不能仅凭引用释放认定旧查询已取消；额外取消入口仍待追踪。


原网络completion0x101a55f8c在0x101a55fd0及0x101a56038向同一个已捕获MainApi取
lazy params。getter0x101a32340在instance+0x18非nil时直接复用，仅nil时重新构造并
缓存；user callback及key22 report因此使用该请求的已缓存参数，不再消费一次
open_event或重新读取设置。缓存回调0x101a54878没有可见MID/request-generation比较；
cacheReadDisposable赋值helper0x100893fc8是Optional assign-with-take，不能称为显式
dispose旧查询。MainViewModel.dealloc0x101a48e50→0x101a48ce0才明确通过Disposable
witness+8 dispose cacheRead（0x101a48db0）与cacheWrite（0x101a48e10）。普通刷新入口0x101a4893c先丢弃已有EarlyRefreshCache结果与continuation，再读isLoading；true时直接返回，
不发送新refresh且不dispose旧cacheRead。false时发feedWillRefresh、通知并置isLoading=true，
再调用网络入口；卡片处理completion0x101a56250弱取VM后清isLoading。
这说明普通loading期重复下拉是拒绝新刷新，不是取消旧缓存读取；实验提前刷新有
独立门禁与取消入口。VC setup读取process-once缓存bool0x12106a632；initializer
0x101b483b4要求pegasus_pull_refresh_opt_enable与infra.eu.opt都true，二者default=false。
开启才安装earlyAction/cancelAction；early UI0x101a372d8要求pan velocity.y>0，
才以reason raw7进入0x101a485e4，loading=false时设loading/pending并发请求。
物理拖动接线在BFCRefreshHeader0x116065044：drag期间offsetY跨过
-originalInsetTop-headerHeight阈值使state1→2，再拖回阈值使2→1；前者通过
setState0x116065300在early enabled时调earlyBlock，后者调cancelBlock。
停止drag且state2会beginRefreshing，state3走正式headerRefreshingAction。
因此这里的cancel是越过完整header阈值后拖回，不能泛称离页/HTTP失败自动取消。
main action0x101a484b4在pending=true只安装continuation，不另发请求；已存结果则
由0x101a584f8处理，均无结果时退普通refresh。处理要求params非nil、result tag非ff、
reason非raw21 sentinel，交0x101a5b3b0后清缓存；deferred0x101a58694采用同门禁。
cancelAction0x101a374d0→0x101a487f8清已有payload/continuation/pending，明确将
isLoading=false（0x101a48918），但没有本层请求dispose/cancel。
pending=false且result tag=ff也仍清loading；没有“本次early请求拥有loading”门禁。
因此early入口被既有loading挡住后，若UI仍触发拖回cancel，可解除其他普通在途请求
的loading；是否实际允许该UI交错与公共网络取消仍未运行验证。
late response0x101a5837c只有原VM weak非nil门禁：无条件清loading0x101a58430，
重新写缓存params/result/reason/pending，再读取当时continuation并调用；没有读取
先前pending/取消代次/当前账号。因此晚回调可重填已取消的缓存，甚至消费后来
安装的continuation；无continuation时不会直接apply。公共网络全局取消和真实送达
尚未验证，不把静态交错可能性写成已复现污染。该分支也不能套作默认普通刷新行为。
账号empty Diff链未清earlyCache；实验main action收到新的Marker reason时，ready-cache
分支却取cache.reason及旧params/result交0x101a5b3b0，新的reason只供无缓存时的
普通请求分支。因此同活VM有ready旧缓存时，账号触发header action存在处理旧结果
的条件路径；仍须满足实验、launch、loading、collectionView和UI action门禁，不当
真实跨账号送达证明。
其它订阅取消与防串扰仍待追踪，具体账号通知链见下。
数据最终写入也已定位：VM.cards getter0x101a48ba0返回FeedUpdater，+0x28是
DataFactory，后者datas在+0x10。默认pegasus_process_data_sync_exp_enable=false时，
render0x101a53fd0排到FeedUpdater.concurrentQueue，0x101a43bfc先等待semaphore，
再main.async执行producer；producer0x101a562f4从原VM当前FeedUpdater取DataFactory
生成Diff。nil Diff直接signal；非nil进入apply0x101a43e2c。实验true分支则直接
调用DataFactory，绕过上述wait入口，不能用默认串行行为概括全部配置。
usingDiff=true时生成UI diff，data setter0x101a44560只weak-load捕获的FeedUpdater，
非nil就写DataFactory.datas（0x101a445b8）；batch分支0x101a447f0同样只weak-load，
将Diff.after写入datas（0x101a4488c）并reloadSections。UIcompletion再publish24并
signal。上述commit点没有可见账号、请求代次或before==current datas检查。
这闭合了本地串行apply与写入点，semaphore本身不使旧响应失效；外部collection
diff引擎与非典型寻址的外部重置仍待核对，不能将局部缺少校验直接当实测污染。
全__text的descriptor直引扫描中，VM._updater的引用仅见getter、初始化及析构；
getter0x101a48bb4已有实例就retain返回，nil才新建并保存0x101a48c34。
VC.viewModel同类扫描仅见两种init的初始nil、lazy getter首次保存与析构，没有
识别到账号回调替换writer。这是有界扫描，不能排除动态或不同寻址的写入。
普通请求0x101a550b0→0x101a34a4c在requestAsync0x101a34ba8后立即release局部
BFCApiRequest，没有把取消句柄回传或存入VM；公共网络层的全局账号取消仍未证明。
该业务构造入口没有设置custom response queue，故异步completion/error沿公共层默认
主队列送达。MainApi error closure0x101a34c14也没有按-999过滤：保留error，置config/
interest=nil与Result tag1，再调用注册callback（0x101a34c30）。因此即使外部实际调用
公共cancel，只要afterwrapper/gateway/errorHandler继续送达，取消错误仍可进入原
weak VM业务回调与earlyCache；不能把transport cancel概括成业务层天然静默。
具体账号入口已有一条闭合链：VC lazy VM初始化时以该MainVM作observer注册
BFCAccountNotification.addActionObserver:type:block:（0x101a3663c，mask raw0xb），
closure0x101a3b788→0x101a4a4d8弱取原VM，LaunchTransaction.isAllDone=false直接
返回；true则用原FeedUpdater生成Diff，before=当时DataFactory.datas、after=empty、
flags两字节0。默认实验false仍走上述queue/semaphore，true直接apply。
apply completion0x101a4aa34调用MainEventOperator的flush函数对，参数raw17；这是
独立operator动作，不能因相同数字叫成Dispatcher raw17事件。该completion执行时
重新读取共享MainEventOperator的函数对；当次绑定closure0x101a5c464捕获同VM，
但另一VC再次绑定可覆写共享闭包，因此不能把其接收者总认定为原Diff的VM。
绑定入口0x101a48f88与completion0x101a4b08c支持此归属限定，真实多实例选择未证。
closure进入0x101a4fa88：collectionView非nil且isLoading=false时
写MainApiMarker raw17，再scroll到(0,-60)，0.3秒main.asyncAfter触发header refresh。
这个已读链没有替换VM、dispose cacheRead、reset isLoading或检查账号代次。
isLoading=true时仍可完成空Diff应用，随后拒绝header refresh；静态路径可以成立，
不把这条静态链当实测时序。通知层0x11605d16c以item.type & action筛选，mask0xb
覆盖Login1、Logout2、Change8，不覆盖Update4。普通命中main.async后读取ssoModel并
回调原action；Change专用路径0x11605d2ac因item.type含bit3，排相对3秒dispatch_after，
再以action8回调。这是账号通知的3秒，独立于上述header refresh的0.3秒。
VC header handler0x101a3b7e8经0x101a37538弱取VC，取其viewModel、读取当时Marker.reason，
再调用普通refresh0x101a4893c。raw17经Int64映射表0x1182c9138变成wire flush=21，
不能写成wire17；普通refresh的isLoading门禁及缓存不自动取消的结论仍适用。
replumeFlushIndex（0x101a5133c）
确实对传入数组从 1 重编号，目前已找到 BannerV8 替换调用，原始响应批次的调用未证。
Swift didSelect（0x101a380e4→0x101a37e38）注入的是 BBListPegasusAdapterProtocol，
不是 MainEventOperator；MainService witness+0x30（0x101b866f8）要求模型符合
CardViewModelProtocol，再调用其 +0x70。SmallCoverV2ViewModel 的见证
0x101b1d8cc→0x101b1d204 以 action=1、main-card 调专用 Reporter
0x101a974c0，构造 `tm.recommend.main-card.0.click`（调用者 default0）并 track，
进入 ClickEvent policy=0。该专用 builder 初始22字段中没有 position；只有后续
extra_rpt_fields/additionalDic 合并可能增加，不能套普通 show/duration 的 position。
它直接用 model.track_id，不走 HD args.track_id fallback；card_rel_id/
card_material_id 为 OptionalString，不套 HD 数字格式。其他模型 click 仍需逐一核对。

HD 原始响应 position 已闭合：刷新解析 0x10df59518 取 data.items，经 CardPool
循环 0x10df17fc0 从输入下标 0 开始，先调用模型配置回调（0x10df1807c），再执行
isValid/类白名单过滤。配置回调 0x10df59978 将原始下标+1 赋 report_flush_idx；
被过滤项仍会占用原始编号，留下的卡不按显示行重新排号。加载更多回调
0x10df5af0c 同样按本次输入数组下标+1 赋值，未加累计列表 count。因此这个位置是
原始单批次位置，不能套用到尚未闭合的 Swift 响应分支。

### 不感兴趣的本地操作与请求

BaseCollectionVC 删除入口 0x10dee8598 先做 cell 广告 close/dislike 报告，再通过 VM
0x10dedceac 本地替换为 DislikeVideoModel，随后发送入口 0x10dedcd5c；本地改变发生
在服务端确认之前。disablePersonalizedRcmd 在该入口影响 toast，所有分支仍走
sendDislikeApiRequest。广告卡有独立分支；普通卡未登录则 0x10dede80c 不发。

通用请求 0x10dedeb28→0x10dedefc8 构造 API 并 requestAsync；URL 是
app.bilibili.com/x/feed/dislike（0x10df563cc）。params（0x10df563d8）始终放
id=param_id、goto=gotoType，nil 退空；reason_id/feedback_id/mid/rid/tag_id/ad_cb/
from/cm_reason_id/from_spmid/from_module/nature_ad/track_id 仅 length>0 时加入。
extraParams 最后 addEntries 覆盖默认值。此处 mid 来自卡片 args.up_id（UP），
不是账号 mid；rid/tag_id 来自正数 args.rid/tid。reason_id>0 且 reasonType=3 时
放 reason_id、=4 时放 feedback_id；includeCmReason 且 cm_reason_id>0 才放该字段。
from_spmid 来源是卡片 from_spmid 加 `.0.0` 或 default-value，goto 来自 card_goto。
该请求的响应、本地恢复、广告专支字段与当前版本验收仍未完成。

## 功能、设置与首页请求参数

此专项核对 NOTSURE 中的当前策略，保留9.13抓包结论与8.89静态分支的版本边界。
下表“相容”仅表示所选场景可生成该值，不证明官方值恒定，也不直接要求改变生产策略。
Swift MainApi.params（0x101a32340）先读实例 self+0x18，非 nil 直接返回；首次才
调用 builder 0x101a3239c 并缓存。MainVM refresh/loadmore 新建 API，故下面状态
读取发生在新实例首次构造参数，不能概括为同实例每次 getter/重试都会重新读取。
getApiOptions（0x101a3204c）取缓存 params、桥接 NSDictionary 后 setParams，
传统公共构造层随后按前述规则合并。builder 已读尾部可选键没有任意 extra 字典
覆盖这些设置字段；但中段 preloadUrlParams 已证会覆盖此前生成的同名业务值：
0x101a32f10 桥接 incoming 字典，0x101a32f18–0x101a32f48 交给 merge
0x101a34414，碰撞分支 0x101a34528–0x101a34544 释放旧 value、存 incoming value。
该 specialized body 的碰撞段没有调用传入 closure，不能仅按 closure 推定旧值优先。
完整公共/Ktor 后置覆盖仍需逐项核对。

| 参数 | 功能与来源 | 操作、保存 | 生成、读取及复用 | 8.89最终字段证据 | 当前策略对照 | 仍缺证据 |
| --- | --- | --- | --- | --- | --- | --- |
| auto_refresh_state | 自动刷新，用户设置/设备配置 | 设置页数组开3关4；didSelect 0x10f2f5fd8→updateAutoRefreshState 0x113ceea74，写 cachedConfig.autoRefreshState.value，再 uploadConfig | getter 0x113cee9d8 缺省/unsigned值<=1退1，否则保留；isOpen仅1/3；新API首建读 | 0x101a33808→UInt.description，赋同名键 | 固定4与明确关闭相容，默认1/重新开3不是4 | uploadConfig磁盘/账号边界、公共覆盖 |
| inline_sound_cold_state | 持久声音偏好与用户是否处理设置 | 音量设置开3关4，0x10f2f5e2c→0x113cee934；1/3写inlineVolumeOn=true，3/4写hasHandledVolumeSetting=true | getter 0x113cee8ac：未处理开1/关2，已处理开3/关4；动态Bool setter更新RAM与NSUserDefaults，新API首建读 | 0x101a33680→UInt.description | 固定4与用户处理后关闭相容，不等同默认2 | 默认配置、与实时mute同步、公共覆盖 |
| inline_sound | 实时静音/系统输出音量，播放状态与设备状态 | BBPegasusInlinePreferences.mutePlay setter 0x11419f388 更新RAM/KVO/通知，未写上述偏好；init仅首次读inlineVolumeOn反转 | 进程singleton，mutePlay=true→1；false且AVAudioSession.outputVolume>0→2，否则3；新API首建读 | 0x101a33574–0x101a33650 | 固定1仅与mutePlay=true相容，不能将cold_state=4直接当实时状态证明 | mute UI/通知同步链、账号复用、公共覆盖 |
| inline_danmu | 首页弹幕，用户偏好及服务器同步 | BBPlayerDanmakuPreference的动态Bool，经BFCPreferences写RAM/NSUserDefaults；active Service.updateDanmakuSwitch再发paramType15同步；服务器也可覆盖 | 内建默认true；true→2/false→1，对象nil省略；新API首建读 | 0x101a33764–0x101a337d8；默认0x1147e5398，写0x114203fe8，同步0x1147e7ad8 | 固定2与默认/开关true相容 | 首页具体UI绑定、账号边界、公共覆盖 |
| voice_balance | 音量均衡，用户偏好/PlayConfig | setter写BoolValue.value、setVolumeBalance，再uploadConfig；设置页switch selected经type37调用setEnableLoudNorm | getter优先cachedConfig.volumeBalance.value，缺失取defaultConfig；内建默认true；true→1/false→0，对象nil省略；新API首建读 | 0x101a338f8–0x101a3396c；getter0x1147f062c，默认0x1147eecd8，setter0x1147f0704，UI0x10f31bb48 | 固定0仅与显式关闭相容，内建默认产生1 | upload持久化/账号/服务器更新、公共覆盖 |
| autoplay_card | 首页自动播放，用户/设备/服务器影响 | UI模型all10/WIFI3/off4；设置页0x10f2f58ec→updateInlineSetting 0x113ced8f4，写DeviceConfig.autoPlay.double_p及server标志，再upload/通知，无重启门槛 | 底层off1/WIFI2/all3，在server=false时生成4/3/10，true时2/1/11，缺省0；合法0/1/2/3/4/10/11最终保留，非法兜底11；新API首建读 | 0x101a32e38→0x1035ab340→0x101a482b8，表0x1182c91e0→Int.description | 固定4与用户明确关闭相容，不是官方全场景常量 | UI数组装入、upload持久化/服务器更新、公共覆盖 |
| column | 布局，用户/账号/设备/服务器影响 | manualUpdate仅3/4，登录写Mid配置；Device把1/3归底层1、2/4归2，另写server标志并通知 | 登录取Mid，未登录取Device；Device底层1生成server1/用户3，底层2生成server2/用户4；最终unsigned<5保留否则0，新API首建读 | 0x101a32700→0x1035ac8ac→currentColumnSetting，再Int.description | 固定4与显式双列采集及关闭server标志相容，码不是实际列数 | 布局UI/flush通知链、磁盘与账号切换、服务器写入、公共覆盖 |
| video_mode | 视频播放样式，用户/账号偏好 | 设置页item.type赋UI.value，didSelect加10；manual仅11/12，登录写MidConfig.playMode并upload，所有状态写list_setting_userDefaults的kBBListPlayTypeKey并通知 | 登录读Mid，缺省0；退出读NSUserDefaults非零值，否则-1；新API首建直接Int.description，不减10 | UI0x10f2f3b04/0x10f2f5c98；manual0x113ced0b4，保存0x113ced234/0x113ced2d4；字段0x101a339a0–0x101a339c8 | 固定1不能等同用户明确选择11；选择码与请求码要保留 | model标题/服务器默认、账号切换通知消费、公共覆盖 |
| recsys_mode | 推荐/关注feed模式，用户及DeviceConfig | 设置页value1传1，value0且当前关注时传2；setter输入1写底层mode2，其余写1，同值跳过，变化upload并通知 | getter底层==2生成1，其他0；Swift isFollowFeedMode→字符串1/0，新API首建读 | UI0x10f2f5aec–0x10f2f5ba8；setter0x113cee678，getter0x113cee5c0；字段0x101a32d8c–0x101a32e04 | 固定0相容推荐模式，关注模式为1 | model标题/默认、账号持久边界、通知刷新与公共覆盖 |
| disable_rcmd（公共参数） | 个性化推荐开关，用户偏好 | 设置selected取disable的反值；tap要求permission_url.rcmd_info存在，当前disabled时直接开启，当前开启时确认后才禁用；默认false，BFCPreferences动态Bool写RAM/UserDefaults | KNetParamModule缓存service，OtherNetParam每次仍读getDisableRcmd；Bool false/nil→0、true→1 | 数据模型0x10f321ad8；action0x10f2f1fb8/confirm0x10f2f2384；native getter0x1000b3e08，Kotlin0x10aac5910 | 不能把默认0与用户确认后的1等同；公共项不是首页builder中的常量 | 最终公共合并覆盖、账号/服务器变更 |
| client_attr（preload） | Dolby/HDR优先，用户、实验与VIP共同影响 | 设置QualitySettingDatas把priorityUseDolbyHDR作switch selected/type50；通用action→setPriorityUseDolbyHDR。player.priority_hdr_842 preset0未命中时setter不写；命中且变化才写CloudPlayConfig/upload；默认false | getter同实验门控，preload再检查有效VIP；仍受preload字典合并时点影响 | UI0x10f312df8/0x10f31bb88；setter0x1147f0adc；preload0x114398220–0x114398270 | 固定1不能等同默认，也不能只凭设置开就保证该bit | upload/账号边界、其他bit与设备能力 |
| qn_policy（preload） | 自动画质，用户播放选择/持久偏好 | BFCPlayerSettingsPreferences.autoQnEnabled默认true；updateUserQn:isAuto接受后写原isAuto，manual不满足shouldMemoryQn则早退 | preload→QualityHelper.autoQualityEnabled→共享偏好，Bool→字符串1/0 | 0x1143980b8–0x1143980e0；getter0x114820fc4；默认0x114faf598；写0x11453b1ec | 只与实际偏好值对照，不能推为设备/网络恒定能力 | isAuto具体UI来源、manual保存门槛、其他覆盖 |
| https_url_req | HTTPS播放地址，用户本地偏好 | OtherSettingDatas用httpsPlayurlEnabled填selected/type10；通用switch Bool→DataManager.setHttpsPlayurlEnabled；默认false，BFCPreferences动态Bool保存 | 新API首建读共享偏好，非nil生成0/1，nil省键；在preload合并后赋值，覆盖同名项 | UI0x10f314778–0x10f314820；写0x10f31bb80，默认0x114faf4fc，字段0x101a33398–0x101a33424 | 固定0相容默认/关闭；打开可为1，无重启要求 | 服务器/账号其他写入、呈现条件 |
| guidance | 卡片/加载更多引导，本地展示标记 | LocalPreferences动态Bool，BBPhonePegasusConfig suite；defaultConfig两个标记均false；UI写true待追 | 新API首建读hasShownGuideTapCard，true才再读hasShownGuideLodeMore；公式!(tapShown&&loadMoreShown) | 默认0x101b8a9e8/0x101b8aa78；字段0x101a33464–0x101a33548 | 固定1相容任一未展示/缺存默认；两项都true才0 | UI写入、清理、账号边界 |
| teenagers_age（公共参数） | 青少年年龄，账号偏好/服务器状态 | PasswordVC status11设置流程仅成功回调才Manager.setAge；同步状态也可覆盖。Prefs动态Int64，常规suite含account.userID；defaultConfig无age | SignHelper.baseParams每次Const→wrapper/manager→Prefs.age→NSNumber.stringValue写公共键；未见16常量 | 公共0x11609c68c/0x11609cac4–0x11609cb00；保存0x115961ebc；成功0x1159777d0 | 固定16缺来源证明；选择器defaultIndex16对应年龄17 | delegate/确认绑定、shared账号重建、缺值动态getter与公共优先级 |
| player_net（preload） | 网络可达状态，系统状态/进程缓存 | BFCReachability监控www.bilibili.com，初status0，异步更新；变化写status并通知，无这条链用户存储 | preloadDevice首次缓存能力项，但每次重写player_net；WiFi1/WWAN2/其他reachable0/不可达3，新API首建merge，同APIparams仍缓存 | 0x114a0c368–0x114a0c430；status0/1/2判断0x1161baf4c/0x1161baf94/0x1161bafdc；merge0x101a32f48 | 固定1只相容当次WiFi；初始异步尚未完成可能3 | 底层仅0/1/2，0分支可受独立读取间状态变化影响；其他public覆盖 |

系统Reachability0x1161e4ea8读取flags失败为0，成功交0x1161e4d84：reachable bit1
未设为0；已设且connectionRequired bit2未设为1，或自动连接bit3/5且无需干预bit4为1；
WWAN bit18设则覆盖2。因此底层正常输出仅0/1/2，player_net的“其他reachable→0”
不能当稳定第四网络类型；三次Bool独立读状态，更新交错可走到该分支。
首页另有network：0x101a32640单次同源status读取，1→wifi、2→mobile、其他空字符串；
早于preload player_net，异步变化可能使同批两个字段不同，同API缓存限制仍适用。

red_point由启动保存状态决定：GPPushNode.setup0x10f6d36f8保存launchOptions远程通知
是否非nil和当时系统角标到BBCPush的bootByNotification/bootBadgeNumber（RAM）。
MainApi0x101a3251c仅非通知启动、bootBadge>=1且MainApiMarker.+10计数为0才写角标
十进制，非请求时实时角标。Marker初始化0x101a35678计数0；订阅dispatcher key22，
首payload可cast OptionalError且nil才0x101a35058清状态并计数+1，错误不消费首次。
VM响应0x101a5b078两支key22分别传error与nil；其他重置/账号切换仍待穷举。

widgets来自系统WidgetCenter配置。Marker初始OptionalString=nil；后台通知接
0x101a35724，iOS>=14调用getCurrentConfigurations。成功0x101a358e4按返回顺序取
WidgetInfo.kind，逗号join保存Marker+58/+60，不读family/intent、不去重；零组件写空串，
失败保留旧值。MainApi0x101a33aac有值才加入widgets，nil移除键，因此未加载省略与
成功空串不同。旧API缓存不更新，新API读当时状态；不是首页player_widget，未证明冷启动
请求前一定读取，未見该串NSUserDefaults持久化。

禁个性化推荐还有设置页以外的明确writer：PersonalizeGuidance setup
0x101b59418把onOpen ivar0x120358518绑定weak-self closure0x101b5f560→
0x101b59ca0。实际openButton ivar0x1203585a0经Rx事件raw64
（0x101b5b364）订阅0x101b5fe88→0x101b5b85c，onOpen非nil才BLR
0x101b5b8c0；callback发送open_button动作/toast后调用
setDisablePersonalizedRcmd=false（0x101b59dcc）。这是用户推荐引导动作，不是
账号或服务端自动重置。
外层creator0x101b57d70在force bit=false时检查0x101b59164：已有guideView
isShowing则拒绝；latestConfig.enable_rcmd_guide必须存在且Bool true、用户
disablePersonalizedRcmd必须true、guideConfig非nil、today count<max_show_count，
并通过关闭冷却0x101b58a44。force=true只绕开该helper，仍需guideConfig及
guideType.lowbyte!=0。raw1冷启动show0x101b594bc另外检查RAM hasShownForCold，
因此force也不绕过它；安排BBSerial priority1/event0x101b5f528→0x101b5a21c，
成功展示后0x101b5a59c才设true，init0x101b57be0设false，不把它称磁盘标记。
非cold show0x101b59628仍需要application window，未保证每次请求展示都完成。
展示计数0x101b58548按当前Date的yyyy-MM-dd key把今日count+1，保留close字符串；
shared helper0x101b57938经yy_modelToJSONObject/字典cast→LocalPreferences
singleton0x120359f78→setPersonalizeGuideInfo（0x101b57a2c），不是HTTP成功。
close callback0x101b5f568→0x101b5a0ac报告close_button，再0x101b58854仅在
close_show_interval>=1时保存今日字符串PegasusPersonalizeStartDayAfterClose，
保留计数字典并用相同持久调用；zero/negative不写marker，没有禁个性化setter。
jump callback0x101b5f570→0x101b5a14c报告panel事件并processUrl
personalized_rcmd_page，也不在该body写偏好。
冷却helper0x101b58a44在config nil、interval<1、close字符串空时允许；正常
eligibility此前仍要求config非nil。非空关闭字符串用yyyy-MM-dd解析
（0x101b58bb8），解析失败退当前Date（0x101b58dac），随后加systemTimeZone
对应secondsFromGMT（0x101b58e14/0x101b58e38）。正interval经UInt→Double
原值交Date.addingTimeInterval（0x101b58ed4/0x101b58edc），**未乘86400**；
再格式化/解析为日期，比较targetDate>today（0x101b59130），返回取反允许
targetDate<=today（0x101b58b88）。不能据字段名把interval写成天数或精确墙钟
冷却时间；malformed日期走当前日期fallback，不直接无条件允许。
Story STLoadBloc.addReloadNotifications0x1041149e4→0x10411431c注册账号
action type1（0x1041143dc）及update type2/triggerImmediately0
（0x104114460），并观察BFCAppPreferences.shared的disablePersonalizedRcmd
keypath0x1183cc3d8。publisher0x105011644/raw options5后经过Bool处理链
0x1050fc84c/0x1050d0154，再sink0x104114c30→0x10411498c；这些框架operator
语义尚未独立命名。preference callback忽略incoming Bool，weakself存在才调用
reloadIfNeed0x104114738/raw4；account update0x104114934走raw2。两者没有写
该偏好。layout helper0x1040be894比较weak mainVC与router.navigationController
topVC（NSObject equality0x1040be970），相等才立即0x104114a80 reload，不相等
只存reloadType byte（0x104114914）；不是foreground通知。reload在landscape
先转portrait，再0x1041152cc/raw2/tab0，currentTab==1追加tab1
（0x104114b80）。延后reason由onViewDidAppearWithPushed
0x104114df4→0x104114dac消费：mode byte==1、pushed false、reloadType!=0才
reload后清0（0x104114e30/0x104114e34）；stored raw4/raw2可通过，raw0 login
与清除sentinel同值而不通过此非零门禁。实际load mode仍raw2，不把reason当wire
mode。loader若正在requesting可拒发，实际网络路径见后续独立核对。这是设置/
账号通知的请求消费路径，不证明偏好按账号分区或清理。


Story实际请求入口0x1041152cc按tab分流：tab0取feedLoader；mode byte==1且tab1
取SeriesLoader。tab0 factory0x104114e5c按router.scene==tab3创建CircleLoader，
否则RecommendLoader（class0x12045c590）。Recommend虚表+c8
0x12045c658→0x104111b9c，仅mode0且sharedResourceId非空可走快速路径；
上述重载mode2直接common0x1041186b0。common先检查requesting byte，已有请求
则返回；否则置1（0x1041187e8），options/params→setParams（0x10411893c），
BFCApiRequest.initWithOptions（0x104118960），completion/error handler，
再requestAsync（0x104118ad4）。这证明可用loader的异步请求调用，仍不等于实际
HTTP已经发送或成功。成功0x10411a4bc→0x1041192d0在处理payload前清requesting
（0x10411938c）；错误0x10411a4ec→0x1041194b0清该byte（0x1041194f0）后
error fanout。weak loader失效不执行这些更新，此范围未证自动重试。
Recommend URL getter0x104111fb0固定https://app.bilibili.com/x/v2/feed/index/story；
options0x104118538设GET，/data映射optional非array StoryModel。
params0x104111fcc先取BBPlayerPreloadUrlParamsHelper.preloadUrlParams；mode2
有focusItem时用playerArgs aid/cid/epid（缺playerArgs数值0）、pgc_info.ogv_style
（缺0）、trackid/goto、contain="1"及optional highlight_id；无focus则取router
的aid/cid/bvid/trackid/material_no/goto。display_id==1才补router from/from_spmid、
commonData.spmid和auto_play="0"，不是按mode2恒定补。全局cold byte0x12045c548
在构造参数时从1消费成0并加open_event=cold（0x104113858–0x1041138ec），
不等待send/ACK；pull仅mode4为"0"，其他包括mode2为"1"（0x1041138f4）。
network按reachability raw1/2/其他→wifi/mobile/空（0x104113980），video_mode
实时取shared setting（0x104113a64），display_id取loader+0x28。request_from、
story_param（query percent decode）、VBFreeBandwidth字段均来自各自helper。
非mode0取广告extra，随后originalRouterParams仍可覆盖ad_extra。此函数尚未证
直接加disable_rcmd；共享preload/public参数不能在此当作空或固定值。

### SeriesLoader 参数与响应证据

Series factory0x104115130读STCommonData.tag ivar0x12045aff0
（0x1041151f0）→loader kind+0x28（0x104115260）。mode2同样直接common；
仅mode0/kind4可能cache fast path。URL0x10411a640按kind4取
https://app.bilibili.com/x/v2/feed/index/relate/story，其余取
https://app.bilibili.com/x/v2/feed/index/space/story/cursor；kind4 options额外
cacheValidLife=600秒、ignoreCache=false（0x10411a6ac–0x10411a6b4）。
Series params0x10411a6e4先补preload/质量/network/翻译状态/免流字段，再按kind
0/1/2/3/4/5调用空dict/0x10411b36c/0x10411bef0/0x10411c87c/0x10411dee0/
0x10411d4fc。kind4 helper要求current item/playerArgs；缺失返回空dict，存在加
aid=avid decimal、trackid（nil空）、当前commonData spmid/from_spmid（nil空）、
view_attribute="0"及arc_attribute="0"，合入共同字段（0x10411aec8）。
Series其他kind字段也已独立映射：tag1 helper0x10411b36c八String
 aid/vmid/position/index/contain/before_size/after_size/cid。vmid优先config.mid>0，
再config.anchorItem.owner.mid>0，再series.item.owner.mid（nil0）；mode3取first
storyItems的cursorIndex/playerArgs，position=left/sizes20/0；mode4取last，
position原始count bit0偶right/奇left（0x10411b7a8–0x10411b7cc），sizes0/20；
其他取current series.item，position空/sizes10/10。contain仅mode3/4为"0"，
其他"1"；空edge仍保留方向/sizes而数值0，不在helper取消请求。
tag2 helper0x10411bef0八String aid/vmid/contain/before_size/after_size/cid/
season_id/goto；config.avid>0 OR config.cid>=1时同时替换aid/cid，未分别验证
每个替换值（0x10411c1c0–0x10411c250）。mode3/4仍改取first/last playerArgs，
vmid/season保持原item/config来源。season_id优先item.seasonId，否则config，
最终nil空；goto按tag2/3/5→ugc-season/ogv-season/pages，其他空。
tag3 helper0x10411c87c增加epid/ogv_style/material_no，总11String；config覆盖
门禁改为avid>0 OR epid>=1（0x10411caf0–0x10411cbbc），同时替换aid/cid/epid。
season仅原series.item，nil空；ogv_style始终原item.pgc_info（nil0），material_no
始终原item.highlight_id decimal（0x10411d3d4–0x10411d42c），不是config或edge。
tag5 helper0x10411d4fc同tag2八字段/override/sizes，但season只原series.item；
vmid特意从store.dataBloc.feed.item.owner.mid（getter0x1040a5f88，
0x10411db28–0x10411dc44）取，不套用series.item。各helper只构造合入的新dict，
未在此写游标/存储，raw loadmode和tag不是同一枚举。
Series response虚表+e8 0x12045caa8→0x10411af68→0x104118064，先调用
optional config.filter(model)，false返回不通知observer（0x104118144–0x104118168）。
其+b0 0x10411a67c固定1，所以跳过mode0 onlineConfig覆盖及该branch的reportStates。
公共handleResponse0x104118064仅filter准入、weakstore有效、type==0、loader.+b0==0、
model.config非nil时写dataBloc.onlineConfig并调用配置helper、trackBloc.reportStates
（0x104118198/0x1041181ac/0x1041181d8/0x104118210/0x104118244/0x10411826c）；
此入口是公共Loader条件分支，不应算Series每次响应的固定事件。
reportStates0x1041f07cc→0x1041f0578（0x1041f07e0）构造三个设置字段：
play_set_state用gestureMode0x10419eb88结果==1转String2、否则1
（0x1041f05dc–0x1041f05f0）；该getter每次优先登录且StoryConfig.gestureType.
lastModified>=1时使用remote.value==2的0/1，否则读本地BBPhoneMPStoryPreferences.
gestureMode（0x10419ebf4/0x10419ec10/0x10419ec54/0x10419eca8），不把remote PB2
直接作为日志2。play_set_start取当前STPlayModeBloc.currentPlayMode的十进制String
（0x1041f0624/0x1041f064c）；qn取CURRENT BBPhoneMPStoryPreferences.playQn，shared
nil为0（0x1041f0698/0x1041f06a8/0x1041f06bc/0x1041f06d8）。随后BFCNeuronExposureEvent.
trackEventWithId:extendedFields:，eventId为main.ugc-video-detail-vertical.set-state.0.show
（0x1041f072c/0x1041f079c），这是普通policy0链，区别于前述卡片trackInstantly。
play_set_start的currentPlayMode getter0x104172a74→0x104172abc重新读本地autoPlayNext/
looping（0x104172b54/0x104172b88），autoPlayNext=true返回raw3，否则looping=true
返回2、false返回1（0x104172bc0/0x104172bc8/0x104172bf0/0x104172bf8）；任一shared
缺失走fallback3（0x104172b44/0x104172b78/0x104172d64）。这里不直接返回配置PB。
另公开updatePlayMode0x1041728b4→0x1041725bc（0x1041728d0）把incoming==1写
local.autoPlayNext=true、local.looping=false；其他incoming写false/true
（0x1041725dc/0x104172628/0x10417264c/0x104172660），再重新问currentLoop并调用
playerBloc.updateWithPlaybackLoop（0x104172694/0x1041726a8）。currentLoop是当前模式
!=1（0x104172a8c/0x104172a90）。因此writer input1与下一次日志raw3不同，不能把
setter input当play_set_start；其他input经此writer归一到raw2。该body仅本地偏好/
player更新及诊断日志，未发Universal/RPC或reportStates；其他writer仍另核。

动态preferences后端已接通：BBPhoneMPStoryPreferences class 0x1201cf678继承
BFCPreferences 0x1202710f0，shared 0x1142bf5c0使用once token0x120da0af8及
instance0x120da0af0，initializer 0x1142bf5f0 alloc/init后存slot
（0x1142bf600/0x1142bf60c）。configName 0x1142bf61c固定返回
`BBPhoneMPStoryPreferences`（0x1142bf620），init 0x1142bf628先super.init
（0x1142bf650）。属性表0x11f0fb5e8明确autoPlayNext/looping是TB,D,N；通用
processAllProperties 0x1167d3798对rawB选择Bool getter0x1167d4adc/setter0x1167d4b5c
（0x1167d3ab0/0x1167d3bc0/0x1167d3bc4/0x1167d3bcc），映射原始property name。
初始化userDefaults同key非nil优先，否则defaultConfig（0x1167d3d30/0x1167d3d8c），
后续getter读RAM cache，setter先改cache再NSUserDefaults.setObject
（0x1167d355c/0x1167d357c），suite由当前configName懒建
（0x1167d4cfc/0x1167d4d14），本链无MID命名参数或Universal响应门禁。
Story defaultConfig 0x1142bf67c静态默认autoPlayNext=false
（0x1142bf7a0/0x1142bf7b8/0x1142bf7c4）、looping=true
（0x1142bf7d4/0x1142bf7ec/0x1142bf7f8），两者均采用默认时currentPlayMode为2；
不能把shared nil时fallback3当成正常默认。没有读取实际存值/磁盘提交结果或账号清理。

qn需区分静态default字典与手写getter：defaultConfig有playQn=0
（0x1142bf904/0x1142bf91c/0x1142bf928），但Story.playQn 0x1142bf960实际取得
BBPlayerSettingsPreferences.shared（0x1142bf970/0x1142bf974），读其playQn
（0x1142bf984）；setter 0x1142bf9a4同样委托该shared并setPlayQn
（0x1142bf9b8/0x1142bf9bc/0x1142bf9d0）。因此reportStates.qn并非直接取Story suite的
playQn=0默认；最终Player偏好/远程同步规则需沿其receiver另核。Story.autoQnEnabled
0x1142bf9e4也委托BFCPlayerSettingsPreferences，二者属性无D，且
handleNonDynamicProperty 0x1142bfa68返回false，不能当作上述动态Bool链。

Player qn接收端BBPlayerSettingsPreferences也继承BFCPreferences，property table
0x11f24ba80的playQn是Tq,D,N；固定configName `BBPlayerSettingsPreferences`
（0x1147ee2cc/0x1147ee2d0），defaultConfig 0x1147ee72c的playQn=NSNumber int0
（0x1147ee75c/0x1147ee774/0x1147ee780）。通用rawq动态getter0x1167d429c经RAM
及longLongValue（0x1167d42d4/0x1167d42f0），setter0x1167d431c封装NSNumber再同suite
保存（0x1167d435c/0x1167d4378）；存值优先于默认。Player.init末调用
resetDropSettingToDefault、syncLocalToRemote（0x1147ee4fc/0x1147ee504），后者
0x1147ee5f0从同suite读syncRemote gate（0x1147ee644/0x1147ee64c/0x1147ee66c），
未置true时只迁移enabledCubicPanorama/dolbyEnable到对应setter
（0x1147ee674/0x1147ee698/0x1147ee6a8/0x1147ee6cc），再写syncRemote=true并synchronize
（0x1147ee6f8/0x1147ee704/0x1147ee714）。该名字不证明playQn被上传；其body无playQn
写入或直接HTTP。其他实际Player qn writer/质量请求使用另沿各调用者核对。

选择模型的didClick链已闭合：playModeList 0x104171748把builder 0x104170c58交给
公共list wrapper 0x104172564。builder使用静态两项值0/1
（0x120459a28/0x120459a30），每项TitleModel.didClick安装closure 0x104172ea0及
捕获的weak bloc/value（0x104171194/0x1041711b4/0x1041711bc）。实际metadata
0x11ff09c68的+0x1a8槽0x11ff09e10→0x104b56610→0x104b56e8c，写didClick的
function/context pair（0x104b56ec8），不是仅凭字段名推安装。closure读取捕获值
（0x104172ea0）→0x104171488，weak bloc非nil才调用updatePlayMode:原始选择值
（0x1041714c4/0x1041714c8/0x1041714d0/0x1041714dc）；随后toast，重新load weak
bloc非nil才取得trackBloc并发BFCNeuronClickEvent.trackEventWithId:extendedFields:
（0x104171548/0x10417154c/0x104171554/0x104171680/0x10417168c）。事件id为
`main.ugc-video-detail-vertical.play-type-select.0.click`（0x104171578），局部字段
`play_type`=输入EXACT1时字符串2，否则字符串1（0x1041715c8..0x1041715f0），
不等于重新读出的currentPlayMode 3/2。weak bloc第一次缺失仍走toast，日志和dismiss
还有各自的后续weak检查；无该body的Universal上传或等待日志ack。

loopSettingList 0x104172558使用builder 0x104171754，将Bool选择捕获到closure
0x104172e30（0x104171cf0/0x104171d10/0x104171d18）→0x104171f38，weak bloc有效
才调用0x104172258（0x104171f74/0x104171f78/0x104171f84）。该helper取输入低位，
写looping=!input（0x104172288/0x10417228c/0x1041722cc/0x1041722d4），再写
独立autoPlayNext=false（0x1041723a0/0x1041723a8/0x1041723ac），更新播放器loop
（0x104172514/0x104172528）；不是调用前述updatePlayMode整数writer。
之后同callback的weak bloc有效才上报
`main.ugc-video-detail-vertical.player-type-select.0.click`（0x10417208c），
`play_type`=Bool低位+1的十进制String（0x1041720dc/0x1041720e0/0x1041720fc），
走BFCNeuronClickEvent（0x104172190/0x10417219c）。输入false对应looping=true、
当前模式2、日志字符串1；true对应looping=false、autoPlayNext=false、当前模式1、
日志字符串2。通用TitleContent触摸→didClick也有实际注册：TitleComponent metadata
0x12049f610的+0x70→0x104b5a294创建TitleContent（0x104b5a2a4/0x104b5a2b8），
+0x78→0x104b5a2cc把component模型.+0x10交install helper 0x104b59094
（0x104b5a2e0/0x104b5a2e8），helper写TitleContent.model（0x104b590c4/0x104b590cc）。
TitleContent class 0x11ff0a140继承BaseContent 0x11ff0c608，其initWithFrame
0x104b59fc0→0x104b59f08调用super（0x104b59fa8）；BaseContent initializer
0x104b6c5c0通过当前metadata.+0xa0调用setup（0x104b6c648/0x104b6c654），
具体TitleContent槽0x11ff0a1e0→0x104b57a54。setup把tapContent:作为action、
self为target的gesture安装到self（0x104b58770/0x104b58788/0x104b58790/0x104b587a8）。
tapContent 0x104b59e24→0x104b59e3c取CURRENT model及其didClick pair，任一nil返回
（0x104b59e58/0x104b59e60/0x104b59e88/0x104b59e8c），否则以捕获context调用closure
（0x104b59ec4/0x104b59ec8）；无该body独立gesture.state门禁。模型、渲染组件与物理
回调已接通；外层more按钮入口、实际运行时renderer选择/展示成功仍另核。

外层已知安装是BBStoryInteractRigthModule.makeShareService 0x1132c2580创建
BBPhoneMPStoryShareService（0x1132c25ac/0x1132c25e0），将weak-module block
0x1132c2b10安装为selectPlayModeBlock（0x1132c2754/0x1132c2768/0x1132c2784）。
该block load weak（0x1132c2b20）→_showPlayModePanels（0x1132c2b28→0x1132c3304），
从CURRENT storyContext.store resolve明确STPlayModeBloc class
（0x1132c3314/0x1132c3324/0x1132c3338/0x1132c3348），对返回receiver调用
showPlayMode（0x1132c336c）。showPlayMode 0x1041709d0→0x104170780→0x1041707b0
（0x1041709e4），layoutBloc.mainVC weak有效（0x104170820/0x104170830）才取
playModeList（0x104170834/0x10417083c），创建VKSettingVC
（0x104170870/0x10417087c）并经poperBloc呈现
（0x104170958/0x104170970），返回controller weak保存到swipeVC
（0x104170984/0x104170990）。这连接已安装share callback到设置列表构造；当前
shareChannel模型是否包含调用selectPlayModeBlock的具体菜单项仍未闭，不能把setter
存在当作该菜单运行可达。loopSetting外层调用另核。

两条选择日志均把局部字典交给trackBloc helper 0x1041efa34
（0x104171618/0x104172128）。该helper重新读CURRENT item，nil返回nil
（0x1041efa68/0x1041efaa4/0x1041efabc/0x1041efdb8），否则生成十个公共字段：
position=index+1、spmid、simple_id、from_spmid、avid/cid（playerArgs缺失取0）、
goto、r_id、track_id、is_full_screen（当前status.isLandscape为1/0），均为String。
其输入字典随后合并到公共字典（0x1041f0034/0x1041f0050/0x1041f0080），重复key
释放旧value并写incoming（0x1041f0364..0x1041f0378），所以调用者可覆盖公共字段。
当前两个调用者只有play_type，不能推所有调用者最终字段都等于公共默认。

本branch没有等待上报结果再完成响应。requesting此前已清0；
缺/data/cast失败不发成功observer。通过filter且weakstore有效才global(default)
处理model.items，再main queue通知snapshot observers
 didLoadCompleteWithResponse:type（0x10411a17c–0x10411a18c），type原loadmode。
具体初始请求0x10410a048：config nil或anchorItem非nil用mode0/tab1/nil requestConfig；
config存在且anchorItem nil才复制avid/cid/seasonId（不复制epid），安装weak self
closure0x10410c7b4→0x10410b688。这个具体filter所有正常返回均true
（0x10410b88c），包括weak self消失/config nil/items nil/未匹配；它匹配响应
playerArgs.avid/cid与**当时的live config**（0x10410b804/0x10410b840），
autoPlayNext且有下一项就取下一项，否则匹配项，存willLocateItem
（0x10410b958–0x10410b964）。因此不能把通用false分支当作此调用链的过期响应门禁。
tag/listener更新0x10410a2c4→0x104115f64复用lazy loader，写tag+28，
containsObject后才addListener（0x10411a290–0x10411a2c8）；本函数不取消在途请求、
清requesting、清其他listener或递增generation。其上游UI callback身份仍待定位。
实际consumer STSeriesBloc.didLoadCompleteWithResponse:type
0x104108340→0x1041078e8：items nil立即返回，非nil空数组仍走adapter及
didLoadedData=true；merge helper0x104107ae0只接受count>0。mode1/2先清
lastReportedItem及preload.cachePool；mode0/1/2替换storyItems，mode3前插并把
series.index加incoming count（0x104108130/0x1041081a8），mode4追加
（0x10410827c）。替换后优先willLocateItem，否则旧item，用isSameArcTo查找，
未找到取index0，再更新focus/UI（0x104107134）。外层mode<=2清willLocateItem，
调用可选adapter witness+50及helper0x1041085b0，最后setDidLoadedData:YES
（0x104107aac–0x104107ab8）。error consumer0x104108398只置didLoadedData=true，
没有替换列表/重试/持久存储写入；这些状态不能解释为网络成功或展示成功。
另有不同的anchor切换producer0x10410b328：已有isEqualTo匹配且index不同时
只经0x104109488/0x1040d096c本地定位；无匹配或已经当前index才复制
avid/cid/epid到requestConfig，raw2/tab1加载。其filter
0x10410bda8→0x10410b9ac确会拒绝：响应items无匹配→可选anchor.failded(model)
然后false；匹配→willLocateItem再true，weak self消失仍true。匹配helper
0x10410bc20→0x10410bae4先比较正epid，否则比较正cid，没有比较avid。
这条回调不能套用初始0x10410a048恒true filter的结论。
Series卡片曝光的producer另已接到实际上报入口，不能用SeriesLoader请求锚点替代。
公开listViewWillFocus0x10410aa94将index/focusType交helper0x10410befc
（0x10410aae8）；helper先取旧common.index，按旧index>新index写preloadMode
（0x10410bf74/0x10410bf80/0x10410bf90），检查storyItems.count>新index
（0x10410c038/0x10410c060/0x10410c064）。准入后先本地定位0x104107134
（0x10410c07c），再调用trackBloc.reportCardExposureWithPrevious:index:type:isFirst:
（0x10410c170–0x10410c1b4）：previous=旧index、index=新index、type=原focusType，
isFirst为当前lastReportedItem==nil（0x10410c194/0x10410c19c）。该body未写
lastReportedItem或等待上报回执；构造时该字段置nil（0x1041099a0/0x1041099a4），
mode1/2响应清零见前文，其他writer仍待核，不能把字段名当可靠一次曝光去重。

STBloc.trackBloc getter0x1043272dc携带STTrackBloc metadata accessor
0x1041f0558进入通用getter0x104327354，调用接收者metadata.+0x78
（0x104327388/0x1043273a4）；STBlocStore.trackBloc0x104327150也按同type resolve。
已定位唯一同selector实现STTrackBloc0x1041eede8→0x1041edf7c
（0x1041eee28）；实际STSeriesBloc class0x11fe2bd60继承STBloc0x11fe5dd18，.+0x78
静态槽正指0x105120c08；该函数weak-load Bloc.store（0x105120c48），存活才
0x105121b60→0x1051238f4（0x105120c60）。后者先按type查cached bloc
（0x10512391c），miss才调用目标metadata.+0x70创建（0x1051239dc/0x1051239f4），
此处STTrackBloc槽为0x1041f01b8，alloc/initWithStore后缓存
（0x1041f01cc/0x1041f01d8/0x105123a08）。已闭实际Series静态槽到指定TrackBloc
构造，store安装顺序/动态override仍另核。其type1按newIndex<previous
产生gesture2，否则gesture1（0x1041edfa0/0x1041edfa8）；type2→gesture3
（0x1041edfb0）；type0只有isFirst=true且newIndex==0才gesture0
（0x1041edfbc/0x1041edfc0/0x1041edfc4），其余type0仅诊断日志并返回，未知rawtype
走enum诊断/trap（0x1041ee098/0x1041ee09c）。不能将所有焦点回调算一次曝光。

实际事件builder0x1041ee0a0重新读取CURRENT dataBloc.current.item
（0x1041ee0ec/0x1041ee110），nil直接返回false（0x1041ee128/0x1041ee408），
不用调用入口的card对象。公开字段包括faid（status helper0x1040a975c，0x1041ee1b0），
该helper初次取BFCIDFA.idfaString（0x1040a97a0）、nil为空，缓存到status的
idfaString lazy槽（0x1040a97cc/0x1040a97d8），以后重用（0x1040a9778/0x1040a9788）；
已存在setter0x1040a980c/0x1040a9854可改该槽，调用方仍待核，未读取实际IDFA。其余
r_id=item.rid十进制（0x1041ee1e0/0x1041ee1fc）、is_full_screen=status.isLandscape
String1/0（0x1041ee26c/0x1041ee284）、position=CURRENT common.index+1十进制
（0x1041ee2fc/0x1041ee308/0x1041ee328）、story_gesture=上述gesture单字符
（0x1041ee354–0x1041ee360）、is_live=item.isLiving String1/0
（0x1041ee388/0x1041ee394）。avid取playerArgs.avid、缺playerArgs为0
（0x1041ee3dc/0x1041ee400/0x1041ee410）；simple_id/spmid/from_spmid重新取CURRENT
common对应字段（0x1041ee4c8/0x1041ee558/0x1041ee5ec），不是旧index对象快照。
另goto/track_id/unique_id分别来自item.cardGoto/trackid/pos_rec_unique_id
（0x1041ee644/0x1041ee69c/0x1041ee6fc）；view_permission为item.isPlayable的1/0
（0x1041ee770/0x1041ee77c）；highlight_cut_id正值才十进制、否则空
（0x1041ee7ac/0x1041ee7d8/0x1041ee7e0）；player_session_id沿当前player.context.tracker
（0x1041ee814–0x1041ee8a0），action_id沿BFCVCPVManager.pvUniqueID
（0x1041ee924）。本节只描述来源，不读取任何真实session/identity。

CURRENT currentTab==1才加Series专属collection_id（item.season.seasonId，缺失则
移除该key，0x1041ee9bc/0x1041eea04/0x1041eea30/0x1041eeae0）及space_type
（Series.adapter witness.+0x30，缺adapter则移除，0x1041eeb7c/0x1041eeb90/
0x1041eeba0/0x1041eec68）；其他tab跳过两字段（0x1041ee9c0）。最后将item.show_report
字典merge到已组字段（0x1041eecbc/0x1041eecf4→0x1041eee44）。该专门化merge
遇到已有key会release旧value、写incoming value（0x1041eef60–0x1041eef74），后续
迭代同样替换（0x1041eeffc–0x1041ef018），因此show_report覆盖同名默认字段；
缺失的key才插入，不能把上述默认来源当最终字段不可覆盖。构造BFCNeuronExposureEvent，eventId为
main.ugc-video-detail-vertical.0.0.show（0x1041eed00/0x1041eed5c），调用trackInstantly
（0x1041eed88），接前述Neuron policy1→采样/入队/编码/缓存/调度链。
这个业务调用返回值不能当服务器回执。space_type实际witness已接：conformance
0x1183cbf58将STSeriesAdapter nominal0x11962ecc8绑定STSeriesAdapterProtocol
0x11962ec38，witness0x11b2b3ed0的.+0x30→0x1040e6d9c；它取实际对象metadata.+0x70
（0x1040e6dc0/0x1040e6dc4），各adapter静态槽如下，返回Swift String，不是数字enum。

| factory tag | adapter / class | space_type getter / String |
| --- | --- | --- |
| 1 | STSeriesUpSpaceAdapter / 0x11fe2ba08 | 0x104103408 → `1` |
| 2 | STSeasonAdapter / 0x11fe2a770 | 0x1040e7a20 → `2` |
| 3 | STEpisodeAdapter / 0x11fe295c0 | 0x1040d7dfc → `2` |
| 4 | STRelateAdapter / 0x11fe2a1c8 | 0x1040e4a68 → `3` |
| 5 | STPageAdapter / 0x11fe29968 | 0x1040db054 → `4` |
| 其他 | STSeriesAdapter / 0x11fe2a508 | 0x1040e6c54 → 空String |

factory0x10410b000对应类型选择见前文，动态替换仍未运行；缺adapter时移除key与存在
base adapter写空String不同。全部Series日志producer及其他字段配置来源尚未全部闭合。

Series边缘加载的实际UI入口listViewDidFocus0x10410ab14→0x10410c308：
preloadMode0且adapter witness+40为true、count-index<=3→raw4/tab1；
preloadMode1且adapter+48为true、index<4→raw3/tab1。
listViewWillFocus0x10410befc在0x10410bf80–0x10410bf90根据旧index>新index
设置preloadMode1，否则0。adapter实际绑定0x104109b78经factory0x10410b000
创建tag1/2/3/4/5对应adapter，把selectedAction设weak self closure
0x10410c7bc（0x104109c50–0x104109c6c）→0x10410b2cc→上述anchor入口。
Page公开seriesPagesView:didSelectedItemAt:0x1040dd448→0x1040dcdd0
给anchor avid/cid及epid0；failed0x1040dd4c4→0x1040dd28c在weak adapter有效
且response.redirect.uri非空时BFCRouter.processUrl:animated:true
（0x1040dd39c），否则固定StoryRes字符串→center toast（0x1040dd428）。
Episode公开episodeListSheet:didSelectEpisode:route:avid:0x1040d8ed0→
0x1040d91b8先dismiss sheet，再给anchor avid/cid0、epid；failed
0x1040d9764→0x1040d8e18忽略响应model，weak adapter有效后直接使用捕获原始
route调用processUrl:animated:true（0x1040d8ea8），没有非空检查/response.redirect。
两种failed是响应目标缺失后的业务回调，不是transport error，也不在此重试请求。
引导计数另有比较差异：noclick入口0x101b581b4要求enable/disable、未点击、
config非nil及threshold>=1，RAM计数从<=999加1（封顶1000）；0x101b582fc
比较count与threshold，count>=threshold才raw3/forcefalse调用展示入口。
noInterest入口0x101b57fb4却在0x101b5816c比较threshold与count，b.lt返回，
因此threshold>=count才调用，不能按名称反写成达到阈值；传入guideType原传。
两者仍受上述eligibility，RAM计数不是持久daily count。真实closeButton
ivar0x1203585a8→Rx control event64（0x101b5b490）→0x101b5ff2c→onClose
ivar0x120358520→共同callback/hide helper0x101b5b85c，实际调用已证的
0x101b5f568→0x101b5a0ac关闭日期保存，随后hide；不在此写禁个性化偏好。

声音两项持久 Bool 的保存桥已闭合：BBListPegasusInlinePreferences 是 BFCPreferences
子类，属性编码 TB,D,N；动态 setter（0x1167d4b5c）查 selector→property key，
NSNumber Bool→_setObjectWithKey:value:（0x1167d34cc），更新RAM字典后
userDefaults.setObject:forKey:。suite 来自子类 configName 的类 description。
这证明设置值有即时内存更新与持久存储调用，不代表已经验证磁盘提交完成时机。
实时 mute singleton init（0x11419f300）只首次读取该存储；系统音量监听 callback
只发 old/new 通知，也不直接写 mute。首页 volumeDidClick:isMannual:
（0x113a99fdc）在 token.isValide 后把音量设为 mute?0:1，再调用共享对象
setMutePlay（0x113a9a058–0x113a9a074）；此入口没有写 cold 两项持久偏好。
新 API 因而可读取实时变化，同 API 缓存不刷新；不能宣称两字段每次切换同步。

autoplay setter 将2/4写底层1、1/3写2、10/11写3，其余0；server标志仅1/2/11为true。
因此用户明确选10/3/4会取消受服务器影响标志。请求最终编码经enum/table映射，不是
直接把底层 double_p=1/2/3发送。column 的另一字符串getter把0..4映射为2/3/2/3/2，
这是展示相关值，与请求column原始码不同；UI标题与实际排布仍需追调用方。

设置通知到刷新需要区分即时与延后：RefreshHelper订阅Column/VideoMode的ByUserAction
通知（0x101b65644/0x101b65718），只消费可cast Int64且分别3/4、11/12的userInfo.value。
0x101b647e0在pegasusIsShow=true时返回；false且latestConfig.mode_switch_refresh_exp
可castInt并等2时，operator+0x60先清理、+0x50派发原reason3/14，否则保存对应flag。
MainVM注册0x101a48f88明确将+0x50绑定捕获VM的0x101a5c404→0x101a4893c，
reason入MainApi+0x11；builder0x101a32cb0再读表0x1182c9138映射wire flush，
所以column reason3→flush2、video reason14→flush17。VM正在loading时拒绝派发。
不要将内部reason原值当成请求flush，也不把实验缺失等同2。

延后flag消费0x101b638a8对userHasChangeFormat走+0x50 reason3，对
playStyleManualChanged却走+0x30 reason14。+0x30绑定0x101a5c464→VM0x101a4fa88，
要求collectionView存在且!isLoading，保存reason、setContentOffset(0,-60,animated=true)，
延迟0.3秒callback0x101a5c758调用捕获collectionView.bfc_beginHeaderRefresh。
Header action0x101a3b7e8经0x101a37538取VC.viewModel、读取保存reason，
再调VM0x101a4893c，最终仍raw14→flush17，但存在loading/view/延迟与UI刷新条件。
这不是通知收到即无条件发RPC；operator绑定发生在VC lazy viewModel nil初始化分支。

延后消费的生命周期已闭合：VC.viewWillAppear wrapper 0x101a37608传key1，
viewDidAppear传key2；共用handler 0x101a37648向BBListPegasusEventDispatcher
（共享入口0x103d9fe54）发布该key与animated payload。RefreshHelper
0x101b654d4订阅同dispatcher的key1，closure 0x101b690ec→弱引用callback
0x101b6728c→0x101b638a8。因此这些flag在viewWillAppear消费，不能写成viewDidAppear。

声音偏好缺值还有条件性默认链：InlinePreferences未覆写defaultConfig，父类
0x1167d33cc返回nil；处理属性时缺省字典为空，NSUserDefaults缺值不会赋属性。
动态Bool getter仅查RAM字典，再对nil调boolValue得到false。因此无持久值且
没有其他先行setter时，inlineVolumeOn/hasHandledVolumeSetting都是false，生成
cold_state=2；实时singleton init反转inlineVolumeOn，得到mutePlay=true、inline_sound=1。
_didUpdateConfig（0x11419ed54）仅return，配置更新通知本身不改这两个Bool。
这不是所有账号、安装或首请求的恒定值证明。

自动画质的UI和保存还需区分：makeQualityData（0x114535648）给自动项
setIsAutoSwitch=true，加入quality list；didSelect（0x114536030）同auto/同qn时
早退，否则先走delegate，缺delegate再qualityProxy.changeQuality。正常播放container
把videoServiceClass配置成BBPlayerVideoQualityService，proxy按context配置取得服务。
changeQuality→_switchToExpectQn（0x11453d23c）仅needUpdate=true才调
updateUserQn:isAuto，再受manual.shouldMemoryQn门槛；
QualityHelper.shouldMemoryQn（0x11482146c）每次读在线String Memorable_qn→integerValue，
允许条件为threshold==0或signed threshold>qn，相等不存；nil/转0允许。自动选择绕过该门槛；needUpdate helper
（0x114539c18）由trial/VIP试用/familyBroadband状态决定。故临时切换、试用等
路径可以改变当前auto状态却不改持久autoQnEnabled。其他widget的context绑定和
代理内部转发仍未全部闭合，不宣称所有播放器入口统一。
青少年设置年龄不能从选择器缺省索引推请求常量：UserCenter.showAgePicker
（0x10f361268）构造1..17，age>0时defaultIndex=age-1，否则index16；completion
（0x10f36148c）把selectedIndex+1传Navigator（0x11596442c），构造PasswordVC
status11并setAge。nextStep该分支验证码/密码流程成功callback0x115977798
仅success=true才把捕获age写Manager；失败不写。同步模式状态0x1159613c4则
从teenagers模式模型.age取32位符号扩展后setAge，因此服务器也能覆盖。
这一同步callback不同于UI设置的successBool：SynchronizeApi0x11595cc70在RPC error
时向completion传(nil,nil)，无error则按模式名挑teenagers/lessons模型；Manager
callback0x1159613c4对teenagers模型没有nil门控，nil.age→0仍setAge。因此错误/响应
缺teenagers模式可能把本地年龄写0，不是自动保留旧值；尚未做运行时复现。
BFCRestrictedModeTeenagersPreferences的动态age类型Tq,D,N，configName
（0x115965870）常规按account.userID形成BFCTeenagersModePreferences-%lld，另有
一次flag归-0分支；七项defaultConfig不含age。动态Int64 getter0x1167d429c从RAM字典取对象后longLongValue，故无持久值且没有
先行writer时退0；不代表所有首请求都0。shared（0x1159657dc）once缓存账号suite实例；
resetPreferences有重建能力但未找到账号切换调用。localShared另once并设置一次flag
以创建suite-0，getAge使用shared而非localShared；不能据configName动态账号格式
宣称每次账号切换都已切换读取实例。
播放能力/画质与flush/pull等继续逐项归因；当前固定采集策略不能替代来源证明。

### Story 清晰度选择与偏好写入的独立执行链

Story分享菜单已有具体画质入口：沿前述shareChannelForModel: type−1跳表
0x119058d80，原始type18项raw54转0x113351e88，构造BFCShareCustomChannel，
公开key却为`kShareActionItemMiniScreen`（0x113351ed4/0x113351ed8），weak action
0x113353f9c（0x113351eb0/0x113351ed0/0x113351ee4）；以执行体核行为，不按key字面猜。
action weak-load service后，CURRENT selectVideoQualityBlock非nil才BLR
（0x113353fb0/0x113353fb8/0x113353fcc/0x113353fe8），随后独立报告
`main.ugc-video-detail-vertical.share-pannel.definition.click`
（0x113354018/0x113354024），不以面板实际显示为条件；弱service缺失也未见此体跳过
整个日志路径。RigthModule.makeShareService将weak module callback0x1132c2b3c
保存到该block（0x1132c279c/0x1132c27b0/0x1132c27cc），callback调用
_showVideoqualityPanels（0x1132c2b4c/0x1132c2b54→0x1132c3404）。后者CURRENT
storyContext.store.resolve(STQualityBloc)（0x1132c3424/0x1132c3438/0x1132c3448）
所得receiver调用showList（0x1132c346c），接下述具体列表/选择/writer/解析链。
availability固定allow-list也明确包含18（0x11335effc/0x11335f000），与19同走
isFunctionModelAvliable contains检验；实际菜单是否包含type18仍取决服务端model。
Store实例安装和运行呈现不由此静态接线单独证明。

实际列表model来源已闭：STQualityBloc.showList0x104176340调用builder0x104174f80
（0x104176354），再present helper0x104176378（0x10417635c）。builder先读
videoQualityService（0x104174fd0/0x104174fe8），从currentAutoQn/currentQuality取得
snapshot（0x104175420/0x104175434/0x104175438/0x1041756e0），逐项alloc
VKSettingView.TitleModel（metadata0x104b57048→class0x11ff09c68；0x104175714/0x104175724）。
每项callback context强捕获quality、弱bloc及snapshot Bool/qn
（0x104175dd8/0x104175df4/0x104175dfc/0x104175e04），thunk0x10417bc4c交model
virtual+0x1a8（0x104175e2c/0x104175e34）；该class slot0x11ff09e10→0x104b56610，选择
TitleModel.didClick ivar0x12049f4d0并存function/context pair
（0x104b56614/0x104b56618→0x104b56e8c/0x104b56ec8）。

TitleContent.setupViews0x104b58828→0x104b57a54（0x104b5883c）真实安装self为target的
tapContent: gesture（0x104b58770/0x104b58788/0x104b58790/0x104b587a8）。tapContent:
0x104b59e24选择didClick并交0x104b59e3c；CURRENT content.model必须非nil
（0x104b59e5c/0x104b59e60），CURRENT didClick func非nil（0x104b59e88/0x104b59e8c）
才BLR（0x104b59ec8），不把tapMore:的另一ivar算选择。thunk转0x10417a80c
（0x10417bc4c..0x10417bc58），弱bloc nil跳过（0x10417a84c/0x10417a850）；
selected quality.isAutoSwitch与captured原Bool均true则直接跳过
（0x10417a864/0x10417a868/0x10417a86c），两者均false且selected qn等于captured原qn
也跳过（0x10417a878..0x10417a898）；其他才didSelectQuality:
（0x10417a8ac）。因此下述点击日志不覆盖每次物理tap，该比较使用建表snapshot，
不是选择时重新读service.current。调用之后若weak swipeVC存在则dismiss并清weak字段
（0x10417a8bc/0x10417a8c0/0x10417a8d8/0x10417a8e4），不以authSelect/播放成功返回为
关闭门禁。分享菜单外层入口已如上闭；model→content的具体类型连接进一步定位：
VKSettingVC构造helper0x104b6db28保存传入section list（0x104b6db78），reload
0x104b6e930读取该list并render（0x104b6e964/0x104b6e9b0→0x104b6e8d8
→0x104b6ddc0）。section.items转换循环读取每个model metadata virtual+0x158
（0x104b6e728/0x104b6e7b4/0x104b6e7bc）。实际TitleModel class0x11ff09c68
槽0x11ff09dc0→0x104b56f28构造TitleComponent，+0x10强保存原model
（0x104b56f50），连同metadata/witness0x12049f6d0返回
（0x104b56f5c）。factory0x104cd1368调用该component witness+8
（0x104cd1384），实际0x11b2ff210+8→0x104b5a3b0→通用CellsBuilder
0x104cd2184。TitleComponent内容witness0x12049f670+0x10→0x104b5a294创建
TitleContent（0x104b5a2a4/0x104b5a2b8），+0x18→0x104b5a2cc取component原model
（0x104b5a2e0）交TitleContent安装body0x104b59094（0x104b5a2e8），保存
TitleContent.model（0x104b590c4/0x104b590cc）。具体model、component、content
不是凭同名推断。通用类型擦除链也已定位：CellsBuilder 0x104cd35c0取该component的
内容witness（0x104cd36b0），经0x104cd36fc→0x104cce33c（0x104cd3820）；
非AnyComponent分支创建ComponentBox并保存metadata/witness pair
（0x104cce410/0x104cce41c），box witness 0x11b30ac28的+0x18→0x104ccf578
→0x104cce940，取保存内容witness.+0x10并调用make（0x104cce95c/0x104cce998）；
box.+0x20→0x104ccf57c→0x104cce9b0先cast incoming content，成功才调用保存
内容witness.+0x18 update（0x104ccea84/0x104ccea8c/0x104cceab8/0x104cceac8）。
具体cell渲染helper 0x104cd2238在缺旧content分支调用box.+0x18 make
（0x104cd235c..0x104cd2380），挂载content后递归本helper
（0x104cd23c4/0x104cd23e8/0x104cd23f8）；已有content并通过其更新准入时调用
box.+0x20（0x104cd2304..0x104cd2334）。UICollectionViewAdapter的实际
cellForItemAtIndexPath wrapper 0x104cca234→0x104cc9d7c（0x104cca2b8），取得
cell后要求ComponentRenderable conformance及isMemberOfClass匹配；符合才调用
上述helper（0x104cc9f84/0x104cc9fa0），否则走注册/重新dequeue分支。
VKSettingVC的lazy adapter helper 0x104b6d284创建VKSettingVCFlowLayoutAdapter
（0x104b6d2b0/0x104b6d2b4）；其class 0x11ff0c7c8.+8→0x11ff255b8
UICollectionViewFlowLayoutAdapter，再.+8→0x11ff254a0 UICollectionViewAdapter。
具体dataSource绑定也已闭：VKSettingVC ctor body 0x104b6d684取上述renderer和
collectionView（0x104b6d724/0x104b6d72c），调用renderer virtual+0x80
（0x104b6d734/0x104b6d73c）。renderer的symbolic typeref 0x1196d6870实际为
Carbon.Renderer<UICollectionViewUpdater,UICollectionViewAdapter>；descriptor
0x1196979b4 vtable起word15，第二槽+0x80实现0x104cd3fbc。
该setter弱保存target（0x104cd3ff8）→helper 0x104cd3f00，从自身.+0x10取同adapter
（0x104cd3f44），通过Updater witness+0x20调用bind（0x104cd3f4c/0x104cd3f58）。
具体UICollectionViewUpdater conformance 0x118404070/witness 0x1204a98d0.+0x20
→0x104cd9e38→virtual+0x120（0x104cd9e4c/0x104cd9e50）；descriptor 0x119697b1c
vtable起word17，slot19正是0x104cd673c。它对原target设置同adapter为delegate及
dataSource（0x104cd675c/0x104cd6770），reloadData（0x104cd6780）并invalidateLayout
（0x104cd67a8）。因此此列表构造确有具体adapter接线，后续cell更新准入及呈现完成仍另核，
不把reload调用等同实际UIKit回调已发生。
此外render body 0x104b6ddc0要求当前target view及其window非nil
（0x104b6de00/0x104b6de28），才更新list/adapter并调用renderer
（0x104b6de54/0x104b6de84/0x104b6deec）；未挂window时直接返回，非无条件render。

STQualityBloc.didSelectQuality:0x10417a45c通过wrapper0x10417a468调用实际body
0x104179dcc（0x10417a49c）。必须weak layout.mainVC存在（0x104179e34/0x104179e44），
且playerBloc.videoQualityService非nil（0x104179e6c/0x104179e84）。先报告
main.ugc-video-detail-vertical.play-set-select.0.click，qn为incoming quality.qn的
Int64.description（0x104179f04/0x104179f20/0x104179fbc），之后才authSelect:
（0x104179ffc）；false直接退出（0x10417a000）。因此点击不是授权或切换成功ACK。
authSelect:0x104179d70实际body0x1041795a4（0x104179da0）先要求hasLogined，false
showLogin并返回false（0x104179604/0x104179608/0x1041797b4/0x1041797b8），包括自动选择，
不因expect 64的适配代码推匿名可成功切换。needVip=false跳过VIP helper；true要求
0x104179a44通过（0x104179618/0x104179628/0x10417962c），否则showVip:后拒绝
（0x104179a28）。helper检查currentUser.vip.isValidVip（0x104179abc），或item.owner.mid
与currentUser.mid的optional相等（0x104179bf8..0x104179c08），不观察实际MID；都不满足
时，存在mainVC/service且supports canTrialVipQuality而返回false会拒绝trial通路
（0x104179cac/0x104179cb8/0x104179cc4/0x104179cdc）；可trial通路还需
trialService.isQualityTrialAble:selected（0x104179cf8/0x104179d10）。nil mainVC/service
有独立分支，不概括为一律拒绝。auth随后若目标可trial，则checkAndStartTrialWithQuality:
必须非零（0x10417964c/0x10417965c/0x10417967c/0x10417968c）；二次trialService已nil
会返回当前nil值（0x104179668/0x1041797bc）。通过后如tracker存在，无论此前是否实际启动
trial，都发player.player.vip-qn-trysee-start.0.player、empty extended dict
（0x104179718/0x104179720/0x104179744/0x104179784），然后返回true
（0x1041797a0）；不能由此日志名推已经trial或播放成功。
权限通过后，如actual player.context.tracker存在，还发
player.player.clarity-type.0.player（0x10417a07c..0x10417a0d0/0x10417a2b4）：
qn为自动时String0、否则selected qn（0x10417a128..0x10417a174）；is_auto取反编码，
selected自动为0、手动为1（0x10417a190..0x10417a1a8）；from_is_auto按原currentAutoQn
同样编码（0x10417a1d0..0x10417a1e4），from_qn原自动为0、否则currentQuality
（0x10417a200..0x10417a240）。缺tracker不阻后续切换。

selected自动时，以hasLogined选expect 80/64（0x10417a300..0x10417a310），用available
quality list与canPlayVipQuality=false求findAdaptQuality，再修改incoming quality.qn
（0x10417a3b4/0x10417a3d8）；手动跳过该适配。receiver须respondsToSelector，才调用
changeQualityWithExpectQuality:preQuality:（0x10417a3ec/0x10417a404），preQuality来自可选
findCurrentQualityInfo（0x10417a018/0x10417a028）。实际STPlayerVideoQualityService方法
0x1041caaf0读取selected qn/isAutoSwitch（0x1041cab38/0x1041cab4c），进入0x1041cdfb8
（0x1041cab6c）。该helper匹配available list中qn（0x1041ce070/0x1041ce078），若匹配且
trialService.isQualityTrialAble为true（0x1041ce10c/0x1041ce11c），以canTrial helper
0x1041cb964的反值决定needUpdate（0x1041ce120/0x1041ce130）；未匹配、trialService缺失
或不可trial则needUpdate=true（0x1041ce138/0x1041ce140）。canTrial helper0x1041cb964要求hasLogined（0x1041cb98c/0x1041cb990），已有效VIP则false
（0x1041cb9e0/0x1041cb9f0/0x1041cb9f4）；否则取已有或resolve trialService
（0x1041cba04..0x1041cba2c），存在才返回trialAble（0x1041cba58/0x1041cba68），
缺失为false。因此该匹配目标可试用且当前可trial时needUpdate=false，不写偏好。

最终_switch(to:isAuto:needUpdate:preferToast:) body0x1041ca0f8要求目标quality存在
（0x1041ca30c/0x1041ca310），否则日志后返回。先写currentAutoQn
（0x1041ca3e4..0x1041ca3f4），needUpdate bit为true才调用偏好helper0x1041cd89c
（0x1041ca3f8/0x1041ca404）：自动传qn=0（0x1041ca3fc/0x1041ca400），在
BBPhoneMPStoryPreferences.shared非nil时写playQn=0并autoQnEnabled=true
（0x1041cd8f4/0x1041cd8f8/0x1041cd928/0x1041cd9cc）；手动必须
BBPlayerQualityHelper.shouldMemoryQn:返回非零（0x1041cd94c/0x1041cd950），才写
playQn与autoQnEnabled=false（0x1041cd998/0x1041cd9c8/0x1041cd9cc）。这沿用前述
Memorable_qn门禁，但receiver为Story preferences；未证明同步上传此local偏好。
之后才进入willSwitchQuality callback及实际切换分支（0x1041ca464/0x1041ca474..0x1041ca4d4），
故偏好更新不是播放成功回执。外层列表入口及present安装、trialService内部开始/失败生命周期，以及后续切换/失败如何更新CURRENT quality，仍分别保留待查。

清晰度切换的重新解析分支0x1041cd9f4要求service.parseModel非nil
（0x1041cda38/0x1041cda3c），以weak service和chosen qn/isAuto构造completion context
（0x1041cda60/0x1041cda7c/0x1041cda84）。它先就地修改同parseModel：preloadUrl=nil、
qn=chosen、isCantUseLocalCache=true、offline=false
（0x1041cda9c/0x1041cdab0/0x1041cdac4/0x1041cdad8）。若符合BBResolverUniteParms且
class为BBResolverBaseParsModel派生（0x1041cdaf4/0x1041cdaf8/0x1041cdb2c/0x1041cdb30），
还设playCtrl=1、qnPolicy=0、clientAttr=2（0x1041cdb48/0x1041cdb4c/0x1041cdb60/0x1041cdb74），curLanguage与
curLanguageType取CURRENT context.director.currentScene.response，相应来源nil则写nil/0
（0x1041cdc20/0x1041cddd8/0x1041cde8c/0x1041cdeb4），调用BBResolverUniteHelper
resolverWith:completeBlock:updateBlock:（0x1041cdf60，updateBlock=nil），接此前已闭Unite
请求/回退路径。失败该protocol/class门禁则优先parseModel.resolverClass非nil
（0x1041cdc7c/0x1041cdc80）调用其resolverWith（0x1041cdd00）；缺resolverClass时须
cast BBResolverBaseParsModel成功（0x1041cdd34/0x1041cdd38），才BBResolverHelper.
resolverV2With（0x1041cddb4/0x1041cddc0→0x1041cdf60），否则退出。三路共同completion
0x1041ce320→0x1041cc9fc（0x1041ce328），不在此构造独立Story quality HTTP endpoint。

completion须weak原service仍在且CURRENT context.playback存在
（0x1041cca48/0x1041cca4c/0x1041cca64/0x1041cca68/0x1041cca80/0x1041cca90）；
result非nil且result.videoInfo非nil才进入采用分支（0x1041cca94/0x1041ccab0/0x1041ccab4），
该分支没有先以error==nil门禁。先将response.qualityList替换availableQualityList并保存
videoInfo（0x1041cccd0/0x1041ccd00/0x1041ccd28），把response.item.streams追加到CURRENT
playback.currentItem（0x1041ccd84..0x1041cce64）；然后以response.currentQn而非
captured expect qn选择实际切换（0x1041ccf28/0x1041ccf58/0x1041ccf74）。特殊本地切换
helper0x1041cc110通过则走0x1041cc834，否则updateItemParams、replaceWithIjkItem、
bindCallBackFor等（0x1041ccfa0/0x1041ccfd0/0x1041cd03c）；不能从解析非nil推渲染成功。

result/videoInfo缺失走解析失败日志（0x1041ccb00..0x1041ccb84），取CURRENT quality，
error可转换为NSError类时提code，否则code=0（0x1041ccb9c/0x1041ccbf0/0x1041ccc08/
0x1041ccc20/0x1041ccc28），交反馈helper0x1041cbd24（0x1041ccc38）。此completion没有
恢复已写的Story playQn/autoQnEnabled、currentAutoQn或已改parseModel字段；无generation/
原item identity比较，观察到的是CURRENT playback，不推运行时必有乱序。
本地切换helper0x1041cc834须context/playback非nil（0x1041cc87c/0x1041cc8a4），手动模式
先setCurrentQuality（0x1041cc8a8/0x1041cc8bc），自动跳过；随后调用playback.
changeQualityWith:playerItem:isDashVideo:isAutoSwitch:autoSwitchMaxQn:autoSwitchMinQn:userQn:
（0x1041cc970），userQn从Story preferences.playQn取、shared nil为0
（0x1041cc910/0x1041cc944）。这些方法调用返回不等播放回执。
本地可切换helper0x1041cc110的布尔组合已核：availableQualityList必须含incoming
qn（0x1041cc1c4/0x1041cc1c8/0x1041cc1cc），CURRENT quality必须能通过
0x1041cb538从同list匹配（0x1041cb560/0x1041cb5f8/0x1041cb600）；无list/匹配返回false。
它要求videoInfo.isDashVideo=true（0x1041cc228..0x1041cc250），目标与当前quality都
isLocal=false（0x1041cc260..0x1041cc27c）、noRexcode=false
（0x1041cc28c..0x1041cc2a8）、isHDR=false（0x1041cc2b8..0x1041cc2d4）。还要求
CURRENT context.playback.currentItem.ijkItem非nil，且其
isExistSpecialQualityStream:(incoming qn)=true（0x1041cc2f0..0x1041cc3a4）；
缺context/playback/currentItem/ijkItem令此gate失败。videoInfo.drmTechType==1另拒绝
（0x1041cc3cc..0x1041cc3f4）。最终将非DASH、任一local/noRexcode/HDR、缺special
stream的低bit OR（0x1041cc3f8..0x1041cc408），全为false再返回(drmTechType!=1)
（0x1041cc468）；videoInfo nil也返回false。这里保留公开属性拼写与原始DRM值，
不猜DRM协议名；player后续失败通知仍待核。

## 设置配置同步、上传与缓存

### Distribution 通用偏好

BBCDeviceConfig.init（0x114fa9204）建串行request/file队列，retryCount=0、
debounce=1秒、generation=0；启动加载ability/userOperation/universalConf及两种diff
PB缓存，universalBlocked则新建空RAM集合。缺失/空/解析失败的universal缓存退
新空UserPreferenceReply。这里只研究路径与代码，未读取真实配置文件或账号值。
cleanUniversalConfigCache（0x114fa93a0）仅清blocked集合，不删除配置、diff或磁盘；
因此此前账号观察者调用clean不能概括为“登录切换清空所有偏好”。

startCloudSync（0x114fa92d0）先syncDiff，completion拉PlayConf和UserPreference；
startUniversalConfigSync（0x114fa9348）只在该completion拉后者。completion即使
上传失败或debounce generation已过期仍执行，不以远端确认成功作为拉取门槛。
requestRemoteUniversalConfig（0x114faa4f8）发Distribution.UserPreference，
UserPreferenceReq descriptor（0x114faca38）零字段；Reply只有field1重复Any
preferenceArray。handler error非nil直接返回，没有业务重试；nil error则copy响应、
merge并排队raw3持久化，该handler没有另一层nil-response或业务status检查。

merge（0x114faac50）在blocked为空时替换universalConf；非空则保留本地blocked
类型，接收远端未blocked项，匹配键为Any.typeURL.lastPathComponent。设置写入
setUniversalConfig:typeUrl（0x114fab274）却按containsString(typeUrl)替换当前
和diff中的旧Any，并将typeUrl.lastPathComponent加入blocked。两处匹配规则不同。
新对象用GPBAny.pack(message,error:nil)，没有处理pack错误；getter
（0x114fab774）锁内copy数组后解锁，取首个substring匹配Any并unpack(error:nil)，
不查远端或diff。typeUrlForClass（0x114fab0b4）按类名缓存descriptor.fullName，
不是自行拼type.googleapis.com URL。

设置wrapper已连接这层：PegasusMid/Device/DeviceWithoutFplocal、CloudPlay/
MidPlay/Play/SpecificPlay、DynamicDevice、OtherSettings、Privacy/MidPrivacy、
SearchDevice的uploadConfig均尾调setUniversalConfig:typeUrl。例如
PegasusDeviceWithoutFplocalConfig.cachedConfig（0x114898fb8）/upload
（0x114898ff4）用完整PB名bilibili.app.distribution.pegasus.v1.
PegasusDeviceWithoutFplocalConfig读写。不能据Objective-C类名将这些偏好上传
误作设备指纹登记；wrapper名称中的Mid也不足以证明磁盘按MID分区。

syncDiffToRemote（0x114fa9eb8）原子递增generation，1秒后在request队列比较；
旧generation跳上传但仍completion。最新generation先处理PlayConf diff，再仅
universalDiff非nil且preferenceArray_Count>0时发SetUserPreference。
SetUserPreferenceReq（0x114facb0c）有field1重复Any preferenceArray、field2
extraContext/message；该builder只赋field1。发送helper（0x114faa7e4）等待
semaphore最多20秒，但忽略wait返回，没有合成超时NSError。非nil响应且nil error
才把universalDiff换为新空Reply并重置共享retryCount；失败保留diff，只有非nil
NSError调用retryLater。超时后response/error仍nil本身不安排重试。
成功清理的是当时的整个当前diff（0x114faa2bc–0x114faa2d8），没有与请求快照
做版本比较。generation仅延迟block入口检查；请求构造/等待期间setter仍可改diff。
因此并发新修改的保留不能由debounce推定；此处记录静态清理边界，未复现实际竞态。

retryLater（0x114faa9ec）在unsigned count<=4时先+1，再10秒global queue重入
syncDiff（另受1秒debounce）；count已有5不再安排。Play和Universal两种成功都
重置同一计数，同一pass的两种error也可各自增加/调度，不能写成单个Universal
请求固定五次尝试。排队后身份/配置变更的更高层处理仍需追踪。

持久化（0x114fa95b4）在file queue执行时才copy模型，调用Tools.syncMessage，
忽略write BOOL后仍通知delegate。路径由NSSearchPath raw14/userDomain1取得目录
再附DeviceConfig，不在这层附账号MID。模型映射为1:cloud_config、2:cloud_op、
3:cloud_universal_config、100:cloud_diff、101:cloud_universal_diff。
PB.data非空原子写；空data删除文件；nil snapshot跳写。因此成功上传后的新空diff
可删除diff文件，而不是nil对象触发删除。main异步syncDeviceConfigWith通知表示
写入尝试完成，不证明磁盘成功。ConfigureHandler（0x10068b3e4）消费通知后取
isAlbumAirdropEnable，写share extension suite的shareExtensionAirdropEnable字符串0/1；
这是派生设置同步，亦非设备登记。

该ConfigureHandler确有注册：ShareIntentService.updateDataInfoAndAddAccountObserver
（0x1006971a8→0x100696db4）调用BBCDeviceConfig.addDelegate(self.configureHandler)
（0x100696fa8）。isAlbumAirdropEnable（0x10069669c）仅hit_album_airdrop_experiment
命中时读MidImConfig.canAirdropToIm.value，缺消息false；setter同实验且只改value
再upload，未写lastModified/defaultValue/exp。MidImConfig实际PB全名为
bilibili.app.distribution.home.v1.MidImConfig，不能据类名猜其他包。

StoryStatus另消费raw3通知（0x1132e7650），首次迁移0x1132e6ecc有进程once byte：
仅登录、StoryConfig非nil、gestureType.lastModified<=0且本地hadManualSetGestureMode
才迁移，local.gestureMode==1→remote.value2，否则1；只setValue/setGestureType/upload，
返回即设once，不等网络成功。supportedPlayControl0x1132e7078在登录且remote时间戳
>=1时用remote.value==2，否则local.mode==1。手动更新0x1132e7184先尝试remote（登录
且已有root才上传），再写本地manual标记/mode。这条链消费StoryConfig，非MidStoryConfig；
未设lastModified，不能依据字段名字推断客户端上传时自动更新时间戳。

新的Story bloc手动setter应独立于旧StoryStatus：STSingleDoubleGestureBloc.
updateGestureMode: 0x10419eb58→0x10419e754（0x10419eb74）。该helper先toast
（0x10419e7b0），取trackBloc并发点击事件
`main.ugc-video-detail-vertical.play-set-type.0.click`（0x10419e7e8/0x10419e8f4），
`play_set_state`=输入EXACT1时String2、否则String1
（0x10419e840/0x10419e848/0x10419e864），字典经此前十字段公共helper
0x1041efa34（0x10419e890）。这是writer之前的独立日志dispatch，不以Universal ACK为门禁。
然后CURRENT hasLogined（0x10419e93c/0x10419e940）为true才取StoryConfig.cachedConfig
（0x10419e958/0x10419e95c）；nil时实际alloc/init新StoryConfig
（0x10419e968/0x10419e970/0x10419e97c），与旧writer仅已有root的门禁不同。
读取gestureType（0x10419e984/0x10419e98c），setValue同映射2/1
（0x10419e9a0/0x10419e9a4/0x10419e9a8），setGestureType后uploadConfig
（0x10419e9b0/0x10419e9bc/0x10419e9c4/0x10419e9cc）。正常缺失message由前述GPB
autocreate语义处理，不能套用异常nil指针路径。该body未写lastModified/defaultValue/exp，
也没有等网络返回；后续getter若时间戳仍不满足>=1，继续采用local分支。
无论登录与否，随后取Story preferences.shared，非nil时设置hadManualSetGestureMode=true
（0x10419ea14/0x10419ea1c/0x10419ea24/0x10419ea28），另重新取shared并setGestureMode原始输入
（0x10419ea34/0x10419ea50/0x10419ea54/0x10419ea58）；没有相等旧值短路。
其gestureMode属性TQ,D,N（0x11f0fb5e8），与之前Bool模式PB的raw值不可互换。
gestureList wrapper0x10419e6e0→builder0x10419dca0（0x10419e6f4）实际创建
DetailModel（metadata accessor0x104b2fcac→class0x11ff04590）。两个模型捕获weak bloc，
通过metadata+0x1d0安装didClick：第一callback0x10419ed58
（0x10419e1c8/0x10419e1d8/0x10419e1dc/0x10419e1e0），第二0x10419ed74
（0x10419e494/0x10419e4a4/0x10419e4a8/0x10419e4ac）。该槽0x11ff04760指向
0x104b2ebb8，明确选择DetailModel.didClick ivar0x12049db28，转0x104b2f620，
写function/context pair（0x104b2f65c）。第一thunk传原始值0
（0x10419ed64/0x10419ed68），第二传1（0x10419ed80/0x10419ed84），同helper
0x10419e600 weak-load bloc（0x10419e634），非nil调用updateGestureMode:
（0x10419e640/0x10419e648/0x10419e64c）；不是从选项文案猜枚举。
具体DetailContent.setupViews 0x104b31720→0x104b308a4安装self.tapContent: gesture
（0x104b31644/0x104b31664/0x104b3167c）。tapContent:0x104b32e70→0x104b335c4
（0x104b32e9c）读CURRENT model，nil跳过；CURRENT model.disable低bit为true则返回
（0x104b335e0/0x104b335e4/0x104b335f8/0x104b335fc），否则读didClick pair并BLR
（0x104b33638/0x104b33640/0x104b3364c）。因此组件物理action、模型callback与writer
有具体接线；此处未将组件实际展示/运行或所有gestureList上游入口算作已验证。

Story handleShareWithStoryItem:season:shareSuccessBlock:coinSuccessBlock:likeSuccessBlock:
0x11334fa98确实把callback0x1133511dc交operation.canonizeChannels返回的block
（0x113350310/0x11335033c/0x113350360/0x113350388），不是孤立getShareActionItems方法。
callback捕获weak service（0x113351204）、原始输入storyItem与season参数：
incoming x2 retain为x25（0x11334fae0/0x11334fae8），写block+0x20
（0x11335036c/0x113350378）；incoming w3保存stack+0x6c
（0x11334fac8），再byte写block+0x30（0x113350364/0x113350368）。若captured
season byte==1且原始storyItem.season非nil（0x11335120c/0x113351214/0x11335121c/0x113351230），
直接返回incoming channel list（0x113351238/0x1133512f0），不重排或装本地actions。
否则新建BFCShareChannelList，incoming aboveChannels.mutableCopy追加incoming
belowChannels（0x113351258/0x113351268/0x11335127c/0x113351294），copy后设新above
（0x1133512a4/0x1133512b4）；weak service.getShareActionItems设新below
（0x1133512c4/0x1133512dc），返回新list。此门禁读取原始输入item，而getShareActionItems另读CURRENT service.storyItem；
两者不是同一时刻的快照，不能泛化所有season菜单均有本地type19。
实际入口取BFCShare.operation（0x11335014c/0x113350150），其getter
0x115ee3a80返回global block，invoke0x115ee3a8c构造BFCShareSession后明确alloc
BFCShareOperation（0x115ee3b28/0x115ee3b34），不是仅凭同名方法选Swift operation。
initWithSession:0x115ee5e48把BFCShareModel保存operation+8（0x115ee5ea4）；
canonizeChannels setter block0x115ee7968把传入callback保存operation+0x20
（0x115ee7980/0x115ee7988）。execute的菜单处理body0x115ee98e8中，默认list分支
0x115ee9a4c和服务端list构造分支0x115ee9c04均读取此槽并调用callback
（0x115ee9a60/0x115ee9a70；0x115ee9c28/0x115ee9c38），返回list复制到
operation.model.channelList（0x115ee9aa4/0x115ee9c6c）后才presentController
（0x115ee9ab4/0x115ee9cc0）。callback实际消费时机已定位；外层execute wrapper
分享channel请求的公共参数链已具体接线：execute block 0x115ee8e40取BFCShareApi.get
（0x115ee8f24），传公开path `x/share/channels`（0x115ee8f40/0x115ee8f44）。get block
0x11622c120实际alloc/init BFCShareApiOperation并setPath:（0x11622c144/0x11622c150），
不在此显式setMethod。参数来自operation.model（非canonizeBlock）及其session：

| 参数 | 来源/构造 | 参数写入地址 |
| --- | --- | --- |
| share_id | model.session.shareId | 0x115ee8fb8 |
| oid | model.session.oid | 0x115ee9004 |
| buvid | BFCShareBuvidServices.buvid | 0x115ee9040 |
| share_origin | model.session.shareOrigin | 0x115ee9084 |
| sid | model.session.sid | 0x115ee90d0 |
| spm_id / from_spmid | model.spmid / model.fromSpmid | 0x115ee910c / 0x115ee9140 |
| panel_type | static CFString `1`，slot 0x11d0454f0→0x11d0d1f30 | 0x115ee9164 |
| share_session_id | model.session.identifier | 0x115ee91a0 |
| object_extra_fields | model.objectExtraFields.yy_modelToJSONString | 0x115ee91ec |
| trigger_parameter | NSNumber(unsigned model.guideTrigger).stringValue | 0x115ee924c |

setParams block接完整map（0x115ee926c），timeout=5.0秒（0x115ee9294/0x115ee9298），
describe BFCShareChannelInfo（0x115ee92bc/0x115ee92d0），安装response callback
0x115ee95e0（0x115ee930c/0x115ee9360），实际invoke async block（0x115ee9384）。
没有读取任何标识符实际内容。
async body 0x11622c568要求CURRENT Injector.delegate存在且支持apiBaseHost、
optionsWithBaseUrl:、requestWithOptions:、modelWith:mappingClass:isArray:isOptional:
（0x11622c5b8..0x11622c608）；取host/path组成 `https://%@/%@`
（0x11622c618/0x11622c62c/0x11622c644/0x11622c64c），不在此硬编码最终host。
传optionsWithBaseUrl:（0x11622c664），params先appendShareSessionExtraParams
（0x11622c6a0）再setParams（0x11622c6b8）。此helper仅session_id非空且delegate支持
shareSessionService时取getExtraParamsWithSessionId（0x11622e0cc/0x11622e0e4/
0x11622e100），先add extra、后add调用方原params（0x11622e120/0x11622e134），
所以相同key调用方覆盖extra。extra具体schema/生产时点待核。
仅uppercase(method)==POST才setRequestMethod raw1（0x11622c6f8/0x11622c71c）；
GET具体options默认需另核，不能以日志fallback `GET`代替sender配置。
非零timeout才setTimeoutInterval（0x11622c728/0x11622c73c）。模型描述设置path `/data`、
class=BFCShareChannelInfo、isArray=false/isOptional=false（0x11622c744..0x11622c760），
通过delegate requestWithOptions取request（0x11622c7b8），安装completion/error/
preProcessRawData handlers（0x11622c800/0x11622c830/0x11622c860），requestAsync
（0x11622c868）。这是一条静态发送连接，不证明运行请求成功。
completion 0x11622ca58要求CURRENT operation.responseBlock存在，读取mapped result
的 `/data`键，以error=nil、model=该值调用（0x11622ca90/0x11622cab4/0x11622cad4），
不额外要求model非nil。error handler 0x11622cafc同样读取CURRENT responseBlock，
传incoming error和model=nil（0x11622cb4c/0x11622cb68/0x11622cb70）。raw preprocessor
0x11622ccb4仅JSON解析用于日志，最终返回原incoming data
（0x11622cd00/0x11622ce40/0x11622ce58）；业务code转换在具体request/backend继续核。
ShareBaseModule实际initializer 0x10018cda8分配ShareCoreInject
（0x10018cdbc/0x10018cdcc），设置同对象为Injector.delegate和arguments
（0x10018cdf0/0x10018ce04）。setter 0x11622dfa8用storeStrong写global
0x120e67210，getter 0x11622dfb8读同槽；不以BSS推运行时对象。
缺delegate或必需selector不支持时只记录注入失败日志并返回
（0x11622c9f0/0x11622ca0c/0x11622ca50），该分支不调用responseBlock；所以不自动
推导execute group已leave或fallback菜单已经触发。另一group participant也已定位：
operation.prepareBlock非nil时enter并传completion 0x115ee98e0
（0x115ee93f0/0x115ee93f8/0x115ee9418/0x115ee9440），其完成时点与channel response
分开；provider具体body继续核。
ShareCoreInject.apiBaseHost 0x1001887fc→0x1001886e8用config.getStringForKey
`share.api_base_host`（0x100188770/0x100188798），返回nil才fallback公开
`api.bilibili.com`（0x1001887b0/0x1001887d4），空字符串不触发nil fallback。
其options/request/model分别通过依赖类method转发
（0x1001888d4/0x1001888fc/0x100188a20/0x100188a30/0x100188afc/0x100188b38），
这些转发的依赖类型缓存与公共API层相同：constructor初始化
_apiOptions/_apiRequest/_apiModelDescription时用0x120280d90/0x120280d98/0x120280da0
（0x100187444/0x1001874ac/0x100187514）。既有ApiClientModule provider对应
BFCApiOptions/BFCApiRequest/BFCApiModelDescription，因此此native绑定上的channel请求
进入前述公共签名、header、gateway及ORM链；动态重绑定仍保留。BFCApiOptions默认
requestMethod=0→公共builder GET的规则适用，不能排除后续injection改写。
_apiErrorDomin使用cache 0x120293aa8（0x10018757c），相对type为
So24BFCApiRequestErrorDomain_pXp；ApiClientModule.register以provider witness
0x120497280注册（0x1049be7b4/0x1049be7dc），其+0x10→0x1049be010明确返回
BFCApiRequestErrorDomain classref 0x11f7be1a8（0x1049be02c/0x1049be034）。
ShareCoreInject.isForbiddenAPIError: 0x100188d88→0x100188c04比较error.domain与此类
nonZero domain（0x100188c30/0x100188cc0/0x100188d1c），相等才检查error.code
==110000（0x100188d44/0x100188d54/0x100188d58/0x100188d5c），其余false。
不是所有非零业务码、网络错误或未登录错误都禁止菜单；本地后续complete error −1012
与原server code110000分开。ShareCoreInject别的API错误加工、channel模型字段映射及
session extra schema继续核。

0x115ee8df0捕获原operation（0x115ee8e28），执行block 0x115ee8e40把同operation
交group notify block（0x115ee9470/0x115ee9478），明确在main queue等待group
（0x115ee94ac/0x115ee94b8）。notify先dismiss loading（0x115ee9908/0x115ee990c），
operation._terminated byte+0x49低bit为true便返回（0x115ee9914/0x115ee9918；
ivar descriptor 0x11f8b1c74）。非terminated路径读保存error byref
（0x115ee9938..0x115ee9944）；有error才调用BFCShareApi.isForbiddenError block
（0x115ee9950/0x115ee9970），false走上述default list（0x115ee9980→0x115ee9a48），
不是所有请求失败均退出。forbidden true则toast localizedDescription
（0x115ee9998/0x115ee99b0），若model.completeBlock存在，调用raw0及由rawcode−1012
构造的本地error（0x115ee99d8/0x115ee99f4/0x115ee99f8/0x115ee9a18），不呈现菜单。
isForbiddenError实现 0x11622c1e0要求error非nil且CURRENT BFCShareInjector.delegate
respondsToSelector:isForbiddenAPIError:（0x11622c1fc/0x11622c220/0x11622c230），
才调用delegate（0x11622c24c），否则false（0x11622c260）；具体ShareCoreInject规则见上述110000/domain门禁。
无error才按operation._disableTitle byte+0x48（descriptor 0x11f8b1c70）选择title
（0x115ee9a2c..0x115ee9b1c）并转换服务器above/below lists。响应callback
0x115ee95e0有error只保存error（0x115ee9618..0x115ee9634），无error则分别保存
aboveChannels/belowChannels/text（0x115ee963c/0x115ee9664/0x115ee968c）及
extra.quick_message_on（0x115ee96b4/0x115ee96c4/0x115ee96d0）；只有后者==1
才group enter并requestShareList（0x115ee96e8/0x115ee96f4/0x115ee974c），随后本请求
group leave（0x115ee975c）。这些消费及等待点不是服务器业务ACK；具体HTTP解析、
channel转换/过滤和其他group participant仍继续核。

服务器菜单转换与Story追加的先后进一步明确：above/below各先交group helper
0x115ee9cf8（0x115ee9b5c/0x115ee9b70）。它按输入顺序查看当前/下一项category
（0x115ee9dac/0x115ee9dbc/0x115ee9df4），连续category相等且下一项category非空时
暂存group；边界有暂存项则追加当前项，构造BFCShareOnlineChannel，把group copy存
stateArray（0x115ee9e30/0x115ee9e3c/0x115ee9e5c/0x115ee9e78），key取首项category、
name/image/picture/textColor取首项（0x115ee9ea0/0x115ee9ec8/0x115ee9ef0/
0x115ee9f18/0x115ee9f40）；无暂存group则原项直接追加（0x115ee9f74/0x115ee9f7c）。
末项用fresh空OnlineChannel作为next sentinel（0x115ee9d80/0x115ee9d8c），非全局按key重排。
随后callback 0x115ee9fd4分别过滤转换后的above/below
（0x115ee9be8/0x115ee9bfc）：逐channel.key调用operation.channelIsAvailable:
（0x115eea080/0x115eea098），true才append（0x115eea0a8/0x115eea0b4）。
该过滤先于BFCShareChannelList构造及Story canonize callback
（0x115ee9c04/0x115ee9c38）；不能把Story在canonize中追加的custom key自动套用
此前的服务器channel过滤。
availability body 0x115ee66c8对微信/QQ等指定channel有对应平台isAppInstalled门禁
（0x115ee675c/0x115ee6774/0x115ee67e0/0x115ee67f8），随后还要求固定allow-list
contains key（0x115ee6978）。该列表initializer 0x115ee69d0以89项公开String构造并存
global 0x120dd1e40（0x115ee6f00/0x115ee6f04/0x115ee6f18），包含公开
`PLAY_SETTING`、`PLAY_MINISCREEN`（静态String slots 0x11d055170/0x11d0551a8），
与Story自定义literal `kShareActionItemPlaySetting`/`kShareActionItemMiniScreen`不同。
未读取运行时安装状态或该global实际值；各平台完整sender/全部列表项仍另核。

Story分享服务有具体gesture面板producer，与前述未闭的selectPlayModeBlock菜单项区别：
getShareActionItems 0x113351b24要求CURRENT storyItem非nil，按其share_bottom_button顺序
逐model调用shareChannelForModel:，只有非nil返回才append
（0x113351b54/0x113351b68/0x113351b9c/0x113351c00/0x113351c10/0x113351c1c）。
shareChannelForModel:0x113351cac先要求BBStoryPanelsHelper.isFunctionModelAvliable:
（0x113351cec/0x113351cf0），再按CURRENT model.type−1查20项u16跳表
0x119058d80（0x113351d84..0x113351dac）。原始type19项目标0x1133521c8，创建
BFCShareCustomChannel，以公开key kShareActionItemPlaySetting（0x113352218）和weak
service action0x113354044初始化（0x1133521f0/0x113352210/0x113352224）。
该action weak service非nil且CURRENT selectPlaySettingBlock非nil才BLR block
（0x113354058/0x113354060/0x113354068/0x11335407c/0x113354094/0x113354098），
随后独立报告`main.ugc-video-detail-vertical.share-pannel.play-set.click`
（0x1133540c8/0x1133540d4），即使block缺失也仍有该日志路径；weak service不存在则不报。
可用性helper0x11335edb4实际把model.type NSNumber化后在avaliableFucntionTypes中
contains（0x11335edf4/0x11335ee0c/0x11335ee24），不是远程Bool配置读取；后者
0x11335ee50的固定array含19（0x11335f014/0x11335f018/0x11335f044/0x11335f0a4），
故普通type19通过此静态allow-list。菜单subtitle另取CURRENT storyContext.status.
currentGestureMode（0x113352234/0x113352244/0x113352254）交metaForGestureMode:
（0x113352264→0x11335e4d0）；按gesture值0取StoryRes36、非零取39
（0x11335e69c/0x11335e6a0/0x11335e6b0），遍历model.button_metas找button_status
等于该resource text（0x11335e53c/0x11335e594/0x11335e5a8）；无匹配时取firstObject
（0x11335e5f0/0x11335e600），空数组则nil。这是动态文字选择而非writer枚举映射。
服务端是否提供type19仍另核，不将type表等同每次菜单显示。
presentController按BFCShareConfigV2.enableNewSharePanel选择BFCShareControllerV2
或BFCShareController（0x115ee5f74..0x115ee5f98），同一model通过setModel:
（0x115ee5fb4）传入，再presentViewController（0x115ee6068）；不读取当前开关值。
该开关getter0x1162277f4只调用global block0x120e671f8；setter
0x11622780c复制外部block入此槽（0x116227824），不把nil或BSS内容当当前配置。
ShareModule安装helper0x10018ca88选block0x1001870dc
（0x10018cd48/0x10018cd80）。该block在bfc_isIPad=true时直接返回false
（0x100187104/0x100187108/0x10018710c），否则解析DeviceDecisionService依赖
（typeref0x1196beb30、0x10018717c），CURRENT getBoolForKey
`dd_share_poster_new_ui`、defaultValue=false（0x100187188/0x1001871a8/0x1001871b4/
0x1001871b8），返回结果（0x1001871d8）。因此面板选择有DD动态读取，未读取实际值；
实际初始化任务provider也已定位：184项Runnable公开名清单index160/slot
0x120274550为ShareModule._$GripperRunnableTaskProviderShareBaseModule。metatype
accessor0x10018d20c返回class0x120293308；conformance0x11825cf60、witness
0x11b0b82d0+8→0x1001866c4以once0x12089af78取task array0x121064e00，
initializer0x100186664保存entry metadata0x11b0b82f0/witness0x11b0b82a0
（0x100186694/0x1001866a0）。entry witness+0x20→0x100186644返回公开task名
ShareBaseModuleModuleInitialize，+0x28→0x100186660尾调0x10018cda8，后者明确调用
上述安装helper0x10018ca88（0x10018ce08）。trigger/thread getter分别使用既有
moduleInitialize/main producer（0x100186508/0x100186520）。此为具体生命周期静态
接线；公共dispatcher准入仍适用，后续getter替换与运行执行不由清单单独证明。
V2 collection选择入口0x115f07b74同样取model.channelList.allChnannels或分组channel
（0x115f07c44/0x115f07c54/0x115f07c74/0x115f07c1c），交clickOnChannel:
（0x115f07cac）；其click入口0x115f07cf0以channel.key调用同model.clickBlock
（0x115f07d50/0x115f07d98），许可后通用路径performClick
（0x115f07fe0）。Story实际onClick安装的callback0x113351318
（0x113350a20/0x113350a40/0x113350a70）由BFCShareOperation setter block
0x115ee7e0c保存operation.model.clickBlock（0x115ee7e20/0x115ee7e28）。callback先
reportShareClickWithChannel:avid:（0x113351348），再CURRENT hasLogined
（0x113351354），登录则true；未登录时仅channel.key等于公开biliIm或biliDynamic
（0x11d055088/0x11d055080，比较0x113351374/0x11335138c）返回false，并标记捕获的
共享Bool（0x113351394..0x1133513a4），其他key仍true（0x11335135c）。所以type19
play-setting不会仅因未登录被此callback拒绝；不能把分享登录门禁泛化所有自定义项。
旧Controller collectionView:didSelectItemAtIndexPath:0x115ef60f4按实际collection
取model.channelList.allChnannels或分组channel，再clickOnChannel:
（0x115ef61bc/0x115ef61cc/0x115ef61fc/0x115ef6224）。click入口0x115ef63e8
若有model.clickBlock先传channel.key，返回低bit为false绕过执行
（0x115ef6448/0x115ef6490/0x115ef64b0），其后还存在青少年限制及特定key分支；
通用允许路径调用performClickWithChannel:isMessage:（0x115ef66d8）。
该执行器0x115ef0e18明确isKindOf BFCShareCustomChannel
（0x115ef1038/0x115ef1048/0x115ef104c），捕获原channel后把completion
0x115ef1e18交dismissWithCompletion:（0x115ef106c/0x115ef1088/0x115ef10a0）。
completion读取原channel.action并直接BLR（0x115ef1e38/0x115ef1e48/0x115ef1e4c），
没有action非nil防护；随后若model.completeBlock存在才调用raw1、nil error
（0x115ef1e70/0x115ef1e8c/0x115ef1e90/0x115ef1e94）。V2独立执行器
0x115f028e4同样识别该custom class、交completion0x115f038e4
（0x115f02b04/0x115f02b38/0x115f02b6c），后者action BLR
0x115f03918、complete raw1/nil（0x115f03928..0x115f03960）。因此此处的成功
回调是本地action返回后的完成通知，不是设置上传ACK；物理collection点击与Story clickBlock安装已定位，
其余青少年/特殊key分支、dismiss completion实际运行和菜单呈现结果尚未全部验证。

真实RigthModule.makeShareService为此service安装weak module block0x1132c2b68
（0x1132c27e4/0x1132c27f8/0x1132c2814）。block weak-load module后
_showPlaySettingPanels（0x1132c2b78/0x1132c2b80→0x1132c3384）；该body CURRENT
storyContext.store（0x1132c3394/0x1132c33a4），resolve具体STSingleDoubleGestureBloc
（0x1132c33b8/0x1132c33c8），返回receiver调用show（0x1132c33ec）。
show0x10419da18→0x10419d7f0（0x10419da2c）要求weak layout.mainVC非nil
（0x10419d84c/0x10419d85c），取gestureList（0x10419d86c），构建VKSettingVC
（0x10419d8a0/0x10419d8ac），session设singleDoubleGestureList
（0x10419d8d4/0x10419d910），调用poper helper0x1041ce6a4
（0x10419d9a4/0x10419d9bc），将返回swipeVC弱保存（0x10419d9dc）。
因此menu action→具体bloc→列表→前述DetailContent choice→日志/本地writer/条件Universal
上传具有静态连接；Store.resolve实际实例安装及最终UI呈现结果仍未运行验证。

### PlayURL 旧操作配置

旧配置与Any偏好分开：requestRemotePlayConfig（0x114faa3f4）发零字段
PlayConfReq到PlayURL.PlayConf，nil NSError时copy reply.playConf保存abilityConf
并排队raw1写；error时返回无业务重试。PlayAbilityConf有30个CloudConf字段，
包括后台/翻转/投屏/字幕/模式/画质/弹幕/Dolby/无损等；PB tag不能直接当confType枚举。
cloudConfigForType（0x114fa99a4）优先本地userOperation.opDict[confType]；
没有本地值才要求propertyName/testSetPropertyName非空且abilityConf[testName]
boolValue=true，复制confType/fieldValue/confValue成PlayConfState，不赋show。

updateCloudConfig（0x114fa9b94）按confType写userOperation.opDict和
syncDiff.newDict，排队raw2/raw100持久化，再syncDiff。最新generation把newDict
合并reqDict并清newDict，reqDict非空才发PlayURL.PlayConfEdit；PlayConfEditReq
只有field1重复PlayConfState，其字段1:confType/enum、2:show/bool、
3:fieldValue/message、4:confValue/message。EditReply零字段。helper也等20秒且
忽略wait结果；非nil响应+nil error清reqDict/重置retryCount，本地userOperation
继续保留。这里没有额外业务code检查，不套用Universal的Any/blocked规则。

实际旧getter wrapper（0x114fa5d50–0x114fa6c40）传入confType与PB tag的对照：
backgroundPlayConf tag1→confType9；flip2→1、cast3→2、feedback4→3、subtitle5→4、
playbackRate6→5、timeUp7→6、playbackMode8→7、scaleMode9→8；tag10..30才与
confType10..30相同。setter原样交incoming PlayConfState给updateCloudConfig，
不替调用者改正confType。不能把描述符声明顺序直接当操作配置编号。

### 章节偏好的直接 Distribution 请求

BBPlayerChapterService._fetchReomteConfig（0x114440a3c）在currentScene.scene_cid/
scene_avid均非0时直接发GetUserPreference，不经过BBCDeviceConfig缓存。
请求typeURLArray仅bilibili.app.distribution.play.v1.SpecificPlayConfig，extraContext
含String mid/aid/cid：currentUser.mid、self.aid、self.cid十进制；本方法无hasLogined门槛。
error非nil、valueArray为空或firstAny unpack对象无enableSegmentedSection selector
时回退true；正常则读该BoolValue.value，缺wrapper的nil getter反而得到false。
所以传输失败fallback与响应缺字段不是同一种默认。

configResidentChapterSwitcherShow（0x114441c40）先写aid/cid，show=true才fetch；
loginProxy.hasLogin KVO callback0x114440314也在show=true时fetch，忽略new bool，
不能只称登录成功重取。changeResidentChapterStatus0x114442500仅状态不同才sync；
UI章节widget.didClickSwitch0x1144857c0把sender.isOn传入，无登录门槛。
PlayerScene.start0x11450510c也以model.showChaptar调用该change，因此上传不限于手动。
_syncRemoteConfig0x1144414f4构造新SpecificPlayConfig+BoolValue.value=current状态→Any，
发SetUserPreference，extra仍mid/aid/cid；此方法自身无login/nonzero scene门控。
handler0x114441754仅return，未见失败回滚/业务重试，不能将fetch条件套到写入。

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
完整计时策略及跨账号处理尚未全部解码。

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
路径。先将缓存 data 解析为 AppEvent，设 uploadTime 为当前 Unix 毫秒，再序列化。
每条消息单独调用 packagePayload（0x1161eb154）；元信息字典包括 logId、eventId、
appId、appVersionCode、platform，后三者是十进制/版本字符串。字典 allKeys 没有显式排序。

分帧由指令恢复为：`RDIO` 四字节、四字节大端长度/标志、一个校验字节、body。
body 是元信息逐项编码后拼接 Protobuf：单字节 key 长度 + key，再四字节大端 value
长度/标志 + value。value 长度最高位置 1 表示还有下一元信息项；外层长度最高位置 1
表示含元信息。其余 31 位表示 body 长度。body 超过 0x4000000 的分支会清空 body；
该异常路径是否可到达以及调用者行为尚未验证。

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
但最终调度间隔、次数上限和过期清理仍待追踪。

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
UIApplicationDidEnterBackgroundNotification。mainDelayAB、disk_cache_delay 和过期
清理配置另有延迟/异步分支，尚未完全核对。

reportByTimer（0x1161ebdec）先暂停 timer 到 distantFuture，再按 common/schedule
计数触发 reportWithCommonCount；完成 block 将 fireDate 设为现在 +timeInterval。
因此这里是完成后再安排时间，不能简单描述成固定每 3 秒发一次请求。进入后台会创建
UIKit background task，并以最大计数请求排空上报；完成或过期 block 结束后台任务。
这不保证系统允许全部网络任务在后台完成。

handleFlowControl（0x1161ebbdc）在当前 timeInterval <maxInterval 时，加基础 interval，
再加 arc4random_uniform(interval >>1)；未看到对加完结果再次 clamp 到 maxInterval，
不能写成严格上限。batchSize >minPackageSize 时按整数除 2 缩小，packageSize 大于
minPackageSize 时直接设为 minPackageSize。这是加法退避与分包缩小，没有在此方法
实现指数退避或立即重发。流控恢复、移动网络配额与缓存等待策略仍待继续解码。

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
等价核对。异常系统时间、整数溢出、配额持久化和客户端重启仍待进一步验证。

### 公共信息与采样配置

`BFCNeuronInfoDelegate`（0x114551764–0x1145517c8）从实验服务查询
neuron_post_gzip、neuron_main_delay、neuron_switch_net（此入口 presetHitValue=0）、
neuron_disk_cache_delay、neuron_enable_public_parameters；scheduleTimeInterval 从远程
配置 neuron.track_polling_seconds 取整数，默认 0。是否命中及配置服务自己的默认逻辑
尚未贯通，不能据实验键存在推断开关当前开启。

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
异常系统时间和套件迁移尚未验证。

随后创建 RuntimeInfo，version/versionCode 分别读取 mainBundle 的
CFBundleShortVersionString/CFBundleVersion，字符串转换失败用空字符串；logver
读取注入服务的 version。任务设置 shared Neuron 的 AppInfo、RuntimeInfo、delegate，
再调用 runWithConfiguration。这证明了模块任务内部的初始化链，尚未证明全局任务
注册器在本样本每一种启动场景都会执行它，也未贯通后续会话变更的同步更新。
注册发现边已补：184-provider静态表entry123（0x120274300）是
BFCNeuronModule._$GripperRunnableTaskProviderNeuronModule，conformance witness
0x11b2f03f8的getter0x104976fb0返回唯一任务；task witness0x11b2f03c8的execution
0x104976f5c转0x1049774a0，trigger为applicationLaunch，thread为main、priority raw750。
因此首轮generated dispatcher具备发现并按该trigger调度任务的具体边，不是仅凭任务名。
实际每种启动是否发该trigger仍是独立门禁。InfoApp.sessionId getter0x11455131c
是ivar+0x40，setter0x114551324做nonatomic copy；初始化0x104977e34保存注入值快照，
异步Neuron事件读取该ivar。当前有界selector扫描未找到另一Neuron写者，但直接ivar
写入和外部账号/设备通知尚未穷尽，不能推出它永不更新。
另一个startup session有独立来源：StartTraceServiceImp.startSessionId0x105037bbc
调用AppStateManager.getStartToken0x105038814。constructor0x105037d98把
UUID.uuidString经Swift String.hashValue取低32位、零扩展，以%lx格式保存RAM token；
不是UUID文本或稳定hash，检查到的构造/生成/读取方法没有落盘writer。
它注册willEnterForeground通知；Monitor.premainStart调用mainStart时，只有环境
ActivePrewarm恰为"1"才通过自身并发queue的async barrier置isPrewarm。
前台回调0x1050387ec经barrier进入0x10503869c，要求isPrewarm==1且refreshed=false
才重新生成并置refreshed=true；普通前台不更新，已标预热的路径只更新一次。
getter通过同一queue.sync复制token，外部setter与账号重置仍未穷尽。
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


## 预加载播放能力参数

BBResolverUtils.preloadUrlDeviceParams（0x114a0c21c）先生成 fnver=0、能力 fnval、
fourk、soft_fnval、player_net 与 force_host。fourk 是 IJKFFUtils.isUhdSupported
的布尔值，不是在该函数另做屏幕判断。player_net 按 Wi-Fi→1、WWAN→2、其他
reachable→0、unreachable→3 选字符串；force_host 先为 0，设置
httpsPlayurlEnabled 为真时覆盖为 2。

supportFnval（0x114a0be60）按位组合：

| 位值 | 添加条件 |
| --- | --- |
| 0x10 | 总是作为基础位 |
| 0x80 | isUhdSupported |
| 0x100 | isEac3Supported |
| 0x200 | enableDolbyVision |
| 0x40 | enableHDR |
| 0x4000 | enableHDR 且 enableHDRVivid |
| 0x800 | isAv1Supported，或 v865_player_support_av1_soft 实验命中且 isAv1SupportSoft |
| 0x4 | v886_player_preload_support_soft_fnval 命中且 isHevcSupported |
| 0x10000 | isH266SupportSoft |

soft_fnval（0x114a0bf6c）在 v886_player_preload_support_soft_fnval 未命中时为 0；
命中则 0x114a0bfb4 组合 H266 软件支持位 2，以及
v888_player_support_av1_soft_fnval 命中且 AV1 软件支持时的位 1。上述实验 preset
均为 1，但实际命中与 IJKFFUtils 的系统能力判定仍需分别核对。

BBPlayerPreloadUrlParamsHelper（0x114397ffc）复制上述参数，再加 qn、qn_policy、
voice_balance、client_attr 和 player_extra_content。qn_policy 是 autoQualityEnabled
的 1/0，voice_balance 是 enableLoudNorm 的 1/0。qn 的 preferredQnForResolver
（0x11482101c）在自动画质开启时选择 32，否则取 userSettingQuality，再过
maxQualityByUserLoginState（0x1148210a8）：已登录原值返回；未登录且远程
配置 enable_player_force_login_qn 的整数 >=1 时取 min(候选画质,配置值)，否则
保留候选。未从此处推断设置本身的持久化和默认画质。

client_attr（0x1143981fc）仅当 player.priority_hdr_842（preset=0）命中、
priorityUseDolbyHDR 开启且 currentUser.vip.isValidVip 为真时返回 1，否则为 0。
extraContent（0x1143982d8）以 screenHeight→long_edge、screenWidth→short_edge
十进制字符串及 VBPreferences.translateLanguage→cur_language 组成字典；该函数
没有自行按 min/max 排序两条边。toJsonString（0x11439843c）对字典用 Foundation
JSON options=0，再 UTF-8 转字符串，非法输入或序列化失败退空；未指定排序键。
因此 player_extra_content 的键顺序不是此函数保证的协议常量。

这些参数被搜索等调用者复制；首页 getPlayerParams 另有选键/合并层，不能将 helper
全部字段直接认定为每种业务请求都会发送。实际 playurl/PlayerArgs 的注入、解码能力
函数和响应选择仍在追踪，同版本执行未验证。假布尔能力的 2,048 个 fnval
组合及 196 个 qn/登录/配置边界已通过分支实现与位公式的离线等价检查；
未验证系统解码能力探测或服务端接受。

## UGC 播放地址请求入口

上层 BBResolverHelper.resolverV2With（0x1149fd984）先按参数模型分派 UGC/PGC/
Live/第三方 URL/PUGV。UGC 设置 newApiPlayView；isCantUseLocalCache 控制是否先
findLocalUGCFile。局部回调 sub_1149FE06C 将找到的 item/videoInfo/audioInfo 装成
ResponseModel 并交调用方，随后仍调用 resolverV2UGCWith:localResponseModel：
localFirst 为真才把此 ResponseModel 传下去，否则传 nil。该分支没有因 localFirst
直接省略网络更新，不能从缓存回调推断最终不联网。无本地结果的 block
0x1149fdcfc 再按非空 preloadUrl、videoSource 与常规 UGC 分支选择；实际格式验证
与实验回退仍需检查。

BBResolverUGCHelper.resolverWith（0x114a5b360）先检查 avid/cid 非零；该函数不是
按 >0 检验。offline 为真时转 findLocalAVFile 并结束这条网络构造路径。缺编号时
有 completion 才回调 com.bilibili.err/30004，并按当前线程立即或派发 main queue。
联网路径创建 BAPIAppPlayurlV1PlayURLReq，最终经 PlayURL.playURLWithRequest
（0x114fad098）调用 defaultService；默认 host=grpc.biliapi.net、isRest=false。

两个请求描述符已逐项提取（0x114fadd00、0x114fae2a4）：

| 字段号 | PlayURLReq / PlayViewReq 共用字段及类型 |
| --- | --- |
| 1–3 | aid、cid、qn：int64 |
| 4–5 | fnver、fnval：int32 |
| 6 | download：uint32 |
| 7 | forceHost：int32 |
| 8 | fourk：bool |
| 9–10 | spmid、fromSpmid：string |
| 11–14（仅 PlayViewReq） | teenagersMode/int32、preferCodecType/enum、business/enum、voiceBalance/int64 |

PlayURLReq 的 aid/cid/qn/spmid/fromSpmid 来自传入模型，字符串 nil 退空；fnver=0，
iPhone fnval 取 supportFnval，iPad 经 ugcFnvalForPad（0x114a6a7bc）：在特定旧机型
列表之外再 OR 0x400，列表内保留 supportFnval，不能把全部 iPad 写成同一常量。
isDownload 为真才 setDownload=2/forceHost=2；forceHttps 或
httpsPlayurlEnabled 为真也设 forceHost=2，其他路径不在构造器显式赋值。
fourk 取 isUhdSupported 的非零布尔值。

resolverV2With:localResponseModel（0x114a5bd7c）改建 PlayViewReq 并调用 PlayView
（0x114fad2a0），aid/cid/qn、fnver/fnval、download/forceHost 与来源页面字段同类。
voiceBalance 从模型 enableLoudNorm 取值；teenagersMode 调
BFCRestrictedModeManager.enableOfMode(0)。preferCodecType 默认原始枚举 1，若
isHevcSupported 且模型 preferCodecType!=7 则设 2；未从这两值推断全部枚举名。
business 直接传模型 isStoryMode。该构造段未显式 setFourk，不能将旧 PlayURL 的
fourk 赋值套到 V2。缺编号仍结束并回调错误；不是自动降级到旧请求。

V2 completion（0x114a5c34c）先检查 error。error 非 nil 且带 bapi_status 时，
将 status.code/message 转为 com.bilibili.err；其他 error 保留并结束，报告失败与回调。
error=nil 且 response 非 nil 时才调用 parseVideoSourceInfoV2，并传本次模型、
localResponseModel、cid 与回调；response=nil 的无 error 情况另合成 30004。
因此存在本地响应参与解析的路径，仍需追解析器的实际选择、码率/音轨降级及缓存
兼容规则。没有在这些已读函数体发现失败自动重试，不能排除传输层独立机制。

局部画质复用 helper getNeedReplaceVideoQnFrom:byLocalModel（0x114a67210）要求
localModel 存在、response.hasVideoInfo 且 streamList 非空，否则返回 -1。它读取
localModel.item.currentQn，把服务器每项 streamInfo.quality 经 reducer 0x114a6741c
折叠：有质量 <= 本地目标时选其中最大值，否则选所有项最小值。该 helper 未按
streamInfo.errCode 或 URL 有效性过滤；调用方在后续另有筛选，因此返回值不是
播放成功保证。5,000 个假目标/列表与公式离线等价核对通过，仅验证选择算术。

parseVideoInfoV2（0x114a61bd0）首先检查 hasUpgradeLimit，命中则组装 message/code/
image/button 的错误资料并结束；随后还有 hasPlayLimit 的独立结束分支。限制响应
不能当作正常空 streamList 来降级处理。常规路径把 hasViewInfo 交专用 parser，
arc.isPreview 保存到 PlayArc，再创建视频质量列表。逐项映射 quality/format/
newDescription/displayDesc/superscript、needVip/needLogin/vipFree、noRexcode、
subtitle/attribute/intact、reportParams 和 errCode/观看限制原因；限制字段不是全局
删掉高画质项的证据。音频另解析普通 dashAudio、Dolby 与 lossLessItem；音量参数
另有缺值转 NaN 分支，完整默认音轨与参数消费仍待核对。

完整 UI→请求模型赋值、V2/统一接口实验选择、预加载复用、离线文件检查、成功响应
映射与播放器建立尚未完成；上述入口不代表所有 UGC、PGC、投屏和下载共用的全协议。

## 直播播放信息与房间信息入口

BBLiveProcessScheduler.getRoomPlayInfoRoomID:...0x10f188a5c分别创建播放信息与
房间信息请求，两次dispatch_group_enter，0x10f188dc4在main queue挂group notify；
它们不是一条请求内的两份模型。四个回调分别为播放成功0x10f188f0c、播放失败
0x10f188f9c、房间成功0x10f189084、房间失败0x10f189114，均先loadWeak scheduler；
对象已释放时直接返回，且不执行group leave。对象仍存在时，播放成功/失败均置
processSchedulerStatus=3000，房间成功/失败均置3500；各自内部success/failure方法
发生在isCanceled检查之前。外部对应回调只有非nil且isCanceled最低位为0才调用，
随后无论成功或失败、外部回调是否被取消门禁跳过，都leave一次。因此取消标记主要
拦截外部通知，并未使这些内部处理跳过。group notify block0x10f1891fc同样弱引用
检查，随后置status=4000并调用_groupCompletion:nil；最后仅未取消且外部completion
非nil才调用外部。status=4000本身不证明两条请求业务成功。

cancelAllRequest0x10f1898b8依次对三个已保存请求（userInfo/roomInfo/playInfo）检查
非nil且isCancelled最低位为0后cancel，最后才置scheduler.isCanceled=true；此方法
没有直接leave group，也未清空请求引用。BBLiveBaseRequest.requestAsync0x111ed8310先计算_delayInterval；>0则创建不重复
NSTimer，target=self、selector=_requestAsync，存scatterTimer并加到currentRunLoop的
NSRunLoopCommonModes；否则立即调用_requestAsync。_requestAsync0x111ed848c在
调用super.requestAsync前写startTime为当前Unix秒，cost0x111ed82f0=endTime-startTime，
因此该cost不包括发送前scatter等待。requestSync0x111ed83c4直接写startTime并调super，
未走scatter等待。

cancel0x111ed8434先写manualCanceled=true；scatterTimer非nil时仅_clearTimer
（invalidate并清空timer），直接返回，没有super.cancel或完成回调。timer为nil才调
super.cancel。因此发送前的延迟请求可被取消而不触发上述四个group回调，不能断言
“任何取消最终都会leave”。已定位的_requestAsync本身也未清空timer引用，timer触发后
是否由其他路径清空仍须核对；这个分支不能仅靠timer已失效推断会调用super.cancel。
验证码重发的request是否被scheduler持有/取消、底层取消回调保证仍待继续追踪。

发送前延迟不是失败重试：_delayInterval0x111ed8530从options.baseUrl构造NSURL，
copy preference.scatters后按顺序找首个_needDelayWithURL返回true的scatter；无URL、
无scatter或无匹配返回-1。匹配器0x111ed8704依次遍历scatter.URLStrings，以scheme与
host字符串均相等为前提，relative=false时path必须相等；relative=true时配置path为空
则放行，否则请求path.hasPrefix(configPath)，没有路径边界或query比较。还要求
scatter.delay>=1。命中后_delayIntervalWithPreference0x111ed89f8仅支持mode=0固定
延迟delay/1000秒，mode=1为(arc4random()%delay+1)/1000秒（取余而非均匀上界API，
先转Float运算再转Double）；其他mode返回-1，不继续选后面的scatter。具体配置的
下载、持久化、默认值与哪些接口匹配仍需沿preference来源核对。
BBLiveBaseClientPreference的mapper0x111ed8cf0把scatters映射到live_network_delay，
容器mapper0x111ed8d98指定BBLiveBaseClientScatterPreference；后者mapper0x111ed8bb8
把URLStrings映射到urls。pre-transform0x111ed8e18若live_network_delay是NSString且
md_objectFromJSONString结果非nil，才用解析结果替换该键，其他输入原样copy返回。
这证明配置既可预解析，也有JSON字符串处理分支，不证明现版服务端实际下发格式。
播放接口handle0x10f189f50读取房间密码，并按currentUser.mid与roomID取得
InternalRoomUserDefault.authenticationModel的token；参数builder0x10f18a440写roomID、
httpsPlayurlEnabled、输入dolby/needPlayURL/needShowPIP、密码/token、HDR支持串及
免流类型，extra为special_scenario="0"、supported_drms="0,3"。
这些是保护房间的资料，不能与普通access_key或ticket混写，本文不读取真实值。

newRequestPlayWrapperWithParams:completion:0x10f7e8c28构造14项基础字典：

| 参数 | 来源/规则 |
| --- | --- |
| room_id / play_type / media_type | roomID直接值；playType/audioType经数值字符串helper |
| http | isHttps非0为"0"，否则"1"，不是BOOL原值字符串 |
| device_name | bfc_platformString，nil退空String |
| only_video / mask | 均为"0" |
| network | helper0x111ebaa94；最终网络枚举取值待核对 |
| protocol | qn==30000时"1"，其他"0,1" |
| format | format数组非nil即逗号join（空数组为空String）；nil才默认"0,2" |
| dolby | dolbyValue经数值字符串helper |
| codec | 从"0"起，H265支持则追加",1"，AV1支持则追加",2" |
| no_playurl | needShowPIP最低位为1直接"0"；否则needPlayURL非0为"0"，零为"1" |
| hdr_type | hdrTypes.length>0用原值，否则"0" |

然后0x10f7e8fd4无条件补qn字符串；freeType非0才加free_type；extra非nil则在
0x10f7e9058最后合并，可覆盖上述业务键。这里H265 getter0x10f7e92f8要求
bfc_rank>=70及iOS11或以后；AV1 getter0x10f7e9338在IJKFFUtils.isLiveAv1Supported
非0时返回1，否则组合softAV1.enable与isAv1SupportSoft结果。后者配置值及rank
来源未闭合，不能把codec视为固定设备平台字符串。

0x10f7e90b0以相对路径xlive/app-room/v2/index/getRoomPlayInfo、HTTPMethod原始0、
BBLiveBasePlayInfo模型和nil keyPath建立请求。wrapper另构造Content-Type=
application/x-www-form-urlencoded、X-Live-Room-Password、x-bilibili-mid及
X-Live-Room-Token四个头，再与已有extraHTTPHeader组合；handle之后还合并当前
请求头并再次设置Content-Type/房间密码（0x10f18a2bc–0x10f18a330），再requestAsync。
合并helper0x112658e44先mutableCopy receiver，再addEntriesFromDictionary传入字典，
最后copy返回，因此传入字典覆盖receiver同名键；具体两次调用的receiver/参数分别
决定覆盖方向，不把所有extraHTTPHeader场合都外推成同一优先级。

房间信息路径独立：handle0x10f18a6fc→client0x10fbeb4bc构造room_id数值字符串、
device_model=bfc_platform（nil经helper回退）及network三项；extraParam.count>0
在0x10fbeb604合并，允许覆盖基础项。0x10fbeb650发相对路径
xlive/app-room/v1/index/getInfoByRoom、HTTPMethod原始0、BBLiveRoomInfo模型；
handle安装customResponseBeforeRequest，并补Content-Type/房间密码后requestAsync。
房间completion0x10f18aa6c先按request.cost/error.code写
live_room_combine_roomInfo_time，message取当前handle.playInfo.liveStatus。NSError非nil
时调用BBLiveUniversalHandle.handleByRoomInfoErrorCode映射，再存roomInfoError并调用
failure；映射器0x10f18b734保留原domain/userInfo，将19002002/19002003/19002004/
19002005分别改为60002/60004/60005/60006，其余code不变。映射后的code为60002或
60006时还调用BBLiveRoomBackManager.clearNode。这里不是自动重试或通用成功码。
NSError=nil时取roomInfo.gaiaInfo.v_voucher，调用
_riskValidationWithVoucher0x10f18b320：voucher.length>0即创建
BFCCommonCaptchaViewController、以router.navigationController.topViewController为parent
展示，记录live.live-room-detail.game.checklayer.show，并返回true以延后roomInfo写入
与success回调；没有voucher则返回false，立即存roomInfo并调用success。

这条正文验证码不以-352为门禁。其UI完成block0x10f18b4e4遇NSError.code=1或3，
先记录checklayer.click，并在非nil时调用quitRoomBlock；随后仍调用completion，
success非零传(token,nil)，否则传(nil,error)。下游0x10f18ad94只检查token.length>0，
非空时新建extraParam，先合并原extra再覆盖gaia_vtoken，递归调用同一房间信息请求
（0x10f18ae18、0x10f18ae40）；返回的新request只unsafeClaim，未在此写回scheduler。
空token则存roomInfoError=验证码error并调用failure（error可能nil）。本层未见次数上限。
这与公共HTTP层的x-bili-gaia-vtoken头是两种独立重发链，不能把字段或触发条件互换。
customResponseBeforeRequest对应block0x10f18aebc写当前NSDate并返回nil，其捕获对象
的具体时间字段仍需按ivars核对；缓存与播放URL选择未闭合。

两条路径进入BBLiveBaseClient公共构造：_optionsWithURLString:...0x111ed5158以
baseURL解析相对路径，创建BFCApiOptions；_mergeOptionParams0x111ed50c0先copy
getRequestCommonParams，再合并非空业务字典，业务值覆盖直播公共键。options保留
输入method，因此上述0进入已解码BFCApi默认GET分支；cacheValidLife/timeout均60秒、
ignoreCache=true、signType=0。此处不推断公共参数之后的最终覆盖或全部传输头。
liveClient工厂0x10fca8aa4读取常量槽0x11cf3a038，基础URL为
https://api.live.bilibili.com。getRequestCommonParams0x111ed8080仅在mainBundle的
bundleIdentifier等于live.bilibili.com或com.bilibili.live.broadcast时返回
platform=ios_link，其他标识返回空字典；不能把ios_link写成主客户端直播的无条件值。

entries dispatcher本身由once initializer0x100697dd8创建并保存静态槽0x1208a6168。
旧BBLiveConfigModule.initWithConfig对应body0x100697e08仅优化flag=false时向同dispatcher
加入五个entry：BBLiveBaseCommonEntry、BBLiveBaseRevenueEntry、BBLiveEntry、
BBLiveBCStudioEntry、BBLiveBCVirtualEntry。优化true的entry注册仍在追踪，不能把这一
条件列表当所有运行路径始终存在的集合。dispatcher.keys0x10edfbe9c遍历各entry.keys，
加到NSMutableSet后allObjects返回，去重但不在这里保证顺序；query键拼接的排序另待
确认。_runForEachEntry0x10edfbdc0枚举entries getter所得列表并调用block，资源回调
block0x10edfbd78先检查entry是否响应selector，再转发原BOOL。

已找到home setup到资源回调的桥：helper0x100698d10向once取得的entries dispatcher
发onHomePageInitialized，然后读取同dispatcher.keys，转Array[String]后交sharedManager
fetchResourceCommands（0x100698e0c），completion为0x1006981bc。后者将传入BOOL最低位转发给同一静态dispatcher，
没有成功/失败分支门禁，发送onLiveConfigFetched:；旧模块门禁已闭合：BBLiveConfigModule.onHomePageInitialized0x100698150经
common0x10069815c，仅runnableTaskOptEnable=false才调用该helper。
对应runnable LiveConfigModuleHomePageInitialized的producer0x1006985ec，execution
0x100698608也取同helper，经common0x100698614要求userInterfaceIdiom==0且同优化
flag==1，与旧callback互补；完整provider注册和dispatcher条目列表仍须核对，不以最近.cxx_destruct符号误归属Swift函数。

资源请求不必在每次入房发生：fetchResourceCommands0x111cc9db0先保存commands与
callBack，dd.key.live.bootstrap(default=false)关闭时立即queryCommands；开启时
返回nil、暂存等待queryLiveResourceCommands。入房_beforeFetchRoomInfo
0x10ed96e58确实向sharedManager调用后者，但它要求hasFetchedQuery=false且bootstrap
开启才执行，**发送前**就setHasFetchedQuery=true，再以暂存commands查询。
失败也未在该callback重置hasFetchedQuery；已读范围内没有自动允许下一次入房重试。
queryLiveResourceCommands完成block0x111cc9f9c仅callBack非nil时调用并清callBack/
commands；callback为nil时跳过清理。其它配置调用/reset及实际bootstrap值仍未穷尽。

直播在线资源请求有独立参数路径：BBLiveBaseOnlineConfigManager.queryCommands:
customParams:completion:0x111cca028检查commands并合成business键，编码customParams，
通过共享HTTP client构造请求后requestAsync；空/无效commands直接completion(false)，
未发网络请求。底层0x111cc53c4以GET /xlive/open-interface/v1/fetch_client_resource、
BBLiveBaseOnlineConfig模型请求，基础参数business来自合成键，customize只在编码后
字符串length>0时加入。这里的business不是固定设备号或登录MID。
失败callback0x111cca290仅日志及completion(false)，没有该body内的自动重试；成功交
_handleWithOnlineConfig0x111cc9840枚举keyValueInfos，更新本地info并收集command。
只有非空command才dispatchCommands，再通知manager delegate，completion按收集数
是否非零返回BOOL；不能把HTTP成功等同于某个network配置必已更新。

旧network保存command handler0x111cc7ae4读取task.value，md_objectFromJSONString后
直接set defaultEnvironment.networkConfig，未在此检查解析结果非nil/字典或保留旧值。
新存储delegate MDKVBundle.manager:didFetchOnlineConfig:0x10fca9a44将command.dictionary
数组交storage._didFetchResponses，再仅对返回changedKeys非空时通知mainBundle readers；
MDKVBundle.network0x111ebacd4读取mainBundle的live_mobile_network键。
旧command type映射已闭合：executeTask0x111cc8f24以type-1索引42字节jump table
0x118ffff50，其中type17进入_liveNetworkConfiguration。真实磁盘写入原子性及
存储失败处理仍须继续追踪。

scatter preference的业务更新入口已找到：BBLiveEntry.onLiveConfigFetched
0x10ec85194先loadRoomPlugins，随后读取BBLiveBasePersistentEnvironment.newKVEnabled；
true取MDKVBundle.defaultBundle.network，false取defaultEnvironment.networkConfig。
所取配置非nil且通过字典类型检查后，objectOfClass转换BBLiveBaseClientPreference，
再向共享BBLiveBaseHTTPClient.client调用setPreference（0x10ec852a8）。该callback
不直接使用传入参数当preference。下载、写入这两存储的路径仍须继续追踪，不能由
callback名称推断每次入房都联网更新。

BBLiveBaseHTTPClient按非空URL字符串缓存client（0x111e8b2f8），已有则复用，
没有则defaultClientWithBaseURL创建并存入字典；空URL返回nil。setPreference
0x111e8b3ac更新自身preference，copy当前cachedClients.allValues后逐client更新，
因此已有client也接收新scatter preference，并非只有新建实例才生效；配置下载来源
仍未闭合。子类_BBLiveBaseHTTPClientBuilder.initWithLogger0x10fca8944从
BFCAccount.loginModel.accessToken取得token，从authority.userID取得currentUID，
并以main queue注册账号delegate。callback0x10fca8bec不按传入login BOOL分支，
而重新读取当前account/authority并更新这两个字段。cachedClient override
0x10fca8a3c将自身设为client.delegate；已读willStart/didComplete delegate仅转给
capture，不能由token ivar存在推断它在这里写入业务参数或HTTP头。

keyPath wrapper0x111ed6edc采用code/message路径。公共请求0x111ed52b8注册
“/”→SKVObject、isArray=false、isOptional=true，再创建BBLiveBaseRequest。
响应头handler0x111ed5838和预处理block0x111ed5880分别把httpHeader/rawData
存到弱引用request；公共completion wrapper0x111ed5788先写endTime为当前Unix秒。
成功block0x111ed58c8在回调对象非nil且request.manualCanceled为真时直接回
(nil, NSURLErrorDomain/-999)，否则记录rawData，并取models["/"].dictionaryValue
交给_validatedResponse0x111ed4e20。该验证器先_filteredResponse0x111ed4ff0：
数组取firstObject，再要求NSDictionary并调用md_dictionaryByFilteringValue:NSNull；
非字典返回nil。过滤helper0x11265925c逐key跳过与所传value指针相同的值（value=nil
才取NSNull.null）；数组交0x112657748，字典递归同helper。数组也按指针过滤并递归
数组/字典，所以这里是递归移除NSNull值，空容器保留；不是字符串/NSNumber等值比较。
随后对codeKeyPath值调用integerValue；
值缺失经nil消息得到0，没有“code必须存在且为整数”的显式验证。非零code返回nil，
并生成com.bilibili.live.base.http.error.domain的同码NSError，userInfo包括
NSLocalizedDescriptionKey（message缺失用内置文案）、NSLocalizedFailureReasonErrorKey
及BBLiveBaseClientErrorRequestResponseKey（后二者均为过滤前输入对象）。code=0则
返回过滤后的对象；这仍不能单凭业务码证明后续模型有效。

失败block0x111ed5a60收到nil原始NSError时补直播域/-900001（完整mov+movk常量，
不是第一条指令显示的-48033）。它记录失败rawData，复制原NSError.userInfo；有rawData
时用NSJSONSerialization、options=1尝试JSON解析，解析错误写入NSUnderlyingErrorKey，
保持原domain/code重建NSError。JSON解析成功时运行同一业务验证器：非零业务码的
NSError优先；没有业务错误则保留原domain/code，并把非nil过滤响应加入
BBLiveBaseClientErrorRequestResponseKey。因此传输失败带code=0正文也不会自动变成功。

失败结果再查dd.live_http_client_common_captcha，default=true。开关开启、最终NSError
code=-352且响应头x-bili-gaia-vvoucher字符串非空时，调用BFCCommonCaptchaService，
tag=live、viewController=nil、useCustomAlert=false，并暂不调用普通完成回调。
验证码block0x111ed5fb8先要求弱client与弱上下文仍存在；任一释放只记录日志并返回，
不补回调。success非零时复制同一options.extraHTTPHeader（nil则新建字典），写
x-bili-gaia-vtoken=helper转换后的token，回写options；随后以原code/message路径和
完成block重新requestWithOptions并requestAsync（0x111ed6234、0x111ed6244、
0x111ed6254）。该block不检查token非空，也没有可见重试次数上限；不能据此宣称
验证码服务内部无上限。success=0则回(nil, 直播域/-352)，localizedDescription设空串，
不直接透传验证码NSError。未进入验证码分支时走普通完成block。

objectClass解析wrapper0x111ed6988把原keyPath交给_parsingResponse:inKeyPath:
objectClass:error:。底层0x111ed7558仅当keyPath.length>0才调用valueForKeyPath；
nil或空路径直接使用当前根对象。因此播放信息构造器传入的nil keyPath在这一层
不会自动取data。输入或所取路径为nil、字典/数组count=0时直接返回nil，不生成该层
类型错误；目标class已匹配则返回对象，其他值再走转换。这不排除具体模型内部另有
JSON字段映射。实际cached client由BBLiveBaseHTTPClient.defaultClientWithBaseURL
0x111e8b174安装JSONValueSerialization，block0x111e8b1c0仅对MDObject子类调用
modelWithDictionary；该方法0x111edb0a4直接走yy_modelWithDictionary。BBLiveBasePlayInfo
继承MDEntity→MDObject，MDObject默认pre-transform0x111edb3d8原样返回字典。
BBLiveBasePlayInfo mapper0x10fbf3414的15组映射为：isPortrait←is_portrait、
liveStatus←live_status、liveTime←live_time、playURLInfo←playurl_info、roomID←room_id、
shortID←short_id、uid←uid、specialType←special_type、allSpecialTypes←all_special_types、
roomOfficialType←official_type、officialRoomID←official_room_id、
pureControlFunctionArray←pure_control_function、degradedPlayURLInfo←degraded_playurl、
subtitleInfo←subtitle_cfg、playerStrategyInfo←player_strategy。
modelCustomTransformFromDictionary0x10fbf37b4把输入copy到originalDictionary；
multi_screen_info非nil且为NSString时用BBLivePlayerMultiScreenInfo.yy_modelWithJSON
转换并setMultiScreenInfo，没有这一分支的NSDictionary直接转换。随后分别计算
_calculateChatRoomStyle与_calculateCloseLiveAndNoPlayer，写两个派生BOOL，并返回true。
派生计算0x10fbf40f0的isChatRoomStyle为liveStatus!=1且allSpecialTypes不含NSNumber207；
isCloseLiveAndNoPlayer计算0x10fbf41ac为liveStatus==0且同样不含207。nil/空数组按不含处理，
不在此为raw207猜业务名称。setLiveStatus0x10fbf4268仅数值改变才重算；
setAllSpecialTypes0x10fbf42f0仅对象指针不相同时更新并重算，两个派生BOOL也仅结果
改变才写回。各字段模型类型、默认值、播放器消费者、BBLiveRoomInfo仍需继续核对，
不把mapper或transform返回true当完整播放策略或有效播放URL保证。

上述闭合公共回执、验证码重发与nil keyPath选择规则，具体业务模型、before hook、
请求cancel到回调的保证、验证码重发的request归属、入房鉴权、弹幕与观看心跳仍待继续追踪；不能声称
直播已完整复现。

### 直播观看时长的独立通道

播放/房间信息与观看计时不是同一请求。BBLiveBaseHTTPClient.requestLiveEnterWithBody
0x10f0e7968以POST /xlive/data-interface/v1/heartbeat/mobileEntry、
BBLiveWatchDurationEnter模型创建请求；requestLiveHeartBeatWithBody:sign:
0x10f0e7a34复制body（nil用空字典），最后合入client_sign，可覆盖body同名键，
再POST /xlive/data-interface/v1/heartbeat/mobileHeartBeat，模型BBLiveWatchDurationHeartBeat。
两者都使用liveTraceClient，其工厂0x10fca8b14以常量URL
https://live-trace.bilibili.com取cached client，单请求timeout改为5秒；不在这里调用
requestAsync，实际触发来自reporter。普通直播API域与trace域不能混写。

BBLiveWatchDurationReporter._generateBaseBody0x10f0f0e74生成八项：platform="ios"；
uuid取self._uuid的copy，经nil字符串helper；buvid取BFCTracker.trackID经同helper；
trackID实际0x115fd2ab8直接转BFCBuvid.buvid，非另一个独立随机tracker ID。
room_id/parent_id/area_id取当前reportModel对应字段；seq_id取_sequenceID；
client_ts是当前NSDate Unix秒向零截断整数。这里没有乘1000，不套App日志毫秒格式。
_reset0x10f0ecda8生成新NSUUID.UUIDString赋_uuid，同时清secretKey/strategy、sequenceID、
server timestamp/next heartbeat time及失败/本地时长状态；不是公共Session_ID重置。
这是基础八字段；watch_time与其余附加字段、补交和签名顺序见后续完整body链。

_initialize0x10f0ec2d0创建专用UserDefaults suite com.bilibili.live.watch_duration，
从固定键读取dictionary并mutableCopy到临时存储，不能仅凭读取证明全部补报成功。
_startTimer0x10f0eccc4创建重复GCDTimer，interval固定Double60秒、target=self、
action=_timerAction，随后schedule；这是检查timer，不是固定60秒一次HTTP心跳的证据。
_updateLocalConfiguationsWithHeartBeats:retry:0x10f0ecf54只在model非nil且retry=0时更新：
heartBeatInterval>=1才写_nextHeartBeatTime，timestamp>0才写_lastServerTimestamp；
secretRule非nil经_strategyPredicated过滤后替换strategy，secretKey.length>0才替换旧key。
本文不读取真实key。重试回执跳过这批配置更新，具体发送条件、响应签名规则、重试与
持久补交尚需闭合；不能把该局部写入当完整直播观看上报实现。

报告门禁已有具体数值：_shouldEnterRequestStart0x10f0ecea0仅要求roomID!=0；
_isEnterRequestComplete0x10f0ecec0要求strategy.count>0且_nextHeartBeatTime>0，
不是仅凭HTTP完成。_shouldReport0x10f0ecef4还要求roomID、areaID、parentArea都>0。
liveStart0x10f0ec7a4先检查isHeartBeating的bit0，已置位直接返回；未置位才_clean
与更新reportModel，通过入口门禁后置isHeartBeating，
发start request。completion0x10f0ec8c8只有配置完成且isHeartBeating仍true才
启动60秒timer并记最后本地Unix秒；否则清isHeartBeating、把实例+0x30 retryCount加1，
加完signed count<=2时直接liveStart，无delay/error-code分类；>2停止并清counter。
成功尾部也清counter，_clean/_reset本身不清该counter；初始零状态下最多两次追加
启动尝试。重试重新_clean/_reset会生成新uuid，不能将其当原body无变化重放。
completion读取当时共享reporter状态，未比捕获room/uuid或结束代次；结束之后旧
entry回调若到达不满足isHeartBeating条件，也可进入这条重启尝试，实际并发未验证。
liveEnd0x10f0eca7c更新model、发end request后立即_clean，
并非等网络成功才停止timer。

timerAction0x10f0f1e68先更新model，localWatchDuration增加Double60，更新最后
本地Unix秒，并以isLiveEnd=true构造body存入临时缓存。正常发送分支比较累计
localWatchDuration>=服务器给的_nextHeartBeatTime，sequenceID先加1，再调用
_liveHeartBeatRequest0x10f0f0078；调用后立刻以累计时长推进_lastServerTimestamp并
清本地时长，没有等网络ack。该被调函数先保存body/sign/sign_input到
_lastFailedHeartBeat（0x10f0f0398），之后才检查_shouldReport；不满足时不发HTTP。
因此上述时间推进甚至不能单独证明已发送。不足阈值仍可能处理_lastFailedHeartBeat，因此timer
频率、服务器间隔与实际HTTP频率不能合为一个常量。
不足阈值的旧失败项分支已具体闭合：0x10f0f1fc0取_lastFailedHeartBeat，再取旧body
mutableCopy、旧sign和sign_input；body/input非nil才继续。若旧body的room_id、
parent_id、area_id经longLongValue都非零，0x10f0f20d0直接进入发送0x10f0f24c4，
沿用旧body/sign/input，不重读_shouldReport或与当前room/account/uuid比较。
任一旧ID为零则走0x10f0f2374，先要求当前_shouldReport，再仅把这三个ID替为当前
model值，重生成input/sign、覆盖_lastFailedHeartBeat并发送；其他旧body字段仍沿用。
因此补发不能概括成原样重放或全量按新model重建，也不把非零判断写成>0。
该发送callback标isRetry=true，复用普通completion；配置更新retry!=0会被门禁拒绝。
不足阈值补发不走正常阈值分支的serverTimestamp推进/本地时长清零。
这些是静态状态转换；跨房间送达、公共取消与外部清理仍未验证。
watch_time helper0x10f0f1828在isLiveEnd=false时原样返回累计时长；true时返回
nowUnixSeconds+localWatchDuration-lastLocalTimestamp，没有看到负值clamp。
不能用总播放墙钟时长或固定60替代所有watch_time。

_storageWithBody0x10f0f28f4复制body并加is_patch="1"，依次生成sign input与sign；
以sign作temporaryStorage字典键保存七项body、local_time、server_time、user_id、
sign_input、sign_output、extend，再写上述固定suite/key并synchronize。
user_id来自_currentUserIDString0x10f0f2d40的BBLiveBaseAuthority.userID；extend取
reportModel.extendParameters，nil用空字典。此处只记录键及来源，不输出key或签名值。
_removeTemporaryStorageWithSign:body:0x10f0f2c04按sign查找/移除并保存字典；
body没有用于该移除判断，也没有重读当前账号进行比较。_dropAllLocalWatchTime
0x10f0f2cdc清空整个临时字典并保存。这些局部不是全局账号隔离证明，补交入口的
user_id/有效期校验和成功回执移除门禁仍须独立追踪。

签名输入是自定义有序文本。_generateSignInputWithBody0x10f0edf74依_keyOrderList
逐键取body并按`"%@":"%@",`拼接，随后删最后逗号、加花括号；不是任意字典的
系统JSON序列化。_signWithInput0x10f0ee328依_strategy顺序迭代，block
0x10f0ee42c取上一轮String.UTF8String，同时以NSString.length作长度参数，调用
0x10f17c9d4，返回C字符串转NSString后用于下一轮。非ASCII输入的字节长度边界不能
用UTF8 byte count猜替换。过滤器0x10f0ec5f8接受integerValue>=0且<12；C dispatcher
的jump table0x10f17cbdc及digest factory0x10f17cd14给出本样本映射：
0–3为SHA3-224/256/384/512，4为RIPEMD-160，5/6为BLAKE2b-512/BLAKE2s-256，
7为Whirlpool，8–11为SHA-224/256/384/512。factory直接读取对应descriptor的digest
函数并编码输出；0x10f17ce54使用%02x小写hex。这里没有独立HMAC key参数。
secret_key已作为body中的有序文本字段参与，不把它改成另一个HMAC公式。
这些结论限8.89静态修改样本，尚未做假数据向量或9.13对应版本复核。
_checkSignOriginalBodyCorrect:sign:0x10f0f1148并未重新计算digest或比较签名：只要求
传入sign.length>0，再遍历body现有keys，对命中_needsCorrectSignParameters的字段
拒绝nil/空String/"0"。它未遍历检查名单寻找body中缺失的键，空body也能越过该遍历。
不能把这道参数门禁写成密码学签名验证。

持久补交发起在_liveStartRequestWithComplete:retryCount:0x10f0ee4f8：temporaryStorage
非空即把isSupplement设true，将新base body交_supplementWatchTimeIfNeeded:body:
0x10f0f1330，输出heart_beat数组文本并放入entry POST body。该helper遍历缓存项，
读取旧body/sign_input及timestamp，经_checkSignOriginalBodyCorrect与_checkTimeAfterCST
门禁，重建JSON后以_specialSignInputWithBody:clientSign:生成补交对象。
此已检查路径没有读取存储项user_id再与当前账号比较；但完整外部切账号清理还未穷尽。
时间helper0x10f0f10d4实际要求timestamp>nowUnix-(UTC hour×3600+minute×60+second+28800)，
没有日期进位分支，不能仅凭方法名简化成严格“当天CST”的判断。

entry completion0x10f0eeabc先按isSupplement调用_trackPatchTimeIfNeededWithEnterModel:error:
消费reason数组；随后直接保存过滤后的secretRule、timestamp、heartBeatInterval与
secretKey（不同于普通heartbeat配置更新的>0/非空门禁），调用外部completion，再
_dropAllLocalWatchTime0x10f0eee9c。error非nil与nil路径都收敛到此尾部。
reason消费者0x10f0ed344只要求reason.count与temporaryStorage.count非零，再枚举reason；
block0x10f0ed4a0按reason的index从当时temporaryStorage.allKeys取key
（0x10f0ed500），读取对应存储项，以reason元素isEqual:"success"
（0x10f0ed5c8，实际stub0x10f8588b0→_objc_msgSend$isEqual:）判断结果并上报局部事件。
这里没有按body/sign匹配回执、固定allKeys顺序或显式index<count门禁，不能将事件中
的旧body与服务端对应关系视为已证明。逐项"success"也不是尾部整字典清空的条件。
因此不能把缓存清空当所有旧观看记录服务器确认。
timer每次还先removeAllObjects再保存当前body，持续活动中也不是无限累积的补交日志。

普通heartbeat completion0x10f0f0684的error=nil分支先无条件清当前_lastFailedHeartBeat，
按捕获sign移除持久项，再更新回执配置；未在这个RAM清除点比较captured seq/room/uuid。
error非nil则调用_retryIfNeededWithHeartBeatsError0x10f0ed0d0：nil输入为false，
非nil除code1012001/1012002/1012003外都为true。该数值规则来自shift/compare/bit
指令，不能补未知的业务错误名称。true保留失败项供之后timer处理，false只记录drop
事件；此completion没有立即重复HTTP。完整并发行为与跨房间隔离仍未实测。

end request0x10f0eef38先计算trunc(localWatchDuration+now-lastLocalTimestamp)，
要求>=1且lastLocalTimestamp>0才继续；sequenceID加1，body用isLiveEnd=true。
随后先清临时字典并_storageWithBody，再检查_shouldReport；delay>0时保存
dispatch_block、排main.dispatch_after并设randomlyDelaying=true，delay<=0立即
requestLiveHeartBeat/requestAsync。cancelRandomLiveEndEvent0x10f0ecbfc取消保存的
dispatch block并清randomlyDelaying，不等同于取消已经发出的HTTP。
随机end入口liveEndIfNeededDelay:model:0x10f0ecb30还要求isHeartBeating原始字节==1，
接受后copy传入model到reportModel，再进入上述end helper；它没有当即_clean。
待发block0x10f0ef810弱取reporter非nil才继续，先清isHeartBeating与randomlyDelaying，
用捕获body/sign/completion发HTTP，然后_clean；没有在这段发送前再校验当前
room/uuid/代次。这与立即liveEnd在调用后马上_clean的时点不同，取消dispatch block
是否赶在其执行前仍是独立边界，不能把随机delay当本地时长永久延续或网络取消。
end completion0x10f0ef8e4复用上述错误分类：error=nil或error非nil但不需重试时
按patchSign移除持久项；需重试时保留。它也调用普通配置更新helper，retry参数固定0。
这些是入房/心跳/退出三种不同状态转移；完整外部取消与并发隔离仍待核对。
body与播放器延迟来源的后续证据如下。
body字段已进一步闭合：_generateBodyWithIsLiveEnd0x10f0f18d0先生成18项，再后合入
上述八项base body，得到26项。额外项按签名顺序为timestamp、secret_key、watch_time、
up_id、up_level、jump_from、gu_id、play_type、play_url、s_time、data_behavior_id、
data_source_id、up_session、visit_id、watch_status、click_id、session_id、player_type。
timestamp取_lastServerTimestamp、watch_time取计时helper，各向零截断再转String；
s_time固定"0"，jump_from仅nil改"0"（空串不在此改）；其他附加值取reportModel。
完整_keyOrderList把前三个base字段platform/uuid/buvid、seq_id/room_id/parent_id/area_id
放最前，18项随后，client_ts最后。session_id取reportModel.sessionID，是直播模型
字段，不应自动替换成HTTP公共Session_ID。

播放器适配器入口已找到：BBLivePlayerAdapterReport._startWatchDuration0x10f0e8db4
把自身playerHeartReportModel交可响应delegate的playerAdapterReportModel:补充字段，
再检查delegate的playerLoadedType原始值恰为1；
满足时把self设shared reporter.dataSource，再liveStart。这里检查的是loadedType，
不能因拒绝日志写着not live就改称liveStatus判断。_stopWatchDuration0x10f0e8f84
先检查/取消尚在随机延迟的end，另reportAbsoluteDuration，再调用liveEnd。
_randomStopWatchDuration0x10f0e93d8取arc4random()%50+10作为Double秒delay，
传入当前playerHeartReportModel的copy。1,006个假数离线核对该除法/余数指令等价，
零差异，只验证10–59秒的算术，不证明运行时分布或实际停止触发频次。
pausePlayerHeartReport0x10f0e7e10读取isWillEnterBackground字节（getter0x10f0ea2e0，
实例+0x11）：恰为1走_stopWatchDuration，否则走随机延迟end；stopByNotice
（getter0x10f0ea2d0，+0x10）为1时随后清零。continue0x10f0e800c与resume
0x10f0e82e8先检查/取消待发随机end，再清stopByNotice并重读randomlyDelaying；
false才调用_startWatchDuration；其后shared reporter.liveStart另有上述isHeartBeating
门禁，不能将adapter调用本身当已发HTTP，也不能把这个共享BOOL当账号/房间代次校验。
terminalPlayerHeartReport0x10f0e850c只停止自身playerHeartTimer并置nil；该方法体
没有调用watch-duration reporter.liveEnd，其计时器与reporter的60秒timer不同。

上游BBLivePlayerAdapter.playbackStateDidChange0x10f0c9eb8按原始状态分派：
3走continue；1、5、6跳过pause/continue；4更新binder后pause，其余值走pause。
这些是原始枚举值，尚未替它们命名成播放/缓冲/结束语义。
playerDidLoadHandle0x10f0c3c20先执行其他tracker，再要求willStartupHeartTrack
字节恰为1（0x10f0c3d10），当即清零，随后更新playerHeartReportModel的gu_id
（resolverModel.neuronSession）、data_source_id、data_behavior_id及click_id
（后三者来自roomAdapter），尾部0x10f0c3ff4在updateFirstReport后调用resume。
不满足入口字节时跳过这一段，不能概括成每次first-frame都重新入房。
loadStateDidChange:reason:0x10f0ca1ac的非零入参分支会pause（0x10f0ca400）；
零分支执行buffer结束处理后直接跳过pause。这里保留BOOL分派，不补未知业务枚举。
报告模型更新0x10f0f2dac仅在dataSource响应
reportModelForWatchDurationReporter时取其模型copy，未识别到账号或请求代次比较。
该dataSource方法0x10f0ea1f4实际tail转playerHeartReportModel getter0x10f0ea25c，
getter非nil复用同模型、nil才分配BBLivePlayerAdapterReportModel。桥接stub的邻近
符号标签可能误导，已按其实际branch目标核对selector。
shared reporter由0x10f0ec1e4的process dispatch_once缓存；dataSource是weak属性
（0x10f0f3bc4/0x10f0f3bdc）。adapter先改shared dataSource0x10f0e8efc，之后才
调用liveStart，故已在上报而拒绝新start时仍可能改变之后timer更新模型的来源；
没有在此setter或start门禁比较source/room一致性。_reset保留reportModel字段，
_updateReportModel在source不存在或不响应时不主动清旧模型。这是局部复用边界，
真实多播放器选择、外部串行约束及并发房间行为仍未验证。
字段补充从adapter.playerAdapterReportModel:0x10f0b8c20转给可响应dataSource的
playerAdapter:reportModel:；DelegateCenter0x10f0d4a14分别转发主delegate与delegates。
已定位NewRoomBaseVC0x10ed7fd78、RoomCoordinatorVC0x10ed95b7c，都读取
dd.live_coordinator_update_report_model（default=true），开启才调用房间分发器
updatePlayerAdapterReportModel:0x10eda1a54。此分发器补roomID、visitId、jumpFrom、
roomInfoModel.areaID/parentAreaID/upSession/upID、roomAnchorModel.level，以及自身
sessionID（0x10eda1dc0→0x10eda1dd8）。model.sessionID getter0x10f0eb7e8是ivar读取，
setter是nonatomic copy，非HTTP公共session getter。分发器sessionID getter
0x10edab5c0读取实例+0xb0；Coordinator._setupRoomInfoDataDispatcherWithParams
先从路由params[sessionID]取值、bfc_urlDecodedString后保存0x10ed8f040，
若保存值length为0，再从params[session_id]同样解码保存0x10ed8f228。
另一个RoomNavigator入口0x10ecd7a20直接取params[session_id]并保存0x10ecd7a60。
因此至少这些入口来自跳转参数，不是每次心跳自动生成session；上游参数最初生成与
其他writer仍需核对。false配置下保留旧model字段与外部其他delegate写入不能省略。
另外mutableCopyPlayerRoomDataDispatcherWithRoomID:officialRoomID:params:store:
0x10ed9b7d4创建新房间分发器，读取旧self.sessionID后mutableCopy，再set到新对象
（0x10ed9ba78/0x10ed9ba88/0x10ed9ba98）；同路径也复制data_source_id、data_behavior_id、
clickID和launchID。已定位caller为Coordinator.bigRefresh0x10ed8b884，以当时旧
roomInfoDataDispatcher和入参roomID/officialRoomID/params发起复制（0x10ed8b920）。
捕获新对象的后续block0x10ed8bfe8先reset旧module/store，再将捕获分发器安装到
弱取的Coordinator（0x10ed8c070）。捕获保存于block+0x20
（0x10ed8bd8c/0x10ed8bd98）；helper0x1153a0398在main直接调用block，off-main
dispatch_async到main（0x1153a03d4/0x1153a03dc）。因此该路径会沿用旧session，
而非必从新params重建；其他随后writer及跨房间实际送达仍未验证。
系统入口也有真实接线：initWithRoomAdapter在0x10f0b7280调用installNotifications
（0x10f0c0810），把自身以object=nil注册didBecomeActive、willResignActive、
didEnterBackground、willEnterForeground及protectedDataWillBecomeUnavailable等通知。
willResignActive0x10f0c0b24先对当前playerReport写willEnterBackground=true，
willEnterForeground0x10f0c0ed4则写false；不是reporter从UIApplication自行推断。
resign方法只在delegate可响应且isPlayMiniScreenplayer返回真、PiP未开启、mini后台
音乐未开启时tail调用adapter.pause；其余该方法分支不主动pause，不能把所有
resign通知都算观看结束。didBecomeActive0x10f0c11a8走recoveryPlaybackAndResetData
（0x10f0c11e4）：delegate若实现isAutoPlayInApplicationStateLaunch且返回false则
不调用play；未实现或true时，mini=true可绕过manualPause，否则要求未手动暂停，
并且readyToPlay=true才调用play。该入口本身不直接调用reporter.liveStart；后续播放
状态回调与前述continue/resume门禁仍适用，不能把每次active都算入房HTTP。
adapter.playerReport getter0x10f0c8a90已有对象则复用，nil才创建
BBLivePlayerAdapterReport并把delegate设为该adapter，不是全局shared adapter report。
同一adapter初始化还addHeartbeatTracker0x10f0c2ab8，将BBLiveOldHeartTracker与
BBLiveOldHeartRepairTracker加入以自身identifier创建的PlayerEventDispatcher，再注册
到EventCenter。这是并存的不同报告接收者，不能把旧事件通道与watch-duration HTTP
合成同一个timer/请求/去重状态；具体旧handler事件门禁仍须分别核对。

销毁入口playerControllerWillDestroy0x10f0c926c先比较传入controller与当前实例
相同，才继续；先terminalPlayerHeartReport停自身timer，再destoryPlayerEvent
（0x10f0c9348）。后者0x10f0e8cbc先取消待发随机end，再检查stopByNotice的bit0；
置位则返回，否则调用_stopWatchDuration→liveEnd。因此“terminal不发end”只描述
该单个方法体，上游组合销毁路径另有有条件的观看结束，不能遗漏或视为无条件。

## 搜索请求与查询会话

BBHD2PhoneSearchResultVM.querySearchResult:focusUpdate:...（0x10de96570）对空查询、
loading、分页结束设入口检查，维护 latestQuery/source/is_org_query、offsetPage，
并按 searchType 分派综合/分类搜索；tryAv 分支还支持将编号查询转入视频入口。
搜索历史写入发生在请求成功之前，不能从本地历史条目推断搜索请求成功。
完整 UI 提交来源、分类枚举、编号识别和并发取消的回调防串扰仍待核对。

综合 searchAll（0x10de97108）先查 useGrpcSearchAPI；helper 0x112758504 使用
实验键 search_grpc_pagination_hd、presetHitValue=0。命中则转 grpcSearchAll，
否则创建 BBHD2PhoneSearchApiV2，赋值 page=offsetPage、pageSize=20、keyword、
order、type、duration、rid、fromSource、recommend=true、is_org_query。
local_time 由 localTimeZone.secondsFromGMT 整数除以 3600 得到，非完整时区标识。
offsetPage==1 时用 NSUUID.UUIDString 更新 VM.qv_id，其他页复用 VM.qv_id，
再赋给本次 API。因此 qv_id 是查询分页层的会话，不能用 App Session_ID 替代。

ApiV2.params（0x10de728a0）先 mutableCopy preloadUrlParams，再覆盖 11 个字段：
keyword（nil→空）、pn、ps、duration、order、rid、from_source（nil→空）、
highlight=`1`、recommend、is_org_query、local_time；整数/布尔经 NSNumber.stringValue。
order 直接索引 `[default, view, pubdate, danmaku]`，未在此 getter 看到边界 clamp。
qv_id.length>0 时再加入 qv_id。预加载参数来源见前节，不能默认全为固定值。

addToQueueAsync（0x10de7309c）以 `https://app.bilibili.com/x/v2/search` 创建
BFCApiOptions，设置 modelDescriptions/params、completion、可选 customResponseAfterRequest、
cachedHandler 与 errorHandler，然后 BFCApiRequest.requestAsync；此层未显式改 method，
零初始化 method=0 进入公共 builder 默认 GET 构造路径；customRequest/
requestInjection 仍可修改。缓存触发见公共层，具体业务配置仍需核对。成功桥接 block
（0x10de73244）从模型路径取 nav、season2/movie2/archive/upper/operation/
suggest_keyword、item、trackid、exp_str、easter_egg、ogv_card、esport 等结果。
旧模型数组与新接口返回的分页游标不能混用。

grpcSearchAll（0x10de96a4c）在已有 dataSource 的后续页调用 nextPageWithCompletion；
初次创建 BBListSearchMainDataService，传 keyword、from、extraInfo.from_trackid、
isOriginalSearch，并将 forcedChatCard 设假。首次 update 另传 order、duration/rid
数组及 pull-refresh 信息。Swift service 会读取 BAPIPolymerAppSearchV1SearchAllResponse
的 pagination.next 更新状态。

实际 SearchAllRequest 创建段 0x1036d0888→0x1036d08c4、发送段 0x1036d1cb8
调用 Search.searchAllWithRequest:handler:。描述符（0x113da34fc）有 24 项：

| 字段号 | 字段 |
| --- | --- |
| 1–6 | keyword、order、tidList、durationList、extraWord、fromSource |
| 7–12 | isOrgQuery、localTime、adExtra、pagination、playerArgs、fromExtra |
| 13–18 | forcedDisplayChatCard、isRefresh、refreshTimes、since、pubTimeBeginS、pubTimeEndS |
| 19–24 | allDoubleColumn、userAct、needOgvExtraWord、filterMap、foldable、isWideScreen |

创建段已核对：fromSource/keyword 来自 service 实例；order 优先 sortRawValue，否则
sort 枚举，有 Int32 转换溢出检查；isOrgQuery/forcedDisplayChatCard 来自初始化状态；
adExtra 取 BBAdReport.requestAdExtra；localTime 为当前时区偏移小时；playerArgs
由 preloadUrlParams 映射；userAct 向用户行为服务取值。durationList、tidList 经字符串
数组以逗号拼接；duration 有 rawValue 优先和枚举转换路径，不能按字段名推断其单位。
isRefresh/refreshTimes/extraWord/fromExtra/filterMap 向各自实例状态取值，refreshTimes
也做 Int32 转换检查。allDoubleColumn 只在对应实例开关为真时显式置 1。
此段未见给 needOgvExtraWord/foldable/isWideScreen 赋值，仍需检查后续注入层。

日期筛选builder局部已独立闭合：service.since OptionalString非nil才
setSince（0x1036d0d80–0x1036d0dbc），没有length>0门禁，空String仍可设置。
随后独立读取customDateRange（ivar0x120421038），Optional无值则跳过日期两项
（0x1036d0e28–0x1036d0e44），不由since是否存在决定。存在时取range起点，
Calendar.current.startOfDay（0x1036d0e74）→timeIntervalSince1970
（0x1036d0e98），检查有限及Int64转换范围后FCVTZS截断写pubTimeBeginS
（0x1036d0ee4–0x1036d0ef4）。终点经helper0x1036d15cc：使用当前Calendar的
startOfDay（0x1036d1724），再date(byAdding:day,value:1,wrapping:false)
（0x1036d1728–0x1036d1758），成功取下一天起点减1秒
（0x1036d17c0–0x1036d17d8）；若calendar加一天返回nil，则用输入终点原始
epoch秒（0x1036d1798–0x1036d17a0）。外层同样有限/Int64边界检查后截断写
pubTimeEndS（0x1036d0f04–0x1036d0f4c）。这不是UTC固定起点+86400秒，
也没有在该body交换起止/清since的分支；实际UI输入、时区变化及日期范围写入
仍须沿consumer核实，不据可选字段存在宣称每次搜索都带日期。

BBListSearchMainDataService自身的实现选择另有process-once flag，不能直接视为
外层每次searchAll的实验查询。initializer0x1036cb0b8对bfc_isIPad=true才读
search_grpc_pagination_hd/preset0（0x1036cb0e0–0x1036cb104），phone分支固定1
（0x1036cb118），保存0x120420e28；once token0x120420e20。
nextPageWithCompletion0x1036cb8b8将空附加参数map传helper0x1036cb598，flag
恰1才用grpcService，否则httpService（0x1036cb618/0x1036cb750）；选中service
nil直接退出0x1036cb880，该body没有转另一个service的fallback。
grpc分支记录requestDidStartTimestamp，并把isPullRefresh附加参数值与String
"1"比较后更新service布尔；附加map空/该key缺失时走0x1036cb808，未在此明确
重置旧isPullRefresh。其generic send结果closure0x1036ce964→0x1036cee3c拆
pointer/tag，实际captured callback0x1036ce954→0x1036cb944。后者weak main
service存在时先写requestDidEndTimestamp；error-tag分支直接交错误callback，
不更新hasMoreData。success且weak service存在时要求response.pagination与next
非nil（nil各到BRK 0x1036cbba4/0x1036cbba8），按next String是否非空写
hasMoreData（0x1036cbaec–0x1036cbb20），再交业务callback
（0x1036cbb60）。没有以返回卡数代替游标判据；weak service失效仍可交结果。
这段callback未见查询/账号generation比较，不能据现对象存在推断旧回执属于
最新query；是否由外层取消/服务生命周期隔离仍待另证。
公开BBListSearchMainDataService.cancel:0x1036cc8d8本体仅检查上述once token，
未初始化时tail swift_once初始化flag（0x1036cc8ec–0x1036cc8fc），已初始化则直接
ret；没有读取httpService/grpcService/currentRequest、调用cancel、清游标或增加
generation。仅调用这个selector不能视为已中止底层或已过滤旧回执；其他UI/
外层VM取消链需分开审计。该结论限定当前样本方法体，不推广到其他搜索service。

通用分页请求段0x1036d6d28创建BAPIPaginationPagination，pageSize和next分别
由service witness+0x40/+0x28取得（0x1036d6db8–0x1036d6dd8），不是仅据属性名
断言读取maxLength。当前All binding witness0x120421820的+0x40实际
0x1036d29e8固定返回20；constructor0x1036d0644的maxLength+0x28实际来自
list.search_word_max_length/default150（0x1036d0698–0x1036d06d8），不能把该
值当pagination.pageSize。+0x28→0x1036d4f70→0x1036d44f8读取实例+0x10的
OptionalString nextToken。构造中next nil传nil，非nil（包括空String）bridge后
setNext（0x1036d6e18–0x1036d6e4c），没有空游标拒发门禁。request getter
witness+0x48→0x1036d29f0→0x1036d083c创建上述SearchAllRequest，随后关联
pagination，再通过send闭包witness+0x50→0x1036d2a14。日期筛选的
since/customDateRange UI来源、完整 PlayerArgs 默认值、空游标结束判断、HTTP 回退
条件及实际 UI 采用哪一实现仍在追踪。本文尚未用同版本样本验证搜索链。

## 动态综合页请求

Swift DFSumViewController.loadAllData(refreshType:) 内部 0x10136b274 创建普通 DynAllReq，
随后清 BBMFRefreshSingleton.isCoolBoot；selectedUpItemModel 存在时另创建
DynAllPersonalReq 并调用 dynAllPersonalWithRequest，普通分支在 0x10136b4ac 调用
Dynamic.dynAllWithRequest。因此不能用普通综合页的请求字段替代选中 UP 分支。
入口完整 loading/登录/分页结束保护与 UI 刷新枚举尚在追踪。

普通请求 builder 0x10136b4e8、描述符 0x1162131b4 已定位 18 项：

| 字段号 | 字段 |
| --- | --- |
| 1–6 | updateBaseline/string、offset/string、page/int32、refreshType/enum、playurlParam/message、assistBaseline/string |
| 7–12 | localTime/int32、rcmdUpsParam/message、adParam/message、coldStart/int32、from/string、playerArgs/message |
| 13–18 | tabRecallUid/int64、tabRecallType/enum、tabRecallExtra/string、reqSortOption/message、bubbleRecallExtraWhenShow/string、sessionId/string |

updateBaseline/apiOffset/page 向 VC 状态取值，refreshType 来自入参；tabRecallUid/type
向 RefreshSingleton.sumVCParams 取值。playurlParam 取 BBDFApiHelper.reqPlayurlParam，
helper（0x10e7b4cdc）从 BBPlayerPreloadUrlParamsHelper.preloadUrlParams 取
fnver/fnval/fourk/qn/force_host 转 intValue，填 BAPIAppDynamicV2PlayurlParam。该对象
保存在静态引用；仅首次对象创建时赋 fnver/fnval/fourk，后续每次更新 qn/force_host。
因此不能把五项都描述为每次按最新能力重算，清空该静态引用的其他路径仍待追踪。
playerArgs 则另读 VC getter；rcmdUpsParam.dislikeTs 来自 0x101371fdc 的本地 getter，
其保存与消费仍待确认。adParam.adExtra 由调用 getter 提供，nil 转空。localTime
取当前本地时区在 Date.now 的偏移秒数，整数除以 3600 向零截断（172,801 个假偏移
算术等价核对通过），不是分钟偏移。coldStart 取 singleton.isCoolBoot 的 1/0；
由于父调用在 builder 之后才清该状态，不能把首请求一律写为 0。

tabRecallExtra/bubbleRecallExtra nil 退空；sessionId 取 VC 的同名状态，其专用生成规则见下节。reqSortOption.sortType 取 0x10135a1d8 的设置 getter，
isColdRefresh 取 VC.isAllFirstReq。该 builder 未见显式赋 assistBaseline/from，
不能凭描述符补常量。排序设置、首次状态重置、offset/baseline 响应更新、卡片处理与
缓存持久化尚未闭合，未执行同版本包或请求服务端。

### 选中 UP 的独立请求

BBDFHDHelper.dynamicAllSelectedUpRequestWithRefreshType:page:（0x10e8c7204）构造
DynAllPersonalReq，描述符 0x11621405c 的字段为：1 hostUid/int64、2 offset/string、
3 page/int32、4 isPreload/int32、5 playurlParam/message、6 localTime/int32、
7 footprint/string、8 from/string、9 playerArgs/message、10 personalExtra/string、
11 adParam/message。hostUid 取 selectedUpItemModel.uid（跳板 0x10f88ef88 明确跳至
uid，不能误认最近符号 mid），offset/footprint 取 helper 的状态，footprint nil 退空；
page 取参数，isPreload 明确 0，localTime 取本地时区偏移秒/3600，向零截断。
playurlParam/playerArgs/adExtra 都来自 BBDFApiHelper；未见赋 from/personalExtra，
refreshType 参数也未在此 builder 消费。此分支没有普通 DynAllReq 的 baseline、冷启动、
排序和 session 字段，不能沿用普通请求表。

BBDFApiHelper.playerArgs（0x10e7b4e6c）使用另一个静态 PlayerArgs 对象：仅首次
赋 fnver/softFnval/fnval，之后每次更新 qn/qnPolicy/forceHost/voiceBalance/clientAttr/
extraContent。qnPolicy 先通过枚举有效性函数 0x116450b8c（UInt32 值<2），不合法退 0；上述值
均取 preload helper，extraContent 单独取其 getter。这与 PlayurlParam 的静态缓存
是两个对象；能力变化后的其他失效机制仍待确认。

综合页 rcmdUps 取值 helper（0x101371fdc）读取 standardUserDefaults 的
`dt_user_dislike_uid`。能转换为 NSNumber 时才与 currentUser.mid 比较；当前用户不存在
或 mid 不同，则把 `dt_user_dislike_timestamp` 写为 NSNumber(0)，并返回 0
（0x1013722ac–0x101372320）。uid 缺失或转换失败时却直接继续读取 timestamp，
并非一律返回 0；timestamp 能转换为 NSNumber 则取 longLongValue，否则退 0。
该 getter 有清理副作用，但正值写入入口、时间单位和对应不感兴趣 UI 尚未闭合。

### 排序选择、账号缓存与刷新触发

sortBy helper（0x10135a1d8）在综合页 isAllFirstReq=true 时从本地排序缓存读，
否则取 allSwitchSortOption.sortType；视频页按 isVideoFirstReq/videoSwitchSortOption
同样分支，其他 tab 或后续 option/sortType 缺失退空字符串。
本地 helper（0x10e7bc630/0x10e7bc738）使用 standardUserDefaults，key 为
`dynamic_switch_sort_` + tab suffix + `_` + currentUser.mid 十进制，无用户经
objc_msgSend(nil) 得 0。写入 setValue 后 synchronize。读出前还检查旧无账号 key
`dynamic_switch_sort_` + suffix：有非空旧值则先写新账号 key，删除旧 key，再返回旧值；
否则读新 key，nil 退空。这个迁移只按调用当下的账号写入，并非所有账号共享读取。

排序按钮 handleSwitchSortBtnAction（0x101360308）先同步卡片选中状态，再进入
0x10135fea8。综合页把当前 option 保存为 last_allSwitchSortOption，替换为点击传入
option；sortType 非 nil 才缓存并构造 Neuron 点击 `dt.dt.rank-sizer.tab.click`，
随后调用刷新 helper 0x10136758c。该 helper 经 0x101367724 在 main queue 的
DispatchTime.now()+0.3 秒安排 0x101372788→0x10136a970，最终调用 collectionView 的
bfc_triggerPullToRefresh。已证的下拉 handler 对综合页传 refreshType=0，进入会话
重置段；触发控件对正在刷新状态的抑制条件仍需核对。sortType=nil 的按钮路径没有
经过这里的缓存/事件/刷新正常分支，不能只凭点击就断言一定产生网络请求。

### 综合页刷新与专用 sessionId

loadAllData 的实际 body（0x10136aad4）先检查 isLoading，已有加载立即返回。
refreshType 原始值为 0 时设置 page=1、清 synthesizeHDHelper.offset、生成新的
VC.sessionId，并把它合入 trackExtra/pvExtras；非零值跳过该重置段，复用已有会话。
随后置 isLoading=true/isFeedRenderEnd=false 并进入请求。apiOffset 与 helper.offset
是不同属性，不能因这个清空动作断言请求字段 offset 也已清空；其他分页入口待串联。

sessionId helper（0x10136180c）明确生成：
`dynfeed_` + 跟踪 BUVID + `_` + Int64(FRINTA(DateUnix×1000)).decimal + `_` +
UUID().uuidString。浮点转整数有有限值/范围保护，FRINTA 是最近整数、半值远离零。
该字符串没有 MD5/FNV/大小写转换，并且带新 UUID，不能与公共 Session_ID、播放器
session 或 login_session_id 合并为同一个字段。上述刷新原始值 0 是已证消费分支，
已闭合下拉 UI：viewDidLoad 中 0x101368f3c 将 block 0x101371c1c 绑定
bfc_addPullToRefreshWithActionHandler，block→0x101369b1c 在综合页传原始值 0。
同一 viewDidLoad 尾部 0x101368fb4 明确置 singleton.isCoolBoot=true，因此此状态
并非已证仅在进程冷启动设置；VC 重建是否发生需另有生命周期证据。其他入口与
分页原始值仍待核对。

VC.loadDataWithRefreshType:（0x10136a9b0）按当前 dataTypeName 路由：等于
allTitle 调上述 loadAllData，等于 `video` 调独立视频列表，否则调第三分支；不能将
综合页 builder 归为所有动态 tab 的通用请求。缓存读取的 completion
0x10136ecc8 仅在 VC 仍存在且 response 非 nil 时调用普通卡片转换
0x10136cef0，传 isLocalData=1，替换 dataSource 并执行无动画 adapter 更新；
这条 completion 没有直接将缓存 response 的 baseline/historyOffset 写回请求状态。

选中 UP 的回调另经 0x101372838→0x101366220，closure 只捕获 VC 与刷新原始值，
已读入口没有普通 DynAll 的 captured dataTypeName 比较。error 非 nil 清补页计数、
置 renderEnd 并 toast；error=nil 时 raw0 清旧列表，再转换/追加 section。
完成路径 page+1，以 PersonalReply.hasMore 更新 VC.hasMore，并将 reply.offset
（nil 空）写 synthesizeHDHelper.offset（0x101366564），不是 VC.apiOffset。
raw0 且当前 selectedUpItemModel 非 nil 时清其 hasUpdate 并更新红点；随后转换数组
长度进入同一个自动补页 helper（0x1013666e4）。选中项变化时的取消/过期回执抑制
尚未闭合，不能把这段状态写入推广为不会受旧请求回执影响。

### 条目不足时的自动补页

普通响应调用 0x10136cca0 将卡片转换 helper 0x10136cef0 返回的
BBDFSectionCardModel 数组长度与 VC.hasMore 交给 0x101361b6c；这个计数是转换后的
section 数，不能直接当作原始 response item 数。helper 累加 tempItemCount，
累计大于 9、loadMoreCount 大于 2、hasMore=false 或
noAutoNextPageWhenUnsatisfied=true 时停止并清两个计数器。否则先递增
loadMoreCount、置 isLoading=false、停止下拉动画，再按当前 tab 路由发原始值 1
的加载请求；综合页重新进入 loadAllData。因此从计数器为 0 开始最多额外发三页，
累计等于 9 仍可补页。此逻辑在成功处理后补足条目，并非错误重试。
noAutoNextPageWhenUnsatisfied helper（0x10135a3b4）在综合/视频页分别读对应的
SwitchSortOption；对象缺失或其他 tab 返回 false。其他分页调用点及这些设置的
写入来源仍需继续核对。

### 视频 tab 的独立 DynVideo 请求

视频加载 body（0x101357ec8）同样以 isLoading 拒绝重复进入；refreshType=0
才 page=1、调用同一个 dynfeed_ session helper并写 trackExtra/pvExtras，非零复用。
调用 Dynamic.dynVideoWithRequest:handler:（0x1013583b8），没有套用综合页 DynAll。
DynVideoReq descriptor（0x116213004，数组 0x1208560e0）为 11 项：1:updateBaseline
string、2:offset string、3:page int32、4:refreshType enum、5:playurlParam message、
6:assistBaseline string、7:localTime int32、8:from string、9:playerArgs message、
10:reqSortOption message、11:sessionId string。

builder 0x1013583ec 赋 refreshType、共用 playurl/playerArgs helper、VC.updateBaseline/
apiOffset/page、当前时区秒数÷3600 向零截断、VC.sessionId；reqSortOption.sortType
取前述排序 helper，isColdRefresh 取 isVideoFirstReq。未在本 body 赋 assistBaseline/
from，也没有综合页的 rcmdUps/adParam/coldStart/tabRecallExtra/bubbleRecallExtra。
refreshType=0 时先从 `BBDFTabVideoCacheKey-` + 当前 mid 十进制读取 baseline 并
setUpdateBaseline，但随后 0x101358644/0x101358650 再以 VC.updateBaseline 赋同一
请求属性；中间没有把缓存字符串赋 VC.updateBaseline。因此此 builder 的最终值以
后一次赋值为准，不能仅看到 stringForKey 就宣称请求恢复了缓存 baseline。
视频响应 0x1013589e4 同样先校验捕获的 dataTypeName；通过后先清 isVideoFirstReq
再检查 error。error 非 nil 时清 loadMoreCount/tempItemCount、置 isFeedRenderEnd=true、
显示 moss_localizedDescription，并调用排序恢复 helper 0x101359048；没有在该错误
分支发自动补页。error=nil 且 request.refreshType=0 时，非 nil
response.dynamicList.updateBaseline 更新 VC.updateBaseline 并存上述视频账号 key，
随后清旧 dataSource。正常列表处理后以 response.dynamicList.hasMore/historyOffset
更新 hasMore/apiOffset，page 检查溢出后+1；转换后的 section 数再次进入同一个
自动补页 helper（0x101358fe4）。完整响应缓存与 nil/空 dynamicList 的特殊路径尚未
闭合，不能将综合页 fallback JSON 缓存直接套用到视频 tab。

另一个 Objective-C 视频页 BBDFVideoListViewController 使用 DFVideoCacheHelper，
不能与上面的 DFSumViewController.video 分支合并。其 loadAllVideo 回调
0x10e824b30 在 error=nil/request.refreshType=0 时调用 writeVideoCacheWithResponse，
helper 0x1014af924 仅 toJsonString 非 nil 才发 fallback writeAsync，scene 的 inline
字符串为 `dt.video-dt.0.0`，id 为当前 mid 十进制（无用户0），version 从 bundle
构建信息生成，expirationTime=0。完整 version 转换与时效语义尚未闭合。
fetchLocalData（0x10e824274）在现有 dataSource count=0 时 page=1 并 readVideoCache；
helper 0x1014b00a0 使用同 scene/id/version。回调 0x10e824374 在返回 reply 非 nil
时直接恢复，否则以 pvEventId 经 cacheKeyWithFlag 到 BBMFArchiveTool 读旧 NSData、
parseFromData。dynamicList.listArray_Count 非零才 transformModel:isLocalData=1
并设置 dataSource。这里的旧缓存回退位于 VC completion，与综合页 helper 的
内部 fallback 是不同结构，不能仅凭共同类名推断相同失败行为。

### 综合页响应状态与两种缓存

普通回调经 0x101372804 转到 0x10136bd04，先比较当前 dataTypeName 与发起请求时
捕获的字符串；不同则跳过正常状态更新。通过比较后先清 singleton 的
TabRecallExtra/BubbleRecallExtra，并清 VC.isAllFirstReq，然后才检查 error，因此失败
也会消耗这些一次性状态。分页结束保护不应仅看请求 builder 的赋值。

在 error=nil 且所建请求 refreshType=0 的非空 response 路径
0x10136c130，先调用 writeDynAllCache（0x101362e98），再取
response.dynamicList.updateBaseline 替换 VC.updateBaseline，并存 standardUserDefaults。
key helper（0x101371f08）为 `BBDFTabAllCacheKey-` 加当前用户 mid 的十进制，
无用户退 0。另一个读取调用在加载准备段 0x10136af44：已有 baseline 字符串为空时
才 stringForKey，缺失退空。该缓存值是 baseline，不能称为整份列表 JSON。

后续回调（0x10136c9d4）读取 dynamicList.hasMore 更新 VC.hasMore，并以
historyOffset 替换 apiOffset；historyOffset nil 退空。常规完成路径 0x10136cba4
有检查溢出的 page+1，随后更新列表 UI；无响应/空列表分支与卡片拼装仍需分别核对，
不能把这些字段更新推广到每一种失败分支。

完整响应的另一条 fallback cache 写入 0x101362e98 调用 response.toJsonString，
仅返回非 nil JSON 才继续 KntrFallbackCacheNativeKt.writeAsync:scene:id:data:version:
expirationTime:。data 为该 JSON，id helper 0x101364680 为当前用户 mid 十进制（无用户为 0），version helper
0x101364504 从 mainBundle CFBundleVersion 取 String（缺失/转换失败退空），
expirationTime 在调用点明确为 0，其语义需后端证明。写入结果另走异步回调并保存
cacheWriteDisposable；序列化失败只进入日志路径。缓存对象、scene、读出时效/账号
隔离与列表恢复仍未闭合，不将发起写入视为磁盘持久化成功。

fallbackCache getter（0x101367a38）懒读取并缓存
KntrFallbackCacheModuleKt.provideFallbackCache 的产物，不能仅凭类名确定磁盘实现。
readDynAllCache（0x101363778）使用同样 scene/id/version 调 readAsync。已确认直接
调用在 VC.viewDidLoad 的 body 0x101368cd4：dataSource 为空且 dataTypeName==`all`
时置 page=1 并读取，再进入后续 UI 初始化，不是已证的网络错误自动回退。

读取回调 0x101363d94 的 error 分支调用旧缓存读取 0x101364210；非
KntrCacheResultSuccess 或 Success.data=nil 也走旧缓存。Success.data 非 nil 时
parseJsonString:error: 为 DynAllReply，模型非 nil 即交 completion；模型 nil 则走
parse error 分支，未在这个分支尝试旧缓存。旧缓存按 VC.pvEventId 经
BBDFCacheHelper.cacheKeyWithFlag/objectForKey 读取 NSData，再 parseFromData。
恢复后列表状态、旧缓存键/有效期与后端的 expirationTime=0 语义仍需继续核对。

## 评论列表 RPC、发布与互动

### 主列表字段与分页来源

BFCCommentMossAPI.requestList（0x113f1c0a0）新建MainListReq，给pagination/
mode/oid/type/rpid赋调用参数；filterTagName只有NSString才保留，否则空字符串。
exposedCommentIds非nil才新建GPBInt64Array，按枚举顺序逐项longLongValue，赋
clientRecallRpidsArray；此body没有排序/去重。extra直接yy_modelToJSONString，
不在本体校验JSON内容。adExtra为非空NSDictionary才requestAdExtraWithParams，
否则调用默认requestAdExtra，不直接把调用字典原样赋PB。WordSearchParam每次新建，
shownCount来自调用参数。此入口未给cursor/seekRpid赋值。

MainListReq.descriptor（0x11417b3e8，表0x1207b34c8）有12项：

| 字段号 | 字段与类型 |
| --- | --- |
| 1–2 | oid/int64、type/int64 |
| 3–5 | cursor/message、extra/string、adExtra/string |
| 6–9 | rpid/int64、seekRpid/int64、filterTagName/string、mode/enum |
| 10–12 | pagination/message、clientRecallRpids/repeated int64、wordSearchParam/message |

Reply.defaultService（0x114178dcc）新建host=`grpc.biliapi.net`、isRest=false；
init连接package=`bilibili.main.community.reply.v1`/service=`Reply`，MainList方法
0x114178e14交BFCMossServiceWrapper，responseClass=MainListReply、serviceName=`MainList`。
静态可还原RPC标识`/bilibili.main.community.reply.v1.Reply/MainList`；实际host覆盖、
metadata和transport回退仍由公共Moss层决定，不把默认构造提升为全部调用的实际运输。
callback0x113f1c45c在error=nil时mapListResponse交success；有error时复制userInfo
（nil则新字典）、替换localizedDescription，经errorCode转换后用原domain新建NSError
交failure，局部未见重发。code/message具体映射和Moss公共自动机制仍需另读。

ListVM.loadDataWithCompletion（0x113f774ec）先reset搜索解析限制、清mixedCards，
调用loadDataWillStartBlock，再置isLoading=true并清插入状态；请求前从pagination
makeLoadRequestPagination，并调用_getRequestCommentIdAndResetIfNeeds与
_getExposedCommentIdsAndResetIfNeeds，不是回执成功才消费这些入口。
_requestCommentList（0x113f7ef98）从VM取oid.longLongValue/type、sortModel.sortMode、
requestExtra、requestAdExtra、filterTag.name及searchParserLimits.parsedTotalCount，
与传入rpid/pagination/exposed列表合入上述API。
BaseListVM.requestExtra（0x113f19bbc）先复制非nil NSDictionary impassiveExtra的
全部项，再仅在VM spmid/fromSpmid/trackId非nil时覆盖对应key；nil属性保留
原extra的同名项，空字符串仍覆盖。最终count=0返回nil，否则copy。
因此extra JSON不是固定三个跟踪字段，页面传入内容也可能延续到列表RPC。
两个reset helper实际是“请求过”标记，而非删字段：0x113f7c6fc在标记false时先置true，
再仅jumpCommentId>=1才返回ID；已标记或非正数返回0。0x113f7c750在标记false时
先置true再返回exposedCommentIds，已标记则nil；没有清列表自身。网络失败也已消费
标记，后续重建请求是否再带这些值取决于另外的标记重置入口。
ListVM.init（0x113f76be0）明确将两请求标记及located设false，保存传入jump ID/
exposed列表，初始sortMode=0。已找到的这两setter直接调用仅init置false与上述helper
置true；普通首屏成功/失败没有调它们重置，其他动态调用或直接ivar写入仍需排除。

BFCCommentPagination的三个builder（0x113f19048/0x113f19098/0x113f19100）均
pageSize=20：首屏offset为空，next/prev分别读保存的nextOffset/prevOffset。
updatePagination（0x113f18efc）替换两offset；mergeNext/Prev分别只替换一边；
mergeFold（0x113f18fdc）置foldPaginationEnabled=true再替换nextOffset。
sessionId独立updateSession保存；checkSessionIsExpired（0x113f18e9c）仅旧session
非nil且与输入不相等才true，旧nil返回false。
isFirstPageReached对prevOffset=nil或空都true；isLastPageReached只比较nextOffset
与空字符串，next=nil经Objective-C返回false。这里没有超时时间运算，不能称为TTL过期。
首屏成功callback（0x113f77838）先updateSession(response.sessionId)、
updatePagination(response.paginationReply)，重建sortModel为响应mode/modeText，
清isLoading/error，再_processLoadData并complete(true)。失败callback
（0x113f77b74）保存error、清isLoading并调errorRequestHandler，随后complete(false)。
虽然它先比较12002/12055/12068/12061，真正构造input_disable=true的空评论模型前
还要求code==12061，因此不能将四个错误都写成同一种禁输入处理。

loadNextPage（0x113f77db4）在isLoading或isLastPageReached时跳过；foldPaginationEnabled
时改走loadFoldPage(nil)，否则next builder发rpid=0/exposed=nil。成功
（0x113f780dc）比较旧session与响应session：变化则更新session和两offset，
用_processLoadData替换处理并调用forceRefreshBlock(nil)；未变仅mergeNextPagination
再_processLoadNextPageData追加处理。这处session失效在已经成功收到新页后处理，
没有先发另一次首屏RPC。失败（0x113f783c8）只清loading/保存error，未在本体重试。
prev请求（0x113f7841c）以isLoading/firstPageReached门控，用prev builder，
rpid=0/exposed=nil；成功0x113f7870c同样在session变化时替换处理及forceRefresh，
未变仅mergePrev并_processLoadPrePageData，后者返回值交complete(true,值)。
失败0x113f78a18清loading/存error，complete(false,Int64.max)，局部未重试。

折叠列表是另一RPC，requestListFold（0x113f1cde4）新建FoldListReq，仅赋
oid/type/pagination/extra JSON，交Reply.foldListWithRequest，成功parseListFoldResponse。
loadFoldPage（0x113f78a8c）先拒绝isLoading；普通next未到底时使用next builder，
已经到底则倒序寻找mixedCards中的FoldCardModel，使用该卡pagination；未找到或
pagination=nil不发送并complete(false,nil)。FoldListReq.descriptor
（0x11417ea90，表0x1207b8258）仅1:oid/int64、2:type/int64、3:extra/string、
4:pagination/message，不能沿用MainList的mode/曝光/搜索字段。
成功0x113f78e90只mergeFoldPagination，
清loading/error，再有completion则交true/foldListText，否则_processLoadNextPageData；
此body没有检查/更新session。失败0x113f7909c清loading/存error，局部未重试。
完整UI触发、标记其他写入与错误恢复继续追踪。

PageTableVC.refresh（0x113f5c40c）明确取viewModel.tryLoadData；ListVC.refresh
（0x113f4bdc8）先调用super这一入口，再将isFirstLoadData设false。
BaseVM.tryLoadData（0x113f1af38）先置tryLoadDataExecuted=true，再检查isLoading，
正在加载即返回，其他调用loadData。没有以tryLoadDataExecuted已true禁止再次刷新；
它是另一状态标记，不能把try前缀解读为只请求一次。

MossAPI的errorMessage（0x113f1e3c8）优先NSURLErrorDomain的userInfo描述；
其他domain有bapi_status时取其message，无status且domain=`io.grpc`时用
moss_localizedDescription，其他退userInfo描述。errorCode（0x113f1e4f0）在
非URL错误且有bapi_status时取status.code并32位符号扩展，否则保留NSError.code。
不能把所有Moss NSError.code都当成业务码，或把URL错误的数字改为业务status。

### 子回复详情的不同请求

requestDetail（0x113f1c60c）构造DetailListReq，给oid/type/root/rpid/mode/
pagination/scene/needSubjectTitle赋调用参数；extra与adExtra生成规则同上述MainList，
交Reply.DetailList，成功mapDetailResponse。descriptor（0x11417b138，
表0x1207b30e8）为11项：1:oid/int64、2:type/int64、3:root/int64、4:rpid/int64、
5:cursor/message、6:scene/enum、7:mode/enum、8:pagination/message、9:extra/string、
10:adExtra/string、11:needSubjectTitle/bool。本builder未赋cursor；没有MainList的
filterTagName/clientRecallRpids/wordSearchParam，不能把主列表字段整套复制到详情。

DetailVM.loadData（0x113f690e8）在isDeletedRootComment时跳过；其他先清mixedCards、
调willStart、置loading、清fakeCommentIds，用首屏分页builder及一次性jump rpid helper。
取rootCommentId、detailSortModel.sortModel.sortMode、sceneType及requestExtra发送。
needSubjectTitle helper（0x113f6d190）仅传入rpid>=1、bizType原始7、sourceType原始6
同时满足才true，具体业务枚举未命名。成功0x113f695f8更新session和两offset、清
loading/error，捕获的needSubjectTitle恰为1时保存subjectTitleModel，再_processLoadData、
complete(true)；失败0x113f69838清loading/存error、complete(false)，本体未重试。
详情next/prev/fold、排序选择以及跳转UI绑定仍需继续贯通。

### 排序操作到重新请求

ListContainer.switchSortMode（0x113f44370）转currentVC.switchSortMode。
ListVC实现（0x113f4f574）只处理VM.showType=1且当前sortMode非1；当前2改3，
其他非1值改2。它先写VM.sortModel，再在table可下拉且disablePullRefresh=false时
triggerRefresh(true)，其他分支直接refresh，进入前述tryLoadData/List RPC；
不是只本地重排。随后setOrdering读readableString（0x113f193cc）：mode2=time，
mode3=heat，其余空。业务埋点reportClickMore中的state由旧mode3产生2、其他产生1，
不能把该埋点state当成新RPC.mode。showType/mode1阻断以及刷新已有loading门槛
仍然适用；按钮/可访问性入口与详情sort链继续核对。

### 广播插入与单条评论补取

ListVC.didReceiveNotice（0x113f56080）对ReplySubjectReplyInsertionResp先比较
消息oid与当前oid.longLongValue；不同退出。ignoreInsertCard(rank)为true或
config.sourceType==2也退出。随后枚举supportModeArray与当前sortMode比较，
只有支持该模式才getPreInsertModel、保存insertTagModel，并调insertNewCommentV2。
同入口对ReplySubjectInteractionResp同oid则调用likeUpdateHelper.start/decelerate/
didReceiveMessage，不走单条补取。广播订阅、连接与消息解码仍未闭合。

insertNewCommentV2（0x113f5650c）检查waitingRequest、tag.shouldInsert及rpid与
current/preInsertCard的重复；通过后计算插入位置、置waitingRequest=true，再调
ListVM.loadNewCommentV2→_getNewComment（0x113f7e880）。非nil tag才发
MossAPI.requestCommentWithRpid（0x113f1d434），构造ReplyInfoReq赋rpid及
bizScene=1，交Reply.ReplyInfo。descriptor（0x11417dce8，表0x1207b7350）
三项为1:rpid/int64、2:scene/enum、3:bizScene/enum；该builder未赋scene。
nil tag分支只记录日志，本体未调用completion，不概括为false回调。

补取成功callback（0x113f7e9cc）在model为nil、blocked或已在indexFilter时
complete(false)；其余先addItemToIndexFilter、setTagModel、applyToListRootComment、
enableFold=true、预计算高度，保存preInsertCard后complete(true)。此时尚未直接插列表。
失败callback（0x113f7ebe0）记录并complete(false)，没有业务重试。
VC callback（0x113f56810）先清waitingRequest，仅success非零继续；当当前tag.rpid
匹配preInsertCard或currentInsertCard时清insertTagModel，随后调用
insertNewComment(preInsertCard)。不匹配时保留tag但仍进入该插入调用，不能写成
“响应与最新tag不一致就丢弃”。实际索引计算与替换规则仍待解码；此链不证明键盘
发布成功必然同步插入，也不把广播消息本身误作HTTP发布回执。

ignoreInsertCard（0x113f77190）虽接收rank，已读方法没有使用该入参；返回true
条件是ignoreInsertNewCard、callbacks.getEnum(0,"Insert")的bit0，或
insertEffectRanges.count非零。不能把方法名或rank入参改写成已证明的排名阈值。
insertNewComment（0x113f5716c）要求model非nil、与currentInsertCard非同一对象、
VC.shouldInsert非零；置waitingInsert，按tag重新计算indexPath。nil indexPath时
只记日志并清waitingInsert；有效时在table begin/endUpdates之间向VM.objects
insertObject(atIndex)，再insertRows，更新相邻分隔线/行、保存tag.insertIndexPath、
currentInsertCard并清waitingInsert。这里比较的是对象身份，不是另一轮rpid去重。
tryInsertNewComment（0x113f5765c）有tag时再走V2补取，无tag且pre/current对象不同
时尝试直接插preInsertCard；后者并非重新请求ReplyInfo。

### 评论广播房间与双向流

ListContainerVC.viewWillAppear（0x113f40e74）仅
comment_support_moss_streaming实验命中（preset1）时注册BFCCommentBroadcast
handler；weak callback 0x113f410f8调用handleReply。viewDidDisappear
（0x113f41148）同实验gate下unregisterComment并leaveRoom(type,oid)。ListVC
tableView.willDisplayCell（0x113f4e4e8）则在本体前段直接按config.context.type/oid
调用joinRoom；这里没有同实验检查，也没有只第一个cell的检查。

Broadcast register（0x114025b80）将新handler设为当前值并追加RAM数组；unregister
（0x114025c00）删除末项，改用剩余末handler或nil。不是向所有已注册handler广播。
joinRoom（0x114025cf4）拼`reply://<oid>_<type十进制>`（format=%@_%lld），先将
本地room state的semaphore+1；joined=true时不再向RoomCenter join，否则加入并
注册reachability observer。joined仅didStartWithRoomId（0x114026790）写true，
不是发出join即确认。leaveRoom将计数-1并按32位结果负数归0，仅结果0时forceLeave；
forceLeave调用RoomCenter.leave并以新空state替换该room字典值。这些是RAM状态，
未见账号隔离或持久化；多cell/多页面的引用配对仍需核对所有调用者。

RoomCenter.joinRoomId（0x114895c20）拒绝nil observer/空room，锁内按room查弱引用
hashTable；当前count=0才调用service.join，随后add observer并保存。leave
（0x114895d7c）对count<=1移除room并发service.leave，其余只移除该observer。
具体弱引用回收与重复willDisplay的实际行为未运行验证。
lazy service（0x1148966ac）创建BFCRoomService；其init（0x1148968a8）在传入
BFCMossCenter上注册`/bilibili.broadcast.v1.BroadcastRoom/Enter` bidi，响应类
RoomResp，GRXWriteable callback转RoomCenter响应/错误处理。join/leave/online
各构造RoomReq赋id_p及相应空event对象，再writeMessage；sendMessage则赋id_p、
msg.targetPath、msg.body=GPBAny(anyWithMessage,error:nil)。不是三套独立HTTP URL。

描述符（0x114afb348/0x114afb420/0x114afb4a8）已恢复：

| PB | 字段编号与类型 |
| --- | --- |
| RoomMessageEvent | 1:targetPath/string、2:body/message（Any） |
| RoomReq | 1:id_p/string；event oneof的2:join、3:leave、4:online、5:msg均message |
| RoomResp | 1:id_p/string；event oneof的2:join、3:leave、4:online、5:msg、6:err均message |
| SubjectReplyInsertionResp（0x1140c9d34，表0x1207b16a8） | 1:oid、2:type、4:rpid、5:timestamp、6:rank、7:stepSize为int64；3:title/string；8:supportModeArray、10:supportTagIdsArray重复int64；9:supportTagArray重复string |

响应按id_p取observer快照、解锁后分派online/message/error/join事件；join交
didStartWithRoomId，评论Broadcast将joined=true。评论message入口
resolveCommentMessage（0x11402613c）要求body.value非nil且NSData，按targetPath
精确匹配`/bilibili.broadcast.message.reply.Reply/`下的SubjectNotice、
SubjectReplyInsertion、SubjectInteraction，再用对应PB initWithData:error解析；
插入/互动在解析error=nil且当前handler存在时交当前handler。未知path不处理。
ListContainer对插入消息supportTagArray非空时向符合filterTag.name的contents分派，
空数组时与其他消息一样交currentVC（0x113f42834–0x113f42854）。后续ListVC再做上述oid/mode gate。

RoomCenter的重入不是所有错误通用重试：notifyObserversWithError
（0x1148963bc）仅domain=`io.grpc`且code=110303（0x1a000+0xedf）时向现有
observer调用didRestarted并rejoinRooms；后者锁内枚举现有room keys重新service.join。
评论Broadcast.didRestarted仅日志，mossReachabilityDidChange读isReachable但本体未
重新join。连接建立、鉴权metadata、传输退避/流恢复仍属公共Moss层缺口，不能由
这些room方法推出后台常驻或断网自动恢复。

### 发布字段与验证码续提交流程

BFCCommentPosterApi 根评论 builder（0x11407c16c）构造 message=传入文本、root=`0`、
oid/type 的 NSNumber.longLong→stringValue、plat=`3`，并从 extra 对象分别取
from/scene/ordering/from_spmid/spmid/track_id/goto/container_uuid；extra 字符串
nil 退空。子回复 builder（0x11407c51c）以传入 rootRpid 替换 root，另赋
parent=parentRpid 十进制；并非只改 message。这些 builder 没有在已读 body 先做
空文本/oid 正数/登录校验，UI 与更早模型校验仍需串联。

统一发送（0x11407c934）向 `https://api.bilibili.com/x/v2/reply/add` 发 method=1，
/data 可选映射 BFCCommentAddReplyModel。输入 dictionary 非 nil 则 mutableCopy，
否则新建，再将当前 BFCVCPVManager.sharedInstance.pvUniqueID 赋 scm_action_id，
覆盖输入同名值，随后 copy 交 setParams。captchaToken.length>0 才复制或新建
extraHTTPHeader 并加入 x-bili-gaia-vtoken；无 token 不在此 builder 加该头。
它分别设置调用方 completion、自定义 error handler、customResponseAfterRequest 后
requestAsync；公共 auth/sign/header 合并依旧由前述 BFCApiRequest 执行。

error handler（0x11407cd48）读取 NSError.code，并仅从 HTTP response 的
allHeaderFields 取 x-bili-gaia-vvoucher。code=-352 且 voucher.length>0 才隐藏 loading、
结束输入、调用 BFCCommonCaptchaService.onVoucherWithTag=`comment`；其他错误走
原 failure。验证码 completion（0x11407cfe4）仅 success 原始 bool 非零且 token
length>0 时，以捕获的原 dictionary/success/failure/customResponse 重新调用统一
发送，并传新 captchaToken；不满足条件调用原 failure。重发会再次生成当前
scm_action_id，不直接复用先前 BFCApiOptions。此局部没有次数上限或延迟回退；
仍需核对 captcha service 的内部限制、成功回执到列表更新、草稿持久化及 UI 提交入口。
分析未打开真实挑战 URL、申请验证码或发布评论。

### 普通评论键盘的另一条模型路径

BFCCommentKeyBoardPostWrapperView.sendMessage（0x1140bd7b0）在 NSString.length=0
或 >=1001 时 toast 并结束；1–1000 才继续。这是 UTF-16 code unit 长度，已读入口
没有先 trim。它把原文本存 rawMsg；atReplyUserNick 为空时清 parentRpid，然后创建
PostModel 并赋 oid/type/rawMsg/rootRpid/parentRpid/code/codeV2/voteType/extraModel、
页面跟踪字段，调用 PostVM.postWithModel（0x1140bdcb4）。
PostVM（0x113f854ac）先 transformToHttpRequestParameter，结果 dictionary.count>0
才 sendRequest，否则完成 NSError(domain=`commont`,code=-1000)。该模型转换与上面的
轻量根评论/子回复 builder 并非同一方法，不能用轻量字段清单描述整个键盘请求。

PostModel 转换（0x11407d1c0）只以 oid 对象非 nil 为基础门槛，未见正数校验。
parentRpid 非零用 parentRpid，否则 rootRpid 非零才以 rootRpid 填 parent，两者均0
省略 parent。codeV2.length>0 时发 code_v2，否则发 code（nil 经字典下标省略）。
vote 总是十进制：extra.hasVoteLink 为真取 model.voteType，否则0。
goods_item_id 由非空 jumpUrlIds.allObjects 用逗号连接，结果 length>0 才加入，
这里没有排序；at_name_to_mid 为非空 atInfoMap 经 NSJSONSerialization options=0
转 UTF-8 JSON（0x11407d8fc），失败/空集合省略；pictures 为非空 imageList 的
yy_modelToJSONString（0x11407d9f4），空集合省略。has_vote_option/is_charged/
sync_to_dynamic 均将 extra 对应布尔转十进制，charged_fee/grade_id/grade_score
将 extra 对应整数转十进制；这些赋值没有先以收费/评分开关跳过，nil extra 的
Objective-C 数值 getter 退0。mid 来自 model.mid，nil 退空，不能把它直接写成
当前账号 ID。spmid/from_spmid/track_id/goto 取 model 字符串，nil 经字典下标省略。
sendRequest（0x113f85638）可通过 readPostReportExtra block 再覆盖 from/spmid/
from_spmid/scene/ordering/track_id/container_uuid，后交统一 PosterApi。成功回调取
/data、置 postSuccess=true，并把 rpid 交完成回调；错误回调 parseErr、保存 error、
置 false。customResponse 在业务码=12015 时另读取 need_captcha/url/
need_captcha_v2/url_v2，不能与 -352 voucher 挑战合为一种错误。成功后草稿清理见下述键盘回调；
列表插入仍待逐步追踪。

键盘 service 的 UI 发布 callback 已闭合到此 wrapper：BFCCommentKeyBoardView
keyboardService（0x114031d30）设置 checkPostAvailableBeforeTransform，callback
0x114032628 要求 isInputEnabled 且 keyboardViewDelegate 非 nil；设置
validateDataAfterTransform 到 0x114032684，重新检查转换后 text 的 UTF-16 长度
1–1000，并赋 inputString。postInputContent 注册到 0x114032930
（0x114031fc4），要求 delegate 响应 biliSendMessageWithString:postExtraModel:complete:，
构造 extra 的投票、商品、@、图片 JSON、同步动态、收费、评分信息，再于
0x114032d00 调 delegate。PostWrapperView 的该协议方法（0x1140bdd14）把
code/codeV2 均置 nil，交上述 sendMessage；验证码回调另传这两个字段。
BBKeyboardService.lpDidClickPublish（0x1140d72fc）先发 publishStart，再执行上述
available callback，false 即返回；从 lightPublisher.outputData 检查 attributedText
或 images 至少一者非空，创建 DefaultPublishWorkFlow，登记转换、转换后校验、业务
助手/收费过滤、图片失败与 completion，再 run。workflow completion 0x1140d8474
隐藏 loading、调用 postInputContent、清 workflow；workflow failure 0x1140d8518
隐藏 loading并清 workflow，不调用 postInputContent。因此这里的 workflow 完成发生
在评论请求发出之前，不等于服务器发布成功。LightPublisherObjcBridge 的 Swift
callback 0x104803968 向其 weak delegate 发 lpDidClickPublish（0x1048039c4），
对应物理 button→此 callback 的 Swift UI 接线仍待核对。

PostWrapperView.bindPostVMEvent（0x1140bab5c）订阅 postSuccess/error，skip 第一项。
成功信号先调用 postResultBlock，再根据 VM.postSuccess/公共提示处理；成功处理调用
postSuccess（0x11402d45c），隐藏 loading、清 atReplyUserNick/inputString、
draftString 置空、关闭 giveup text，keyboardService.dismissWithPostResult(true)，
并通知 keyboardPostSuccess。失败入口另传 false，不复用此清文本流程。
这些setter证明键盘状态改变；disk draft清理后端与ListVC回调接线见下节。
ListVC把postSuccessBlock绑定0x113f54738（0x113f541f4），若self仍存在且
response.success_action!=1则进入_addNewCommentWithModel；等1跳过插入仍执行后续
清replyTarget/nick与postCommentResultHandler。deleteTempObjects非空且当前objects空时
先恢复临时数组，再清deleteTempObjects。新评论入口0x113f550fc从response.reply取模型，
nil直接返回；置isNewlyPosted/enableFold、upperMid与success_animation。
有replyTarget走子评论模型/父root绑定，newCard实验走addPostedSubComment；无target
走applyToListRootComment并增加计数，再addPostedComment:insertIndex。
后者0x113f795b8预计算高度、取得root插入索引、处理分隔线并insertObject，没有在这段
另发MainList/ReplyInfo。这是成功响应后的局部插入链；子评论完整分支和并发去重仍待闭合。

旧业务验证码路径（0x1140b944c）订阅 errorNeedCaptchaSignal，先检查
needCaptchaV2 且 captchaUrlV2.length>0，满足则展示V2；否则检查旧 needCaptcha+
captchaUrl.length>0。V2 loadWithURL（0x1140b9930）给服务端 URL 附 oid/page/
ordering/type，再载入验证码 view；没有打开该 URL。旧 didDoneCaptchaInput
（0x1140b9b7c）以 rawMsg、code=传入答案、codeV2=nil、保存的 extraModel 重发。
V2 onVaidate（0x1140ba2a0）读取 success/cancel/token，但重发门槛为 success=true
且 token.length>0，cancel 不额外阻止满足门槛的分支；用 rawMsg、code=nil、
codeV2=token、保存的 extraModel 重发，completion=nil。这会重建 PostModel 和
请求参数，不能称为原 BFCApiRequest 直接重试，也不是 x-bili-gaia-vtoken header。

草稿保存入口 BFCCommentListVC._saveDraftIfNeedsV2（0x113f4a544）要求已登录、
oid.length>0、_shouldSaveDraft=true 和键盘 draftData 非 nil，才交
ServiceLocator.saveDiskDraftWithKey:oid:diskDraftData:；标识 _draftIdentifer
（0x113f4a49c）格式为 `comment_draft-<当前 mid 十进制>`，cp_oid 作为另一个参数。
不能把它直接称为跨账号公共草稿。读取入口（0x113f4a620）用同标识/cp_oid，
异步 callback 0x113f4a70c 仅在 sendMessageView.isActive=false 时恢复，避免覆盖
已激活的键盘。后端注入对象的注册、读取触发和删除范围仍待核对。

ServiceLocator保存桥（0x1047e5bd8）要求输入能cast为DiskDraftData，否则不保存；
把oid十进制字符串放入仅含oid键的字典，调用该数据的协议setter，再以上述key调
DraftService witness+0x20；读取桥0x1047e53f4用同key调用+0x28。
静态协议表只找到DraftServiceImpl一个conformance（0x118295854，
witness0x11b10ce28），其保存/读取分别转0x100e31850/0x100e32028。
这仍不是运行时Inject注册已闭合的证明。

该Impl异步磁盘分支将文件名组成`comment-<传入key>.archive`，保存0x100e31ac4、
读取0x100e3227c都没有把oid加入文件名。路径helper0x100e33978调用
NSSearchPathForDirectoriesInDomains(raw5,user1,expand=true)，选返回数组最后一项，
追加`/Publish/Draft`，必要时创建目录，再追加文件名。因此此候选后端同一账号key
对应一个文件，oid位于保存的数据内，不能说每个oid都有独立草稿文件。

文件扩展名archive并不代表NSKeyedArchiver：writer0x100e33fe8使用JSONEncoder.encode，
若文件已存在先removeItemAtPath:error，删除失败会抛错；之后createFileAtPath:contents:
attributes:nil的Bool返回未检查（0x100e341cc之后直接release）。这是先删再建，
没有该分支原子替换证明；成功回调不保证createFile实际成功。
读取0x100e32624检查文件存在，contentsAtPath后JSONDecoder.decode为DiskDraftData
（0x100e32738–0x100e3274c），completion派发main。只读取了代码与路径字面量，
没有打开真实沙盒、草稿或账号数据。
clearDiskDraftWithKey（0x1047e55e4）向DraftService witness+0x30传同key、nil completion；
候选Impl0x100e32bf0排队到0x100e32e50分支，同样构造该文件名和路径，存在时
removeItemAtPath:error（0x100e332a4），失败日志，completion仍main队列。
因此此接口清该key的文件，未见遍历所有账号/oid目录；ListVC lazy sendMessageView（0x113f53ec8）将0x113f55070绑定为
keyboardPostSuccess（0x113f543f8）；此callback取当时_draftIdentifer再清文件，无oid参数。
实际调用0x11402d45c在清文本/draftString、dismiss(true)后读取此callback，非nil才执行。
该入口来自bindPostVMEvent订阅postSuccess的处理（0x1140bb180），先postResultBlock，
随后只在VM.postSuccess bit0为1且未走公共提示失败分支时进入成功处理；
因此这条ListVC链的服务端成功状态可触发清当前账号key草稿，不能泛化到全部评论VC。

### 评论赞踩与取消的请求和局部 UI

PraiseApi.makePars（0x113f1e5d0）和 DislikeApi.makePars（0x113f1b77c）均构造
oid/type/rpid/action/scene/ordering/spmid/from_spmid/track_id/container_uuid。
oid nil 退空，type/rpid/action 为传入整数十进制；scene/ordering/spmid/
from_spmid 直接赋字符串，nil 经字典下标省略；track/container nil 退空。
PraiseVM 普通赞（0x113f862f0）给 action=1，取消赞（0x113f8685c）给0，随后另加
from=该 VM 的字段；踩（0x113f86d48）给 action=1，取消踩（0x113f87268）给0。
此处 wire action 表示执行/取消，不等于评论模型的 action=1赞、2踩。

PraiseApi.request（0x113f1ead0）向 `https://api.bilibili.com/x/v2/reply/action`
发 method=1；DislikeApi.request（0x113f1ba1c）向 `/x/v2/reply/hate` 发
method=2，即前述 POST 加 URL query 的公共构造分支。两者复制参数，覆盖当前
scm_action_id，映射 /data，设 completion/error 后异步发送。
isFoldedReplyIgnored 没有加入 hate 请求字段；它只捕获到 completion
（0x113f1bc98），恰为1且 /data 为 NSDictionary 时删 is_folded_reply 再交业务回调，
其他情况直接交原 /data。不能把该局部响应改写当作服务器忽略折叠的选项。

旧 BFCCommentListCell 的 _installActionsBlocks（0x113fcf6d4）将 actionContent
的 praise/dislike callbacks 接到 cell.delegate（0x113fd03f4/0x113fd0314）。
ListVC wrapper（0x113f52c8c/0x113f52e24）转 super，并在成功 callback 更新折叠；
PageTableVC（0x113f5d688/0x113f5da24）按 isCancel 选 VM 的对应取消/执行方法，
取 cp_type/scene/ordering/spmid/fromSpmid，成功后刷新表格。
actionContent.onLikeClick（0x113fbc950）/onDislikeClick（0x113fbdbac）调用业务
block 后继续改 model.action、highlight 和赞数，不在该段等待网络完成；模型
action=1 点赞取消，=0/2 点赞置1，踩的操作另处理原赞数。错误回调的恢复、重复点击
抑制、V5替代实现与其选择配置仍需核对，不能把这一套 UI 行为提升为所有评论布局。

### 评论删除、确认与参数覆盖

DeleteApi.makePars（0x113f1b0d0）遍历输入字典 allKeys：key 加到 oid 数组、
对应 value.description 加到 rpid 数组，再分别逗号连接。两数组同次遍历保持配对，
没有按 oid 或 rpid 排序。type 对象非 nil 则直接赋值，否则字符串`1`；
spmid/extend_content 非 nil 才赋，from_spmid/track_id/container_uuid 直接下标赋值，
nil 省略。不能沿用赞踩 builder 的整数格式化和 track 空字符串规则。

requestWith:defriend（0x113f1b444）在 defriend 非零时选 `/x/v2/reply/del/combo`，
否则 `/x/v2/reply/del`，method=2（POST加URL query），响应映射根 `/` 字典。
该 body 先复制输入并覆盖当前 scm_action_id，setParams 于0x113f1b624，
随后0x113f1b634–0x113f1b638 又把原输入赋给同一 options。
BFCApiOptions.setParams（0x116091dd4）是 offset0x30 的 nonatomic copy setter，
所以第二次替换第一次的字典；这处 SCM 注入不能当作最终请求字段。
输入 nil 也会替换为 nil，而不是保留第一次的新字典。公共构造层仍可能另加字段。

Manager.clickDeleteAction（0x113f84efc）展示确认框，确认 callback0x113f851fc
调用 deleteReply，取消仅记取消操作。deleteReply（0x113f83ee0）构造单条
oid→rpid.stringValue 字典，传 track/container/extend 均 nil，并用 defriend=0 请求。
成功 callback0x113f8410c 先提示、发布 BFCCommentShouldRefreshList，再调完成回调；
没有在已读确认入口先删除列表模型。该调用的 errorBlock 为global block
0x11cf81cf0，invoke指针明确是0x113f841c8：取NSError.userInfo的
NSLocalizedDescriptionKey，length>0用原提示，否则退资源默认提示，再toast；
该分支未发成功刷新通知。

combo连接到clickAddBlackListAction的确认callback（0x113f8450c）：
捕获upperOperation byte恰为1时（0x113f84628–0x113f84634）调用
deleteAndDefriend（0x113f846a0）；否则交另一独立addToBlacklist服务。
确认前只展示alert。它复制commonReportParams，补entity=`reply`、entity_id=
rpid.stringValue，yy JSON作为extend_content，spmid给固定reply-card来源。
deleteAndDefriend（0x113f848b4）从sheetParam取type/fromSpmid/trackId/containerUUID，
构造单条oid/rpid并传defriend=1。成功0x113f84b80从根响应.data读
deleted/blocked.boolValue；有非空toast用服务端toast，否则默认提示，随后无条件
发布刷新通知，再将两个bool交完成回调。此局部没有以deleted或blocked为真才刷新。
不能把HTTP成功概括为删评、拉黑都成功；列表通知消费者与上层两个结果的处理仍待闭合。

### 评论置顶与取消

SetTopApi.makePars（0x113f25fd8）构造oid/type/rpid/action/spmid/from_spmid/track_id/
container_uuid；数字转十进制，字符串直接字典赋值、nil省略，不在此加入scene/ordering。
request0x113f26208向https://api.bilibili.com/x/v2/reply/top发method2（POST加URL query），
映射根对象，mutableCopy参数覆盖当前scm_action_id再发送；未见业务重试。
Manager.bringReplyToTop0x113f83870传action1，cancelTopReply0x113f83ba8传0，
均取模型oid/rpid、sheetParam的type/页面追踪项。clickTopAction0x113f84dcc依isTopped
选择取消/置顶，再由完成closure接外部handler；此入口没有确认对话的证据。
成功0x113f83a38先toast、发BFCCommentShouldRefreshList通知，再调用可选completion；
通知对应观察者刷新仍待闭合，不等于已证明各评论VC立即重新拉取列表。

### 评论举报页面与原生回调

ReportVM.showReportPage（0x113f879bc）构造浏览器URL，未直接提交举报HTTP。
OnlineConfig.urlForReport0x11409e37c读取comment.report_url，空时退
https://www.bilibili.com/h5/comment/report。追加oid/pageType/rpid/platform=ios/build/
scene/ordering/spmid/fromSpmid/trackId/containerUUID/scmActionId；build缺值空字符串，
其余字符串nil字典省略，数字转十进制。这里camelCase页面字段不同于赞踩/发布query。
完整report URL经bfc_urlEncodedString后放入bilibili://browser/?url=%@，Router匹配controller、
注入BFCCommentJSBridge.informResult，再push；静态研究没有打开页面。

informResult callback0x113f87ec4只在回传rpid.longLongValue等于捕获模型rpid时
延迟0.3秒main执行结果处理；不匹配仅日志。
结果处理0x113f87fc8读code.integerValue：非0且completion存在则回(false,false,false,nil)；
code0则只接受NSNumber showToast/addBlacklist（不匹配类退false），String toastContent
（不匹配退nil），回(true,showToast,addBlacklist,toastContent)。这是网页回传结果，
不是原生网络响应解析；缺code经nil.integerValue也为0，不能视为严格字段校验。页面实际提交字段、登录/验证码流程和
服务器请求仍未从网页源验证，不能由这个原生URL构造推断举报API已完整闭合。

## 搜索自动播放的 Universal 偏好消费

SearchDeviceConfig.cached/upload0x114899778使用固定type URL
bilibili.app.distribution.search.v1.SearchDeviceConfig，tag1=SearchAutoPlay；后者
value1为Int64Value，affectedByServerSide2为BoolValue，复用前述Universal同步与diff。
SearchInlineSetting.get0x10e3695fc先读UniversalSettingsSynchronizer.isMigrated，false
用legacy autoPlaySettingFromSearch；true要求root/hasAutoPlay/hasValue，否则raw11，
不回退legacy。PBvalue1/2/3分别对应禁自动播/仅WiFi/允许蜂窝；affected缺省false，
为false时raw4/3/10，为true时raw2/1/11，未知value亦raw11。

setter0x10e369764若输入属于server raw1/2/11且当前人工raw3/4/10，直接return；
其他情况按同映射写PBvalue与affected，再Universal.upload；未迁移则只写legacy。
无本段login/时间戳/相等检查。迁移分支不创建缺失root，nil消息可使本次没实际上传，
仍发com.bilibili.search.settings.auto_play通知。autoCanPlay0x10e36998c对10/11为true，
1/3仅Reachability.status==1，其余false；affected只区分来源优先级，不改变网络模式。
legacy默认raw11。isMigrated0x104c73930读standard UserDefaults固定key
bfc_universal_settings_uploaded，缺值/cast失败false，无所见MID后缀；读取来自Swift
静态存储0x1204a7320所持String及默认Bool，而非按账号拼key。迁移写入链如下。

onHomePageInitialized0x104c7437c先通过0x105130238读取另一个静态Bool，
最低位为0才在0x104c743c8进入迁移body0x104c739d0；该Bool初始化
0x105130148来自配置infra.ue.opt.gripper.runnable（defaultValue=false），
不能省略这个外层开关。迁移body先检查
use_new_config_system实验命中（presetHitValue=false），未命中或已迁移时走locator
0x104c73578。命中且未迁移才收集可迁移设置；收集结果count=0的分支
0x104c73e70→0x104c74164直接将该固定key写Bool true（0x104c741e0），
没有setUserPreference请求。非空时构造BAPIAppDistributionSetUserPreferenceReq，
逐项尝试GPBAny.initWithMessage:error:，打包失败的项跳过；0x104c740d0设
preferenceArray，0x104c7414c调用setUserPreferenceWithRequest:handler:。
收集结果非空不等于最终Any数组非空，不能将空数组都归入上述直接写入分支。

handler桥0x104c74530保留输入reply/error并传给0x104c749d0；只有reply非nil、
error为nil且当时isDirty最低位为0，才在0x104c74b0c写Bool true。isDirty由
0x104c738ac读取进程内byte 0x121072cc8，0x104c738ec直接写入；它与持久迁移
标记不是同一份状态，此回调也不清除isDirty。失败门槛不写迁移key，埋点statusCode
按isDirty原始byte是否为0分为1/2；成功写入路径statusCode=0。两条路径均使用
common.settings.migration.failure命令名，不能由埋点名字推断失败；之后均进入
locator0x104c73578。本段没有显式synchronize、MID校验或立即重新请求，其他
isDirty setter调用者及迁移触发全链仍需继续核对。

其中Search迁移builder0x104c7448c创建新的SearchDeviceConfig/SearchAutoPlay，
不先读cachedConfig；填充helper0x104c764d8直接打开固定Search legacy suite，
取autoPlaySettingFromSearch并要求能cast为Int64。suite缺失、key缺失或cast失败
返回false，builder释放新模型并返回nil，迁移收集跳过该类型；这里没有使用
SearchInlineSetting运行时的默认raw11代替缺值。存在且cast成功时用
0x104c747c8生成两个wrapper：raw1/3→value2、raw2/4→value1、raw10/11→value3；
affected仅raw1/2/11为true，其他已知值false。未知raw仍返回新wrapper，value及
affected保留新对象默认值，而不是跳过类型或强制value3。0x104c7660c/0x104c76628
将wrapper写入SearchAutoPlay；builder随后设置autoPlay并加入迁移候选。
这一来源校验与迁移后的getter fallback属于不同路径，不能混写成同一个默认策略。

真实搜索完整设置列表UI仍待闭合；但已定位一个搜索结果页入口：
ResultViewController.inline4GTipDidTapNotUse0x100a719fc→Swift body0x100a71810，
明确取BBPhoneSearchInlineSetting.shared，0x100a71860以raw3调用上述setter，
即人工“仅WiFi”；该写入在读取viewModels/后续展示处理之前完成，没有本段登录门槛。
已有一条搜索广告卡片的物理按钮链：BBAdInlineSearchV2PanelView class
0x12019d268的superclass明确为BBAdInlineBasePanelView 0x12019d0d8；继承的
wwanTipView getter0x113be4a44创建BBAdInlineWwanTipView并在0x113be4c0c把
weak panel closure0x113be4cb0赋给notUseWWANHanlder。tip.notUseControl getter
0x113bf2930创建buttonWithType:0，0x113bf298c以control event原始0x40绑定
clickNotUseWWAN；该handler0x113bf257c仅在closure非nil时调用block invoke。
closure取weak panel后动态发wwanTipNotUseClick；SearchV2 override
0x113bed1f8先调用super隐藏tips，再0x113bed244读BBSearchInlinePreferences.shared
的inline4gOperationProxy、0x113bed254调用inline4GTipDidTapNotUse。

该代理的来源也已定位：ResultViewController初始化body0x100a5b858中，设置
search.search-result.0.0.pv的分支于0x100a5bf94把当前初始化后的controller注册为
BBSearchInlinePreferences.shared.inline4gOperationProxy；setter0x1141a06d4使用
objc_storeWeak，getter0x1141a06bc使用objc_loadWeakRetained。其他分类pv分支
在0x100a5bf00已返回，不能将此注册推定为所有分类结果页都有。按钮→weak panel
→当前shared weak proxy→上述raw3 setter构成所见链；并不是panel自行持有
最初页面或发Universal请求。其他三种设置值入口和完整设置列表仍待逐项核对，
通用同名selector的Pegasus/Channel caller仍不能替代Search调用证明。

同一初始化分支还在0x100a5bfc4将controller注册为inlinePlaySettingProxy。
BBAdSearchInlineTool.currentSearchInlineSetting0x113bd0c68通过该shared proxy调用
searchInlinePlaySetting；ResultViewController实现0x100a71bfc取
BBPhoneSearchInlineSetting.shared.autoPlaySetting。广告工具转换
_convertAutoPlaySetting:0x113bd0cd4将raw10/11归10、1/3归3、2/4归4，其余也归10；
这层抹去server/manual来源差异，但不写原设置。proxy为nil时Objective-C调用
返回0，落入该转换的默认10；不能将这条局部消费的默认值替代前述PB getter、
迁移或全局Search自动播放判断。实际广告请求/播放器采用这个值的调用方仍待核对。

蜂窝临时放行也与全局autoPlaySetting分开：canAutoPlayWhenCellular0x10e369a0c
仅对raw10/11为true；showCellularMask:0x10e369a2c用传入Int秒数减firstShowTime，
转Double后依次除3600及24，结果>=7才为true；这里不是绝对差值。
cellularMaskCanPlay0x10e369a78要求firstShowTime>=1，否则false；成立时读当前NSDate
unix秒并截断为Int，返回!showCellularMask。这对应所见七天窗口计算，不能推断
系统时钟回退防护。updateUserClickCellularMask:0x10e369a74直接尾调动态
setFirstShowTime:，沿用输入时间而非内部读取now；defaultConfig0x10e369520给
firstShowTime=0及legacy autoPlaySettingFromSearch=11。
时间写入已找到InlineNetworkingPlugin捕获weak self的callback body0x100d57824：
weak plugin仍存在时取BBPhoneSearchInlineSetting.shared，Date()当前unix秒经Swift
有限值及Int范围检查、截断后，0x100d5792c调用updateUserClickCellularMask:。
接着若weak delegate存在，调用其witness slot+8并带输入Bool false；未设置全局
自动播放raw10/11，不能把七天临时放行视为改成“允许蜂窝”。该callback的
遮罩按钮绑定已闭合：WWAN mask创建点0x100d575f0将
0x100d5adb4→0x100d57824作为NetworkingMaskView的continueToPlay closure，
constructor0x100d5abc0在0x100d5ac6c保存到continueToPlay ivar；
绑定方法0x100d59a24取continueButton（0x100d5a4f8），使用control event原始0x40的
reactive流订阅0x100d5a85c，并交disposeBag管理。该subscriber读取continueToPlay并
执行保存的closure，构成继续播放按钮→当前秒缓存写入链。具体显示文本由SearchRes
资源决定，未用方法名猜资源内容。

## 收藏业务参数的入口

MediaListApiManager.modifyFavourite（0x11456d698）向
https://api.bilibili.com/x/v3/fav/resource/deal发method1 POST；rid为传入String，nil退空，
type为resourceType十进制。addFids/delFids分别仅count>0才逗号join成add_media_ids/
del_media_ids，保持输入顺序，未排序；均空仍可发请求。签名公共项由通用层加入。
selector虽含from，入口保存参数x2/x3/x4/x5/x7、未消费x6，构造范围没有from键。
不能仅凭签名参数名声称该字段已发送；本分支也未显式加入scm_action_id。
/data映射成功completion(true,nil)，失败另包装BFCApiServerErrorDomain再回false；
该业务入口未见本地重试，具体错误码/文案转换仍待继续核对。

首页InlineController._requestFavorite（0x11418a0c8）依isPGCSourceType分流：
PGC取epid走modifyCompilations、resourceType24；UGC取avid十进制走上述
modifyFavourite、resourceType2，以默认文件夹String0列表和空列表传入add/del。
并先读meta.tracker.from传给selector，这不改变目标函数忽略from的证据。
_updateFavoriteState0x1141884d0先要求输入非0，false直接return；true未登录仅showLogin，
登录才固定_requestFavorite:true。成功callback0x1141885b8要求weak self存在，
把token的BPInlinePlayableFavorite设true（0x114188664），通知relationship变化并toast；
失败toast localizedDescription或fallback，没有这段状态回滚。此入口不能作为取消收藏
协议证据；物理按钮与选文件夹入口仍待闭合。

合集modifyCompilations完整入口0x11456dc68向/x/v3/fav/resource/batch-deal发method1。
resources在rid/seasonId均非nil时为rid:resourceType,seasonId:21；仅rid时rid:resourceType，
仅seasonId时seasonId:21；此处nil与空字符串不同。add/del仍非空数组才逗号join。
当前pvUniqueID仅length>0写action_id（不是scm_action_id）；extra nil先退空字典，
yy_modelToJSONString后赋extra，from直接下标赋值（nil省略）。token.length>0才copy
extraHTTPHeader并写x-bili-gaia-vtoken（0x11456e08c），保留其他header。

错误callback0x11456e440仅response匹配HTTP类时取header x-bili-gaia-vvoucher，否则空；
error.code==-352且voucher非空才调用CommonCaptchaService tag compilation_favorite。
验证码callback0x11456e7d4要求成功Bool非0且token非空，捕获原参数递归重建完整请求，
以token作header；失败/空token回原completion(false,nil,error)，没有该范围最大续提次数。
这是独立于普通deal的业务续提交流程；未运行验证码或实际收藏请求。

### 首页 Inline 三连的请求

InlineController.ugc_tripleLikeWithCompletion（0x11418a46c）取item.playableParameters.meta，
构造4项aid/from/spmid/from_spmid；aid为meta.avid十进制，其余tracker字段nil退空字符串。
0x11418a6b4建options，method1 POST到https://app.bilibili.com/x/v2/view/like/triple，
/data映射Dictionary且optional=true。成功callback0x11418a878分别从/data取like/coin/fav
并boolValue，缺data/键退false；后续状态应用、UI触发/登录仍待核对。
未从接口名推断它与单独投币/收藏总有相同参数或相同服务器行为。

PGC入口0x11418aa44仅显式ep_id=meta.epid十进制（nil空），method2 POST URLquery到
https://api.bilibili.com/pgc/season/episode/like/triple；映射路径为data且未设optional。
callback0x11418ad64读data.like/coin/favorite的Bool以及coin_number整数，缺键按ObjC
nil消息退false/0，再completion(nil,like,coin,favorite,coinNumber)；error callback
0x11418aedc原error作为x1、其余false/0。favorite拼写不同于UGC的fav，PGC参数也未
显式带UGC三项tracker；公共参数仍由各自引擎决定。

共同update callback0x1141887f8只捕获weak controller，error非nil只toast；nil则按三项
Bool提示结果。全true调用当前token.makeTripleLike并通知TripleLike状态true；部分成功
逐项把当前token的Like/Coin/Favorite设true并通知，coin成功额外updateCurrentUser，
false项不设false；coinNumber在这段update未消费。已逐pointer确认三个属性名字。
回调反复读当前token，未见捕获请求avid/epid、比较当前视频或账号session再应用；
这是静态范围的缺少复核证据，不代表实测串片。错误/部分失败未自动重发三连。

token.makeTripleLike的Container0x1141f9144接ChronosService0x114200bc8，将当前
videoParams.meta.relationship三项设1，再_syncRelationShipTripleLike0x114202998；
后者仅isActive时发本地relationshipChainChanged三项true。这里是播放器状态同步，
未见新增网络三连请求或投币次数写入，不把本地args当上报协议。

同Inline的_requestLikeStatus（0x114188b88）发method1到/x/v2/view/like，aid同meta.avid，
like按传入状态非0→1、0→0，加tracker from/spmid/from_spmid（nil空）；映射可选
/data/toast，无这段字段scm_action_id/track_id/coin/fav。_requestCoinWithCompletion
（0x114189968）另发/x/v2/view/coin/add，ignoreCache=true、method1，multiply=1、
avtype=1、select_like=0，加aid与同3个tracker字符串；映射可选根Dictionary。
该Inline投币入口没有2枚选择参数；不能推断其他投币面板也固定1。
_updateLikeState0x114187a9c检查BFCAccount.hasLogined，登录走上述like，未登录另走
_requestUnLoginLikeStatus0x114188fe8到/x/v2/view/like/nologin（method1、/data映射）；
字段aid/like/action/from/spmid/from_spmid，其中like来自传入Bool十进制、action字面like。
_updateLikeState把输入状态xor1后传给登录/未登录两个request，网络字段是目标状态，
不能把该update输入直接解释为要发送的like。
_updateCoinState0x114187f48则hasLogined bit0为0时只showLogin(nil)，不在这分支发coin。
_updateTripleLikeStatus0x114188754直接交_requestTripleLike0x11418a3c0，再按
meta.isPGCSourceType选择pgc/ugc，本方法没有登录判断；不代表更上层UI无门控。
makeTask的弱引用relationship callback（0x114186f98→0x114186fe0）连接
_playerRelationshipDidTrigger0x114188a68，按BPInlinePlayableLike/Coin/Follow/Favorite/
Dislike/TripleLike属性名字匹配分别调上述update（Dislike update仅return）。
这是player task事件到业务的接线；物理按钮/手势到事件、重复门控、成功状态与其它
播放器入口仍需逐条闭合。

### 首页卡片长按三连的另一入口

BBListInlineV2LikeItemView.longPress0x113d99f80在gesture.rawState1且supportTriple时
调tripleLikeAction，rawState3且supportTriple时调EndAction；不支持的开始走onTap。
Action0x113d99c38拒绝isAnimation、当前用户silence和三项已全成功，否则置animation
并启动Lottie。EndAction在progress<0.3时pause，反向播放到0后仅finish，不走请求；
其他进度本段return，让原动画完成。原playWithCompletion callback0x113d9b3e4仅
finished非0才finish、调用finishTripleLikeBlock，然后检查登录；logged发_requestTripleLike，
unlogged在未selected时发nologinLike，再autoLogin。动画/finish callback先于HTTP响应。
不能把长按开始、松开或动画结束各算一次三连提交，也不能将finish名字当业务成功。

此卡片_requestTripleLike0x113d9a55c是独立HTTP：method1同UGC三连URL，data Dictionary
非optional；六项aid=当前view.aid十进制、from=76、fromSpmid/from_spmid/spmid均
字面tm.recommend.0.0、action_id=当前pvUniqueID（nil空）。没有显式track_id/source/token，
fromSpmid与from_spmid同时发送，不能替它规范化字段名字或套InlineController tracker。
成功0x113d9a8b0从data取like/coin/fav boolValue，按成功项更新按钮/isCoined/isFav，
coin成功更新当前用户，再调用tripleLikeStateChange；失败项不清true。error只清animation
并toast；此范围未见验证码续提/重试。init0x113d98e6c创建target=self/action=onTap及longPress两recognizer，tap要求
longPress失败，均加到likebgView（0x113d99138/0x113d99164）；物理手势接线已闭合，
外层finish/tripleStateChange callback绑定仍待核对。

该view未登录点赞0x113d9a0e0也有独立七项：aid十进制，like按当时view.isSelected
非0→1/否则0，action字面like，from=7，spmid/from_spmid同tm.recommend.0.0，
action_id当前pvUniqueID nil空。method1到/like/nologin，/data/toast String可选；成功
仅启动本地点赞动画，error清animation并toast。长按完成未selected时调用这一方法，
不能从方法名改成单独投币/收藏，亦不把from=7与logged三连from=76混同。

### 独立播放器的 UGC 三连 provider

BBPlayerLikeProvider完整selector0x104a9033c桥接7个输入String，到Swift body
0x104a8d440：显式aid/from/spmid/from_spmid/action_id/track_id六项，action_id读当前
BFCVCPVManager.pvUniqueID；aid这里是输入String原样，不是Inline从meta.avid转数字。
verifySource/verifyToken分别非空才作为source/token追加。method1、同app三连URL、
/data Dictionary映射optional=true。无trackID selector0x104a8f850给track_id空String，
字段仍进入六项字典，不是省键；该函数范围没有自查登录或重试门控。

completion thunk0x104a90fec→0x104a8f9b4将/data cast成字典并保存到结果model；
无法cast直接completion默认结果。正常解析like/coin/fav/prompt为Bool、prompt_text/
toast为String、multiply为Int，失败cast各退false/nil/0；不是Inline的boolValue任意对象。
error callback0x104a90290只构造结果model.error并completion，未见transport自动续提。

该成功handler还读/data.v_voucher String。捕获原verifySource非空且voucher String
非空时先展示BFCCommonCaptchaViewController，completion被延后；未满足则解析普通结果。
验证码callback0x104a91124要求成功Bool bit0且返回token Optional非nil（此处未查长度），
重调原Swift body，沿用捕获业务参数并以返回source/token替换验证输入；失败回原结果。
若返回token为空String，重建body会省token键，不能把Optional非nil等同非空。
此静态分支没有-352判断或HTTP voucher header读取，也未见最大递归次数；与合集收藏
的-352+header流程不同。普通UGCHandler._tripleLikeWithCompletion0x1143a9d7c取currentScene.scene_avid，读
当前isLiked/isFavorite后调用LikeOrDislikeService.tripleLikeAid；其body0x104a8bef4
将avid十进制，取from/spmid/fromSpmid/trackID helpers，固定verifySource=view_vvoucher、
verifyToken空，直调provider。该service方法本段无login门控，但更上层物理操作尚待核对。
字段helper优先级已核对：from0x104a8c56c、fromSpmid0x104a8c7bc先取service
对应String并检查长度，**非空才优先**；空串继续经context.director.currentScene.model
读取相应属性，最终nil转空串。spmid0x104a8c6b8及trackID0x104a8c90c直接走当前
scene.model，无本段service覆盖值，最终nil转空串。四个helper各独立读当前scene，
与入参avid不构成同一时刻的固定model快照；service覆盖属性的写入者仍待追。

service成功转接body0x104a8c0e4读取provider结果的error、三项Bool、prompt、
coinsCount与toast，原样交completion；prompt不是总成功Bool。Chronos handler的
callback0x1143a9f28要求weak self仍存在；error非nil只showToast资源兜底，跳过关系更新
及外层completion。error nil时，tripleLike=true且请求前捕获isLiked=false才通知更新
点赞；tripleFav=true且捕获isFavorite=false才setIsFavorite=true。tripleCoined=true
则将当前coinService.coin加**服务器multiply映射的coinsCount**、setIsCoined=true并
updateUserModel，没有捕获旧coin数或vid/account一致性比较。三项false不清已有状态，
prompt在该callback未消费；最后_showTripleToast传三Bool/toast，再调用外层completion，
部分false也进入这一路。本callback不会自己重发网络请求；其回写针对当时service，
不是依据请求avid重新定位模型。service在发起provider后还直接调用计数helper的
addPlayerVideoLikeInteractionCount（0x104a8c0c0），该调用不等待网络completion；不能
把该本地交互计数当成服务端三连成功或三项全部true。

播放器like widget还存在独立于Chronos handler的旧动画提交链：oldTriple0x1144beb28
绑定gestureBegin/End分别调用startAnimation/endAnimation；startAnimation0x1144bb894
将完成block0x1144bbd04交animWidget。完成Bool非0时先移除动画，再读当前isLiked和
loginProxy.hasLogin；**已登录或设备为iPad**才调用tripleOperation0x1144bc6ac，取当时
scene_avid→同like service.tripleLikeAid。未登录非iPad走unloginTripleOption0x1144bc9d4：
当前isLiked=false才先发requestUnloginLike(isLiked=false,isTriple=true)，随后无论
isLiked都showLoginVC，空completion block0x1144bca64不接网络结果，没有自动补三连。
不能把这条iPad例外推广至上面全屏投币按钮或provider自身。

完成block先报player.player.full-screen.triple-like-click.player，type按完成Bool非0→1、
0→2，然后才门控提交；动画未完成也会上报click type2。tripleOperation callback
0x1144bc810同样分error/三Bool/coinsCount，成功时按捕获的isLiked/isFav只补true，投币
加服务器multiply映射数量并updateUserModel；没有另发三项独立请求。这里无外层
completion，error仅toast资源兜底，未见重投。传入isCoined与from并没有作为provider
参数覆盖；capture具体以callback读取为准，不能按selector名补键。

widget.tripleLikeAnimationComplete0x1144bd09c则先报
player.player.full-screen.triple-like-success.player，再调用可选tripleMagicAnimComplete，
该函数没有查询业务网络结果。newTriple0x1144be7c8的该callback播放SVGA并向
playerTripleMagicAnimCompleteSignal发tuple(true,空串)，不是本函数直接发HTTP。新样式
网络链另已追到：newTriple gestureBegin0x1144be914→startSharkAnimation0x1144bc180，
先将likeBtn.selected=true，再调用startAnimationWithType(raw1,completion0x1144bc2dc)，
并发送playerStartTripleGesSignal(true)。其动画completion先报同click/type1或2，重读
isLiked恢复button.selected；仅完成Bool非0才进入同样“已登录或iPad”的门控，并调用
同tripleOperation0x1144bc6ac，否则非iPad未登录走同unlogin方法。故新旧两套动画
最终共用该网络入口；animationCompleteSignal其他接收者的展示消费仍需分开核对。
事件名称中的success不能作为三连接口成功证据。

未登录点赞的实际provider是完整selector0x104a8f678→Swift body0x104a909f8，
method1到/x/v2/view/like/nologin，映射/data为NSDictionary（modelWith三参数，
不是上面三连optional Dictionary接口）。八键为aid十进制、like输入isLiked bit0的
十进制0/1、action输入isTriple bit0为true→triplelike/false→like、from、spmid、
from_spmid、action_id当前pvUniqueID、track_id输入String（空也保留）；没有把like
反转为目标值，也没有source/token验证码字段或本段重试。上面未登录三连调用链
传isLiked=false/isTriple=true，因此明确发送like=0、action=triplelike，与推荐卡片
action=like、from=7那条请求不能混同。

like service.requestUnlogin body0x104a8b788先查BFCAccount.hasLogined；已登录直接
completion(false,false)且不发请求；这两个参数是success、needLogin两个Bool，
不是Bool/Error。未登录才分别读scene_avid与上述字段helpers，保留输入两Bool发provider，
之后调用addPlayerVideoLikeInteractionCount（0x104a8ba00），不等响应。

provider成功回调0x104a911c0→0x104a8f45c读取/data.need_login，只有Int恰为1才
生成true，缺失、类型转换失败及其他Int都为false；toast按String转换，失败为nil。
/data本身缺失或转换失败仍回success=true/error=nil/toast=nil/needLogin=false，
不能把此处success等同于完整业务数据。error回调0x104a911c8回false/error/nil/false，
本段不自己showLogin或重投。

服务层回调0x104a8cd44→0x104a8ba24先要求weak service仍存在；已释放则连completion
也跳过。success bit0为true才调用本地状态方法0x104a8b5e0，固定输入true，
但该方法按回调时当前isLiked做切换：未点赞时先清isDisliked（若有），设isLiked=true、
like数加1；已点赞则设false、like数减1后截到至少0。计数是Swift带溢出检查的Int运算，
并非服务器返回计数。没有按请求发起时isLiked或avid/account检查，因此并发及切换场景
仍可能影响当前关系；不能表述为成功后一律设true。

随后0x104a8ce78向standardUserDefaults固定键kBBPlayerUnloginLike写String "1"，
再调用synchronize，未检查其返回值；本层键不含MID或avid，读取/清除方仍待核对。
最后main.asyncAfter的deadline为DispatchTime.now()+1.0+0.5秒，0x104a8cf74只向捕获
completion传true和本次needLogin bit0，不再读取service或登录状态。这是延迟界面回调，
不是延迟HTTP重试。provider传来的toast在该服务回调中未使用。

success=false分支不改关系或写上述键：取error.localizedDescription，nil或空串则
使用“操作失败，请重试”，经当前context.toastWidgetService显示center toast；随后直接
completion(false,本次needLogin bit0)。provider自己的error路径使第二Bool为false。
这段仍没有自动登录、自动重投或账号/视频一致性校验。

普通PlayerLikeWidget.like:0x1144bdf6c取当时likeBtn.isSelected，登录分支传该值给
requestWithIsLiked:；未登录先构造登录block0x1144be3a0。iPad或supportUnloginLike
bit0为false时直接调用登录block、bubbleToast为空；其他手机才发requestUnloginLike，
isLiked沿用按钮值、isTriple=false，callback0x1144be4f8要求success与needLogin两Bool
都非0，才取playerbaseres_global_string_918资源作为bubbleToast调用登录block。
登录block另带business_id=3、scene_name=player.player.recommend.0.player，使用
showLoginVCWithTrackParams:；没有登录完成后的自动重投callback。按钮值是在点击时读取，
服务本地关系切换则发生在响应时，两者不能视为同一时刻的状态。

supportUnloginLike getter0x104a8a074只读取service实例中的Bool ivar
0x12049a718，不在getter中查询远程配置、账户或NSUserDefaults；initWithContext对应
Swift body0x104a8cb18在0x104a8cb70写默认true。另有公开setter0x104a8a0f8，
外部注入/后续修改方尚待核对，不能将初始化默认值推成所有场景恒true。
kBBPlayerUnloginLike字面量的限定ADRP+ADD候选扫描只找到上述写入点；该扫描不覆盖
所有引用形式，因此不足以证明没有读取、注销清理或重置路径。

### 独立播放器普通登录点赞

service.requestWithIsLiked:0x104a8ab74→Swift body0x104a8abac按当前scene_avid及
上述from/spmid/fromSpmid/track_id helpers取值；输入isLiked bit0不反转，goto和token
为空String，source固定view_vvoucher。provider body0x104a8d024构造
BAPIAppViewV1LikeReq并调用LegacyView.likeWithRequest:handler:；该Legacy实例方法
0x11644aa84明确进入handleRestRequest，不据protobuf模型名推断网络上传protobuf或gRPC。
getLikeHttpRule0x11644abb0给出verb原始2、pattern=/x/v2/view/like、空pathBinding、
bodyBinding=nil、isAsteriskBody=true；编码/签名仍由既述公共REST层处理。

LikeReq descriptor0x1164508c4的11项为aid#1/int64、ogvType#2/int64、from#3/string、
spmid#4/string、fromSpmid#5/string、trackId#6/string、goto_p#7/string、like#8/int32、
source#9/string、token#10/string、actionId#11/string。该provider未设ogvType，
不将默认值描述为必然显式发送；aid直接输入Int64，like为输入Bool bit0转0/1，其余
业务String直接设，包括空goto/track；actionId每次读取pvUniqueID，nil桥接为空String。
source/token各自仅长度非0才设，因此首次service调用只设source、不设token。
发出provider调用后0x104a8ae1c立即addPlayerVideoLikeInteractionCount，不等响应。

provider handler0x104a8f05c→0x104a8ea38先要求捕获source非空和reply非nil，
随后reply.vVoucher非空才弹验证码；它不以HTTP -352或特定error code作验证码门槛。
验证码callback0x104a912e0要求成功bit0及返回token Optional非nil（没有长度检查），
递归同provider、保留业务参数、替换source/token；cancel直接completion(false,
验证码error,空String)，无自动传输重试或本段递归次数上限。未触发验证码时只要reply
非nil，就回success=true/error=nil，并读取reply.toast（nil为nil）；这一路不先检查
同时返回的error，不能据success推断error原本不存在。reply=nil时回success=false，
error=nil也仍为false，toast为空String。error能转换为NSError且moss_isBizError非0时，
改建BFCApiNonZeroErrorDomain错误，code取moss_getBizErrorCode，userInfo带
NSLocalizedDescriptionKey和NSLocalizedFailureReasonErrorKey，分别由
moss_getBizErrorMsg/Reason填入；其他error原样传出，未作重试。

service callback0x104a8ae40先要求weak service仍存在，已释放则不调上层completion。
provider success bit0为true时调用0x104a8b5e0固定true，按响应时当前isLiked切换关系及
计数，和上述未登录本地切换相同；没有avid/account重核对。success=false且error
转NSError.code恰为正数65004或65006，也做同样本地切换、不show失败toast，但可选上层
completion仍传原success=false，不能视作请求成功。其他error使用localizedDescription
显示center toast；error=nil用“操作失败，请重试”。这里没有未登录路径的1.5秒延迟或
kBBPlayerUnloginLike写入，callback传来的toast String也未消费。

### 独立播放器点踩

service.requestWithIsDisliked:0x104a8b0a4→Swift body0x104a8b0dc取当前scene_avid、
spmid/fromSpmid helpers，保留输入isDisliked bit0给provider0x104a9052c；这里没有
from/track/goto/source/token，也未调用点赞交互计数。完整ObjC provider入口
0x104a8f78c只桥接对应输入。provider用method1发app端/x/v2/view/dislike，五项
参数为aid Int64十进制、dislike输入bit0的0/1、spmid、action_id当前pvUniqueID、
from_spmid；两业务String为空也保留，未反转dislike。根路径/的NSDictionary映射
optional=true，success callback0x104a911fc忽略返回model、固定completion(true,nil)，
error0x104a91224回false/原error，没有验证码或本段自动重投。

service callback0x104a8b264先要求weak service存在，否则不回上层。success=true
按响应时当前isDisliked切换：若原本未点踩且已点赞，先取消点赞并将like数减1截至0；
然后当前isDisliked为false→true、true→false。计数带Swift溢出检查，无请求时状态、
avid/account一致性校验。success=false且NSError.code恰为正数65005或65007，
走同样状态切换而不show失败toast，但上层可选completion仍接到原success=false。
其他error显示localizedDescription center toast，error=nil显示“操作失败，请重试”；
没有1.5秒延迟或上述未登录缓存写入。客户端错误码分支只确认本地处理，未赋予这些
码的服务器业务语义。

BBPlayerDislikeWidget.dislike:0x114374d3c从当时dislikeBtn.isSelected取值，先上报
player.player.negative.0.player，再查BFCAccount.hasLogined；登录传按钮原值给
requestWithIsDisliked:，未登录仅showLoginVCWithTrackParams:，scene_name同上述事件，
没有未登录点踩请求或登录完成重投callback。dislikeBtn getter0x114374fe8首次创建按钮时绑定
control event原始0x40，并设exclusiveTouch=true；这些是UI入口约束，service/provider
本身的代码段没有同样登录检查。

### 独立播放器投币 provider 与 service

BBPlayerCoinProvider完整selector0x104a04bec桥接输入，Swift body0x104a03978
构造/x/v2/view/coin/add请求：method1、ignoreCache=true，根路径/ Dictionary映射
optional=true。十项基础键为multiply、aid、avtype、from、spmid、from_spmid、
select_like、goto、track_id、action_id；前两项分别将输入coin Int、avid Int64转十进制，
其余业务String沿用输入，action_id取当前pvUniqueID。selector虽称cardGoto，实际键为
**goto**；空track_id仍保留键。verifySource/verifyToken分别非空才追加source/token，
本body没有自查登录、投币上限或已投币状态。

completion thunk0x104a04fcc→0x104a0473c先将映射/转字典；失败直接completion(nil,nil)。
成功保留外层根字典，再cast根字典的data，读其中v_voucher String；捕获verifySource
和voucher均非空时展示验证码，延后普通completion，否则返回原根字典、nil error。
该分支没有-352判断或HTTP voucher header读取。验证码callback0x104a0513c要求
成功Bool bit0且返回token Optional非nil，沿用业务参数、换入返回source/token递归重建
请求；此处不检查token长度，空String会被body省键。失败completion(nil,验证码error)，
没有回原根字典；error thunk0x104a05060将请求error直接交completion，不自动续提。
本分支没有可见最大验证码次数。

BBPlayerCoinService.postCoinRequest0x114443014仅在coinType非0且当时scene_avid>=1
时调用sendCoinRequest，并上报player.player.player-coins.0.player；没有本段登录检查、
coinType只准1/2或twoCoinsBtnEnabled检查。send0x1144431f0将coinToLikeSwitch非0映射
select_like="1"、否则"0"；avid重新读currentScene，from/spmid/fromSpmid取其model。
它将coinType原样交provider，固定avtype="1"、goto/track_id/verifyToken为空String、
verifySource=view_vvoucher。post与send分别读取scene，不能当成一次原子快照；面板对
1/2枚、余额、登录的实际UI约束见下述全屏按钮与CoinWidget。

service callback0x114443474以error nil判断成功，先BFCAccount.updateUserModel，再把
捕获coinType和返回根字典交sendCoinSuccessed0x114443768；因此provider的(nil,nil)
也能落入该分支，不能额外假定一定有data。success读data.like.boolValue，先无条件设
isCoined=true、将当前coin加捕获数量；仅like Bool bit0为true才另通知
likeOrDislikeServiceProxy更新点赞，false仅走投币成功日志。error=-110展示绑定手机提示，确认callback
0x114443724打开绑定页面；其他error toast localizedDescription或资源兜底。最后仍
将原error传外层completion，未见自动重投或当次avid/account重新核对；CoinWidget
消费completion时的pop行为见下文。

全屏按钮handlerCoinBtnAction0x11448d4a4先上报player.player.coins.0.player，再查
loginProxy.hasLogin；已登录push BBPlayerCoinWidget，未登录仅showLoginVC并传scene_name，
本handler没有保存登录成功后自动开面板的completion。面板updateUI0x1144894a0读取
service.twoCoinsBtnEnabled：true显示并选中twoCoinsBtn、取消one；false隐藏并取消two、
选中one，默认数量来自该flag，不取余额决定默认1/2。余额显示读userModel.coinCount，
之后updateCurrentUser completion0x114489ac4只重读余额改文案，不消费error，也不重新
决定数量。twoCoinsBtnEnabled的model写入来源仍待追。

面板coinBtn创建0x11448b7c8绑定postCoin:为controlEvents=0x40；post0x11448c2a8
one selected bit0=true先取1，否则two.selected非0取2，否则0，沿用当前Preference
coinToLikeSwitch交service。没有本post范围余额比较、disabled/duringCoin检查或再次
登录检查；0仍到service，由postCoinRequest的非0门控拦下。one/two按钮分别绑定
exclusionBtn；按钮taped0x114488d10固定选中自己、取消exclusionBtn，不反转当前
selected。coinToLikeSwitchBtnClick0x11448c1f4将
BFCPlayerSettingsPreferences.shared.coinToLikeSwitch xor1写回，再重读更新selected，
提交时重读而非直接消费UI selected。该Preferences继承BFCPreferences，coinToLikeSwitch
编码TB,D,N（property list0x11f34eb08），走已核对的通用动态Bool getter/setter；
configName0x114faf4c0固定BFCPlayerSettingsPreferences，defaultConfig0x114faf4cc
将coinToLikeSwitch设true。通用userDefaults0x1167d4ccc按configName创建suite，
此偏好层没有MID分区；其他写入者/整suite清理尚未穷尽。
post completion0x11448c424忽略传入error，weak加载widget后直接popWidgetAnimated，
因此成功和失败均尝试关面板；没有此callback内继续重投。

两枚开关的一个实际写入已闭合：Swift VDViewAndPlayViewBlocImp中的
playInformatitonInject(_:_:)，函数0x103b1fcb4，读取BBVDDataBloc.basicModel并配置
播放器。末段0x103b21ffc由type slot0x120371320（So19BBPlayerCoinService_p）解析
coin service；非nil才读basicModel.arc的copyright，并在0x103b22070调用
setTwoCoinsBtnEnabled。实际条件为**(copyright byte & 0xfd)==1**，即raw1/raw3为true，
不是简单copyright==1，更不是余额>=2。class vtable核对：BBVDBasicModel0x11fe0dd68
+a0=arc getter0x103ee752c；BBVDArcModel0x11fe0dc40+a8=copyright getter0x103ee5f54，
读取ivar0x120450490的byte。本段没有请求网络来决定该flag，也没有coins余额比较；
版权enum各raw的含义及其他模型分支不能由掩码猜测。其他setter候选/不同播放器场景
仍需分开核对，不能推广为全客户端两枚规则。

## 推送注册、权限状态与设备上报

PushModule 的三个调度事件应分开：ApplicationLaunch runnable（0x1001a7770）
调用setup（0x1001a7800），trigger为applicationLaunch、main线程、默认priority450；
ModuleInitialize runnable（0x1001a7960）经0x1001a7abc调用start（0x1001a7ae0），
trigger为moduleInitialize、main线程。homePageInitialized另执行内容放行和失败路由重试，
不能按函数地址推出框架的全局事件先后或priority比较方向。
setup的AppDelegate=nil分支跳过服务安装和Center配置，但仍注册五个生命周期通知。
Helper的WillEnterForeground（0x1001b1b64）把当前badge十进制记为
main.active.redpoint.0.click的num，没有正数门槛、没有清badge；它与下述Center
DidBecomeActive清badge并发callback/badge是两条链。

BFCPushService.initializeWithAppDelegate（0x115e02908）以self+8 bit0一次门控，
首次先写initialized，再associatedObject保存服务、用class_replaceMethod安装五个
AppDelegate通知方法，并设UNUserNotificationCenter.delegate=self；该局部未保存旧IMP。
静默收包（0x115e03b00）传原userInfo给Center，随即调用fetchCompletion raw0，
不等待路由/网络完成。Center（0x1149e97d4）构造type1/silent=true的content，
先forward再通知contentHandler，本体不发callbackClick；不能把type1静默收包当成点击。
旧本地通知（0x115e03be4）type0、identifier取userInfo.task_id；它会forward，
但不进入远程type1的点击API，identifier也不同于UNresponse的request.identifier。

APNs didRegister 回调（0x115e0395c）逐字节用 `%02lx` 转小写两位 hex，没有固定
NSData 长度校验，再交 BBCPushCenter。Center（0x1149e94fc）先更新 RAM token 和
BBCPushNotificationPreferences.deviceToken，再发 type=1 上报并通知 delegate，
不等待上报成功；init 会从 Preferences 恢复旧 token。APNs 失败仅转交 error，
Service 不清旧 token；接收错误的 Center（0x1149e9688）实际再发 type=4
（0x1149e9794），随后也调用 didRegister delegate。此 Center body 未清 RAM/
Preferences token 或 settings flags，所以 type4 可能带旧 token，delegate 名称
不能作为注册成功证据。

registerWithOptions（0x115e02ef0）以 options&0x47 申请通知权限；completion
不消费 granted/error，随后读取 settings。Center（0x1149e930c）保存 settings，
计算 notificationOpen，并置 notificationRegistered=true，再无条件调用 APNs
registerForRemoteNotifications。registered 因而不能等同于用户同意。open 的算法
0x1149e8030：authorizationStatus=3 为 true；=2 时要求 lockScreen/
notificationCenter/alert 之一为原始值 2；其他为 false。
PushHelper 正常启动传 options=7；提示 UI 确认路径在 status=0 时申请 options=7，
其他状态打开应用通知设置。GPPushNode.startIfAuthorized 实际条件为 status!=0，
不能凭名称缩成 status=2。启动注册的全局顺序仍待核对。

PushHelper.setup（0x1001a9c34）默认设 Center.appId=1；注入 service.productID
精确等于字符串 `14` 时改为 7（0x1001aa1a4），再连接 Service.delegate=Center、
Center.delegate=PushHelper。因此 app_id 也不能统一写为 1。启动 DD
`dd_push_new_install_use_custom_alert` 默认 false，与 isNewInstall 同为 true 才跳过
正常 start。使用 custom view 时查询 settings：status!=0 才注册 options7；status=0
也会递增 rn。rn setter 只写 RAM/Preferences，不发上报，启动 UI 完整顺序仍在追踪。

上报入口 sendPushReport（0x1149e80f0）没有以 token 非空/open=true 拒绝请求。
事件类型为 1:APNs token 到达、2:账号登录/切换、3:退出、5:notifyChangeToken、
4:APNs 注册失败、7:前台重新读取 settings；账号 update 回调是 RET。
type5 的两个明确消费者为 PushModuleRestrictedModeObserver（0x1001a8f7c）和
GPPushHelper（0x10f6d3688）的 enableChangedOfMode:，均查询传入 mode 的
BFCRestrictedModeManager.enableOfMode，true 才用当前 token 发 type5。模块初始化
0x1001a944c 注册前者，无 mode 过滤参数，dealloc 移除；具体 mode 枚举尚未闭合，
不能将 type5 等同于 APNs 新 token 或某个固定限制模式。extra 记录六个数字枚举：
authorization_status/sound_setting/badge_setting/alert_setting/
notification_center_setting/lock_screen_setting。

BBCPushApi.pushReport（0x1149e6df4）向 x/push/report 发 method=1，ignoreCache=true，
12 字段为 app_id 十进制、buvid（Const 0x104e2dab0→BFCBuvid.buvid，跟踪36字符）、
device_token（nil 空）、push_sdk=`1`、time_zone（Date 当前时区秒数÷3600向零截断）、
notify_switch 布尔十进制、type 十进制、mobile_brand=`Apple`、mobile_model=
UIDevice.bfc_platformString、mobile_version=systemVersion、extra 的 yy_modelToJSONString、
push_to_start_token（standardUserDefaults/ActivityPushToStartToken，nil 空）。
此 body 的 requestAsync 没有业务 completion/响应校验，也没有失败回滚 token 或
递归重试；公共网络层行为独立。BBCPushApi.init（0x1149e6d98）明确把默认 host=`api.bilibili.com` 存 self+8，
report 以该属性组装 `https://%@/x/push/report`。Center.setApiHost 会转给内部 API，
尚未找到其调用方，默认 host 不能等同于不可覆盖。上报额外初始化计数继续追踪，未读取
实际 token 或 prefs 内容。

### ActivityKit 两种 token 的独立上报

ActivityTokenMonitor（0x102bc72cc）创建 TokenState actor 时将 token/startToken
两个 Optional 清零，不从 NSUserDefaults 恢复。pushToStartTokenUpdates
（0x102bca134）逐字节 `%02x` 后空分隔连接，先与 actor.startToken 比较；相等
跳过，不同则更新 RAM，再写 standardUserDefaults/ActivityPushToStartToken
（0x102bca9f4），然后才启动报告。它读取 persisted old token 给状态/telemetry helper，
去重判断仍用 actor，不能据磁盘 old==new 就说进程首次更新不报告。
Activity.activityUpdates→每个 Activity.pushTokenUpdates（0x102bc7e88）独立产生
push_token，同样小写 hex；ActivityState ended/dismissed 跳过此次处理，其他状态
与 actor.token 比较，变化才更新 RAM 和报告。该分支未见持久化，也不是 APNs token。

两种变化均走 0x102bc93ac→0x102bc94b8→reportWithRetry（0x102bc5bf8），不调用
Center.notifyChangeToken。报告（0x102bc61a4）向固定
`https://api.bilibili.com/x/push/report` 发 method=1、ignoreCache=true，仅7字段：
app_id=`1`、跟踪 buvid、type=`1`、push_to_start_token=actor.startToken、
push_token=actor.token、push_sdk=`1`、当前时区小时向零截断；两个 Optional 字符串
nil 退空。它与普通 Center 的12字段请求、device_token 和可覆盖 host 不同。
retry 仅在两个 Optional 都 nil 时本地拒绝，空但非 nil 的字符串通过此检查。
调用方 limit=3，失败最多3次尝试，间隔1秒，最后抛错；sleep 取消直接走错误，
不增加第4次。completion（0x102bc58ac）直接 resume(returning:)，error
（0x102bc5a4c）resume(throwing:)，此 body 没有独立业务 status 检查；公共网络层
的判错另论。报告失败不回滚缓存，相同 token 的后续 update 仍可能被 actor 去重。

启动模块（0x102bc2fac）要求 dd.liveactivity_enable（默认 true）与 runtime
availability 17.2.0 均通过。start（0x102bc2890）的 tokenmonitor_delay 默认 false、
monitor_delaytime 默认10秒；delay false 或 applicationState 原始2立即监控，其他
情况延时，睡眠后不重新检查状态。startTokenMonitor（0x102bc6e8c）先创建
activityUpdates/pushToStartTokenUpdates 两任务，再读取 areActivitiesEnabled 做
日志与 cold_start 设置 telemetry，该读取不是此入口的权限 gate。两个任务在已读
创建 iterator 之前也未再检查它；框架是否交付 token 不能由 caller body 代替证明。

### 通知点击、延后导航与 badge 回执

BFCPushService.didReceiveNotificationResponse（0x115e03d70）按 request.trigger 是否
为 UNPushNotificationTrigger 取 type=1/0，转 delegate 后立即调用系统 completion。
Center（0x1149e99a8）先 forwardContent，再仅 type=1 调 callbackClick，最后通知
didReceiveContent。dismiss 也经过此 forward，不直接等同于“没有导航/回执”。
自定义 action 按 rich_1.0/rich_media.buttons 的 identifier 匹配，button type 为
remove 才 click=4，其余 click=0；dismiss 本身也取0。

点击 API（0x1149e7314）向可覆盖 current host 的 `/x/push/callback/click` 发
method=1，设置 app=appId 十进制、task=userInfo.task_id 的 `%@` 格式、
push_sdk=`1`、mid=Const 注入 service.mid 十进制、token=当前 APNs token（nil空）、
click 十进制与 extra。task nil 没有门槛，会经格式化形成 `(null)`。extra 仅自定义
action 传 `{button: actionIdentifier}` 并 yy_modelToJSONString；其他 action 传 nil，
字典下标会省略该键，不能把七条赋值语句描述为七个键必带。此 API 没有业务回执
或重试 block，不能由客户端发送证明服务端接受。

forwardContent（0x1149e8978）在 handleAllow 恰为1时 main.async execute，否则
同步追加 RAM 数组；setHandleAllow 非零即 flush，不比较此前值。flush
（0x1149e8d90）把各条 main.async 给 contentHandler 后清数组，没有再次发送 click
回执。因此系统 completion/点击回执不等待延后导航完成。
homePageInitialized放行runnable读push.delay_handle_allow：signed<1立即，>=1
按Double秒main.asyncAfter；放行priority400、retryFailed priority200均为main，
调度器比较方向未证，不能按数值断言先后。
Helper构造（0x1001a9738）把普通/静默失败数组初始化空RAM；初次路由失败分别
append72-byte tuple或content对象。普通缓存还有主动延后条件，并非全是失败：
handle（0x1001b4144）只有launchOptions远程task_id为非空String且等于当前task时
才检查冷启动加速。dd_push_handle_url_try_speedup默认false，false直接缓存延后；
true时dd_push_url_can_speedup_pattern（默认空）必须正则匹配location=0且覆盖
完整UTF-16长度才尝试导航，否则也缓存。加速导航失败另append；无/不同冷启动task
直接route，该分支失败未见同样append。不能据数组名概括所有路由失败都重试。
retryFailed经main.async到0x1001ad04c，
静默数组仅scheme=bilibili且host=laser的有效URL才重路由；普通数组直接
processUrl:animated=true。已读循环结束没有清空/移除缓存。
该重试不再次调用HTTP callback/click，但action字符串非空时会记
push.push-message.action.0.click（0x1001aec0c），含action_id/task_id/当前Center token；
另有public.apns.ground.other路由结果埋点，不能概括为重试没有点击报告。
完整初次payload URL选择与框架全局事件顺序仍待核对。

导航parser（0x1001b0820）rich按钮按id匹配非nil actionIdentifier，读取字段
`link`；type为空/default/remove保留link，其他非空type清空link。没有匹配按钮
才回退顶层userInfo.url String。remove虽记录tuple flag，已读主handle没有用它
跳过route；因此remove点击raw4或dismiss不能单凭名称推断不导航。
parser为导航URL补缺失的na.src=push、from_module=push-pop，保留已有同名query，
重新拼回fragment。这些是导航归因参数，不是callback API字段。
silent分流（0x1001af0f8）只接受原始url的scheme=bilibili/host=laser，合法后亦按
上述相同launch task/DD加速决定立即导航或缓存；普通不同task失败的局部仅报错与
ground埋点，不追加silent缓存。静默收包无HTTP点击回执，仍有
public.apns.trigger.other收包埋点与public.apns.ground.other路由结果埋点；
不能把无点击API概括为无上报。消息与payload实际内容未读取。

willPresent（0x115e03cd4）仅回系统 presentation options：applicationState 原始1
为27（iOS14+）/7，其他为8/0，不在该 body 转发或发点击回执。
Center.applicationDidBecomeActive（0x1149e9274）只处理 signed badge>=1，先调用
setApplicationIconBadgeNumber(-1)，再报告旧正数；不要把 setter 参数归一化为0。
badge API（0x1149e75c4）向 current host 的 `/x/push/callback/badge` 发 method=1，
七字段 app/mid/buvid/device_token（nil空）/action=`clear`/type=`number`/number=
旧值十进制，该 body 没有 push_sdk。异步无业务 completion/重试，失败不还原本地 badge。

收包和路由埋点的字段来源独立：trackTrigger（0x1001ac4f0）的
public.apns.trigger.other含payload=原始userInfo经JSON options0/UTF8，失败省略；
task_id/url取原始String，否则空；app_state取UIApplication状态十进制。
该入口未见type/silent/remove过滤。trackGround（0x1001adde0）的
public.apns.ground.other同样含payload/task_id/url/app_state，另加ground_url=
实际路由URL、result=bool bit0的0/1、error=NSError.localizedDescription或空。
重试也记录ground，不能当作APNs HTTP receipt。

didReceiveContent（0x1001b2f48）先trackTrigger，再构造app.active.growth.sys；
remove/silent/local三个parser flag任一为true时不发growth。九String字段为
open_app_from_type=push、open_app_uid/groupid/url为空、open_app_addition=parser task、
open_app_wake=非空且相同冷启动task时1否则2、session_id=BFCActiveReport.sessionId
或空、idfa=BFCIDFA.idfaString或空、deeplink_id=最终路由URL。这里session并非
Ktor lazy会话来源；过滤growth不代表禁止导航。未读取真实payload/IDFA/session。

### 本地通知与 category

Center.init（0x1149e79dc）只注册rich_1.0类别；Service转换
UNNotificationCategory（0x115e02e18）时actions/intentIdentifiers均为空数组，
options=0、placeholder=nil。这条注册链没有把rich_media.buttons转换为系统按钮；
通知扩展另一路尚未证明，不能据parser字段推导已经注册这些UNNotificationAction。

Service.scheduleRequest（0x115e03400）仅_initialized byte恰为1且request.type=0
继续。复制title/body/badge；sound非nil用soundNamed，否则defaultSound。可变复制
userInfo后用传入identifier覆盖task_id，并用同identifier建UNNotificationRequest。
fireDate非nil取NSDateInterval(now,fireDate).duration，建不重复timeInterval trigger；
本体没有正数/clamp校验，nil则trigger=nil。addNotificationRequest的completion
（0x115e03754）仅return，没有处理平台错误或业务重试，也未设categoryIdentifier。
旧didRegisterUserNotificationSettings（0x115e03848）忽略传入settings，先写
didAskForPermission=true再重读实际settings交Center；该标记不是授权成功证明。

已确认四个静态业务schedule调用点，动态selector调用仍可能遗漏：

| 来源 | 操作条件与通知内容 | 标识及后续边界 |
| --- | --- | --- |
| 下载notifyUi（0x115933ee4） | state1239且lastestState非1239/0、inReview=false生成发送flag；main block再要求appstate原始2且flag1。标题/正文取下载模型非空值或本地化；url=bilibili://user_center/download | identifier=kBFCDownloadMessage:+entityType+":"+task.bfc_uniqueString；无论schedule与否仍post BFCDownloadTaskNotifyUiNotification |
| 投稿失败（0x10cdb0c5c） | title/body来自参数及格式化，url=/uper/user_center/archive_list；本体无appstate/权限门槛 | 固定BBUPER_ARCHIVE_ADD_FAIL，无fireDate，最终仍受Service初始化门槛 |
| Phone前台召回（0x10f26a96c） | 读push_recall_time(float days)/push_recall(body，空时本地化)；先取消，再以正数days*86400或默认5184000秒建通知 | 同identifier=longTimeNoUse；title空/userInfo初始空，Service仅附task_id，无url |
| HD转Phone前台召回（0x10c8892d0） | 与Phone同配置/取消/重建规则，两个入口本体未请求线上config | 同longTimeNoUse；本地type0无HTTP click/growth，trigger仍可记录 |

下载时间比较不能直接描述成可靠1秒节流：0x115933f64–0x115933f70计算
t=tv_sec*1000+tv_usec，未见微秒除1000；已有task时间还先被重写0。
随后unsigned(t-old)>1000或state变化才继续并保存t。保留这段单位/保存异常，
不据比较常量推出实际限流效果。上述通知仅静态研究，未调度或触发真实通知。


## 崩溃插件的实际提交与本地缓存完成

BFCAnalytics.installAnalytics0x10513a864 setupAppUUID后main dispatch_after两秒
（0x10513a8c8）→0x10513a8dc→setupTrackerHandlerIfNeeded0x10513abac。
config.isExperimentalGroupHitForKey(app_tracker_kscrash_enable_v4)
（0x10513abdc）为false仅log，为true才把appUUID交shared handler并装callback。
app_tracker_power_consume_enable命中结果XOR1（0x10513ac88–0x10513ac8c）作为
installTracker参数，不能从key字面反推开关方向/线上值。
BFCTrackerHandler.installTracker0x105142d10创建WCCrashBlockMonitorPlugin，
enableCrash/enableBlockMonitor固定true，listener=self，reportStrategy=1；输入
Bool只决定是否装bGetPowerConsumeStack=true的默认block config，随后plugin.start。
真实listener桥0x10514f160→super0x105144688弱取listener
（0x1051446ac–0x1051446c0）→onReportIssue（0x1051446cc），nil则不提交。
Analytics callback0x10513ad00把同一report dictionary分别交
trackLog(app_reboot_track)（0x10513ad44）及
trackTech(public.crash.crash-report-scene.track,rate100)（0x10513ad74）。
AnalyticsModule装入的Tech closure0x100029b04解析optional
BFCMikotoService.Type（typeref0x120274960→0x1196beac2），调用实际service
trackTech:extendedFields:policy:rate:（0x100029bdc），policy raw2/rate原传，
复用已闭合Mikoto→Neuron transport；nil service返回false。Log closure
0x100029dcc另取optional BFCLogService instance（0x120274940→0x1196beb58）
调用logEvent:type:file:function:line:（0x100029ee4）。具体provider inventory
false index180/slot0x120273188为LogModule._$GripperLogProviderModule；
注册0x1049522b0用BFCLogService key0x120276350→LogProviderDependencyProvider，
getter0x104952234→0x10495217c经once0x104952580创建LogSystem
（0x104952600–0x104952618），不是直接把provider当service实例。
两者均为同步提交回调，没有HTTP响应参数。
### LogService注册、日志后端与远程配置采用时序

LogSystem构造读standard defaults bfclog.blog_enable到instance byte+0x10
（0x1049525e4/0x104952610），后续getter不刷新。logEvent实现
0x104953a00→0x1049536b4用type/event_details包装原dictionary，
NSJSONSerialization options8（0x104953868）后UTF8，失败不写；
成功经0x1049534b4/0x104953028按该snapshot选择以下出口。
false分支0x104953314→C logger0x11539bba4→global0x120db2368 BFCLogEngine。
engine init0x11539bfb8注册DDFileLogger到DDLog（0x11539c1fc）；
DDFileLogger.logMessage0x1153bda34转UTF8 NSData（0x1153bdb34）→
lt_logData0x1153bdf40→current handle.seekToEndOfFile→writeData:ddError:
（0x1153bdfa0），证明的是本地文件出口。可选BFCLogFileHandle封装mmap/zip，
其内部写入另追，不把文件logger当已上传。
true分支实际0x1049533a0→BLogger virtual+80=0x1050a1bf8，mLogger nil
直接返回；0x104953140是String.Encoding value-witness destroy，不是sender。
ProviderModule exec0x1049524a8→0x1049529e4先构造DDLogger，再按同持久Bool
false传DDLogger、true传nil给BLogger init slot+78=0x1050a1ab0
（0x104952c08）。此处nil会构造BLogServiceDefaultImpl；已有非nil mLogger
不替换。DefaultImpl log0x1050a26b0 level4选BLog.error
0x1164801c8→0x116480204→C0x116486584，coreglobal0x1210df460 nil跳过，
非nil到0x1164802d0；core内部持久化/上传还在追踪，无Crash服务器ACK证据。
配置更新入口LogModule0x104951890→0x10495262c先resolve LogService并excute
（0x1049526bc/0x104952720），之后才取optional DeviceDecisionService交
0x104955c48：log.blog_enable defaultfalse→写bfclog.blog_enable
（0x104955ccc/0x104955d0c），log.use_oslog→bfclog.is_use_oslog。
该updater没有写已构造LogSystem.byte+0x10，故不能声称同进程即时采用新开关；
文件大小等已有缓存配置及其他task顺序仍须分别核对，不输出实际配置值。
### Crash实验门禁与issue模型

实验Bool配置callback0x100029d18解析DeviceDecisionService
（typeref0x120274938），调用getBoolForKey:defaultValue:false
（0x100029d9c）；缺service/未命中默认false，因此不能据插件构造固定true
认定所有启动都安装Crash。具体分组仍是服务端/本地配置结果，未读取实际值。
onReportIssue0x105142ee0按plugin tag/reportType/dataType分支。Lag reportType2
的五字段app_launch_time/uuid/key/log/call_status中log是类型label；generic
NSData/UTF8分支五字段app_launch_time/diagnosis/uuid/key/log中log是UTF8文本，
diagnosis尝试解析crash.diagnosis，失败退固定说明（0x105143388–0x10514360c）。
其他dataType分支四字段app_launch_time/uuid/key/log。app_launch_time取
reboot analyzer，uuid取handler.app_uuid，key取issue.filePath；只记录来源，
不输出实际报告/身份/路径值。payload无效可跳过提交。
**正常返回的共同尾部无条件reportIssueComplete(issue,true)**
（0x105143684），不测试tech callback Bool、不等待网络结果；无callback/无效payload
路径也可到这里。插件0x10514f1a0排serial pluginReportQueue
（0x10514f224，init nil attributes0x10514ece8）。reportType1 success==1
调用deleteCrashDataWithReportID（0x10514f538），无论success都移除uploading ID；
成功且队列空继续delayReportCrash。Lag成功也删相应文件
（0x10514f844）。这只是本地交付后清理，不证明服务端ACK。
plugin.start0x10514ed84在安装后delayReportCrash（0x10514f004）；helper
0x1051505cc main再延两秒，strategy1→reportCrash0x105150978→serial queue。
缓存非空且未uploading时取一份报告、加入uploading、构造issue
（0x105150c08–0x105150c40），排main回plugin.reportIssue
（0x105150e2c–0x105150e34）。这是启动/后续本地完成触发的缓存重放，未证
活体崩溃发生时发送或HTTP失败重试。
loadPendingCrashReportID0x10514aaf8枚举KSCrash.allReportID，取首个按"-"拆分
component count<6的ID（0x10514b340），wrapper未排序/TTL检查；底层顺序未证。
getPendingCrashReportInfo0x10514a7a8读取报告JSON encode，nil/空编码直接删除
（0x10514a9f4），独立于网络。删除最终到NSFileManager.removeItemAtPath:error:
（0x1051759b4），未测试返回Bool/error，因此连磁盘删除成功也不能由local completion
反推。缓存捕获writer、完整配置来源、Log独立出口与业务初始化可达性仍未闭合。

## 稍后再看的旧 Phone 请求族

BBPhonePegasusWatchLaterAddApi（class0x1200b3898）super由实际class metadata
确认为BBPhoneDeprecateApiV3Base（0x1200a4758），不是据API名推断Kotlin实现。
三个apiConfig均复制super配置后覆盖apiPath/requestMethod：

| API / config | endpoint | config method raw |
| --- | --- | --- |
| Add，0x10f53eb00 | https://api.bilibili.com/x/v2/history/toview/add | 12346 |
| Delete，0x10f53edcc | https://api.bilibili.com/x/v2/history/toview/del | 12346 |
| List，0x10f53f190 | https://api.bilibili.com/x/v2/history/toview | 12345 |

Base.options0x10f25ffe0若bfcRequest.options已存在就复用，不重建当前参数；缺失才
读取apiConfig，method减12345（0x10f2600cc–0x10f2600d8）写BFCApiOptions，
对应公共builder raw0 GET/raw1 POST。base config0x10f25f8bc默认timeout60、
cacheValidTime60、apiSignType34567、isNeedCacheResponseData=false；options将
signType减34567→0、ignoreCache取缓存Bool反值，并安装params/extraHTTPHeader/
modelDescriptions（0x10f2601bc–0x10f260228）。default cache life并不证明启用
缓存。base init0x10f25f7b4构造BFCApiRequest；addToQueueAsync0x10f25f834先
options/setHandler，再bfcRequest.requestAsync（0x10f25f864）。这是实际传统
HTTP发送入口，最终公共参数/签名/拦截器仍遵守前述公共层门禁。

Add.params0x10f53ebc4写aid为%lld decimal（0x10f53ec00–0x10f53ec34），
from输入String经BBPlayerFromHelper.numberFromWithTrace
（0x10f53ec4c–0x10f53ec64），返回对象非nil才加入from；不是直接透传原String。
未在该getter看到aid>0校验。Delete.params0x10f53ee90优先viewed Bool非0时
只返回viewed="1"（0x10f53eec4–0x10f53ef04）；否则按aidArray原序用%@及
%@,%@拼成aid String，无sort/dedup/逐项数值校验，nil/空array得到aid=""
（0x10f53ef08–0x10f53f02c）。viewed模式不再合aid数组。
Add结果mapping0x10f53ecc8指向根"/"字典；List mapping0x10f53f254将/data映射
BBPhonePegasusWatchLaterListModel，isArray=false，模型count/list有独立属性。
这不是以本地新增标记或animation成功代替服务端结果。

实际manager入口已匹配这些classrefs：addWatchLater0x10f53f598创建Add
（0x10f53f5f0），输入aid/from设于0x10f53f610/0x10f53f61c，再安装success/
error blocks并queueAsync0x10f53f6c8。loadWatchLaterListAtPage:pageCount:
completionHandle:errorHandle:0x10f53fd24创建List（0x10f53fd5c），只使用
incoming completion/error；该body未读取page/pageCount x2/x3，未设置pn/ps，
queueAsync0x10f53fdec，不能据selector参数声称分页请求。success/error blocks
0x10f53fe30/0x10f53fe44只在captured callback非nil时转发，未在此改列表缓存。
deleteWithAidArray0x10f53fe58创建Delete并设aidArray（0x10f53feb8），发送
0x10f53ff48；deleteHasWatched0x10f53ffb8同类设viewed=true
（0x10f540000），发送0x10f540088。
Add success block0x10f53f720先reportWatchLaterClick:pageName:
（0x10f53f798），使用captured aid的decimal及reportFrom nil→空String；这是成功
callback后的点击事件，不是该body证明点击瞬间已报告。读BBPhoneWatchLaterConfig
shared.hasShownFirstSuccess选择toast；首次分支写true（0x10f53f884），按captured
isAnimation选择动画。然后业务completeHandle非nil时交(error=nil,response)
（0x10f53f8b4–0x10f53f8c0），**callback返回后**才manager.sharedConfig.
addNewWatchLater.sendNext(NSNumber true)（0x10f53f8c4–0x10f53f90c）；未在此把
aid加入本地列表。error block0x10f53f944可按NSError.userInfo描述显示toast，
再交原error及cachedMappedResponse（0x10f53fa18–0x10f53fa2c），不发新增signal。
config marker持久保存桥已另核实：BBPhoneWatchLaterConfig（0x1200b3b40）
super是BFCPreferences（0x1202710f0），属性表0x11e483ab0将
hasShownFirstSuccess/isCloseWatchLaterList编码TB,D,N，playState编码Tq,D,N。
shared0x10f541114用once0x120c9adc0/cache0x120c9adc8，configName
0x10f5411b0固定BBPhonePegasusConfig；上述Bool setter因此经前述动态preferences
桥写RAM/UserDefaults，未在该suite名拼MID。实际磁盘提交、其他账号清理与callback
重入仍未验证，不能据名称推定exactly-once。
带登录包装入口0x10f53fa9c查BFCAccount.hasLogin（0x10f53fb08）：true直接Add；
false调用navigator.loginWithCloseBlock:nil/completeBlock（0x10f53fbc4）。完成block
0x10f53fc20只检查captured isAddAfterLogin字节恰1才Add，未在此重查hasLogin/
调用身份或处理关闭callback。不能把登录弹层出现等同已添加，也不能从该wrapper
推断所有直接Add入口都有登录门禁。列表完整模型、
账号清理与较新的BBListWatchLaterManager/Kotlin路径仍独立待证，不能推广为全部
稍后再看入口已经采用这一旧实现。
manager.init0x10f53f47c另注册BFCAccount observer/actionType bitmask3
（0x10f53f4c8），创建RACSubject addNewWatchLater。其account callback
0x10f53f50c不检查incoming action/model，只对shared config写
isCloseWatchLaterList=false（0x10f53f534），不在这个body清first-success标记/
新增signal或取消待发请求；dealloc0x10f53f548移除observer。这是局部账号变化
消费，不能合并成用户列表或全部偏好的账号隔离。


### BBListWatchLaterManager 原生单条与批量添加

现代manager仍有不同endpoint。公开单条
addWith:spmid:from:isAfterLogin:container:snackBarEnable:（0x1043538c4）
转0x1043536e4：BFCAccount.hasLogined为true才0x104353cf4；false创建LoginConfig，
只有isAfterLogin bit1才装0x1043538b0完成closure，之后autoLogin。
完成closure直接回0x104353cf4，未在此重查登录/账号generation。该helper要求
router.navigationController非nil（nil到0x104353e74 BRK），取visibleVC，创建
options0x10434e60c。它用POST https://api.bilibili.com/x/v2/history/toview/add，
参数aid=输入Int64 decimal（0x10434e7d0–0x10434e7e8）、toview_version="v2"、
spmid及optional from→BBPlayerFromHelper.numberFromWithTrace，返回nil不加。
不将该入口改称资源数组协议；此options内未证aid正数门禁。
公开四参数addWith:spmid:from:isAfterLogin:入口0x104353c38把输入NSArray桥为
[String]（0x104353c60–0x104353c6c），转数组路径0x104353994（0x104353cc4）。
joined的typecache0x1202762d0→0x1196befa6也确为SaySSG。[String]数组路径
登录成立后用options0x10434e9b8，POST
https://api.bilibili.com/x/v3/fav/toview/adds（0x10434ea0c–0x10434ea54）。
resources为输入数组joined(separator:",")（0x10434eba4–0x10434ebb0），
另加toview_version="v2"、spmid，from也经上述转换；本体未排序/去重/空数组
拒绝。资源字符串具体生产/编码仍待调用方核对，不能把所有元素假定为aid。
两options都把/data映射同一optional非array Model（metadata0x10434f414）。
单条helper0x104353cf4和数组helper0x104353994创建BFCApiRequest，并经共同
0x104352f4c装completion（0x104352ffc）/error（0x104353078）后
requestAsync（0x104353094）。completion closure0x104353ef0先调用payload
adapter，再给业务Result tag0；error closure0x104353f7c给tag1。
单条adapter0x1043530c0→0x10435330c取/data动态cast Model，缺失/cast失败
则创建空Model（0x10435339c–0x1043533b0），并不把缺data自动改成失败。
单条业务closure0x104354038→0x1043530c4与数组0x104353ebc→0x1043533c8
负责toast/snackbar；后续Model字段、列表/删除、资源来源与缓存生命周期仍需
独立闭合，不能由请求completion推定本地列表已更新或Kotlin统一入口。


现代添加Model class0x11fe60680，RO0x11fe60620/property表0x11d8375a8：
isEnabled为Bool，toast/actionText/link为NSString，avids为NSArray；另有
iconStyle ivar0x120465460。init0x10434f2e0把isEnabled/iconStyle初始化0
（0x10434f300/0x10434f30c）。单条成功业务只在Model.isEnabled恰1且调用时
snackBarEnable bit1时交snackbar helper0x10434ff48（0x104353200），否则中心toast；
数组成功业务用isEnabled bit1（0x10435348c）选择snackbar，并把response.avids
（0x1043534a4）传入，而非原请求数组，visibleVC重新取当前router。
单条callback则保留请求时visibleVC/container，并把原aid封为数组；两者不能合并成
相同展示时机。错误分支用Error.localizedDescription→center toast，不在这些
业务callback body写共享列表缓存。Model customPropertyMapper0x10434efe8→0x10434f61c映射
isEnabled←show_toast、actionText←jump_text、link←app_jump_link；avids generic
class0x10434f078另指明元素类型。iconStyle在blacklist array0x120465400，
customTransform0x10434f268→0x10434f158读icon_type可cast Int，恰1才置Booltrue
（0x10434f22c–0x10434f23c），其他可cast数值置false；缺失/类型不符保留原状态。
该transform返回true不代表网络成功。snackbar后续动作/计时仍另核对。


### 新版 WatchLater v2 列表、清空与删除 builders

原生BBListWatchLaterInner中另外三项具体options builder已定位，不能套用旧列表
忽略page参数的结论。0x101108fc4设置GET
https://api.bilibili.com/x/v2/history/toview/v2/list（0x101109004），/data→
非array Response（metadata0x10110a0dc）。四String字段：start_key输入String、
asc由输入Bool bit1→"true"/"false"（0x101109180–0x1011091a4）、sort_field
由另一输入Bool bit1→decimal10/1（0x1011091d0–0x101109200）、split_key输入
String（0x101109204–0x10110921c）。builder不自行加pn/ps，具体输入生产另证。
first helper0x10110dd80给start_key空String（0x10110ddd4–0x10110ddd8），
后续helper0x10110e30c传入start_key原值；两者分别调用builder
（0x10110ddf0/0x10110e380），alloc/init BFCApiRequest后进入共同Rx包装
0x103714bd0（0x10110de3c/0x10110e3b4）。订阅、取消、回执归属和缓存更新仍需
沿该包装/效果consumer核对，不能把构造Observable当成已发送HTTP。
共同包装0x103714bd0捕获BFCApiRequest，创建Observable subscription closure
0x103714c84（0x103714c24–0x103714c3c；create helper0x1050f9f18）。只有该closure
执行才装completion/error并requestAsync（0x103714de0–0x103714de8），返回
0x1050e2514的静态NopDisposable（metadata0x11b353ef0，0x1050e2578）。
因此该包装没有订阅dispose→request.cancel桥；不等于整个页面绝无外层cancel，
也不据create返回断言已订阅。相邻另一包装0x103714ee4确创建dispose closure
0x1037151a4并调用request.cancel（0x1037151ac），不能把它的取消语义套用到当前
列表所选0x103714bd0。actual page effect subscription及账号/游标归属仍待证。
clear builder0x1011092c4设置POST
https://api.bilibili.com/x/v2/history/toview/clear（0x1011092ec），clean_type
为输入Bool bit1+1的decimalString，即false1/true2（0x101109454–0x101109478）。
v2/dels builder0x1011094fc设置POST
https://api.bilibili.com/x/v2/history/toview/v2/dels（0x10110952c），唯一业务参数
resources（0x10110966c–0x101109690）。输入collection按occupancy bitset/iterator
0x1011184e4枚举，每个Int64转decimal String（0x101109734–0x101109744），
数组joined comma（0x1011097fc–0x101109808）；空collection成空String，没有
显式排序或正数过滤。本体使用hash容器枚举，不假定用户点选顺序。
helper0x101114e94给该builder输入原collection，创建BFCApiRequest后直接
requestAsync（0x101114f00–0x101114f08），这个helper完整body没有装业务
completion/error handler。因此不能从该fire-and-forget helper声称删除成功后
才移除UI/缓存；实际业务触发与本地状态更新仍沿caller核对。
Response class0x11fb74c80/RO0x11fb74c20/property表0x11d5ca620含Bool
hasMore及String next/splitKey/playbackURLString、NSArray items。items generic
class0x101109d80绑定Item metadata0x10110b09c。custom mapper
0x101109d68→0x10110ba6c明确hasMore←has_more、next←next_key、
splitKey←split_key、playbackURLString←play_url、items←list；因此property名
不能直接当JSON key。willTransform0x101109e5c→0x10110bbe0另读tab_type
可cast Int，1→internal tab0、10→tab1（0x10110bcb0–0x10110bce8），缺失或
其他值保留初始化/已有值。
两条响应map thunk0x101110828/0x10111083c都到0x10110e2f8→0x10110e560，
读/data后dynamicCast Response（0x10110e5e4）；空dict、缺/data或cast失败
返回nil（0x10110e5ec/0x10110e604），没有在此构造空Response或发起重试。
Single入口0x10110e42c实际调用0x1050fb2c8→0x1050c10a4的CompactMap factory
（0x1050c10f4），输出MaybeTrait；nil转换结果在sink Optional tag1分支
0x1050c14ac–0x1050c14d0仅销毁、不forward，非nil才发next
（0x1050c1524）。因此这条入口缺/data/cast失败不会派发dataLoaded nil。
首屏helper0x10110dd80的feature byte两支也都过滤nil：byte==1分支直接调用
同CompactMap 0x1050c10a4（0x10110deb0），另一支经Single→Maybe helper
0x1050fb2c8（0x10110e040）。因此模型缺失过滤并非仅分页入口行为；
不把没有next事件等同networkFailed或构造空列表。
后续map0x101110574打包MainAction raw tag0x42，携带所捕获pageTab bit、
context和已解包Response（0x101110584–0x10111059c）；pageTab这个bit在options
控制sort_field10/1，不能将它误当独立用户sort设置。具体状态consumer
0x101113974接受tag族0x40/低位2，先把Response.splitKey写到state首String
（0x1011139c4–0x101113a18），然后按所携Bool查state的分支字典
（0x101113a28–0x101113a30）；未命中仍保留此前splitKey写入。
命中分支读取hasMore/play_url/next_key/items（0x101113acc–0x101113b38），
原捕获collection与响应items先通过0x101117d58追加，随后0x101114a98只裁掉
首尾连续cardType raw1（首端0x101114af8–0x101114c80、尾端
0x101114d48–0x101114db4），空数组原样返回；不是按aid去重，也不删除中间raw1。
组合列表与状态；缺模型的next过滤及networkFailed状态另见下段。
Swift reflection另提供业务名：MainAction descriptor0x1194eeaa8/fields
0x1197d4f1c的第三payload case是listAction；其type reference
0x1196ede26→ListAction descriptor0x1194eeac4/fields0x1197d4fc8，
payload case0/1/2/3/6分别refetch/loadMore/dataLoaded/networkFailed/deleteItems。
所以上述raw0x42对应listAction.dataLoaded，consumer低位6是deleteItems。
MainAction五payload后的无payload raw7对应hideManagementToolBar；delete效果
producer0x101114974/0x101114984包装fire-and-forget closure0x101118d44，
同时第二效果打包该hideManagementToolBar（0x1011149ac–0x1011149b4）。
包装0x10371598c的subscription closure0x103715adc→0x103715a34先执行业务
closure（0x103715a60），随后完成observer及返回NopDisposable
（0x103715a94/0x103715a9c），不等待删除HTTP ACK；0x103715984只swift_retain。
generic Store dispatch0x103715ba8先调用reducer（0x103715c3c），发布state
（0x103715c54），再forEach effects（0x103715cac）。实际页面dispatch、effects
订阅见下述实际slot/witness闭合；账号归属仍待证，不把服务端接受当已验证。
首屏feature byte来源once initializer0x101119340：解析DeviceDecisionService，
getBoolForKey:watchlater_disk_cache_enable defaultfalse（0x1011193c4–0x1011193f8），
存global byte0x121069a30；首屏helper经once-token0x12030a578读取，因此不是每次
请求刷新远程开关。true分支成功map0x1011103ac先0x10110d46c写缓存，再发
raw0x42 dataLoaded，latestArray为空；false分支不走该缓存writer。
缓存ID helper0x10110d330每次读取BFCAccount.currentUser.mid，nil或MID<1返回nil；
否则拼MID decimal + "_" + pageTab映射10/1 + "_" + asc/desc，未输出实际MID/key。
writer0x10110d46c在**响应map时**调用它，先改Response.tab为捕获pageTab，
yy_modelToJSONString非空才交FallbackCacheOCBridge helper0x102124f0c，scene
main.later-watch.0.0。version来自once0x10110d1a8读取Bundle CFBundleVersion
String，缺失/错型为空；不是cache协议固定版号。writer明确传expirationTime=nil
（0x10110d548），completion是nullsub0x10110d5f8，并立即释放返回task
（0x10110d58c/0x10110d590）；没有等后端写入ACK。nil expiry在已定位FallbackCache实现的判定见后段，注入覆盖/存储边界仍另证。
在已查writer/key helper没有原请求MID或generation比较，当前MID读取与URL发送时
账号快照不是同一证据；未运行复现跨账号写入，不作发生过污染的结论。

true分支error closure0x10111043c→0x10110e180收到捕获empty/ascendingChanged判定
Bool、pageTab和asc。仅Booltrue且同cache key helper能生成ID，才创建FallbackCache
读Observable 0x101110480→0x10110d5fc；同时保留networkFailed raw0x43事件的组合。
reader回调0x10110d7a8要求read code0、JSON非nil且YYModel Response有效，才发
dataLoaded raw0x42/latestArray为空，随后completed；其他结果仅completed。
其回调没有再比对当前MID/Store generation。组合0x10110e26c调用0x1051011e0，
metadata0x105101268明确SwitchIfEmpty；source是cache读AnonymousObservable
（0x1050c6448/0x1050c6480），alternative是networkFailed的Just
（0x10110e258→0x1050d9230）。sink ctor0x105101a98初始化empty=true
（0x105101afc/0x105101b00）；onNext0x10510170c把empty=false并转发，
completed0x105101734仅empty=true才订阅alternative（0x1051017b8）。
故有效cache发dataLoaded后完成，不再发原networkFailed；未命中/无JSON/无有效模型
完成空序列，才派发原错误action。不能写成同时派发两种action或无条件成功回退。
cache error事件若存在则走sink原error转发0x1051016f0，不自动转alternative；
实际reader业务失败的code映射见下述native bridge。

Swift bridge的具体read结果加工0x102126354首先dynamicCast为
KntrCacheResultSuccess（0x102126380–0x102126394），成立时回调code0、data可选String、
error:nil（0x102126478–0x10212648c）；Success.data=nil仍保留code0，并非非空数据保证。
其他结果用String(describing:type)再依次contains CacheResultMiss、Expired、
VersionMismatch、Corrupted（0x102126400/0x102126458/0x1021264f4/0x102126544/
0x102126594），对应code1/2/3/4，data:nil/error:nil；未知类型也退code1
（0x1021265a4→0x102126468）。这里失败分类依赖类型描述String子串，未使用每类
dynamicCast。async error另回code4、data:nil、加工后的error
（0x102126740/0x102126750–0x102126764）。read success callback先检查isMainThread
（0x102126174）：main直接加工（0x102126188），非main dispatch main.async
（0x1021262c8）。上述WatchLater消费者不发Rx error，而以非0/nil/模型失败完成空序列，
因此这些cache失败仍由SwitchIfEmpty发原networkFailed；不把bridge NSError等同Rx error。

cache读的dispose与HTTP NopDisposable不同：0x10110d5fc把返回FallbackCacheOCTask
包装进闭包0x1011104e0，再0x1050a8718构造disposable；闭包到task helper
0x102124e00，调用非nil cancelBlock后将其function/context清零
（0x102124e30/0x102124e54）。read bridge0x102125d54调用
KntrFallbackCacheNativeKt.readAsync:scene:id:version:（0x102125dfc/0x102125e14），
订阅async对象virtual+0x10返回handle（0x102125f80），捕获它安装task.cancelBlock
0x102128248→0x102127bc0：调用captured handle的virtual+0x10。
write bridge0x102124f0c同样将可选expirationTime转KntrLong，nil保持nil，再调用
writeAsync:scene:id:data:version:expirationTime:（0x102125000/0x102125020）；
其返回task的cancelBlock也走0x102127bc0。这证明取消调用桥，不证明底层磁盘事务
已经中断，也不因Swift task释放推断自动cancel。native cache expiry/存储路径及运行
投递时序未运行验证；具体注入、nil expiry及文件后端见后述FallbackCache章节，
未读取实际cache/账号key。
清空列表与v2/dels的fire-and-forget不同。MainAction无payload raw3
clearAllWatched由0x1011152c0→0x10110d9d8传Booltrue，clean_type=2；raw4
clearAllInvalid由0x101115308→0x10110d9e8传false，clean_type=1。共同helper
0x10110d9f8构造clear request，再同Rx包装0x103714bd0；之后用Materialize
0x1050db7c4（metadata accessor0x1050db84c）把next/error/completed变成事件，
flatMap交0x10110db8c/0x101110814→0x10110dba0。其next raw0只返回empty
Observable；error raw1显示FavoritesRes.string_65后返回empty，不产生refresh action；
completed分支显示string_111，再发MainAction raw0x80 refreshAllData，Boolfalse
（0x10110dd28–0x10110dd60）。所以这是成功结束后的重拉效果，不能把批量delete的
乐观本地移除或无ACK handler套用到clear。这里先派refreshAllData action，
不据action名字认定立即发HTTP。MainState reflection descriptor0x1194eeae0/
fields0x1197d50a4、metadata0x11b127200的field vector确认splitKey0/isAscending16/
selectedTab17/listData24/isManagementSheetShown32。

clearAllWatchedAlert raw1由0x101115164的0x1011151a8分支清management sheet Bool，
构造AnonymousObservable→0x10110d058，BFCAlertController builder0x1011088a8；
confirm closure0x10110d1a0传raw3到0x10110fe80，向observer发clearAllWatched再completed。
clearAllInvalidAlert raw2分支0x101115214→0x10110d8b4→builder0x101108b50，
confirm0x10110fe78传raw4，cancel0x101110898→0x1011101a4只completed。
两个alert都经通用0x1004e7380到
alertControllerWithTitle:message:confirmTitle:confirmHandler:cancelTitle:cancelHandler:dismissOnEmtpyTapped:
（0x1004e7508），confirm bridge0x1004e7594调用捕获closure；builder的confirm wrapper
0x101108fb4/0x101108fb8→0x101108f7c，cancel wrapper0x101108fbc/0x101108fc0→
0x101108f2c。navigationController非nil才present；未提供这些alert的全部上游菜单入口。

refreshAllData的state reducer0x101115978识别action族0x80，传Bool到0x101110a0c，
逐现存分支重组ListState后写回字典（0x101115a28），返回空effects。
helper保存items/offset/hasMore/playURL/totalCount等，清networkError、selectedItems并
isToolShown=false；items为空时isLoading=true/pullToRefresh=false，非空时
isLoading=false/pullToRefresh=true（0x101110cec/0x101110cf4/0x101110cf8、
0x101110dac/0x101110dd0），isAscendingChanged取incoming Bool（0x101110dd4）。
clear完成传false。结合已查UI consumer，非空且headerState1才beginHeaderRefresh，
随后header action仍经refetch reducer；不能把所有分支或空分支都说成已重发请求。
其余combined reducer/外部观察采用范围继续核对。

左滑删除物理TableViewAdapter.tableView:commitEditingStyle:forRowAtIndexPath:
0x101108538→0x1011086f8，按indexPath取component并cast ItemComponent，成功才
读item.aid（0x1011087b8），store非nil才dispatch slot+98（0x10110881c）。
打包raw0x47 singleDeleteAlert，byGesture固定true（静态word0x1182502d0=1，
0x1011087f8/0x101108800）；此body没有按incoming editingStyle再次分支。
其reducer low7 0x101111434在byGesture true分支把单aid包装Set
（0x101111498/0x10111149c），产生raw0x46 deleteItems effect
（0x1011114c4/0x1011114dc），不走另一路确认弹窗。这里只归属系统commit动作，
非所有删除菜单均免确认。
deleteItems consumer0x101113c90枚举state分支字典occupancy，逐个分支对items的aid
查所传Set（0x101113f84–0x101114010）；匹配项分区后通过0x101118c24移除tail，
再裁掉首尾连续cardType raw1，保留中间分隔项。结果items写回当前分支、更新state
字典（0x101114740、0x101113d60/0x101113d90）；不是仅删除当前pageTab。
完成遍历才构造删除HTTP fire-and-forget和hideManagementToolBar两个effect
（0x101114920–0x1011149c8）。结合Store先发布state后订阅effects，证明本地删除
发生在该网络effect发出之前。这个发送helper无业务ACK/error handler，所以在已查
删除consumer/发送路径中未见失败回滚；外部通知/重新拉取仍可能纠正，不能声称整个
客户端永无恢复。后续hideManagementToolBar raw7进入0x1011154b8，读取当时
MainState.selectedTab，只清这一个分支selectedItems（0x101115574/0x101115578），
再对其isToolShown=false（0x101115808），经0x101110fd4写回字典；所查body保留
该分支totalCount，没有在此重拉或遍历全部分支清选中集合。不要把跨分支删除items与
当前分支toolbar清理合并为同一范围。

ListState reflection metadata0x11b127290/descriptor0x1194eeafc确认字段offset：
items0、offset8、networkError24、hasMore32、playbackURLString40、isLoading56、
isToolShown57、selectedItems64、totalCount72、pullToRefresh88、isAscendingChanged89。
请求reducer0x101111f30只接listAction族0x40，low0 refetch进入0x1011122a4，
low1 loadMore进入0x101111f8c。两支先要求state分支字典非空且含pageTab；否则
无请求effect（0x1011126e8/0x1011126d0）。所检查这两支在分支存在时未用旧
hasMore/isLoading值拦截请求，而是清networkError、写isLoading=true再存回分支；
UI源仍可能另行门禁，不能外推任意触发频次。
loadMore读取该分支offset String原值（0x101111ff0/0x10111277c），捕获其items
作latestArray，asc来自state.byte+16、split_key来自state首String
（0x10111276c/0x101112770），进入0x10110e30c（0x101112784）。refetch同样
读取state asc/split_key，经0x10110dd80把start_key置空（0x1011128e4–0x1011128f4）；
另传入Bool来自isAscendingChanged或现items为空的判定（0x101112800–0x1011128b8），
不是额外HTTP字段。两支均先更新state再返回effect，Store随后订阅发送。
networkFailed low3进入0x1011124b0，分支存在才写捕获error到networkError24，
isLoading=false、pullToRefresh/isAscendingChanged=false
（0x1011125f4/0x101112608/0x101112620），保留items/offset/hasMore等其余字段，
没有在这支发自动retry。模型nil被CompactMap过滤时不进入这支；是否有另一个
完成事件重置UI仍沿订阅consumer核对，不直接推断永久loading。
列表页物理入口已缩小：ListViewController.viewDidLoad0x10111b9a4→
0x10111a25c装header refresh action closure0x10111c104
（0x10111a3a0/0x10111a3fc），其0x10111b8fc先resetNoMoreData，再携
当前pageTab dispatch listAction.refetch raw0x40（0x10111b974–0x10111b988）。
footer refreshing action装closure0x10111c124（0x10111a448/0x10111a49c），
传raw0x41到0x10111d6e0，weak VC有效才读当前pageTab并dispatch loadMore
（0x10111d72c–0x10111d74c）。这证明拖刷新/底部分页动作的业务生产，
不把viewDidLoad安装action误写成它已立即请求。另一个binding0x10111acbc
订阅该ListVC.viewWillAppear:，先映射Void，再TakeCount1
（0x10111aed4/0x10111aee0→0x1051031f8，实际TakeCount factory
0x105103244），首次appearance回调0x10111cacc携当前pageTab dispatch
同refetch raw0x40（0x10111caf0–0x10111cb10），disposable进VC.disposeBag。
此为每次binding的首次appearance，不等于所有页面/整个进程只请求一次；
reducer请求门禁仍决定是否发HTTP。
ListVC binding另从store virtual+80读BehaviorRelay（0x10111b5dc），CompactMap
0x10111f0b8→0x10111d768要求weak VC有效并取其当前pageTab对应ListState，
订阅0x10111b6a4→callback0x10111d860→UI consumer0x10111d8ac，disposable进VC bag。
pullToRefresh=true且headerState1时先contentOffset0再beginHeaderRefresh并返回；
其他路径有networkError时headerState3才endHeader，items非空show error toast、空则
error展示。无error时items空且isLoading=true进入加载展示；items非空或isLoading=false
才到0x10111db04：pullToRefresh=false/headerState3时endHeader，再按hasMore选择
endFooterRefresh或endRefreshingWithNoMoreData（0x10111db80）。因此结束刷新不能
概括为只看loading=false；列表是否非空与pullToRefresh也参与。
已查effect订阅只传onNext action callback，其error/complete handler参数为nil
（0x103715d4c–0x103715d60）。nil模型被过滤不生成dataLoaded/networkFailed，也未在这条
完成回调另派reset action；仍不外推所有UI状态永久不变，因为其他action/外部生命周期
可以改state，实际空响应情况未运行验证。
MainVC.initWithNibName:bundle:0x1011233c4→0x1011271c4初始化其disposeBag/
cachedViewControllers，并新alloc Store后调用0x103715b2c，存入该VC.store
（0x1011273bc–0x1011273ec）。所检查构造不是全局共享Store；cached ListVC工厂
0x10112752c把这个Store传给列表页。MainVC.cxx_destruct0x10112556c释放disposeBag、
cached页数组与Store（0x101125588/0x1011255a8/0x1011255d8）。Store ctor
0x1037164ac创建独立DisposeBag存+28、BehaviorRelay存+10，并保存reducer function/
context；析构0x103716318释放relay/reducer context/disposeBag。实际effect subscribe
0x103715ce4传该Store作callback context，回调0x1037167cc返回同Store dispatch；
所查链未携MID/request-generation做回执比对。页面对象释放时机仍取决于外部持有，
不能从析构入口存在推断pop/换号即已取消请求；该请求包装NopDisposable边界仍适用。
全局账号通知是否重建/关闭这一MainVC、外部reload和请求取消继续待证。
Store nominal descriptor0x1195e8ef4的vtable header offset15/count6
（0x1195e8f34/0x1195e8f38），第五method entry0x1195e8f60解析到
0x103715ba8，对应metadata slot(15+4)*8=0x98，闭合上述VC实际dispatch接收者。
该方法state发布后逐effect调用0x1037165d4→0x103715ce4；它用
0x1050e2aa0安装回调0x1037167cc（再dispatch返回Action）并将disposable加入
store+28（0x103715d64–0x103715d94）。Rx helper在0x1050e2d58实际调用
ObservableType witness+10，而不是只返回未订阅的效果对象。该conformance
0x1183a4f80明确protocol ObservableType0x1196b6198、type Effect
0x1195e8ec4、witness pattern0x11b26bf78，slot+10=0x103715940→
0x103715910读取Effect内实际Observable并调用virtual+60
（0x103715924–0x103715930）。列表所选Observable subscription已在上文闭合
completion/error/requestAsync；dispose没有直接request.cancel。页面销毁、
外层账号/并发响应归属还需独立证据。

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
有限值和整数范围检查。sourceType 的字符串映射不为空时加入 source，映射表仍待解码。
scene 按 UIApplication.applicationState 为 0 取 front，否则取 background；
extendFields 另有字典合并调用，冲突优先级尚待核对。reportScene 非零时加 report_scene。

BFCApiOptions.requestMethod 设原始值 1，reportScene=0 使用
`https://api.bilibili.com/x/v2/history/report`，非零使用同主机的
`/x/v2/history/report_scene`；设置 params/modelDescriptions 后创建 BFCApiRequest 并
requestAsync。该业务方法还根据 syncLocalType 写入本地缓存，发生在异步请求启动后，
没有在此入口等服务端成功才写入。具体枚举、缓存实现与响应处理仍待核对；也不能据
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
实验的实际命中与策略枚举来源尚未贯通，不能将 preset 值写成当前运行状态。
getReportParams（0x114452990）复制业务 ID/类型，currentTime/duration 来自上述
播放位置与媒体时长，localDeviceTime 来自 BFCServerTimeChecker.realTimeInterval，
localStartTime 来自 tracker.heartBeat.curHeartBeatContext.getLocalStartTimestamp；
ignoreTimeVerify 设为 playback.inQueuePlay。服务端校时与开始时间生成还需下钻。

reportPlayHistory（0x114452b64）经 shouldReport 再调用 helper。另有明确区分的
reportPlayHistoryOnlyMemory 与 reportPlayHistoryToMemoryAndDB：后者先调内存历史
入口，再调用 setCurrentTime:cid: 和 setDuration:cid:；不能将所有保存行为等同于云请求。
_addObserver（0x114452ebc）观察 playbackState 与 playerDestroyed。状态原始值 5 时，
reportWhenStoped 为真走云历史入口，否则仅内存；原始值 3 分支用于历史提示。
playerDestroyed 为真且 reportWhenStoped 为真时也调用云历史入口。状态枚举业务含义、
观察者安装方、重复触发处理与其他调用方尚未完全核对。
addSupplementSyncObserver 另接补同步 manager 和 reportScene；补同步调度待继续追踪。

未登录入口的 saveLocalWatchWithReportModel（0x10cb181c8）创建 BFCHistoryAVModel，
data_id 为 avid 字符串，view_at 为当前 Unix 秒向零截断后写回 double，progress 将
currentTime 用 fcvtps 向正无穷转整数，duration 保存原媒体时长；同时写入 cid、
总分 P 数、当前 P、标题/封面、UP 名称/MID、part 和 uri。
uri 格式为 `/av/%@/?page=%@&trace=play_history`，最后交给
BFCHistoryDataManager.engine.saveHistoryDataWithModel。此方法未看到将近结尾进度
改为 -1；实际底层持久化、排序/去重、读取和登录后的合并仍未证明。

### 播放器心跳的边界

`BBPlayerHeartBeatServiceV2.playStart/playEnd`（0x114889414/0x11488956c）先验证
播放准备状态、context/meta 有效性与完成状态；开始路径包含 resumeTrackerMetaInfo。
_playStartReport/_playEndReport 根据 v8.48.0_heart_beat_update_meta_info 条件更新
质量/语言等信息，再调用下层 heartBeat 的 playStart 或 playEnd:withSyncImmediately:。
因此历史同步、播放心跳对象和 Neuron PlayerEvent 描述符不是同一个请求。
底层计时、会话和发送队列见下节；Tracker创建本服务和观察触发已有静态链，
其他scene的采用范围及实际调用频率仍需核对。
BFCAtomicHeartbeat有独立的应用事件路径，不能仅凭同名“心跳”推断它走播放历史
端点或具有相同节奏。普通service.trackMetaInfo:在建立context后将self赋给
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
（policy raw0；0x1001298c0），不是直接构造播放历史HTTP。解析所用type缓存
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
Gripper派发链。执行读取enable_bfcatomic_heartbeat(default=true；0x100129e00)，
通过才创建BFCAtomicHeartbeatInjection并shared.startWith（0x100129e68）。该开关
false在0x10012a064退出，也不继续读取下面nettrack开关。
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
setter仍未穷尽。不能从这些受meta.shared门禁的状态或stream_reachable字面
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
unregister0x10013e4a4只走同type移除，已读body无直接状态reset，未证明logout触发。
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
本轮没有执行DNS或探测网络，未验证OS实际超时/回调次数。


### 心跳上下文、会话与发送队列

Context.setupSession（0x1148859c8）优先采用 metaInfo.sessionID 非空字符串，否则调用
BBPlayerSessionManager.createSessionID（0x11487f6b8）。后者将 BFCBuvid.buvid 与
`NSNumber(double(Date.timeIntervalSince1970 ×1000))` 用 `%@%@` 拼接，取 bfc_md5String
再 lowercaseString。结果是小写 MD5 形状；不是 UUID，也未看到随机数。NSNumber 的
具体文本格式、同时间碰撞及现版生成尚未验证，不能离线随意用整数毫秒字符串替代。
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
extra组装仍待逐项闭合，不能把普通UGC type/play_mode/network_type规则推广到OGV。
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
完整item/graft分支及_isPrepared重置仍待核对，不能称每次起播都上报或成功回执才置位。
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
上述field构造与AppPlayerInfo的18项编码已闭合，但其他业务配置与observer更新未穷尽。
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
的idfa/track_id等键混同。$idfa/$idfv缺失才读VKIdentifier，未读取实际标识值。
$player_event_seq缺失时取model+8旧Int32转十进制String，再把缓存+1
（0x114881ed8–0x114881f10）；提供该键则不递增。model.initWithPlaySession:
0x114881884初始化seq=0（0x1148818dc），这是实例报告次序而非推荐report编号、
请求次数或服务器ack计数；其他业务配置调用与session reset/继承的关系尚未穷尽。
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
仍未穷尽，不能从重建播放器对象断言新session。
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
仍待核对，不能仅凭这组方法断言暂停、缓冲、seek 的所有行为。

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
heartbeat.v2.cache.copy，并有写临时副本/移除/移动分支。完整异常恢复、存储保护和
loadCachedReportItems0x114888570检查文件存在/NSData非空，再unarchive；该方法未
读取当前时间、item年龄或账号。loadFileCache的排队block0x114887854将返回数组
直接addObjectsFromArray到memCache（0x1148878bc），非空时reportWith:nil、
syncToFileCacheImmediately=false、apiCallback=nil（0x114887920），没有在这段
恢复包装按TTL/账号过滤。这里只限定已读恢复路径，其他清理/文件生命周期仍待核对，
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
匹配回执；真实并发交错与其他start_ts writer仍待核对。
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
尚待核对，不把这一层看到的键视为整个应用心跳字段全集。

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

## 广告加载与归因的静态入口

UGC播放器广告有独立HTTP：BBAdPlayerAdUGCManager._requestUgcPlayerAdWithAid:cid:
0x1133e2c84先cancel当前request，创建新BFCApiOptions，GET
https://api.bilibili.com/x/v2/dm/ad（0x1133e2cf0/0x1133e2ffc）。四个业务params为
type="1"、oid=入参cid十进制、aid=入参aid十进制、ad_extra=下层返回String。
额外归因不是顶层字段：仅BBAdCmConfigManager.shared.avid等于入参aid时，分别
检查cm_from_track_id与ocpx_target_type非空，复制到ad_extra输入字典的
track_id/ocpx_target_type（0x1133e2d34–0x1133e2ea8）。两者多次读shared/getter，
未见一次性账号/归因快照。/data按BBAdPlayerAdModel、非array映射；新request
替换manager实例ivar后requestAsync（0x1133e3090/0x1133e3134）。此body未设置
timeout/auth/cache/responseQueue自有值。成功callback0x1133e31d8弱取原manager，
将/data model交_updateWithModel:；error0x1133e3250则交nil。两者不比较请求身份、
aid/cid或账号epoch；cancel不证明已排队回执不会更新，后续UI门禁仍待核对。
updateWithAid:cid:0x1133e232c先reportEnter、清mixList/hasAd/icon并把当前aid/cid、
upperAvatar/from_spmid/from_track_id/ads_control存实例，再用_hasAdWithCid:
0x1133e44ac检查ads_control.has_danmu且cids中存在longLongValue==当前cid；通过
才上述请求（0x1133e26e0/0x1133e26f4），不由enableShowDanmaku直接阻止HTTP。
BBAdPlayerUGCAdService._fetchDanmaku0x1133f0ec8先把PlayerDanmakuPreference的
enableShowDanmaku传manager，再从两次currentScene读scene_avid/scene_cid交update。
manager.init另观察共享cm_config，skip1/takeUntil自身dealloc；回调只在共享avid≤0
或等于实例aid时用当前实例aid/cid再update（0x1133e220c–0x1133e22b8）。
成功model消费0x1133e3280先对每个mixList item及icon.ad_info报告raw61，即
UIEvent表中的danmaku_advert_result（0x11cf88798的raw61位置）。mixList报告在
Danmaku/Floating额外校验之前，不代表通过这些校验，也不是实际展示事件。
_reportWithEvent:model:0x1133e6154要求model.ad_cb非空，构造av_id/c_id（NSNumber，
零值仍0）、enable_show_danmaku字符串0/1及可选extra.cm_from_track_id，交
BBAdReportUIEvent.reportUIEventWithAdcb:event:url:params:，url空String
（0x1133e639c）。UIEvent普通入口0x11433f4d8使用needFilter=false/salt=nil，
具体发送/缓存/失败恢复见下述独立UIReport链。

requestAdExtraWithParams:0x114326f64将update=false交
_requestAdExtraWithUpdate:params:0x1143276c4。adExtraSwitch false直接返回空String；
true时先合并_adExtra基础字典，再只拣允许键及匹配class的调用方值
（0x1143277c0/0x114327b3c），JSON options0成功才交BBAdReportCrypto.
AESUpperStringWithDefaultKeyFromData:（0x114327808/0x114327834），最终nil也返回
空String（0x11432788c–0x1143278a0）。不是明文JSON直接透传；该UGC caller的
update=false不走更新位置一次性分支。基础字段、允许键类型、AES模式和加载触发/
展示/点击链仍在核对，未读取实际身份或发起广告请求。
基础字典_adExtra0x114327c40的候选String键为lng/lat/lbs_ts/network/operator_type/
ap_name/ap_mac/vendor/model/screen_size/idfa/ua/mobi_app/ua_sys/ua_web/os_v/
bootTimeInSec/countryCode/language/deviceName/systemVersion/machine/carrierInfo/
memory/disk/sysFileTime/hardware_model/timeZone/network_v2/boot_mark/update_mark/
story_shown_ids/dns_client_ip/initial_time/opensdk_ver。String setter
0x1143448d4要求非nil、NSString且length>0才插入，因此不是所有字段每次存在。
build另用ParamInfo.build.intValue（缺/空→0）boxed NSNumber；user_apps用probe
返回对象，nil→空String，通过safeSetObject（非nil对象/key才插入）。基础构造
先apInfoWithUpdate:true、locInfoWithUpdate:false及postbackInfo，再逐getter读取；
未证明这些getter全部实时采集或权限通过，也没有读取实际位置/身份/安装应用值。
允许覆盖表0x1143278f0的19键有具体class：NSNumber的
disable_component_click_url/linked_creative_id；NSDictionary的
tab_req/view_req/comment_req/tab3_req/native_req/dynamic_req；NSString的
track_id/from_track_id/ocpx_target_type/ai_track_id/ai_from_track_id/creative_id/
request_id/caid/from_spmid/nature_ad/ad_story_extra。回调0x114327b3c只在输入值
isKindOfClass匹配时覆盖基础字典，未知键/错型忽略；此处允许空NSString，不能套
基础String setter的非空条件。
加密实际encryptAES:key:0x1143400c8使用CCCrypt Encrypt/AES、options raw1
（PKCS7、未启用ECB）、keyLength16、固定16字节IV（0x114340190–0x1143401ac），
即AES-128-CBC包装。key先以UTF8 getCString写17字节零初始化buffer，未在此body
检查转换BOOL；没有输出key内容。失败返回nil，成功data经每字节两位hex后
uppercaseString（0x11433ffb0–0x11433ffdc），空data/nil→空String，不是Base64。

UIReport实际请求与回执也已静态闭合。普通UIEvent的customBlock
0x11433fe8c先合并generateParameters，再合并caller params；后者覆盖同名字段
（0x11433fedc/0x11433fefc）。reportEvent:adCb:url:customBlock:
0x11433ccf0创建新item，timestamp为NSDate epoch秒×1000后截断到Int64
（0x11433cdb8/0x11433cdbc），生成参数、复制customBlock结果，再installParameters。
generateParameters0x11433e874含event/ad_cb/track_id/url/build_id/buvid/idfa/mid/
network/operator_type/ts/vendor/model/bootTimeInSec/countryCode/language/deviceName/
systemVersion/machine/carrierInfo/memory/disk/sysFileTime/hardware_model/timeZone/
dns_client_ip/initial_time/os_v；mid此时读BFCAccount.currentUser.mid并转十进制String
（0x11433ea30/0x11433ea40），不是API发出时重新读取。
installParameters0x11433efac只保留NSString key与NSString或NSNumber value，未要求
String非空；NSDictionary等嵌套value被过滤。这些是静态getter/schema，没有读取实际值。
_reportItem:0x11433d150要求item非nil、event非空、parameters非空，再排串行queue
com.bilibili.bbad.report.ui（init0x11433d038，dispatch0x11433d20c），单item参数
包装成一元素array交API（0x11433d2a0/0x11433d31c）。返回不等于网络成功。

BBAdUIReportApi.requestWithParametersArray:completionHandler:errorHandler:
0x11433e098使用NSMutableURLRequest/NSURLSession.sharedSession，POST
https://cm.bilibili.com/cm/api/conversion/mobile/v2。空array直接return，不调用成功/
失败handler。User-Agent来自uaWithEncode:false（nil→空String），Content-Type为
application/json，timeout15秒，body为{"uploads":参数array}的YYModel JSON data。
Memex.shouldCompressedByBrotli为true时Content-Encoding=br并替换压缩body；否则
才检查gzip（0x11433e210/0x11433e250）。压缩返回nil仍setHTTPBody:nil，未见回退
原JSON分支（0x11433e284–0x11433e290）。此路径不经过BFCApiRequest，不套用其签名/
ticket拦截器；URLSession自身的共享配置与Cookie实际行为尚未动态验证。
dataTask resume后释放局部task句柄，锁NSCondition并无条件waitUntilDate(now+
timeoutInterval+1)，即16秒；未在wait之前先检查done，wait返回BOOL也未使用
（0x11433e390–0x11433e3e0）。若完成信号早于wait，静态次序存在仍等到期限的可能，
未执行调度实验。wait后done=false才置done=true并生成domain
BBAdUIReportApiFailErrorDomain/code=-1001；未见在此分支cancel task。
网络completion0x11433e6f0在同一condition锁下只首次写data/response/error；done
已true时丢弃这些结果，仍signal/unlock。因此超时后的迟到成功不再转成业务成功。

成功须无transport error、HTTP status 200–299，且_BBAdUIReportApiModel非nil、
code字符串isEqualToString:"0"（0x11433e474–0x11433e4e8）；成功handler在此调用栈
接原data/response，未排main queue。失败统一新建上述domain、userinfo=nil的NSError：
transport error只保留code，非2xx用statusCode，模型缺失或code不匹配用model.code.
integerValue（模型nil→0），不是保留原错误说明（0x11433e524/0x11433e634）。
_reportItem成功handler0x11433d368随即_retryMoreThanInterval:0；失败
0x11433d374保存含原item的record。filename按event+identifier+url+timestamp
直接拼接，其中identifier0x11433f058是ad_cb+track_id（nil→空String）；没有分隔符/
账号分区。缓存为Caches/com.bilibili.bbad/report.ui的YYCache
（0x11433d090–0x11433d124），record与kUIAllRecordKeys分别写入；未证明两次写入
具有事务原子性。

_retryMoreThanInterval:0x11433d7cc逐缓存key处理，record缺失、f_index>4或
now_ms−item.timestamp≥86400001时删除（0x11433d8d4–0x11433d928）。入参interval
>0时还要求原item年龄>interval；读取的是item.timestamp，不是last_report_ts。
_reportAllRecords排相同串行queue后传3600000ms（0x11433d7c0/0x11433d7c4），
不是在此建立每小时timer。符合条件先从缓存移除、将原item.parameters与
is_reupload="1"合并，最多10条一批交同一API；原parameters后合并，若自身含
is_reupload会覆盖标记（0x11433d994–0x11433db0c）。未重新generateParameters，
因此mid等沿用创建item时的值；此body没有current账号/epoch校验。
批量成功handler=nil，先移除的record不再写回；批量失败callback0x11433db90对
捕获record逐个f_index+1、last_report_ts=本轮now_ms并_saveRecord
（0x11433dc30–0x11433dc54）。删除后发送前/失败重写前进程退出可能丢失队列项，
不能宣称恰好一次或持久化可靠投递。失败另发KntrAdAlarm.reportUiFailed，首次
is_retry="0"，重传is_retry="1"；该告警的网络出口仍待追踪。
这里另有尾批控制流缺口：发送判断只在当前record获准加入后检查count==10或
当前key为最后一项（0x11433da70–0x11433da90）。若已有不足10条的待发送项，
后续直到末尾的key均因缺失、过期、次数或interval被跳过，循环直接到
0x11433db38释放数组，没有循环结束后的flush；此前这些获准项已经从缓存删除。
这是本样本静态可达路径，尚未用真实缓存/请求运行复现，不把它表述为实际丢失次数。
外部重传触发已定位：BBAdModule.onModuleInitialize0x10ea736b4先ParamInfo.
prepareInfo，再BBAdSingleton.shared.observeAppLaunch（0x10ea736c8/0x10ea736e4）。
observeAppLaunch0x10ea73fbc以object=nil登记UIApplicationDidFinishLaunchingNotification；
selector0x10ea74014先BBAdReporter.retryFailReportWithType:7，再UIEvent.retryFailReport
（0x10ea74028/0x10ea74038）。后者0x11433f894→_retryFailReport0x11433ff28取
UIReport.shared→reportAllFailEvents0x11433cfd8→_reportAllRecords，进入上述一小时
原item年龄门禁。不是每小时定时发送；这里也没给已经发生的启动通知做补发。
模块初始化真实注册/执行时机及实际通知交付仍未证，不能仅凭selector宣称启动必重传。
BBAdReport.retryFailReportWithType:0x114326e20按bit0/1/2分别触发AdOwn/AdMMA/
CntReport；它自身不调UIReport。UI重传是启动selector的另一显式调用，不把raw7
错误映射为四通道，也不把该模块扩展为全部广告SDK重传。

UIEvent filter语义另有边界：_reportUIEvent0x11433fbc4总要求eventStr非空；只有
needFilter=true才进一步要求adcb非空（0x11433fc38–0x11433fc50）。过滤key按
event/adcb/url/salt直接拼接后MD5，命中实例filters就丢弃，未命中在发送前加入，
不是网络成功后去重；ordinary needFilter=false无需非空adcb。
reportWithName:adcb:url:params:的默认repeat=true（0x11433f7a0），最终对repeat
xor1得到needFilter（0x11433f834）。因此以下App前后台使用空adcb仍能进入独立
UIReport请求，不能套用UGC manager自有的model.ad_cb非空门禁。

BBAdAppEnterStateReportManager.shared的首次构造0x11415f5bc创建实例，保存
ParamInfo.ts为coldStartTs、初始化RAM任务数组，并以object=nil注册DidBecomeActive/
WillResignActive通知（0x11415f66c/0x11415f6a8）。广告模块初始化会取此shared
（0x10ea736f8），实际模块注册仍待核对。homeFirstScreenImageLoaded0x11415f6c0
报告app_enter_foreground，start_type="cold"、ts=coldStartTs（缺失退当前ts），
空adcb/url。该方法自身不检查是否首次报告，首屏回调外部去重仍待证。
DidBecomeActive0x11415f978保存Date epoch秒×1000的Double reportActiveTime，
捕获当时CFAbsoluteTimeGetCurrent，并main dispatch_after **30000000ns（0.03秒）**
（0x11415f9d4/0x11415f9d8）。该延迟callback先按捕获时间消费callup task，再在
isReportActive=true时报告app_enter_foreground/start_type="hot"；false只置true。
未在此callback读实际UIApplication状态或新的时间/代际，排队后快速失活仍可能
执行这段逻辑，实际OS调度未验证。
WillResignActive0x11415fe98用当时epoch毫秒减reportActiveTime，比较常数Double
30.0（0x11415fee8–0x11415fef4），即此局部单位为30毫秒，不能写成30秒。差值
低于门槛仅isReportActive=false；达到门槛置true并报告app_enter_background、
空adcb/url。这些是本样本的运算/分支，不推断设计意图或其他版本同样行为。

callup停留任务makeCallupStayTimeReportTask0x11415f7e0新建对象、isCanceled=false/
isCallupSuccess=false、startTime=CFAbsoluteTimeGetCurrent，保存adInfo/url/extra；
在main直接append，否则main.async append（0x11415f8a0–0x11415f914）。
_performCallupStayTimeReportWithCurrentTime:0x11415fb38仅处理!canceled、success、
adInfo非nil，show_time=truncInt64((传入currentTime−startTime)×1000)，负数跳过。
构造BCMUIAdEvent/name=na_callup_app_stay_time、原adInfo/url，先合原extra再写
show_time十进制String覆盖同名字段（0x11415fcf8/0x11415fd40），最后report。
随后逆序清除canceled或success任务，不依据网络回执；success但adInfo缺失/
show_time负数的任务也会清除。这是本地任务消费，成功标记局部来源见下；
BCM事件发送桥见下文，不能把“唤起成功”当广告回执成功。
task.callupSuccess0x11415ffc0只setIsCallupSuccess(true)，写self+9；cancel
0x11415ffb8只setIsCanceled(true)，写self+8。没有网络ack、清另一个flag或直接
消费任务的逻辑，因此两flag可独立保持true，消费仍按canceled优先门禁。
已核实concrete openScheme:naCallupReportExtraParams:item:errorHandler:
0x114139888先构bcmModelFromItem、manager task（0x114139974–0x1141399b0），
将task强捕获于completion+0x20，再调用UIApplication.openURL:options:
completionHandler:0x114139a88。completion0x114139bbc按传入Bool bit0，true
callupSuccess0x114139be8、false cancel0x114139bf0，之后另行
reportCallUpStatus。即使弱取业务receiver结果nil，task flag分支仍执行。
另openScheme:item:openWhitelist:errorHandler: callback0x114139f80和
openScheme:item:trackID:reportParams:errorHandler: callback0x11413f16c也按
传入Bool对捕获task分支（0x114139fac/0x114139fb4、0x11413f19c/
0x11413f1a4）。这证明OS completion接受会标记本地成功，不证明目标app已呈现、
停留结束或服务端广告回执成功；任务只在后续DidBecomeActive延迟消费路径报告。
限定direct selectorstub0x117232740的其他caller也已定位：card callback
0x11413653c按Bool标记/取消（0x114136578/0x114136580），button callback
0x114137188按Bool尾调，AppStore callback0x114137fd4同样按Bool
（0x114138000/0x114138008）；trackID变体0x11413cb04、0x11413e668另有同selector
调用。它们的上层forceCallupSuccess/业务completion producer仍需分别审计，不把
全部callupSuccess写成仅UIApplication原始Bool或扫描穷尽全部动态调用。
button installedSchema分支也已闭合：public wrapper0x114136d70先将输入
forceCallupSuccess写**共享BBAdClickManagerHelper**（classref0x11f7b6ff0→
class0x1201c0038，0x114136dfc），再调用inner0x114136e64。inner自身未读取
incoming w5；isButtonShowOpenWithUrl:installedSchemaUrl:通过才构task、调用
UIApplication.openURL completion0x114137188，按原Bool标记成功/取消；否则转普通
clickButtonWithUrl:item:successBlock:failBlock:（0x114137134）。trackID inner
0x11413c7dc也不读取incoming w7，其installed branch同样openURL
0x11413ca00→completion0x11413cb04。不能从参数名推定该OS completion被改true。
共享force实际reader在needCallbackAfterCallup helper0x11413a034：先清
helper.callupCancel；原Bool true直接needCallback=true。false且URL转换nil同样
返回needCallback=true（0x11413a0dc→0x11413a22c）；有效URL才检查第三方
判据，发旧BBAdReportUIEvent raw40/41及open-white alarm raw2/3，随后置共享
callupCancel=true（0x11413a18c），再读共享force（0x11413a1ac）：true返回
needCallback=false，false返回true（0x11413a1bc–0x11413a22c）。这不是任务flag。
上述openScheme completion把helper返回作needCallback，却仍把**原OS Bool**作
reportCallUpStatus（0x114139c2c–0x114139c44）；report helper0x11413a274按原Bool
选择NA_callup_suc/fail（0x11413a524–0x11413a530），无条件报告旧UIReport
（0x11413a5a8），只有errorHandler非nil且needCallback=true才调用业务callback
（0x11413a5ec–0x11413a604）。force改变回调门禁，未在此改任务成功标记或该
UI事件的原始status；共享属性在completion时读取而非任务捕获快照，其他点击
写入的交错/账号代际未运行验证。

BCMUIAdEvent使用另一concrete发送链，不能直接套旧UIReport缓存规则：其report
0x114168954在日志后调用super，superclass已按class metadata确认为BCMAdBaseEvent；
super.report0x114168414→BCMReport.shared.report:。dispatcher为concurrent queue
com.bilibili.bcm.report.dispatcher（0x11416f708–0x11416f714），异步block
0x11416f7e8要求BCMReportItem protocol与shouldReport。UI subclass.shouldReport
0x1141684dc只要求name非空或extendedFields[event] String非空；reportType raw1。
该type经BCMReport.ui.reportParams:context:info:（0x11416f988/0x11416f9a4），
lazy ui0x11416fe0c构造BCMUploadsReport(name="ui")、reportURL为同conversion/mobile/v2。
UI subclass.buildReportParams0x114168574先base params、name/url及model归因字段，
再非空显式adcb覆盖model.ad_cb、extendedFields最后覆盖（0x1141688d4/0x11416890c）；
最终helper0x11416bc00读取bbad_params，若为NSDictionary就最后addEntries合并，
再无条件移除bbad_params/bbad_report_urls/bbad_tap_rect/bbad_filter_salt
（0x11416bc14–0x11416bc94）。因此嵌套bbad_params还能覆盖event/adcb/show_time等
此前字段；callup方法的show_time覆盖extra只是该层先后，不能宣称最终body必保留
计算值。helper没有旧UIReport.installParameters的String/NSNumber白名单过滤。
UI base helper0x11416ad04设置is_sdk_v2="1"、当下epoch毫秒Int64十进制ts，
再取BCMInfoCenter的buvid/mid/idfa/build_id/network，以及BBAdDeviceInfo的vendor/
operator_type/model；缺失值退空String。随后合BBAdDeviceInfo.CAID dictionary，
再写dns_client_ip/initial_time/os_v，返回copy（0x11416aff4–0x11416b108）。
BCMInfoCenter.registerInfoSource0x11416bd1c强存source；模块runnable name
BCMSDKModuleModuleInitialize0x10209e4d8对应entry0x10209e4f4→0x1020a0498，
body构造BCMSDKModule.AdSource后通过BCMConfig.initWithInfoSource
（0x1020a052c–0x1020a054c）注册，并调用BCMReport.retryFailedEvents
（0x114166f5c/0x114166f88）。该retry异步转ui/feeAd/feeMMA各自retryFailures
（0x11416fd94–0x11416fdf8），不是旧BBAdSingleton启动selector。
AdSource constructor0x1020a0348把当时BFCBuvid.buvid复制到自身buvid String
（0x1020a03b0–0x1020a03d4）；buvid:0x10209e62c读取该保存值，不每次读BFCBuvid。
mobi_app:同样读constructor传入的配置String。mid:0x10209e6b0则经helper
0x1020a0760从注入_account读取mid、转Int64 decimal String
（0x1020a07dc–0x1020a0808）；_account的静态type reference确认为BFCAccountService
protocol。其DI key cache0x120276360相对type reference0x1196bf256确认为
BFCAccountService；root334-service库存0x120272628的index6/slot0x1202726a8
确含AccountModule._$GripperAccountInfoModule。注册0x104c6f164通过0x10513162c
（0x104c6f1ec）绑定provider factory0x104c6fbc8→0x104c6f0b8→0x104c6f040。
factory构造_$GripperAccountServiceProviderDependencyProvider，service witness
0x1204a6d10的getter槽+0x10→0x104c6eed0→0x104c6ee54；后者首次分配
AccountServiceImp（0x104c6ee70–0x104c6ee84），保存provider+0x10并复用。
AccountServiceImp.mid:0x104c6e620每次调用BFCAccount.currentUser
（0x104c6e658），存在user再取mid（0x104c6e674），nil返回0
（0x104c6e69c）。这里缓存的是service对象，未缓存user/mid；没有mid存入buvid
快照的分支。注册存在不证明模块运行顺序或运行时没有替换该binding。
InfoCenter.buvid/mid若source不响应对应带参数selector就返回空String；idfa/build/
client_version/ua则先取BBAdDeviceInfo默认值，再允许source同名selector覆盖。
这些是当前source类及getter的有界证据，模块真实执行次序和source后续替换尚未
动态验证，不能把buvid和mid都写成相同生命周期的“实时公共身份”。
params是在dispatcher消费event时生成，不是在BCMUIAdEvent.report调用前冻结，
mutable event引用直到该阶段的所有权/并发影响尚未证明。

BCMUploadsReport.reportParams:context:info:0x114174858要求非空params，copy三项后
排自身串行queue com.bilibili.bcm.report.uploads.ui。reportURL及completion setter
也排同queue（0x114174708/0x1141747e8）。消费0x1141749bc构造单元素uploads请求
→BCMReportSession.sharedSession.request:modifier:，modifier为BCMUploadsModifier。
_requestWithParamsArray0x114175010使用NSMutableURLRequest、BCMInfoCenter.ua/
User-Agent、application/json、POST、timeout15秒（0x114175118），body为uploads
JSON；返回copy request，不在这个builder直接resume。modifier
sessionRequestCustomWillSendRequest0x114174308 copy请求后按BCMMemex选择br优先/
否则gzip；压缩nil仍替换body，没回原JSON。无压缩保持原body。
BCMReportSession.request:modifier:0x1141724c4只接受符合modifier protocol的传入对象，
否则用默认SimpleModifier；预处理返回nil直接返回nil。非nil则NSURLSession.sharedSession
dataTask/resume→NSCondition无条件wait(now+request.timeout+1)，done与迟到结果门禁
同旧链的结构（0x114172674–0x11417270c/0x1141728e0–0x114172944），超时NSError
BCMReportNetworkErrorDomain/-1001，无task cancel。wait返回BOOL未使用，早到signal
仍可能等待期限；这里未执行线程调度或真实请求。
Session将data/response/error包装后交modifier响应加工
（0x114172728–0x114172754）；UploadsModifier0x1141740e8要求无transport error、
HTTP200–299、_BCMUploadsModel非nil/code String="0"才留下error=nil。其他情况
另建NSError：transport用BCMReportNetworkErrorDomain/原error.code，非2xx用
BCMReportServerErrorDomain/HTTPstatus，业务码/缺模型用BCMReportNonZeroErrorDomain/
model.code.integerValue（常量slots0x11cf85938/0x11cf85940/0x11cf85948），userinfo=nil；
模型nil的code路径仍为0。Uploads自身_validateSessionData0x11417521c只检查
sessionData非nil且error=nil，不能把它当第二次解析业务码。
首次成功会_retryMoreThanInterval:0；失败保存BCMReportRecord，随后调用自己的
completion（0x114174adc/0x114174d28/0x114174d64）。缓存名report.uploads.ui与
旧report.ui不同。首次失败新建record，filename为原builder请求的URL.absoluteString、
未压缩HTTPBody的MD5及发送前epoch毫秒，用"|"分隔（0x114174b04–0x114174bdc）；
新record.f_index再加1，first_report_ts与last_report_ts都取该发送前时间
（0x114174c1c–0x114174c40）。保存params时先放is_reupload="1"再合原params，
原值可覆盖标记；reportURL/context/adInfo一并保留。这里没有账号分区或切换账号
时重建params的分支，重传沿用保存的归因及身份值。

BCM retryFailures0x114174f8c排自身queue，block0x114175000传3600000ms；
同样是原记录年龄门禁，不是每小时timer。_retryMoreThanInterval:0x114175260
先删除缺失record或空reportURL的key；URL非空但与当前sender.reportURL不相等时
跳过并保留（0x1141753a0–0x114175408）。匹配URL后，f_index>3或
now_ms−first_report_ts≥86400001才删除（0x114175414–0x114175454），与旧UIReport
的>4及item.timestamp来源不同。可选abandon回调reason raw0用于空URL等无效记录、
raw1用于次数超限、raw2用于过期；缺失record不传nil对象给该回调。
interval≥1时还要求now_ms−first_report_ts>interval，没用last_report_ts
（0x114175564–0x114175584）。获准后先removeRecordForKey，再把保存的params
加入最多10条的batch（nil params退空dictionary）。批量失败才对各record的
f_index+1、last_report_ts=该batch发送前now_ms并saveRecord；成功不重写缓存
（0x114175750–0x114175794）。两种结果都逐record调用completion，传success、
本轮递增前的f_index、保存的params/context/adInfo及sessionData.error
（0x1141757a4–0x114175840），不能把completion中的retry数当递增后值。

BCM也存在上述尾批缺口：flush仅在获准分支检查count==10或当前key为最后项
（0x1141755f4–0x114175614），跳过末尾key会经0x114175538–0x114175560直接退出
到0x114175a18，未补发已删除且不足10条的待发送batch。URL不匹配也能走该跳过
路径；这是静态控制流结论，尚未运行复现。AdAlarm的KNeuron/Mikoto出口及
BCM source账号DI见本节独立链；实际模块调度/事件触发仍需区分。

BCM UI completion0x11416fe7c在请求结果后调用BBAdInterceptor.syncWithBlock
（0x11416ff54）。此concrete helper0x104838c70先检查BBAdConfig.isInspectorEnabled，
false不执行传入block；true取KntrAdInspectorManager.shared并同步调用block
（0x104838cec–0x104838d18）。观察block0x1141703d0由保存params重建单条uploads
JSON字符串，addUIReportJobRequestBody/adId=adInfo.ad_cb/isRetry=(旧f_index>0)，
再按success调用job.successData:nil或job.failReason:错误码格式串
（0x1141704a4/0x1141704f0/0x114170560）。它不是发送前拦截器，不修改已经发送的
请求，也不是批量重传实际HTTPBody的原始捕获；一批多条时这里仍逐record造单条body。

success=false另发KntrAdAlarm.reportUiFailed（0x114170134），commonParams来自
adInfo.makeKntrAlaramParams，nil退empty。extra有is_retry=(旧f_index==0?"0":"1")、
fail_count=旧f_index十进制、is_bcm_report="1"、desc/code来自加工后的NSError、
ad_cb和保存params[event]，不是新解析response payload。旧f_index==0还会调用
BBAdKtTracker.trackWithEvent raw9（0x1141701a0–0x11417031c），success时desc="success"/
code="0"，failure用错误说明/码；重传不进入此raw9分支。这两种观察事件与原POST
回执是后续动作，各自最终sender/采样门禁未闭合，不能宣称一定产生另一请求。

计费与MMA是另外两类BCM传输：BCMFeeAdEvent.reportType=0x100
（0x114168f64），shouldReport0x114168f6c要求model.bcm_is_ad_loc且name或
extendedFields[event]非空。其params按common helper0x11416b10c→model归因
helper0x11416b798→name→extendedFields→最终bbad_params合并，交dispatcher
bit8分支feeAd.reportParams（0x11416fb04–0x11416fb20）。lazy feeAd0x1141705bc
构造BCMUploadsReport(name="fee.ad")，POST
https://cm.bilibili.com/cm/api/fees/wise（0x114170604/0x114170608），沿用同Uploads
JSON/压缩/session/业务码/批量cache机制，但cache名为report.uploads.fee.ad。
它不是UI conversion地址；业务触发者、common完整字段、Once去重仍待闭合。

BCMFeeMMAEvent.reportType=0x200（0x114169800），shouldReport0x114169808要求
bcm_is_ad_loc且stringURLs.count>0，未验证每条URL可发送。buildReportURLs
0x114169884按原stringURLs顺序逐项用bcm_MMAURLWithInfo:extendedFields:替换/
加工，只保留返回String.length>0；模板替换字段与编码细节尚待追踪。
dispatcher bit9分支0x11416fce4–0x11416fd00交feeMMA.reportURLs:context:info:；
lazy feeMMA0x114170f60构造BCMURLReport(name="fee.mma")，不是Uploads sender。
该对象queue com.bilibili.bcm.report.url.fee.mma、cache report.url.fee.mma，
modifier为BCMReportSessionSimpleModifier（0x114172db8–0x114172e50）。

URLReport.reportURLs0x114173044 copy URL数组/context/info，排自身串行queue，
block0x1141731a8逐URL新建currentTask(index=0)并分别同步走同BCMReportSession。
_requestWithReportURL0x114173764对NSString trim首尾空白/换行→NSURL.URLWithString，
非nil才构造GET、BCMInfoCenter.ua、timeout15秒，无uploads body
（0x1141737a4–0x11417389c）。这里未见host/scheme allowlist或业务签名；NSURLSession
实际允许的URL与系统拒绝仍不能从该局部body替代验证。URL解析nil会先存
BCMReportRequestErrorDomain/-3001；随后_validateSessionData:nil又以同domain/-1
覆盖currentTask.error（0x1141738ec/0x1141739c4）。SimpleModifier0x1141729ec只以
transport无error及HTTP200–299判成功，不解析JSON/code；失败分别归Network/Server
domain。URLReport._validateSessionData0x11417392c只看sessionData/error，并把error
写currentTask。故MMA的2xx成功不能套UI/fee.ad的业务code="0"条件。

首次URL失败在请求结果之后取now_ms，保存record.f_index+1、first_report_ts/
last_report_ts=此时now、原加工后URL/context/adInfo（0x11417343c–0x1141735fc）；
filename由builder URL/HTTPBody MD5/now用"|"拼接，缺失项为空String。它不保存
参数dictionary，也不在重传时重新做MMA模板替换。每次结果随后_complete调用
completion(currentTask)，没有统一main切换（0x114173614/0x114173a00）。
首次URL成功会increase sentinel并排同queue **10秒**后_retryMoreThanInterval:0，
closure仅当sentinel仍等于捕获值才执行（0x1141733a4–0x114173430、
0x11417369c–0x1141736d0），一串成功中的较旧排队重传会失效；不能写成成功后
立即重传。公开retryFailures0x1141736e0仍排interval3600000ms。

URL retry0x114173a84删除缺失/空URL、f_index>3或首次失败年龄≥86400001ms；
interval≥1则要求now−first_report_ts>interval。符合条件先从cache删除，再逐条
以保存URL发GET，新currentTask.index取旧f_index，失败才f_index+1并保存本次
失败后的last_report_ts；两种结果都_complete（0x114173d08–0x114173f38）。
这里没有Uploads的batch或sender.reportURL匹配，不能复制其尾批漏flush结论。
删除后发送/重写前的进程退出仍可能丢失项；MMA completion/abandon告警与真实
业务URL producer继续追踪，未运行第三方URL请求。

MMA模板helper0x11416da88先copy原String；空String直接原样返回。非空时
BCMAdInfo.modelWithItem取model，再构造宏dictionary：__TS__取调用时epoch ms
Int64 decimal（0x11416db44–0x11416db9c），__OS__取BBAdDeviceInfo.os；
__BUVID__/__MID__取BCMInfoCenter可选String，__IDFA__取InfoCenter.idfa，
空值采用静态占位，__IDFAMD5__取该String的MD5。占位IDFA时另检查
model.macro_replace_priority：raw1对非http前缀或命中origin-macro domain list
删除IDFA/MD5两宏，使原URL占位符保留（0x11416de60–0x11416de9c）；raw2对非http
前缀或命中empty-list domain list将两宏置空（0x11416ddfc–0x11416de48）；其他
情形保留静态占位及其MD5。这里仅hasPrefix("http")，不是严格scheme验证，
BCMMemex列表实际配置内容尚未读取。
__UA__单独经bfc_urlEncodedString（0x11416dec4），__REQUESTID__/__IP__取
model.bcm_request_id/bcm_client_ip，__CREATIVEID__/__SHOPID__/__UPMID__仅
正整数decimal，__TRACKID__取track_id。六个motion宏__WIDTH__/__HEIGHT__/
__DOWN_X__/__DOWN_Y__/__UP_X__/__UP_Y__先有静态缺省；非nil motionValue经
0x11416cb2c转换dictionary后覆盖（0x11416e134/0x11416e154）。tapRect入口
0x11416d984仅非empty CGRect生成motionValue，Double→Int64截断，宽高及
down/up两组坐标都取同一rect origin（0x11416d9f0–0x11416da20）。
最后extendedFields整dictionary再merge，能够覆盖上述任意宏
（0x11416e160–0x11416e170）；bbad_formatToStringKeyValue0x1141782c0保留
NSString或能respondToSelector(stringValue)的key/value，无法转换者省略。
enumeration block0x11416e2b0只处理同时以"__"开头/结尾的key，对当前结果串
stringByReplacingOccurrencesOfString全量替换（0x11416e2e0–0x11416e334）。
不是统一URL query编码，除UA之外不在此helper额外encode；dictionary枚举顺序
不保证，若扩展value带其他宏，嵌套替换结果可能受顺序影响。未知宏保留，helper
没有hostallowlist、最终URL有效性或签名检验，后续GET builder才URLWithString。
因此MMA缓存保存的是已替换URL，重试不重新读此宏dictionary/当前身份/时间。

BCM Once admission与网络成功独立。UI Once.shouldReport0x114168b74、FeeAd
Once.shouldReport0x1141692e0先过super shouldReport，然后取eventHash（非nil即
采用，空String不fallback）或defaultHash；extendedHash非nil时追加"|"+值，
再追加"|"+event.name，nil片段经0x114177b78转空String。UI defaultHash
0x114168dbc为MD5(model.ad_cb+"|"+event.url)，FeeAd defaultHash0x114169528
为MD5(model.request_id+"|"+source_id decimal+"|"+creative_id decimal)。查询
共享BCMEventRecord.contain，未命中先record再返回true
（0x114168d44–0x114168d80、0x1141694b0–0x1141694ec）；已命中返回false。
去重key未直接加入账号/时间/类型前缀，业务eventHash可能另外包含这些值，尚未
统一审计其producer。不把Once理解为只在成功后登记或失败后自动恢复资格。

MMA Once在buildReportURLs0x11416a1a8逐条检查**原stringURLs**，同样取
eventHash或defaultHash（0x11416a53c，request_id/source_id/creative_id三项MD5），
可选extendedHash后拼"|"+当前原URL，而非event.name。未命中项先加入输出再
record（0x11416a400–0x11416a42c），输出覆盖self.stringURLs
（0x11416a49c），之后才super.buildReportURLs0x11416a4c0做宏替换。故宏替换
或后续URL解析失败前已占去重资格，同一串里后续重复原URL正常会被前项挡住。
其buildReportParams0x11416a138直接返回super.extendedParamsFields或空dictionary，
不能据method名推断它走Uploads POST。

BCMEventRecord.shared0x11416ab24用进程once创建，init0x11416ab80创建mutable
set及semaphore(1)。contain0x11416ac04与record0x11416ac74分别wait forever、
查containsObject/加addObject、signal；nil参数分别false/no-op。已检查这些body
没有磁盘持久化、时间expiry、移除或账号监听。但contain与record之间释放了锁，
caller没有跨两步锁，不能宣称并发原子check-and-record；实际dispatcher外部串行
约束与进程生命周期外reset仍需另证。这个内存Once记录与失败retry磁盘cache分开。

UI completion的BBAdKtTracker raw9进一步闭合为KntrAdTrackEvent.uiReport：
trackWithEvent ObjC桥0x104912d20→通用bridge0x104913020→callback
0x104913794，event转换0x104913724查十项selector表0x11b2eb7a0，raw9对应
slot0x11f798c00/uiReport。callback把BBAdTrackParams转
KntrAdTrackCommonParams（0x1049134ec，initWithRequestId:resourceId:srcId:
creativeId:cardType:extra:），nil参数先创建空BBAdTrackParams；extraMap nil取空
dictionary，再KntrAdTrack.shared.trackEvent:commonParams:extraMap:
（0x1049138b0）。此已检查路径没有读cm.ad_track_disable。另独立
adTrackEnabled getter0x1049133fc按配置cm.ad_track_disable整数==0返回true；
wxCallUp专用helper0x1049138f4自行读取同配置，非零直接返回
（0x1049139dc），但它不是raw9通用callback。不能因getter/其他helper存在，就
宣称UI completion也已过该门禁。KntrAdTrack内部另有如下tt_track_enable和采样
门禁，实际Mikoto service binding如下，网络行为仍按其独立链判断。
Kotlin导出表也已定位，避免把SelectorsHolder dummy方法当业务实现：
type adapter0x120595930关联TypeInfo0x11b748360
（kntr.app.ad.domain.track/AdTrack），ObjC名KntrAdTrack；唯一instance method
entry0x11ccc7720取trackEvent:commonParams:extraMap:→export shim0x10bcb3b88，
转换参数后0x10bcb3cf0调用实际AdTrack body0x107ab8924。body已追到KNeuron
singleton0x120c5e448→wrapper0x105d60bc8，以接口hash raw0x13780、slot+0x38
间接dispatch（0x107ab9664）。wrapper初始化0x105d60a10分配TypeInfo
0x11b4fa4b0（kntr.base.neuron/KNeuron），通过injected provider接口hash0x901
取service并保存+8（0x105d60b74/0x105d60b7c）；实际provider implementation和
该slot具体sender现已由如下DI闭合；最终发送仍需按Mikoto/Neuron独立链判断，
不据KNeuron名称认定复用普通BFCNeuron click出口。
KNeuron provider mPlatformNeuron$2.invoke0x105d61454解析KClass
0x11c643b90（TypeInfo0x11b4fa210，NeuronEntryPoint），interface hash0x18e
slot0实际为0x10b928fcc；经root getter0x10b91f73c取component+0x98，调用
provider hash0x584→producer hash0x587/method2。该field由0x10b931068存储，
SwitchingProvider raw id21（0x10b93105c），group0 table0x118652e72[index21]
raw0x3bf→0x10b93d09c→0x10aab14ec。singleton raw producer0x11cb3e168的
getter0x10aab159c→initializer0x10aab1a68，返回cache0x120c6cbf8，具体type
0x11bb40710为kntr.base.neuron.epoch.impl/mPlatformNeuron$1。
初始化经epoch NeuronModule classref0x11f7bf170创建module，neuron getter
0x10aab1c50结果存+0x10、mikoto getter0x10aab1d54结果存+0x18；原生neuron
getter0x100205b94的keypath0x118269168/0x118269190目标确为BFCNeuronService。
但AdTrack调用hash0x13780/+0x38实际是table0x11c34b2d0[7]→0x10aab5388，
该方法用**+0x18 Mikoto**。调用Function0取boxed Bool
（0x10aab54a8/0x10aab54b0），event String不等infra.metrics且Bool false时
返回（0x10aab5528）；true时trackTech:extendedFields:policy:rate:
（0x10aab58d4），rate100，输入Bool非零policy1、零policy2。
infra.metrics路径从fields[command]构URL，成功trackNetWithURL:extendedFields:
（0x10aab59dc），另加kmikoto::simpler按Function0 Bool为"1"/"0"；缺command/
URL转换失败走trackTech policy1/rate100（0x10aab5c38）。此是边界分流，不是
本调查发送URL。相对普通click接口slot1→0x10aab5f30才读+0x10，创建clickEvent
0x10aab6098、设置extendedFields后trackEvent:trackPolicy:0x10aab6340。
epoch mikoto getter0x100205c54的keypath0x1182691b8目标
0x1196bee2a为BFCMikotoService.Type。实际MikotoProviderModule.register
0x104958138用key0x120274f78，factory0x1049582a0→0x104958100→provider
constructor0x104958088；witness0x12048db40/+0x10→0x104958060→lazy getter
0x104958014，未缓存时builder0x104958254取ObjC classref0x11f7b6e08
**BFCMikoto**，Swift ObjC metadata缓存0x12048db58，再写provider+0x10。
这供应类/元类型，符合epoch initializer的metaclass+conformsToProtocol
BFCMikotoService检验（0x10aab1df4–0x10aab1e28），不是任意同名service。
334项root false/raw0 service inventory中index195/String slot0x120273278
确为MikotoModule._$GripperMikotoProviderModule，补齐注册库存关系。
依赖注册/解析执行仍为运行条件。上述ad.track.*非infra.metrics事件在配置和随机
门禁接受后转BFCMikoto.trackTech，适用前述logId002312/native trackEvent采样
与异步Neuron入队边界；不能把函数返回、本地observer通知当HTTP成功。

AdTrack基础map已定位：request_id（0x107ab8af4）、resource_id decimal
（0x107ab8b84）、src_id（0x107ab8bec）、creative_id decimal
（0x107ab8c7c）、card_type（0x107ab8ce4），nullable String取空。
cm.ff.tt_track_param_with_large_param对应lazy global0x120c65468、getter
0x107aba324；true才加入common.extra（0x107ab8d58），false且incoming extraMap
含item则复制map并移除item（0x107ab8de4–0x107ab8e24），不修改原incoming map。
filtered extraMap先复制为输出，再遍历common map覆盖同key
（0x107ab8f64、0x107ab9328），不能按ObjC extendedFields优先规则类推此合并。
另cm.ff.tt_track_enable lazy0x120c65460在发送前要求Bool==1
（0x107ab95b8/0x107ab95bc），不满足绕过KNeuron；与前述cm.ad_track_disable
独立。initializer0x107aba204创建五个lazy：track_toggle$2、
param_with_large_param$2、data_sampler$2、action_sampler$2、report_sampler$2。
后面三项读取cm.config.tt_track_data_rate、cm.config.tt_track_action_rate、
cm.config.tt_track_report_rate（0x107abaafc/0x107abab48/0x107abab94）；最终
采样Function0由TypeInfo0x11b748400、+8捕获event
（0x107ab9614/0x107ab9650），funcTable0x11c037770/+0x10实际invoke
0x107ab9880。读取kotlin.random/Random.Default global0x120c5a930
（initializer0x10528ff94、TypeInfo0x11b37cad0），对+8 delegate
TypeInfo0x11b36f940（kotlin.random/NativeRandom）的virtual+0xf0
0x105290198传from0/until100（0x107ab9928/0x107ab992c）；实现取range=until−from，
100走UInt随机右移1、remainder和拒绝重采样（0x10529028c–0x1052902a0），
until排他，即0..99。用signed
random<event.+0x14 Int32决定Bool（0x107ab9934–0x107ab9940）。没有在该body
按用户hash或固定种子稳定分桶。AdTrack传入sender Bool=0
（0x107ab9658），非infra.metrics被lambda拒绝就不trackTech；接受才raw policy2/
native rate100。metrics则把该Bool写simpler字符串而不按false直接丢弃。
捕获event阈值producer已闭合为enum initializer0x107ab9978：创建十个
AdTrackEvent TypeInfo0x11b7484a0并存array global0x120c65450；ordinal存+0x10、
rate存+0x14、实际event String存+0x18。下表是enum ordinal，并非未经证明的其他
bridge raw值；上述ObjC转换按selector选择同名enum。

| Ordinal / event | 实际event String | rate来源 / 写入site |
| --- | --- | --- |
| 0 appstoreLoadStatus | ad.track.appstore-load-status | action_sampler，0x107ab9d48→0x107ab9d90 |
| 1 adData | ad.track.ad-data | data_sampler，0x107ab9dec→0x107ab9e88 |
| 2 click | ad.track.click | action_sampler，0x107ab9e94→0x107ab9ed8 |
| 3 wxCallUp | ad.track.wxprogram-callup | action_sampler，0x107ab9ee4→0x107ab9f28 |
| 4 appCallUp | ad.track.app-callup | action_sampler，0x107ab9f34→0x107ab9f78 |
| 5 appDownload | ad.track.app-download | action_sampler，0x107ab9f84→0x107ab9fc8 |
| 6 webViewLoad | ad.track.webview-load | action_sampler，0x107ab9fd4→0x107aba018 |
| 7 mmaReport | ad.track.report-mma | report_sampler，0x107aba024→0x107aba068 |
| 8 feeReport | ad.track.report-fee | report_sampler，0x107aba074→0x107aba0bc |
| 9 uiReport | ad.track.report-ui | report_sampler，0x107aba0c8→0x107aba10c |

action getter0x107aba438读lazy0x120c65478、report getter0x107aba54c读
0x120c65480；data读0x120c65470。三个配置String经处理helper0x10529f5ac，
再按十进制Int解析，
nil/解析失败走调用fallback（0x107aba660–0x107aba7e4），此body未做0..100
clamp。三个caller的静态fallback分别data100（0x107abab20）、action100
（0x107abab6c）、report5（0x107ababb8），不是读取本机/远端的实际配置值。
enum initializer按once flag0x120c79e08只写这些rate快照；本次静态检查
没有每次track重读远程配置或对现有enum改rate路径。random比较仍每次调用，
不能把lazy rate缓存写成一次随机决定，也不因native rate100断言全量上传。

KntrAdAlarm不是另一条已证直连URL。导出表0x11ccc4610的fireEvent桥
0x10bc93474转换参数后调用AdAlarm body0x107ab486c
（0x10bc935dc），TypeInfo0x11b747a40。common接口hash0x19b00五个getter
（0x107ab49bc/0x107ab4a2c/0x107ab4a94/0x107ab4afc/0x107ab4b68）生成
request_id/creative_id/src_id/card_type/extra；nullable值先替为空String。
0x107ab4bbc→0x105283fd4创建新map，先复制common（0x10528408c），后合
extraMap（0x105284098→0x1052463f4），故extras覆盖同key，与AdTrack次序不同。
之后first pass读取Map.Entry slot+0x8的**value**，nil则跳过
（0x107ab4f44/0x107ab4f4c）；非nil才取key/value放入输出。实际
HashMap.EntryRef TypeInfo0x11b372240的hash0x980 methods0x11bd24198
为0x105249a94（keys）/0x105249b50（values），已核实槽位而非猜测key过滤。
put旧entry允许nil（0x1052463bc），因此extra nil能覆盖common后被过滤移除，
不会回退common。second pass的非nil断言0x107ab5210→0x107ab5450
是异常分支，不能将正常过滤过程写成常规业务崩溃。

initializer0x107ab64b4创建alarm_toggle及data/click/status/report四个lazy。
总开关cm.ff.tt_alarm_enable（invoke0x107ab6d38，default Bool1）缓存于
0x120c65420；fire要求boxed Bool==1（0x107ab4d20–0x107ab4d34）才调用sender，
未证每次重新查询配置。四rate配置分别cm.config.tt_data_rate（0x107ab6e00，
fallback5）、cm.config.tt_click_rate（0x107ab6e4c，100）、
cm.config.tt_status_rate（0x107ab6e98，80）、cm.config.tt_report_rate
（0x107ab6ee4，5）；helper0x107ab6a2c按radix10解析，缺失/解析失败用fallback，
未见clamp。这些是静态默认值，不是本机或服务端实际配置。
AdAlarmEvent initializer0x107ab55b8创建21项；ordinal+0x10、rate+0x14、
独立reportName+0x18，fire取后者（0x107ab4d84）。event name/rate赋值如下：

| rate getter | reportName（前缀ad.ops.） | name写入site |
| --- | --- | --- |
| data，0x107ab65dc | data.no-adinfo；data.unsupport-card-type；data.material-invalid | 0x107ab5d18；0x107ab5d68；0x107ab5db8 |
| click，0x107ab66f0 | appstore.load-status；click.no-react；click.wxprogram-callup-failed；click.openwhitelist-failed；click.downloadwhitelist-failed；webview.load-failed；iaa.load-failed；iaa.show-failed | 0x107ab5cc8；0x107ab5e08；0x107ab5e58；0x107ab5ea8；0x107ab5ef8；0x107ab5f48；0x107ab6178；0x107ab61c8 |
| report，0x107ab6918 | report.mma-failed；report.fee-failed；report.ui-failed；report.fee-abandon；report.ui-abandon；report.mma-abandon | 0x107ab5f98；0x107ab5fe8；0x107ab6038；0x107ab6088；0x107ab60d8；0x107ab6128 |
| status，0x107ab6804 | iaa.load-status；iaa.show-status；iaa.playable-load-status；iaa.plugin-request-status | 0x107ab6218；0x107ab6268；0x107ab62bc；0x107ab6308 |

其中appstore.load-status明确走click，不能按后缀猜status。fire创建
AdAlarm$fire$$inlined$runCatching$1（TypeInfo0x11b747ae0）并捕获event+0x8
（0x107ab5274）；KNeuron wrapper0x105d60bc8调用site0x107ab5284传
Bool1/name/finalMap/采样Function0。lambda invoke0x107ab54c0每次取Random
整数0..99（0x107ab5568–0x107ab5570），signed比较random<event.rate
（0x107ab5578/0x107ab557c），返回boxed Bool。它是采样判据，不是response
callback；下游已证复用epoch mPlatformNeuron$1→BFCMikoto技术/metrics路径。
本体没有direct completion、递归send或timer retry；此范围不排除下游持久化/
重试，也不能由fire返回或采样接受推断实际HTTP成功。


Monitor producer的有限审计需保留receiver边界：class0x1201c2b30/RO0x11f090bd8
是BCMMonitorUIAdEvent，class0x1201c2b80/RO0x11f090c88是
BCMMonitorUITrackEvent。BCMAdBaseEvent.eventWithInfo0x114168338确会alloc输入
class receiver（0x114168358）；reportName:info:url:params:0x114167438保留
incoming class并交该builder，理论可构造subclass，但尚未找到实际Monitor receiver。
常见reportUIEvent两variant0x114167520/0x114167624则硬编码BCMUIAdEvent
classref0x11f7b9cb8（0x114167548/0x11416764c），不能按继承selector推Monitor。
BBMallAdHelper.reportMonitor0x103a338a8→0x103a33fbc实际是宏替换URL→
URLRequest（0x103a34310）→NSURLSession.shared/dataTask/resume
（0x103a34374/0x103a343e4/0x103a34418），也不证明BCM Monitor endpoint。
有限直接call/类名扫描未闭合Monitor业务实例/事件名producer；不排除generic
objc_msgSend、动态class/config或外部调用，也不据此称死代码。


HD2首页广告strict producer另有实际链：BBHD2PhonePegasusAdSingleCell
strict0x10df15718只把rect/extra转adView（0x10df1579c）。lazy factory raw3
（0x10df14e88）→BBAdPGView mapper0x113ba0cb8→BBAdPGHDOddView
（0x113ba0df4–0x113ba0e10）；strict0x113bcc378转其mapped cell
（0x113bcc3fc），已核001/003/Live063等family继承BBAdPGHDOddCellView。
base BBAdPGView.strict0x113ba0fb4本身RET，不能统一推广。
HDOddCell.strict0x113bc814c先BBAdReporter.innerReportType raw3/event15
（0x113bc829c），随后visibleMark，再intersection双轴50%→viewDidStopWithVisible
（0x113bc8300–0x113bc833c）；后者阈值不是前面wrapper的发送门禁。
Reporter0x113c4a2e8→0x113c4aa38按type bit0/bit1分别Own/MMA，所以raw3是
同时两支，非一种strict enum。Own0x113c4ace4先丢nil/空params；event15另调用
_containerTypeWithRectParam0x113c4a928：任一rect空或intersection空返回-1；
双Infinite返回raw1；其他交集高/宽分别>=0.5*第一rect高/宽才raw0
（0x113c4aa18–0x113c4aa30）。物理HD packing0x113bc81f0–0x113bc81fc已证
第一rect为VIEW，故Own真正门禁也为双轴>=50% VIEW，而非面积50%。
-1丢弃（0x113c4ae64–0x113c4ae68）；non15 events不走此几何门禁。
通过event15门禁后**立即reportType1/event0**（0x113c4afe0），有container和
syncQueue时额外创建operation入队，延一秒再event15
（0x113c4af40–0x113c4af9c→0x113c4b068→0x113c4b04c）。这两个调用不能
误写成有队列只有延迟/无队列才立即；所有通过者都走立即event0。
Manager0x113c4b5dc创建两serial queue，raw0 common、raw1 noCancel
（0x113c4b6b8）；operation init0x113c4bb3c复制执行block，guard初值及
isDisposed=false。execute0x113c4bbc8先置disposed=true，然后仅block非nil且
 guard.value==0才执行（0x113c4bbfc–0x113c4bc38），未重查可见矩形、未以旧
isDisposed挡重复execute。cancel0x113c4bc50递增guard
（0x114340d20→OSAtomicIncrement32），只能压制未来event15，撤不回event0。
addOp0x113c4b7dc同步到自身queue，先移已disposed，再containsObject新operation
（0x113c4b8f4–0x113c4b95c）；不是creativeID/payload去重，每次Own调用新建对象。
标准cancelStrictShowEvent0x113c49ff4先通知再cancel type0（0x113c4a048）；
WithType0x113c4a4dc对-1/raw1直接返回，其余container.cancelAllOp
（0x113c4a540）同步枚举cancel并清数组（0x113c4ba88/0x113c4bac4）。
MMA独立body0x113c4b070也已核对：params非空、raw15调用同rect gate
0x113c4a928，通过后同container/一秒Operation/取消guard；立即
reportType2/event0（0x113c4b40c），延迟event15（0x113c4b4e8），
缺container/queue只立即event0，非15直接原event（0x113c4b448）。
payload却不同：立即event0用copy base并补validatedUrlsWithOriUrls结果的
meta x23（0x113c4b110/0x113c4b154/0x113c4b16c）；延迟closure
0x113c4b4ac捕获原baseParams x19（0x113c4b328–0x113c4b32c），没有继承
这份URLs补充。Own/MMA各建freshOperation；Operation队列没有creative-ID
dedup证明，但下游另有item filter：Own._reportWithItem0x114336164要求
needReport及context.bbad_is_ad_loc非零，needFilter时取filterHash查实例+10
集合，已含丢弃，未含在发送前加入（0x114336224）。event0/15的Own/MMA
item表均设置needReport/needFilter=1；hash组成和清理范围另追，不能由队列层
结论声称端到端无去重或恰好一次。Own.filterHash0x114335ddc为MD5 of
无分隔concat五对象：request_id(nil空)、NSNumberLongLong src_id/creative_id、
NSNumberInt EVENT、filter_salt(nil空)（0x114335f5c/0x114335f6c）。
MMA.filterHash0x114331b30第四项却是raw reportURL，不含EVENT
（0x114331c1c–0x114331ca0）；因此Own event0/15不同，而MMA两URL及其余字段
相同可跨event命中。OwnReport+10/MMAReport+18各shared初始化SafeArray，
contains/add在API排队前，所核失败callback没有undo；清理生命周期仍待证。
context从params取bbad_filter_salt存内部+b0后从最终params移除
（0x114329ae8–0x114329b2c），没有读取实际盐值。MMA URLs precedence为
显式reportUrls→context.bbad_report_urls非nil（空数组也屏蔽fallback）→extra中
event0 show_urls/event15 show_1s_urls；保持数组顺序，仅非空String生成item。
该取消现已配对HD2 MainV2物理生命周期：handleAdShowEventWithMainV2VC
0x10dfa2a74的RAC绑定viewDidDisappear→0x10dfa2ff8→cancel
（0x10dfa3000），scrollViewDidScroll→0x10dfa3004→cancel
（0x10dfa300c），shouldScrollToTop callback0x10dfa3010仅tuple.first为
UIScrollView且scrollsToTop true才cancel（0x10dfa30a8）。重新start来自
viewDidAppear、endDragging且second Bool false、endDecelerating及didScrollToTop
（0x10dfa2e8c/0x10dfa2f34/0x10dfa2f90/0x10dfa2fdc）。startReport
0x10dfa30c8要求VC.view.window存在，collection.bounds转换到Topmost坐标后
与其bounds相交，交集WIDTH>=10（0x10dfa3200–0x10dfa3208）才遍历visibleCells。
广告卡ad_info.is_ad_loc非零转AdSingleCell strict（0x10dfa340c），其余
reportType1/event15/ad_info（0x10dfa3454）。VIEW为cell.frame→collection→
Topmost，LIST为collection.bounds同坐标；这是HD2 MainV2，不推广PhoneSwift。
同HDcell click0x10df154a4先取report_args.state，nil退report_click_position，
再HomeData.reportCardClick（0x10df155a8）后optional internaljumpdelegate
（0x10df15624）；incoming jumpBool在该body未保存。adClickEventReport
0x10df157c8 RET。exposedIn:item:0x10df15dd0用CURRENT self.model交
HomeData.reportRealCardShow（0x10df15e1c），不是strict event15；字段见上述
HD通道。_neuronReportParams0x10df15e3c给sub_goto=ad_info.report_card_type
decimal、sub_param=creative_id decimal；nature_ad恰1才加ad_image_md5=
creative_content.image_md5（nil空，0x10df15fc0–0x10df1606c）。这份extra覆盖
Neuron base；旧001365没有合入extra的步骤。没有读取/输出实际广告ID或hash值。

BBAdModule.onModuleInitialize0x10ea736b4还有独立启动producer：main.async
block0x10ea738e8取BBAdDeviceInfo.userApps（0x10ea73914），makeAdInfo后创建
**BCMUIAdEvent**，name=realtime_user_apps，extendedFields仅user_apps（nil取空），
report0x10ea739bc。同初始化安排main+6秒block0x10ea73a08
（0x10ea73754–0x10ea73774），同样创建BCMUIAdEvent，而非MonitorUIAdEvent；
name=cm_ui_report_monitor，extendedFields仅mobi_app取BFCBuildConfig.mobiApp，
report0x10ea73af8。随后另发BFCNeuronExposureEvent
ad.neuron-report.monitor.0.show.trackInstantly（0x10ea73b0c/0x10ea73b1c）。
这是UI Uploads与Neuron的两个调用，不据监控命名合并endpoint。实际启动任务调度
先后与成功发送未运行验证，userApps实际内容未读取。
初始化也向BCMAdExtra装SimpleModifier（0x10ea73714/0x10ea73730），handler
0x10ea7384c mutableCopy输入params，读取BBAdSingleton.postbackInfo.storyShownIds，
以story_shown_ids覆盖输入同key（nil取空，0x10ea738ac），再copy返回；
modifier.valueCustomWillEncryptParams0x11416e7b0有handler时采用该返回，否则
原params。这是AdExtra加密前扩展producer，不是MMA宏模板或上述UI event扩展。

fee.ad completion0x11417063c对每次结果排Inspector sync block
0x114170b20，创建单条uploads JSON job addFeeReportJobRequestBody:adId:isRetry:
（0x114170bf4），以**旧f_index>0**为retry，成功successData:nil、失败failReason，
仍受BBAdInterceptor.isInspectorEnabled门禁。失败每次另KntrAdAlarm.reportFeeFailed，
五extras is_retry/fail_count/is_bcm_report/desc/code（0x114170898），common取
adInfo.makeKntrAlaramParams或Empty。只有旧f_index=0才BBAdKtTracker raw8
（0x1141708f4/0x114170a60），对应selector表feeReport；五extras为
is_bcm_report/desc/code/ad_cb/event，
成功desc/code取success/0，失败取NSError，事件名取reportParams[event]。
abandon0x114170d0c转KntrAdAlarm.reportFeeAbandon，四extras fail_count/
is_bcm_report/reason/event，reason通过abandonReasonStringFromReason，未证明
上述Kotlin告警实际发送endpoint。

fee.mma completion0x114170fd0先取currentTask.error/URL/info/index，Inspector
block0x114171b04创建addMMAReportJobUrl:adId:isRetry:（0x114171b58），index>0为
retry、结果处理同上；是发送后的job记录，不拦截GET。index=0才先发
BBAdKtTracker raw7/mmaReport（0x1141710f4/0x114171800），五extras
is_bcm_report/desc/code/ad_cb/url，success或error取值。随后所有index的失败均
KntrAdAlarm.reportMmaFailed，七extras url/desc/code/is_retry/ad_cb/fail_count/
is_bcm_report（0x114171130–0x1141712e0）。失败分类若
BCMReportRequestErrorDomain且code=-3001，发BCMUIAdEvent mma_url_error，url取
currentTask.URL（0x114171394–0x1141713d8）；否则发mma_submit_failed，extended
先有code decimal（0x1141714b0–0x114171558）。成功所有index发BCMUIAdEvent
mma_submit_success（0x114171890–0x114171a7c）。成功/一般失败两种UI event还从
adInfo.extra非空dictionary补submit_type、submit_action_from（缺失取空），
保留原extended中的code。不是BCMMonitorUIAdEvent，不混成Monitor endpoint；
它们走普通UI Uploads，不触发MMA再次发送。
此-3001分类不代表nil URL一定产mma_url_error：已闭合GET builder写-3001后
validate(nil)覆盖为-1，具体nil URL路由应按最终error看；其他error producer未
穷尽。MMA abandon0x114171c28另reportMmaAbandon，四extras fail_count/
is_bcm_report/reason/url（0x114171dc8），同样与UI/Kotlin first-result事件分开。

BCM Monitor是另一个发送器：BCMMonitorUIAdEvent.reportType0x11416bcb0和
BCMMonitorUITrackEvent.reportType0x11416bcb8均固定raw0x10000。dispatcher
0x11416f7e8检查bit16（0x11416f9b8），将已build/copy的同params/context/info
送monitor.reportParams:context:info:（0x11416fa20/0x11416fa3c）。monitor getter
0x114171e64懒建BCMUploadsReport name="monitor"（0x114171e90），URL固定
https://cm.bilibili.com/cm/api/conversion/mobile/v2（0x114171eac/0x114171eb0）。
故它走已闭合Uploads JSON uploads POST、压缩、HTTP2xx+code0判据，独立串行
queue com.bilibili.bcm.report.uploads.monitor、cache report.uploads.monitor
（name模板0x114174508/0x114174560）。getter未安装UI/fee.ad/MMA completion
或abandon observer，不能套用那些Inspector/Kotlin/UI反馈事件。
公共BCMReport.retryFailedEvents block0x11416fd94只调用ui/feeAd/feeMMA
（0x11416fda8–0x11416fdf8），未调monitor。因此已闭合SDK启动公共retry入口
不能宣称会排Monitor旧缓存。Monitor仍继承Uploads单次成功后立即
_retryMoreThanInterval:0（0x114174adc/0x114174ae0）、失败saveRecord
（0x114174d28）及通用retry限制/尾批未flush边界；独立外部monitor.retryFailures
调用、Monitor实际业务producer尚未穷尽。不要因事件名cm_ui_report_monitor或
mma_submit_success含监控语义而把普通BCMUIAdEvent路由到此地址。

### 广告去重容器的锁与生命周期边界

Own.shared0x114336084缓存global0x120da0b68，once-token0x120da0b70；
MMA.shared0x114332154缓存global0x120da0b48，once-token0x120da0b50，
各通过0x117051e9c/0x117051e74进入dispatch_once。已检查Own完整方法范围
0x114335ff8–0x114336fdc和MMA 0x1143320c8–0x11433367c，未见初始化后的
hash数组替换、remove/clear或成功/失败/retry清除，亦未见类内账号observer注册。
这只是所检查类范围，外部动态调用是否清除仍未知，不能称账号隔离或永久去重。
SafeArray.init0x114340ee4创建mutable array和count1 semaphore。
containsObject0x1143415d8独立wait FOREVER→contains→signal
（0x11434160c/0x114341620/0x114341634）；addObject0x114342684再次独立
wait→add→signal（0x1143426b8/0x1143426cc/0x1143426e8）。这三方法内未见
TTL/容量淘汰。两个锁区不保证调用方check→add组合原子；实际线程交错未运行验证，
不能把静态同hash过滤写成并发exactly-once。

### Story选集面板与卡片翻译的实际入口

Season公开tableView:didSelectRowAtIndexPath:0x1040ef044→0x1040eef20，
按row从storyItemArray取item，要求delegate非nil才调用0x1040ea4d8。
面板工厂0x1040e85d0创建STSeriesSeasonView并弱设adapter为delegate
（0x1040e8634）；外层0x1040e96a8要求weak store/current series.item。
config缺失或showDescPopr!=1进入0x1040e7f20的session=season面板；flag1则
构造DescVCConfig locatedVideo=true/infoStyle2/current storyItem，进入
0x1040aa0b8。此分支选择UI，不是额外网络mode。
Season选择consumer0x1040ea4d8发送
main.ugc-video-detail-vertical.content-select-panel.0.click，select_content_id
取所选playerArgs.avid decimal、position=row+1，再merge0x1040e9dbc。
随后构造avid/cid来自所选playerArgs、epid0/failded nil的anchor，再调用
selectedAction（0x1040ea8cc）；无失败UI回调不能等同HTTP失败无处理。

Story卡片翻译公开STMoreBloc.translate:0x104185330→STCardTranslateBloc
0x10412f058，分别检查current.item与focusItem；后者缺失不发请求。
GET https://app.bilibili.com/x/v2/feed/index/story/trans，新建五字段：aid/cid
取focus.playerArgs Int64 decimal（缺失0）；goto/trackid取focus字符串（nil空）；
translation_status取focus.translation.status signed decimal（缺失0）。
/data/translated_item映射optional非array StoryItem，requestAsync0x10412f670。
此函数未使用STLoadBloc请求中byte，未见业务retry或偏好写入。
成功0x10412ffb8→0x10412f6b4要求weak bloc和原focus item仍活着，模型有效才
排main closure0x104130004。主线程0x10412fb78重新读取live focusItem，写入
响应title/desc/translation；双方chapters非nil且count相等才替换
permanent_entrance。此body没有avid/cid/原item equality或generation检查；
仅属静态写入边界，不推断发生过运行时旧响应覆盖。error0x10412fae4仅日志。
未来Series params的need_translate来自当前item.isTranslated0x1042efd68，
仅translation.status==1返回true（0x10411ab78），不是全局翻译设置Bool。

More物理菜单raw type37在0x104184a40跳表（0x104184de0/base
0x104184aa4）落0x104184b74，调用translateWithItem:customModel:
0x104185324→0x104184e84，要求HorizonGridModel并安装autoDismiss=true点击
callback0x10418f4d0。callback经0x104185594的weak bloc/live current.item门禁，
objc translate:0x104185674→上述0x104185330；菜单捕获item与实际focus请求item
分开，未见generation比较。外层虚方法调用者仍待名。
Portrait cell 0x113294fdc先dispose旧translationDisposable，再RAC观察translation，
skip1/takeUntil self.dealloc→0x113295214读取live cell.storyItem/watchMode/position，
调用installWithItem:watchMode:position:（0x11329526c），没有网络或全局偏好setter。
shouldAddAiTranslate0x104191a34仅要求current.item.type==1，nil false，不能按名称
把它作为上述card trans端点的账号/翻译状态门禁或独立AI请求证明。

### HDMainV2普通曝光项、检查触发与页面复用

AdSingleCell.exposedItems0x10df15c30读取当前model的report_timestamp_str/
report_track_id/report_flush_idx生成ExposureIdentifier，取self.contentView创建一个
BBListExposureItem（0x10df15ce0/0x10df15d50）。它没有设置单项ratio/repeated；
convenience init0x103eb2884→默认init0x103eb2a88留下exposureRatio none和repeated
optional raw2。因此普通曝光采用HDMainV2 delegate策略，不套广告Reporter双轴50%门禁。
MainV2.exposureManager0x10df401a0仅cached ivar nil时创建，rootView=collectionView、
先enabled=false/delegate=self（0x10df401f0–0x10df40220）；setter0x10df407c4仅
strong store，析构0x10df407d8释放。BBListExposureManager.reset0x103eb3060只
removeAllObjects。已扫描直接call和reset/setExposureManager三层selector，未找到该VC
具体clear/replace调用；动态ObjC、Swift间接和外部运行时仍未知，不声称永不重置。

checkFeedExposure0x10df40238先读disableRealExposureInTianma，true直接返回。
isChangedSwitchSize=true则延迟200ms main，以strong self capture到0x10df40300，
读当时manager→checkExposure（0x10df40324）后清sizeflag；false立即check
（0x10df402dc）后清flag。所检查body未清池或取消延迟任务。
viewDidLoad安装collectionView.contentOffset RAC观察（0x10df38ca8），weak self
callback0x10df38f88先tryInlinePlay，再checkFeedExposure（0x10df38fa8），
不是仅scroll end触发。bindVM观察VM.objects（0x10df3b2c8），callback
0x10df3bbf8重新读当前VC.viewModel；其isUpdateDislike=true跳过reload/check。
false按当前VM.willLoadFromBottom选择reloadBottomItems或allSections reload，layout后
要求VC.isShow && shared.hasFirstCheckAutoPlay（0x10df3be98/0x10df3beb8），
才main async weak self→0x10df3bfec先checkFeedInline再checkFeedExposure
（0x10df3c00c）。count仅影响emptyView/首batch，未作为最终check的非空门禁。
此callback未比对发射VM和当前VM或账号generation；未运行复现旧VM发射，保留静态边界。

addPegasusMainViewReallyShowObserver0x10df3fd90 merge self.isShow、self.isCoverBySplash、
SplashAppear/SplashDisappear通知四源，弱self callback0x10df400f4→0x10df4010c。
实际enable计算current isShow && SplashManager.splashStyle==0；另一
isReallyShowing0x10df3fd60计算isShow && !isCoverBySplash，两个谓词不混写。
backgroundBecomeActive0x10df3c83c先resign=false，splashStyle0时cover=false，始终
bannerExposure；isReallyShowing为true才main queue零延迟strong self→0x10df3c940
调用checkFeedExposure，复用当前cached manager，所检查body无pool reset。

### 日志附件Laser：实际按钮、归档、上传与结果反馈

LaserUploadViewController.uploadLogs0x100076b9c→0x1000766f4创建feedbackTask，
controller.taskID同时作taskType/tag，再uploadLogsWithTask:completionBlock:
（0x114a8a78c）。此直接入口不套uploadAllLogsWithTag:0x114a8a464的时间节流；
后者提交时即更新lastUploadTime，未等网络回执。提交保存UUID completion，
didReceivedTask0x114a8af24按actionName非nil选BaseOperation、nil选TaskOperation，
设置BFCLaser delegate并入队；TaskOperation.main0x114a90c30→uploadAfterPackup。
LogModule multibinding0x12028f0c0注册BFCLaserAttachmentProvider，两个witness
0x12048d060/+10→0x1049514a0 BLogAttachment、0x12048d048/+10→0x1049514d8
BFCLogAttachment。Laser setup0x1000777f4解析同协议数组key0x120279490，
逐项对实际BFCLaser receiver registerAttachmentProvider:（0x100077b48），
闭合实例注册。BLogAttachment.localPaths0x104953c98→0x104955284先flush
BLogger，再枚举Documents/BLog按yyyy-MM-dd筛日期；没有读取实际日志内容。
operation附件收集0x114a8bd04调用注册provider localPaths/data并保留name关联。

TaskOperation.uploadAfterPackup0x114a91348取得date/dateList对应附件，空列表error1；
非空先createZip，失败退createTar（0x114a917dc/0x114a918c0），计算归档size/MD5。
实际uploadServiceForOperation:0x114a8c790缺getter默认raw2；实验getter
0x100074a94查询laser.upload_to_upos preset1，true2/false0。因此默认UPOS，
而非备用Uploader固定URL。raw0走BFCLaserUploader0x114a967d8→0x114a96834，
options.localPath、requestMethod2/taskType1/ignoreCache1/timeout60/cacheLife0，
/data模型、completion/error后requestSync0x114a96a50，/data.url非空才接受。
raw2先复用task identifier匹配的UPOS task，未找到才新建BFCUploadRequest，设置
profile/options.mid/归档file location，再装completion0x114a92290并resume。
回调error nil才从storageInfo.bucket/key构造download URL/UPOS URI，任一结果均
signal semaphore（0x114a923e8）。等待后删除归档0x114a92124，不等同删除原日志文件。

UPOS taskWithRequest0x114a996a8→TaskManager0x114a9c510创建UploadTask并设
performer=self，resume0x114aa56d0→0x114a9cd84创建BFCOperation包装
OperationManager并入队；enableRealTimeTranscoding另分支。普通start0x114a9a9dc按
phase/enableSimple/size阈值选simple，否则Pre/Initial/Part/Merge managers。
fresh request options ctor0x114aa7410未显式设置simple/transcode，恢复task配置
仍需区别。BaseRequestManager.sendRequest0x114aa89ac调用实际apiRequest构造
BFCApiRequest，设callback queue/timeout/handlers后requestAsync0x114aa8c38，
不是按SDK名推断Ktor。pre-upload0x114aac48c选非空request.preUploadUrl或内置
endpoint、method0、options query+archive basename/profile；merge endpoint由
storageInfo及uploadId/taskConfiguration构造。part/merge完整options仍未闭合。
error callback0x114aa8d48递增currentTimesOfRetry，交替continuousFailure时按
optionalEndpoints count轮换endpoint；current<timesOfRetry才main dispatch_after
interval后重启。Base默认timeout120/timesOfRetry10/interval3
（0x114aa9030/0x114aa9038/0x114aa9040），子类可覆盖，不当全局固定策略。
正常Merge.success0x114aaa55c设置resultInfo/phase→notifyTask:error:nil，失败另传error；
CallbackManager0x114a9bc38调用completion(error,storageInfo)0x114a9bca0→上述Laser
0x114a92290。这是实际上传回执链，未证明服务端持久性或所有恢复任务均可续传。

上传后TaskOperation.main按URL是否nil写status3/-2等reportContext，report
retryTimes3/retryInterval3（0x114a91020），具体feedback0x114a92708→LaserApi
0x114a89448，requestSync0x114a89820。报告error时循环，最多3次总attempt、
间隔3秒，区别UPOS stage retry。如果上传error nil但report error非nil，合成error6
（0x114a91094）；最终delegate completion0x114a911ec携URL/error。BFCLaser
0x114a8d160删缓存task、main派发UUID completion并移除callback；本地清理不是远端ACK。
上传成功和报告成功是两层判定，不能用Crash.reportIssueComplete(true)代替。
Laser setup业务触发余项、UPOS缓存恢复/各stage覆盖、BLog最终daily-file写入继续追踪；
没有网络/文件内容/设备采集验证，不推广所有诊断均走Laser。

### BLog缓冲区、压缩、最终文件写入与flush限度

BLog setup0x11647f9f4→0x1164864ec对nil global一次alloc/ctor并存
0x1210df460；core0x1164802d0分别读console/file阈值。允许写文件才加newline、
mutex保护buffer.append0x116480a78（0x1164808e0）。buffer ctor0x116483b2c
open/ftruncate后mmap prot3/flags1（0x116483c98），失败退heap；append memcpy
0x116480aec更新used/header，满块切换后owner virtual+30（0x116480b84）。
owner vtable0x11d05ead0/+30=0x116484838转job/SharedPools压缩；另一输出owner
0x11d05ea40/+30=0x1164843a0→0x11648441c入core+80队列。
压缩worker vtable0x11d05eb40/+30=0x116485434→0x116485594，TLS缓存状态，
初始化传level1/method8/windowBits-15/memLevel8/strategy0，符合raw DEFLATE参数；
helper内部未完整重推，不作加密归因。stored-block fallback显式LEN/NLEN+memcpy。
disk worker vtable0x11d05e8c0/+30=0x116481bfc→0x116481c84，从队列取得
BLockJob（0x116482518），更新day/path，再file helper0x1164828c4→lazy open
0x1164834e8→实际_open0x116483540（EINTR重试）。实际_write0x11648298c
处理partial write和EINTR，失败另报diagnostic。daily/quota/旧job筛选存在，
精确保留策略仍待追，不读取实际路径或日志内容。
flush0x1164809b0装semaphore、调用相同owner、wait FOREVER0x116480a5c；
关键边界是disk worker写成功、失败或旧job跳过均可到job completion0x116482188，
原block callback vtable0x11d05ec10/+30=0x116485c44重置header并signal
（0x116485c70）。所以flush返回只证明本地排队job完成，不能证明文件写成功、
落盘持久性或服务器收取；Laser的flush→附件收集仍受这一区别限制。

### HD2外层账号事件、重建与新曝光池边界

BBHD2PhonePegasusVC.loginStateObserve0x10df1a670注册BFCAccount observer
mask6（0x10df1a6e8），沿已闭合公共action映射即Logout2+Update4，不包含Login1/
Change8；桥0x11603a2b8保留mask，callback wrapper0x11603a354不改action。
Update且current hasLogin时homeVM.clearTime→tryLoadData
（0x10df1a77c/0x10df1a79c）；Logout且!hasLogin时homeVM.clear
（0x10df1a7c8），之后都比较VC.isLogin与当时Account.hasLogin。
Bool不同才setIsLogin、新MainVM（0x10df1a8a0）、rebuildVC0x10df1a8e4，
再新MainVM.tryLoadData；Bool相同不重建Main，但不能说homeVM不刷新。
这里homeVM是下述notice VM，与推荐MainVM及其feed请求分开。
rebuild0x10df1a028强制buildVCUseCurrent=false→0x10df1a030，旧内页
willRebuildSignal.sendCompleted0x10df1a090，再new MainV2 alloc/initWithMainVM
0x10df1a0d0，移除旧view/parent并设置新mainVC。新MainV2.init0x10df385f0
创建RACSubject作willRebuildSignal，再setViewModel输入VM。这样重建形成新VC和
新lazy曝光池，区别旧manager.reset；并未证明旧VC立刻析构或旧HTTP取消。
所扫描willRebuildSignal getter direct/selector调用未找到takeUntil/subscribe消费者，
内联ivar/动态使用仍未知。refreshBlock0x10df1a38c仅current hasLogin才读取weak外层
homeVM.tryLoadData0x10df1a3c8，所检查closure不reset曝光池。

### Laser启动任务、服务器任务与预先去重

LaserModule Runnable witness0x11b0a6c60的构造入口0x10007461c/0x1000745b4→
moduleInitialize、0x10007463c/0x1000745cc→main，priority360，name
LaserModuleModuleInitialize；exec+28→0x1000746d4→setup0x1000777f4。
时序上BFCLaser.setup0x100077a84先于附件provider注册0x100077b48。
setup0x114a89c34从cache.tasks0x114a8fc38→Preferences.tasks解dict恢复任务并
queue.addOperation0x114a89ed8，因此未证明恢复任务总能看到后注册的所有附件；
未测线程交错，不把静态先入队次序当成运行竞态已发生。
registerMossStreaming0x114a8ab3c注册V1 Laser.watchLogUploadEvent及V2.watchEvent；
生成方法0x114afa028/0x114afb59c经MossCenterWrapper→sharedCenter→registerSvr，
response class分别V1LaserLogUploadResp/V2LaserEventResp。V1 handler
0x114a8ac24把taskid/date映dict→fawkesTask0x114a8ad24→didReceivedTask；
V2 0x114a8ad84把taskid/action/params映dict→0x114a8aec0→didReceivedTask。
具体stream底层重连/外部所有权仍属于Moss公共层余项，不把此注册当已接到真实任务。
didReceivedTask0x114a8af24仅laserType1/2先containsTaskId（0x114a8afcc），
hit记录后退出；miss先addTaskId0x114a8b074，再cache.addTask/入队。
addTaskId0x114a90858将新ID插index0，count>=11移除last，setTopTaskIds
0x114a90954，普通单插保留10。标记发生在执行/回执前；已查body无时间或账号拼接，
外部清除未知，不能称成功后去重或完整账号隔离。
BFCLaserPreferences动态属性tasks NSArray/uploadInfos NSDictionary/topTaskIds NSArray，
继承BFCPreferences；其方法表无configName override，继承getter
0x1167d33b8通过NSStringFromClass生成namespace。BFCPreferences.userDefaults0x1167d4ccc调用configName后initWithSuiteName
（0x1167d4cfc/0x1167d4d14）并缓存到instance+8，故此类固定suite
BFCLaserPreferences，所查body未拼账号。expiry/外部clear仍待追，不读取实际缓存或ID。


### HD2 notice 的门禁、参数和回执时间归属

外层init0x10df193d0创建MainVM（0x10df19504/0x10df19514）；viewDidLoad
0x10df19cf4另创建HomeVM并保存（0x10df19d98/0x10df19da8），先buildVCUseCurrent=true，
再以当时BFCAccount.hasLogin初始化isLogin（0x10df19dd4/0x10df19de0），然后装账号observer。
此Bool不能按默认false处理。HomeVM.wiredInfo经RAC、main scheduler、skip1
（0x10df19e84/0x10df19ed8/0x10df19eec）到weak外层updateUIByWired
0x10df1a014；这是notice UI来源，不是MainVM.objects。viewDidLoad尾端当前登录才
homeVM.tryLoadData（0x10df19f70/0x10df19f8c）。outer dealloc0x10df1958c
移除Account observer和NotificationCenter observer（0x10df195ac/0x10df195cc），
所查body没有内页HTTP cancel；不能把观察者移除当请求取消。

HomeVM.loadData0x10df57e90先读当前NSDate和共享global0x1210741d0；已有date且
elapsed<1800秒则只结束loading、清error，恰好1800可继续。BFCAppPreferences.inReview
为true也同样退出。通过才构造GET https://api.bilibili.com/x/member/v2/notice
（0x10df57f78/0x10df58024），/data映射NSDictionary、isArray=false
（0x10df57fa4，静态JSON pointer0x11d0ef8d0），requestAsync0x10df580dc。
params0x10df58508只组两个String：uuid来自BFCIDFA.idfaString移除全部连字符，
nil/空→空；mid来自BFCAccount.userSID（0x10df585ac），nil→空。
没有读numeric MID，不能按字段名替换来源。这里没有读取实际IDFA/SID或响应。

completion0x10df58188把捕获的请求开始Date写共享global（0x10df58214），再按/data
status/type处理：status0→wiredLoginType0/wiredInfo=nil；security→type1/security对象；
realname→type2/realname对象；其他→0/nil，最后loading=false/error=nil。
共享Date写入不依赖weak VM仍存在，所查body没有当前账号/当前HomeVM比较。
error0x10df58334忽略incoming error，weak VM有效时只loading=false/error=nil，不写Date。
clearTime0x10df584f8只共享Date=nil；clear0x10df584bc还type0/info=nil。
这两个body没有清推荐数据/曝光池或cancel。共享Date跨HomeVM实例，但外部重置、
响应到达顺序与真实账号切换影响尚未运行验证。

### 字幕选择、AI翻译目标偏好与公共 Locale 元数据

STCaptionBloc主字幕菜单builder0x10412e040安装click0x10412ef60→0x10412dae4，
选择副字幕0x10412eee0同helper；weak bloc有效才向捕获caption service发
chooseMainItem:/chooseViceItem:，再sendSutitlelanguageTrack:，scene字面量"3"。
BBPlayerCaptionService0x114855f30/0x114856010→0x114856c98更新selectedMain/Vice、
currentLanguage文本及context.danmaku.config.enableCaption/mainLanguageCode/viceLanguageCode。
config setter0x11485b6b0/0x11485b6cc是copy ivar setter。changed block由播放器
0x1041a9090安装（0x1041a9174），经0x1041a9464→0x1041a86d4到可选服务
subtitleLanguageDidChanged:secondaryLanguage:；native实现0x1143b6d70只更新Chronos
OnDanmakuConfigChanged，nil language→kBBPlayerSubtitleNone，所查路径无全局目标偏好writer。
sendSutitlelanguageTrack:0x11485733c上报player.player.subtitle.language.player，字段
bilingual_subtitles_status/language_code/scene/status/big_subtitles_status；这是事件入口，
不能当字幕下载或语言持久化。其他字幕设置入口仍需单独核对。

AI target则有实际偏好writer：BBPlayerAITranslateService.switchLanguage:
0x1049cccd8→0x1049cc80c比较currentLanguage与incoming对象指针，相同（含nil/nil）
直接返回；变化时设置currentLanguage并调用VBPreferences.shared.setTranslateLanguage:
（0x1049ccbb0），值incoming.lang、缺失→nil。随后currentScene.reloadType=4
（0x1049ccc40）并调用重新获取的currentScene.reload0x1049cccac。
closeTranslate0x1049ccd20传nil，也受相同指针门禁；reload调用不等于已发HTTP。
Story AI菜单0x104126e1c要求live player/service key0x1203f2550及language.items，
row selected同样用对象指针（0x104127084），languageType2加AI badge。
row click0x1041293b8→0x104127764要求weak bloc/weak row有效，重新resolve live service，
可选openToast后switchLanguage:capturedRow（0x104127910），dismiss/clear swipeVC，
再发main.ugc-video-detail-vertical.half-aidubswitch-option.0.click、option=row.title。
该callback没有把captured row与fresh service语言列表再次匹配；不据此声称实际竞态。

VBPreferences class0x11ff10888继承BFCPreferences0x1202710f0；translateLanguage是
NSString dynamic-copy属性，configName0x104b9872c固定VBPreferences，不拼MID。
init0x104b9844c→0x104b98284订阅KntrTranslation.alwaysTranslateFlowIOSAsync；callback
0x104b984f4忽略传入Bool，重读alwaysTranslate：true取KntrLocalization.current.language，
false取nil，再写translateLanguage（0x104b985f4）。所查setup没有dropFirst；实际首次
投递时机仍未知。此订阅可覆盖播放器先前选择，账号/上游flow写入边界继续追踪。
已闭合的preload helper读取此偏好作cur_language；不要等同Story card-trans五字段请求。

Locale元数据走独立缓存：0x105060e60创建LocaleCache，初始六空String/+0x78 false，
同步refresh0x1050624ac重读KntrLocalization.SYSTEM/current两组language/script/region和
KntrTranslation.alwaysTranslate，然后在锁内替换六String与Bool。观察0x1050627e4
组合localeFlowIOSAsync/alwaysTranslateFlowIOSAsync，SkipCount factory0x1050fc84c
（metadata0x1050fc894、count写+0x18@0x1050fc8c0），caller0x105062adc传1。
callback0x1050638ac→0x10506382c忽略tuple，weak cache有效才完整fresh-read refresh。
因此先同步初始化，再跳过一个组合投递；不猜具体投递频次/运行值。

0x10505f9ec和0x105060cb8均在锁内snapshot六String/+0x78，调用builder0x105060f44
构造BAPIMetadataLocaleLocale，设置sLocale/cLocale/alwaysTranslate及系统Timezone/GMT offset。
这里setAlwaysTranslate:0x10506115c是PB setter，不是KntrTranslation setter。
不读VBPreferences.translateLanguage。header producer0x10505f9ec对Locale.data非nil时
base64EncodedString(options:0)（0x10505fb84），插入x-bili-locale-bin
（0x10505fba0）；nil data省略。conformance0x118436c80解析protocol LocaleRegionService
0x1196b139c、type MetadataStore0x1196aed58，wtable0x11b347318：+8→0x10506043c→
header map，+0x10→0x10506045c→0x10505ffcc二进制map，+0x18→0x10506047c→
0x105061414 region。provider0x10008da60以once0x120897bc8/cache0x120897bd0返回该
existential，initializer0x10008dfd4。最终HTTP/Moss overlay和采用范围继续追踪；
不能从header builder推断所有请求必带，也不能把player target-language与此Locale合并。


HD2 notice close 的UI与网络效果另有完整入口：WiredNoticeView第一个UIButton
0x10df52cfc经RAC control0x40（0x10df52f24）、throttle0.3秒（0x10df52f40）到
weak view closure0x10df53ecc，把frame置CGRectZero后closeSignal.sendNext:nil
（0x10df53ef4/0x10df53f10）。外层closeSignal0x10df1ab34经main deliver订阅
0x10df1b088，读当前homeVM.closeWarning（0x10df1b0b0），随后立即hideLoginWiredView
（0x10df1b0c0）。hide0x10df1b61c只remove notice view、重做当前mainVC view constraints，
没有清wired type/info/shared Date/推荐曝光池。closeWarning0x10df58370构造
POST https://api.bilibili.com/x/member/v2/notice/close（0x10df5845c），同uuid和
mid=userSID及NSDictionary /data parser，无业务completion/error handler，
requestAsync0x10df58478后释放局部request。UI隐藏不等待ACK，所查路径无rollback；
后续wiredInfo投递仍可能重新显示，不能声称服务端已关闭或永久清除notice。


### UPOS 各阶段配置、分片状态适配与取消通知

Initial class0x12020c6b8/Merge0x12020c708/Pre0x12020c848的原始method lists均无
Base timeout/times/interval覆盖，沿已查正常manager用120/10/3。
SinglePart class0x12020c8e8则明确覆盖：0x114aaef40/0x114aaefb4/0x114aaf028
读取taskConfiguration.timeout/timesOfChunkRetry/delayIntervalOfChunkRetry。
configuration parser0x114aa82a8解析chunk_size/threads/timeout/chunk_retry/
chunk_retry_delay/endpoint/endpoints/upos_uri/put_query：zero chunk_size→8388608，
threads unsigned≤1→1，zero timeout→900，zero chunk_retry→200，zero retry_delay→3
（0x114aa83cc/0x114aa8404/0x114aa8444/0x114aa8500/0x114aa853c）。
这些是pre响应解析默认值，不是实际服务配置或全局retry budget。Simple timeout
0x114aadc18另按options.size作移位/高位乘法后+5，不能套固定120。
SinglePart.retryOnFailure0x114aaedd4增加partInfo.timesOfRetry并发retry通知，
实际重试调度仍走Base failure closure。

Pre.apiRequest0x114aac48c优先非空request.preUploadUrl，否则
https://member.bilibili.com/preupload（0x114aac698/0x114aac6a8），GET。
mutable-copy options.queryDictRepresentation，加入r=upos、name=filePath.lastPathComponent、
profile。success0x114aac970解析configuration，仅endpoints非空才记ctimeOfPreupload/
taskConfiguration、推进phase并通知更新（0x114aaca38/0x114aaca7c/0x114aacb94）。
Initial0x114aa97b8使用公共URL format "https:%@/%@%@"，activeEndpoint及
NSURL(uposUri).host/path填入，不自行补slash或固定动态域名。params uploads=""、
output=json，customInitialParas后合并可覆盖；method raw2，X-Upos-Auth来自configuration.auth，
BFCApiRequest init0x114aa9ba4。Merge0x114aa9f34同format，改用activeEndpoint及
storageInfo.bucket/key；output=json、uploadId、biz_id，needTranscode才添profile，
customMergeParas后合并可覆盖（0x114aaa308）；method raw2、auth非nil才添同名头，
init0x114aaa4fc。不读取实际auth/endpoint/上传资料。

SinglePart0x114aadd4c同URL规则及auth头、ignoreCache1/signType1，params为decimal
partNumber及uploadId。非background路径seek partInfo.offset、读partInfo.size字节，
taskType4/localData；background为taskType3/localPath。requestInjection0x114aae5ac
mutable-copy最终request并明确设置PUT（0x114aae5cc）。preProcessRawData
0x114aae5e0仅HTTP status200合成JSON code0（0x114aae630/0x114aae6a0），其他nil。
这是传输状态适配，不是服务端返回JSON code0或所有分片已持久化的证明。

Task.cancel0x114aa5740→TaskManager.cancelTask0x114a9d1c8；running operation存在才
cancelOperation、删UPOS task cache、state0，再notifyTaskDidCanceled；无operation也通知，
但跳过这段删cache。OperationManager.stop0x114a9b4c8取消uploadQueue，Base.stop
0x114aa88a0设isStop1并main common modes排BFCApiRequest.cancel、waitUntilDone=false
（0x114aa8960）。取消通知0x114a9be9c→block0x114a9bfbc只向delegate发
uposUploadTaskDidCanceled（0x114a9bfe4），不调用task.completionHandler。
因此不能把它当Laser upload-completion0x114a92290或semaphore signal；底层request
取消后的error回调与wait释放仍待证，也不直接声称hang。

Laser Task.init0x114a92930记录UUID/createTs；缓存parser0x114a92c08恢复createTs，
cache.tasks0x114a8fc38重建后直接加入（0x114a8fd38/0x114a8fd50），所查循环无age门禁。
createTs selector stub0x117292060的直接B/BL扫描只见metrics及dictRepresentation；
不覆盖直接ivar/动态访问。未闭合Laser任务TTL/外部generic suite clear；十项task-ID上限
不能写成TTL。UPOS自身另有expired-task数据库路线，不能移植给Laser Preferences。


Story More的AI两种动作与card translation独立：raw35 jump0x104184d94→
aiAudioWithItem:customModel:0x10418d3b0→0x10418cb04要求SwitchModel，观察
live service.base.currentLanguage，callback0x10418ef18→0x10418cf5c只按非nil设置isOn。
switch click0x10418ef20→0x10418cfc4重新resolve service，Booltrue→openTranslate
（0x10418d0a8），false先dismiss再closeTranslate（0x10418d194/0x10418d1a4）；
可选open/closeToast及More事件报告，不直接发HTTP。
openTranslate0x1049cd0cc→0x1049ccd30按items顺序寻找lang等于新读的
KntrLocalization.current.language，未匹配再取fresh items首项，nil/空→nil，
然后switchLanguage:（0x1049cd08c）。这个body不读取保存的translateLanguage来恢复选择。
raw36 jump0x104184af4→aiAudioExchangeWithItem:customModel:0x10418dad4→
0x10418d3bc，click0x10418ee88→0x10418d954→STAITranslateBloc0x104128f94，
旧swipeVC dismiss/raw0并清引用，再建上述language rows、VKSettingVC，以
STPoperOptions.session=translateList呈现（0x1041290bc/0x1041291a0），weak保存结果。
只打开panel不修改语言/偏好；raw37仍是前述card-trans。

AI reset0x1049cbe3c→0x1049cbd78只清service.language/currentLanguage、四组handlers和
guide/toast状态，没有switchLanguage、VBPreferences setter或scene.reload。
STAITranslateBloc virtual0x104126324→service.reset（0x1041263cc）的事件注册仍待归属。
因此显式close写偏好nil与局部reset清内存不能混同；其他生命周期writers继续核对。


### HD2 MainVM 迟到回执的原VM与共享状态边界

apiProcess0x10df58dfc的success0x10df59104/error0x10df59ab8均捕获weak原VM于block+28；
success+20强捕获requestparams.open_event，error+20捕获请求时appstate字符串，
另捕获retry/isActiveRetry两个byte。requestAsync0x10df59030后局部request释放
（0x10df590a4），所查body无VM-owned request setter/cancel token。MainVM.dealloc
0x10df58880只移除Account/Notification observers再super；继承链
MainVM→3PointListVM→BaseListVM→BaseVM的完整销毁、public全局取消另待证，
不据局部无cancel断言所有旧请求一直存活。

success完整0x10df59104至0x10df59978无nil VM、当前outer.mainVM或账号generation门禁。
原VM仍作为sceneUri/needShowGuidance/follow_mode/noDataTip/visible_area/interest/
login_event/updateArray/error/loading/objects/isEnd/shouldShowBottom的receiver；
weak VM消失只令其ObjC消息无效，不使完整callback退出。共享Config的
isFeedReqSuccessOnce=true（0x10df591f8）、pegasusCloumn（ipad_hd_abtest NSNumber
true→3/false或错型→4）、BBAdPegasusHelper.setIPadCloumn、RefreshHints autoRefreshTime、
FormatManager column、InlineShared autoplay都可继续执行。
config.home_transfer_test→global0x1210e10d4（0x10df59440），
show_inline_danmaku intValue==1→global0x1210e10d0（0x10df5947c）；
shared MainApiHelper**当前**firstRequestInfo非nil才清空（0x10df595dc/0x10df59614），
无请求归属比较。missing key的numeric ObjC消息多为0，typed fallback要单独保留。
因此不能把原VM消亡写成旧回执没有共享副作用；真实发生与外部取消仍未验证。

CardPool conversion callback0x10df59978强捕获success阶段读到的原VM，用page_from="1"、
原VM from_spmid_v1/v2及conversion callback index+1→report_flush_idx，timestamp
来自card.getCurrentTimestamp；CardPool.dataArrayFromArray:modelAnalysisCallback:needToReport:0x10df17f54的x23从0
逐raw input增加（0x10df17fc0/0x10df17fe4/0x10df18674）；转换后在nil/isValid过滤和
加入结果之前调用callback(model,x23)（0x10df18074/0x10df1807c）。因此该HD回调的
report_flush_idx是raw input ordinal+1，unknown/missing/invalid不压缩编号；嵌套items
子卡callback仍用parent raw x23（0x10df1832c/0x10df18330）。banner_item子项另用
child index+1（0x10df18564–0x10df18594）。不要套Swift compactMap的编号规则。
first converted CardBaseModel idx保存见前述修正，与loadMore末卡不同。

error完整0x10df59ab8至0x10df59fdc同样无nil/currentVM/account门禁。
trackTech0x10df59d00先使用incoming error.description、捕获retry/activeRetry/appstate及
当前launchState/当前UIApplication.appstate；没有error.code=-999绕过。
retry byte恰为1才读原VM当前options再apiProcess，retry分支暂不清loading/error；
nil VM不重试，但tech仍可执行。最终分支原VM当前objects.count=0（也包含nil VM）
生成tm.recommend.load-error.0.show（0x10df59e54/0x10df59e64），error_code来自incoming
error.code decimal，load_scene来自原VM.emptyErrorReason、nil VM numeric0。
随后空分支reason=3，全部final errors向原VM写loading=false/errorincoming；net error→
overflow String1，否则objects非空→String3，空则无overflow。无当前outer VM重定向或
UI exposure pool reset。仅记录静态来源，不读取实际error或声称已复现迟到回执。

### UPOS 自身数据库过期与停机后的回调门禁

Config.init0x114aa5050的expiredDay默认2（0x114aa5088/0x114aa508c），可被setter改变。
CacheManager.ensureCacheEnabled0x114a9f844首次置enabled=true后alloc/open，传
config.cachingDirectory/expiredDay。openDatabase0x114a9f91c调用getExpiredTask：
transaction0x114aa0590用signed truncation(now Unix seconds - unsigned(days*86400))
执行SELECT task_identifier FROM upos_config WHERE ctime_of_preupload < ?
（0x11d38d830/0x114aa0658），ctime来源pre成功回执，不是LaserTask.createTs。
有expired IDs先delegate.tasksHaveExpired，再逐deleteTask0x114a9fa78。
实际Client.tasksHaveExpired0x114a9988c删file cache（0x114a998f4），可选delegate
每ID收到taskDidFinish(identifier,error7)（0x114a999e0）；这不是upload completionHandler。
首次enable/open做过期处理，不是所查restore每次读取都重新比较age；未读实际DB/目录。

BFCOperation.cancel0x114ab02b8只有executing才performer.stop（0x114ab0300/0x114ab0318）。
UPOS error callback0x114aa8d48若weak manager存在，仍可clear internalRequest、
sessionEnd/增retries/排delayed retry（0x114aa8f2c），该callback无isStop检查；
但下一sendRequest0x114aa89ac先构造apiRequest/保存，再checkError/isStop，
isStop门禁0x114aa8a18在requestAsync之前阻止新send。停机仍可能发生构造/通知/调度，
不能等同又发网络；该路径仍不足证明Laser completion收到取消或wait一定释放。

pre query producer0x114aa7a1c无条件字段traceId/device/osVersion/build/version；
mid/appKey/accessToken/networkType各nil-gated，size非零才decimal String，path非nil才加。
之后pre覆盖r/name/profile。只记字段来源，不解码凭据、身份或实际设备值。


### Story AI语言偏好到 Unite 播放解析及响应回显

BBStoryPlayableScene.getPlayItemFromPreloadItem0x1132f7704要求preloadItem非nil，
读取VBPreferences.translateLanguage，交preload.response.availableWithLang:
（0x1132f7774）。允许复用时从preload.resolverItem构建play item；不允许时清除
当前model.resolverModel.preloadUrl（0x1132f7880），重新读取目标偏好写curLanguage
（0x1132f78b0）、curLanguageType=0（0x1132f78cc）、clientAttr&~2
（0x1132f78e0），存回model并返回nil。playWithParams0x1132f61e4在nil分支调用
resolveToPlayEnablePreload:true（0x1132f650c）；后者0x1132f6540要求resolverModel
符合BBResolverUniteParms，才调用UniteHelper（0x1132f6644，updateBlock=nil）。
这闭合了请求材料变更与解析入口，不把偏好setter或reload直接当成已发送请求。

availableWithLang0x114a0b300在language.items.count=0时立即true；否则读取
alwaysTranslate，true才取当前locale.language作自动目标。扫描语言列表：非空传入偏好
在列表中时要求response.curLanguage等于偏好；否则自动目标在列表中时要求等于自动目标；
两者均不可用时仅curLanguage.length=0允许复用（0x114a0b558–0x114a0b5d4）。
该body不比较curLanguageType、不写偏好；列表及locale是fresh reads，未观察实际并发。

UniteHelper.resolverWith0x114a4c8d8：isCantUseLocalCache=true直接IgnoreCache；
否则kmpOffline决定KMP或native离线解析。离线callback0x114a4ca90/0x114a4cbe0
有response就向原completion交付，即使error非nil；仅response=nil回退IgnoreCache。
IgnoreCache0x114a4cd30重新读preloadUrl，非空走PreloadResponse、空走PlayViewResponse。
Preload失败且response=nil也回退PlayView（0x114a4cef4）。通用helper的离线路径仅适用于isCantUseLocalCache=false。具体Story初始factory
tranfromUniteParsModelFromParams0x11330c148显式setIsStoryMode=true（0x11330c1a4）、
setIsCantUseLocalCache=true（0x11330c1b0），末尾fresh VBPreferences.translateLanguage
写curLanguage（0x11330c510/0x11330c528），该factory完整body无curLanguageType setter。
所以这个producer的参数直接走IgnoreCache；若后续语言不匹配清preloadUrl且仍使用该model，
进入PlayView。其他model来源仍保留通用离线条件，不把所有切换都宣称为实际联网。

PlayViewWith0x114a4dcfc构建BAPIAppPlayeruniteV1PlayViewUniteReq与VideoVod：
params.curLanguage→vod.curLanguage（0x114a4dfec），curLanguageType→
vod.curProductionType（0x114a4e008），clientAttr→vod.clientAttr；Story回退的type0
确实进入PB字段。aid/cid/qn来自params；fourk来自IJKFFUtils.isUhdSupported，fnver=0，
softFnval/fnval来自BBResolverUtils两个支持函数，voiceBalance来自enableLoudNorm，
isNeedTrial来自params，qnPolicy仅params.qnPolicy==1时true。download=true设置
下载raw2/forceHost2；普通播放forceHost2由forceHttps或播放器httpsPlayurlEnabled决定。
request的spmid/fromSpmid/bvid/adExtra/fromScene/playCtrl来自params，extraContent.copy
（0x114a4e090/0x114a4e0a0）；lastReply.fragmentVideo非nil时清片段reports后复用。
codec及其余分支另证，不读取实际身份/广告字段值。

实际dispatch0x114a4e350调用Player.playViewUniteWithRequest:handler:；class入口
0x114a6ec84取得defaultService，instance0x114a6ebf8将request、Reply class、
service对象+8和方法字面量PlayViewUnite交BFCMossServiceWrapper.handleRpcRequest
（0x114a6ec60）。这是业务到Moss wrapper的调用证据；公共transport元数据采用范围
需沿独立transport链核对，未运行RPC。

RPC callback0x114a4e3d8：incoming error非nil构造type2业务错误，优先非零bapi_status.code、
非空bapi_status.message，分别回退NSError.code/localizedDescription；reply=nil且无error
为30004/type2。reply非nil但hasVodInfo=false为30005/type3，stream count0或parser.asset=nil
为30004/type3。type3仍执行parser，内部completion可带parsedresult/supplement但asset等nil；
外层0x114a4d180有error时直接main completion(nil,error)，不会把该parsedresult应用到Story。
无error才构建BBResolverUniteResponseModel，继承initWithPlayViewInfo0x114a0bb2c复制
language（0x114a0bca8）、curLanguage（0x114a0bcd0）、type（0x114a0bcec）。
Story completion0x1132f66a0要求weak scene存活；error→_playError（0x1132f66ec），
无error→setResponse（0x1132f66f8）→_playWithResolverResponse，enablePreload取捕获true
（0x1132f6708）。这些局部body未见MID/avid/generation比较，未据此宣称已复现串回执。

Parser0x114a48ec4把reply.language经parseLanguageWith0x114a43ebc变成BBResolverLanguage，
保持items顺序；item.productionType→languageType（0x114a44078），并复制lang/title/
buttonTitle/subtitleLang及语言菜单/开关toast字段。reply.vodInfo.curLanguage→result.curLanguage
（0x114a4951c），curProductionType signedInt32→result.curLanguageType（0x114a49550）。
Story updateTranslate0x1132f7f38及Swift入口0x1041c0eb8把response三字段交AI service.setup
（0x1132f7fd0/0x1041c0e70）。setup0x1049cbe64选择首个optional lang匹配且languageType
匹配的item（helper0x1049d0740），直接setCurrentLanguage（0x1049cc0f8）；缺/空items清本地
language选择与flags。它不调用switchLanguage、不写VBPreferences、不reload；因此服务器回显
恢复当前选项与用户目标偏好writer是不同阶段。

### HD2 loadMore 的原VM当前数组与入口门禁

直接MainVM.loadMoreData0x10df5a4c0仅检查isLoadingMore；正常tryLoadMoreData
0x10dedfa14另要求!isLoading和tryLoaded，super.loadMoreData0x10dedfa54设置两个loading flags。
成功0x10df5a898及错误0x10df5b04c捕获weak原VM，不在这些回执body比较当前outer VM、
账号或generation；producer requestAsync后释放局部request，未见VM-owned cancel handle。
成功即使原VM消失仍可更新共享autoRefreshTime/autoplay及home_transfer_test、
show_inline_danmaku（0x10df5a938/0x10df5aa20/0x10df5aa5c/0x10df5aa98）。
转换后读取原VM的CURRENT objects（0x10df5acb0），追加本次转换数组（0x10df5acc4），
超过loadMoreMax裁prefix（0x10df5ad0c），再setObjects（0x10df5adf4）；不是请求起点数组快照。
达到max或review置end/bottom，低于max且新数组非空可继续；新数组空则end并overflow4。
转换callback的flush_idx也采用上述CardPool raw ordinal+1。

错误先tech上报（0x10df5b1b8），再清loading/more并写incoming error；该完整body无retry或
-999静默分支。当前reachable=false时overflow用先前捕获currentStatus raw值；reachable=true
且原VM当前objects非空才固定overflow4，否则不发该overflow。正常入口门禁仍适用，缺generation
比较不等于已观察并发乱序。BaseListVM/BaseVM method table无own dealloc，其destruct只释放字段；
全局dispatcher、外部所有者和完整运行时取消边界仍未知。

### WatchLater 管理菜单到确认与工具栏动作

管理sheet producer0x10110f67c读取静态三项数组0x12030a768；MoreAction.Action
reflection0x1194eebbc/0x1197d51bc的empty cases依次为clearAllWatched、clearAllInvalid、
batchManagement、delete。数组前三项tag2、ordinal0/1/2映射前述三动作。
SheetModel经MoreAction.Item转换；ActionSheetController.init0x1011333b4把传入row callback
存到clickItem（0x1011334b0）。viewDidLoad helper0x10112f82c向contentView witness+0x10安装
0x10113365c→0x10112fde8；该callback弱controller有效时启动dismiss动画
0x10112ff74，completion0x101133890→0x10112fe9c先dismiss(false)再读取live clickItem
（0x10112ff24/0x10112ff50）。该witness对应contentView的clickItem setter，物理row事件已在下段闭合。

row callback0x1011100c4→0x101119cd8读取Item.action并交captured action consumer；
0x101110078→0x10110f908在tag2时把ordinal0/1/2分别转MainAction族0xa0的1/2/6：
clearAllWatchedAlert、clearAllInvalidAlert、showManagementToolBar，然后交Store action callback。
前两项由已述确认弹窗才转clear_type2/1；批量管理转工具栏状态，未在菜单转换body直接请求HTTP。
菜单上游入口及账号变化处理仍待证；row物理接收者已闭合如下。


PlayView Vod codec分支由enable_new_playview_rule AB（0x114a4debc）决定：true取
min(params.preferCodecType,IJKFFUtils.preferVideoCodecId)，包括params=0，映射
getVideoCodecTypeWithId再减1，经0x114fbd490要求unsigned<5，否则raw0。
AB=false且hitAV1Support=true时params非零才与device prefer取min，零用device prefer；
相同映射/范围检查的invalid fallback却是raw1（0x114a4df60）。AB=false且AV1不支持
默认raw1，HEVC支持且params.preferCodecType!=7时变raw2（0x114a4df7c）。
最终写vod.preferCodecType（0x114a4df8c）；这里只保留已证raw值，不猜PB enum语义。

### HD2 刷新旧卡保留与布局裁剪

buildObjectsWithNewArray:clearOld:0x10df5a28c从CURRENT原VM.objects复制引用到OLD，
不是clone模型。needReloadForFeedStateChange=true且NEW非空时先丢OLD并清该flag
（0x10df5a31c），NEW空保留flag。clearOld=true或OLD空直接NEW；否则移除旧
refreshModel，NEW非空时在OLD index0插当前refreshModel（0x10df5a3b8），结果NEW+OLD
（0x10df5a3cc）。NEW空时只去掉旧separator而保留旧卡。完整builder不重新赋旧卡
track/timestamp/report_flush_idx，也不reset曝光池；其他writer/运行时行为另证。

combined count>=101才先prefix100（0x10df5a400），再调用evenNumbersArrayWithDataArray
（0x10df5a418）；<=100不调用。该selector stub0x10df5b2d4经machine-verified
0x10f835540→0x117185340实际到_pad helper0x10df5b2d8。helper按当前pegasusCloumn、
每个model.cellclass.cellSizeType、累计行宽和已完成prefix边界裁剪，并非简单count%2。
raw size1/2累计1/2，恰好column宽记录当前位置并清宽，超过则保留前一完成边界；
raw size4或refreshModel在不完整行时提前结束，其他情况可记当前边界。BannerList清宽且
完成边界递增1，不能直接等同循环index。空数组或无完成边界可返回nil，否则稳定prefix；
不排序、不改report字段，不推断raw size4的业务名称。关键累计/边界地址为0x10df5b4ac–0x10df5b4d4，nil返回0x10df5b548、prefix返回
0x10df5b578–0x10df5b584；结论仅适用本样本静态实现。


WatchLater sheet的contentView来源也有具体witness：MoreAction.SheetModel witness
0x11b1273a0的+0x20→0x101119974→0x10112f630，分配本模块ActionSheetContentView，
返回contentView witness0x11b127870（0x10112f6b8）。其+0x10→0x10112de98，
确把安装callback写入ActionSheetContentView.clickItem（0x10112ded8）。实际UIKit
method table入口tableView:didSelectRowAtIndexPath:0x10112e55c→0x10112f500
（0x10112e5dc），取IndexPath.row、校验当前items边界、读取该item，clickItem非nil
才调用（0x10112f5a8）。由此闭合row点击→弱controller→dismiss animation completion→
live controller.clickItem→MoreAction ordinal→Store确认/工具栏action。
动画helper的完成投递时序未运行；不把页面显示/菜单构造当成已选择或已经发送clear HTTP。

### HD2 notice 第二按钮的安全页面路由

showLoginWiredView0x10df1aa08每次新建NoticeView；当前type1取wiredInfo.location，
其他取title，再重读type==1作isDiffPlace（0x10df1aad0）。第二UIButton的control raw0x40
经throttle0.3（0x10df53708/0x10df5371c）→弱view发送enterSafeSignal
（0x10df53f58）；outer将signal交main scheduler→弱outer callback0x10df1b4e8。
callback重新读取当前type：1使用固定https://passport.bilibili.com/mobile/index.html；
2读取当前wiredInfo.url，要求非nil但没有空String长度门禁；其他返回。
BFCBusModel设置url后，以main/login_diff_place调用BFCBusMagiSystem，validator=nil
（0x10df1b5ec）。该完整callback不hide notice、不调用notice/close；页面路由并不代表
服务端安全处理成功，后续页面实现仍另证。


WatchLater上游实际管理按钮也已定位：MainVC.lazy manageButton0x1011251e0，作为
navigationItem.rightBarButtonItem.customView装入（0x101123c38–0x101123c78）。
绑定0x1011249bc取得同一按钮，以control raw0x40调用Rx helper0x105028f14
（0x1011249d0/0x1011249d8），订阅callback0x10112579c（0x101124a34），disposable
存页面bag。callback读live manageButton.isSelected：true→MainAction族0xa0 raw7
hideToolBar；false→raw5 showManagementSheet，交当前Store.slot+0x98（0x10112580c）。
raw5 reducer0x101115354先managementSheetShown=true（0x101115370），创建
AnonymousObservable、producer0x10110f67c（0x1011153b8/0x1011153c4）；Store订阅才呈现sheet。
raw6 batchManagement则清managementSheetShown并把当前分支isToolShown=true。
所以管理按钮、row选择、确认、请求是分开的实际阶段；按钮为selected时点击只退出工具栏。
完整账号变化处理与页面外部销毁/取消边界继续核对。


### HD2 follow_mode 响应持久化与 Logout 清理

MainVM.feedStateChangeWithDic0x10df5b62c由刷新/分页成功在原VM上调用；weak VM=nil时
ObjC调用自身无效，因此此方法内共享写入不能列入nil VM仍执行的清单。非空dic且能映射
FeedStateListModel时shared FeedStateManager.setFeed_mode（0x10df5b6b0）并
needFeedStateSetView=true（0x10df5b6bc）；空dic置该Bool false（0x10df5b6d4），
且仅当前followState==1时原VM.feedStateExitViewNeedShow=true、shared.followState=2
（0x10df5b6f0/0x10df5b6fc）。独立设置页选择/提交链见后段；选中推荐卡的实际按钮创建/注入仍待证。

FeedStateManager是once0x120c97ff0/global0x120c97ff8；init0x10df070b0创建固定
NSUserDefaults suite字面量feed_state_userDefaults（0x10df070f4/0x10df070f8），不拼MID。
setFollowState0x10df07158仅incoming不同于RAM+8才写RAM、setInteger key
kBBHD2PegasusFeedStateType（0x10df07188）并synchronize；getter0x10df0719c在RAM非0
复用，否则每次integerForKey（0x10df071c0）。needFeedStateSetView的Bool缓存规则类似：
相同值setter不写，true复用、false重读defaults。feed_mode getter在RAM对象非nil复用，nil时
读归档key kBBHD2PegasusFeedStateSettingKey（0x10df0727c）并unarchive；setter0x10df072d0
每次strong存、归档/setObject/synchronize（0x10df07340），nil传nil。
所以响应follow_mode可以落本地固定suite，后续MainVM.loadData/loadMore读取shared.followState（0x10df58d08/0x10df5a5e4），
仅raw1→请求recsys_mode=1，其余raw0/2→0（0x10df58d18/0x10df5a5f4）；
不是把followState直接发成follow_mode，follow_mode是响应键。
缓存零/false不能解释成默认无条件磁盘零；未读取任何实际defaults内容。

outer账号observer mask6只接Logout2/Update4，前述Logout2且hasLogin=false分支
0x10df1a85c实际向shared FeedStateManager发clean。索引nearest symbol的clearButtonPressed
曾有误导；machine branch0x10f8425c0→0x117254620确为_objc_msgSend$clean。
followState==1只决定前置toast，不限制common clean调用。clean0x10df07120依序
setFollowState0（0x10df07134）、setFeed_mode:nil（0x10df07140）、
setNeedFeedStateSetViewfalse（0x10df07154）。整数/Bool setter仍受RAM相等门禁，不能把clean
描述为无条件强写全部defaults；此Logout分支先读取followState。该固定suite的清理边界不代表
所有账号Change8都收到此observer，也不证明旧请求取消或曝光池转移。

管理按钮Rx physical绑定补足：0x105028f14创建订阅producer0x105029288→0x1050290b0，
weak control有效才创建ControlTarget（0x105029174），传入捕获controlEvents raw0x40。
ControlTarget.init0x1050074b8把callback和events存入自身，并实际向control
addTarget:action:forControlEvents:，action=eventHandler:（0x1050075c8）。这是物理事件注册；
订阅disposable取消的target removal与eventHandler forward仍需沿各自body核对。


管理按钮事件与dispose现已闭合：ControlTarget.eventHandler:0x105007268要求callback非nil、
weak control仍有效，调用callback（0x1050072dc）；该订阅安装callback0x10502995c发
next(Void)，进页面管理回调。返回disposable0x105029990→0x105029834解除retainSelf，
weak control有效时removeTarget:eventHandler:forControlEvents（0x105029898），
再把ControlTarget.callback函数/context清零（0x1050298b8）。这里取消的是UI target绑定，
不能套用为BFCApiRequest的HTTP cancel；list网络包装仍是NopDisposable。

### Locale 元数据的具体 HTTP/Moss 采用范围

公共producer/cache/LocaleRegionService witness见上节；具体注入key0x1204c28e8解析为
Inject<LocaleRegionService>。BaseInterceptorModule在334-class inventory index69
（0x120272a98），conformance0x1182514b0/witness0x11b0a8018的+8→0x10008dc3c→
registrar0x10008e010。registrar将LocaleRegionService作为flag0单绑定（0x10008e098），
HttpApplicationInterceptor/ApiGatewayInterceptor.Type/GRPCInterceptor分别flag1多绑定
（0x10008e114/0x10008e190/0x10008e20c）。API/GRPC exact keys0x120276370/0x120276378
接既有ApiClient.moduleInitialize的registerClass（0x1049bea30）及Moss.moduleInitialize
的registerGateway（0x100151914/0x100151920），不是只凭类名推断启用。
184-runnable inventory index36（0x120273d90）执行0x10008de7c，也把相同once MetadataStore
经BFCDeepblueWrapper virtual+0x70真实setter0x10505e5ec赋到localeRegionService。

API gateway interceptor0x10506436c取当前gateway.request，nil直接返回；非nil解析
LocaleRegionService并调用witness+8（0x105064480），遍历headers→
URLRequest.setValue(_:forHTTPHeaderField:)（0x105064b38），写回gateway.request
（0x1050644ec）。相同名称覆盖先前request header。native HttpApplicationInterceptor
另有witness0x11b3476f0，+0x10→0x105063ed8→0x105063d68，取request.urlRequest，
同样调用Locale witness+8（0x105063e4c）并用同setter，最终setUrlRequest（0x105063e98）。
两个body未见host过滤，但入口/transport选择仍限制覆盖范围。

Moss interceptor0x105064530调用Locale witness+0x10（0x105064644），获取metadata map，
与existing gateway.extraHTTPHeader合并，producer同名值覆盖旧Any或新增（0x105063f90），
setExtraHTTPHeader（0x105064744）。这个map值类型混合：x-bili-locale-bin是Foundation.Data
（0x105060024/0x105060038），x-bili-metadata-ip-region与
x-bili-metadata-legal-region是String（0x105060158/0x105060294）；可选值缺失时省略/移除，
不是全部raw bytes，GRPC consumer这里也没有再base64。现有native defaultAutoRPC正常路径
最终addEntriesFromDictionary到callOptions.initialMetadata（0x115e09110/0x115e09124），
所以gateway同名元数据在该阶段又覆盖早先callOptions，再构造/start unary；gateway-response
fastpath不启动unary。未读取实际locale/region或身份值。

范围限制仍显式保留：BFCApiRequest.build在ktorRequestEnable=true时跳过API gateway
（0x116095ab8/0x116095b48）；旧task runner0x1000aae78在requestType2跳native application
遍历，其他type才调用该集合witness+0x10（0x1000aaf88）。这两项是不同门禁，不从旧type2
或wrapper赋值推断独立Ktor/KMoss/GrpcEngine拥有相同metadata plugin。之前经过gateway的
URLRequest可带已有headers，独立Kotlin consumer仍继续核对。


FeedState代理选择的局部行为也已闭合，物理UIButton绑定仍未定位：MainV2代理
0x10df3dcbc在SelectedModel、event等于right_button_event且当前未登录时，调用
Navigator.login（0x10df3ded8）直接返回，不移除卡。不属于该分支时要求CURRENT
VM.objects.containsObject(model)，随后以indexOfObjectIdenticalTo取得index，调用VM
clickFeedStateCellWithModel:event（0x10df3de20）。VM返回true时代理手动
collectionView.deleteItemsAtIndexPaths（0x10df3de74），false不做该删除。
VM0x10df5b71c在SelectedModel且shared.followState!=1时比较left/right event；
right匹配写followState1（0x10df5b95c），移除CURRENT objects中的同一模型。
返回true的移除用isUpdateDislike=true包住setObjects再恢复false
（0x10df5b828/0x10df5b850/0x10df5b864），对应代理手动删除；right匹配的false支路
setObjects不包该flag（0x10df5b890），交一般objects订阅重载。这两个完整body没有
API/RPC/tryLoadData；更改影响下一新建API的recsys_mode，不等于按钮立即请求刷新。
MainApi.params的recsys_mode写入在firstRequestInfo merge之后（0x10df57334），
因此这里对象Bool覆盖更早同名firstInfo值，之后player params merge及公共拦截器另有边界。


### WatchLater 列表实际行点击与 URI 来源

TableViewAdapter.tableView:didSelectRowAtIndexPath:0x101107d08先调用super
（0x101107dfc），再向selectPublisher发送当前IndexPath（0x101107e44）。
ListVC绑定0x10111b00c读取该publisher并订阅callback0x10111f04c→0x10111cb2c
（0x10111b14c）；订阅closure捕获页面，disposable存bag。callback读live tableView的
allowsMultipleSelection（0x10111cb68），通过当前Store.slot+0x80取得状态快照
（0x10111cb90），按页面pageTab查当前分支items，不使用请求发起时的旧items。

普通模式先校验当前分支与row边界，读取所选Item.targetURLString；只要求Optional非nil
（0x10111cdfc），完整分支未检查String长度。随后deselectRow:animated=false
（0x10111ce2c），BFCRouter.shared.processUrl:animated=true（0x10111ce90），
再报告main.later-watch.video-card.0.click，扩展avid来自所选Item.aid
（0x10111cfe8/0x10111d074）。Item mapper0x10110a3f0→0x10110bd00将
JSON uri映射targetURLString（0x10110be34–0x10110be64）；初始化该Optional为nil
（0x10110aee4）。这与Response.play_url映射到分支playbackURLString、工具栏播放
当前分支的入口不同；router后续解析/播放请求不从此callback推断。

批量模式同样读取当前分支items；row对应Item.cardType的bit0为0才派发
（0x10111ccc4），bit0为1或分支/row不成立则只取消选中。派发携带该Item.aid，
ListAction族0x40低位4，即tag0x44（0x10111d0c4/0x10111d0dc），交当前
Store.slot+0x98（0x10111d0f0）。不把这个选择action直接等同deleteItems或HTTP删除；
该回调完整body没有请求构造、网络发送或ACK处理，选择状态reducer继续单独核对。

### HD2 卡报告时间精度与请求局部序号

CardBaseModel.getCurrentTimestamp0x10df9166c读取NSDate.date
（0x10df9168c）、timeIntervalSince1970（0x10df9169c），FCVTZS截断为signed64
（0x10df916a0），以静态%lld格式生成String（0x10df916b4）。单位epoch秒，
没有乘1000、单调计数、随机盐或请求generation。刷新callback0x10df59978与分页
callback0x10df5af0c在解析每卡时分别调用并写report_timestamp_str
（0x10df59a94/0x10df5b028）；items子卡按同callback分别取时，banner_item则复制
父timestamp（0x10df185ec）。此处没有读取或输出实际运行时日期值。

CardPool转换每次将raw ordinal归零（0x10df17fc0）；刷新与分页均将ordinal+1写
report_flush_idx，没有加当前objects.count或page offset。因此这个字段是请求内原数组
位置，不是组合显示列表下标或跨分页递增序号。保留旧卡仍保留旧报告字段；同一epoch秒
解析的卡可得到同timestamp，不能用它单独认定唯一请求代际。完整曝光标识还依赖
track/ordinal/app状态，静态精度结论不代表已观察到运行时标识碰撞。


ListAction raw4的状态consumer0x101112a7c按tag族0x40/低位4跳到
0x101112c64，重新查state当前页分支；缺分支走空结果返回。命中后读取该ListState，
对其+0x40集合调用0x10111fc38（0x10111315c），helper对incoming aid作hash查找：
已有元素直接返回false（0x10111fcc8），缺失则copy-on-write插入
（0x10111fcf4），并写回集合；之后0x101110fd4存回页分支（0x10111318c）。
所以这一行“选中”事件是幂等添加aid，不是同一action切换选中/取消；取消选择走另一个publisher/action，见下段。此分支没有删除effect或请求ACK。


取消选择则由TableViewAdapter.tableView:didDeselectRowAtIndexPath:0x101107e9c
向deselectPublisher发送IndexPath（0x101107fa0），ListVC订阅安装
0x10111b218→0x10111f094→0x10111d1ac。只有live tableView允许多选才继续
（0x10111d1fc），重新读当前Store/current pageTab/items及row，取当前Item.aid
（0x10111d3c4），派发ListAction tag0x45（0x10111d3d8/0x10111d3f0）。
状态consumer低位5分支调用集合helper0x10111ff74（0x101112f68）：查aid缺失则返回
nil且不改集合（0x10112003c），命中copy-on-write并移除对应bucket
（0x101120028→0x1011211a8，count减1写入0x1011212f0），存回分支。
因此选中/取消分别为集合插入/移除，均不发送删除HTTP；删除仍由另述确认效果执行。


### Kotlin 翻译设置与 alwaysTranslate 派生状态

KntrTranslation真正export由classadapter0x1205b5858指向instance table
0x11ccf97b0：alwaysTranslateFlowIOSAsync→0x10be39c4c、alwaysTranslate→
0x10be39f20；static table0x11ccf97e0的translation/shared分别到
0x10be3992c/0x10be39abc。不是同名KotlinSelectorsHolder占位方法。
Bool adapter调用0x105c2fc5c→0x105c2fbd4，读取Translation.+0x40派生flow，
接口hash0x901 slot0取底层flow、hash0x406 slot0取boxedBool，并解包+8
（0x105c2fd28）。不能直接把alwaysTranslate等同用户开关值。

Translation singleton init0x105c2f148使用TypeInfo0x11b4c7490，global
0x120c5d8d8；namespace为translation、key为user-enabled，+0x20保存
SerializableSharedPreferencesProperty（TypeInfo0x11b3b6550）。构造0x1053e183c
后读取delegate0x1053e1d98（0x105c2f34c），初始Bool转MutableStateFlow
（0x105c2f370），保存userEnabled到+0x28（0x105c2f414）。该initializer未拼MID。
setter0x105c2f870读取+0x28当前Bool，同值直接返回（0x105c2f960）；不同才记录
Localization日志并用hash0x487 slot1更新flow（0x105c2fb98），不直接写+0x40。

userEnabled的apply1 collector TypeInfo0x11b4c75d0、table0x11be471a8→
0x105c30154→0x105c2ff5c；实际emit0x105c30264读取incomingBool与singleton.+0x20，
调用property setter0x1053e1fa0（0x105c30348）。后者序列化0x1053a680c
（0x1053e206c），将backing、key和serialized value交0x1053e2a2c
（0x1053e2070）。这闭合flow到存储property更新调用；最终native后端见下段，持久化完成
时序另证，不声称setter返回时已落盘。

alwaysTranslate初始值由0x105c31040计算（init0x105c2f424），apply2 collector
TypeInfo0x11b4c77d0/table0x11be47368→0x105c3063c→0x105c30744，收到
userEnabled后重算（0x105c307b8）并更新派生flow（0x105c3080c）。独立locale collector
0x105c30bfc也重算（0x105c30c68）并更新同flow（0x105c30cbc）。计算函数在缺省
参数时重新取Translation.userEnabled和Localization.current：userEnabled=false→false；
current等于Localization.SYSTEM→false；否则调用locale predicate0x105c1c2e0
（0x105c311e4），其配置匹配见下段。因此locale变化本身也可能更新派生Bool，
再影响此前VBPreferences订阅/LocaleCache，而非只有用户toggle产生变化。

UI侧共用setter0x10a49f6ec同时比较当前locale与userEnabled，仅两者都相等才跳过
（0x10a49f818）；不同则先调用Localization setter0x105c20e68
（0x10a49f848），再调用Translation.userEnabled setter0x105c2f870
（0x10a49f878）。两个具体closure0x10a4a66cc/0x10afc45d4已接到此helper，
但UI注册、按钮label与完整设置页触发仍待证，不把任意closure存在视作用户实际操作。

海外guidance另有export classadapter0x1205cbc08/table0x11cd100a0，构造selector到
0x10bf248d4→0x105758f10（0x10bf24b94）；Swift0x102afa7d0传入title/pic/bullets/
tip/buttontexts/settingsURI/onDismiss。其onDismiss0x102afabac→0x102afaa0c只在
weak guidance有效时调用外部可选callback、dispose popper并置nil；完整body没有写上述
翻译设置。实际guidance按钮的Kotlin action继续另证。


### WatchLater 页面返回检查与列表重拉的边界

MainVC ObjC method table0x11f8dd9a8的viewWillAppear:0x101124bac、
viewWillDisappear:0x101124ec8、viewDidDisappear:0x101124edc共用helper
0x101124ef0：先调用super，再调用utility.isPopbackWithViewController:record:
（0x101124fc4），record raw分别1/4/8。此helper不派Store.refetch、未调用Account
getter/observer或请求cancel；super与页面外部账号处理仍另证。

viewDidAppear:0x101124e98→0x101124bc0的record raw2检查为true时进入
0x101124cb8，创建MainActor Task；async global0x12030b420首relative指针到
0x1011277ac→0x101125f44。Task调用utility.checkingWidgetStateFor:from:completionHandler:
（0x1011260cc），For raw1、from为main.later-watch.0.0.pv。callback0x101126358
将error交throw continuation、成功可选guide交resume。成功续体0x10112620c要求weak
MainVC有效，再写alertGuideModel（0x101126268）；错误续体0x1011262f8抛出，外部
Task错误处理未闭合。此body不派列表action、不处理Account；widget引导完成并不等于
列表回执或换号重拉，账号通知是否关闭/重建外层页面继续保持未证。


### 独立 Kotlin Locale hook 的 Ktor 采用与覆盖门禁

这条来源是KLocale/GLocaleImpl/LocaleCache，TypeInfo分别0x11bb48190/
0x11bb480f0/0x11bb48410，initializer0x10aae8140/0x10aae910c写global
0x120c6cc80/0x120c6cc88。尚无它是Swift MetadataStore adapter的证据。
Root GInterceptor id58的成员getter0x10b9213fc读root+0x1d8，constructor
0x10b9324a8/0x10b9324b8装SwitchingProvider id67，branch0x10b93c71c→
0x10aae7184。id58在0x10b93c880/0x10b93c888解析该成员并加入此前已接
CommonParamsPlugin的18成员collection，仍受Enable GInterceptor=true门禁。

provider TypeInfo0x11bb47c50/table0x11c353bf8→0x10aae79dc创建Lambda
0x11bb47ef0→0x10aae7eb8，构造RequestHook名locale、callback0x11cb41dd0
（0x10aae7f6c→0x105d53940）。callback TypeInfo0x11bb482d0/table
0x11c354440→0x10aae9400；实际RequestHook chain callback执行0x105d53470，
返回request后继续chain（0x105d5356c）。Locale callback clone MutableRequest
（0x10aae9484），读KLocale经0x10aae85c8取得序列化String（0x10aae94d0），
以virtual+0x108写header x-bili-locale-bin（0x10aae94f8），不是URL参数。
沿已证toRequest$1/header setter0x10a9b285c，仅Enable header write once显式true且
原header已存在时保留；缺失/false则替换。不能把native无条件setValue规则套到此门禁。

serializer0x10aae86d0结果非nil时调用byte编码helper0x10528e34c
（0x10aae8688），nil则返回静态空String（0x10aae86a4）；callback写header前无
非空检查。编码helper准确变体/换行规则见后段；这里
空String fallback也不同于native Data nil遗漏。

独立binary producer TypeInfo0x11bb47e30→0x10aae7d1c创建0x11bb48230，
factory0x10aae92bc读原始bytes（0x10aae935c），nil→nil metadata，非nil创建
KBinaryMetadata0x11b4cd2e0并设置同header名与bytes（0x10aae93b8/0x10aae93bc）。
Root getter0x10b926814读+0x600，constructor装id195；六producer集合branch
0x10b93e5ac解析此成员并构造collection（0x10b93ed64）。该集合到GrpcEngine的具体注册见下段，不外推全部KMoss/stream请求。


Translation property最终backing也已接到NSUserDefaults：constructor0x1053e183c
用namespace translation调用0x1053e0058（0x1053e1904），后者将namespace存
native wrapper.+8，classref0x11f7b5c10确为NSUserDefaults，调用initWithSuiteName:
（0x1053e02f0），结果存wrapper.+0x10（0x1053e034c）；nil构造会trap。
writer0x1053e2a2c先经0x1053e20c0检查options，再对同wrapper defaults调用
setObject:forKey:（0x1053e2c10），key=user-enabled，object为此前序列化结果。
此具体namespace/key链没有MID成分；外部clear与实际落盘时序仍未证。

alwaysTranslate末predicate0x105c1c2e0经0x105c1c0fc读取配置key
 dd_localization_language_config（getter0x1053df890）；缺失/空String返回EmptyList
（0x105c1c1c0），非空JSON经serializer0x105315994与decode0x1053a6cac，
已检查的可接受decode异常也回退EmptyList（0x105c1c2d4）。predicate顺序遍历row，
跳过row.+8=nil，以当前NSLocale.localeIdentifier作exact比较（0x105c1c488），
第一个匹配返回row Bool byte+0x20（0x105c1c4b0），无匹配返回false
（0x105c1c4b8）。重复配置first wins，缺配置并非默认true；这是配置标识匹配，与此前
Localization.SYSTEM对象比较门禁不同。配置row准确JSON字段名见后段，未读取实际配置值。


binary集合的实际consumer也已闭合：上述六producer branch是id194，constructor
0x10b9369dc/0x10b9369e4存root+0x648，getter0x10b926d1c读该字段
（0x10b926d74）。其Locale首成员的id195 branch0x10b93ee40调用
0x10aae7714（0x10b93ee54）。CommonHeader注册branch分别读ASCII getter
0x10b92675c、binary getter0x10b926d1c（0x10b93e9dc），交0x10aa2a850
（0x10b93e9f0）；generated provider TypeInfo0x11bb2f070保存两collection
（0x10aa2a914）。hash584 getter0x10aa2b0e0创建wrapper0x11bb2f290，解析两个
getter后存wrapper.+0x10/+0x18（0x10aa2b244）。沿此前factory0x10aa2c178逐个
解析producer，实际CommonHeaderInterceptor binary loop0x10aa42570/0x10aa425a8
调用Locale producer，非nil metadata经GrpcMutableRequest virtual+0xc8
（0x10aa425cc）写MutableHeader.binary。由此证明该GrpcEngine common-header链
采用独立Kotlin Locale bytes；未证明其他platform/Moss/stream engine的全部路径。


AiTranslateConfig的准确schema也已定位：token0x11c62bc80→0x11c62bc60→
0x11c62bc40/0x11c62bc20→0x11c62bc08，KClass TypeInfo0x11b4c3c90，serializer
0x11b4c3dd0的descriptor initializer0x105c1ac44声明四个optional key：
language_tag、support_ai_translate、ai_translate_title、ai_translate_sub_title。
deserializer0x105c1b2d4→0x105c1b960在缺字段时默认nil/false/nil/nil，对应
row.+8/+0x20 Bool/+0x10/+0x18。因此上述predicate取第一个language_tag与当前
localeIdentifier exact匹配项的support_ai_translate；首匹配缺Bool也为false，不继续找
后续重复true。这只解码schema/default，不读取实际配置row。


### HD2 follow配置来源与设置页提交触发

MainApi.modelDescriptions0x10df575e4明确/data/items为required NSDictionary array
（0x10df57634），/data/config为optional非array NSDictionary（0x10df5766c），
/data/config/auto_refresh_time为optional NSString（0x10df576a8）。成功callback
读取config（0x10df5915c）的follow_mode（0x10df59174），调用原VM.feedStateChange
（0x10df59354）。JSON键是follow_mode，本地manager属性才叫feed_mode；这些body不走
Moss RPC，服务端实验/决定发送字段的原因无法从客户端静态样本证明。
FeedStateListModel.modelContainerPropertyGenericClass0x10df06e44只映射
option→BBHD2PegasusFeedSettingModel（0x10df06e70/0x10df06e90）；SettingModel
value为qword（0x10df06f94），selected为byte（0x10df06fb4）。

FeedSettingVC.viewDidLoad0x10df076e0从shared.feed_mode.option浅复制数组
（0x10df077a0/0x10df077c0）；followState1且value1、或followState0/2且value0时才
置selected=true（0x10df07888），其他模型此初始化不清false，不能推唯一选中。
随后直接读suite的kBBHD2PegasusNeedFeedStateSetView（0x10df078e0），true才重新取
CURRENT feed_mode.option并setDataArray（0x10df07930），false不填此数组。
init0x10df07664设置disableAutoLoadData/disableAutoKVOObjects/disableShowingEmptyStatus
true；不从基类名称推它自动请求option或填默认列表。

真实tableView:didSelectRowAtIndexPath:0x10df07c84校验row<count，逐项selected=false
（0x10df07d5c），重读当前array/row并置选中项true（0x10df07dd4），reload后只写
selectedModel（0x10df07e00）。此回调不持久化followState、不请求。
viewDidDisappear0x10df07a20在selectedModel非nil时才提交：chosen.value1→state1；
value0且旧state1/2→state2；其他→state0，最后shared.setFollowState
（0x10df07b20）。读取旧state在消失时（0x10df07a8c），不捕获row点击时状态。

MainV2.bindVM0x10df3b564注册feedStateObseve0x10df3a138，KVO followState经
 distinctUntilChanged→skip1（0x10df3a22c/0x10df3a240），owned scoped disposable
（0x10df3a2cc）。callback0x10df3a49c先更新弱原VC显示；manager CURRENT state非0
且needFeedStateSetView=true才继续。state1另写CURRENT VC.viewModel.flush4
（0x10df3a4fc）；state1/2均写CURRENT VM.needReloadForFeedStateChange=true
（0x10df3a520），再scrollToTopAndRefreshData（0x10df3a530），不捕获旧VM。

该helper实际BaseCollection0x10dee8450先animated滚顶，再main dispatch_after0.3s
（0x10dee8510）；block强持原VC并延迟取它的collectionView，调用
bfc_triggerPullToRefresh（0x10dee8580）。MainV2 bind0x10df3aec4装handler
0x10df3b6e4（0x10df3af50）；具体collection override0x10deebf44仅尚无refreshview时
创建并装handler（0x10deebfd4），已有不替换。trigger0x115f5bf54先state1/startAnimating
再state2；setState0x115f5d410仅旧1→新2且handler非nil才调用
（0x115f5d4b4）。弱原VC有效时handler读取CURRENT VM→tryLoadData
（0x10df3b728/0x10df3b738），BaseVM0x10df02780先置tryLoaded，isLoading=true直接
返回，否则loadData（0x10df027bc）。设置commit/KVO不绕loading门禁、不取消在途请求，
也不保证立即新发送；下一次允许load才重新读当前followState形成recsys_mode。

物理TopView gesture安装0x10df4e0cc/0x10df4e0dc→action0x10df4e558，登录时路由
/main/feedsetting（0x10df4e598），未登录时Navigator.login（0x10df4e5bc）。但是HD2
FeedSettingVC注册0x10def14a8/0x10def14c0使用不同literal /pegasus/feedsetting；另一个
/main/feedsetting注册0x10f50afd8–0x10f50aff0的class是BBPhoneSetThemeViewController。
没有证到两URL别名/模块覆盖关系，故不能把TopView tap宣称已进入上述HD2设置页。
设置页row→消失提交→KVO→pull→tryLoadData链独立成立，真实路由激活范围仍待证。


HD2 idx的配置归属：BBHD2PhonePegasusConfig class0x1200420a8继承
BFCPreferences0x1202710f0；property table0x11df94b38中pegasusFeedIndex为Tq,D,N，
即动态Int64。configName0x10df8648c固定BBHD2PhonePegasusConfig；shared
0x10df863f0为once/global0x120c980d0，未按MID分实例。defaultConfig0x10df86498将
pegasusFeedIndex默认值写为String "0"（0x10df864f8/0x10df864fc），不是NSNumber0；
列数默认值另为NSNumber4（0x10df865cc）。沿此前通用BFCPreferences.userDefaults
0x1167d4ccc，configName→initWithSuiteName:（0x1167d4cfc/0x1167d4d14），可定位
固定suite；动态q getter/setter的IMP安装见后段，实际持久化完成仍待证。

刷新idx只在CURRENT objects非空且FIRST为CardBaseModel时读取首idx
（0x10df58bcc）→MainApi.setIdx（0x10df58bd8）；空或首非base才dataDM.read
（0x10df58c04/0x10df58c10），不扫描第一个兼容模型。分页只在非空且LAST为base时
读末idx（0x10df5a69c/0x10df5a6a8）；空或末非base不fallback磁盘，也不setIdx。
MainApi.init0x10df56cd8只调用super并初始化helper，未证此case的最终默认idx值；
不将刷新 fallback误套到分页。save入口0x10df2b6ec与read入口0x10df2b72c分开。


### FallbackCache Native export 与 nil expiry 的静态实现边界

WatchLater所用Swift桥有具体提供者：once0x1208e4d80→0x102124ed4调用
KntrFallbackCacheModuleKt.provideFallbackCache（0x102124ef0），保存对象global
0x1208e4d88；读写都复用它。实际classadapter0x1205cac48/static table0x11cd0f7f0
把此selector接到0x10bf16a58→0x1089bf32c（0x10bf16b04）。后者解析注入provider
再调hash0x587 slot+0x10（0x1089bf458）；下述Root绑定已闭合，外部override仍有边界。
NativeKt classadapter0x1205cabd8/static table0x11cd0f760把writeAsync selector接
0x10bf162f8、readAsync接0x10bf15c7c。writer捕获cache/scene/id/data/version/expiry，
lambda TypeInfo0x11b8606f0/interface0x981→0x1089b7940，实际调cache的hash0x1d300
slot5（0x1089b79dc）。因此不是ObjC占位类的方法名证据。

该接口的已定位实现FallbackCacheImpl TypeInfo0x11b8614f0、interface table
0x11c100e50/witness0x11c100e20，slot5=0x1089bb458，读slot2=0x1089bb5ec。
writer wrapper取instance.+8 manager→0x1089bc61c→coroutine0x1089bc350→emit
TypeInfo0x11b861b10、hash0xc81→0x1089bdb2c→0x1089bd3b4。它构造
CacheMetadata0x11b860ef0：version来自参数，timestamp为当时epoch毫秒
（0x1089beee4；秒*1000加subsecond整除），expirationTime沿incoming Optional保留，
scene来自参数（0x1089bd86c/0x1089bd870）。没有把nil expiry换成600秒或其他TTL。
CacheMetadata serializer0x11b861030、descriptor initializer0x1089b948c的准确JSON
keys为version/timestamp/expirationTime/scene；timestamp与expirationTime optional，
version/scene required（0x1089b959c/0x1089b95b0/0x1089b95c4/0x1089b95d8）。

read wrapper0x1089bb5ec→0x1089bc74c→emit TypeInfo0x11b861db0/hash0xc81→
0x1089bdcd8。解析CacheEntry后取metadata.expirationTime：nil直接跳过年龄判定
（0x1089be140→0x1089be278）；非nil仅CURRENT epoch毫秒严格大于stored expiry才
进入失效分支（0x1089be150/0x1089be154），等于仍通过。失效时调用后端删除
（0x1089be164→0x105cd7044）并构造非成功结果；后端/取消完整实现另证。
跳过expiry后仍比较stored metadata.version与read请求version
（0x1089be280–0x1089be298），不匹配另走失败分支。因此WatchLater nil expiry在这个
具体实现没有自动年龄失效，但并非永久保证命中：版本、内容/解析与其他删除仍能使读失败。
还需保持注入实现/覆盖范围边界，未读取实际文件、缓存内容、账号key或运行时日期值。

读结果类型有具体TypeInfo名：Success0x11b861150、Miss0x11b8611f0、
Expired0x11b861290、VersionMismatch0x11b861330。过期分支删除后构造Expired，
携带原metadata（0x1089be22c/0x1089be270）；版本不匹配同样先删除该path
（0x1089be2cc–0x1089be2d8），再构造VersionMismatch，保存请求version与stored
metadata.version（0x1089be3a0/0x1089be3e0–0x1089be3ec）。版本匹配才调用传入
deserializer，input为CacheEntry.data（0x1089be29c/0x1089be2a0/0x1089be428），
返回Success保存解析data和原metadata（0x1089be43c/0x1089be480）。这些不是任意
非成功均自动重试的证明；WatchLater Swift消费者的旧缓存/错误回退另有自身门禁。

metadata反序列化0x1089b99a8还有独立默认规则：required mask0x9要求version与scene
（0x1089b9fcc–0x1089b9fd4）；timestamp缺失时调用CURRENT epoch毫秒helper
（0x1089b9fdc–0x1089b9fec），expirationTime缺失时存nil
（0x1089b9ff0–0x1089b9ff8）。这不会给缺失expiry补TTL；同时，缺失timestamp得到
解析时刻不代表文件新写入。写metadata与读metadata默认分别发生在不同环节。

read异常cleanup有额外类型门禁：exception TypeInfo.+0x5c的值落入raw
0x3e4–0x49e范围才进入已核Corrupted路径
（0x1089be504–0x1089be510/0x1089be6dc–0x1089be6e8），部分路径先删除当前file
（0x1089be520/0x1089be6f8），构造CacheResult.Corrupted TypeInfo0x11b8613d0并
保存exception（0x1089be790–0x1089be7a0）。范围外走rethrow
（0x1089be7a8），尚未将该raw类型范围命名为所有IO/解析/取消错误；不是所有异常
都会被吞成缓存miss，也不能仅由cleanup推断某次运行时文件已删除。

### FallbackCache 的 Root 注册、文件后端与取消边界

export使用的key0x11c93d4d0有具体Root registration
（0x10b92bb3c–0x10b92bb48），provider来自Root.+0x458（0x10b92bacc）。
constructor0x10b934c00–0x10b934c08安装SwitchingProvider id139；跳表分支
0x10b93e9fc调用getter0x10b924a9c，实际读Root.+0x450（0x10b924af4），
经0x1089b80a4→scope hash0x1501 slot+0x10（0x1089b814c）解析其provider。
该field是id140经cache wrapper0x1053450c0构造
（0x10b934ba0–0x10b934bb0），分支0x10b93e298实际调用factory0x1089bef90
（0x10b93e2a8）构造此前FallbackCacheImpl和manager。故是实际注入路径，
不是由唯一conformance猜实现；运行时scope/override仍不从静态注册排除。

factory初始化files库0x105cd8520，manager.+8保存global0x120c5dfd8
（0x1089bf0ac），此global由SystemFileSystem$1 TypeInfo0x11b4e0a70构造
（0x105cd858c/0x105cd85c8）。lazy目录callback0x1089bd08c调用
NSSearchPathForDirectoriesInDomains，raw directory13/domain1/expand=true
（0x1089bd15c–0x1089bd168），取首Caches候选后join固定list_fallback_cache
（0x1089bd240）；候选空或类型不符另有fallback，不猜绝对沙盒路径。
path helper0x1089bcf90用regex `[^a-zA-Z0-9._-]` 将匹配字符替换为 `_`
（0x1089bd044/0x1089bd05c），scene与id分别处理，id追加 `.json`；write path
0x1089bd7e4–0x1089bd938，read镜像0x1089bde34–0x1089bded8。
schema为 `<Caches候选>/list_fallback_cache/<sanitized scene>/<sanitized id>.json`；
未读取实际path/key/文件。同名sanitize可能产生碰撞，不宣称哈希隔离或完整路径防护。

0x1089bc248只是lockScene coroutine：0x1089bbebc先锁manager.+0x20 Mutex
（0x1089bc038），查询scene map，缺失构造Mutex（0x1089bc11c）并存map
（0x1089bc174），解manager锁（0x1089bc1dc）后返回scene Mutex。
write emit拿该Mutex并lock（0x1089bd5ac），等待可suspend
（0x1089bd5fc→0x1089bd750）。继续后检查/创建scene目录；mkdir后端
0x105cd90c8→0x105cd946c。sink helper0x105cd71ac（0x1089bd69c）以append=false
dispatch到0x105cda87c，选`wb`并fopen（0x105cdaa14），包装FileSink
TypeInfo0x11b4e0c90；再buffer为RealSink、写JSON String、close
（0x1089bd6a4/0x1089bd6e0/0x1089bd6f0）。RealSink.close0x105cd30d4先把剩余
buffer交FileSink write，再尝试close，最终C调用为fwrite0x105cdc8b4、
fclose0x105cdccb0；正常close后scene unlock0x1089bd744。
异常cleanup另close/unlock/rethrow（0x1089bdad8/0x1089bdb20/0x1089bdb28）。
该body直接打开目标文件，未见temp-file rename；不是原子替换或fsync持久保证。

read source slot8（0x1089be0b4）到0x105cda17c→fopen0x105cda310，包装
FileSource TypeInfo0x11b4e0bf0。buffer/read String
（0x1089be0c0/0x1089be0d0），解析JSON前close（0x1089be0e4）；具体fread
0x105cdc4b0/fclose0x105cdc704。此前过期/版本失败的delete helper0x105cd7044
以mustExist=true调slot2（0x105cd7088/0x105cd708c），具体0x105cd8954→remove
（0x105cd8ab4），目录另rmdir。读取与写入的真实IO已闭，实际文件内容未检查。

write coroutine在0x1089bc4e4调用context-change0x1052b32fc→Job校验
0x1052bf420→0x1052bfda0；Job非active取取消异常并throw
（0x1052bfe8c–0x1052bfe9c）。context来自shared KCoroutineScope，不按用途猜
Dispatchers.IO。此检查可阻止进入block，scene Mutex等待另有suspend边界；
具体同步write/close段0x1089bd604–0x1089bd6f0及C FileSink没有Job检查或token参数，
不能推取消会中断fwrite或恢复被`wb`截断的目标。此前Swift/native handle cancel调用
与这些协程门禁分开记录；静态调用证据不证明运行时取消完成。


### Kotlin Locale 的编码与独立缓存更新

Kotlin Locale编码选择global0x120c5a928的Base64.Default（TypeInfo0x11b37c8b0）：
init0x10528dbec在0x10528dd44将urlSafe/MIME两个flag清0，padding取enum-array
0x120c5a918.+0x20，即PRESENT/ordinal0（0x10528e1e0/0x10528e1e4）。encoder
0x10528e520–0x10528e52c选普通64字符alphabet，静态比对匹配A–Z、a–z、0–9、+、/；
tail写 '='（0x10528e614/0x10528e9e8），MIME=false分支0x10528e620使用INT_MAX
chunk bound，不插MIME换行。故具体HTTP helper0x10aae8688是标准padded Base64、无
换行；没有选择另存Default.+0x28/+0x30的UrlSafe/Mime实例。nil仍为空String。

独立GLocaleImpl init0x10aae8140创建自己的LocaleCache0x11bb48410和
CachedLocaleData0x11bb485f0，两LocaleInfo0x11bb48690初始六空String/Boolfalse，
立即refresh0x10aae966c（0x10aae83dc）。refresh读取Localization.SYSTEM getter
0x105c20cd0（0x10aae971c）、current getter0x105c20de0（0x10aae9750）；export表
0x11ccf9558/0x11ccf9570确到adapter0x10be37f10/0x10be38098并调用同两getter。
两个native locale分别经languageCode/scriptCode/countryCode helper
0x105c331c0/0x105c333b0/0x105c335bc转三String；Translation getter0x105c2fc5c
（0x10aae978c）提供此前派生alwaysTranslate，保存到CachedLocaleData.+0x18。
所以缓存Bool不直接等于user-enabled，且不是从Swift MetadataStore对象取。

观察安装读取localeFlow0x105c20d58（0x10aae8454）和alwaysTranslateFlow
0x105c2fbd4（0x10aae8494），combine0x1052f6704→drop1 wrapper0x1052ef5f0
（TypeInfo0x11b38c570，literal count1写0x1052ef6a4）。callback TypeInfo
0x11bb48550/table0x11c354600→0x10aae9a0c忽略incoming tuple并重读上述全部来源
（0x10aae9a28/0x10aae9a2c）。refresh以stlr替换缓存对象（0x10aae990c），请求serializer
0x10aae86d0以ldar读取一个snapshot（0x10aae8760–0x10aae8770），再从该对象读取
两LocaleInfo与Bool（0x10aae87b0/0x10aae87b4）。实际UI setter使用相同Localization/
Translation上游，但setter返回与观察刷新先后、实际延迟仍未运行验证；不是每个请求
同步重新读取所有设置，两个缓存实现也不因此统一。


### HD2 idx 的动态 Int64 getter/setter 与重新启动读取

BFCPreferences.processAllProperties0x1167d3798对属性type q/raw0x71
（0x1167d3b24/0x1167d3b28）选getter0x1167d429c和setter0x1167d431c
（0x1167d3b88/0x1167d3b90），动态缺method时class_addMethod
（0x1167d3c8c/0x1167d3d14），selector-map保存具体property key。
getter经_defaultsKeyForSelector→RAM _getObjectWithKey（0x1167d42d4）→
longLongValue（0x1167d42f0）；setter经同映射→NSNumber.numberWithLongLong:
（0x1167d435c）→_setObjectWithKey:value（0x1167d4378）。所以idx默认String "0"
确被转为Int64 0，保存idx为NSNumber，经此前RAM/UserDefaults writer复用；不是猜key名。

init0x1167d36c8创建RAM dictionary（0x1167d3734）并process properties
（0x1167d3780）；每property先userDefaults.objectForKey（0x1167d3d30），非nil优先；
nil才取defaultConfig匹配key的value（0x1167d3d8c）。非isNilValue时存RAM
（0x1167d3dfc），origin标记disk2/default1。随后getter只读RAM，不逐请求重读磁盘。
由此闭合保存idx→新实例初始化读固定suite→刷新builder fallback读取的静态链；
落盘完成、外部进程更新、注销清除仍未运行验证，分页无fallback分支仍保持区别。

### LanguageSettingsPage 的 Compose 生命周期提交

codegen有公开`bilibili://settings/language` route：URI array0x11cb99f80长度1，
element0x11cb99f90→KString0x11c871a20。collector TypeInfo0x11bbdf090/body0x10afc199c
复制array（0x10afc1a28），与static wrapper0x11cb99f98交registry hash18000 slot0
（0x10afc1ae8）。wrapper body0x10afc1b24返回DefaultFunctionWrapper，捕获
functionref0x11cb9a158，其body0x10afc1c08创建FunctionTarget
TypeInfo0x11b4c22b0，content取singleton0x120c6e8f0.+8（0x10afc1ca8），public name
LanguageSettingsPage（0x10afc1d6c）。content TypeInfo0x11bbdf3d0/body0x10afc2294
调用page0x10afc3e6c（0x10afc238c），再取singleton0x120c6e900.+8并经theme helper
0x1060a8bf8（0x10afc3ffc/0x10afc4018）到真实页面body0x10afc49d8。
这是route定义→target→render entry。实际collectRoutes binding也进入BRouterC：
DaggerSingletonC.BRouterCImpl.SwitchingProvider TypeInfo0x11bd18c90/body0x10b901e5c
读取raw ID（0x10b901ed0），table0x118652dd4 index33→0x10b902240，创建
Root_BRouterModule provider TypeInfo0x11bd1cfc0（0x10b90229c/0x10b9022d8），用
public key collectRoutes.7d76c4b2c1249142c1ac7c62036ddf0f981fa491
（0x11cc67c80/0x10b903bac）注册binding（0x10b903b58/0x10b903ba8）。provider body
0x10b94be58 alloc实际Lambda TypeInfo0x11bbdf270（0x10b94bed4），resolve captured
provider并保存context.+0x10（0x10b94bf5c/0x10b94bf64）。Lambda init0x10afc1e84
构造registry（0x10afc1f58/0x10afc1f5c）；get0x10afc1f94要求.+0x18非nil
（0x10afc202c），才registry hash782 slot4→hash10780 slot0执行static collector
0x11cb99f78（0x10afc2090/0x10afc20ec/0x10afc20fc）。不能只凭binding注册当已执行。

BRouterC constructor真实provider rawID33保存component.+0x120
（0x10b8eb53c/0x10b8eb540/0x10b8eb54c），getter0x10b901ab0读取该字段
（0x10b901b08），实际map assembly将其与同public key配对
（0x10b9046a8/0x10b9046bc）。外层BRouterCBuilder TypeInfo0x11bd162b0的build
0x10b8ea290 alloc该component并存parent/self（0x10b8ea30c/0x10b8ea34c）。Builder来自
SingletonC rawID122/table0x118652f3a index22分支0x10b93e990
（0x10b93e9a0/0x10b93e9a8），provider保存root.+0x3c0（0x10b934368/0x10b934370），
getter0x10b923fd4实际传入BRouterCore createBRouter provider TypeInfo0x11b4bd140
（0x10b93e7b8/0x10b93e7dc/0x105bef274）。生成provider工厂0x105bef1b0的
incoming x1 builderprovider保存在+8，incoming x0 context在+0x10
（0x105bef1d4/0x105bef1d8/0x105bef274），不把context槽误写为builder。
生成provider0x105bef790构造实际BRouterCoreKt_createBRouter_Lambda
TypeInfo0x11b4bcfc0（0x105bef80c），保存resolved builderprovider+0x10
（0x105bef950）。具体get0x105bee90c读此provider（0x105bee988），hash0x584
slot0取得实际Builder（0x105bee9d0/0x105beea08），捕获在coroutine
TypeInfo0x11b4bd300+0x20（0x105beee34）。coroutine0x105befa60取Builder
（0x105bf038c），hash0xfe00 slot0（0x105bf03d0）；实际Builder TypeInfo0x11bd162b0
itable0x11c5089d0的同hash→funcarray0x11c5089c0→上述build0x10b8ea290，
所以createBRouter静态路径确实构造含语言ID33 binding的BRouterC。
get自身要求lambda+0x30非nil（0x105beed5c），nil throw（0x105beeeac），
init0x105bee388必须先行；具体binding的init/get排序见后段，导航完成仍另核。

build返回交helper0x105345b94（0x105bf03dc），该helper以KClass0x11c52f4e0
→BaseGripperFetcher TypeInfo0x11b39c650求值（0x1053478e8/0x105345c04），
hash0x702 slot0（0x105345c58）。actual BRouterC TypeInfo0x11bd18bf0
itable0x11c50b710、entry0x11c50b730→funcarray0x11c50b708→0x10b901c20，
取component getter0x10b9002f8（0x10b901c88）再provider hash0x584
（0x10b901cdc）。这一步是取得Fetcher，不把helper当作已经执行所有route collector。
该getter读component+0x18（0x10b900350/0x10b900398）的SwitchingProvider ID0。
其branch构造34项Pair map（count34：0x10b9041d4/0x10b9041d8），语言Pair
（0x10b9046bc/0x10b9046c0）放element32（0x10b9047a8），map factory
0x1052838c8（0x10b9047b8）。对应34项TriggerBean list含同语言element32
（0x10b905d10），TypeInfo0x11b39cfd0公开类型名TriggerBean；该bean+8静态key
0x11c62adc0为CollectRoutes，+0x10为语言bindingprovider（0x10b905b94），
+0x18 rawflag1（0x10b905b88），不由名称推运行。list factory0x10522e81c
（0x10b905d24）。Fetcher factory receiver hash0x2a00 slot2（0x10b905dd8）
实际收到map x3/list x4（0x10b905db8/0x10b905dd0），组件类型KClass
0x11c6295a8→BRouterComponent TypeInfo0x11b4b9920。已闭具体collection成员与
工厂输入；其后具体执行链见下段，不等同已发生运行时导航。

createBRouter coroutine的hash0x4181 slot3 receiver是BRouteCentral
（interface TypeInfo 0x11b4c0200，0x105bf04d0/0x105bf04dc），不是ConfigurationImpl。
BRouterCore TypeInfo 0x11b4bd3c0保存central/configuration/BaseFetcher
（0x105bf0430/0x105bf046c/0x105bf0470）；DefaultRouteCentral TypeInfo
0x11b4c0280同hash slot3→0x105c04774，将Core存.+0x18（0x105c047e8），
lambda 0x11b4c0a40→0x105c0a168→coroutine 0x105c0998c读取Core.+0x18
（0x105c09a8c..0x105c09a94），以literal CollectRoutes调用Fetcher hash0x2500 slot3
（0x105c09ae4/0x105c09af4）。实际DefaultGripper 0x11bd12ff0→0x10b8d9d00
→TriggerExecutor.execute 0x10b8e43dc（0x10b8d9f08）→coroutine 0x10b8e3c7c。
它逐TriggerBean取provider（0x10b8e41a8），调用producer hash0x587 slot1
（0x10b8e4200），nil跳过（0x10b8e4208）；要求返回对象hash0x2c00，bean rawflag1
时再调用该接口并收集（0x10b8e4230..0x10b8e4260/0x10b8e4008/0x10b8e4028）。
语言bean已证raw1；后续0x1052b25dc/0x10b8db878（0x10b8e42b8/0x10b8e4320）
的跨binding等待语义仍另核，不称所有binding严格逐一完成。

语言binding的缓存wrapper不能省略：DSL tail经builder hash0x603 slot0
（0x10b9068bc）→0x10b8d78dc置byte+0x41=1（0x10b8d78ec）；finalizer
0x10b8d7a5c创建ContextProcessingProducer 0x11bd13830，其WrappedProducer
0x11bd12370捕获generated provider（0x10b8d7b94）。缓存分支包入
DefaultCacheableProducerNew 0x11bd14470，FunctionWithSubscribers 0x11bd145b0
保存function（0x10b8d7c8c），atomic reference保存wrapper.+8
（0x10b8d7c94/0x10b8d7c98），最终StaticSuspendProducer 0x11bd14310.+0x38
（0x10b8d7d84）。async方法0x10b8dc5ec→0x10b8dc90c→virtual+0xb0
（0x10b8dc948）→0x10b8dfdd8取.+0x38并调用hash0x405（0x10b8dfe4c）。
缓存invoke 0x10b8e0368读atomic state（0x10b8e063c..0x10b8e0648）；function-state
分支取function（0x10b8e0688）→0x1052157e8（0x10b8e07ec），该helper创建stack
adapter 0x11b36c6f0，保存function（0x105215860）并直接调用0x105216290
（0x10521589c）→captured function hash0x405（0x105216304）。
因此该分支接到ContextProcessingProducer 0x10b8dd1c0→coroutine 0x10b8dc978；
无context override路径取WrappedProducer（0x10b8dcc3c）并invoke
（0x10b8dcd74），其body 0x10b8d7dc8 resolve generated provider
（0x10b8d7e78）并调用语言Lambda hash0x405（0x10b8d7ed4）。其他atomic状态复用、
成功CAS及异常恢复尚未完整解码，不称每次CollectRoutes都会fresh注册。

实际语言Lambda 0x11bbdf270 invoke 0x1053466ec先virtual+0x98 clone
（0x105346770），具体0x10afc1da8分配同TypeInfo并只复制context.+0x10
（0x10afc1e18/0x10afc1e50/0x10afc1e54）。ProducerBase coroutine 0x105346840
依次调用clone virtual+0xb0 init（0x105346a58→0x10afc1e84）和+0xa8 get
（0x105346bf8→0x10afc1f94）；init存registry dependency.+0x18
（0x10afc1f5c），get要求非nil（0x10afc202c），通过registry hash0x10780调用
static collector 0x11cb99f78（0x10afc20fc）。collector 0x10afc199c最终route注册
hash0x18000 slot0（0x10afc1ae8）。首次函数执行的init-before-get及静态注册链已闭，
导航完成、通用竞争注册/替换和缓存后续状态仍是独立边界。

顶层BRouter get的具体冷/热调用也已闭。SingletonC ID121写入及cached provider存
root.+0x3d0（0x10b934470/0x10b934474/0x10b93447c/0x10b934480），getter 0x10b924144。
factory 0x105bef1b0通过builder cache slot0→0x10b8d78dc
（0x105bef37c）明确设置cacheflag，再finalize（0x105bef490）；其trigger slot4参数
0x11c356e70为empty String（0x105bef3dc），不能命名启动trigger。
SingletonC实际BRouter.EntryPoint interface 0x11b4b9aa0/hash0x488实现
0x10b929388调用root getter/provider/producer hash0x587 slot2
（0x10b9293f8/0x10b929450/0x10b9294a8）。具体StaticSuspendProducer slot2
0x10b8dc0ec先virtual+0xa0（0x10b8dc168）→0x10b8dffb0→cacheable hash0x2283 slot0
0x10b8e01a8，检测atomic state是否ValueHolder TypeInfo 0x11bd14510/hash0x155fa
（0x10b8e01fc..0x10b8e022c）。true走virtual+0xc0（0x10b8dc188）→0x10b8e00a4
→cacheable slot1 0x10b8e0278，返回已保存state.+8（0x10b8e0304），不新运行collector。
false取context（0x10b8dc1dc），创建AbstractSuspendProducer$get$1 0x11bd13650
（0x10b8dc288），捕获原producer（0x10b8dc2c4）→0x10b8e4940（0x10b8dc2d0）
→0x1053086e8（0x10b8e4ad4）。后者创建BlockingCoroutine 0x11b3917e0
（0x105308974），启动该lambda（0x105308b90），处理/等待state及mutex
（0x105308c4c/0x105308c6c/0x105308d00）。lambda 0x10b8dc838读原producer并调
virtual+0xb0（0x10b8dc85c/0x10b8dc874）→上述冷函数执行链，所以slot2不只是返回
未执行provider；等待线程策略、其他atomic状态与异常恢复仍另核。
正常函数返回的cache writer也有实证：0x10b8e0368把结果与singleton
0x120c5a8e8.+0x10比较（0x10b8e0798/0x10b8e07b4），相等绕过写入；非相等或nil
交0x10b8e0bfc（0x10b8e07bc/0x10b8e0830/0x10b8e0834）。writer分配同ValueHolder
0x11bd14510（0x10b8e0c88），把结果存.+8（0x10b8e0cc4），调用0x1052ae97c
（0x10b8e0cd0）以ldaxr/stlxr更新atomic state（0x1052aea44/0x1052aea50）。
所以ValueHolder存在不保证payload非nil；此正常返回写入不覆盖悬挂完成、异常或reset策略。
CollectRoutes实际产物亦持久存入central：0x105c0998c校验RouteCollectorImpl
0x11b4c0570（0x105c09be0/0x105c09be8），创建FinalRouterTable 0x11b4c04a0
（0x105c09c24），存central.+0x20（0x105c0a0cc）。central hash0x4181 slot2
0x105c062c4→0x105c0400c读取该字段，nil抛错（0x105c040b8）。尾部collector清理的
对象类型仍待核，不称路由cache清空，账号变化触发reset也尚未闭合。
实际KRouter$2 TypeInfo 0x11b4c17d0/body 0x105c0e178 resolve BRouter.EntryPoint
KClass 0x11c62b1a8（0x105c0e1f0）并调用hash0x488（0x105c0e244）。lazy initializer
0x105c0e020以static function 0x11c62b1b8构造lazy、保存global 0x120c5d740
（0x105c0e080/0x105c0e090），getter 0x105c0e0b8经once 0x120c726c8及lazy hash0x901
（0x105c0e0dc..0x105c0e0f8/0x105c0e148）取值。既有Guidance URI dispatch
0x105c0cce8路径调用该getter（0x105c0cd64），可迫使冷BRouter初始化并注册语言路由。
另一个实际caller 0x10692601c属Compose container构造callback 0x11b622290：
创建IosComposeContainerViewModel 0x11b620610（0x106925fac），取KRouter后URI处理
（0x106926050/0x106926058）→BRouter dispatcher hash0xfe80 slot4（0x106926114）。
具体URI来源/是否language、运行时导航完成和app启动时点均不由这些静态调用证明。

页面实际collect Localization.localeFlow（0x10afc4b40/0x10afc4b50）与Translation.+0x38
lazy flow（0x10afc4b8c/0x10afc4c18）。remember为空才用collected locale创建mutable state
（0x10afc4d1c/0x10afc4d28），Bool同样取collected value后box并remember
（0x10afc4e6c/0x10afc4e88/0x10afc4e90）；已有holder分支不自动覆盖编辑值。
该lazy producer0x105c30d00实际来自Translation$2 TypeInfo0x11b4c7bd0，读取singleton.
+0x28 userEnabled flow（0x105c30d8c），返回readonly wrapper（0x105c30d94）；页面初始
Bool来源因此是userEnabled，不能混作derived alwaysTranslate.+0x40。
Locale callback TypeInfo0x11bbe0050捕获holder（0x10afc5c74），传AppLanguageSettings
0x10afc5fe8（0x10afc5cd0/0x10afc5cdc）；实际invoke0x10afc4600只将incoming Locale
写captured holder hashb82 slot1（0x10afc466c/0x10afc46b4），没有立即调用全局writer。
随后事件`main.setting-language.option.0.click`（0x11cb9aaf0/0x10afc4788），单字段
text来自incoming Locale的native localeIdentifier（0x10afc46f8），不是已提交CURRENT值。

真实候选行callback TypeInfo0x11bbe0230捕获optional onSelect functionref及row Locale
（0x10afc6ea4），作为modifier callback交0x105819084（0x10afc6f0c/0x10afc6f10）。
其body0x10afcc3e4读functionref.+8，nil跳过，非nil hash981 slot0传captured row Locale
（0x10afcc450/0x10afcc454/0x10afcc45c/0x10afcc460/0x10afcc498/0x10afcc4ac），闭合到
上述local edit callback；候选列表来自已知固定七locale（0x10afc6a88），行Locale以virtual+0x80与incoming selected Locale比较
（0x10afc6d4c/0x10afc6d54/0x10afc6d58），enabled=比较结果XOR1
（0x10afc6ef0）；故已选行在此click modifier disabled。不把recomposition callback
0x10afcc4e8当onClick。
Bool callback TypeInfo0x11bbe00f0捕获另holder（0x10afc5e24），传AiTranslationSettings
0x10afc7be4（0x10afc5e84/0x10afc5e90）；invoke0x10afc47c4 box incoming Bool并写holder
（0x10afc4868/0x10afc48b4），也不立即写Translation全局。其同名点击事件
（0x10afc4990）单字段always_translate_switch按incoming非零→String1、零→0
（0x10afc4910/0x10afc4920/0x10afc4964）；这报告用户编辑值，不能当派生effective状态。
实际switch绑定已闭：AiTranslation helper0x10afcaa24将onChange装入Ref
（0x10afcab44），调用SimpleSwitch0x10afcc124→0x106c77a10，x1为该callback、w0为
页面当前Bool（0x10afcc0e8/0x10afcc110）。其具体callback TypeInfo0x11b658f80捕获
onChange与rendered Bool（0x106c789a4/0x106c789e4/0x106c789ec），以modifier callback
交0x1058191ec（0x106c78a58）。实际click body0x106c79b38要求callback非nil
（0x106c79ba4/0x106c79ba8），计算BIC(1,capturedBool)
（0x106c79bac/0x106c79bb4），box后hash981 slot0转发（0x106c79bbc/0x106c79c0c）；
页面forwarder0x10afcc5d4经optional Ref提取/再box/调用
（0x10afcc604/0x10afcc648/0x10afcc654/0x10afcc660/0x10afcc6b0）到0x10afc47c4。
这条实际控件action先反转rendered值，再写页面holder，仍需下述cleanup才提交全局。

compose0x10afc4f74创建并remember捕获两个可编辑state holder的callback，
以Unit key交0x1054378bc（0x10afc501c），构造DisposableEffectImpl
TypeInfo0x11b3bdc40。RememberObserver table0x11bd63438/hash0x1901的slot2
0x105439674调用effect（0x10543975c），保留cleanup到+0x10；effect callback
0x10afc447c创建cleanup0x11bbdffb0并复制两个holder。slot1 0x1054397a4在cleanup
非nil时调用其hash0x4680→0x10afc4558（0x10543984c）再清nil，slot0
0x105439888不执行cleanup。这是effect离开composition的提交，不据此推某具体按钮
独占写入或精确iOS导航/消失时序。
cleanup读取holder CURRENT locale（0x10afc42f0）与Bool（0x10afc4394），交此前
common setter0x10a49f6ec（0x10afc45d4）；捕获的是可变holder，不是初始值快照，
且Unit key不随locale/Bool值本身重新key effect。same-value门禁仍有效。

既有用户翻译guidance另有真实Button writer：构造0x10a4a4ee0创建callback
TypeInfo0x11bab9dc0并remember（0x10a4a4f78），将其与content交Material3 Button
helper0x1059ef600（0x10a4a5020），helper内TypeInfo0x11b490280/0x11b4903c0
对应Button$2/$3。callback0x10a4a65bc先报告
main.homepage.translation-popup-olduser.translation.click（0x10a4a6670），再读fresh
Localization.SYSTEM经0x105c20cd0→0x105c1ea9c与captured Bool holder当前值
（0x10a4a66b4/0x10a4a66c0），调用common setter（0x10a4a66cc），再调用关闭callback
（0x10a4a671c）。不是无条件写true，也不同于Swift guidance.onDismiss的无writer分支。
content外层label与config来源由下述schema/map链定位，事件名不替代可见label证据。

实际提交用的captured Bool holder有独立初始化/编辑链：outer.+0x40 holder来自
0x105460c00（0x10a4a0894），初值为静态boxed Bool true
（0x11cd1e280.+8），不读Translation.userEnabled。Column$3 callback
TypeInfo0x11bab9be0捕获同holder（0x10a4a3878），经modifier callback安装
（0x10a4a38e4→0x105819084）。invoke0x10a4a6044读当前Bool、XOR1并写回holder
（0x10a4a6070/0x10a4a60b0/0x10a4a6104），只改变本地编辑state；draw读取同holder，
最后translationButton callback0x10a4a66c0读取当前值后common writer才进入持久链。
用于config A/B选择的outer.+0x38是另一个默认true holder，不能混作翻译开关值。

guidance内部两config对象的schema已定位为ExistingUserGuidanceData
TypeInfo0x11baba0e0，serializer0x11baba180。descriptor init0x10a4a6f94–0x10a4a705c
列9字段：title、desc、tip、iconUrl、confirmButtonText、cancelButtonText、
gotoSettingsText、gotoSettingsUri为required；langChineseName optional。
deserialize0x10a4a7570以required mask0xff校验（0x10a4a7f88–0x10a4a7f94），
前8依次写+8/+0x10/+0x18/+0x20/+0x28/+0x30/+0x38/+0x40
（0x10a4a7f98–0x10a4a7fa4），第9缺失存nil到+0x48。
ExistingUserGuidance$1捕获derived config state；invoke0x10a4a174c按当前Bool state
选configA或configB。Button content0x10a4a6754取选中config.+0x28
（0x10a4a685c）交Text，故实际label为confirmButtonText。另一settings callback
0x10a4a6b84读config.+0x40→0x105bd1508→0x105c0cce8，然后关闭guidance
（0x10a4a6bf8），未见Translation writer。helper0x105bd1508构造StringUri
TypeInfo0x11b4b8620（0x105bdae24），再0x105c0cce8经0x105c0e0b8/
0x105be8440/0x105be9764到BRouter dispatcher hash0xfe80 slot4（0x105c0ce50）。
这是路由派发；实际provider/target/成功回执仍待核，callback未检查派发结果便关闭。
两config外层来源继续核对；下述locale-keyed map链不把export位置参数直接套入内部schema。

两config的实际上游是远程配置key `dd_localization_existing_user_guidance`
（0x11cad07b0）。getter0x10a4a8e08→0x1053df890（0x10a4a8ec8），以token链指定
Map<String,ExistingUserGuidanceData>，decode0x1053a6cac（0x10a4a8f20）；缺失/blank
退EmptyMap，decode exception最终处理仍待核。Native builder的A取map中的localeA
localeIdentifier键（0x10a4aff48；key helper0x10a4a8b50）；B则取fresh
Localization.current的localeIdentifier（0x10a4afff8/0x10a4b0070）。要求A/B均非nil
（0x10a4b06a8/0x10a4b06ac），把两对象存render closure.+8/+0x10
（0x10a4b0858），callback0x10a4af664→ExistingUserGuidance调用0x10a4af980。
因此pair来源是按locale查map；localeA准确来源由后述lazy list闭合。B.langChineseName在render
前被写入（0x10a4b068c），这些config对象不能一概称为immutable快照。

map decode的catch只在raw TypeInfo.+0x5c减0x3e4后小于0xbb时记录日志并退EmptyMap
（0x10a4a8fec/0x10a4a8ff4），其他异常rethrow（0x10a4a9004），不称全异常容错。
A helper0x10a4a8b50遍历Localization.+0x10 lazy list（0x105c20c48），首个candidate
以virtual+0x80 equals fresh SYSTEM（0x105c20cd0→0x105c1ea9c）成立便返回；
无匹配退Localization.+8 lazy getter（0x105c20bc0，0x10a4a8db0）。list和fallback
公共名称及其producer另沿lazy初始化核对；B的current getter
0x105c20de0仍与SYSTEM 0x105c20cd0分开。

fallback lazy0x105c211d0→Locale.Companion getter0x105c1c990，实际读Companion.+0x10
（0x105c1c9ac）对应lazy0x105c1cfc4、公开固定tag `zh-Hans-CN`
（0x11c62bd70）。不要误套相邻.+8的zh-CN producer0x105c1cee0。
list lazy0x105c212a0构造7项（0x105c214b8/0x105c214c4–0x105c214d0），依次getter
0x105c1c990/0x105c1ca18/0x105c1caa0/0x105c1cb28/0x105c1cbb0/0x105c1cd48/
0x105c1cdd0分别读Companion.+0x10/+0x18/+0x20/+0x40/+0x48/+0x60/+0x68，
对应zh-Hans-CN、zh-Hant-HK、en、ja、es、pt、ar。故A是该固定候选list中首个等于
concrete SYSTEM的Locale，无匹配退zh-Hans-CN，B仍是当前用户所选current。

SYSTEM本身另有具体lazy producer：Localization.+0x18 lazy由function object
0x11c62c130/TypeInfo0x11b4c4eb0接0x105c21528，getter0x105c20cd0；不是七项
候选列表或直接取current。producer取得standardUserDefaults（0x105c2164c），以
公开key `AppleLanguages` objectForKey（0x105c217dc）保存旧对象，再
removeObjectForKey（0x105c21a00）。随后resolve cached service0x120c5d8c0并
调用hash0x11180 slot0（0x105c21b48），以raw index0交0x105c1ff7c
（0x105c21b54/0x105c21b58）；此helper仅取返回wrapper.+8的get(index)，
没有已证空数组fallback。旧对象非nil才在正常返回路径setObject:forKey恢复
（0x105c21db0）；旧对象nil跳过恢复（0x105c21b6c→0x105c21dec）。异常/finally
恢复尚未证，不能称always restore。这里只分析静态body，未执行或读取真实defaults。

该service initializer0x105c2ebb8直接分配createPlatformLocaleDelegate$1
TypeInfo0x11b4c7f90；itable0x11be47950的hash0x11180接0x105c339b8。实现对
NSLocale调用preferredLanguages（0x105c33afc），按原iterator顺序逐tag构造
NSLocale.initWithLocaleIdentifier（0x105c33dfc），转Locale wrapper
（0x105c33e64）并append（0x105c33e70–0x105c33e7c），最终列表放wrapper.+8
（0x105c33ee0）。因此这里SYSTEM取临时移除覆盖之后的首preferred language，
七项匹配/回退是之后guidance helperA的独立步骤。restore后的0x105c32784
已查前段为UIView.appearance.setSemanticContentAttribute raw3
（0x105c32870/0x105c32960），后续UINavigationBar appearance；不是已证Locale
observer刷新。SYSTEM lazy的外部reset和OS语言变化通知路径仍待核。

Localization.current的存储及回流另已闭：initializer0x105c2042c以namespace
`localization`、key `custom-locale`（0x11c62c0c0/0x11c62c0f0）构造
SerializableSharedPreferencesProperty（0x105c20638），保留到.+0x30/+0x38；
共同backing constructor0x1053e0058使用NSUserDefaults.initWithSuiteName。
这段构造不加入MID，不能据此否定其他账户清理writer。启动缓存byte0x120c5a4e1
来自initializer0x105c31e74读取UIDevice.userInterfaceIdiom，计算raw!=1
（0x105c320e8/0x105c32120/0x105c32124/0x105c32138）。byte==1时current初始
读property→MutableStateFlow（0x105c2068c/0x105c20698），否则取上述fallback
getter（0x105c206b8），flow存.+0x40（0x105c20784）。未读取真实偏好值。

current setter0x105c20e68首先要求该缓存byte==1（0x105c20f4c/0x105c20f50），
再以Locale.equals比较incoming与flow当前值，同值返回（0x105c20fbc/0x105c20fc0）。
变化才写flow hash0x487 slot1并调用platform apply0x105c322cc
（0x105c211a0/0x105c211a8）。后者取incoming localeIdentifier
（0x105c324c4），向standardUserDefaults.AppleLanguages写单元素数组
（0x105c324e4–0x105c324f4、0x105c325e0），再调用appearance helper
（0x105c32614）。这是标准defaults的语言覆盖，另有suite中的序列化存储；
这些body没有替换.+0x18 SYSTEM lazy。启动对旧zh-CN匹配时转zh-Hans-CN
并经同一setter（0x105c207e4/0x105c208dc/0x105c208e8），迁移仍受此门禁；
其他分支直接应用当前Locale（0x105c20870）。

current flow的apply collector TypeInfo0x11b4c4ff0接emit0x105c22e5c，取fresh
singleton.+0x38（0x105c22ef4），交共同writer0x1053e1fa0（0x105c22f24），
再0x1053e2a2c到native setObject:forKey；不宣称同步落盘。反向collector
Localization$6/0x105c23054取.+0x30.property.asFlow（0x105c230c0/0x105c230c8），
以consumer TypeInfo0x11b4c5330→0x105c23110接收，旧zh-CN替换zh-Hans-CN
（0x105c231b8/0x105c2320c），调用同一setter（0x105c2324c）。同值比较阻止
相同Locale反复写flow，未见该callback的generation/account检查。

propertyflow0x1053e1a44→0x1053e05b0→SharedPreferences$asFlow$1
TypeInfo0x11b3b62d0/body0x1053e0718，给backing.+0x10注册
addObserver:forKeyPath:options:context（0x1053e0c44，raw options3/context nil）。
listener TypeInfo0x11b3b6370/body0x1053e0dd4 reload当前value
（0x1053e25d4，call0x1053e10a4），交captured producer hash0x407 slot6
（0x1053e1108）；awaitClose注册cleanup（0x1053e0ce4），cleanup0x1053e1188
removeObserver:forKeyPath（0x1053e15d0）。这条观察suite localization/custom-locale，
不是已证SYSTEM/AppleLanguages的OS语言变化通知；具体ObjC KVO adapter仍可另核。

KntrLocalization实际adapter0x1205b5548的instance exports表0x11ccf9540仅四项
localeFlowIOSAsync/SYSTEM/current/setCurrent:；该表未导出SYSTEM setter/reset。
current setter另外两组大量调用分别来自NumberFormat preview callback
0x107d52930→0x107d585f0（TypeInfo0x11b77be60、vector0x11c060500）及
DateTimeFormat preview callback0x107d55890→0x107d2266c（TypeInfo0x11b77c720、
vector0x11c060d18），package均kntr.base.localization.preview。其生产UI可达性
未证，不能当账户/配置监听writer。以上有界body未替换SYSTEM lazy，仍不宣称
全应用没有间接reset、OS通知或账户触发路径。

公共query另有实时Locale producer，与binary LocaleCache分开。TypeInfo
0x11bb42390的provideCLocaleGNetPublicParam$1/function object0x11cb3ed70接
0x10aac4474，每次读取fresh Localization.current、Locale String getter
（0x10aac4518/0x10aac4520→0x105c1ded4），以公开key c_locale
（0x11cb3ed80）交Param factory0x105d52fe4（0x10aac4538）；value nil退nil，
非nil存Param.+8/+0x10（0x105d5304c/0x105d53098）。s_locale sibling
0x10aac49f0每次读SYSTEM（0x10aac4a94/0x10aac4a9c），key0x11cb3edb0；
SYSTEM自身lazy仍缓存，producer再次调用不等于刷新OS语言。

Locale String getter0x105c1ded4读每个Locale.+0x10 lazy，接Locale$1
TypeInfo0x11b4c4910/body0x105c1df5c。它拼languageCode（0x105c1e168），scriptCode
非空时加`-script`（0x105c1e054），countryCode非空时加`_country`
（0x105c1e104），组合0x105c1e17c/0x105c1e18c/0x105c1e19c。因此不是裸
languageCode，schema形状为language[-script][_country]；未输出真实设备值。
各Locale对象有自己的String lazy，c_locale producer每次取当前对象，服务缓存不
固定语言值。

NetPublicParam constructor0x10aac220c只存function object到.+8
（0x10aac22b4），实际hash0x13180 slot0→0x105d52e20每次invoke所存producer
（0x105d52e80/0x105d52ed0）。CommonParamsPlugin loop0x10a9aca6c明确调用
hash0x13180（0x10a9acd00/0x10a9acd38），nil跳过、existing query key则保留
（0x10a9acd08/0x10a9acd40/0x10a9acd7c/0x10a9acda8）。c_locale实际collection
绑定见下段；公共hook启用时，后续hook执行会读新current，无需该对象自己监听flow。
DI已接SingletonModule provider0x11bb41250/static0x11cb3e6a8→DSL定义
0x10aabecd4→lambda0x11bb41ad0→constructor0x10aac220c；实际Root注册也已闭：
DSL body0x10aabec18的调用0x10b93c74c位于SwitchingProvider ID44分支
0x10b93c738，jump table0x118652e72的index44 UInt16=0x166、base0x10b93c1a0。
constructor以ID44包装provider并存Root.+0x120（0x10b9318d0/0x10b9318d4/
0x10b9318e0），getter0x10b920374。实际11-member public-param collection的ID40
分支0x10b93cb18调用此getter、resolve并保存结果
（0x10b93cb6c/0x10b93cb74/0x10b93cb78），写array element3
（0x10b93cc30/0x10b93cc34）；count11 header0x10b93c09c/0x10b93c0a0、arraybase
0x10b93cc48，经factory0x10522e81c（0x10b93d788）形成集合。该ID40 provider存
Root.+0x170（0x10b931df8–0x10b931e00），getter0x10b920aa4。

CommonParamsPlugin的实际Root分支0x10b93d2d0取同collection getter
（0x10b93d2ec），以x1交0x10a9ab6fc（0x10b93d318/0x10b93d324）；generatedprovider
TypeInfo0x11bb1d9c0捕获collection provider到.+8（0x10a9ab7cc）。factory0x10a9ab9cc
invoke该provider hash0x584 slot0（0x10a9abacc），把resolved collection存concrete
lambda TypeInfo0x11bb1da60的.+0x10（0x10a9abb80）。所以c_locale不是仅存在DSL定义，已经接CommonParamsPlugin factory捕获集合；
该集合实际进入commonParamsPlugin$publicParam$1，TypeInfo0x11bb1dc60/callback
0x10a9ade68（methodvector0x11c32c2e0）。构造处取原lambda.+0x10/.+0x18后swap并存
callback.+8/.+0x10（0x10a9abcd8/0x10a9ac320/0x10a9ac324），故callback.+0x10正是
上述11集合。callback每次读.+0x10、取iterator（0x10a9ae2b4/0x10a9ae35c），逐binding
hash0x587 slot2产实际NetPublicParam并收集（0x10a9ae37c–0x10a9ae3a8），再转换/组合
（0x10a9ae4b8/0x10a9ae4c4）；hook最终request采用仍按此前公共执行门禁。
invoke0x10a9abca4在
0x10a9abce0实际读取lambda.+0x20作为迭代集合，不能把0x10a9abe18–0x10a9abe24的
另一dependency转换当作.+0x10公共参数集合消费。它与GInterceptor 18-member集合
分开。s_locale也在同collection的zero-based element4：ID45 provider存Root.+0x128
（0x10b931958/0x10b93195c/0x10b931968），getter0x10b92042c；ID40集合分支调用
getter、resolve，写element4（0x10b93cb84/0x10b93cb8c/0x10b93cc38）。ID45分支
0x10b93d234→DSL0x10aabee80（0x10b93d248），binding0x11cb3e770接generatedprovider
TypeInfo0x11bb412f0/factory0x10aac0ca8→concrete lambda TypeInfo0x11bb42010。
其槽0x11bb420b8→0x10aac39e4把static function object0x11cb3ed78存NetPublicParam.+8
（0x10aac3a84/0x10aac3a8c），接已证SYSTEM producer0x10aac49f0。因此两query均是
实际集合成员，s_locale重复执行仍读SYSTEM lazy。不能宣称所有HTTP/Moss/Ktor请求
均采用该集合或绕过现有enable门禁，OS locale reset仍未证。

公共callback产物到执行loop也已连接：plugin构造0x10a9abca4创建configure callback
TypeInfo0x11bb1dd00（0x10a9ac330/0x10a9ac338），将上述publicParam function存.+8
（0x10a9ac378），以CommonParamsPlugin name和createClientPlugin helper 0x105d3f61c
构造（0x10a9ac394）。configure actualbody 0x10a9b200c分别通过0x105d3eaac注册
TransformRequestBodyHook（TypeInfo0x11bb1dda0/0x11b4f23d0，0x10a9b20e0）、
RequestHook（0x11bb1de40/0x11b4f2290，0x10a9b2144）和Send
（0x11bb1dee0/0x11b4f1bd0，0x10a9b21ac）。第一actualcallback 0x10a9ae500在条件
分支读取publicParam function（0x10a9ae784），接口hash0xa01 slot0调用
（0x10a9ae9f8..0x10a9aea08）到具体0x10a9ade68；返回producer collection保存在x22
（0x10a9aea0c），交wrapper 0x10a9ac72c（0x10a9aea30），wrapper保持collection
（0x10a9ac754/0x10a9ac888）并调用fillloop 0x10a9aca6c（0x10a9ac894）。
RequestHook sibling也有直接fillloop调用0x10a9af354。因此实际公共集合→provider解析→
注册callback→参数执行loop已闭合；此前CommonParamsEnable/typed tag/method/content/
rpc门禁仍适用，configure callback创建不等于所有client都运行其hook。

### Phone 推荐设置页的点选写入与 recsys_mode 三层值

具体设置列表行的tapMethod是`pushToHomeConfigVC`：MainVC.init 0x10f2fea38调用
getMainSettingDatas（0x10f2fea58），再super.initWithDatas（0x10f2fea84）。构造body
0x10f307a84中，该行title/vcTitle取SettingsRes.string189
（0x10f3085f4/0x10f308628），detail合并getFormat和inline自动播放描述
（0x10f308658/0x10f30866c/0x10f30868c）；CFString0x11d208390存值栈.+0x10e0
（0x10f3086f4/0x10f3086fc），公开tapMethod key 0x11d2082d0存对应key栈.+0x10a0
（0x10f308704/0x10f308708），count8 dictionary（0x10f308780）加入行数组
（0x10f308798），最终settingModelWithDic→yy_modelWithJSON（0x10f30c024/0x10f323940）。
海外Teen whitelist也明确包含相同resource189（0x10f30b934/0x10f30b944），不把配置
运行值或所有用户可见性视为已知。

通用cell物理手势实际安装在0x10f32f2c8的contentView，self为target、tapClickGesture:
为action（0x10f33090c/0x10f330914/0x10f330954）。BaseVC取CURRENT datas[row]并安装
weak-self tapBlock（0x10f2fe600/0x10f2fe704）；gesture.state EXACT3
（0x10f330a04/0x10f330a08/0x10f330a0c）才tapClickCell，将CURRENT cell.model交block
（0x10f330b74/0x10f330b90），block保存tapCellModel再didSelectCell
（0x10f2fe7bc/0x10f2fe7cc）。MainVC.didSelectCell 0x10f2ff590读model.tapMethod→
NSSelectorFromString（0x10f2ff5cc），respondsToSelector=true才performSelector
（0x10f2ff5ec/0x10f2ff5fc）。该具体selector 0x10f3070e4先直接上报
`main.setting.setting-layout.0.click`（0x10f307100/0x10f307108），再创建
BBPhoneSetThemeViewController（0x10f307138/0x10f30713c），以animated=true push
（0x10f307150），这条入口不走router。Theme.init 0x10f2f28d8仅super.init及pv/highlight
初始化，没有本body的isThemeMode赋值；普通ObjC新实例零初始化使该Bool默认为false
是此处静态推论，未冒充一次setParams调用或运行时值。独立存在的
pushToPegasusFeedRecommandSettingVC 0x10f301740仍未找到其具体row绑定；新闭合的
物理入口不据此填补该方法来源或HD2路由alias。

`/main/feedsetting`已注册的BBPhoneSetThemeViewController虽名Theme，实际有推荐
设置分支。setParams0x10f2f29a4读公开 `isThemeMode` Bool
（0x10f2f29ec/0x10f2f29f0→0x10f2f2a14）；另 `setting` 只接highlight
（0x10f2f2a4c），不把class名字当仅主题页。_prepareDatas0x10f2f32c4在
isThemeMode=false（0x10f2f32f0/0x10f2f32f4）构造推荐sections；只有manager.
isDisplayFeedModeSetting及VC.feedModeArray.count>0（0x10f2f3808/0x10f2f3824）
才加入PegasusRes.string214作标题的section（0x10f2f3884）。viewDidLoad
0x10f2f2d24在manager显示门禁true时取feedModeSettings→setFeedModeArray
（0x10f2f30e8/0x10f2f3110/0x10f2f3128）。cell配置从feedModeArray[row]取value
（0x10f2f44b4/0x10f2f44d0），以CURRENT isFollowFeedMode XOR (value!=1)写
isSelected（0x10f2f44d8/0x10f2f44f4/0x10f2f44f8/0x10f2f4500）。value1在follow
时选中，所有非1值在非follow时选中；响应若有重复/非标准value，不保证唯一选中。

FeedModeSetting.setup0x101b8983c向BBListPegasusEventDispatcher注册raw26 callback
（0x101b898a8→0x101b8a388→0x101b899f8）。callback要求payload dictionary.
follow_mode可转非空dictionary（0x101b89ab4/0x101b89b14），经Model.yy_modelWithJSON
（0x101b89b6c）成功才helper0x101b8a3ec并setDisplay=true
（0x101b89b98/0x101b89bcc）。helper保持Model.option原索引顺序逐项创建
BBListPegasusSettingObject，写title/desc/value
（0x101b8a5a0/0x101b8a600/0x101b8a620），最后setFeedModeSettings
（0x101b8a6dc），这段循环不写isSelected、不排序去重。接受的Model可含空option，
display=true仍需前述VC.count门禁；不是服务端selected字段决定选择。
missing/空payload或转换失败的两条fallback，在CURRENT feedModeSetting==1时
updateFeedMode(0)（0x101b89c54/0x101b89c90、0x101b89d14/0x101b89d50），
随后setDisplay=false（0x101b89cc0/0x101b89d80）；这里的input0不要套物理取消input2。
raw26完整网络producer及账户重置边见后文。helper还将Model.yy_modelToJSONData
交feed_mode文件writer（0x101b8a420/0x101b8a47c→0x104e298d0），namespace见后文；native createFileAtPath返回Bool被丢弃（0x104e29ae8），不据调用断言落盘成功。

tableDidSelect0x10f2f5614当前section标题匹配该资源（0x10f2f5a20/0x10f2f5a48）
才进入此branch，先全部item.isSelected=false（0x10f2f5ab4，真实stub
0x10f87a0b8→0x1175bd980），再row项=true（0x10f2f5b30）。chosen.value==1
调用updateFeedMode(1)（0x10f2f5b60）；value==0且CURRENT isFollowFeedMode=true
（0x10f2f5b94）则updateFeedMode(2)（0x10f2f5ba8/0x10f2f5bac）；value0但非follow
或其他value不调用writer，但均reportRecommendWithOption(row+1)
（0x10f2f5bc0）。这是点选即时提交，与HD2 settings页disappear提交分开。

manager.updateFeedMode0x113cee678把input1转cachedPegasusDeviceConfig.mode的
Int64Value.value=2，其余input转value=1（0x113cee744/0x113cee74c）；与旧PB.value
相同便返回（0x113cee75c），不同才setValue、uploadConfig
（0x113cee768/0x113cee770），之后发公开
BBPegasusFeedModeSettingDidChangedNotification（0x113cee7f0），userInfo为
`value`:NSNumber(original setter input)（0x113cee7a4/0x113cee7cc）。这条notification
紧随uploadConfig调用返回，body没有等待upload业务成功的门禁；实际持久化/失败策略
另查。随后logEvent UserPreference FeedMode Setting，info为原input.stringValue
（0x113cee838/0x113cee844）；same-PB gate跳过upload/notification/log全部。

getter feedModeSetting0x113cee5c0要求cachedConfig、hasMode及mode.hasValue
（0x113cee5d8/0x113cee5f0/0x113cee614），PB.value==2才返回1
（0x113cee630/0x113cee638），其他或缺值返回0；isFollowFeedMode
0x113cee5a4→0x113cee5ac比较该结果==1。Swift首页builder取shared.isFollowFeedMode
（0x101a32d74/0x101a32d8c），转ASCII `1`/`0`（0x101a32da4），写
`recsys_mode`（0x101a32de8/0x101a32e04）。因此setter input1、PB2、wire1三层
不同；取消关注input2写PB1、wire0，不能直接把input2或PB2作为请求码。下次新API
读此getter。FeedModeSetting另注册上述NSNotification
（0x101b899b4–0x101b899d4），destructor移除observer（0x101b8a28c）。receiver
0x101b8a1cc→0x101b8a794仅在userInfo.value可cast Int时，向同一dispatcher发
raw27、payload单Int数组、d0=0（0x101b8a7fc/0x101b8a86c/0x101b8a8ac/
0x101b8a8c4/0x101b8a8cc）；缺值/类型失败返回。Home实际刷新消费者及账号/
服务器更新边见下段，不能把notification或raw27派发本身当刷新请求已发。

RefreshHelper实际注册raw27/flag1（0x101b65a50/0x101b65a54），callback
0x101b6911c→0x101b663b8只接受payload首项可cast Int且EXACT==1
（0x101b66400/0x101b6640c/0x101b66410），weakHelper存活才调用0x101b646e0。
因此UI取消input2及fallback/logout input0不经这条consumer刷新。helper在
pegasusIsShow=true时取operator.+0x30、reason5并dispatch
（0x101b646fc/0x101b6471c/0x101b64774/0x101b64778）；未show时，配置
mode_switch_refresh_exp getter0x101b63054仅Int2返回raw2，匹配才先operator.+0x60
再.+0x50、同reason5（0x101b6472c/0x101b64758/0x101b64768），否则仅置
followStateChanged=true（0x101b6479c）。viewWillAppear到0x101b638a8消费延后标志，
优先级为userHasChangeFormat→rcmdStatusChanged→playStyleManualChanged→follow。
follow获胜才operator.+0x30/reason5（0x101b63ab8/0x101b63ad0/0x101b63ad8），
dispatch后ALL四flag清零（0x101b63980/0x101b6398c–0x101b639a4）；高优先变化可
以其他reason消费followflag，不保证每个flag各发一次请求。

MainVM的operator.+0x30绑定0x101a5c464→0x101a4fa88
（0x101a4939c/0x101a5c474），沿已闭collectionView/!loading/0.3s/header refresh
链；.+0x50绑定0x101a5c404→0x101a4893c（0x101a492e8/0x101a5c414），仍受loading
准入；.+0x60绑定0x101a5c424→0x101a4f1f8（0x101a49324/0x101a5c434）。准入后
0x101a550b0 alloc新MainApi、保存reason（0x101a550ec/0x101a55100）；builder表
0x1182c9138的qword index5=4，故reason5→wire flush4，recsys_mode仍独立读取
CURRENT manager（0x101a32d8c），不从通知input直接生成。

raw26实际config producer包括normal refresh0x101a5b3b0更新VM.config后取当前
config作payload[0]并publish（0x101a5b554/0x101a5b5a8/0x101a5b5bc/
0x101a5b5dc/0x101a5b5e4），fallback cache0x101a54878同样更新/publish
（0x101a54938/0x101a549c0/0x101a549c8），loadmore0x101a55088亦然
（0x101a55448/0x101a554e4/0x101a554ec）。因此options及缺失follow_mode回退不只
由新网络refresh结果触发；callback未校验account generation，真实跨账号行为未运行。

feed_mode本地JSON的namespace witness0x11b175230+8→0x101b8a330返回
feedmodesetting；路径helper0x104e2a030取NSSearchPath raw9/userDomain1首路径
（0x104e2a050/0x104e2a080）追加/com.bilibili.list/（0x104e2a0bc），再namespace/
feed_mode（0x104e29c08/0x104e29c2c/0x104e29bac），构造中无MID输入。
已有文件先remove再create，未证原子写或成功ack；它与Universal PB选择存储分开。
账户observer注册mask0xa（0x101b89978），但consumer0x101b89d94仅incoming
EXACT2（Logout，0x101b89ddc/0x101b89de0）且CURRENT模式==1才读此文件，取首
option.value==1的title或资源254回退（0x101b89e30/0x101b89e64/
0x101b89f54/0x101b89f58/0x101b89fa4），showCenterToast后updateFeedMode(0)
（0x101b8a10c/0x101b8a138/0x101b8a13c）。incoming8不会执行此reset，mask10
不等同两事件都重置；该body不清文件、不setDisplayfalse/清options。实际setup实例安装见下段；
这些文件读取不等于首次本地options恢复。

实际MainService.setup0x101b85a58把FeedModeSetting静态object（0x12034eff8）
放入plugins array（0x101b85d88/0x101b85d98/0x101b85da8），witness
0x11b175260的+8→0x101b8a310→setup0x101b8983c（0x101b8a320）。plugins setter
0x1035a4050先存array，再按40-byte existential顺序调用各witness.+8
（0x1035a408c/0x1035a40d8），因此已接实际订阅安装。0x101b85564仅初始化
MainEventOperator，不应当作此setup。ServiceCenter.register0x101b8831c写serviceMap
后调用service metadata.+0x150（0x101b88430/0x101b88444/0x101b88484/
0x101b88488）；MainService该槽0x11fbf8d10正指0x101b85a58。

BBPegasusSwiftModule.setup0x101a09378→0x101a08f74（0x101a093dc）resolve registry，
默认fallback0x101a08464提供shared ServiceCenter/global0x12106a6b8及witness
0x11b1751f0。它新建MainService（0x101a09040/0x101a09044/0x101a09050），以rawscene1
交registry witness.+8（0x101a0905c–0x101a0906c）；默认witness0x101b88a74接上述
register。外部registry override的实际identity仍另核。legacy onModuleInitialize
0x101a083a8仅runnable optfalse才setup（0x101a083c0/0x101a083e0）。opttrue替代
为库存index135/slot0x1202743c0的provider0x1001ca8a4/class0x120299640；lazy task
array0x1001ca844由0x1001ca7f4创建一组metadata0x11b0be940/witness0x11b0be8f0
（0x1001ca830）。name槽.+0x20→0x1001ca744返回PegasusSwiftModuleModuleInitialize，
execute槽.+0x28→0x1001ca760要求idiom0及opt EXACTtrue
（0x1001ca79c/0x1001ca7ac/0x1001ca7cc/0x1001ca7d0），再调用static thunk
0x101a083a4（0x1001ca7e0）→同setup。trigger helper0x1001ca608接moduleInitialize
producer0x105138060，thread helper0x1001ca620接main producer0x10513818c；静态门禁
不保证实际每次执行。setup0x101b8983c不读feed_mode文件；已知logout及FeedTopView
label读文件，不据持久JSON推settings options启动恢复。

Phone首页模式条有独立的物理导航入口：TopFeedModeView.initWithFrame wrapper
0x101b979ac→0x101b977c4将self.tapView作为gesture target/action安装到self
（0x101b97940/0x101b97960/0x101b97978）。tapView 0x101b983fc→0x101b984e8
读取CURRENT BFCAccount.hasLogined（0x101b9850c），true选`/main/feedsetting`
（0x101b98518），false选`/login`（0x101b98570），以空参数调用route helper
0x101b6fd30（0x101b98588）。该helper先transferFromHttpScheme（0x101b6fe04），
合并URL query，解析或序列化失败时沿用transferred string；先设置
PersonalizeGuidance.hasClickedInPegasus=true（0x101b6ff94），再以animated=true调用
BFCRouter.processUrl（0x101b6ffe0），不以router成功返回为该标志门禁。已知Phone
`/main/feedsetting`映射仍受外层Compose/native-transfer影响；此入口不证明settings列表
某行的tapMethod，也不解决HD2的main/pegasus alias。

FeedTopView的模式条状态consumer实际安装在0x101b96148→0x101b964bc：raw27/flag1
（0x101b96590/0x101b96594/0x101b965a0）callback 0x101b96d9c经weak-self helper
0x101b966bc→0x101b9685c；raw26/flag1（0x101b965fc/0x101b96600/0x101b9660c）
callback 0x101b96e1c直接tail同raw27 callback。两者忽略event payload，重新读CURRENT
feedModeSetting（0x101b968a0），desiredHidden=(mode!=1)
（0x101b968b0/0x101b968b4）；与当前isHidden相等即返回
（0x101b968cc/0x101b968dc/0x101b96a10）。只有hidden改变，才setHidden
（0x101b96904），读取feed_mode JSON（0x101b9694c）并解析Model
（0x101b96994），取可选title（0x101b969cc）设置titleLabel.text（0x101b96a40），
缺失model/title则text=nil（0x101b96a24/0x101b96a2c），最后layoutIfNeeded
（0x101b96a94）。所以同mode的raw26即使替换JSON，也未必刷新显示标题；该handler
不检查isDisplayFeedModeSetting或options.count。lazy view创建时先hidden=true
（0x101b95fd4/0x101b95ffc/0x101b96048）。JSON读取不恢复settings option数组。

### Phone 播放模式引导：入口、曝光与当前实例移除

PlayModeGuideManager有独立的公开路由`/main/feedsetting?setting=playStyleSetting`
（literal0x11789c420），不与PersonalizeGuidance混为同一入口。onOpen body
0x101b404dc先用空参数调用公共router helper0x101b6fd30（0x101b40580），之后才处理
引导状态。onJump body0x101b40934要求CURRENT currentModel非nil且cardJumpEnable
EXACT1（0x101b40998/0x101b4099c/0x101b409ac/0x101b409b0），才route
（0x101b40a08）。这两个body在route之前没有login门禁；公共router仍有前述转换与
hasClickedInPegasus写入。实际show创建PlayModeGuideView并绑定weak-manager
onClose/onOpen/onJump（0x101b3fb68/0x101b3fbbc/0x101b3fbfc），weak helper
0x101b408dc在manager仍存在时执行对应body（0x101b4090c/0x101b40918）。

View背景安装jumAction gesture（0x101b41870/0x101b41890/0x101b418a8），action
读onJump并BLR（0x101b4349c/0x101b434bc）。左右按钮安装target=self及raw control
0x40（0x101b421fc/0x101b4220c/0x101b42214）；leftButtonTapAction0x101b434f0
和rightButtonTapAction0x101b435c8共用0x101b43528。CURRENT view.model非nil且isV2==1
（0x101b43548/0x101b43558/0x101b4355c）时左close、右open，否则左open、右close；
选中closure非nil才调用（0x101b43568/0x101b435b4/0x101b43588）。不能根据按钮侧别
固定推断动作。

旧model factory0x101b3e0d8读Memex公开key `pegasus.story_mode_guidance_config`
（0x101b3e12c），要求config/dictionary非nil，yy_modelWithDictionary
（0x101b3e1d8）；Model默认cardJumpEnable=false、isV2=false
（0x101b3dea8/0x101b3ded4）。新factory0x101b3e294读
`pegasus.story_mode_v2_guidance_config`（0x101b3e2e8），解析WapperModel
（0x101b3e394），storyGuide存在才强制child.isV2=true
（0x101b3e3c8/0x101b3e3d4/0x101b3e3d8）。公开Model属性表0x11d63f278包含
imageUrl/title/subTitle/showTimeSec(double)/cardJumpEnable/setButton/cancelButton/isV2；
wrapper表0x11d63f3b0含timeoutForDismiss/timeoutForClick(Int)及typed storyGuide。
本类metaclass没有自有custom mapper，继承/category行为另核，不猜snake_case别名。
wrapper默认timeoutForDismiss=30、timeoutForClick=180（0x101b3e044/0x101b3e054）。

两个model是实例lazy cache：helper0x101b3e220仅缓存字段为sentinel1时执行factory
（0x101b3e248/0x101b3e24c/0x101b3e254/0x101b3e260），包括nil结果也缓存。
init0x101b3efc0将两个字段设1（0x101b3efe0/0x101b3efec）。raw26/flag1注册
（0x101b3e54c/0x101b3e550/0x101b3e55c）weak callback0x101b4376c→0x101b3ed88
只把CURRENT feature字典中need_show_story_mode_guide成功Int cast且==1转换成
oldGuideEnable（0x101b3ee50/0x101b3ee54/0x101b3eea4），把
story_mode_v2_guide_exp成功Int原值或失败0存newGuideExp（0x101b3ef68/0x101b3ef8c）。
该完整callback不重置lazy models/currentModel/guideView；不据此推全局永不刷新或按账号分区。

真实entrance注册包括foreground selector _showPlayModeGuideIfNeeded
（0x101b3e5fc/0x101b3e618），以及raw2/flag1 weak callback0x101b43744；两者到
0x101b3e6e8。old admission先拒绝miniScreenPlayerManager.showing
（0x101b3e740），再要求oldGuideEnable==1、CURRENT videoMode==2、weak page provider
可用且其page字符串等于`main.ugc-video-detail-vertical.0.0.pv`、未hasShownOld
（0x101b3e750/0x101b3e794/0x101b3e7b8/0x101b3e8a8/0x101b3e900/0x101b3e914）。
先currentOldGuide=1（0x101b3e924），再要求Chinese locale、仍未hasShown、!isShow、
currentOldGuide==1和oldModel非nil（0x101b3e988..0x101b3e9e0）才enqueue
（0x101b3e9ec）。其fallthrough还独立判断newGuideExp>=2/currentNewGuide>=2
（0x101b3ea08/0x101b3ea1c）。new admission0x101b3f2a4要求Chinese locale、
nextShow时间STRICTLY小于now、!isShow、currentNewGuide为raw2或4、wrapper/storyGuide
非nil（0x101b3f358/0x101b3f38c/0x101b3f390/0x101b3f3a0/0x101b3f3b0/
0x101b3f3bc/0x101b3f3e8/0x101b3f410），才enqueue（0x101b3f41c）。不为raw值猜枚举名。

Enqueue0x101b3f624先存CURRENT currentModel（0x101b3f64c），再BBSerial.addEvent
priority raw0（0x101b3f744/0x101b3f750），closure捕获weak manager与strong supplied model
（0x101b3f6d0）；thunk0x101b4381c到实际show0x101b3f7e4。当前oldGuide==1存old token，
否则当前newGuide>=2存new token（0x101b3f784..0x101b3f7b4），替换旧token时此helper
未显式end。实际show要求weak manager可用、TopmostView.viewForApplicationWindow非nil、
page provider及其protocol metadata可用；已有CURRENT guideView则退出
（0x101b3f8fc/0x101b3f91c/0x101b3f950/0x101b3f98c/0x101b3fa40）。view以captured model
构建并add到上述window view（0x101b3fc14），保存guideView、isShow=true
（0x101b3fc1c/0x101b3fc44）；oldGuide==1时此后才hasShownOld=true（0x101b3fc6c）。

Attach后实际BFCNeuronExposureEvent `tm.recommend.play-mode-guidance.0.show`
（0x11789c3f0/0x101b3fe58）trackInstantly（0x101b3fec4），无该body额外dwell门禁。
trigger_type String：当前oldGuide1→0，否则newGuide2→1、4→2、其余→3
（0x101b3fcac..0x101b3fd28）；tm_card_play_state是CURRENT videoMode经枚举metadata和
_print_unlocked格式化（0x101b3fd98/0x101b3fdb0/0x101b3fdd0），不能标成decimal raw值。
这证明日志dispatch，非服务端收到。

Attach/曝光之后，showTimeSec>0用原Double，否则5秒
（0x101b3fee4..0x101b3fefc），main.asyncAfter（0x101b40088）strong捕获manager
（0x101b3ff6c/0x101b3ffcc）。timer thunk0x101b438c0→0x101b40d98仅dismiss
CURRENT manager（0x101b40df4），未比较原view/model/token/generation，也未保存取消handle。
不能声称迟到旧timer天然屏蔽新引导；实际serial是否允许该交错仍未运行验证。
Dismiss0x101b3f46c要求CURRENT isShow==1且guideView非nil
（0x101b3f490/0x101b3f494/0x101b3f4a4），匹配old model/guide时end/clear old token
（0x101b3f564/0x101b3f56c），匹配new时end new token（0x101b3f594）。后者机器码却选择
oldGuideToken descriptor0x120357098清零（0x101b3f59c/0x101b3f5a4），保留此实测区别。
随后isShow=false、remove CURRENT view并清guideView/currentModel
（0x101b3f5ac/0x101b3f5bc/0x101b3f5cc/0x101b3f5d8），不清memoized models。
Timer、background _autoDismiss0x101b3ebd0（注册0x101b3e5b4/0x101b3e5d4）及raw3
callback0x101b3ea58仅dismiss成功+wrapper可用+CURRENT newGuide>=2时更新冷却：
now+timeoutForDismiss*86400，overflow trap，随后清currentOldGuide/currentNewGuide
（0x101b40e70..0x101b40eac；0x101b3eca4..0x101b3ece0；0x101b3eadc..0x101b3eb94）。
因此默认30在此consumer是天。

持久实现亦有具体证据：原Mach-O dyld rebase superclass slot0x11fbf6028→BFCPreferences
0x1202710f0，metaclass-super0x1203570b0→0x120271118；属性表0x11d63f100中
hasShownOldStoryModeGuide为TB,N,D，nextShowStoryModeGuideTimeInterval为Td,N,D。
configName0x101b40f98返回固定BBPegasusPlayModeGuideManager
（0x101b40fa4/0x101b40fb8），default builder0x101b43984分别Bool false
（0x101b43a10）及boxed Int0（0x101b43a44），后者实际dynamic getter仍为Double。
BFCPreferences的ASCII d分支选getter0x1167d49c8/setter0x1167d4a50
（0x1167d3adc/0x1167d3bd8/0x1167d3be0）；getter读RAM object→doubleValue
（0x1167d4a04/0x1167d4a20），setterNSNumberDouble→通用RAM/UserDefaults writer
（0x1167d4a94/0x1167d4ab0）。普通初始化disk值优先default，固定suite无MID参数；
不证明跨账号外部清理，也不把NSUserDefaults调用当磁盘成功。singleton once
0x12034eeb0→initializer0x101b3e0ac保存0x12106a618（accessor0x101b40efc）。

BBListPlayerBehavior注册receiver已具体定位：module installer0x101a08f74取pgs bridge
（0x101a09078），将同一PlayModeGuide singleton0x12106a618与protocolRef0x11f7b0580
交virtual+0x68（0x101a0911c/0x101a09124/0x101a09134/0x101a09154）；singleton未初始化
分支swift_once→initializer0x101b3e0ac（0x101a09348/0x101a09354/0x101a09358）。
bridge accessor0x104e4ddac与ObjC pgs0x104e4ddec共享once0x120a33508/global0x1210730e8，
实际BFCResolver0x11ff35d30经init0x104e4e064存underlying Resolver到ivar0x1204b07f8
（0x104e4e078）；underlying是once0x120a33580/global0x121073160的Resolver实例。
class slot+0x68指0x104e4e2d0，检查conformsToProtocol（0x104e4e2f8/0x104e4e2fc）；
manager protocol list0x11d48ff08含BBListPlayerBehavior0x11d62d1b0。接受后用
NSStringFromProtocol→SwiftString（0x104e4e31c/0x104e4e32c），强捕获同manager
（0x104e4e358/0x104e4e360），factory0x104e4e3e0返回原receiver，交Resolver.register
0x105127fd4（0x104e4e380），不另建manager。

Phone objectFromProtocol0x104e4e720调用同bridge lookup0x104e4e674
（0x104e4e750），用同generic type及protocol-name String查询0x105129240
（0x104e4e6a0/0x104e4e6ac/0x104e4e6bc/0x104e4e6f0）。Phone protocolRef0x11f7b5148
虽指另一protocol对象0x12078c070，但name同为BBListPlayerBehavior；key输入为type+name，
因此接到上述exact-manager factory。竞争注册、scope、override或miss语义另核，未证明
后续不存在替换。另两实际消费者0x10359b4ac（Mall VDToStoryBloc shareGotoStory日志helper）
及0x103c322a0经lookup/cast后发送playerDidChangePlayModeToStory
（0x10359b648/0x10359b678/0x10359b690；0x103c3275c/0x103c327c0/0x103c327d8），
Mall入口具体用户动作与伴随Booltrue callback生产门禁仍待核，不能由日志名推行为；
BBVideoModule拖动入口如下已闭。

其中BBVideoModule.VDToStoryBloc helper0x103c322a0先写willTransType raw3
（0x103c32318）、isEnterStory true（0x103c32364）及snapshot（0x103c323b0），
然后才做分享播放准入。Memex公开key `ff_story_new_share_player_825` 默认hit=true
（0x103c32404），命中且share-player helper0x103f8e518返回>=1
（0x103c32440/0x103c32444）走替代参数路径；否则beginSharePlay helper0x103f8e5e4
（0x103c325d4）必须true（0x103c325e4），false绕过DidChange退出。该helper要求
player.context.shared非nil（0x103f8e668）及share record非nil（0x103f8e67c），
设role/setupMode/phase均raw1（0x103f8e6a4/0x103f8e6b8/0x103f8e6cc），调用service
virtual+0xb8（0x103f8e6f8）后返回true；record来源另核。通过后才lookup/cast并
通知playerDidChangePlayModeToStory（0x103c327d8），之后再处理BFCRouter route，
故guide状态触发发生于导航之前，不能当作导航成功回执。

具体拖动producer与此helper已有静态接线。安装器resolve VDDetailContainerBlocProtocol
（0x103c2fd58..0x103c2fda4），非nil PublishSubject<DraggingFlowState>订阅callback
0x103c3292c（0x103c2fe04/0x103c2fe2c）。该callback只接受原始byte3
（0x103c32940/0x103c32944），route lookup(input0)必须非nil（0x103c32954），
helper0x103c31dc0 false则直接进入VDToStory rawreason4/Booltrue（0x103c32998），
true走helper0x103c31f64(raw4)另经分享播放与route准入。enum descriptor0x119624580
有0 payload、4 empty cases，reflection0x119875a54依次begin/dragging/recover/dismiss，
所以此raw3是dismiss，不是账号通知值。实际V3协议conformance0x1183c3860、
witness0x11b2a7870+8→0x103f3051c返回其draggingFlow field0x1204521c0；初始化
0x103f2f648保存同一个subject。Coordinator初始化将self.handlePanGesture:装到view
（0x103f34354/0x103f3436c），ObjC action0x103f32198→0x103f31d88，sender.state
（0x103f31e18）raw1/2分别begin/change，所有其他值取Y velocity
（0x103f31f30/0x103f31f64），不能仅称ended。结束helper0x103f32044要求
CURRENT offset<0或abs(velocity)<=20（0x103f32070..0x103f3207c），才以CURRENT
onPanGestureEndScroll和offset/Y velocity回调（0x103f32124..0x103f3214c）。
该槽已绑定weak V3 thunk0x103f318a8（0x103f2ee2c），经weak helper0x103f2f244
到0x103f295ac（0x103f2f290）。后者对有限值要求offset<0且
(offset<=-pullDismissThreshod或velocity>600)（0x103f296f0..0x103f29720），
content view非nil（0x103f29770）后才向同subject发raw3/Rx next tag0
（0x103f297ac..0x103f297cc），发生在dismiss动画之前。subject nil只跳过emit，
仍继续动画；不能把所有退出都算作guide触发。订阅dispose、其余入口和运行呈现另核。
替代共享路径helper0x103c317bc进一步要求CURRENT video.avid/cid均>=1
（0x103c31858/0x103c318c8）、playback非nil且raw playbackState>=3
（0x103c31948/0x103c31964）、shared与record非nil
（0x103c319d8/0x103c31a10），以及helper0x103c34ae8返回false
（0x103c31a1c）。后者读取CURRENT playback.inQueuePlay（0x103ed6ddc），非队列
直接false；队列且ijkItem nil或其cid与CURRENT currentVideo.cid不等则true拒绝。
不从原始state>=3命名为playing，也不读取具体标识值。前述isEnterStory/snapshot
先写后准入的本体未见rollback，不能把写入当作准入成功。

第二物理入口是左侧edge backpan。安装器0x103c2fd30将weakself thunk0x103c329f4
交VDBackPanGestureBloc.addBackGesture:0x103f1f64c；后者init target/action
（0x103f1f730）、setEdges raw2（0x103f1f744）、安装到CURRENT mainVC.view
（0x103f1f7e0），保存callback/context（0x103f1f8a0）。ObjC backAction0x103f1fdd8
→0x103f1fa9c，只接sender.state raw3（0x103f1fad8）；位移比例translationX/window
width（keyWindow或mainScreen）clamp到[0,1]（0x103f1fba4..0x103f1fbbc）。有限值
fraction>0.25或velocityX>800才调用CURRENT action
（0x103f1fd44..0x103f1fd7c），经0x103c329f4→0x103c328d4→0x103c31f64(rawreason2)
（0x103c32910），仍受上述共享路径helper及route(input1)非nil门禁。
播放器Story按钮还有独立入口：installer 0x103c2f874取VDPlayerBloc.player
（0x103c2f8c0），getService helper 0x103f437a4以flag1与精确protocol typeref
0x11973975c/缓存0x12041af98（So24BBPlayerGotoStoryService_p）求service
（0x103c2f8e8），非nil才安装weak bloc callback/thunk 0x103c32a3c
（0x103c2f8f8/0x103c2f91c/0x103c2f924/0x103c2f95c/0x103c2f988）。
service.addClickActionHandler 0x104a7dabc只替换单slot，copy新block/强保存context
并release旧handler（0x104a7dad8/0x104a7dafc/0x104a7db34/0x104a7db38），不是监听数组。
实际BBPlayerGotoStoryWidget的lazy button 0x104a7dc9c→0x104a7dd00创建UIButton，
action handlerSwitchBtnAction:以self/event0x40 addTarget
（0x104a7dd40/0x104a7dd4c/0x104a7dd50/0x104a7dd54）。ObjC handler
0x104a7e75c→0x104a7e614若CURRENT context.tracker存在，先track公开事件
`player.player.story-button.0.player`、extends=nil（0x104a7e69c）；tracker缺失仍继续。
取CURRENT _gotoStoryService（descriptor 0x12049a1c8；0x104a7e6b4），nil时同protocol
flag1 fallback 0x104b10294（0x104a7e6dc）。clickHandler存在
（0x104a7e70c）才Block invoke（0x104a7e730），之后仍调0x104a54a18。
callback thunk→0x103c2ff0c先weakself、route(input0)非nil
（0x103c2ff54/0x103c2ff68），再weak reload并要求共享准入helper 0x103c317bc true
（0x103c2ff84/0x103c2ff90/0x103c2ffa0），故仍受上述avid/cid/playbackState/shared/
record/queue门禁。isHitBackToStory false（0x103c2ffc8/0x103c2ffd8）才调用
VDToStory rawreason3（BL site 0x103c3012c）；true释放该route，改调0x103c31f64(reason3)
（0x103c2ffe0/0x103c3000c），独立重核share gate和route(input1)。按钮点击日志先于这些准入，
不等同导航或DidChange通知成功。服务lookup也不能简单称具体class实例：player lookup
0x103f437a4读player.context（0x103f437cc）→0x104b0ff1c（0x103f437e8）；widget
fallback读widget.context（0x104b102c0/0x104b102cc）→同helper 0x104b0faac
（0x104b102e4），由protocol描述转类名并NSClassFromString
（0x104b0faf4/0x104b0fb5c/0x104b0fb98），CURRENT context.serviceManager
（0x104b0fbd4）以flag1 createProxyAndBindService（0x104b0fc00）。具体
0x114822968先createProxyForService（0x11482297c），proxy非nil才bindService
（0x11482298c/0x114822998）。具体proxy target/cache已闭，但有同manager前提：
createProxyForService 0x114822904→_findOrAdd 0x114822694
（0x114822914），先_serviceForClass（0x1148226a8），nil才_add
（0x1148226c0）。lookup在锁下按Class查dictionary（0x114822654/0x114822668/
0x11482267c）；add alloc该Class、initWithContext后另锁写同dictionary
（0x1148226f4/0x114822718/0x114822734/0x11482274c/0x114822754）。
两者不是同一get-or-create critical section，首次并发是否串行由外层政策另核。
每次成功lookup后都新建BBPlayerServiceProxy（0x11482292c/0x114822938），其init
0x114822e94弱存actual service并保存actual.class
（0x114822ec4/0x114822ee4）；class override 0x1148234bc返回保存Class
（0x1148234c4）。故不同proxy可以指向同manager缓存的actual service。
bindService 0x114822a3c经proxy.class查actual（0x114822a68/0x114822a78），
missing时新建并rebind（0x114822a94/0x114822ab0）；actual inactive才serviceOnStart，
然后serviceOnBind(proxy)（0x114822b40/0x114822b4c/0x114822b58）。具体服务继承与
Video/player/widget是否安装同context仍待核，不能把两lookup当同一proxy。
forwardingTargetForSelector 0x1148230c8只在weak actual存在且isActive=true时普通转发
（0x1148230f0/0x114823100/0x114823108）；inactive仅
rac_valuesForKeyPath:observer:与rac_valuesAndChangesForKeyPath:options:observer:
两个selector例外（0x1148231a4..0x1148231c0）。forwardInvocation
0x1148232b4也只对active actual invokeWithTarget
（0x1148232dc/0x1148232ec/0x1148232fc），其余setTarget:nil再invoke
（0x11482330c/0x114823314）。因此inactive旧proxy不保证执行具体icon setter或click
registration；返回值语义仍在NSInvocation边界，未作运行验证。
Widget init 0x104a7dee4→0x104a7e7fc（0x104a7df1c）初始化bag/service/lazy button后，
调用display 0x104a7df50及订阅helper 0x104a7e208（0x104a7e928/0x104a7e92c）。
display在CURRENT context/status nil时不改现态（0x104a7dff4/0x104a7e01c）；
status.isVerticalScreen true、service nil、gotoStoryIconUrl nil或URL转换失败
（0x104a7e030/0x104a7e064/0x104a7e0a8/0x104a7e0f4）写Gone/Hidden true
（0x104a7e110/0x104a7e128）。valid URL则setImage、completed=nil
（0x104a7e1a0），立即Gone/Hidden false（0x104a7e1c4/0x104a7e1e0），不等待图片回执。
service.base.gotoStoryIconUrl观察（0x104a7e318）→callback 0x104a7e5c4重读CURRENT
display（0x104a7e5d4），disposable进own bag（0x104a7e408）。controlActive KVO
keypath 0x1183f6e68→getter 0x104aed2ec，观察结果经MainScheduler
（0x104a7e470/0x104a7e4f4）→callback 0x104a7e5e4→0x104a54a18(rawfalse)，
按钮后同helper rawtrue；FlexControl实际attachment及该helper的完整显示控制另核。

该backpan安装还有上游参数gate：0x103c2fcb8调用isHitBackToStory helper
0x103c31dc0，false（0x103c2fcf4）跳至0x103c2fd4c→0x103f1f8ec，不绑定上述
reason2；true才执行0x103c2fd30。helper取CURRENT VDDataBloc.routeParam
（descriptor0x12044fee8）非nil后virtual+0x5c0；具体VDRouteParam
class0x11fe11a38槽0x11fe11ff8→0x103f11438 getter，读back_to_story_id
（descriptor0x120451860→0x103f126e0）。该String非nil且count>=1
（0x103c31e58/0x103c31e64/0x103c31e74）才true，不把此gate称Memex或设置toggle。
播放器Story图标的具体writer为0x103c2f4ac：取CURRENT player、resolve同协议service
（0x103c2f500），service nil不写；enable helper 0x103c32fd8为false时明确写icon nil
（0x103c2f518/0x103c2f5fc）。true取CURRENT basicModel（descriptor 0x12044fef8；
0x103c2f558），经BBVDBasicModel.+0xe8/getter 0x103ee783c取viewBase
（descriptor 0x120450740；0x103c2f584），其.+0x20为storyEntrance（0x1183c31d0）；
StoryEntrance class 0x120451d48.+0xc0/getter 0x103f15e4c读取landscapeIcon.+0x30，
桥接后setGotoStoryIconUrl:（0x103c2f5d8/0x103c2f634）。basic缺失亦写nil，不保留旧icon。
enable helper要求非vertical（0x103c33004/0x103c33014）、basic存在及
storyEntrance.arcLandscapeStory.+0x28为true（getter 0x103f15db0；0x103c330c4），
随后common 0x103c33104：BBPlayerPlaySettingService存在时supportShakeItem或
supportCubicPanorama任一true拒绝（0x103c33184/0x103c33204），service缺失仍继续
restricted gate。0x107c24ef8→0x10f82fb54→0x1145f1e74分别询问RestrictedModeManager
rawmode0/1、business `player`（0x1145f1e94/0x1145f1ea8），OR bit0任一true拒绝
（0x103c332a0），不由raw值猜模式名称。
StoryEntrance构造helper 0x103f16200从incoming ObjC receiver复制arcLandscapeStory
（0x103f1626c/0x103f16270）及landscapeIcon（0x103f16280/0x103f162a8）；后者nil走
trap（0x103f162dc），不是empty fallback。具体响应来源也已闭到Viewunite：BBVDBasicModel.initWithReply wrapper
0x103ee7fbc→0x103ee810c（0x103ee7fd8）读reply.viewBase（0x103ee8280），构造
VDViewBaseModel（0x103ee82b0）并存basic.viewBase（0x103ee82c8）。其constructor
0x103f163b4读incoming.config.storyEntrance（0x103f163e0/0x103f165a0/0x103f165bc），
构造VDStoryEntranceModel并复制上述Bool/String（0x103f165d8/0x103f165f0），存
viewBase.+0x20（0x103f16600）。相关必需reply.viewBase/config/storyEntrance缺失各有
trap分支（0x103ee86a8/0x103f16770/0x103f16774），不称网络fallback。
CURRENT DataBloc.basicModel writer 0x103eca5a8以原reply构造basic
（0x103eca5e8），直接替换descriptor 0x12044fef8并释放旧值
（0x103eca618/0x103eca61c）。parse helper 0x103ec9ecc先调注入parser witness+8
（0x103ec9f3c），status bittrue且reply nil才走该错误分支
（0x103ec9f54/0x103ec9f58）；其余分支先store CURRENT response
（0x103eca054），读viewBase/bizType/pageType，另要求admission helper
0x103eca1ec=true（0x103eca178/0x103eca17c），才交basic writer（0x103eca190）。
admission按bizType raw1/2/3解析plugin并调witness+8（0x103eca22c..0x103eca23c/
0x103eca350），未识别biz/provider缺失则true（0x103eca388）；plugin具体实现待核。
线上source取BAPIAppViewuniteV1View classref 0x11f7ba550
（0x103ecf678），调用viewWithRequest:handler:（0x103ecf74c）。handler thunk
0x103ed0cb8→0x103ecfa18弱取捕获VDLoadTask（0x103ecfa58）；task已释放才令Booltrue
（0x103ecfa70/0x103ecfa74），经0x103ed0c5c→0x103ecf7b0时该Booltrue只取消日志并退出
（0x103ecf7d0/0x103ecf920），不是error code判断。false继续weak LoadBloc，存在才把
原reply/error、cacheflag=false交0x103ece87c（0x103ecf9c8/0x103ecf9ec）。VDLoadTask
实际分配后存CURRENT LoadBloc.task（descriptor 0x120450020；0x103ecf60c/
0x103ecf774），不将task寿命门禁称账号代际、也不以字段替换推立即释放。
至少一条icon重算触发来自supportCubicPanorama观察（0x103c2fbc8/
0x103c2fc08/0x103c2fc5c）：callback 0x103c3535c→0x103c328b0调CURRENT icon writer
（0x103c328c4）。响应解析后所有刷新hook、proxy target身份和请求参数仍继续核。

false分支具体是removeBackGesture 0x103f1f8ec：pan nil时早退（0x103f1f910），
否则从CURRENT mainVC.view移除（0x103f1f9ac），清pan及action pair
（0x103f1f9bc/0x103f1f9d4）；mainVC nil仍清字段，view nil走异常路径。
delegateShouldBegin 0x103f1fe28另读CURRENT player.context.status.isFullScreen，
true拒绝（0x103f1ff08），status nil或非全屏允许（0x103f1ff20）。
route mapper 0x103f12858→0x103f14834给back_to_story_id配置两个别名
`backToStoryID`/`back_to_story_id`（静态array 0x12044f3f8），不由此推别名优先级。
具体route producer 0x103c30140检查incoming Bool（0x103c3016c/0x103c310f4）；
false分支新建UUID/uuidString（0x103c312b4/0x103c312b8），覆盖旧entry或插入
`back_to_story_id`（0x103c31310/0x103c3132c），true跳过（0x103c31330）。
目的端BBVDDetailVC.setParams 0x103edf498先super.setParams（0x103edf53c），
helper 0x103edf56c重读CURRENT self.params（0x103edf598），nil早退（0x103edf5a4）；
桥字典→0x100028bf8（0x103edf5c8/0x103edf5dc），转换nil亦早退（0x103edf5ec）。
通过后从self.store（descriptor 0x120450320）取VDDataBloc，设flag1
（0x103edf750..0x103edf75c），转换params 0x1000f8ee8（0x103edf768）并调用
parser 0x103f138a4（0x103edf77c）。返回optional直接替换CURRENT routeParam
（0x103edf7b0），释放旧值后调用side effect 0x103ec9798（0x103edf7c4/0x103edf7c8）。
因此params/桥转换nil保留旧routeParam，parser nil则清空。上述特定outgoing route
如何跨导航成为下一次destination setParams的输入仍待核，未读取实际UUID或参数值。



伴随Bool callback的false分支已接回深度writer：manager conformance0x1182cc070
指VideoEventObserver descriptor0x119640c98，witness0x11b172f38.+8→0x101b413d0→
0x101b41294；Bool=false时恢复栈并尾调0x101b410f8（0x101b413b0..0x101b413cc），
传原position，不是只释放/无动作；true才进入下述raw2门禁。实际Story
STPlayBehaviorBloc body0x1041a41c4/virtual+0x138 slot0x11fe32bd0要求incoming x0非nil
（0x1041a41dc），更新counter后读dataBloc.current.index（0x1041a42d4），w1=0
（0x1041a42e8），调用VideoBroadcastService witness+0x18（0x1041a42f4）。具体广播
witness0x11b0f2208.+0x18→0x1009cd598→0x1009cd2a8对weak hash table取快照，filter
VideoEventObserver，解锁（0x1009cd484）后逐一witness+8同步回调
（0x1009cd4c8），传original index与Bool bit0；manager接收路径因此能进入raw4。
该service依赖实际factory0x1009cd920→0x1009cd698→0x1009cd620创建nested provider，
witness0x1202cc1e0.+0x10=0x1009cd5c4返回精确Broadcast singleton0x1210679a8与
witness0x11b0f2208；receiver边界已定位。virtual+0x138的上游是focus改变分派：
STDataBloc.setFocusItem:0x1040a7514先will helper，再写CURRENT focus
（0x1040a7588），did helper0x1040a7868接OLD item。NEW focus非nil且
new.isSameArcTo(old)=true（0x1040a78c0/0x1040a78c4）跳过；否则先发raw11 OLD
（0x1040a7a68），再raw13 NEW focus（0x1040a7ab8/0x1040a7ac0→0x10432963c）。
STBlocStore tag13跳表0x1183d23f4→0x104329aa8，捕获payload+0x10，交closure
0x10432a40c（0x104329afc）→具体bloc virtual+0x138（0x10432a43c），
STPlayBehavior实际槽为上述0x1041a41c4。payload nil不广播；非nil才读CURRENT
current.index，不能直接将focus payload当index或称每次播放进度都触发。
实际setFocusItem UI caller、generic bloc枚举准入与Bool=true生产者继续核。

currentNewGuide两个真实producer应与show分开：playerDidChangePlayModeToStory
0x101b410d0→0x101b40fcc要求nextShow<now、CURRENT videoMode==1、newGuideExp低byte
bit1为true（0x101b4104c/0x101b41050/0x101b41090/0x101b41094/0x101b410a4），
写raw2（0x101b410b0/0x101b410b4），本body不enqueue。另callback0x101b41294要求incoming
Bool bit0 true（0x101b412ec），再经同门禁写raw2（0x101b41390），上游另核。
playerDidPlayStoryAt0x101b41264传caller position到0x101b410f8（0x101b41280），同样要求
cooldown<now、videoMode==1（0x101b41180/0x101b41184/0x101b411c4/0x101b411c8），
每次读Memex公开pegasus.story_mode_v2_depth_for_story default10
（0x11789c480/0x101b41200/0x101b4120c/0x101b41210），position>=threshold且exp bit2
（0x101b41220/0x101b41224/0x101b41234）写raw4（0x101b41240/0x101b41244）。拒绝分支
不自动清旧值。StoryFeedVC.loadPlayer:isAutoPlay:isShared:0x1132e0064实际通过resolver.
pgs.objectFromProtocol(BBListPlayerBehavior)（0x1132e0650/0x1132e0668）取receiver，传
CURRENT self.storyIndex（0x1132e0684/0x1132e0688）给playerDidPlayStoryAt
（0x1132e0690）；receiver注册及同name lookup见上述桥接，loadPlayer完整上游仍另核。

close0x101b40130、open0x101b404dc及jump0x101b40934的点击日志均有独立门禁：
dismiss必须成功且new wrapper非nil（close0x101b40194/0x101b401c0；open
0x101b4059c/0x101b405c8；jump0x101b40a24/0x101b40a50）才进入字段构造。
open/jump已在这些门禁前route，close无route；缺click不等于没导航。
CURRENT newGuide>=2时用timeoutForClick*86400而非Dismiss字段，写nextShow后先清
currentOld/currentNew（0x101b40210..0x101b40248；0x101b40618..0x101b40650；
0x101b40aa0..0x101b40adc）。默认180同样是天。随后才读取CURRENT state构造trigger_type，
因此走上述清零分支的新卡点击落String3，不能沿用曝光时raw2/4映射1/2。
click_area分别close String2（0x101b402a8/0x101b402ac）、open String1
（0x101b406b0/0x101b406b4）、jump String3（0x101b40b3c/0x101b40b40）。
点击tm_card_play_state对CURRENT videoMode用Int.description
（0x101b4037c/0x101b403a4；0x101b4077c/0x101b407a4；0x101b40c30/0x101b40c58），
与曝光的enum _print_unlocked不同。`tm.recommend.play-mode-guidance.0.click`使用普通
track（0x101b40478/0x101b40878/0x101b40d2c），非trackInstantly；open本body不更新
feed mode，实际设置选择另属页面writer。旧卡内容也受new wrapper是否可用的点击门禁。


### HD2 与 Phone feedsetting 路由的解析和同名 bus 门禁

Phone BBPegasusBus.didBeenRegistered（0x113a5fbe4）也把
BBPeagasusFeedSettingVC（类拼写Peagasus，0x113a5fffc）注册到
`/pegasus/feedsetting`（0x113a6000c/0x113a60014）；这不是物理页面调用。
公共mapBiliNative0x115fb396c→_bfc_map0x115fb4064→genUrlComponent0x115fb40d0，
component.config0x115fbb4dc对无scheme路径取首非 `/` component为host
（0x115fbb6ac），其余join为path（0x115fbb6c8）。所以main与pegasus在此层host
不同、path同为/feedsetting，无parser alias证据。缓存映射0x115fb688c在existing
`:b`/`:m`且新model.feature=nil时返回error10002（0x115fb6d20），不是无条件后者覆盖；
mapBiliNative丢弃该error。实际外层URL改写/alias仍待证。

实际processUrl:animated:runtimeList（0x115f589f8）每次读
`dd_enable_compose_router` defaulttrue（0x115f58a5c/0x115f58a60）；true先
blockingAndExecuteKntrRouterRequest（0x115f58a70），handled true便返回
（0x115f58a78）。false/未handled才transferFromNativeScheme
（0x115f58a98）、callNativeBlock（0x115f58ab8）及正常push（0x115f58b18）。
native transfer0x115fb2d90遍历router.+0x10的host映射，匹配后调用block
（0x115fb2ec0），可产生新URL。因此前述parser无alias不代表全局无改写；有限引用
仅确认author注册0x1009ce9cc及BBMallRouter包装0x1039c1c80/0x1039c1ca4，
尚未证main/pegasus转换，TopView `/main/feedsetting` 到HD2页仍未闭。

HD2 setupModuleInitialize0x10def17c8以NSClassFromString(BBHD2PegasusBus)
（0x10def17e4）→initWithName(pegasus)（0x10def17f4）→registerSubBus
（0x10def1804）。Phone入口0x1001c8924要求userInterfaceIdiom==0及once Bool
0x121073908==true（0x1001c8974/0x1001c8994），再创建BBPegasusBus同名pegasus
（0x1001c89a4/0x1001c89d8/0x1001c8a00）。Bool来自
`infra.ue.opt.gripper.runnable` defaultfalse（0x1051301ec/0x105130208），有swift_once
缓存，不读取实际配置。registerSubBus0x1162406c4对nil/reentrant/name空/同名已存在
直接返回（0x116240768/0x116240780→0x1162407d0）；首次成功才will/register字典/did
（0x116240790/0x1162407b8/0x1162407c8）。同名注册门禁成立，正常任务另有互斥的
设备条件，不能由两个class同名推正常启动存在覆盖竞赛。

Phone的184项Runnable库存index134、slot0x1202743b0接provider accessor
0x1001c9498；conformance0x118262200→witness0x11b0bdf28的+8接lazy任务表
0x1001c88e4→initializer0x1001c87f8。8项表的首pair（0x1001c8834）为metadata
0x11b0bdf48/witness0x11b0bdda8；name槽+0x20→0x1001c8108返回
PegasusModuleModuleInitialize，execute槽+0x28→0x1001c8124→上述0x1001c8924。
priority/trigger/thread getter分别0x1001c8050/0x1001c806c/0x1001c808c；trigger
转0x105138060的moduleInitialize，thread转0x10513818c的main，不推实际执行时刻。

HD2的provider为index133、slot0x1202743a0，名
PegasusHDModuleGripperModule._$GripperRunnableTaskProviderPegasusHDModule。
nominal0x119488ab8→conformance0x1182648c0→witness0x11b0c0d20的+8接
0x1001d4e54→initializer0x1001d4d68，也是8项；首pair0x1001d4da4为metadata
0x11b0c0d40/witness0x11b0c0ba0。name槽接0x1001d4658的
PegasusHDModuleModuleInitialize；execute0x1001d4674经setupModuleInitialize
selector0x11f745a60转helper0x1001d4cc0。它要求idiom==1及相同once Bool==true
（0x1001d4d14/0x1001d4d18、0x1001d4d38/0x1001d4d3c），才对
BBHD2PegasusModule发送setupModuleInitialize（0x1001d4d44–0x1001d4d50），
接0x10def17c8。Phone idiom==0与HD2 idiom==1在稳定设备类型下互斥。
LegacyApp.registerModules0x105139388另以bfc_isIPad（0x1051393c8）选择
BBHD2Module.registerHDModuleWithLiveClass（0x105139434→0x10c86c154）；其6项
common modules数组index2含BBHD2PegasusModule（0x10c86c4fc/0x10c86c504），
交registerCommonModules（0x10c86c55c）。常规模块onModuleInitialize的optfalse
分支与上面opttrue Runnable分支接同一setup；不读取实际flag或启动顺序。

### VIP HD 素材请求、响应模型、入口点击与首页回执

8.89的BFCVipHDEntranceApi.requestUrl（0x10e32cd34）直接返回
`https://api.bilibili.com/x/vip/ads/materials`；requestUrlParam0x10e32cd40创建字典，
把实例.position赋给position（0x10e32cd64/0x10e32cd84），无本地MID/会员状态参数
生成；公共HTTP参数/身份头另由公共层处理。类0x1200514e0的superclass
0x120116df8为BBPgcBaseApi。这三个具体producer每次new该API并设置固定公开位置值：

| producer | position | setPosition / runAsync |
| --- | --- | --- |
| fetchHDHomeToastWithSuccess | 53 | 0x10e32d17c / 0x10e32d204 |
| fetchHDHomeTopBarWithSuccess | 54 | 0x10e32d3e0 / 0x10e32d468 |
| fetchHDVipUserCenterWithSuccess | 3 | 0x10e32d8a8 / 0x10e32d930 |

BBPgcBaseApi.init0x1120a8b0c创建BFCApiRequest存instance.+8
（0x1120a8b40–0x1120a8b50）；runAsync0x1120a8b70先setupOptions、setupHandler
（0x1120a8b80/0x1120a8b88），再requestAsync（0x1120a8ba0）。setupOptions
已有options非nil便跳过创建（0x1120a8cb0），不能把复用实例看成每次重建参数。
新options signType=0（0x1120a8cc8），读取isIgnorCache，base默认true
（0x1120a93cc）；isPostRequest默认false（0x1120a93bc），builder选requestMethod raw0
（0x1120a8dd0–0x1120a8de4），该VIP subclass已列method没有override。URL经过
checkValueToHTTPS，url params经过checkValueToStringWithDictionary，再赋options
（0x1120a8da0/0x1120a8db8/0x1120a8e4c/0x1120a8e64）。customOptions能影响cache
interval/timeout（0x1120a8d08–0x1120a8d70），不把该base默认提升为全部PGC请求常量。
cancel0x1120a8bb4转发到当前bfcRequest.cancel（0x1120a8bd0），实际运输/取消回调
仍按公共HTTP层门禁；三producer局部未保留单独公开cancel handle或自建retry。

Toast success callback0x10e32d240从response[`/`].data.list_v2取数组
（0x10e32d288/0x10e32d2b0/0x10e32d2c8），以BFCVipHDEntranceModel转换
（0x10e32d264/0x10e32d2e4）；非空只取第0项（0x10e32d310/0x10e32d320）构造
BFCVipHomeToastView.initWithModel（0x10e32d340），交捕获success callback
（0x10e32d354）。空数组交nil（0x10e32d378）；fail callback0x10e32d394同样交nil，
不在这个失败body重发。不把首次model理解为服务端排序/最优候选保证。

TopBar success0x10e32d4a4也取response[`/`].data.list_v2
（0x10e32d508/0x10e32d520/0x10e32d538），转同一model数组（0x10e32d554）；
空列表交两个nil（0x10e32d658–0x10e32d668）。非空只取首model
（0x10e32d590），按image_list原顺序枚举（0x10e32d5c8），取首isTopLeft=true
的image.url（0x10e32d60c/0x10e32d644，实际url stub0x117739a20），没有候选
用空String。仅url.length>0、track_params.vip_status确为NSString且等于公开
String `1`、完成时BFCAccount.hasLogined=true，才BFCVipAvatarIconView.initWithUrl
（0x10e32d6a8/0x10e32d6f0/0x10e32d75c/0x10e32d778/0x10e32d788/
0x10e32d7a0）；否则avatar nil。无论该avatar是否nil，非空model都会创建
BFCVipEntranceButton.initWithModel（0x10e32d7d0），callback交avatar和button
（0x10e32d7e8）。fail0x10e32d858交两个nil；这里的登录检查只门控avatar，
不是position54请求发送或整个button的登录门禁。

UserCenter success0x10e32d96c不同，取response[`/`].data.list（不是list_v2，
0x10e32d9b8/0x10e32d9dc/0x10e32d9f4）转同一model数组（0x10e32da10）。
非空创建BFCVipEntranceSectionController，把完整数组setEntrances再callback
（0x10e32da4c/0x10e32da58/0x10e32da68），不只取首项。之后取lastObject的
track_params，nil退空字典，发BFCNeuronExposureEvent公开事件
`vip.my-page.vip.entrance.show`（0x10e32da70/0x10e32da88/0x10e32daa8/
0x10e32dab8）；这个producer的曝光调用发生在交付section之后，不是已证实际
cell可见检测。空数组0x10e32dad8、fail0x10e32db00均callback nil，不构造该曝光。
两个入口的外部消费者已有下述实际调用，其他刷新/账户生命周期仍分别核。

BFCVipHDEntranceModel的container映射0x10e32db10明确5项：click_target→
EntranceClickTarget（0x10e32db34/0x10e32db40），style→BFCVipEntranceStyleModel
（0x10e32db50/0x10e32db5c），image_list/title_list→BFCVipEntranceContentModel
（0x10e32db6c/0x10e32db78、0x10e32db88/0x10e32db90），button_list→
BFCVipEntranceButtonContentModel（0x10e32dba0/0x10e32dbac）。自身还公开theme、
position、entrance_id、track_params、extra_params的accessors
（0x10e32dc58/0x10e32dc74/0x10e32dc94/0x10e32dcb4/0x10e32dcd8）。
EntranceClickTarget公开link/code/jump_type（0x10e32de68/0x10e32de84/0x10e32dea0）；
下述两个点击body使用link，未据jump_type分流。model.diffIdentifier每次调用
UUID.UUIDString（0x10e32dc04/0x10e32dc18/0x10e32dc28），不是缓存entrance_id；
isEqualToDiffableObject0x10e32dc50固定返回true，不推差分框架最终刷新行为。

顶部按钮initWithModel0x10e32e96c保存model、showAnimation=false，再buildUI
（0x10e32e9c8/0x10e32e9d4/0x10e32e9dc）。buildUI注册自身clickAction，
controlEvents raw0x40（0x10e32f118–0x10e32f128），随后以model.track_params发
`vip.home-page.top-navigation.vip-icon.show`（0x10e32f148/0x10e32f168）；
这是构建按钮阶段的曝光调用，早于Home回调安装view，未证可见检测。
clickAction0x10e32f698取model.click_target.link（0x10e32f6bc/0x10e32f6cc）；
该link stub0x10f85bb4c实际接0x1173e68a0的objc_msgSend$link，不能采用
nearest-symbol bannerLink名。link.length>0才BFCRouter.shared.processUrl:animated:true
（0x10e32f6f0/0x10e32f6f4/0x10e32f718）。不论link是否为空，后续均调用
showAnimationIfNeeded:false（0x10e32f72c），以model.track_params发
`vip.home-page.top-navigation.vip-icon.click`（0x10e32f74c/0x10e32f76c），没有
路由成功回执门禁；此body未给nil track_params另造空字典。

个人中心section.didSelectItemAtIndex0x10e3323d8没有按incoming index挑素材，
取entrances.lastObject（0x10e332400/0x10e332410），在其button_list找code
`vip_center_tip`（0x10e33242c/0x10e332440/0x10e33244c）。helper0x10e33269c
按原列表顺序比较item.code，首相等即返回item.click_target.link
（0x10e332750/0x10e332764/0x10e332774/0x10e3327a8/0x10e3327b8）；
无匹配/空列表返回空String（0x10e332724/0x10e3327d4），首匹配的nil link
不会继续找后续匹配。选择body把公开参数onlyFullScreen=String `1`追加到
所得String（0x10e332468/0x10e332470/0x10e3324a4），直接processUrl:animated:true
（0x10e3324e4），没有顶部按钮的length检查。随后取同一last model.track_params，
nil退空字典，发`vip.my-page.vip.entrance.click`
（0x10e3324fc/0x10e33251c/0x10e33252c）。两入口这里只调用公共路由，不能把
服务端link当已固定的后续HTTP endpoint；外层Compose/Native路由及目标页面请求
需另闭，点击上报不代表路由成功。append helper0x1167a6144要求传入非空NSDictionary
（0x1167a6184–0x1167a61ac），NSURL.URLWithString失败返回原String
（0x1167a61bc/0x1167a61cc→0x1167a6510）。成功时枚举allKeys，用String key和
非nil value构造`%@=%@`（0x1167a629c/0x1167a62a4/0x1167a62b8），已有query后拼
`&%@`（0x1167a62e8），此完整body无percent-encode或同名key去重。原query非空
按原String中的`?query`范围替换query（0x1167a63d8/0x1167a6558）；没有query时
把`?newQuery`插在fragment前或String末尾（0x1167a64e0/0x1167a6524/0x1167a6564）。
因此追加onlyFullScreen不会覆盖已有同名query项；空/异常URL的最终解析及push结果
未运行，不把helper调用当目标页面必定打开。

HD HomeViewController.viewDidAppear wrapper0x10024352c接implementation
0x100242d4c（call0x100243548），先super.viewDidAppear（0x100242d88）、
resumePlayView.inHomeVC=true（0x100242dbc）及续播准备（0x100242ea4），然后
topBarShowing=true（0x100242ef8），resolve/cast上述PGC BFCVipHDService后调用
fetchHDHomeTopBarWithSuccess（0x100243030）。完整implementation中没有本地
会员/登录/首次一次请求门禁；不推super或服务端同样无门禁。callback
0x100246224→0x10023f420分别weak-load原HomeTopBar（0x10023f458/0x10023f490），
存活才把avatar交0x10023f4c0、button交0x10023f764；callback body没有request
generation或Home VC身份比较。avatar helper先移除/清旧avatar再看incoming是否nil
（0x10023f4f4–0x10023f504），因此nil回执也能清旧头像角标。button helper
incoming=nil时先看旧vipEntranceBtn（0x10023f788→0x10023f9cc）；旧btn存在才
移除其view/清ivar并重设message trailing constraint
（0x10023f9e8/0x10023f9f8/0x10023fa00），旧btn也nil直接返回。incoming非nil
则移除旧btn并保存/添加新btn（0x10023f798–0x10023f7e0）。这两个helper都能
响应nil回执移除已有VIP UI，前置producer的请求失败也走两个nil回执。

HD UserCenter请求helper0x1002521d0先BFCRestrictedModeManager.enableOfMode
raw0（0x100252204），true便返回（0x100252208→0x100252318），否则resolve/cast
PGC BFCVipHDService、fetchHDVipUserCenterWithSuccess（0x10025230c）。
UserCenterViewController.bfc_tabDidGetSelectedAgain（0x1002579ac）明确调用此helper
（0x100257a28）；viewDidLoad wrapper0x1002505a8→implementation0x10024fe84
（0x1002505bc）另直接调用该helper（0x100250208），随后注册
BFCAccountNotification.addActionObserver:type:block raw7（0x1002502a4）；callback
0x100252354→0x100250504只要求weak原VC仍存活（0x100250530），再调用
（0x10025058c）。公共postAction0x11605d16c按observer.type & action筛选，沿前述
已闭action映射，mask7覆盖Login1/Logout2/Update4而不含Change8；observer callback
未按incoming action分开这次VIP刷新。不能把raw7误读成单个第7事件，也不使用
nearest-symbol AvatarConfig.destruct作为触发名。callback0x1002596a0转
0x100257ce4，把收到section打包、以main queue.async调度
（0x100257da4/0x100257edc），执行closure0x1002596dc→0x100257f34。该closure
先weak-load原UserCenterVC（0x100257f74/0x100257f78），存活才加工当前dataSource、
setDataSource和reloadDataWithCompletion:nil（0x100258458/0x100258484），没有
复读restricted mode/账号/MID/generation的门禁。不能把producer曝光记录当成
这一main queue UI更新完成。

UserCenter UI更新按CURRENT isHasVipCenterItem Bool（ivar0x1202a3580）定位第0项，
不是按creative/model身份搜索。incoming section非nil先包装ListDataSectionItem
（0x100258008–0x100258020），读取CURRENT dataSource.items（0x100258074/0x100258088）；
flag=true且数组非空先删除range[0,1)（0x100258208–0x100258214），再在range[0,0)
插入新wrapper（0x100258238–0x100258244），flag=true（0x100258254）。flag=false
跳过删除，同样插入第0项；数组空也跳过删除。删除helper0x100259824将replacement
count0交0x100259728（0x1002598a8/0x1002598bc），后者destroy旧range并memmove
后段（0x100259774/0x1002597b4），不是仅隐藏cell。单item替换helper0x100259a20
按newCount=oldCount+1-rangeLength计算（0x100259a64–0x100259a98）。结果创建新
ListDataSource、保存到VC.lazy dataSource（0x1002582d8–0x1002582e4）。
incoming=nil且flag=false只走公共reload；nil且flag=true则当前items非空时删除第0项
（0x100258378–0x100258388），创建新dataSource并flag=false（0x100258424/0x100258430）。
失败回执能移除先前VIP section；若其他writer破坏flag/第0项约定，此body不做class/
identity校验，未观察实际不一致。所有这些更新用响应完成时的当前数组，不是请求起点快照。

HD HomeViewController有实际toast调用消费者：注册段读取resumePlayView.needShowRelay
（0x100241c34），安装callback0x100246134并把disposable交原VC.disposeBag
（0x100241cb4/0x100241cf4）。callback转0x100245054，只接受incoming首byte raw0；
relay具体为BehaviorRelay<Bool?>，raw0=false/raw1=true/raw2=nil，来源见下段。
之后weak-load原VC
（0x100245098），displayedVipToast=true或bfc_vcStatus!=2均返回
（0x1002450b0/0x1002450c8），resolve BFCVipHDService并校验协议后调用
fetchHDHomeToastWithSuccess（0x1002451cc）。具体PGC注册链见下段，运行时其他
注册/覆盖仍另有边界。返回toast非nil且原VC仍存活才0x1002451f8→0x100245268；
该helper首先要求VC.vipToast=nil（0x100245290），随后保存toast并置
displayedVipToast=true（0x100245294/0x1002452a4），才继续addSubview/动画。
consumer成功回调未重新读bfc_vcStatus；未见request generation/MID比较。
nil失败/空列表不写此展示标志，不证明实际发生过后台展示或重复请求。

HomeResumePlayView reflection field descriptor0x11979935c中needShowRelay typeref
0x1196c87bc的symbolic ref经0x11b08fbc0指向BehaviorRelay nominal
0x1196aef88，后缀`ySbSgG`为Bool? generic。init把raw2交BehaviorRelay initializer
0x105065bd0并保存relay（0x10023a2b0–0x10023a2dc），不是初始false立即取素材。
producer0x105065aac转所持BehaviorSubject→Event.next构造
（0x105065ad8/0x1050e5768），不是把Bool? raw2当Rx终止事件。
续播显示准备helper0x1002395d8先读BFCAccount.hasLogined及needShow==true
（0x100239608/0x100239620）；成立才new BBHD2PegasusResumePlayApiHelper并
requestLatestHistoryWithHandler（0x10023963c/0x1002396e4）。不成立直接发
didBecomeActiveTriggle ? nil : false（0x100239714–0x100239730），再清该flag。
history callback0x1002397d0先needShow=false（0x1002397f4）；返回model=nil时
同样发上述nil/false（0x100239840–0x10023985c），model非nil取item交
0x100238330（0x100239938/0x10023994c）。该render helper中item.uri非空时准备
续播view并发flag ? nil : true（0x1002387b4/0x1002387bc/0x1002387d8–0x1002387f4）；
uri nil/空时走隐藏helper0x1002389c0，再发flag ? nil : false
（0x100238878–0x1002388b4）。这限定toast入口在普通续播不可展示的false分支，
不是每个history响应都请求VIP；具体helper的发送/错误加工见下段。
didBecomeActive0x100239754仅parentView非nil且inHomeVC==1才置该flag=true
（0x10023976c/0x100239780/0x100239790）并再调用准备helper
（0x1002397a8）；这些flag=true路径发nil，会被toast subscriber排除。
原VC存活/status/展示标志门禁仍独立，不把账户检查提升为VIP请求自身登录必需。

BBHD2PegasusResumePlayApiHelper.requestLatestHistoryWithHandler0x10c86cd38
另有CURRENT BBHD2MCPlayerSettingPreferences.enableResumePlaying门禁
（0x10c86cd74/0x10c86cd84）；false直接handler(nil,nil)
（0x10c86ce30–0x10c86ce40），不发RPC。true创建LatestHistoryReq，business固定
`archive`（0x10c86cd90/0x10c86cda0），取playerPreloadParams并setPlayerPreload
（0x10c86cda8/0x10c86cdc0），调用History.latestHistoryWithRequest
（0x10c86ce18）。class方法0x115e1e804先取defaultService（0x115e1e83c）；
defaultService0x115e1e014每次alloc并init host `grpc.biliapi.net`、isRest=false
（0x115e1e024/0x115e1e028/0x115e1e02c），而非defaultRestService。
initializer0x115e1dee0以package `bilibili.app.interface.v1`、service `History`
创建Moss service（0x115e1df38/0x115e1df40/0x115e1df4c）。instance method
0x115e1e778交LatestHistoryReply class、所持service及方法名`LatestHistory`
到BFCMossServiceWrapper.handleRpcRequest（0x115e1e7c0/0x115e1e7d0/0x115e1e7e0）。
这闭合具体Moss入口，实际metadata/transport沿公共层；helper未保留cancel句柄。

preload getter0x10c86d08c首次nil才new并缓存参数对象（0x10c86d09c/0x10c86d0b4），
首次写qn、fnver=0、fnval及fourk（0x10c86d0d4/0x10c86d0e0/0x10c86d0f8/
0x10c86d110）；qn从bus `main/qn_playurl`结果的qn取long，负值归0，无结果0
（0x10c86d1a0/0x10c86d1c0/0x10c86d1c4/0x10c86d1cc），fnval来自supportFnval，
fourk来自isSupported4K。每次getter都会重新读httpsPlayurlEnabled，true写
forceHost=2，false=0（0x10c86d12c–0x10c86d140），不能把整个preload称每次全重建。
前述Home准备每次new helper；其他helper复用writer边尚未枚举。

RPC callback0x10c86ce60若error非nil且带bapi_status，构造NSError：domain取旧error，
code取status.code，NSLocalizedDescriptionKey取status.message、nil退空String
（0x10c86ceb8/0x10c86cedc/0x10c86cf00/0x10c86cf2c/0x10c86cf48/
0x10c86cf84），handler(nil,error)（0x10c86d024–0x10c86d034）；无status保留原error
（0x10c86d018）。error=nil且reply.items非nil才构造BBHD2HomeResumeReplyObject
并handler(model,nil)（0x10c86cfc4/0x10c86cfd0/0x10c86cfe8/0x10c86d004）；
items=nil跳过handler（0x10c86cfd0→0x10c86d040），不是在此body主动交nilmodel。
wrapper initializer0x10c86cbd0把reply.items映射到自身item，并复制hasItems/scene/
rtime/flag（0x10c86cc18/0x10c86cc38/0x10c86cc44/0x10c86cc64/0x10c86cc70）；
这里的items不是数组count门禁：LatestHistoryReply.descriptor0x115e21240交4项
field table0x120844230（0x115e21288/0x115e2128c），其items field1的class明确
BAPIAppInterfaceV1CursorItem，是单message；scene field2、rtime field3、flag field4
依次在0x120844250/0x120844270/0x120844290，raw dataType为14/8/14。
LatestHistoryReq.descriptor0x115e211d4交2项表0x1208441f0
（0x115e2121c/0x115e21220）：business field1/raw14，playerPreload field2/raw15
（entry0x120844210）的class为BAPIAppInterfaceV1PlayerPreloadParams。
items entry的raw15亦与该单message相同。GPBMessage.resolveInstanceMethod的getter
type table0x1193a5cda/base0x116798670（0x116798664/0x116798668）已按binary解码：
raw8→0x116798adc/getInt64，raw14→0x116798884/getString，raw15→
0x116798974/getMessage。所以business/scene/flag为String、rtime为Int64。
message getter block0x116799ec8转helper0x116792e84：raw15/16读取storage指针
（0x116792eac–0x116792ecc），空则按field.msgClass alloc/init
（0x116792ed4/0x116792ed8），保存父对象/field并以原子compare/store安装
（0x116792ee0/0x116792eec/0x116792ef0–0x116792efc）；竞争已有值则释放新对象、
返回已安装对象（0x116792f50–0x116792f64）。正常message getter缺值会自动创建
CursorItem，不以hasItems为此getter门禁；reply=nil或异常对象/分配路径仍分开。
因此helper的items=nil跳过callback是代码分支，不能据此推正常空PB响应必然走该分支。
wrapper虽复制hasItems，却未在前述render前用它拦截。CursorItem.descriptor
0x115e2094c交16项表0x120843628（0x115e20994/0x115e20998），uri field7为
String/raw14（entry0x1208436e8），非oneof。descriptor flags0x1c的bit0=0，
FieldDescriptor constructor0x116775284不载入显式defaultValue
（0x1167752c4/0x116775308）；String getter block0x116799eb8也转0x116792e84，
无presence走field.defaultValue（0x116792f14/0x116792f38）。defaultValue getter
0x1167754cc对非repeated/raw14且default nil返回空String
（0x1167754dc/0x1167754f4/0x116775500）。因此正常空CursorItem.uri缺值会为空，
接前述render的不可展示false/nil分支，而不是helper.items=nil分支；reply/error与
Home status/active flag仍有独立门禁，不推服务端所有空数据必然请求toast。

Toast自身还有独立操作/计时链。initWithModel0x10e33286c保存model，buildUI、
updateUI并autoDismiss（0x10e3328c8/0x10e3328d0/0x10e3328d8/0x10e3328e0）。
buildUI给actionButton/closeButton分别注册jump/closeAction，controlEvents raw0x40
（0x10e333798/0x10e3337a4/0x10e3337c8/0x10e3337d4）。updateUI按button_list
原顺序取首code=top_reminder_bubble_button_title的click_target.link作为jumpUrl
（0x10e3338c4/0x10e33390c/0x10e33391c/0x10e333950/0x10e333960/
0x10e333994），无匹配空String。随后发Neuron曝光
`vip.home-page.avatar.renew-toast.show`（0x10e333b50/0x10e333b5c）；track_params.
count>0时另交BFCVipMaterialReporter.reportExposureEvent（0x10e333b94/
0x10e333bac/0x10e333bf4）。均在view初始化时，早于Home安装view，不证明物理可见。
jump0x10e332948仅jumpUrl.length>0才processUrl:animated:true并dismiss
（0x10e33297c/0x10e3329b8/0x10e3329d0），无论空/非空都发Neuron事件
`vip.home-page.avatar.renew-toast.click`（0x10e332a04/0x10e332a10），不等待路由成功。
closeAction0x10e332a30先dismiss（0x10e332a44），track_params非空才mutableCopy并
覆写code=close_button（0x10e332a84/0x10e332aac/0x10e332ac8/0x10e332ad8），
交素材reportClickEvent（0x10e332b08）；不是同一个Neuron jump事件。

autoDismiss0x10e332cfc以dispatch_time的delta=0xee6b2800（4,000,000,000ns）
排main queue weak callback（0x10e332d1c–0x10e332d24、0x10e332d6c/0x10e332d78），
callback0x10e332d9c调用dismiss（0x10e332db4）。此4秒计时起于init，不起于首页
addSubview；未见该body保存可取消timer。dismiss0x10e332b40先weak动画alpha=0
（0x10e332c58/0x10e332c6c），completion只在weak view及superview均存在时移除
shapeLayer/清引用/移除view（0x10e332c90/0x10e332cb4/0x10e332ccc/
0x10e332ce0/0x10e332ce8）。dismiss stub0x10f849448实际接objc_msgSend$dismiss
0x1172c9580；该移除body没有清HomeVC.vipToast或displayedVipToast，其他外部writer
仍可另核，不把关闭动作推成下一次即可再展示。

素材reporter的无eventId overload0x11465ead8/0x11465eae4传空String，核心补公开
event_id为vip.vip-operation-position.tips-track.0.show/.click，并写event_type
show/click（0x11465eb34/0x11465eb70/0x11465eb88、0x11465ec00/
0x11465ec3c/0x11465ec54）。input要求NSDictionary，再mutableCopy；report0x11465ec88
读取调用时currentUser，将mid、vip_status、vip_type、vip_due_date各转String并
覆写同名键（0x11465ed24/0x11465ed8c/0x11465ede4/0x11465ee3c），这里仅分析
取值指令，不读取真实身份。单事件包装数组交report:completion
（0x11465ee70/0x11465eed4），后者创建BFCVipMaterialReportApi并requestAsync
（0x11465f2d8/0x11465f2e8）。重发批次走同一API constructor但不再经过上述
单事件账户覆写body，不能称重发自动重取MID。

API factory0x11465e678把事件数组放private_params，另取buvid
（0x11465e6e4/0x11465e710），base URL固定
`https://api.bilibili.com/x/vip/ads/material/report`（0x11465e734），requestMethod
raw2（0x11465e7b8），按公共builder先拼query到URL再POST
（0x116095550/0x116095554→0x1160955d4/0x116095618→0x1160956d0），设置
requestInjection（0x11465e818）。injection0x11465e900
mutableCopy原request，向捕获字典加filtered=String1/0，来自CURRENT
BFCAppPreferences.inReview（0x11465e948/0x11465e960/0x11465e970）；JSON序列化
options0/error nil（0x11465e990），赋HTTPBody及Content-Type
application/json; charset=utf-8（0x11465e9b0/0x11465e9d0）。completion handler
0x11465e9e8交Booltrue，error handler0x11465ea00交false，不在这里另查响应业务code。

单事件结果callback0x11465ef74锁reporter：false时failedDatas.count>=20先移除第0项，
再append捕获事件（0x11465f024/0x11465f044/0x11465f068）；true且failedDatas非空、
reportingFailedDatas=false才置true并reportFailedDatas
（0x11465efcc/0x11465efdc/0x11465eff0/0x11465eff8）。这是后续成功触发的补报，
未见此body自设重试timer。reportFailedDatas0x11465f0b0复制当前队列作batch
（0x11465f100/0x11465f174）；batch callback0x11465f1c8只有true时从当前队列
removeObjectsInArray(batch)并置reportingFailedDatas=false
（0x11465f200/0x11465f21c/0x11465f230）。false分支直接unlock
（0x11465f200→0x11465f234），这个body不复位flag、不移除batch；其他writer/reset
尚未枚举，不推实际永久卡住或账号清理行为。队列持久化、其他物理reporter入口仍待核。
shared0x11465ea18使用once token0x120da1b20及global0x120da1b18，initializer
0x11465ea48 alloc/init并存global（0x11465ea58/0x11465ea64），不是每个事件新reporter。
init0x11465ea74新alloc队列对象、存.+0x10（0x11465eab0/0x11465eab8），此body不从
磁盘恢复；failedDatas getter/setter0x11465f324/0x11465f32c仅读/strong-store该槽，
reportingFailedDatas getter/setter0x11465f338/0x11465f340仅读/写.+8 byte；destruct
清.+0x10（0x11465f348/0x11465f350）。完整text的直接BL/B到flag setter及其stub
0x11760ff40仅命中上述0x11465eff0/0x11465f230，selref0x11f72ee78的有限ADRP邻接
扫描未见另外调用；未闭动态selector/其他寻址/直接offset writer，保留reset缺口，
不能把未找到的调用当全应用无复位证明。

reportFailedDatas在当前queue为空时直接返回（0x11465f0e8→0x11465f198），也不清flag。
batch持有拷贝数组strong、reporter weak（0x11465f118/0x11465f154/0x11465f15c/
0x11465f164）；completion load weak nil跳过队列/flag修改
（0x11465f1e4/0x11465f1ec）。成功清掉batch后没有递归drain较新事件。
once thunk 0x117052b14 materialize token并tail dispatch_once（0x117052b18/0x117052b24），
不是reset方法；有限global引用扫描只证明已观察initializer writer，不排除其他寻址。

额外业务入口已按实际reporter.shared receiver确认：

| 入口与触发 | 输入/门禁 | dispatch边界 |
| --- | --- | --- |
| PGCDynamicVipNativeModule.dynamicCallMethod:args:completionBlock: 0x111fe9bf8 | method必须`report`（0x111fe9c24）；eventId必须NSString且非空（0x111fe9cac–0x111fe9cbc）；eventType integerValue为0/1 | 0→ExposureWithEventId（0x111fe9d94），1→ClickWithEventId（0x111fe9dbc），其余skip；completionBlock在此body不调用，非API ACK |
| BBStoryFreeBandWidthComponent.willDisplay 0x104204628→0x104204120（0x10420463c） | contentView.hidden则skip（0x10420420c/0x104204210）；weak item.freeFlowToast.track_params必须存在（0x104204370/0x10420439c/0x1042043d8） | shared（0x104204448）→reportExposureEvent（0x104204468），present dictionary无count>0门禁；同时安排8秒后close，计数defaults不是failedDatas持久化 |
| 同Story freeClicked 0x104205720→0x104205358（0x104205734） | button_uri非空才route（0x104205414/0x104205428/0x10420547c）；URI缺失仍close（0x1042054a8）后尝试读track_params | shared（0x10420553c）→reportClickEvent（0x1042055a0）；不以route成功为report门禁，不据此把普通close或8秒autoclose算click |
| BBPgcDetailPayView strictExposure block 0x11212bdd4 | weak view及reportData非nil（0x11212bdf0/0x11212be0c） | reportExposureEvent（0x11212be44）后本地true，不等待API结果 |
| BBPgcPhoneBangumiDetailDialogView strictExposure block 0x1122469b4 | weak view及ePWidgetVM.report.extends非nil（0x1122469d4/0x112246a20），converter 0x11263c9ac | reportExposureEvent（0x112246a9c）后本地true，converter error/nil可仍使reporter拒绝输入 |
| BBPgcPlayerDialogViewWidget strictExposure block 0x112507e40 | dialogViewModel.report.extends（0x112507e60/0x112507eac） | 同converter→Exposure（0x112507f28） |
| BBPgcPhoneBangumiFollowVipTipHeadView strictExposure block 0x111f4de08 | currentTipModel.report.extends | Exposure（0x111f4decc） |
| BBPgcPhoneBangumiInfoPayForPlaybackHintView strictExposure block 0x11224c0ec | weak view、presenter及respondsToSelector:payForBangumiHintViewStrictExposureData（0x11224c108/0x11224c120/0x11224c158） | 取得data（0x11224c170）→Exposure（0x11224c1a4），本地true（0x11224c1b8）未检查data/接受/服务器成功 |
| BBPlayerVipTipsWidget didAppear 0x104b05504→0x104b050b4、closeAction、vipAction | 当前vipInfoModel.track存在（0x104b05358/0x104b05380/0x104b05944/0x104b0596c/0x104b05f6c/0x104b05f94） | ExposureWithEventId（0x104b0542c），两个ClickWithEventId（0x104b05a14/0x104b0603c）；显式eventId不同于默认overload，物理target/appearance链见后文 |

Dynamic输入extendedFields可选非空JSONString，经pgcdynamic_dictFromJSONString
（0x111fe9d04）；枚举（0x111fe9dfc）保留NSString值，其他仅respondsToSelector:
stringValue者转换（0x111fe9e40/0x111fe9e68/0x111fe9e78），不支持值skip。
缺eventType依ObjC nil integerValue为0，不据此称required-field校验。
Dialog converter 0x11263c9ac使用UTF8/raw4及JSON options1/NSError
（0x11263c9c4/0x11263c9ec），error/nil返回nil（0x11263ca04/0x11263ca2c），
因此strictExposure localtrue与合法event及服务器成功必须分开。上述strictExposure
callback的可见性/dwell调度安装及两种具体UI入口见后文，其他触发不从方法名推已执行；统一身份覆盖及失败队列
仍沿此前reporter链，未读取真实eventId、身份或队列。

Player VIP tips的曝光入口实际是didAppear: 0x104b05504→Swift body 0x104b050b4
（0x104b05520），super.didAppear（0x104b050fc）后走前述track→ExposureWithEventId
（0x104b0542c）；0x104b051e0仅该函数中段，不能当entry做caller归因。
initWithContext 0x104b03e08→0x104b062f0（0x104b03e24）在super.initWithContext后
buildUI（0x104b06380/0x104b06390→0x104b03e44）。buildUI取lazy closeBtn/vipBtn
（0x104b03ee4/0x104b03f68），各factory把widget作为target，分别注册closeAction
（0x104b03848/0x104b03858/0x104b0385c/0x104b03860）及vipAction
（0x104b03bbc/0x104b03bcc/0x104b03bd0/0x104b03bd4），controlEvents均raw0x40。
这接通两种物理点击到上述material reporter；不概括其他dialog close/desc按钮。

strictExposure的调度和本地去重：PayView.pgc_strictExposureEvent 0x11212bd14创建
BBPgcStrictExposureEvent（0x11212bd34/0x11212bd38），把weak-view callback
0x11212bdd4传initWithTriggerHandler（0x11212bd84）；event.init 0x114669a2c保存handler
（0x114669a78）。实际collector 0x114669be4枚举对象，要求protocol/selector门禁
（0x114669cbc/0x114669cd0/0x114669d08），已有filterKey则skip
（0x114669d50/0x114669d60），取相关view并fullyVisible检查（0x114669d78），
event.handler非nil（0x114669da4/0x114669db0）才记录filterKey、加入filteredKeys
（0x114669dbc/0x114669de0）并创建rawflags16 cancellable dispatch block
（0x114669e84/0x114669e88）。event关联源object（key0x120da1b78/policy1，
0x114669eb4），dispatch_time偏移1,000,000,000ns再main dispatch_after
（0x114669eb8/0x114669ec4/0x114669ecc/0x114669efc）。delayed callback 0x11466a06c
要求weak collector/source/event/view都有效（0x11466a0b4..0x11466a0c0），再次同view
fullyVisible（0x11466a0c8）才执行handler（0x11466a0e8）；handler的本地Bool直接写
event.collected（0x11466a0ec/0x11466a0f4）。false移除filterKey
（0x11466a104/0x11466a13c），最后清源object association（0x11466a164）。这是两次
可见性观察间隔名义1秒，不是持续可见一秒/服务器确认；localtrue可使collector去重，
即使此前event JSON转换或reporter接受失败。

UIView.pgc_checkFullyVisibled 0x11466967c实际检查self/immediate superview.hidden、
superview/window存在（0x1146696a4/0x1146696bc/0x1146696d8/0x11466971c），把self
frame及superview bounds转换到window坐标（0x114669788/0x114669804），与window/
superview bounds求交（0x114669860/0x114669894/0x1146698b8），交集非empty/null且
width/height等于转换后的frame（0x1146698cc/0x1146698e4/0x114669914/0x11466991c）。
本body不证明兄弟遮挡、alpha、前台scene、所有祖先hidden或实际用户注意力。
cancelEventsForMayReportableObjects 0x11466a21c删除filterKey、取消dispatch block并清
block/association（0x11466a304/0x11466a348/0x11466a35c/0x11466a370）；这不是网络
task cancel，也不撤销此前已调用reporter。

具体UI collection入口之一是SeasonDetailVC.videoPlayerListViewDidReload
0x112007de4→collectVipStrictExposure（0x112007e14→0x112007e30）：先交可选per-VC
batch，再交videoPlayerListView.visibleCells（0x112007ed8）到shared collector
（0x112007ef0/0x112007f08）。另FollowSubVC.viewDidAppear 0x111f37aa0→collect
（0x111f37b5c→0x111f3b698），派weak main callback（0x111f3b6fc），要求vipHeadView
存在且CURRENT tableView.tableHeaderView pointer==vipHeadView
（0x111f3b768/0x111f3b7c4/0x111f3b7c8），才交该view到同collector
（0x111f3b824），接前述VipTipHeadView callback。其他controller/cell触发仍按独立
证据核查，未由这两个入口覆盖全部VIP业务。

具体绑定由BBPgcPadModule.setupModuleInitialize（0x10e32c794）取得
BFCResolver.pgc（0x10e32c7c4），把BFCVipHDServiceImp class（0x10e32c7d8）
registerClass:forProtocol:BFCVipHDService（0x10e32c7e8/0x10e32c7f0）。Home使用
0x104e4de1c、ObjC pgc getter0x104e4de5c经0x104e4daf4使用相同once token
0x120a33510/global0x1210730f0；initializer0x104e4de08→0x104e4df6c包装
SwiftResolver到ResolverBridge。其supplier0x104e4eba4另once创建SwiftResolver
（0x104e4ec88→0x105127b08，global0x121073168），未按请求新建scope。
registerClass0x104e4e1d8取NSStringFromProtocol（0x104e4e22c），转SwiftString
作为key交0x105127fd4（0x104e4e28c）；closure0x104e4e89c→0x104e4e1d0→
0x104e4e170以NSStringFromClass生成所注册class的String（0x104e4e188→
0x107c2c064→0x10f8976c8→0x11711ada4）。classFromProtocol helper
0x104e4e528同样以NSStringFromProtocol（0x104e4e548）查0x105129240
（0x104e4e590），非nilString经NSClassFromString（0x104e4e5c8）变回class。
因此Home/注册端两个静态protocol对象虽地址不同，均名BFCVipHDService并按名称
查找，不能因指针不同否认该绑定。class与object注册槽/覆盖规则仍分别核对，
不宣称运行时永无其他registration。

BBPgcPadModule.name（0x10e32c6f0）为BBPgcPadHD；常规模块
onModuleInitialize0x10e32c6fc读runnableTaskOptEnable（0x10e32c718），true直接
返回（0x10e32c72c），false才发setupModuleInitialize（0x10e32c774）。opttrue替代
入口已接：184项Runnable库存index129/slot0x120274360为
PGCPadGripperModule._$GripperRunnableTaskProviderPGCPadGripper；nominal
0x119488ee8→conformance0x118265280→witness0x11b0c1530的+8接
0x1001d9288/lazy initializer0x1001d9200。3项任务表首pair（0x1001d923c）为
metadata0x11b0c1550/witness0x11b0c14a0；name槽+0x20→0x1001d8f1c返回
PGCPadGripperModuleInitialize，execute槽+0x28→0x1001d8f38→0x1001d92c8。
后者要求idiom==1（0x1001d93ac/0x1001d93b0）及相同runnable once Bool true
（0x1001d93b4/0x1001d93d0），才发送BBPgcPadModule.setupModuleInitialize:
（0x1001d93d8/0x1001d940c），接上述VIP class注册。其余两项名称为
PGCPadGripperApplicationInitializeFinished（0x1001d8fe8）及
PGCPadGripperHomePageInitialized（0x1001d9130），各selector经0x1001d9158同样
idiom1/opttrue门禁（0x1001d91ac/0x1001d91d4）。常规模块的全局注册顺序、
动态DI覆盖/实际flag仍另待证，不能从库存推每次启动所有任务无条件执行。

### Ktor 开关的重复读取、client once 与已创建 task

BFCApiConstWrapper.isKtorRequestEnabled0x105068c64每次resolve注入的
DeviceDecisionService，再getBoolForKey `dd.api_request_use_ktor`、defaultfalse
（0x105068d18/0x105068d1c）。它是独立于dd.http_client_opt和dd_http_client_use_ktor
的第三个开关，未读取实际值。BFCApiRequest的build、completion、queryString及
Operation.main分别读它（0x116095ab8/0x116095e5c/0x11609734c/0x11609751c/
0x11609ac8c），未证构建/发送/响应共享不可变flag snapshot。

main开关true且BFCApiConst.httpClient非nil才client.task(built request)
（0x11609aca4–0x11609acdc），把返回task保存operation ivar
（0x11609acf0，offset global0x11f8b3ed0），安装onCompletion再request
（0x11609ad60/0x11609ad70）；false/nil去另一运输分支0x11609b040。
启动前改变开关可能影响这里选择，不证明已经启动的task迁移engine。
client wrapper0x105067e70另有swift_once token0x120a8e988，initializer0x105067dd0
resolve BFCHttpClient optional并保存object或nil到global0x121073678
（0x105067e5c），后续只读/retain（0x105067e8c/0x105067e90）。真实provider
0x10009b7d0调用此前config-selecting factory0x10009be10，registration0x10009b900
在0x10009ba04接此service；不从registration raw Bool推缓存语义。
有限whole-text ADRP邻接ADD/LDR/STR查找仅找到slot初始化store和getter load，支持
该寻址模式未发现直接cache-reset writer，不能排除间接写/运行时重注册。没有证到
账号或配置observer使这个wrapper重新选择client。

Operation.cancel0x11609c16c→cancelTask0x11609c1b4对已存NSURLtask与BFCHttptask
分别cancel并清ivar（0x11609c1dc/0x11609c1e4、0x11609c1fc/0x11609c204），不重读
ktorflag也不创建替代task。旧task.request的dd_http_client_use_ktor true且disable attr
缺失才set requestType=2（0x1000aa224）；false/nil service/disable key存在分支在
0x1000aa228汇合，此gate不把旧requestType重置，task复用能力仍另待证。

邻接HttpModule DD observer0x10009bd74→0x10009c96c只匹配
`http_load_balance_enable`（0x10009c9a8–0x10009c9cc），要求value非nil，重读配置
后更新LoadBalances（0x10009cb6c→0x10009ed84），不是该body证到的client热替换。
四个公开开关/disable key有限直接引用扫描均为已查读取；尚未闭业务disable attrs/
Enable GInterceptor writer，未找到不能推永不启用。DeviceDecisionService具体DI
实现、remote/local更新及账号context生命周期继续追踪。

DeviceDecisionService已有具体DI绑定：334 component库存的DDModule index85
（0x120272b98）和DDModuleMapper index86（0x120272ba8）；mapper0x10003c8e4在
0x10003c9fc/0x10003ca64绑定该service，provider0x10003d840→callback0x10003d910
resolve/cast BFCIDDContainer（0x10003d91c/0x1000389c0/0x1000389e8），返回container
本身。DDModule注册的container provider0x1000381ac首创建后缓存到.+0x10
（0x100038250），其factory0x10003c3a8实际alloc DDContainerProvider，virtual+0x50
接0x10005832c→0x100058410。这个factory先创建DDContainerV2，再读
KDeviceDecision.shared.defaultDD.isDDAppDisabled（0x100058528）；false返回V2
（0x100058688），true创建legacy DDContainer并把同一个V2挂其containerV2
（0x100058590）。未读取实际disabled值，不能概括实际service必为V2。
V2 getBoolForKey0x10004fbdc以config:nil转core0x10004fc6c，再到Kotlin
IDeviceDecisionKt.getBool（0x10004fd04）；context更新和内部key求值继续核对。
container对象缓存不等于Bool值缓存；API/旧task仍逐次问service，API httpClient
once另冻结已选client对象，两者生命周期分开。

账户通知也有具体DD属性更新入口：184项Runnable库存index46/slot0x120273e50的
DDPropObserverModule，单任务witness0x11b0a49e8的execute槽+0x28接
0x100038f64→0x10003cf20。它resolve BFCAccountNotifyManagerService.Type后初始化
static DDMidPropObserver（0x10003cfac–0x10003cfbc），addNotifyService
（0x10003cfcc）。accountDidLogin0x1000391e0以及logout/update/change
0x10003dbfc/0x10003dc00/0x10003dc04均转0x10003d3f0，resolve optional
BFCDDPropertyService，非nil才propertyChangedFor公开key `mid`（0x10003d498）。
该body不读取实际MID，不取消现有HTTP task、不替换httpClient once、不重跑factory。
V2 propertyChangedFor0x10004f570取lazy property interface（0x10004d608），首次经
KDeviceDecision.shared.property取得并缓存（0x10004d644，ivar0x120277c68），再
onPropertyUpdatedName（0x10004f5c8）。这是账户属性更新边，具体property绑定/
缓存处理见下段；不能等同Ktor开关必变或已选client迁移，legacy0x100046e68另核。

实际KDeviceDecision.shared.property已闭到PropertyCenter。Kotlin export shared
adapter0x10be27910初始化0x1053de844，instance property adapter0x10be28460读
KDeviceDecision.+0x18（0x10be28534）。initializer以DI key0x11c544a58 resolve
（0x1053deb78），调用provider hash0x587 slot+0x10并存.+0x18
（0x1053debd0/0x1053debd8）。Root registration0x10b92ca8c使用相同key
（0x10b92caf4），捕获getter0x10b91fad4的provider（0x10b92cafc）；该getter读
Root.+0xc0，其cached SwitchingProvider id26分支0x10b93d4d4→0x10a9bdf98。
lambda TypeInfo0x11bb206a0/invoke0x10a9bf214最终取DDContainer hash0x1c83
slot+8（0x10a9bf378）。依赖Root.+0x80的id18分支0x10b93d134→0x10a9bdbe4，
lambda0x11bb204c0/invoke0x10a9bed10再构造factorylambda0x11bb20ba0。
其invoke0x10a9c05a0分配DDContainer TypeInfo0x11bb21500
（0x10a9c0734/0x10a9c0738），constructor0x10a9c3994分配PropertyCenter
TypeInfo0x11bb272e0（0x10a9c4488/0x10a9c448c）并存container.+0x30
（0x10a9c4ec0）；所选hash0x1c83 slot+8 getter0x10a9c656c正读.+0x30
（0x10a9c6578）。因此不是只凭唯一interface候选推注入；不提升为全部legacy路径。

onPropertyUpdatedName export row0x11ccf7818→adapter0x10be23ccc，hash0x3c00
slot+0x10接PropertyCenter0x10a9f5ea4。它捕获center/name到lambda0x11bb274c0
（0x10a9f5f64），以scope.+0x20 launch0x1052b31c0（0x10a9f5f7c），返回不等
重求值完成。lambda invoke0x10a9f6d94在center.+0x40按name同步Map.get
（0x10a9f6df8/0x10a9f6e00→0x10a9c0a18），nil跳过（0x10a9f6e04），非nil
才处理entry0x10a9f5fac（0x10a9f6e18）。这不是按通知name直接删全部决策cache。

entry处理先锁center.+0x38（0x10a9f6064），按0x10a9f5d3c判断eligibility
（0x10a9f6080），再原子取entry.+0x10内的当前provider
（0x10a9f60ac–0x10a9f60b8）。eligibility=false或provider缺失时，按name从
center.+0x28 cache remove（0x10a9f6150→0x10a9c0de4）。该cache同步holder
0x10a9c0920内分配Kotlin HashMap TypeInfo0x11b371e80
（0x10a9c0990/0x10a9c0994），hash0xa00 slot+0x30→0x1052468e8先find index
（0x105246964→0x105247f7c），再remove index（0x105246998→0x105248628），
这里是实质单name删除；entry.+8及center.+8参与eligibility，未套未经核对的政策名。

eligible时取旧cache、尝试新source0x10a9f6544（0x10a9f60e0/0x10a9f60f4）；
返回对象.+0x10缺失时退entry provider0x10a9f7110，provider仍nil退entry snapshot
.+0x10（0x10a9f71ec/0x10a9f71f8–0x10a9f7210）。old.equals(new)为true便跳过
写入和事件（0x10a9f6120/0x10a9f6124）；变化才按name Map.put
（0x10a9f6190→0x10a9c0b5c，具体HashMap0x1052462e8）。删除/变化两路才launch
lambda TypeInfo0x11bb27560（0x10a9f6294/0x10a9f62ec）；invoke0x10a9f6e64
向center.+0x30 hash0x483 slot+8发property name（0x10a9f6edc）。此事件到决策依赖/结果cache失效见下段；不保证账户callback返回时Bool已变，不取消
现有HTTP task或迁移once client。未读实际name对应属性值。

V2 Bool查询也已接同一DDContainer，而非只闭property。getBoolForKey:defaultValue:
config:0x10004fd34取lazy dd（0x10004fd7c→0x10004d5e0，ivar0x120277c58），
交core0x10004fc6c（0x10004fd94）再Kotlin getBool adapter。KDeviceDecision.dd
以key0x11c544a38 resolve并存.+8（0x1053de9c8/0x1053dea20/0x1053dea28）；
Root registration0x10b92c958使用同key（0x10b92c9b8）及getter0x10b91f5cc的
Root.+0x88 cached provider id17。id17分支0x10b93cef4→0x10a9bdd28的lambda
TypeInfo0x11bb20560/invoke0x10a9bf3a8 resolve上述id18、直接返回同DDContainer
（0x10a9bf4b4/0x10a9bf4bc）。因此V2 dd与property来自相同安装的父container。
export row0x11cd0fb30→0x10bf1cf94→helper0x1053ddeec，经decision hash0x3b00
slot+8（0x1053ddfe0）接该TypeInfo0x11bb21500的0x10a9c68d8。每次查询先从
container.+0x38调用evaluator0x10a9dbd1c（0x10a9c69a4–0x10a9c69b4），其结果
cache/依赖失效及最终类型/状态转换见下段。外围Bool helper仅nonnull才取boxed Bool.+8
（0x1053ddfec），nil保留原default并返回（0x1053ddfe8/0x1053ddffc）；不能将
Ktor defaultfalse读成开关永远false，也不能由对象一致性推全部决策cache已重置。

DecisionCenter的属性flow消费者已接实。DDContainer constructor分配
TypeInfo0x11bb24920并存container.+0x38（0x10a9c4ecc/0x10a9c4ed0/0x10a9c5170），
把已证PropertyCenter存DecisionCenter.+0x10（0x10a9c4f28/0x10a9c4f68）；另建
.+0x28/.+0x30两个同步cache holder（0x10a9c4fe0/0x10a9c503c）。constructor无条件
launch observePropsUpdate lambda TypeInfo0x11bb24ce0（0x10a9c5100/0x10a9c5160），
不等待collector安装。invoke0x10a9dd5b0经PropertyCenter hash0x7081 slot0
（0x10a9dd670）→0x10a9f4dc0读取同一.+0x30 flow并包装read-only flow
（0x10a9f4ddc/0x10a9f4de4），构造collector TypeInfo0x11bb24d80并collect
（0x10a9dd688/0x10a9dd71c）。

collector0x10a9dd754枚举DecisionCenter.+0x28的keys（0x10a9dd7f4），逐项取当前
entry（0x10a9dd994），nil跳过；只在entry.+0x10 dependency collection.contains
通知name为true时收集该decision key（0x10a9dd9ec/0x10a9dda08），交0x10a9dce28
（0x10a9dda28）。后者逐key remove .+0x30（0x10a9dd020），取/删除.+0x28 entry
（0x10a9dd030/0x10a9dd048）；source helper0x10a9dcb4c缺失时以context=nil调用
0x10a9dc15c重求值（0x10a9dd058/0x10a9dd0dc/0x10a9dd0e0），old/new status与value
比较再决定后续通知（0x10a9dd060–0x10a9dd0b8）。正常query也在0x10a9dc15c按key
读.+0x28，命中返回cached item.+8（0x10a9dc288/0x10a9dc294/0x10a9dc29c）；因此
已证删除的是实际查询结果cache。.+0x30另作辅助Bool cache，result.+0x11==1时才
可写boxed Bool（0x10a9dc6d0/0x10a9dc6d4/0x10a9dc6ec–0x10a9dc70c），不把它直接
等同公共getBool最终返回值。

默认配置观察者的通知源是DecisionCenter.+0x20：constructor以0/0、nil、mask6
调用flow factory 0x1052dff68并保存（0x10a9c4f74..0x10a9c4f88）。它不同于
DataCenter的node flow。didKeysUpdated 0x10a9dce28在old cache缺失
（0x10a9dd034）或old/new结果比较需要通知时，构造lambda TypeInfo 0x11bb24e20
（0x10a9dd114/0x10a9dd120/0x10a9dd124），捕获center/key并在scope.+0x18 launch
（0x10a9dcf44/0x10a9dcf5c）。invoke 0x10a9ddb48读center.+0x20
（0x10a9ddb6c），hash0x483 slot+8 emit该key（0x10a9ddbc0）；相同结果跳过通知。
DDContainer默认observer 0x10a9c983c从container.+0x38取同一flow并read-only包装
（0x10a9c9af8..0x10a9c9b0c），安装仍受container.byte+0x50==1门禁。
observer从静态enum集合0x120c5b338取各enum.+0x18，保存为captured key collection
（0x10a9c9928/0x10a9c9a24/0x10a9c9af0/0x10a9c9b60）。transform
0x10a9ca158→0x10a9c9e44遍历captured集合（0x10a9c9f74/0x10a9c9fe0），
向下游emit各key（0x10a9ca058），但这是onStart预发：factory 0x1052ed940
实际TypeInfo 0x11b38bfd0为onStart$$inlined$unsafeFlow$1，collect 0x1052ee6e8。
订阅开始预发默认key全集；之后filter TypeInfo 0x11bb22060/collector 0x11bb22100
body 0x10a9ca3ac对incoming key做captured集合contains（0x10a9ca410/0x10a9ca414），
不命中返回Unit，命中才downstream emit。不能把onStart遍历称每次变化通知重发全集。
collector TypeInfo 0x11bb221a0/body 0x10a9ca4d4以0x1053df1dc查enum
（0x10a9ca5a4），normalize 0x10523c6b8后遍历0x120c5b330并比较enum.+0x18
（0x1053df25c/0x1053df290/0x1053df298）。nil lookup返回Unit（0x10a9ca700）；
命中则getString(key,nil,nil) 0x1053dddd8（0x10a9ca5c8），再将enum和String/nil
交container.+8的hash0x3d80 slot+8 setter（0x10a9ca624）。

该setter的具体依赖也已接实：container ctor保存x2到.+8（0x10a9c3a38），factory
从lambda.+0x10取x2（0x10a9c0774），依赖经0x10a9bed10/provider hash0x584/
producer hash0x587（0x10a9bee70/0x10a9beecc）存入lambda（0x10a9bef40）。
Root getter 0x10b91f45c读Root.+0x78（0x10b91f4b4），该字段由cached
SwitchingProvider ID20构造（0x10b930e38/0x10b930e44/0x10b930e48）；
table 0x118652e72 entry20→0x10b93cf9c→0x10a9be340（0x10b93cfd0），
getterlambda TypeInfo 0x11bb20880捕获config-module provider（0x10a9be3b0/
0x10a9be3f4）。实际get 0x10a9bf67c创建provideDDDefault$1 TypeInfo
0x11bb22240（0x10a9bf7c0/0x10a9bf7c8）及SharedPreferences 0x11b3b6230
（0x10a9bf874/0x10a9bf87c），调用constructor 0x1053e0058并保存wrapper.+8
（0x10a9bf8c0/0x10a9bf8c4）。固定suite公开literal 0x11cb2d540为
`dd-default-config`，此factory无账号参数，不推其他writer/clear不存在。
native peer通过NSUserDefaults.initWithSuiteName创建defaults
（0x1053e02f0），存peer.+0x10及Kotlin wrapper.+8
（0x1053e034c/0x1053e0374）。setter 0x10a9cab98总用原enum.key.+0x18
（0x10a9cabb8），nil替换公开sentinel `__DD_DEFAULT_NULL_VALUE__`
（literal 0x11cb2d4b0；0x10a9cabc4/0x10a9cabc8），tail 0x1053e2a2c
（0x10a9cabe4），先type validation 0x1053e20c0（0x1053e2aa8），再对peer
defaults setObject:forKey:（0x1053e2ab0/0x1053e2c10）。本地调用不是磁盘同步或网络ACK。

同一wrapper的getter 0x10a9caa3c还有快照分支：byte+0x10由config-module
hash0x28500/+0x50初始化（0x10a9bf864/0x10a9bf868）；==1
（0x10a9caab4..0x10a9caac4）读原key（0x10a9caad8），把原值或nil sentinel写到
原key+公开suffix `::to_sub_process`（literal 0x11cb2d500；
0x10a9caaec..0x10a9cab1c），返回原值（0x10a9cab20）。!=1只构造/读取suffixed key
（0x10a9cab44..0x10a9cab68）。read helper 0x10a9ca958→0x1053e25d4
（0x10a9ca9c0..0x10a9ca9d0）实际NSUserDefaults.stringForKey:
（0x1053e2748），nil传播，sentinel映射nil（0x10a9ca9ec..0x10a9caa00）。
因此setter写原key、条件getter才复制到快照key；不把两分支称同key无条件读取。
该Bool实际依赖也已闭：Root.+0x70由ID19构造（0x10b930db0/0x10b930dc0），
table entry19→0x10b93d32c→0x10a9bdb34（0x10b93d348）。后者把静态producer对象
0x11cb2cd38交module hash0x2b00/+8（0x10a9bdbd0）；此地址不是String DI key。
对象tagged TypeInfo为0x11bb20421，去tag后0x11bb20420，即providesRawProducer0$1，
hash0x584实现0x10a9be478；其associated static provider 0x11c32e6f8亦同实现。
该body实际分配DDNativeArgs TypeInfo 0x11bb28880（0x10a9be4e8），其hash0x28500
slot9/+0x48→0x10a9c0530、slot10/+0x50→0x10a9c0504均返回Bool true，不读取
运行配置字段。因此此native绑定上的observer start gate为true，default getter走
原key读取并写suffixed snapshot分支；保留getter自身false分支，不声称其他实现不存在。
默认enum集合六个公开key为`dd.default.app_disable_kntr_impl`、
`dd.default.enable_core_data_v2`、`dd.default.observable.props`、`dd.default.focus.props`、
`dd.default.update_host`、`dd.default.update_host_configs`；不含`dd.http_client_opt`。
默认持久化getter有具体消费者：factory 0x100058410取KDeviceDecision.shared.defaultDD
并调用isDDAppDisabled:（0x100058528）；export row 0x11cd0fb60→adapter 0x10bf1d3a8
选enum ordinal0/app-disable（0x10bf1d4e0）→0x1053df370（0x10bf1d4ec），后者调
receiver hash0x3d80 slot0（0x1053df448）。nil为false，exact String `true`或`__true__`
为true，其他String为false（0x1053df450/0x1053df470/0x1053df4a8）。该factory先创建V2，
app-disable=false选V2，true构造legacy并附上同V2；这是DD service选择，不直接选择
HttpClient类。HttpClient factory 0x10009be10仍单独query `dd.http_client_opt`，
default=false（0x10009bec8），选择HttpClientOpt/BFCHttpClient
（0x10009bee4..0x10009bef0）。defaultDD DI对象与消费getter的一致性继续追。
默认持久化getter与正常V2 DecisionCenter query仍是不同消费路径；已查observer setter不直接
调用client factory或清API once。已有HTTPClient是否采用后续更新仍待核，未读取持久化值。

由此闭合账户callback→mid属性通知→异步属性变化/删除→name flow→依赖该name的
决策key→其结果cache失效/重求值。未登记name、属性值未变，或决策依赖不含mid，
均不会经此collector清该决策；未读取实际远程key/依赖配置。最终Bool类型/状态转换见下段；
legacy分支及业务enable/disable writer仍待核，未证once client替换或现有task取消。

V2公共Bool的evaluator-result转换也已闭到实际返回值。DecisionCenter.Result为
TypeInfo0x11bb249c0，分配0x10a9dc48c/0x10a9dc494，.+8为boxed status、.+0x10为
payload、.+0x18为辅助byte；初始化清两reference和byte
（0x10a9dc4d0/0x10a9dc4d4）。它不同于formula reply的.+0x10/.+0x11及前述辅助
cache。getBool的0x10a9c68d8取得此result后按下表转换，不读取实际远程值。

| status | payload | 返回Bool及地址 |
| --- | --- | --- |
| nil | 任意 | supplied default，0x10a9c6a28/0x10a9c6aa4→0x10a9c6c54 |
| false | 任意 | false，0x10a9c6c18/0x10a9c6c1c |
| true | nil | true，0x10a9c6ad4→0x10a9c6c50 |
| true | equals `__true__` | true，0x10a9c6aec–0x10a9c6afc |
| true | 其他nonnull | equals `true`的比较结果，0x10a9c6c38/0x10a9c6c40/0x10a9c6c48 |

两个静态schema sentinel为KString0x11c544dc0/0x11c513bd0；该body调用payload
的equality，不trim/lowercase或通用parse数字1，不假定任意运行类型已经校验。
Bool box0x10a9c6c64→return0x10a9c6c7c→公共helper读.+8（0x1053ddfec）；外围
nil-object fallback与内部status=false、payload=nil三者不同。异常landing pad
0x10a9c6dec仅TypeInfo id落[0x3e4,0x49e]才日志并走fallback
（0x10a9c6e24–0x10a9c6e30/0x10a9c6f14–0x10a9c6f20），其他rethrow
（0x10a9c6f24/0x10a9c6f28）。尚未将范围内所有异常逐类命名，不能宣称全部失败
均吞掉或fallback代表远程接受。

### DD 生产启动、配置 key 更新与响应版本触发

DDModule Runnable metadata0x11b0a4a38/witness0x11b0a4920.+0x28指向exec
0x100038680；解析BFCIDDContainer dependency typeref0x1202753e8
（0x100038690/0x1000386f8），保留actual container receiver并start
（0x1000386fc/0x10003870c），随后helper0x10003c5ac（0x100038714）。
V2.start0x10004dff0→0x10004d6e0（0x10004e004）取lazy dd0x10004d5e0，分别安装
versionsAsync:（0x10004d91c）与keysAsync:（0x10004dcc4），通过本实例
SerialDispatchQueueScheduler（ivar descriptor0x120277c50；0x10004d724/0x10004d728/
0x10004d794/0x10004d848）。version callback0x10004d9f4排队0x10004dc44，在
defaultCenter postNotification object=nil（0x10004dc64/0x10004dc8c）；keys callback
weak-load原V2（0x10004ddb4），存在才交0x10004ddec（0x10004ddcc），通过observerQueue
（descriptor0x120277c48；0x10004de94/0x10004de98）排队。这不是重建HTTP client。

DecisionCenter还在constructor安装与property observer独立的配置key coroutine
TypeInfo0x11bb24ba0（0x10a9c506c/0x10a9c50b0/0x10a9c50c8）。invoke0x10a9dd3dc
取IDataCenter hash28680 slot+8（0x10a9dd4a4），actual DataCenter TypeInfo0x11bb23640
的0x10a9d4910返回.+0x18 flow-container，读取其.+0x10（0x10a9dd4ac），构造collector
TypeInfo0x11bb24c40并collect（0x10a9dd520）；emit0x10a9dd554直接将notified key-list
与DecisionCenter交此前selective cache invalidation/re-evaluation0x10a9dce28
（0x10a9dd578）。这里输入本身是配置keys，不重做property dependency membership筛选。
Kotlin实际DI producer0x10a9c05a0在constructor之后（0x10a9c077c），仅container.byte
.+0x50==1才launch DDContainer$start$1 TypeInfo0x11bb217e0
（0x10a9c07ac/0x10a9c07b4/0x10a9c07c4/0x10a9c0818），同gate安装
observeDefaultConfigKey TypeInfo0x11bb21da0（0x10a9c0864/0x10a9c08b8）。该byte是
constructor从依赖hash0x28500 slot+0x48取得并保存（0x10a9c3ae0/0x10a9c3ae4），
未读取其实际配置值；不得与Swift V2.start Rx观察安装合为无条件刷新。

下载前半段是独立native NSURLSession：wrapper0x10a9fb934→0x10a9fb444构造
DDDownloader$download$2（0x11bb25a60），invoke0x10a9e59f4→0x10a9e5354
→downloadWithRetry coroutine body0x10a9e39b8（0x10a9e593c）。后者候选URL构造
NSURL/request（0x10a9e41f0/0x10a9e4318），使用ephemeralSessionConfiguration
（0x10a9e44c4），cachePolicy raw1（0x10a9e45d0）、URLCache nil（0x10a9e4680），
sessionWithConfiguration（0x10a9e4794）→dataTaskWithRequest:completionHandler:
（0x10a9e49dc）→resume（0x10a9e4ae0）；不套用公共Ktor签名或gateway。
completion block0x10bf6e42c连接callback TypeInfo0x11bb289c0实际方法0x10aa00020：
NSError非nil优先失败（0x10aa000b4），data缺失或HTTPResponse缺失/类型不符也失败
（0x10aa00148/0x10aa0014c/0x10aa002a0）；status只接受200..299
（0x10aa00318/0x10aa0035c..0x10aa00364）。随后NSData.writeToFile:atomically:true
（0x10aa00434..0x10aa00440），写false走失败（0x10aa00474/0x10aa006d0）；只有成功
写入才resumeWith Unit（0x10aa004dc），进入后述read/parse/version gate。
外层失败转UpdateException.DownloadFile（0x11bb280d0，0x10a9fb614/0x10a9fb618），
不是政策apply完成。取消handler TypeInfo0x11bb28a60捕获原task+8
（0x10a9e4b60），注册0x1052b6ab0（0x10a9e4b68）；实际0x10aa00950调用task.cancel
（0x10aa00a30），不等于撤销已写文件或回滚缓存。

重试body0x10a9e39b8读取配置max integer+0x18（0x10a9e3b28..0x10a9e3b38），
negative直接exhaust；index从0（0x10a9e3b40），collection+0x10按index取候选
（0x10a9e3bcc），nil或index>max结束（0x10a9e3bd0..0x10a9e3be0）。只对捕获的
Throwable TI id范围[0x3e4,0x49f)失败重试（0x10a9e51c4..0x10a9e51cc），
保存lastError（0x10a9e51d0），未到max则index+1回边（0x10a9e5308..0x10a9e5310），
exhaust重新throw lastError，无error则构造generic exception（0x10a9e5314..0x10a9e5348）。
成功返回Unit（0x10a9e3ad8..0x10a9e3ae4）绕过重试。故非负max=N时最多N+1个索引，
还受候选数限制；未读取实际N、URL、文件内容或策略值，候选/max构造来源继续核。
0x105cd7264仅File/path对象构造，不能当作字节写盘边界。

实际DateCenterFlow.didUpdatedNodes emitter0x10a9d77cc先检查incoming collection
isEmpty（0x10a9d786c），空则返回；非空launch TypeInfo0x11bb23fc0 coroutine
（0x10a9d78d0/0x10a9d7910/0x10a9d7928），body0x10a9d7eb0读同一个flow-container
.+0x10（0x10a9d80d8），hash0x483 slot+8 emit collection（0x10a9d8134）。已闭此flow的
emit→collector→缓存失效。DataCenter TypeInfo0x11bb23640/hash0x28680 slot+0x10实际
body0x10a9d4a70从.+0x28/0x38/0x30三CoreData取key collection
（0x10a9d4d6c/0x10a9d4dc0/0x10a9d4e24），合并（0x10a9d4dd4/0x10a9d4e38）并交
该emitter（0x10a9d4e44）。UpdateEngine apply→CoreData→nodeflow也已闭：coroutine0x10a9f91f0调用download wrapper
0x10a9fb934（0x10a9f9e44），resumed0x10a9f92c4恢复continuation，再读序列化配置
0x10a9e7230/parse0x10a9f1aa0（0x10a9f930c/0x10a9f9318）。数据nil分配ReadFile
exception TypeInfo0x11bb28180（0x10a9f93d4/0x10a9f93d8）；parsed nil或其version.+0x10
与目标不等（0x10a9f9320..0x10a9f932c）分配Serialize TypeInfo0x11bb28230
（0x10a9f9374/0x10a9f9378）。两分支清updating atomic Bool（0x10a9f9470）后绕过apply
（0x10a9f9478→0x10a9f98ac），不概括全部下载异常。

接受后取installed IDataCenter.+0x20，hash0x28680 slot+0x18
（0x10a9f9340/0x10a9f94ac）→actual DataCenter0x10a9d49ac，按environment enum==1
选.+0x38、否则.+0x40（0x10a9d4a04..0x10a9d4a2c），不是账号隔离。对actual CoreData
hash0x28600 slot+0x10传parsed config（0x10a9f94fc/0x10a9f9504），成功路径清updating
（0x10a9f9640）。DDContainer ctor实际factory0x10a9d5e40两次构造并存上述DataCenter
字段（0x10a9c4104/0x10a9c410c/0x10a9c4150/0x10a9c4154）。输入Bool非零alloc
CoreDataV2 TypeInfo0x11bb22a60（0x10a9d5ee0/0x10a9d5ee4/0x10a9d5ee8），零alloc
CoreData TypeInfo0x11bb222e0（0x10a9d6e88/0x10a9d6e8c），保留两分支，未读配置值。

CoreData slot+0x10=0x10a9cbd74→0x10a9cbdd0，wrapper/default mask使w26=1/w24=0
（0x10a9cbd80..0x10a9cbd90/0x10a9cbe0c..0x10a9cbe28），绕过另一incoming-version<=
stored拒绝（0x10a9cbed0..0x10a9cbee4）。mutex下写version atomic.+0x28
（0x10a9cc4c0..0x10a9cc4d8），安装collections到atomics.+0x30/+0x38/+0x40
（0x10a9cc524/0x10a9cc570/0x10a9cc67c），通知gate为true
（0x10a9cc788..0x10a9cc794），交node-key集合到同0x10a9d77cc（0x10a9cc90c），second
集合另交0x10a9d7950（0x10a9cc91c）；随后launch persistence0x10a9cc9dc
（0x10a9cc920..0x10a9cc930），不是磁盘完成ACK。
CoreDataV2 slot+0x10=0x10a9cf184→0x10a9d0490（0x10a9cf190/0x10a9cf194，w2=1），
同样绕过另一version拒绝（0x10a9d054c..0x10a9d055c），写version atomic.+0x38
（0x10a9d07f8/0x10a9d0810）与collections atomics.+0x40/+0x48
（0x10a9d0880/0x10a9d08d8），经0x10a9d1818（0x10a9d08f8）交node-key list到同emitter
（0x10a9d1a24..0x10a9d1a38），second集合另交0x10a9d7950（0x10a9d1a40..0x10a9d1a54）。
因此两实际backend的非空node通知都能进入DecisionCenter缓存失效；空集合仍不发node
事件。下载网络result/error及file-write完成→resumed readback、默认配置event owner
仍待核；响应header触发不能当apply完成，也不替换既有client/task。

V2 synchronous updateWith:0x1000510ac取lazy updater（0x1000510e0），传provided String
与from=dd-v2到updateFrom:remoteData:（0x100051124），返回对
KntrIDeviceDecisionUpdaterResultSuccess dynamic-cast的Bool
（0x100051160/0x100051168/0x100051184），非调用即成功。
带force/test/from/completion版本0x100051780→0x10005119c（0x10005183c）按test选择
version env test/prod（0x1000511f8..0x100051204）；force bit true选
updateToLatestFrom:env:completionHandler:（0x100051254/0x1000512d4），false选
updateFrom:version:env:completionHandler:（0x10005138c）。两者是不同更新入口，回执另核。

真实native响应caller是DDApiGatewayInterceptor.canonicalGatewayResponse:
0x100135360→0x100135830（0x100135390）：取HTTPResponse.allHeaderFields
（0x100135894），必须response存在且cast为HTTP response
（0x100135868/0x100135884/0x100135888），本地request-header helper0x1001353c0所得dict
非空以及response allHeaders非空（0x1001358d4/0x1001358dc/0x1001358e0/0x1001358e4），
才lookup公开dd-v（0x100135980/0x1001359c4）。missing/nil结果
（0x1001359f0/0x1001359f4/0x100135a08）直接走释放/return（0x100135aa4），不会变成0。
存在非nil值时转换优先
String cast（0x100135a94），否则Int cast（0x100135ae0），失败置0
（0x100135ae8/0x100135aec）再description（0x100135b04）；result非空
（0x100135b20）resolve actual DD container（0x100135b28/0x100135b40），调用
updateWith:force:test:from:completion:（0x100135b9c），force=false（0x100135b90）、
from=http（0x100135b68..0x100135b74）、completion=nil（0x100135b98），test来自局部
ENV与test比较（0x1001358f8..0x10013594c）。本地helper读取cached SwiftString
0x121064b70，nil/empty则empty dict（0x100135404..0x100135418/0x100135568），非空分支
生成公开APP-KEY及ENV，ENV由服务isTestEnv（0x1001354f8）选prod/test；不要求response
含ENV，也未读取cached String实际值。存在非nil但String/Int都cast失败的dd-v会生成
String0，仍满足非空并触发update；原String为空则跳过。更新触发不代表成功或业务ACK。

该gateway有production注册：334 raw0 service zero-based index89/slot0x120272bd8
为BFCDDModule._$GripperDDUpdatePlugins。registration0x10003e144把API gateway
multibinding typeref0x120276370、provider metadata0x10003e53c（class0x120276460）、
callback0x10003e710、witness0x1202769c8交0x10513162c（0x10003e1cc，w5=1）。
witness.+0x10=0x10003dc20调用DDApiGatewayInterceptor metatype accessor
0x100135c2c（0x10003dc34），确为实际provider。同module另注册Moss gateway
（0x10003e214/0x10003e248；producer0x10003dc48→DDMossGatewayInterceptor metadata
0x100137f40及init0x1001376d4）。Moss response版本消费另核。native公共controller的
class实例化/canInit/response转发范围适用；不覆盖已知Ktor skip-gateway分支。
配置缓存失效也不自动替换once-cached HttpClient或迁移/取消已创建task。

### HD2 CardPool 的模型映射与实际 cell 注册

allModelClassDict（0x10df17d84）构造8项，缓存global0x120c98038。下表model类
均使用BBHD2PhonePegasus前缀；这不是任意card_type经NSClassFromString的回退。

| card_type | model类后缀 | class取值指令 |
| --- | --- | --- |
| large_cover_v1 | LargeCoverV1Model | 0x10df17dc0 |
| small_cover_v1 | SmallCoverV1Model | 0x10df17ddc |
| hot_topic | HotTopicModel | 0x10df17df8 |
| small_cover_v9 | SmallCoverV9Model | 0x10df17e14 |
| cm_v1 | AdSingleModel | 0x10df17e30 |
| three_item_all_v2 | ThreeItemAllV2Model | 0x10df17e4c |
| small_cover_v5 | SmallCoverV5Model | 0x10df17e68 |
| banner_ipad_v8 | BannerListModel | 0x10df17e84 |

allCardClassDict（0x10df17b1c）另构造17项，缓存global0x120c98030。下表cell类
除最后一项全名外，均使用BBHD2PhonePegasus前缀。

| reuseIdentifier | cell类后缀或全名 | class取值指令 |
| --- | --- | --- |
| local_refresh_v1 | MainRefreshCell | 0x10df17b58 |
| local_refresh_v2 | DoubleMainRefreshCell | 0x10df17b74 |
| local_dislike_v1 | SingleDislikeCell | 0x10df17b90 |
| local_dislike_v2 | DoubleDislikeCancelCell | 0x10df17bac |
| local_dislike_v3 | DoubleThreePicDislikeCancelCell | 0x10df17bc8 |
| local_dislike_v4 | DoubleDislikeV2CancelCell | 0x10df17be4 |
| local_dislike_v5 | SingleDislikeV2Cell | 0x10df17c00 |
| local_dislike_v6 | SingleDislikeV2ReasonsItemCell | 0x10df17c1c |
| local_dislike_v7 | DoubleBigCardDislikeCancelCell | 0x10df17c38 |
| local_dislike_v8 | DoubleThreePicDislikeV2CancelCell | 0x10df17c54 |
| large_cover_v1 | LargeCoverV1Cell | 0x10df17c70 |
| small_cover_v1 | SmallCoverV1Cell | 0x10df17c8c |
| small_cover_v9 | SmallCoverV9Cell | 0x10df17ca8 |
| cm_v1 | AdSingleCell | 0x10df17cc4 |
| local_dislike_cm_v1 | AdSingleDislikeCell | 0x10df17ce0 |
| small_cover_v5 | SmallCoverV5Cell | 0x10df17cfc |
| banner_ipad_v8 | BBHD2PegasusBannerV8Cell | 0x10df17d18 |

实际消费者是BaseCollectionVC.viewDidLoad（0x10dee53f0）：取CardPool映射
（0x10dee5688/0x10dee568c）并enumerate（0x10dee56e0）；callback0x10dee5ee0
弱读原VC的collectionView，以value注册class、key注册reuseIdentifier
（0x10dee5f28）。MainV2继承此base。cellForItem（0x10dee9488）对CURRENT VM.objects
做行边界检查，取当前model（0x10dee9540），要求BBHD2PegasusCardModelProtocol
conformance（0x10dee9564/0x10dee956c）；成立则直接用model.card_type dequeue
（0x10dee9578/0x10dee9594），设置delegate/context并installWithObject(model, argv:nil)
（0x10dee95f8）。越界或不符合protocol则走generic空cell（0x10dee9630）。
8项转换映射与17项cell注册分别承担不同职责；hot_topic/three_item_all_v2可转换不证明
普通cell已注册。动态注册、subclass覆盖与model自定义映射尚有边界，不由两表差异推断
运行时崩溃或不可达。

### HD2 设置响应字段到可见行及提交边界

FeedSettingVC.cellForRow读取当前dataArray[row]（0x10df07c40）后调用
FeedSettingCell.installWithObject（0x10df07c60）。install0x10df081dc先校验model类
（0x10df08214），title→myTitleLabel.text（0x10df08228/0x10df08250），
desc→myDescLabel.text（0x10df08268/0x10df08290），selected取反→checkImageView.hidden
（0x10df082a8/0x10df082d0）。这不是按value硬编码文案；错误model类型直接返回，
此body不清除复用cell原文案/check，实际复用呈现未运行验证。

新VC初始化仅对匹配项setSelected，不setSelectedModel；正常新实例未点选任何行时，
viewDidDisappear的selectedModel nil门禁（0x10df07a70）不提交followState。
已使用VC若复用，selectedModel未在已核viewDidLoad/viewWillAppear重置，不能把该
新实例结论外推到所有后续消失。MainVM.feedStateChangeWithDic（0x10df5b62c）只验证
input count、转换后的typed model及非nil，不要求option非空、title非空、唯一selected、
value在0/1内或已登录；客户端不能证明服务端发送此配置的生产原因/实验约束。

缺失/空follow_mode分支先置needFeedStateSetView=false（0x10df5b6d4），再把state1
转2（0x10df5b6fc）。KVO消费者重读needflag并以false跳过刷新；没有其他交错writer时，
这个响应驱动state写入自身不能满足刷新门禁。有效typed响应写feed_mode并置needflag=true
（0x10df5b6b0/0x10df5b6bc），不写followState；用户提交/其他选择事件另写state，
不能把这些producer合成无条件的‘响应模式变化立即重发’。
