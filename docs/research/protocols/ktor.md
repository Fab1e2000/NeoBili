# Ktor 桥接与公共参数

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## Ktor 桥接与公共参数

`KtorClientObjc.request:priority:method:signType:bodyData:completionHandler:`
（0x10502edb0）桥接到 Swift 构造函数 0x10503031c，创建 HttpClientOpt，传入 method、
signType、bodyWithData、priority 和完成回调，metricsType 固定为 0，再 request。
另一构造变体（0x1050304f8）传入 signType=3；不能据此概括所有业务请求。

NetParamImp 的 SessionId/GuestId 为服务 getter 的桥接，缺值回空字符串；
getDisableRcmd（0x1000b3e08）读取 disablePersonalizedRcmd 设置，getFiltered
（0x1000b3eb8）读取 inReview。这些入口证明设置会进入公共参数来源，尚未证明所有
Ktor 请求最终都带它们。**Ktor 侧装配点已定位（本轮闭合）**：`NetParamImp` 是
`_TtC17BFCHttpSignModule11NetParamImp`（Swift，**与 native HttpSign listener 同一个模块**），
getter 为 `getSessionId` 0x1000b3b8c、`getGuestId` 0x1000b3c88、`getMobiApp` 0x1000b3cf0、
`getBuild` 0x1000b3dbc、`getStatistics` 0x1000b3dc8、`getDisableRcmd` 0x1000b3e08、
`getFiltered` 0x1000b3eb8；Kotlin 侧（0x10aa…/0x102b… 地址段）经 selref 装载后派发：
`getGuestId` selref 0x11f79c2b8 → 0x10aacc370 ∈ `sub_10AACC114`；`getDisableRcmd` selref
0x11f79c2c8 → 0x10aac5908 ∈ `sub_10AAC566C`；`getMobiApp`/`getStatistics` selref
0x11f790fd8/0x11f790fe0 → 同一函数 `sub_102B25740`（0x102b25b8c/0x102b25ce0）；
`getSessionId` selref 0x11f798d48 → 0x1049573b0 ∈ `-[DeviceServiceImp sessionId]`（桥回服务）。
即 Ktor 侧的身份参数由该 Swift 桥提供，**不是复用 native HttpSign listener 的 `setHttpHeader` 路径**。
剩余：这些值最终写成哪些 Ktor header/parameter（哪些经过 `CommonParamsPlugin`、哪些经 Ktor
request headers）仍需按插件断言核对。Moss 的常量 wrapper 另提供 accessToken、guestID、xTrackID、
deviceToken、网络代码、restriction、gaia 与回退配置入口，待逐个追到编码器。

