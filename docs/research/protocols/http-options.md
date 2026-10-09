# options 默认值、缓存与响应入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

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
独立账号通知链。**缓存调用方已收齐（本轮闭合，含强否定与阳性对照）**：
① 读：`-[BFCApiRequest _queryFromLocalCache:]`（0x1160932f8）的 `_objc_msgSend$` stub
0x11718b0c0 **只有 1 个 BL**——`-[BFCApiRequest _query:]_block_3`@0x116092820；
② 结束分发：`_queryRemoteEnd:allHeaderFields:localCache:error:immediately:`（0x116093a00）
stub 0x11718b280 只有 3 个 BL——block_3@0x116092a3c、block_4@0x116092c14/@0x116092de8；
③ 写：`-[BFCApiCacheKVDB setValue:forKey:withLogicKey:]`（0x116098874）stub 0x117659280
**只有 1 个 BL**——block_4@0x116092d9c（即写缓存的唯一站点）；
④ 逐键失效：`-[BFCApiCacheKVDB clearValueWithLogicKey:class:]`（0x116098aa8）为**强否定**——
`sel_clearValueWithLogicKey:class:`（0x11a01603b）全镜像只出现在 `__objc_const` 0x11f4e0948
（本类 method list），**没有 `__objc_selrefs` 槽**；阳性对照 `sel_setValue:forKey:withLogicKey:`
（0x11a3e99f5）同时存在于 `__objc_const` 0x11f4e0930 与 `__objc_selrefs` 0x11f741348
⇒ “逐键失效已实现但无 dispatch 点”。
⑤ 全清 `cleanAllApiCache` 有两套 dispatch 形态：形态 A 用 `selRef_cleanAllApiCache`（0x11f640040）
+ 裸 `objc_msgSend`，装载点**恰好 2 处**且都在 `AccountNotiInfoModule`——
0x104c6b494/0x104c6b498 ∈ `-[AccountNotiInfoModule accountDidLogout]`（函数 0x104c6b418，
符号名是 `accountDidLogout`，旧文写作 `logout`）、0x104c6b534/0x104c6b538 ∈
**`-[AccountNotiInfoModule accountDidUpdate]`**（函数 0x104c6b4bc）⇒ **账号更新与登出都会清
API 缓存**（本轮新增）；两处都在 `swift_getObjCClassFromMetadata`(0x104c6b490) 之后派发，
类名属运行期解析。形态 B 走共享 stub 0x117254660，共 7 个装载点：真实业务调用
`-[BBPhoneSettingMainVC clearLocalImage]`@0x10f2fffb4（BL），其余为尾调用转发 thunk
（`+[BBPhoneDeprecateApiV3Base cleanAllApiCache]`@0x10f25f830、
`+[BPlusBaseApi cleanAllApiCache]`@0x112dabef8、
`+[BBPgcPhoneBangumiUniversalApi clearCacheWithSeasonId:]`@0x1121d7c58 /
`clearCacheWithEpisodeId:`@0x1121d7c70、`-[BBUperAutoHeightTextField
clearButtonPressed:]_0`@0x10f8425c4 距入口 431756 字节属 nearest-method 误attribution），
另有一个 `_objc_msgSend$cleanAllApiCache_0`（0x1170bb9c8）**0 调用点**（死 stub）。
残余：登录/退出时清理与请求入队的**先后次序**仍属运行期，需 9.13 抓包或真机日志对照。

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
**gateway 错误加工链（已闭合到指令级）**：`-[BFCApiGatewayController
canonicalGatewayResponseWithData:response:error:]`（0x1160997bc）先
`alloc`+`initWithData:response:error:`（0x11609981c–0x116099834）构造
`BFCApiGatewayResponse` 包装，再 `gateways`(msgSend 0x11609984c)→
`countByEnumeratingWithState:objects:count:`(0x116099868) 快速枚举，逐个
`canonicalGatewayResponse:`(0x1160998b4)；**折叠语义**：x25 初值为包装对象
（0x116099880），每轮尾 `mov x25, x22`（0x1160998d8）⇒ 前一个 gateway 的输出是
下一个的输入，遍历内**没有 status/error 门禁**，每轮一个 autorelease pool
（0x1160998a4/0x1160998d0）。返回最终包装（x22，0x116099938）。
**唯一消费点**：stub 0x117239460 只有 1 个 BL——`-[BFCApiRequest
_buildRequestOperation:afterRequest:]_block_2` @0x116095e74；该 block 先读
`+[BFCApiConst ktorRequestEnable]`（0x116095e5c），`tbnz w0,#0`(0x116095e60)
**为真则整段跳过 native canonical**，为假才调用 controller，随后用包装的三个字段
**整体替换**局部变量：data(0x116095e84)、response(0x116095ea0)、error(0x116095ebc)
（0x116095edc/0x116095ee0/0x116095ee4），再交 `rawDataHandler`(0x116095eec)；
其后 `sub_116092E38` 只是时间戳 helper（gettimeofday/mach_timebase_info/
mach_absolute_time，全局 0x120e620c00/0x120e620c0c），**不是错误加工**；仅当
response 非 nil 且 `isKindOfClass` 通过（0x116095f50/0x116095f68）才读
`statusCode`/`allHeaderFields`/`allKeys`（0x116095f7c/0x116095f8c/0x116095fa8）。
⇒ gateway 可以改写 error，但 controller 自身不新增错误加工（不把状态码/error 转成
`BFCApiNonZeroErrorDomain`），code 非零域加工仍在 0x116093474。
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
将成功 host 保存进程字典，后续初始化可复用。keyWithRequest（0x11609e8fc）的门禁不是直接读键：
0x11609e91c/0x11609e924 取 `_OBJC_CLASS_$_BFCMultiDomainConfig` 调 `multiDomainEnabled`
（msgSend 0x11742ac40），0x11609e928 `cbz w0` 为假即返回；随后才取 URL→host
（0x11609e930/0x11609e940）、shared(0x11609e960)→multiDomains(0x11609e970)→
allKeys(0x11609e980)→containsObject:(0x11609e994)。
**`net_multi_domain_enable` 的读取点与采用时序（本轮闭合，含默认值不对称）**：该字面量在
`__cstring` 只有 1 份 ASCII（0x117774630，**无 UTF-16 副本**，故不是 Kotlin AttributeKey 类键），
全镜像有 2 个读取点——① `+[BFCMultiDomainConfig multiDomainEnabled]` 0x11609ec04：
`adrp/add` 取该串后 `mov w1,#0x0`（0x11609ec0c）尾调 `sub_11649C3D0`（ObjC 通用布尔配置读取器，
全镜像 239 个调用点），**默认 0**；② `sub_10009BC80`（模块字面量
`srcs/base/BFC/Networking/HTTP/BFCHTTP/BFCHttpModule.swift` 0x117774460）0x10009bd04/0x10009bd08：
`String._bridgeToObjectiveC()` + `getBoolForKey:defaultValue:`（selref 0x11f675250），
`mov w3,#0x1`（0x10009bd34），**默认 1**。⇒ “未配置”在 ObjC 链路等价 false、在 Swift
HttpModule 链路等价 true，两个默认值不可互换。采用时序：引擎启动时
`-[IgHttpEngine start]` 0x11609f864 → `-[IgHttpEngine parseConfig]` 0x1160a0c00 采用一次；
配置更新时 `-[IgHttpEngine setOnlineParams:]` 0x1160a0bb8 由 `sub_10008A498`
（模块字面量 `IgnetModule/IgHttpModule.swift` 0x117771730）@0x10008c06c 派发，该函数同样用
`getBoolForKey:defaultValue:`（selref 0x11f675250）逐键读取；`BFCHttpModule` 侧另有 DD 通知观察者
`-[HttpModule.DeviceDecisionDataObserverImp didUpdatedFor:status:value:]`（0x10009bd74，内部走
`sub_10009C96C`）。残余：`sub_10009BC80` 的 invoke 点**已按四种编码穷举仍为 0**——0 个 BL/B 调用者、
0 个绝对（含 tagged）8 字节指针、0 个 32 位“相对槽自身/相对 image base”与 4 字节相对引用；
且它**不是**相邻观察者类 `_TtCC13BFCHttpModule10HttpModuleP33_…29DeviceDecisionDataObserverImp`
的 IMP（该类 method list 0x11fa79618 解码得 entsize=0x18、两段 count=1+2，IMP 为
0x10009bd74（`didUpdatedFor:status:value:`）、0x1000a08c8、0x1000a0918，三者都不是它）。
**同区域阳性对照**：早 0x40 字节的 0x10009bc40 有 `__const 0x11b0a9170` 指针引用、
上述两个 IMP 也能在 `__objc_data` 0x11fa79630/0x11fa79650 找到 ⇒ 扫描器在该区域是敏感的，
“0 引用”不是工具失灵。⇒ 只能解释为 (a) 未被调用的编译器产物，或 (b) 运行期构造的函数指针；
**静态不可判**，取证=运行期在 0x10009bd08 下断点（若永不命中则支持 (a)），或改用 chained-fixup
感知的指针解析器复扫。
needDomainGrade 经 getter 0x1160a4278 读取底层 C++ response 的状态字节；其赋值
赋值条件在底层传输层内部（needDomainGrade getter 0x1160a4278 读 C++ response 状态字节），静态不可还原；因此不能把任意 HTTP 错误都说成会自动换域名重试，也不能与 ticket 退避或首页 VM 的一次额外尝试合并成一个策略。下一步 = find_callers.py 0x117431940（`_objc_msgSend$needDomainGrade` stub）收全部派发点，并从同函数内的 response 写点回溯赋值。注意直接对方法入口 0x1160a4278 跑 find_callers 只会得 0 条——该工具只匹配 BL/B 精确目标，ObjC 分派收不到。

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
无论now是否通过门禁，completion尾0x115dab690都清flag。该request在
0x115dab524 requestWithOptions后到0x115dab544 requestAsync前只调用过
setCompletionHandler（0x115dab53c），没有第二次handler写入，故errorHandler为nil：
注册的BFCApiRequest通用完成路径在incoming NSError、ORM error或
remote model为nil时走失败分支（0x116093ac8–0x116093ad0），errorHandler为nil
便退出（0x116093d0c/0x116093d18），不调用成功completion，因此失败路径到不了清flag。
全__text针对0x120dd11d0的ADRP+byte LDR/STR扫描（scan_byte_global.py）只命中
0x115dab464读、0x115dab470置true、0x115dab690置false三处，没有超时/取消清flag路径：
flag在异步请求前置真，只由成功completion清除。于是首次尝试失败或请求在途后，
boottime不等且syncServer=true的后续调用一律返回0（0x115dab468 tbnz→0x115dab558）
且不再发请求，realTimeInterval收到0再返回nil（0x115dab1f4/0x115dab228），
单进程内不会自动重试。残余边界：非ADRP形式的间接写入不在此扫描内，进程重启后RAM flag归零。
**该 flag 的实际消费方已闭合（team-c21）**：`+[BFCServerTimeChecker realTimeInterval]` 0x115dab1a8
的共享 stub（0x10f868f60）全部 13 个调用点——播放历史族 7 处
（`-[BBHD2UGCMiniScreenConfiguration reportHistoryForPad:player:]_block` 0x10caff838、
`-[BBHD2UGCMiniScreenDataSource recordHistoryWithProgress:duration:startTime…]` 0x10cb00b88、
`-[BBHD2MPPlayerVideoUpdate reportHistory]` 0x10cc38ed0、
`-[BBHD2MPPlayHistoryCloudSyncService reportPlayHistory]` 0x10cc49178、
`-[BBHD2MPPipDataSource recordHistoryWithProgress:…]` 0x10ccc0aa4、
`-[BBHD2PLContainerPiPDataSource recordHistoryWithProgress:…]` 0x10cd2883c、
`-[BBHD2PlayListMiniScreenConfiguration reportHistoryForPad:player:]_block` 0x10cd29af8）、
`+[BFCTikDuration _currentMsecTimeStamp]` 0x10ec7cd48、直播购物 5 处
（0x10efaa824/0x10efd3370/0x10f0289f8/0x10f0297c0/0x10f02c284）；
`realTimeIntervalWithSyncServer:`（stub 0x1174bae80）的**唯一**调用者就是 `realTimeInterval`
自身（0x115dab1ac），没有第二个业务入口。即服务端校时只服务“播放历史时间戳 + 直播购物时间”，
校时失败期间这些站点取本地时间/nil（运行期后果，静态可推）。
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
ivar名称当成动态属性的直接读取指令。前述boottime/slinterval走通用动态属性层，writer已闭合：
BFCPreferences.processAllProperties0x1167d3798按class_copyPropertyList安装各类型getter/setter
（double类型'd'分支0x1167d3adc选getter sub_1167D49C8/setter sub_1167D4A50，安装
class_addMethod0x1167d3c7c/0x1167d3d04或method_setImplementation0x1167d3c68/0x1167d3cd4），
并建立selector→属性名映射（0x1167d39d4/0x1167d39e4），_defaultsKeyForSelector:0x1167d360c
据此得到UserDefaults键=属性名；随后0x1167d3d2c–0x1167d3dfc把userDefaults.objectForKey:的非nil
值连同sourceType=2写入_configCache(self+0x10)/_sourceTypes(self+0x18)，故跨启动读回走缓存。
setBoottime:0x115dab634与setSlinterval:0x115dab678经setter模板0x1167d4a78→numberWithDouble:
0x1167d4a94→_setObjectWithKey:value:0x1167d34cc，后者写_configCache后写userDefaults
（0x1167d357c），suite由userDefaults0x1167d4ccc按configName创建。两属性是两次独立setter调用，
仍非事务提交；suite名字面量只有0x115dab184一处引用，BFCServerTimePreferences classref只有
0x115dab094/0x115dab3b4/0x115dab61c三处，未发现按名清除该suite的静态调用方
（边界：以运行期字符串全清defaults的上游不在扫描内）。没有读取实际存值。
该响应头与辅助请求均独立于播放器heartbeat的start_ts回执。
