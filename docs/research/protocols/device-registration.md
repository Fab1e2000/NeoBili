# 设备登记与访客生命周期

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 设备登记与访客生命周期

设备指纹加密和五项 guest 资料结构见 [身份研究](../recommendation-parameters.md#ios-分析样本中的生成与加密规则)。
登记请求 BFCDeviceUpdateBuvidRequest.requestUpdateBuvidWithData:completion:
（0x115fd7ed0）使用 Ktor，method=1/signType=0/priority=0，body 是 key/content JSON，
Content-Type=text/plain。URL 是字面量 `https://app.bilibili.com/x/resource/fingerprint`
（0x115fd815c）；0x115fd8220 request:priority:method:signType:bodyData:completionHandler:
的 priority/method/signType 实参分别是寄存器常量 0/1/0，不来自服务端配置。
加密路径（已证，8.89 静态）：入参 bytes 即 `getDeviceInfo` 的 54 字段 GPB 序列化
（`+[BFCDeviceToken fingerprintMaterialBin]` 0x115fd77d4 = shared→getDeviceInfo→data；
`-[BFCDeviceToken getDeviceInfo]` 0x115fd717c 为 once 缓存到全局 0x120e623d8）。
0x115fd7f30–0x115fd7f60 以 arc4random 取 16 字节、值域 1..127 作 AES key；
0x115fd7fcc `CCCrypt`(op=0/AES128/options=3=ECB+PKCS7/无 IV) 加密 payload，hex 后为 content；
同一 key 的 hex 交 `crsaWithPublicKeyPath:encrypt:`（实现 0x115fd8400：读内置 BFCDevice.pem、
去 PEM 头尾、base64 解码、`SecKeyCreateWithData`(kSecAttrKeyTypeRSA/kSecAttrKeyClassPublic/
kSecAttrKeySizeInBits=2048)、`SecKeyCreateEncryptedData`(_kSecKeyAlgorithmRSAEncryptionPKCS1)）
导入属性 2048 不是实际 modulus：独立解析包内 BFCDevice.pem 为 1024 位，
原参数的 Apple Security 离线 fixture 输出 blockSize=128、PKCS1 ciphertext=128B；
见 `DerivedData/Validation/root-rsa-wire-audit/findings.md`。9.13 形状相容不证明公钥/算法完全相同。
得 key；0x115fd8108 `dictionaryWithObjects:forKeys:count:2` 组 {"key":RSA hex,"content":AES hex}。
该构造段没有根据 CCCrypt 返回状态或 JSON error 直接中止（nil 值以空字符串顶替）。
回调 0x115fd82d0 要求 error=nil、body 非 nil、HTTP 200、顶层与 data 是 NSDictionary，
再取非 nil data.bili_deviceId；未检查业务 code==0（该回调内除 data/bili_deviceId 外不读
任何响应键）。**逐指令核查（0x115fd82d0–0x115fd83e0）**：区间内 objc 选择子只有
`JSONObjectWithData:options:error:`、`objectForKeyedSubscript:`（键 CFString 'data' 与
'bili_deviceId'）、`statusCode`、`objc_opt_class`/`objc_opt_isKindOfClass`，**`objc_msgSend$code`
出现 0 次**，也没有该范围外的响应键读取——故"不校验业务 code"是指令级结论，不是抽样推断。
另外该回调未检验编号类型/长度。所有不通过分支都汇到 0x115fd83e0 释放返回，
**completion 不会被调用**（登记失败静默丢弃），仅成功分支 0x115fd83bc 以 deviceId 调 completion。

登记指纹负载的54项描述符已逐项定位：`+[BFCDeviceIosDeviceInfo descriptor]` 0x115fd895c以
0x115fd89a8 `mov w6,#0x36`（fieldCount=54）、0x115fd89ac storageSize=400、
fields数组0x12084c4e8、messageName字面量`IosDeviceInfo`（0x115fd8990）建描述符；
字段号1..54依次为 os、platform、osver、t、idfa、idfv、model、brand、oid、freeSpace、battery、
root、brightness、languages、totalSpace、network、countryIso、sysname、memory、name、isVpn、
track、appId、appVersion、appVersionCode、mid、chid、fts、sdkver、buvidLocal、ip、
corefilemodifytime、corefilecreatetime、systemvolume、strBattery、isRoot、strBrightness、
strAppId、userAgent、freeMemory、deviceAngleArray(重复)、biometric、biometricsArray(重复)、
lastDumpTs、batterystate、batterytemperature、camcnt、camlight、campx、cpucount、kernelversion、
screen、sim、issimulatorIos。赋值点集中在 `-[BFCDeviceToken generateInfo]` 0x115fd5b54，
该函数有54个setter调用（0x115fd5bac–0x115fd6bd0，逐项来源如 platform←userInterfaceIdiom、
osver←systemVersion、t←Date、oid←carrierNameGetter、buvidLocal←localBUVID、
fts←firstRunTime、mid←midGetter、appId←productID、os/brand/sdkver/track/sim等为字面量、
batterystate←batteryState、batterytemperature←thermalState、screen←`%ld,%ld,%.1f`、
camcnt/camlight/campx←AVCaptureDevice、corefile*←/System/Library/CoreServices文件属性）；
所选 `-[BFCDeviceToken generateInfo]` 未找到 ip、userAgent、isVpn 的赋值点；
`setIp:`全镜像有9个命名 stub 调用点、`setUserAgent:`29个，`setIsVpn:`命名 stub
未发现。该工具形态与抽样接收者不覆盖 generic objc_msgSend、间接写入和反序列化，
不能证明全应用无法构造或更改此类消息。具体赋值来源见站点与指令；旧类别合计不一致，不用51项数量替代逐项验收。
**descriptor presence 已读取，实际 wire 仍有边界**：fields 数组 0x12084c4e8
（真实 stride 0x20，含8B default）中 isVpn(#21)、ip(#31)、userAgent(#39) 的
hasIndex 为20/30/39，分别位于0x12084c768/8a8/9a8。原task-28的stride0x18、
ip行890及userAgent has38错误撤回（root-static-remaining/device-three-descriptors.json）。实际 GPB serializer 已接：data 0x116793460→writeToCodedOutputStream 0x116793694→
writeField 0x116793960。singular gate 在0x1167939a0加载number/hasIndex，39a8调
0x11679e914，false于39ac直接return；helper读取storage[index>>5]、移位AND1。
因此**对应has-bit=0就不写wire**已由本镜像原指令证明。新对象+allocWithZone
0x116792030依storageSize400调用外部NSAllocateObject，init设messageStorage指针而
无本地has memset，零初值依赖系统allocator契约。getDeviceInfo缓存并返回可变单例，
未穷尽生成后全部间接写者，所以不能升级为“登记永远缺三字段”。原task-28的
整体缺席结论收窄为条件性presence规则（root-static-remaining/findings.md）。
`classRef_BFCDeviceIosDeviceInfo` 0x11f7f02b8 所选引用形态命中一次
（0x115fd5b98 ∈ generateInfo），类对象0x12023ebe0命中descriptor；此结果不覆盖
Swift相对指针、chained fixups、reflection及对象传递，不能证明只有一个创建点。
阳性对照 classRef_BFCDeviceToken 33处、classRef_BFCAccountDeviceInfo 1处，仅验证
同类引用扫描可命中，不升级为全域不存在证明。
9 个 `setIp:` 调用点抽样接收者为 BFCAppEnvironmentIP、BFCNetSniffer、TypepbRoot（NeuronDebugger 配置）、
SuperNodeRelease（P2P 节点）、投屏/DLNA 设备模型；29 个 `setUserAgent:` 抽样接收者为 IJKMediaConfigParams、
BFCWebImageDownloaderConfig、BFCDownloadAVEntity/EpEntity、BFCPaymentBaseParam、MQPWebService、
BBMusicDownloadEntity 等，均非本 payload 类（完整站点表
DerivedData/Validation/team-c3/setIp-setUserAgent-callers.json）。repeated 两项取值：
deviceAngleArray = `+[BFCMotion cachedDeviceMotion]` 返回的前三个 double 转 Float
（0x115fd64b0/0x115fd64e4/0x115fd6508，同次返回的第四个 double×1000 取 abs 写 lastDumpTs 0x115fd6560）；
biometricsArray 仅在 `+[BFCDeviceBiometry cachedType]`==2/==1 时分别写 'faceid'/'touchid'
（0x115fd65b8/0x115fd6598/0x115fd65ec），其它类型只 setBiometric:0、不调 setBiometricsArray:。
同名的 `-[BFCAccountDeviceToken generateInfo]` 0x116058d3c 构造的是另一个类
BFCAccountDeviceInfo（classref 0x116058d7c），字段重名，按setter全镜像计数会污染统计；
按类过滤后的完整站点表见 DerivedData/Validation/team-t1/setter-callers.json。

serverBUVID getter（0x115fd7224）在 expiry<now 时先设置 now+120，再异步申请并
立即返回旧值；相等时不申请。Token 回调 0x115fd7398 另要求 length>0，将内存 expiry
设为请求发起时刻+86400。值相同也延期，但不重复替换/保存；值变化时保存 Preferences
及 Keychain。失败不清旧值且保留 120 秒窗口。回执落点（已证）：0x115fd73dc–0x115fd73f0 锁内写
token+0x20 = 捕获的请求发起时刻 + 86400（0x118444518 常量）；0x115fd73f8–0x115fd7428 与
token+0x18 现值 `isEqualToString:`，相同则跳过保存，不同才 `objc_storeStrong` 并
0x115fd7488–0x115fd74a4 调 `[BFCDevicePreferences shared] setServerBuvid:`；Keychain 在
0x115fd7484 `dispatch_async`(main) 的 block 0x115fd74d4 内：`[[BFCKeychain alloc] initWithService:3]`
（0x1173952e0）→ `setString:forKey:@"serverBUVID" error:`。deviceId 为 nil 或 length==0 时
0x115fd73c0/0x115fd73cc 直接返回，不写任何落点。loadServerBUVID（0x115fd706c）读取
Preferences→Keychain 时会 validateBUVID，因此本次回调的接受条件与重启后加载条件
并不相同；expiry 在上述路径没有持久化，也未发现主动定时登记。

Guest.load（0x11605a5a0）只在 guestId 为 0 或 -2 时登记，其余值直接返回。
请求回调 0x11605a658 在 transport error 或非零 API code 时返回错误及 -2、不保存；
code=0 后取 data.guest_id.longLongValue，只拒绝 0/-2，不能把此层验证写成“必须正数”。
成功经 barrier_sync 写 Guest 对象与 GuestPreferences。访客登记请求链（已证）：
`-[BFCAccountGuest load]` 0x11605a614 走 `+[BFCAccountGolangApi requestGuestRegisterWithCompletionBlock:]`
0x116049894 → `+[BFCAccountRSA requestRSA:]` 0x11605b678（内部 `requestPublicKeyWithCompletionBlock:`，
即公钥由运行期接口取回，不是本地 PEM）。该取回端点已闭合：
`+[BFCAccountGolangApi requestPublicKeyWithCompletionBlock:]` 0x116047568 以空参数字典
尾跳 `get:params:completionBlock:`（0x117325dc0），路径字面量 `x/passport-login/web/key`
（CFString 0x11d3d5b10），host 同为 passport.bilibili.com ⇒ **GET
https://passport.bilibili.com/x/passport-login/web/key**；回执在
`+[BFCAccountRSA requestRSA:]_block` 0x11605b70c：error 非 nil 直接 completion(error,nil)；
`code` 非 0 以 apiRequestErrorDomain.nonZero+message 构造 NSError（0x11605b778–0x11605b818）；
code=0 时从 `data` 字典取 `key`（0x11605b880，须 NSString，否则空串）写 BFCAccountRSA+0x8、
取 `hash`（0x11605b8f4，同类型门）写 +0x10，再 completion(nil, rsa)（0x11605b960）；
字段缺失以空串顶替，不中止。请求体 0x116049980–0x116049a34 =
{`device_info`: `BFCAccountGuestInfo.info`, `dt`: base64(`[rsa encrypt:guestInfo.key]`)}，
再 `post:params:completionBlock:`。`+[BFCAccountApi post:params:completionBlock:]` 0x116046058 →
`_request:params:method:completionBlock:`：0x1160460fc host 字面量 `passport.bilibili.com`、
0x116046108 `https://%@/%@`、路径字面量 `x/passport-user/guest/reg`(0x11d3d5d90)
⇒ **URL = https://passport.bilibili.com/x/passport-user/guest/reg**（method=1 POST），
另加公共参数 `sdk_ver`=`0.1.15`(0x116046158) 与 `setIgnoreCodeNonZero:1`(0x116046204)、
`setApiKeySecretType:1`(0x116046218)。回执信封 0x116046844–0x116046d58：仅当 `Content-Type`
前缀 `application/json` 才 `JSONObjectWithData:options:1`，须为 NSDictionary，再读
`message`(NSString) 与 `code`(NSNumber) 后 `setResponseCode:`。该函数未发现定期过期或
并发请求合并标志；其他层是否另有调度仍需核对：唯一写入guestId偏好的路径是
`-[BFCAccountGuest saveGuestIdWithData:]_block`（0x11605a474调setGuestId:），
全镜像 `_objc_msgSend$setGuestId:`(0x11759bea0) 的BL/B调用点只有该处与
0x115e0d4cc（sub_115E0D26C，属另一类的NSString字段拷贝，紧邻0x115e0d4b4先读guestId），
其余两处是stub自身别名，因此**登录/退出路径不写guestId偏好**（边界：动态派发与以运行期
字符串为参数的整suite清除不在扫描内）。

AccountModuleModuleInitialize 的 Swift setup（0x104c6daf4）分别注册两个主队列通知：
DidBecomeActive→0x104c6cbf0→loadGuestId，WillEnterForeground→0x104c6cb88
仅在 hasLogined 时 validateToken/updateCurrentUser。setup 还直接调用一次 loadGuestId。
因此登记失败可在后续 active 通知再次触发，不是每次前台都无条件重新登记。
active completion（0x104c6cc80）忽略 error 参数，trackTech `infra.ids`，扩展字段是
guest_id（含失败哨兵 -2）与 total_memory（NSProcessInfo.physicalMemory），policy=2、
rate=100。实验 account.guestid_can_add_in_netcore（preset=1）传入 guest header 控制器；
网关消费已如下闭合；全局启动顺序属 scheduler 运行期（AccountModule setup 0x104c6daf4 的唯一直接调用者是 0x104c6cb4c，其余经 task witness 间接触发），静态不可定；下一步 = scan_callers_set.py 0x104c6daf4 0x104c6e290 0x104c6e2f0 后读 task witness 的 priority getter；preset 不证明实际开启。

GuestId header有两条不同链。HttpSign helper0x1000b5484要求guest控制依赖与
account依赖非nil、guestIdCanAddToNetCoreHeader=true，随后每次读guestId写GuestId；
无本段登录、正数或非空检查。dd.http_sign_buvid=true时该helper先于signType判断，
false时仅signType!=3调用（0x1000b2b50/0x1000b2dd4），并非所有引擎必走。

Account provider0x104c6efc0按同flag选AccountApiGatewayInterceptor或Nothing的
class metadata；缓存0x1204a6d28/30是类，不是实例。Gripper0x104c6f268注册协议class
provider，ApiClientModule0x1049be96c解析同协议class数组、逐项registerClass；
append0x11609919c同步追加无去重。0x1049be324 是到 register 0x1049be96c 的独立尾调 thunk；0x120a1d800 的 swift_once 实际在 0x1049be388–3c4 门控 task provider 初始化 0x1049be328，并非 register 方法体。撤回 task-38 的“注册只发生一次/flag变化不重选”推论；task witness 调度次数仍须追，不由相邻函数位置推控制流（root-static-audit/recovery/0x1049be2ac.asm）。
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
将其当作 guest 重置。**观察者注册方式更正（8.89 静态）**：账户通知不走 NSNotificationCenter——
`BFCAccountNotification` 0x11605cf58 用自有注册表，注册入口为
`_objc_msgSend$addActionObserver:type:block:` 0x1171c8500、
`addActionObserverForObject:actionType:actionBlock:` 0x1171c8540、
`addUpdateObserver:type:block:triggerImmediately:` 0x1171d34c0、
`addUpdateObserverForObject:updateType:updateBlock:triggerImmediately:` 0x1171d34e0、
`addNotifyService:` 0x1171cec60（外层经 `+[BFCAccount addActionObserverForObject:…]` 0x11603a2ac/0x11603a2b8 转发）；
对 `addObserver:` stub 扫描只会命中无关 KVO/通知中心调用。已枚举注册点 70/25/6/7/1 处
（DerivedData/Validation/team-c3/account-notification-registrations.json，代表观察者含
BBPlayerLoginService addListeners、BFCMossStreamChannel observerAccount、BFCCommentPageTableVC _addLoginObserver、
BBMallAccountManager init、BFCRestrictedModeManager init 等），**未见任何被证会清 guest 偏好的注册块**；
但逐 block 行为仍需反汇编，且 9.13 抓包核对退出后 guest/BUVID 存储是否保留（本样本不含运行期证据）。

### 短信 UI 的 login_session_id

UI 入口 helper 0x104cf8968 重建全局扩展参数字典，将跟踪 BUVID 与十进制毫秒时间
直接拼接，再取 UTF-8 MD5 的 **32 位大写 hex**。毫秒 helper 0x104cf86e8 使用
DateUnix×1000→FRINTA（最近整数、半值远离零）→有边界检查的 Int64 转换，不是
向零截断。全二进制BL扫描该helper只有四个调用点（0x104cec0c8 +[Login updateLastLoginInfo]、
0x104d1a710与0x104d1b0a4 +[StrictLogin overseaForceStrictLoginWithCompletion:toolView:]、
0x104d1d820 StrictLogin类内），没有其他登录UI直接BL复用该helper（间接派发不在扫描内）。

SmsAlert2Controller 的发送分支（0x104d9ece0）和重发分支（0x104d9f800）读取同一
全局字典、合入 BFCAccountSMSContext.extendedParams，再 sendSMSWithContext。
提交分支 0x104da0400 将同一字典与 scene=popup/from_pv 合并到 LoginContext，
经 0x104da0588 loginWithContext 发起登录。因此这条链是在 UI 入口换新，发送、
重发与提交复用；不是每个 HTTP 请求重新生成。Golang SMS send（0x116048be0）
与 login/sms（0x116048e54）最后合入 extendedFields，证明该字段进入表单，
而非仅供统计。SMSSendResponse.isNew 控制 RegisterRequest/LoginSMSRequest 分支；
注册分支的表单与后续换 token 见下节。
FastAlertController.loginRegCheck 0x104d5b15c→0x104d5af9c 只是切换勾选状态与动画，
原0x104d5b174是mov指令而不是发送点。真实 loginAction 0x104d5c144→0x104d5b184
在0x104d5b1c4取fastContext，合入from_pv及全局登录扩展槽0x1204abd20，
0x104d5b3d4–3e0 setExtendedParams，0x104d5b4c8 loginWithContext。
fastContext 0x114964670 的type raw6→AccountSession.fastLoginWithContext
0x114968050→BFCAccountFastService 0x11496f390→LoginFastRequest 0x1160443c8→
FastLoginApi 0x116047228→POST passport.bilibili.com/x/passport-login/fast/login。
基础字段mid/fast_login_token取fastLoginModel，local_id/buvid取BFCBuvid，device_id取
BFCDevice.currentBuvid，device_name/platform取UIDevice；accessToken非nil时加入
from_access_key，device_tourist_id是guestId字符串。extendedFields最后合并可覆盖
这些同名字段；公共AccountApi随后覆盖sdk_ver=0.1.15，method=1，apiKeySecretType=1，
再通过配置的request类发送，最终serializer/sign仍按公共链。
因此发送链不属于“天然只能运行期确定”；响应status/SSO转换/落盘与新版实际值另验。
FastRequest 0x1160445a4 的回执要求 API result.code=0 且 FastResponse.status=0
才转换SSO，非0status/url走后续路由；特定error=-105且captcha尚空走验证码委托。
handleSSOModel 若delegate支持fetchUserModel，获取失败阻断后续接受；成功或无该委托
转refreshCookies。已读cookie completion随后saveSSOModel:YES，保存JSON/更新fastToken；
不据此推Cookie联网成功或服务器设备登记成功。AccessTokenCopy独立副本已证写
standardUserDefaults；SSO同时经AccountModelPreferences/BFCPreferences和KntrStorage，
不能泛称所有凭据都在Keychain或全在一个存储。AccountModelPreferences.configName 0x116055888=NSStringFromClass，suite已闭合为
BFCAccountModelPreferences，动态setter复用BFCPreferences写UserDefaults；Kntr底层
仍需Kotlin导出typeInfo/adapter，物理IO成功和实际账号隔离不由API调用证明。
完整原始链 root-static-session/fast-login.md；OAuth2入口的对应字典引用仅已证
用于telemetry，不能据此扩展到OAuth请求。

离线假 BUVID 验证通过 12 个 post-Date 毫秒 Double 的 x.49/x.5/x.51 边界（含负数）、
大写 MD5 格式与同一舍入毫秒复用关系。验证的是 FRINTA 消费值；不声称任意秒数经
Foundation Date 内部 epoch 转换后都精确保留小数半值，也没有执行官方包或验证服务端。

### 账号校验、刷新、注册与退出

validateTokenRealWithSSOModel（0x1160521b8）拒绝 nil SSO（61000），否则将旧 accessToken
交给 info 请求。回调 0x1160524d4 的 transport/API 错误返回 needRefresh=false；业务
61000 只有被校验模型 mid 与当前账号 mid 相同时才调用退出。code=0 仅检验返回
mid/expires_in 非零，未在此层拒绝负值或比较新旧 mid；保留旧 token/cookie/sso，更新
expiresIn 并 updateSSOModel(type=0)。回执字段与分支（已证）：0x116052b54 `data[@"mid"]`
longLongValue、0x116052b98 `data[@"expires_in"]` longLongValue、0x116052bdc `data[@"refresh"]`
boolValue；61000 分支 0x116052750 取 `[self+0x20 tokenInfo].mid` 与
`[[BFCAccount shared] ssoModel].tokenInfo.mid` 比较（0x1160527d4），相等才 0x116052948
`logoutWithApi:`（参数为请求 absoluteString，nil 时用字面量 `BFCAccount_validate`）；
错误分支以 `[BFCAccountInjector apiRequestErrorDomain]` 与 `empty desc` 兜底描述记日志
（0x116052aa4/0x116052eac）。validateAndRefresh（0x116051cc0）根据服务端
refresh 布尔值决定刷新；此处未证本地提前过期阈值，不应将 expires_in 保存误写为阈值比较。原生请求公共签名、设备提供者和 Cookie 交接补充见 [DEV-04 实现契约](../contract/identity.md#dev-04-账号刷新与-confirm)。

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
marker 写入时机属运行期迁移分支（startMigrateData 0x10be56e9c 在 data=nil 时即写 marker=1，有模型时先存 account 再写 0x10be5727c），静态不可定调用次序；下一步 = scan_callers_set.py 0x10be56e9c 0x10be54d10 收齐调用方，不能把双写描述为始终从同一后端读。

迁移标记写入也与完整提交不同：startMigrateData（0x10be56e9c）在已经 migrated
时直接成功；data=nil 时写 marker=`1` 并成功。有模型时首项 SSO 字符串 length>0
才保存 account，随后立即写 marker=`1`（0x10be5727c），再条件保存其余四项；
首项为空则失败且不写 marker。finishRollback（0x10be54d10）写 marker=`0`。
AccountStorageModuleModuleInitialize（0x104c6d760）调用 decision；与 AccountModule
在模块 scheduler 中的全局启动顺序属运行期（AccountStorageModule 任务 accessor 0x104c6e2f0、AccountModule 0x104c6e290），静态不可定；下一步 = scan_callers_set.py 0x104c6d760 0x104c6daf4 并读各自 task witness 的 priority getter，不把 marker 当成五项存储的原子提交。

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
服务端撤销成功；已定位的 AccountNotiInfoModule.update为RET，login经thunk更新服务userID并非空，logout 清全部 API cache，
change 清 cache 并更新 Bugly userID；DeviceConfigNotify.update 为 RET。其他观察者
与存储转换尚有缺口。同版本运行与服务器验收未执行。