BFCHttpSignModule 的原生 HttpSign listener（0x1000b2860）通过 0x1000b5484 组装
Buvid=BFCBuvid.buvid、Session_ID=注入 BFCDeviceTraceService.sessionId、x-bili-trace-id=
同服务.getXTraceId，再逐项 setHttpHeader。dd.http_sign_buvid 配置影响赋值顺序：
flag 为真先注入，再检查 requestSignType==3 并返回；flag 为假时，只有
requestSignType!=3 才后注入。因此 signType=3 并不在所有配置下都省略这些头。
listener 在 Ktor 引擎中的安装范围已闭合为**不安装**：原生 Listener 多绑定只由4个模块提供
（BFCHttpSignModule accessor 0x1000b2600、BFCHttpUserAgentModule 0x1000b830c、
BFCHttpTrackerModule 0x1000b91d4、NetworkFlowControlModule 0x10495bce0），消费点是旧
BFCHttpTask 的 application interceptor 分发：0x1000aae94/0x1000aae98读ivar
BFCHttpTask.requestType（`[x8,#0x500]`）→0x1000aae9c ldrb→0x1000aaea0 `cmp w8,#2`
→0x1000aaea4 `b.eq 0x1000aafcc` **直接跳过整套 listener 遍历**，非2才取client
（0x1000aaeb0/`[x20,#0x4c8]`）并走sub_10513522C等遍历；原生HttpSign自身门控是
`dd.http_sign_buvid`（字面量0x117776190），与Ktor的Enable GInterceptor/common params/sign
不是同一开关。**Ktor 侧是否存在“把 native HttpSign 材料包成 GInterceptor”的适配器——本轮结论：
本镜像未见该适配器**，三条证据：① `dd.http_sign_buvid`（0x117776190）全镜像只有 **1 个** ADRP+ADD
读取点（0x1000b2af4/0x1000b2af8，落在 BFCHttpSignModule 的 listener 函数体内）；若 Ktor 侧另有
adapter 复用该配置，应出现第二个读取点。② native listener 的多绑定消费点只由旧 `BFCHttpTask`
分发（0x1000aaea0 `cmp w8,#2`→0x1000aaea4 `b.eq` 整段跳过），type2 不进入。③ Ktor 侧身份参数来自
**同一 Swift 模块的另一个类** `NetParamImp`（见上文），不是 listener 的 `setHttpHeader` 路径；
头名字面量上 `Session_ID`(0x117acfd33) 与 `Buvid`（8 处 ASCII；其中 0x117acfd3e 附近是 listener 的
selector/type-encoding 串表、0x11776f920 是 `LaserUploadViewController` 的调试文案
`Buvid : %@ (点击复制)`）**只有 ASCII**，Kotlin `__const` 里 native 三元组只存在
`x-bili-trace-id` 的 UTF-16 字面量（0x11cb37a02）及日志串 `header x-bili-trace-id=`（0x11cb3f410）。
**边界**：`__const` 指针为 chained fixup 编码，`find_string_refs.py`/全域精确指针扫描对 UTF-16
字面量均 0 命中，故“字面量缺失”不单独构成证明；结论主要由①②③支撑。
18 成员集合已解析到栈槽与 root 字段：`sub_10B93C044` 在 0x10b93c814 起以数组长度立即数
`mov w10,#0x12`（=18，0x10b93c0e0）构造，成员是 `sp+0x200+0x528+0x10k` 的 16 字节
(值,typeinfo) 对——每个成员 `ldr x0,[x21,#8]` 取 root，`add x1,x25,#槽` 后 `bl <成员 getter>`，
再 `add x1,x25,#槽+8` 后 `bl sub_10B951888`（Kotlin/Native typeinfo 装箱 helper：读对象类型元数据
`[meta+0x3c]`/`[meta+0x40]`）。18 个 getter 形态一致、各读**互不相同的 root 懒字段**（+0x198、
+0x1a8、**+0x1b8**、+0x1d0、+0x1d8、+0x1e0、+0x1f0、+0x1f8、+0x270、+0x278、+0x288、+0x290、
+0x298、+0x2a8、+0x2b8、+0x2c0、+0x2c8、+0x2d8；对应 getter 依次 0x10b920e3c…0x10b922afc），
**数组顺序 = root 字段偏移顺序**，不是 name/order 排序；其中 root+0x1b8 即旧文已闭的
`provideTicketRequest` ⇒ **ticker 是第 3 个成员**。残余：其余 17 个成员的名字**本轮仍只能到偏移级**
——已排除两条静态路线：① 0x10b93b000–0x10b93c044 内**没有**对 root +0x198…+0x2d8 的 store；
② 全 `__text` 按偏移 + 基址寄存器聚类的 store 扫描只命中 sp(x31) 大栈帧与 Swift
`assignWithCopy_*` 值见证（假阳），所选扫描没有定位同时写18字段的构造体；不证明其他或间接初始化不存在。
另外成员 getter 本身也不含惰性初始化：以 ticker 为例，getter 直接读 `[x19,#0x1b8]`，
为 0 时只调 `sub_1052299B0`（NPE/未初始化陷阱，静态描述符 0x11cc6bae0）；这只证明该getter缺初始化时陷阱，不能据此推出字段来自外部writer。
**名字需运行期或元数据解码**：下一步 = 解 Kotlin/Native 类型元数据（成员类型信息由
`sub_10B951888` 读 `[meta+0x3c]`/`[meta+0x40]` 的 typeinfo 表得到），或运行期在 0x10b93c820
断点转储 18 个成员对象的类名。
BFCDeviceTraceService
的注册已在下文会话来源章节闭合（334项component表index100 0x120272c88→witness
0x11b2ee368+8注册入口0x104957210→provider getter0x104957110缓存DeviceServiceImp），
此处不重复；DeviceServiceImp 的 Objective-C protocol list（0x11d88cdf8）确实同时
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
**`requestType` 的写入方（本轮边界）**：`requestType` 确为 `_TtC13BFCHttpModule11BFCHttpTask`
的 ivar（ivar list 0x11d4d23d8：entsize=0x20、count=0x1d=29，`requestType` 是第 10 项，与
`needRetry`、`requestSignType`、`requestMetricsType`、`requestMethod` 相邻）；**但没有任何业务
经 ObjC 选择器写它**——共享 stub `_objc_msgSend$setRequestType:` 0x117610e80 的 9 个 BL
全部属于别的类：`+[BBMallResolverUGCHlsParsModel makeWithAvid:cid:qn:dolbyEnabled:requestType:]`
0x1139263f8、`+[BBMallResolverUniteHlsParsModel makeWith…:union_type:requestType:]` 0x11393db24、
`-[BBPegasusChannelV2WikiVC resetPageData]` 0x113acdd18、`…scrollViewWillBeginDragging:` 0x113ad14c8、
`…tapRequestAPIWithNid:contentNid:` 0x113ad1df8、`-[BBPegasusChannelV2WikiVM loadMoreData]` 0x113ad7af4、
`…loadWikiFeedData` 0x113ad7e5c、`+[BBResolverUGCHlsParsModel makeWith…:requestType:]` 0x114a0db80、
`+[BBResolverUniteHlsParsModel makeWith…]` 0x114a5823c。ivar 偏移数组（元素指针
0x1210644c0+8i）不在本工具链的 section 表内（`offset()` 返回 None），故 `[x8,#0x500]` 这一
读点偏移无法自证；全镜像 `str w?,[x?,#0x500]` 扫描也没有落在 0x1000a9–0x1000ab 区。
⇒ 写入方是 **Swift 直接字段写、尚未定位**（ivar #10 偏移 0x500，偏移数组 0x1210644c0+8i，全镜像 `str w?,[x?,#0x500]` 扫描无命中）；
下一步 = 用 fixup-aware 解析器取 `requestType` 的真实 ivar 偏移后扫该偏移的 store，或运行期在 0x1000aae98 断点读 receiver 与命中偏移。
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
本处不推实际运行时client实例。Enable GInterceptor属性的键对象槽在0x120c5e410，旧直接寻址扫描找到
真实读取5处（0x10a9ae5e8、0x10a9aedf0、0x10a9af5c8、0x10a9b0cc8、0x10a9b14c8；早前扫描多报的0x105ee0810/0x105d700ec是基址寄存器被`ldr x8,[x8,#0x478]/[x8,#0x458]`覆盖后的误报，scan_slot_rw.py已加"基址被覆盖即失效"判定后复跑得5处），
缺省值为false（0x10a9af620 cbz→0x10a9af62c `mov w21,#0x0`）；两种寻址形式全扫
（ADRP+LDR/STR与ADRP+ADD+LDR/STR，阳性对照：同法能查到0x1204ced28的STR写点0x1051315a8
与0x120dd11d0的STRB写点）**未命中直接写点，但不能证明没有间接写者**。新初始化0x105d5ac44–50将槽地址和key对象交0x10bfd0a94，helper0x10bfd0af4间接STR已定位；这只初始化key，不等于请求attrs=true。三个键名（Enable GInterceptor 0x11c6434d2、
Enable common params 0x11c6433b2、Enable sign 0x11c6433f2）只以__const中的Kotlin
UTF-16LE常量存在、无ASCII副本，说明AttributeKey由Kotlin侧创建、Swift侧只消费导出全局，
这些字面量形式不能判断request attributes true的producer是否存在。bfc_http_disable_ktor 同法闭合为无 writer：字面量 0x1177759a0 全镜像仅 1 处 ADRP+ADD（0x1000aa1e4，读取点），阳性对照 bfc_http_disable_common_params 0x117774d20 有 2 处（含新版 BFCHttpTask.signType: 的写入点 0x105034be0）；运行期由 Kotlin 侧写 attrs 的情形静态不可定，下一步 = find_string_refs.py 0x1177759a0 复跑并对 0x1000aa1e4 所在函数的 attrs 来源回溯。
request属性值补证（root-static-session/ktor-ticket-boundaries.md）：Common/sign predicate
缺省true，G缺省false。native request$1 0x105d5ebc8–ec80只在原attrs
bfc_http_disable_common_params等于字符串1时写Enable common params boxed false。
另InfraNetTrackSimpler closure0x10aa338b0取requestBuilder+18 attrs，在
0x10aa33998经Attributes interface写同一common=false。它们是实际值producer，
不等于key初始化，也不能推出首页必走。G捕获boolean→GInterceptorEnable typed tag
再写request的链已核；原始G值writer另已定位CommonParamsPlugin callback，读取kn.new.interceptor默认true并写实际配置Bool，不能凭缺省false或slot零扫描推全App状态。
残余边界：key初始化间接写已归因；同一AttributeKey的request attributes值写入需继续追producer，不能因扫描工具只查直接寻址而标为静态不可判。

provideTicketRequest（0x10aad1ab8）以 GTicket provider 构造 RequestResponseHook，
request/response closures 分别为 0x10aad280c/0x10aad29d4，名称实际为 `ticker`，
并实现 GInterceptor，进入上述18成员集合的注册关系已闭合。Enable GInterceptor属性在本镜像中
旧直接引用扫描只读而遗漏间接初始化写者，request attrs生效值仍待producer核对，
Kotlin侧的18成员集合与ticker hook仍受该属性门控；因此不能宣称全部 HTTP 请求都带 ticket。
残余（属运行期间接装配，静态不可定）：Ktor侧是否把原生HttpSign材料包装成GInterceptor；下一步 = disassemble.py 0x10b93c044 0x10b93cb00 逐个解析18成员集合（0x10b93c814 是 sub_10B93C044 内 +0x7d0，须从函数入口起才不漏前段；成员形式 `ldr x0,[x21,#8]; add x1,x25,#0x528+8k; bl sub_10B921xxx`；成员 getter 依次 0x10b920e3c/0x10b920fac/0x10b92111c/0x10b921344/0x10b9213fc/0x10b9214b4/0x10b921624/0x10b9216dc/0x10b9221a4/0x10b92225c/0x10b9223cc/0x10b922484/0x10b92253c/0x10b9226ac/0x10b92281c/0x10b9228d4/0x10b92298c/0x10b922afc，append 点 0x10b951888）。

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
