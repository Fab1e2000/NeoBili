# 二、身份、设备登记与票据

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 二、身份、设备登记与票据

### DEV-01 BUVID 本地生成与存储链（非 HTTP，但决定多端点身份）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 无网络端点：`+[BFCBuvid buvid]`（0x1167cbe68）。它是认证 Buvid 头、Tracker trackID、UserAgent 与 BFCActiveReport 的共同来源。 |
| 2) 触发时机 | 首次需要时惰性计算；`_buildRequestOperation:afterRequest:`（0x11609537c）在 `authenticationHeaderParams` 里取它作为 Buvid 头（classref 0x11609d4b4→0x11609d4b8）。全镜像按 classref 邻近 ∩ BL 统计到 117 个直接调用点（明细 `DerivedData/Validation/team-t1/buvid-class-callers.json`）。 |
| 3) 请求头 | 不适用（本地取值）。取值链：Preferences `trackID` → Keychain（service 枚举 2=`trackId`、key=`buvid`；`-[BFCKeychain initWithService:]` 0x1167cd224 查 3 项静态表 0x11d085568，2→0x11d1060d0 `trackId`）→ Keychain 命中后回写 prefs（0x1167cbfc4）→ `BFCIDFA.idfaStringWithoutDash`（0x1167cbfe4）→ `identifierForVendor` 去连字符（0x1167cc0fc/0x1167cc158）。 |
| 4) 参数及来源 | 无请求参数。生成格式：36 字符，`Z`/`Y` + 主体第 2/12/22 字符 + 32 字符主体；不是带连字符 UUID。**首次生成分支（8.89 静态已闭）**：prefs/Keychain 均无效时 `+[BFCBuvid buvid]_block` 0x1167cbedc 先置再生成标志 0x120e71220=1（0x1167cbfd8）；IDFA 有效 → idfa[2]/[12]/[22]（0x1167cc01c/0x1167cc03c/0x1167cc05c）+ `'Z%@%@%@'`（0x11d3fc730）拼 4 字符前缀再追加完整 idfa（0x1167cc0b0）；IDFA 缺失 → identifierForVendor.UUIDString 去 '-'（0x1167cc158）同样切片用 `'Y%@%@%@'`（0x11d3fc750）。接受门 `+[BFCBuvid isValidTrackID:]` 0x1167cccfc：NSString+length>0+≠32 位十六进制黑名单常量（0x11d3fc7b0）+≠'Z'+35 个'0'（0x11d3fc7d0），不查长度；过门才 `setTrackID:`（0x1167cc2c0）+ main 队列 block 0x1167cc38c 写 Keychain('buvid')。IDFV 也无效的兜底 = `'%ld'`×(timeIntervalSince1970×1e6)（常量 0x1182ebd00，0x1167cc314/0x1167cc318），**只写内存缓存 0x120e71228（0x1167cc348），不落 prefs/Keychain，重启即重走生成**。缓存经 dispatch_once 0x120e71230。 |
| 5) 签名与编码规则 | 不适用。Keychain 排在 IDFA/IDFV 之前，因此重装后来源只可能是 Keychain 或重新生成。 |
| 6) 响应结构 | 不适用。 |
| 7) 与 NeoBili 当前实现的差异 | `AppBuvid` 的新生成路径采用自身 IDFV 的 Y 分支，读取既有偏好/Keychain 并保留旧编号和 Debug 实验覆盖值；没有请求 IDFA 授权，IDFV 缺失用进程内时间兜底。官方 IDFA 分支及首次生成的现版行为未做真机验收。 |
| 8) 证据等级与版本 | 8.89 静态（0x1167cbe68 及取值链地址）；当前源码；另有既有样本 36 字符 Y/Z 值符合结构的形状证据。 |
| 9) 残余不确定项 | 底层查询与删除已静态闭合：BFCKeychain→UICKeyChainStore，generic-password/service、可选accessGroup、account键，SecItemCopyMatching同步读取、-25300返回nil；clearAll/removeItem→SecItemDelete，成功或-25300为true。所选wrapper没有自行切队列，BUVID调用方另调main队列不等于全部Keychain操作都主线程。实际重装保留、entitlement及OS返回值属于运行边界（root-static-session/device-boundaries.md）。 |

### DEV-02 设备资料登记（54 项指纹 payload）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `POST https://app.bilibili.com/x/resource/fingerprint`（URL 字面量 0x115fd815c，0x11d3d14f0），`Content-Type: text/plain`（0x115fd81a8）。调用方是 `+[BFCDeviceUpdateBuvidRequest requestUpdateBuvidWithData:completion:]`（0x115fd7ed0），经 `KtorClientObjc request:priority:method:signType:bodyData:completionHandler:`（0x115fd8220）传 `priority=0`、`method=1`(POST)、`signType=0`——这三项与 host/path 都是构造期常量，不来自服务端配置。官方侧类方法（含 `+[BFCDeviceUpdateBuvidRequest crsaWithPublicKeyPath:encrypt:]` 0x115fd8400）；主文档旧称的 `-[BFCDeviceToken requestUpdateBuvidWithData:]` 是错误归属，本轮已改为索引中的实际符号。 |
| 2) 触发时机 | `-[BFCDeviceToken serverBUVID]_block`（0x115fd72e4）在 expiry 需要刷新时调用登记：`getDeviceInfo`（0x115fd717c，`dispatch_once` + block 0x115fd71f4 调 `[self+0x20 generateInfo]`，结果缓存到全局 0x120e623d8）→ `data`，即 payload 就是这串 54 字段 GPB 字节。`+[BFCDeviceToken fingerprintMaterialBin]`（0x115fd77d4）是同一条取 payload 的封装。getter `-[BFCDeviceToken serverBUVID]`（0x115fd7224）在 expiry<now 时先置 now+120，再异步申请并立即返回旧值（相等时不申请）。`+[BFCAccountGuest loadGuestIdWithCompletionBlock:]`（0x11605a5a0）只在 guestId 为 0 或 -2 时登记（见 DEV-03）。 |
| 3) 请求头 | Ktor 桥接路径的公共参数/头受 `Enable common params`、`Enable GInterceptor`、`Enable sign` 门控（key槽0x120c5e410初始化间接STR已核，旧6读0写不能判断request attrs写者；G predicate缺省false）；ticket hook 在同一 GInterceptor 集合内（TICKET-02）。 |
| 4) 参数及来源 | body 为 AES-128-ECB/PKCS#7 后的 Protobuf。权威描述符是 `+[BFCDeviceIosDeviceInfo descriptor]`（0x115fd895c）：`mov w6,#0x36`⇒fieldCount=54、storageSize 400、fields 数组 0x12084c4e8、messageName `IosDeviceInfo`（0x115fd8990）。字段号 1..54 依次为 os、platform、osver、t、idfa、idfv、model、brand、oid、freeSpace、battery、root、brightness、languages、totalSpace、network、countryIso、sysname、memory、name、isVpn、track、appId、appVersion、appVersionCode、mid、chid、fts、sdkver、buvidLocal、ip、corefilemodifytime、corefilecreatetime、systemvolume、strBattery、isRoot、strBrightness、strAppId、userAgent、freeMemory、deviceAngleArray（重复）、biometric、biometricsArray（重复）、lastDumpTs、batterystate、batterytemperature、camcnt、camlight、campx、cpucount、kernelversion、screen、sim、issimulatorIos。赋值点是 `-[BFCDeviceToken generateInfo]`（0x115fd5b54）所选赋值段（0x115fd5bac–0x115fd6bd0）；54是descriptor字段数，不是实际setter调用数；**已列具体赋值来源**（身份账号、设备系统、常量、时钟、越狱环境与repeated；旧分类数量合计不一致，不作为51项验收）。站点表 `DerivedData/Validation/team-t1/setter-callers.json`。两个 repeated 与相关字段已由 team-c3 补到指令级：`deviceAngleArray`（字段 41，`GPBFloatArray`）以 `arrayWithCapacity:3` 接 `+[BFCMotion cachedDeviceMotion]` 返回的 d0/d1/d2（0x115fd64b0–0x115fd64b8），同一次返回的 d3–d8 与常量 1000.0 相乘取 abs 写 `lastDumpTs`（0x115fd6560–0x115fd6568）；`biometric`/`biometricsArray`（字段 42/43）取 `+[BFCDeviceBiometry cachedType]`，`==2`→`biometric=1` 且数组元素 `'faceid'`，`==1`→`biometric=1` 且 `'touchid'`，其他→`biometric=0` 且**不调用** `setBiometricsArray:`；`sim` 为 `hasSimGetter` 真→字面量 `'5'`、假→`'1'`；`+descriptor` flags=0x1c（UsesClassRefs｜Proto3OptionalKnown｜ClosedEnumSupportKnown）。`isVpn`/`ip`/`userAgent` 三项无赋值点，见 DEV-08。证据：`DerivedData/Validation/team-c3/findings.md` S2.3。 |
| 5) 签名与编码规则 | body 是 JSON `{"key":…,"content":…}`（字典构造 0x115fd8108，`dataWithJSONObject:options:` 0x115fd8130）。`content` = hex(AES-128-ECB + PKCS#7(payload))：0x115fd7f8c–0x115fd7fcc 调 `_CCCrypt`，`w0=0`(kCCEncrypt)、`w1=0`(kCCAlgorithmAES128)、`w2=3`(ECB｜PKCS7)、`x3`=随机 16 字节 key、`x5=0`(无 IV)。AES key 由 0x115fd7f30–0x115fd7f60 以 `arc4random` 循环 16 次、取模 127 后 +1 生成，取值域 1..127。`key` = hex(RSA-PKCS1v1.5(UTF-8(hex(该 16 字节 key))))：内置 `BFCDevice.pem` 公钥（0x115fd8034 `pathForResource:@"BFCDevice" ofType:@"pem"`）经 `crsaWithPublicKeyPath:encrypt:`（0x115fd8400）去 PEM 头尾→base64 解码→`SecKeyCreateWithData`（`kSecAttrKeyTypeRSA`/`kSecAttrKeyClassPublic`/`kSecAttrKeySizeInBits`=2048）→ `SecKeyCreateEncryptedData` 配 `_kSecKeyAlgorithmRSAEncryptionPKCS1`。`ticket_context_fingerprint_enable` 命中时 GetTicket 签名追加 fingerprintMaterialBin（0x1000968d8/0x1000968f4）。本文不记录 AES/RSA 密钥或随机值。 |
| 6) 响应结构 | 回调 0x115fd82d0 的逐项门禁：`error==nil`（0x115fd8308 `cbnz x22`）→ `data` 非 nil（0x115fd8314 `cbz x19`）→ `statusCode==200`（0x115fd8318 `cmp x0,#0xc8`）→ 顶层是 NSDictionary（0x115fd8334 JSON 解析 + 0x115fd8358 class 检查）→ `data` 值是 NSDictionary（0x115fd8390）→ `bili_deviceId` 键非 nil（0x115fd8398 + 0x115fd83b0 `cbz`）→ 才调 completion。**该回调不读 `code`/`message`**，且所有失败/非 200/形状不符路径都汇到 0x115fd83e0 直接释放返回，**completion 完全不被调用**（静默丢弃）。成功保存点 `-[BFCDeviceToken serverBUVID]_block_block`（0x115fd7398）：deviceId nil 或 length==0 直接返回；锁内把内存 expiry 设为捕获的请求发起时刻 +86400 秒（0x118444518）；与当前值 `isEqualToString:` 相同则跳过保存，不同才 `objc_storeStrong` 并写 `[BFCDevicePreferences shared] setServerBuvid:`（0x115fd74a4），再 `dispatch_async(main, block 0x115fd74d4)` 写 `[[BFCKeychain alloc] initWithService:3]` 的 `serverBUVID` 键。即落点两条（Preferences suite + Keychain，service 枚举 3），**仅值变化才写**，Keychain 写主队列异步，内存 expiry 不落盘。`loadServerBUVID`（0x115fd706c）读 Preferences→Keychain 时会 `validateBUVID`（`+[BFCDeviceToken validateBUVID:]` 0x115fd7604），因此回调接受条件与重启后加载条件不同。 |
| 7) 与 NeoBili 当前实现的差异 | `IOSFingerprintProtocol` / `AppDeviceRegistration` 已编码真实本地资料子集，按8.89公共公钥和AES-ECB/PKCS7＋RSA-PKCS1提交key/content，并仅存真实bili_deviceId。登录、日志和Device头共用结果。未实现全部54项，当前9.13服务端兼容及真机登记尚未验收；拒绝或网络失败不制造编号，保留已缓存结果并冷却重试。访客/票据使用各自独立登记服务与缓存。 |
| 8) 证据等级与版本 | 8.89 静态（描述符 0x115fd895c、站点 0x115fd5b54、URL 字面量 0x115fd815c、加密路径 0x115fd7ed0、RSA 0x115fd8400、回调 0x115fd82d0、保存点 0x115fd74a4/0x115fd74d4）；证据明细 `DerivedData/Validation/team-t1/findings.md`（描述符/54 项来源）、`DerivedData/Validation/team-c3/findings.md`（S2 加密与 repeated 取值、S3.1/S3.2 响应与保存点）；当前源码。 |
| 9) 残余不确定项 | 端点/编码/保存点本轮已闭合；剩下的是运行期取值：54 项在真实设备上的实际值、以及 9.13 是否仍用同一 URL 与 PEM。**presence条件与旧解析错误已修正**（root-static-remaining/findings.md）：真实descriptor stride0x20，isVpn/ip/userAgent行0x12084c768/8a8/9a8、hasIndex20/30/39。GPB data→writeField→has-bit helper已读，位为0则直接return不写wire；不能把所选generateInfo未赋值推广可变getDeviceInfo singleton永远无后续写者，新对象零初值依NSAllocateObject契约。原team-c24“整体缺席”撤回为条件性规则。取证方式：真机在 0x115fd72e4 的 `getDeviceInfo` 返回处 dump 该消息，或在 `generateInfo` 返回前断点；跨版本用 9.13 抓包对照 `x/resource/fingerprint` 与响应字段。**9.13 抓包（线级，team-c12）已完成该对照**：现版仍是 `POST https://app.bilibili.com/x/resource/fingerprint`（28 条：mainland 21 / overseas 7），`content-type: text/plain`，query 14–15 键，body 为 JSON 且顶层恰为 `key`+`content`；`key` 长度恒 256（128 字节 hex）、`content` 长度 992/1024/1056/1088（496/512/528/544 字节 hex），两值字符集全为小写 hex ；独立复核证实 8.89 包内 PEM 的 modulus 为 1024 位，Apple Security 原导入属性 2048 仍得到 128B block/output。9.13 外层双 hex 与长度相容，但不证明同 PEM/RSA padding/AES 模式或明文 schema（root-rsa-wire-audit/findings.md）；**54 项实际取值仍需解密或真机 dump**。 |

### DEV-03 访客登记 `+[BFCAccountGuest loadGuestIdWithCompletionBlock:]`

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `POST https://passport.bilibili.com/x/passport-user/guest/reg`：host 字面量 `passport.bilibili.com`（0x1160460fc）+ `stringWithFormat:@"https://%@/%@"`（0x116046108）+ 路径字面量 `x/passport-user/guest/reg`（0x11d3d5d90）；由 `+[BFCAccountApi post:params:completionBlock:]`（0x116046058）在 0x116046060 tail-call 到 `+[BFCAccountApi _request:params:method:completionBlock:]`（方法入口 0x116046064；此处 `w4=1` 即 POST）走传统 HTTP 层。入口是类方法 `+[BFCAccountGuest loadGuestIdWithCompletionBlock:]`（0x11605a5a0；索引符号名如此，早期写作 `-[BFCAccountGuest load]` 是笔误）。 |
| 2) 触发时机 | 该函数读 `guestId`（`+[BFCAccountGuest guestId]` 0x11605a488），仅当值为 **0 或 -2** 时才走 0x11605a61c `+[BFCAccountGolangApi requestGuestRegisterWithCompletionBlock:]`（0x116049894）；其他值在 0x11605a63c 直接回调现有值。`AccountModuleModuleInitialize` 的 Swift setup（0x104c6daf4）注册两个主队列通知：`DidBecomeActive`→0x104c6cbf0→`loadGuestId`，`WillEnterForeground`→0x104c6cb88 仅在 `hasLogined` 时 `validateToken`/`updateCurrentUser`；setup 还直接调用一次 `loadGuestId`。因此登记失败可在后续 active 通知再次触发，不是每次前台无条件登记。 |
| 3) 请求头 | 该族由 `+[BFCAccountInjector apiOptions]` → `optionsWithBaseUrl:` → `requestWithOptions:`（0x116046268）走传统 HTTP 层；公共头与签名同 FEED-01 的公共层，但 `setApiKeySecretType=1`（0x116046218）会切换该族的 appkey/secret 类别。GuestId 另有两条独立消费链：HttpSign helper 0x1000b5484 要求 guest 控制依赖与 account 依赖非 nil、`guestIdCanAddToNetCoreHeader=true`，随后每次读 guestId 写 `GuestId`，无本段登录/正数/非空检查；`dd.http_sign_buvid=true` 时先于 signType 判断，false 时仅 `signType!=3` 调用。原生 `Account` gateway interceptor（init 0x1160548a4 当时 snapshot guestId）在 canonical 0x116054980 用 `setValue` 写 `GuestId`，无本段 login/host 门控；`ktorRequestEnable=true` 明确跳过该 canonical（0x116095ab8→0x116095bb8）。 |
| 4) 参数及来源 | 请求体两键（0x11604991c–0x116049a34）：`device_info` ← `BFCAccountGuestInfo.info`；`dt` ← `base64([rsa encrypt:guestInfo.key])`（0x1160499d8 取 RSA 密文，0x1160499e8 `bfc_base64EncodedString`）。公共参数追加 `sdk_ver="0.1.15"`（0x116046148–0x116046158）。RSA 公钥不是本地 PEM：`+[BFCAccountRSA requestRSA:]`（0x11605b678）内部走 `requestPublicKeyWithCompletionBlock:`（0x11605b6e0）在运行期单独取回。option 层 `setIgnoreCodeNonZero=1`（0x116046204）：非零 code 不在 HTTP 层抛错，交业务回调判断。 |
| 5) 签名与编码规则 | 走传统 HTTP 公共层签名（`createSign:` 0x11609ce34 的排序/转义/secret 拼接）；`setApiKeySecretType=1` 选择该族 secret 类别。`dt` 的 RSA 密文以 base64（非 hex）编码。 |
| 6) 响应结构 | 信封 JSON `{code: NSNumber, message: NSString, data}`：仅当 `allHeaderFields[@"Content-Type"]` 前缀为 `application/json` 时才 `JSONObjectWithData:options:1`（0x116046844 起），要求顶层是 NSDictionary，再读 `message`/`code` 并 `setResponseCode:`（0x116046d58）。`+[BFCAccountGuest loadGuestIdWithCompletionBlock:]` 的回调 0x11605a658：transport error 时回调 `(error, -2)`；读 `response.code` 后失败分支组 NSError（`[BFCAccountInjector apiRequestErrorDomain]` + `NSLocalizedDescriptionKey`）**且不保存**；成功后才取 `data.guest_id.longLongValue`，只拒绝 0/-2，不能写成“必须正数”。成功经 `barrier_sync` 写 Guest 对象与 GuestPreferences。该函数未发现定期过期或并发请求合并标志。 |
| 7) 与 NeoBili 当前实现的差异 | `AppGuestRegistration` 已接入启动/激活登记、公钥获取、自身资料 AES-CBC/RSA 编码及 guest_id 持久化；公共头及 SMS device_tourist_id 复用实际回执。失败不存并于后续激活重试，账号切换保留访客编号。当前服务器接受待验证。 |
| 8) 证据等级与版本 | 8.89 静态（0x11605a5a0、0x11605a658、0x116049894、0x11604991c–0x116049a34、0x116046058/0x116046060/0x1160460fc/0x116046108/0x116046204/0x116046218/0x116046844、0x11605b678、0x104c6daf4）；证据明细 `DerivedData/Validation/team-c3/findings.md` S3.3；当前源码。 |
| 9) 残余不确定项 | setup104c6daf4安装UIApplicationDidBecomeActiveNotification到mainQueue，callback104c6cbf0→loadGuestId；setup另在104c6e060直接调用。同已证guestId0/-2门禁衔接，不保证每次active网络登记。task witness/全启动注册执行次序仍是独立静态目标；真实缓存/错误返回及9.13版本行为属运行期（root-static-session/device-boundaries.md）。 |

### DEV-04 账号刷新与 confirm

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `x/passport-login/oauth2/refresh_token`（builder 0x116047d98）；`x/passport-login/confirm/refresh`（0x116051660/0x1160488d4）。均为 Golang passport 表单。 |
| 2) 触发时机 | `refresh`（0x116052f78）先请求服务器时间（HB-04），回调忽略时间请求 error；`validateAndRefresh`入口0x116051ab8、回调0x116051cc0按服务端 refresh 布尔决定刷新；`validateTokenRealWithSSOModel`（0x1160521b8）拒绝 nil SSO（61000），否则把旧 accessToken 交给 info 请求。confirm 在 cookie 回调 0x116053734 内以捕获的**旧 SSO** 与 sts 发出，不等待其结果。 |
| 3) 请求头 | 未在主文档逐项列出；由 passport 表单与 cookie 驱动（`x/passport-login/confirm/refresh` 用旧 cookie 的 DedeUserID/SESSDATA）。 |
| 4) 参数及来源 | refresh：旧 `refresh_token`/`access_key`、`sts`、`local_id`/`buvid`（跟踪 BUVID）、`bili_local_id`（localBUVID）、`device_id`（currentBUVID）、`device_name`/`device_platform`；**该 builder 没有 `device_meta` 或 extendedFields 合并**。时间请求返回 0 时把 sts 改为 -1，否则沿用返回整数。confirm：旧 cookie 对应 mid/session、旧 token、`revoke_api=REFRESH_CONFIRM_REVOKE`、sts 及上述设备字段；缺失字符串退空。 |
| 5) 签名与编码规则 | 已追到 BFCAccountApi `_request` 0x116046064：sdk_ver=0.1.15、apiKeySecretType=1；BFCApiRequest `_queryString` 0x116097308 在原生通道选 passportKey，业务参数覆盖公共参数后调用 createSign。signType 默认为 0（BFCApiOptions init 未赋值），编码显式转义 `!*'()`；Ktor 运行时分支不由该证据覆盖。 |
| 6) 响应结构 | refresh 响应 0x1160533dc：transport/非零业务码失败不保存；code=0 解码 SSO 后没有额外模型有效性检查。新 mid 与当前 mid 相同才刷新当前 cookies；cookie 回调忽略其 error，更新 SSO(type=1) 后发 confirm 并返回成功。其他 mid 仅更新对应已保存账号，不刷新当前 cookies。`validateTokenRealWithSSOModel` 回调：transport/API 错误返回 needRefresh=false；业务 61000 只有被校验模型 mid 与当前账号 mid 相同时才调用退出；code=0 仅检验返回 mid/expires_in 非零，未拒绝负值或比较新旧 mid。 |
| 7) 与 NeoBili 当前实现的差异 | 已接入 `AppLoginRenewal`：启动/前台恢复按需 info，refresh=true 才取时间并 POST refresh，账号一致且新 token/Cookie/refresh token 完整才保存，然后用旧 SSO confirm。SMS 和安全验证兑换解析 refresh_token/expires_in；`DeviceIdentity` 将完整凭据放入单个 Keychain 记录并回读确认，重启优先读该记录。同账号续期不改变播放/行为的登录代际；换号/退出取消并拒绝迟到结果。成功检查间隔 30 分钟、失败冷却 60 秒是本地低资源策略，无定时器；61000 标记 App 授权失效并通知设置页开放短信补授权，不擅自删除 Cookie。旧安装未保存 refresh token，需短信重登或同账号补授权后才能自动续期。 |
| 8) 证据等级与版本 | 8.89 静态（builder 0x116047d98、refresh 0x116052f78、callback 0x1160533dc/0x116053734、confirm 0x116051660/0x1160488d4、validate 0x1160521b8）；当前源码（grep 结论）。 |
| 9) 残余不确定项 | 给定可见链已证validate info响应提供refresh Bool，回调0x116051eb4/eb8据此是否调用refresh；expires_in非零校验/保存不等于本地提前N秒比较。operation.autoRefresh只选validateAndRefresh或validate。撤回“本地阈值在此比较链内”前提（root-static-remaining/findings.md）；三个定位caller已全文核：HD2/PhoneBus无条件validate后update、MineVM avatarUserId0且hasLogined才validate，所选callbacks无expiry/time阈值；不推全应用间接路径，服务器如何给refresh与9.13实效另验。 |

补充证据：`requestInfoWithAccessKey:` 0x116047bb4 为 GET `x/passport-login/oauth2/info`，
含 access_key、local_id、bili_local_id、device_id、buvid、device_name/device_platform。
`BFCAccountInjector.currentBuvid` 0x105040dc0 通过服务 fingerprint getter，
`DeviceServiceImp.fingerprint` 0x1049572ec 转 `BFCDeviceToken.currentBUVID` 0x115fd7754：
优先 serverBUVID，否则 localBUVID。`localBuvid` 0x105040db0 / 0x104957300 单独转 localBUVID。
因此 device_id 可以使用本地登记回执，不能把跟踪 BUVID 直接替代 bili_local_id。

localBUVID 生成 0x115fd6c80：IDFA 非 nil 否则 IDFV 字符串，加 `+平台+Apple` 取大写 MD5；
追加当前系统时区的 yyyyMMddHHmmss 和 `MD5("iOS+首次运行毫秒").prefix(16)`；
0x115fd7520 将前 62 字符按两位十六进制求和，取低 8 位追加两位大写校验和。
首次运行毫秒来自独立 BFCDevicePreferences（初始化 0x115fd5984），不是 guest 时钟。
NeoBili 不读取 IDFA，使用自身 IDFV，独立持久化首次生成时间及编号；日期使用 Gregorian/POSIX
以保证格式长度。这是明确的本地兼容选择，非所有系统 Locale/广告授权分支的复刻。

Cookie 交接 0x11604edf4：官方遍历响应 cookie_info 的 domains/cookies，写系统 Cookie
及 WebKit，并发起 `/api/login/sso?webview_cookie=1`。NeoBili 原生接口从自己的 Keychain
读取 Cookie，不启用系统自动 Cookie，所以原生续期使用响应中的完整账号 Cookie 原子替换；
未增加无消费者的 WebKit SSO 同步。confirm 的 mid/session/旧 access_key/旧 refresh_token
来自更新前的快照，confirm 失败不回滚新凭据、不自动重放。

验证边界：静态链和注入响应可验证请求、签名向量、原子保存、换号竞争、失败退避；
未强制轮换真实账号凭据，当前 9.13 服务端续期接受情况及官方 Ktor/SSO 运行时分支仍须验收。

### DEV-05 新用户注册与换 token

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | SMS register（0x116049374）与 `x/passport-login/oauth2/access_token`（exchange，0x116047fdc）。 |
| 2) 触发时机 | SMS 发送/重发/提交共用 UI 入口 helper 0x104cf8968（见 DEV-07）；`SMSSendResponse.isNew` 控制走注册分支还是登录分支；注册响应 `code=0` 解码 RegisterResponse 后 SMS 服务用其中 code 继续 exchange，未直接把注册响应保存为 SSO。 |
| 3) 请求头 | 未在主文档逐项列出。 |
| 4) 参数及来源 | 注册表单：`cid/tel/code/captcha_key`、四种设备编号 `local_id`/`buvid`/`bili_local_id`/`device_id`、`device_name`/`platform`、`device_tourist_id`；存在旧 accessToken 时加 `from_access_key`。`extendedFields` 最后覆盖这些字段，随后 RSA 回调 0x116049794 再赋 `device_meta`/`dt`，因此它们又能覆盖扩展参数。exchange 仅发送六项：`code`/`grant_type`/`local_id`/`bili_local_id`/`device_id`/`buvid`；空 grantType 在上层退为 `authorization_code`，注册扩展参数不会自动沿用至该 builder。 |
| 5) 签名与编码规则 | `device_meta`/`dt` 由独立 BFCAccountDeviceToken 与 RSA 回调写入；不同于 DEV-02 fingerprint 加密材料，当前文档未展开完整登录 JSON/key 生成，不可混用。 |
| 6) 响应结构 | 登录 SMS 回调 0x11604131c：先检查 response 存在；存在时解析 SMSResponse，`status` 只接受 NSNumber，`url`/`message` 只接受 NSString。`code=0` 且 `status!=0` 时直接 `completion(nil,SMSResponse)`，不保存 SSO；`status=0` 才解码并交 delegate。缺失/错误类型 status 保留对象默认 0，这层没有 required-status 校验。Session UI 回调 0x1149661d0 只有 `status=0` 才 `setLoginSucceed=10`；非空 `response.url` 都会设置 nextBlock；`next`（0x114966778）在 status=2 时带 message 调 `showSecurity`，其他值不带。`handleSSOModel`（0x11604fcf0）若先 `fetchUserModel`，fetch error 会阻止保存；cookie refresh callback 则忽略错误并保存 SSO/user/登录日期与账号列表。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili `SMSPassport` 使用自身 buvid/local_id，并发送已取得的 fingerprint device_id 和访客 device_tourist_id；未取得时省略。bili_local_id/device_meta/dt 配套生成仍未实现，不替换为其他类型标识。 |
| 8) 证据等级与版本 | 8.89 静态（0x116049374、0x116049794、0x116047fdc、0x11604131c、0x11604fcf0）；当前源码。 |
| 9) 残余不确定项 | 原loginRegCheck0x104d5b15c仅勾选/动画，0x104d5b174并非发送；真实loginAction0x104d5c144→0x104d5b184→fastContext(type6)→FastService→LoginFastRequest→POST /x/passport-login/fast/login 已静态闭合。mid/token/本地与服务器设备ID、条件access_key/guestID及extendedFields最后覆盖、公共sdk_ver再覆盖均见root-static-session/fast-login.md。不再列天然运行期表单；code0+status0门禁、captcha特定-105委托与SSO保存到Preferences及bili_account/account API链已补证。验证码续请求关联、cookie回调错误语义、实际物理落盘/新版取值另验。 |

### DEV-06 退出与撤销

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 单撤销 builder 0x1160481d0 与批量 revoke；退出入口 0x11604b964 可被 `logoutIntercept` 阻止（错误 -2）。端点路径未在主文档逐字给出，批量与单条共用同一 builder 族。 |
| 2) 触发时机 | 用户退出；通过拦截后 `revoke_type` 在 `saveCurrentAccount=false/true` 时分别为 1/2；只有 `deleteAllAccount` 且已保存账号数>1 才发 batch/revoke，否则 revoke。 |
| 3) 请求头 | 未在主文档逐项列出。 |
| 4) 参数及来源 | 单撤销 12 项：mid/access_key/refresh_token/session/revoke_api/revoke_type/local_id/bili_local_id/device_id/buvid/device_name/device_platform；批量另加 `need_delete_account_info`（保存账号 revokes JSON）、`is_self_revoke`、`device_tourist_id`，共 15 项。 |
| 5) 签名与编码规则 | 未在主文档记录。 |
| 6) 响应结构 | 请求回调 0x11604c3b0/3b4 都为空：发起网络后立即 dispatch 本地 cleanup，再 `completion(true,nil)`，**不等待 transport/API 结果、不因失败回滚**。本地成功不能证明服务端撤销成功。logout 的主队列 block（0x11604c3b8）清 SSO/Cookie/用户与快速登录资料并发出账号通知；该函数体没有直接清 guest 或 BUVID。通知分派 0x11605e2d8 把原始值 1/2/4/8 映射到 accountDidLogin/Logout/Update/Change。`AccountNotiInfoModule.logout`（0x104c6b418）调 `cleanAllApiCache`；`update`为RET，`login`经40c thunk→2a0更新服务userID（SSO mid nil→0），非空；`change` 清 cache 并更新 Bugly userID。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 账号退出路径见 `BiliPassport.swift`/`DeviceIdentity`；NeoBili 在换登录时刷新公共 session（[DeviceIdentity.swift](../../../NeoBili/Data/Networking/Identity/DeviceIdentity.swift)），是自身隔离策略，不是官方行为的复刻（review R16）。 |
| 8) 证据等级与版本 | 8.89 静态（0x11604b964、0x1160481d0、0x11604c3b0/3b4、0x11604c3b8、0x104c6b418）；当前源码。 |
| 9) 残余不确定项 | AccountNotiInfoModule logout104c6b418及change104c6b4c0调用cleanAllApiCache，update4bc为RET；login40c→bridge6a4→2a0读取SSO mid（nil→0），转String给BFCTrackerService.updateUserIdentifier:，非空实现（typed keypath已核）。静态superclass metadata已解析BFCApiCacheKVDB→FMKVDatabase，clearDB→FMDatabaseQueue dispatch_sync→DELETE FROM T_KVTTable；旧类解析必须运行期说法撤回。仅该API缓存表，不证明清guest/BUVID/Keychain/defaults；SQL实际成功、服务器revoke结果另需运行期（root-static-session/device-boundaries.md）。 |

### DEV-07 短信 UI 的 `login_session_id`（本地派生）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 无独立端点：UI 入口 helper 0x104cf8968 重建全局扩展参数字典。该字典随后进入 sendSMS/提交/注册表单。 |
| 2) 触发时机 | `SmsAlert2Controller` 发送分支 0x104d9ece0 与重发分支 0x104d9f800 读同一全局字典并合入 `BFCAccountSMSContext.extendedParams`；提交分支 0x104da0400 把同一字典与 `scene=popup`/`from_pv` 合并到 LoginContext，经 0x104da0588 `loginWithContext` 发起登录。**在 UI 入口换新，发送/重发/提交复用，不是每个 HTTP 请求重新生成。** |
| 3) 请求头 | 见 DEV-05（表单通道）。 |
| 4) 参数及来源 | 跟踪 BUVID 与十进制毫秒时间直接拼接，再取 UTF-8 MD5 的 32 位**大写 hex**。毫秒 helper 0x104cf86e8 使用 `DateUnix×1000`→FRINTA（最近整数、半值远离零）→有边界检查的 Int64 转换，不是向零截断。全二进制 BL 扫描该 helper 只有四个调用点：0x104cec0c8（在 `+[Login updateLastLoginInfo]`，方法入口 0x104ce92e4 的函数体内）、0x104d1a710 与 0x104d1b0a4（在 `+[StrictLogin overseaForceStrictLoginWithCompletion:toolView:]`，方法入口 0x104d1a2bc 的函数体内）、0x104d1d820（StrictLogin 类内）。 |
| 5) 签名与编码规则 | 该字段是提交表单的一个字段值；无独立签名步骤。Golang SMS send（0x116048be0）与 login/sms（0x116048e54）最后合入 extendedFields，证明该字段进入表单，而非仅供统计。 |
| 6) 响应结构 | 不适用（输入字段）。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili `SMSPassport.Context` 把登录尝试设小写 UUID32，在同次尝试复用（review R16）。生成算法（BUVID+FRINTA 毫秒→大写 MD5）与 NeoBili 不同。 |
| 8) 证据等级与版本 | 8.89 静态（0x104cf8968、0x104cf86e8、四个调用点）；离线假数据验证（12 个 post-Date 毫秒 Double 的 x.49/x.5/x.51 边界，含负数；只验证 FRINTA 消费值与格式）；当前源码。 |
| 9) 残余不确定项 | 不声称任意秒数经 Foundation Date 内部 epoch 转换后都精确保留小数半值；OAuth2 入口的对应字典引用仅已证用于 telemetry，不能扩展到 OAuth 请求。 |

### DEV-08 三字段在所选 generateInfo 未赋值及实际 presence 规则

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 不是独立端点：本条目约束 DEV-02 的 `IosDeviceInfo` payload（字段 21 `isVpn`、31 `ip`、39 `userAgent`）。结论限于**所选 generateInfo 未找到这三项赋值；序列化由消息实际 has-bit 决定**，不否定可变缓存消息后续写者，也不据此自行凑字段。 |
| 2) 触发时机 | 不适用（属 payload 构造约束）。 |
| 3) 请求头 | 不适用。 |
| 4) 参数及来源 | **所选 generateInfo 未赋值的有界证据**：加载 payload 类的 `classRef_BFCDeviceIosDeviceInfo`（0x11f7f02b8）全镜像只有 1 处代码引用（0x115fd5b98，位于 `-[BFCDeviceToken generateInfo]` 0x115fd5b54 内、紧随 `_objc_opt_new`），类对象 0x12023ebe0 只有 1 处（`+[BFCDeviceIosDeviceInfo descriptor]` 0x115fd8988）；阳性对照 `classRef_BFCDeviceToken` 33 处、`classRef_BFCAccountDeviceInfo` 1 处。`setIp:` 共享 stub 0x1175b1720 有 9 个调用点、`setUserAgent:` 0x117656fa0 有 29 个（另 `+j_` 0x10f884768 12 个），抽样反汇编 5/9 与 5/29 的接收者全为 App 环境 IP、抓包嗅探、投屏/DLNA 设备模型、IJK 播放参数、图片下载器、支付 base param、下载实体、`TypepbRoot` 调试配置、`SuperNodeRelease` P2P 节点等与登记 payload 无关的类。`isVpn` 为全镜像 0 命中：连 `_objc_msgSend$setIsVpn:` stub 都不存在。站点表 `DerivedData/Validation/team-c3/setIp-setUserAgent-callers.json`。 |
| 5) 签名与编码规则 | 不适用。 |
| 6) 响应结构 | 不适用。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 已有版本受限的自身登记适配器，所选资料子集不填这三项。完整54字段、当前服务器兼容及真机验收仍未完成（见 AppDeviceRegistration.swift）。 |
| 8) 证据等级与版本 | 8.89 静态，所选流程与抽样调用；不证明其他间接写者不存在。证据明细 `DerivedData/Validation/team-c3/findings.md` S1、`team-c1/findings.md`；当前源码。 |
| 9) 残余不确定项 | 所选类引用与抽样 setter 调用不能排除全程序间接写者；实际serializer已核：has-bit=0→writeField直接return不写wire，hasIndex20/30/39与真实stride0x20已更正；新对象零初值依NSAllocateObject契约且可变单例后续写者未穷尽；反方向（若服务端要求这三项）需运行期证据：真机在 `-[BFCDeviceToken serverBUVID]_block`（0x115fd72e4）的 `getDeviceInfo` 返回处下断点、或在 `generateInfo` 返回前 dump 该消息，也可解密一次 `x/resource/fingerprint` 的 AES 明文对照（需授权）。 |

### DEV-09 访客取 RSA 公钥接口

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `+[BFCAccountGolangApi requestPublicKeyWithCompletionBlock:]` 0x116047568 **尾跳** `get:params:completionBlock:`（0x117325dc0）⇒ `GET https://passport.bilibili.com/x/passport-login/web/key`（路径 CFString 0x11d3d5b10）。 |
| 2) 触发时机 | 访客登记前取公钥（与 DEV-03 的 `dt` 构造配套：用该公钥加密本地 AES key）。 |
| 3) 请求头 | 公共层默认头（该接口无独立特殊头）。 |
| 4) 参数及来源 | 无业务参数（`params` 为公共层默认）。 |
| 5) 签名与编码规则 | 公共层签名；响应为 JSON。 |
| 6) 响应结构 | 回执在 `+[BFCAccountRSA requestRSA:]` 的 block 0x11605b70c：`code != 0` → `NSError`（nonZero 域 + message）；`code == 0` → 取 `data.key`（0x11605b880，非 NSString 门则空串）写入 `rsa + 0x8`、`data.hash`（0x11605b8f4）写 `+0x10`，随后 `completion(nil, rsa)`（0x11605b960）。**本文不记录该接口返回的密钥内容。** |
| 7) 与 NeoBili 当前实现的差异 | 本轮未做差异判定；NeoBili 访客流程是否走同一公钥接口属 DEV-03 差异面。 |
| 8) 证据等级与版本 | 8.89 静态（上列全部地址）；`DerivedData/Validation/team-c24/findings.md`（task-28）。 |
| 9) 残余不确定项 | 返回hash有明确消费者：encrypt:options11605b9c4仅options bit0真时把hash插入明文首部，再CRSA.encrypt；默认encrypt:传0。密码登录及tourist devicePassword所选caller传1；访客dt所选11605b108调用默认encrypt:，不前插hash。不推广所有alias；实际返回key/hash、轮换/文件与加密失败及9.13适用性仍需另验（root-static-session/device-boundaries.md）。 |

### TICKET-01 GetTicket（Moss/gRPC）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `0x100096814` 构造 `GetTicketRequest`，调用 `0x100098d48→BAPIApiTicketV1Ticket.getTicketWithRequest:handler:`；默认 host `grpc.biliapi.net`，`package=bilibili.api.ticket.v1`、`service=Ticket`、`method=GetTicket`。该默认路由不是所有网关或实验分支的实测结果。`TicketMoss`（0x1000982b0）负责退避。 |
| 2) 触发时机 | `BFCTicket.onTicketReq`（0x100096328→内部 0x100096170）在锁内读 ticket 与 `expireAtInS`，解锁后比较当前 Unix 秒；`expireAtInS` 为零或剩余秒数不足配置提前量（默认 1800）时调 0x100099678 安排异步更新，**同时返回读出的旧 ticket**（不阻塞 getter）。服务内部禁用状态返回空字符串。`onTicketResp`（0x1000964d4→0x100096380）在内部启用且状态等于字符串 `1` 时记录到期并调用同一异步更新入口。`TicketUpdateModuleModuleInitialize`（0x100095c5c）经注入的 TicketSetup 见证 0x100096584 调 0x100095f08 安排 global/default QoS 异步任务；startup 0x10009937c 在锁内标记 setup-ready 并按缓存 expiry 决定是否异步刷新。 |
| 3) 请求头 | 调用 receiver 是 Ticket 类：classmethod 0x10518e5f0 先 `defaultService`，再调 instance `getTicket`；`defaultService`（0x10518e51c）每次 alloc/init，没有 once service。wrapper 创建 0x10509f93c 在 `REST=false` 时取注入 service implementation 的 options witness+0x20；已闭合 `MossServiceRealImpl` 的 0x100151544→0x107c24fa0→0x10f82fcac→0x115e06c20，最后 helper 每次重读当前 accessToken 及 Device/Network metadata。KMoss 分支仍由其 engine 提供 metadata，不能外推同一最终 header。 |
| 4) 参数及来源 | 内部 RPC 构造函数 0x100096814：`context=1` 是 string→bytes map，`keyId=2` 是固定键标识，`sign=3` 是 bytes，`token=4` 为 string（此构造器未赋 token）。context 实验启用时加入 `x-fingerprint`（设备指纹二进制材料）及 `x-exbadaset`（安全模块材料）。执行 enable 的输入是配置 `ticket_enable` 的实验命中，不是 `presetHitValue`：`sub_100099108` 把 feature 开关保存到 +0x10（0x1000991b0），其输入是 `BFCTicketConfig` 单例槽 0x1210643d8 的 +0x10（0x10009918c/0x1000991ac），该字节由 `BFCTicketRuntime` 0x10009ae38 读实验 `ticket_enable` 得到（`hitExperimentalGroupForKey:presetHitValue:1`，落 [sp+0x2c] 0x10009af70），`presetHitValue=1` 只是无分组时的预设值；`TicketInternal` 的唯一构造调用点在 `-[BFCTicket init]`（方法入口 0x100095e84，索引符号名如此）内 0x100095ec8。材料门禁：cfg+0x11 命中才加 `fingerprintMaterialBin`，cfg+0x12/+0x13 命中才加 `gaiaMaterialBinWithIgnoreNormal:`。 |
| 5) 签名与编码规则 | 签名输入构造 0x100096d40：先 append 新构造的 `BAPIMetadataDeviceDevice` 的 Protobuf bytes，再按 context key 字符串升序逐项 append `UTF-8(key)+raw(value)`，**没有在这些 append 之间加长度或分隔符**；空 key 整项跳过，空 value 仍保留 key。设备 metadata 来自构建、设备、guest 及指纹服务，与 Neuron AppInfo 的字段来源不同。0x100099f3c 调用 CCHmac SHA256，将固定客户端签名材料作为 key，输出 raw 32 bytes 写 sign；空消息或空 key 在此函数返回空 Data。离线假数据验证通过：Python 与 CommonCrypto HMAC-SHA256 2,000 组对照、24 个 context 排列的拼接结果及 100 个退避边界。 |
| 6) 响应结构 | `GetTicketResponse` 描述符：`ticket=1/string`、`createdAt=2/int64`、`ttl=3/int64`、`context=4/message`。成功回调 0x100099934 根据 response 非 nil 进入 0x100099978，**没有在此分支同时要求 error 为 nil**；expiry 使用回调时 Date Unix 秒 + ttl；配置 `ttlOverwrite` 非零时替换 ttl（没有限定必须为正），`createdAt` 未参与该计算。锁内分别写 `TicketPrefs.ticket`/`expireAtInS` 并清进行中标志。失败 0x100099cdc 只清该标志，保留旧票据和旧 expiry。`TicketPrefs` 是 `BFCPreferences` 子类，两属性独立写入、无事务性落盘证据。退避：`TicketMoss` 按 `min(failureCount×baseDelay, maxDelay)` 安排下一次请求，值小于 1 时立即安排且无 jitter，否则再加 `[0,maxJitter]` 的浮点均匀样本；调用 0x100098ac8 在 response 非 nil 时清失败计数，否则加一；失败回调不自动递归重发。配置默认 `baseDelay=1`、`maxDelay=15`、`maxJitter=1` 秒。 |
| 7) 与 NeoBili 当前实现的差异 | `AppTicketService` 已实现 RPC/签名、非阻塞缓存、提前续期、失败退避与旧票据保留；DeviceIdentity 向全部已实现 App 请求提供 ticket。签名使用同次 Device protobuf 原始字节；账号代际/BUVID 隔离是本地保护策略。可选安全 context 未填，当前服务器接受待验证。 |
| 8) 证据等级与版本 | 8.89 静态（上列全部地址）；离线假数据原语/拼接验证；当前源码。 |
| 9) 残余不确定项 | `ticket.get_max_tries` 默认 4 只写入 cfg+0x30，加载该配置槽 0x1210643d8 的全部 7 处（0x1000962a4/0x1000968d0/0x100096a18/0x100099194/0x1000994a4/0x10009ab1c/0x10009abf4）只读 +0x10..+0x13、+0x18、+0x20、+0x28，整个 ticket 区非栈 `[x,#0x30]` 访问只有 0x100098e68（dispatch queue attributes）与 0x100099ff8（CCHmac 上下文）⇒**所查direct-load与具体桥面未消费该值，不得写成“会重试4次”，也不能据此否定所有间接消费**。TicketPrefs 用全局 singleton 槽 0x12027d090 与固定 suite，没有按 UID/access-token 选命名空间，也没有成功保存前的 account-generation 检查；外部登录/登出是否另行 reset 属运行期分支、静态不可定（下一步 `$PY scan_addr_uses.py 0x12027d090` 收齐全部读写点，并用 9.13 抓包核对跨账号 ticket 复用）。 |

### TICKET-02 `x-bili-ticket` / `x-ticket-status` 拦截器（HTTP 与 Moss）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 两个拦截器：HTTP 侧 `canInitWithRequest` 返回 true（0x1051f24f8）；Moss 侧 native `BFCMossTicketInterceptor`。Kotlin 侧由 `provideTicketRequest`（0x10aad1ab8）构造 RequestResponseHook 进入 18 成员集合（注册读取点 0x10b92111c）。 |
| 2) 触发时机 | 每个被拦截请求的 canonical 阶段。原生 HTTP `canonicalRequest`（0x1051f2500）无条件 `setValue`，nil ticket 改空字符串，没有已有值保留/empty/host 门禁；原生 Moss 0x1051f26b4 先合入旧 `extraHTTPHeader`，再以 exact dictionary key 覆盖 ticket，nil 也改空（不同于 Kotlin Moss 的 nonempty 门禁）。Kotlin coroutine 0x10aad2234 只在 ticket 非 null 且非空时加 `x-bili-ticket`。 |
| 3) 请求头 | 写 `x-bili-ticket`；读响应头 `x-ticket-status`。原生 HTTP 响应入口 0x1051f25d4 要求 NSHTTPURLResponse 类型，再从 `allHeaderFields` 字典取键；原生 Moss 从 `responseHeader` 字典取键。 |
| 4) 参数及来源 | ticket 值来自 TICKET-01 的 `onTicketReq`（0x100096328）。Kotlin 侧 `KTicketServiceImpl.onTicketWithHost:path:`（0x100134734→0x100134d58）**不使用传入的 host/path**，直接调用注入的 `ticket.onTicketReq`；`update`（0x100134848→0x10013478c）以状态字符串 `1` 调用 `onTicketResp`。Kotlin↔native 桥：getter 0x10aad2b54、update 0x10aad2e90。 |
| 5) 签名与编码规则 | 不适用（仅 header 注入）。 |
| 6) 响应结构 | 状态精确等于字符串 `1` 时才调 update（Kotlin Moss 与 provideTicketRequest$1/$2 都只识别 `1`）。原生 HTTP controller（0x115e0c710）同步 gateway 数组后逐项调 `canonicalGatewayRequest`（0x115e0c870），只有结果 response 非 nil 才停止；检查到的方法无 URL/service 白名单。 |
| 7) 与 NeoBili 当前实现的差异 | `HTTPTransport` 与 SMS 传输已把匹配已发送 ticket 的 x-ticket-status=1 接入更新；生产公共 App 请求统一携带自身缓存票据，未获取时省略。 |
| 8) 证据等级与版本 | 8.89 静态（0x1051f24f8/0x1051f2500/0x1051f26b4/0x1051f25d4、0x100134734/0x100134d58/0x100134848/0x10013478c、0x10aad2b54/0x10aad2e90）；当前源码。 |
| 9) 残余不确定项 | 具体GTicket/native bridge body已复读，host/path→ticket字符串、update→固定1。调用安装已有18成员集合正证；真实调用次数/时序另验，不因间接装配放弃静态接线（root-static-session/ktor-ticket-boundaries.md）；`Enable GInterceptor` 键槽 0x120c5e410 旧直接寻址扫描遗漏初始化间接 STR（105d5ac44→10bfd0a94→10bfd0af4）；key 对象初始化与请求 attributes 值写入须分别追，缺省 false 不能代替最终值，因此不能宣称全部 HTTP 请求都带 ticket；Foundation/transport 对响应 header 大小写与重复头的归一化在 NSURLSession 实现内（本镜像不含），静态不可判定，不能据 exact subscript 断言 wire 大小写变体一定失败（下一步 9.13 抓包核对同一 key 的大小写变体与重复头合并，静态侧对照读取点 0x1051f25d4）。**9.13 抓包（线级，team-c12）已就此给出对照**：全语料没有任何自定义头在同一请求上重复（重复头只有 webview 的 `cookie`），HTTP/1.1 请求用混合大小写（`Session_ID`/`Buvid`/`GuestId`/`APP-KEY`/`ENV`，80 条，78 条为 `/x/vip/ads/material/report`）、HTTP/2 请求同名头一律小写（`session_id`/`buvid`/`guestid`/`app-key`/`env`），即 **wire 大小写变体由 transport 决定而不是由字典键名决定**；`x-ticket-status` 响应头只在 webview 请求见到 22 次（取值恒 `1`，`/x/click-interface/web/heartbeat` 20 + 另 2 条），官方 App 原生请求 0 次；`x-bili-ticket` 在 `dataflow.biliapi.com`(1439)/`grpc`(1234)/`api.bilibili.com`(924)/`app.bilibili.com`(727)/`passport`(258) 出现而在 `cm.bilibili.com`、`data.bilibili.com` 为 0。8.89 所选 ticket 安装集合/原生与 Kotlin header 注入正链成立；18 成员其余 typed binding 名字和动态属性写者须以各自实际表/函数证据为准，不能由字段寻址或直接 caller 零命中宣布外部写入、全局无适配器或未调用。Moss raw compression enum2 与9.13 gzip线级样本分开记录。BLog真实 DDLogger→双 thunk 配置链已闭。G缺省false与缺键defaultattrs复制已核；CommonParamsPlugin原始writer读取kn.new.interceptor默认true并把实际返回Bool装箱写G，不能称最终永远false或true；ticket reset、五GPB clear边界见 root-static-session/last-tail.md。 |

### HB-01 播放器移动心跳 `x/report/heartbeat/mobile`

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `https://api.bilibili.com/x/report/heartbeat/mobile`，`BFCApiOptions` 原始 `requestMethod=1`，`postApiWith`（0x1148888b0）调 `requestSync`。 |
| 2) 触发时机 | `BBPlayerHeartBeatServiceV2.playStart`/`playEnd`（0x114889414/0x11488956c）先验证播放准备状态、context/meta 有效性与完成状态；`_playStartReport`/`_playEndReport` 按 `v8.48.0_heart_beat_update_meta_info` 条件更新质量/语言等信息后调用下层心跳。`itemPlaybackState` block（0x11488a2c0）按原始状态值分派（new raw3 先 `updatePausedTime`、old raw2/5 才 `_playStartReport`；new raw4 先 `updatePlayedTime`、old raw2 才报告开始；结束报告条件为 new raw6、或 new raw5 且 old!=1、或 new raw0 且 old 为 3/4）。`applicationDidEnterBackground`（0x11488b0b8）在 `reportPolicy` bit2=0 时只 `catchAndStorePlayEndData`，bit2=1 才 `service.playEnd`；`applicationWillEnterForeground`（0x11488af54）在有效且未 completed 时 `clearStorePlayEndData`，无效且 bit2=1 时先 `resumeTrackerMetaInfo` 再 `_playStartReport`。 |
| 3) 请求头 | 由公共 `BFCApiRequest` 层写（User-Agent / Session_ID / x-bili-trace-id / extraHTTPHeader / Buvid）。`postApiWith` 复制参数后补当前 idfv/idfa 和 `polaris_action_id`，删掉内部 `hash`/`isStart`。 |
| 4) 参数及来源 | `Context.generateMutableDictForEvent`（0x114885bcc）输出 session、start_ts、video_duration、total_time、played_time、paused_time、actual_played_time、list_play_time、miniplayer_play_time、last_play_progress_time、max_play_progress_time、quality、is_auto_qn。`MetaInfo.generateDict`（0x114886d4c）再输出 mid/aid/cid/sid/epid/type/play_type/sub_type/play_mode/network_type/auto_play/epid_status/play_status/user_status 以及 from/spmid/from_spmid/track_id/sessionID；字符串 from/spmid/from_spmid 缺失填 `default-value`，track_id/sessionID 缺失填空；`attached_avid` 受 `playerDefaultQueue` 分支控制；`cur_language`/`perfer_type` 有空格串兜底（是原字面拼写）。`generateExtDictForEvent`（0x114886290）生成内部 `isStart`（开始 1、结束 0）与 `hash`（NSUUID.UUIDString，nil 时空字符串），hash 用于缓存匹配、发送前删除。计时：`updatePlayedTime`（0x114885674）`played_time` 加墙钟整数差，`actual_played_time` 用单精度 `delta × playbackRate + previousActual`（fmadd）后向零转整数；`updatePausedTime` 以相同墙钟基点累加 `paused_time`；`calculateTotalTime`（0x1148863a8）令 `total_time = played_time + paused_time`。 |
| 5) 签名与编码规则 | 同 FEED-01 的公共签名层。会话 ID 生成：`Context.setupSession`（0x1148859c8）优先采用 `metaInfo.sessionID` 非空字符串，否则 `BBPlayerSessionManager.createSessionID`（0x11487f6b8）：`BFCBuvid.buvid` 与 `NSNumber(double(Date.timeIntervalSince1970 ×1000))` 用 `%@%@` 拼接，取 `bfc_md5String` 再 lowercaseString；结果是小写 MD5 形状，不是 UUID，也未看到随机数。`NSNumber` 文本格式已闭合到指令（0x11487f700–0x117409820）。 |
| 6) 响应结构 | completionHandler 从映射的 `/data` 取 `ts` 并记成功；errorHandler 另有“response 是 HTTP 对象且 statusCode=200”时也记成功的分支，其他情况记录错误 code。因此不能把 `BFCApiRequest` 的 error callback 一律当本队列失败。服务端 ts 反馈：`reportTrigger`（0x114888230）的同步 `postApiWith` 成功后，仅 snapshot index0 且 `apiCallback` 非 nil 时把 serverTs 排到 main（0x11488843c/0x114888484/0x114888494），block 0x114888560 调捕获 callback；`Context.reportEvent`（0x1148866e0）安装的 callback 0x114886910 弱取原 context，非 nil 就写 `start_ts`（实例 +0x50，0x11488692c）——**没有 captured session/hash/current start 比较，也没有 ts>0 门禁**；每次调用 `postApiWith` 前先把 serverTs out 初始化 0（0x11488836c），HTTP200 错误分支也可判成功。发送与缓存：`reportWith`（0x114887940）把非空 item 加入内存，`syncToFileCacheImmediately=true` 时同步文件后退出该入口，false 时仅在 `reachability.currentStatus` 非零时触发发送；`syncFileCache` 用 NSKeyedArchiver 归档到系统目录、文件名 `heartbeat.v2.cache`/`heartbeat.v2.cache.copy`；`reportTrigger` 逐条同步调用 `postApiWith`，失败最多再试两次（先 sleep(5) 再 sleep(10)，即每轮至多三次尝试，发生在串行 API 队列），成功后按 item.hash 匹配移除内存项。`loadCachedReportItems`（0x114888570）检查文件存在/NSData 非空后 unarchive，**未读取当前时间、item 年龄或账号**；`loadFileCache` 的排队 block 0x114887854 直接 `addObjectsFromArray` 到 memCache，没有按 TTL/账号过滤。恢复发起方：`BBPlayerCoreModule.onModuleInitializedConfig`（0x1147ddd4c）取 sharedManager 再 `loadFileCache`，位于后续 `hasLogined` 检查之前。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 在 `reportAppWatch` 用 `postApp(path:"x/report/heartbeat/mobile")`（[BiliAPI+History.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+History.swift)），参数由 `AppWatchProtocol.mobileParameters`（[AppWatchProtocol.swift](../../../NeoBili/Data/Networking/Reporting/AppWatchProtocol.swift)）生成：`played_time` 取真实观看墙钟时长，`actual_played_time` 独立按倍率分段累计；`last_play_progress_time` 与 `max_play_progress_time` 分开；`start_ts` 先取本地秒，起播回执由 sender 按播放 session 校正；历史保留本地起播值。发送层只在内存排队、按账号/视频/分P 串行、失败不恢复队列、无文件缓存与后台 stash（review R17）。 |
| 8) 证据等级与版本 | 8.89 静态（上列全部地址）；当前源码。9.13 同链未验收。 |
| 9) 残余不确定项 | metaInfo已有具体UGC/OGV/inline/迁移赋值链复用，不把泛“其余”当天然不可静态判。reportTrigger成功后用captured hash→removeMemCacheWith：锁内选首个hash相等字典，NSMutableArray.removeObject按对象相等移除，无session/视频/account二次区分；不能称正好删除一个重复或证明真实碰撞发生。实际频率/交错、9.13及未识别全业务builder属于有限覆盖之外（root-static-exposure/final-feed-heartbeat-tail.md）。 |

### HB-02 观看历史 `x/v2/history/report`（含 `/report_scene`）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `reportScene=0` 用 `https://api.bilibili.com/x/v2/history/report`，非零用同主机 `/x/v2/history/report_scene`；`BFCApiOptions.requestMethod` 设原始值 1。入口链：`BBHD2MPHistoryReport.reportPlayHistory`（0x10cb17ff4）→ `CloudSyncHelper.reportPlayHistoryWithParams`（0x104a80850）→ Swift 实现 0x104a80fcc。 |
| 2) 触发时机 | `reportPlayHistory` 要求 `cid >=1`，block 填字段后检查 `BFCAccount.currentUser`；没有用户时调 `saveLocalWatchWithReportModel`。`_addObserver`（0x114452ebc）观察 `playbackState` 与 `playerDestroyed`：状态原始值 5 时 `reportWhenStoped` 为真走云历史入口，否则仅内存；原始值 3 分支用于历史提示；`playerDestroyed` 为真且 `reportWhenStoped` 为真时也调云历史入口。`shouldReport`（0x1144528ec）拒绝 `cid<1`；`reportPolicy=1` 且实验 `ff_player_history_report` 命中时拒绝。 |
| 3) 请求头 | 公共 `BFCApiRequest` 层。 |
| 4) 参数及来源 | 校验（0x104a80fcc）拒绝空 model、`cid<1`、`avid<0`、`epid<0`、`duration<1`；`ignoreTimeVerify` 为假时还拒绝 `currentTime<1`。通过后若整数 `duration - currentTime <=4`，直接把 `model.currentTime` 改成 `-1`（距结尾判断，包含超过 duration 的输入；不是累计观看四秒或恰好播完的证明，整数减法有溢出 trap 分支）。请求字典：type、sub_type、cid、aid（来自 avid）、sid（来自 seasonId）、epid、progress（经上述改写的 currentTime）、duration，均转十进制字符串；`localStartTime` 非零时加 `start_ts` 与 `device_ts`（double 转整数向零截断，有有限值与整数范围检查）；`sourceType`为整数，0省略source，非0经104a82c64的21项表转换String后非空才插入；1player-old/3tianma-inline/7story-single/8story-series/17story-ogv/20player-window等，越界unknown（完整表见主文档）；`scene` 按 `UIApplication.applicationState` 为 0 取 `front`，否则 `background`；`extendFields` 在标准字段之后、`report_scene` 之前合并；`reportScene` 非零时加 `report_scene`。**纯播放历史链不会产生 `source` 键、不走 extendFields 合并、也不加 `report_scene`**：`BBHD2MPHistoryReport.reportPlayHistory` 的 block（0x10cb180f8–0x10cb181b0）只 setType/setSubType/setAvid/setCid/setSeasonId/setEpid/setCurrentTime/setDuration/setLocalDeviceTime/setLocalStartTime/setSyncLocalType，且该 0x10cb1xxxx 区间内没有 `setSourceType:` 的 selref 调用点（全镜像该选择子 25 处调用点均不在此区间）。 |
| 5) 签名与编码规则 | 同 FEED-01 公共签名层。`localDeviceTime` 来自 `BFCServerTimeChecker.realTimeInterval`，`localStartTime` 来自 `tracker.heartBeat.curHeartBeatContext.getLocalStartTimestamp`（0x114885230 读 `_start_verify_ts`(+0x18)，不是 NSDate 那份）。 |
| 6) 响应结构 | 主文档未记录该入口的响应消费细节；`syncLocalType` 对应的本地缓存写入发生在异步请求启动后，没有在此入口等服务端成功才写入。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 在 `reportAppWatch` 用 `postApp(path:"x/v2/history/report")`（[BiliAPI+History.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+History.swift)），参数由 `AppWatchProtocol.historyParameters` 生成，`progress` 取 `report.position` 向下取整、`duration` 取媒体时长、`device_ts` 取本地当前秒；`sid`/`epid` 固定 `"0"`；没有 `source`/`extendFields`/`report_scene`；历史 checkpoint 不发 `mobile` 的判定在 `reportAppWatch` 的 `delivery == .checkpoint` 分支。另有独立网页通道 `x/click-interface/web/heartbeat`（[BiliAPI+History.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+History.swift)，Cookie-only 登录时使用），与 App 通道分开。见 review R13/R17。 |
| 8) 证据等级与版本 | 8.89 静态（0x10cb17ff4、0x104a80850、0x104a80fcc、0x1144528ec、0x114452ebc、0x10cb180f8–0x10cb181b0）；T2 findings C-1/C-2；当前源码。 |
| 9) 残余不确定项 | extendFields逐key覆盖、reportScene非0后写已闭；sourceType真实整数→104a82c64的21项source String映射已闭，0省略/越界unknown。CloudSyncService.getReportParams读服务self._sourceType，非源ParamsModel；4独立场景新建receiver分别17、7/8、1、20，不作服务预填链。Interactive/OGV代理已绑定具体CloudSyncService class，经manager缓存/alloc/init，weak target非nil且active才forward普通setSourceType；Interactive写1/OGV写bizSourceType，不保证inactive写入。observer init安装已证，实际账号/回执交错与9.13另验（root-static-session/last-tail.md）。 |

### HB-03 Atomic 应用心跳与 NetTracker（Neuron 事件，非独立端点）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 不直接调播放历史 HTTP：`BFCAtomicHeartbeat._fireDelegates`（0x1149f2f10）经注入 helper 0x100129684 调 `BFCNeuronService` 的 `customEvent`/`setExtendedFields`/`trackEvent:trackPolicy:`（policy raw0），最终走 LOG-01 的 Neuron 通道。事件 ID：`app.app.new_heartbeat.0.other`（`_reportHeartBeat`）、`app.app.new_heartbeat.1.other`（`_pointTransition` 0x1149f2e88，仅 pointState=3/10/20 发，之后 state+1，=21 时 invalidate 并清 point timer）。NetTracker 另发 `public.heart.net.track`（诊断分支）。 |
| 2) 触发时机 | 模块 184 任务清单 index29（0x120273d20），priority 450、moduleInitialize/main，exec 0x1001295b0→0x100129c50；读 `enable_bfcatomic_heartbeat`（default=true，调用点 0x100129e00），返回非 0 才创建 `BFCAtomicHeartbeatInjection` 并 `shared.startWith:`。`startWith:`（0x1149f2868）保存 injection 后 `startBeating`；`startBeating`（0x1149f29fc）先把 `_newHeartBeat` 置 true，读 `standardUserDefaults.infra_heartbeat_terminate`（CFString 0x11d387390）作 lastBegin，保存当前 `NSDate` Unix 秒为 begin 并写回同键；`setup`（0x1149f2b74）以 `arc4random()%30` 秒排主队列 block 0x1149f2c58，再启动 always timer（30 秒）并将 pointState 置 0、立即启动 point timer（1 秒）；两 timer 均 NSTimer+BFCWeakProxy、mainRunLoop common modes、repeats=true，添加后 fireDate=distantPast。`endBeating`（0x1149f2b20）invalidate 两 timer 并置 pointState=21。`bfcheartbeat_nettrack_enable`（default=false，0x100129ed4）通过时才在 main 队列 now+20 秒执行 0x100129bd0，把独立 lazy NetTracker 加为 delegate。 |
| 3) 请求头 | 同 LOG-01（Neuron 通道）。 |
| 4) 参数及来源 | Atomic 字典由 `heartBeatDictParams`（0x11487eac8）产出，要求 `playback.isGetFocus`、dataSource 非 nil 且响应 `trackMetaInfo`，否则返回 nil；写 avid、cid、seasonid、epid、playback_status、playback_time、playback_rate、video_quality、is_buffering、track_id、scene、spmid、from_spmid、playerSessionId（0x11487f108–0x11487f230），最后 session 从当前 tracker getter 取，未另建 atomic session。`playback_status` 静态表 0x11cf91e38 将 raw0/5/6→stopped、1/2/4→paused、3→playing、unsigned>6→unknown；`video_quality` 先取 `qualityProxy.currentQuality` 十进制 String，只有等于 `"0"`（0x11487ef5c）才改取 `currentItem.ijkItem.currentQn`。`scene` 由 `getCurrentSceneValueWithMap`（0x11488ae28）按 `context.status.isFullScreen/isVerticalScreen` 选 sceneMap 的四个键（landscape/portrait × full/half screen），nil/非 dictionary map 返回 nil。`_fireDelegates` 建 `app_running_status` 等公共字段，对 `app.app.new_heartbeat.1.other` 加 `hb_moment`，对 `app.app.new_heartbeat.0.other` 加 `heartbeat_new`/`heartbeat_begin`/`heartbeat_last_begin`/`last_begin_interval`，然后枚举 `hashTable.allObjects`；回调 0x1149f3338 只对支持 `heartBeatDictParams` 且返回非空字典的 delegate 做 `addEntriesFromDictionary`（0x1149f33b8），**字段可被后枚举 delegate 覆盖，未在这段排序或按 session 过滤**。`heartbeat_new` 直接取 `_newHeartBeat` 字节（0x1149f304c）转 Bool String，`begin`/`lastBegin` 及两者差用 `"%.0f"` 格式写 String；发 0.other 后在本方法尾清 `_newHeartBeat`（0x1149f32cc–0x1149f32ec），**不等待上传回执**；1.other 不清此字节。NetTracker.heartBeatDictParams（0x10012bd68→0x10012a910）读注入 apiClient.metrics 与 reachability 状态，构造 outer key `stream`，其 value 是一个对象数组的 UTF8 JSON String；内层六 String：timestamp、stream_event 字面 `stream_reachable`、stream_code、http_code、http_error_code、reachability。 |
| 5) 签名与编码规则 | 同 LOG-01。JSON 用 options0/UTF8，失败只省略 `stream` 键。 |
| 6) 响应结构 | 诊断分支与返回 `stream` 字段分开：`bfcheartbeat_analysis_close`（default=false，0x10012b21c）命中直接跳过 diagnoser 但仍返回心跳字典；否则 `bfcheartbeat_analysis_force`（default=false，0x10012b2c8）读取后，仅当 `stream=false`、或 http_code 不在 200–399、或 force=true 时调用 diagnoser（0x10012b3b0）。`_diagnoser` callback 0x10012c838→0x10012b9f8 仅 result tag bit8=0 时继续，bit8=1 直接不 track；继续时将诊断 payload 经 JSON(options0)/UTF8 转 String，成功添 `analysis` 到发起诊断时捕获的六字段 inner 字典，序列化失败省略 `analysis`，仍由 `_mikoto.trackTech` 报告 `public.heart.net.track`，policy raw2、rate100。`DiagnoserService` 距上次诊断 <10 秒时回传 skip tag 0x100，in-flight 或 `diagnoser_close` 时回 tag 0x102；包装 helper 0x1001420d8 把 context byte+0x30 OR 0x100 后回调，故这些 skip 正好被 NetTracker 的 bit8 门禁排除。`accepted probe` 置 in-flight=true（0x10013fc7c）并取 `retriveDNSAddress`；正式 probe 创建 dispatch group 与初值 5 的 semaphore，DNS 结果 join 后写 dns_info；innerAll 逐 host TCP 443、dataFree 逐 host TCP 809、outNet 逐 URL 调 `BFCNetSpeedTool.speedTestWithURL:`；in-flight 实际在安排 group.notify 之后立即清 false（0x100140520），不等待 probe 完成。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 源码无 `new_heartbeat` 事件、Atomic 数据源或对应应用 timer（review R23，已闭合为“缺口事实成立且可判定”）。不能把旧包应用 timer 频率改成 NeoBili 观看报告频率。 |
| 8) 证据等级与版本 | 8.89 静态（上列全部地址）；T2 findings C-5（时间来源分离）；当前源码。 |
| 9) 残余不确定项 | Diagnoser注销已正证：witness11b0b3710+8 register/+10 unregister10013e4a4；component deinit遍历(type,witness)，BLR witness+10→public unregister105131718→resolver105136b14。resolver取owner+10锁对象并锁其+10，移除owner+18字典对应type/qualifier键；旧raw-pointer零命中/仅LINKEDIT不能否定该生命周期。注销服务注册不等于取消正在跑的网络task或logout；endBeating已排block仍可_timerAlwaysStart的实际并发/9.13行为另验（root-static-exposure/auth-action-diagnoser.md）。 |

### HB-04 公共服务端时间辅助 `x/report/click/now`

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `https://api.bilibili.com/x/report/click/now`，由 `BFCServerTimeChecker.getLocalRealTimeIntervalWithSyncServer` 创建 options（0x115dab484），`timeout=2` 秒，映射 `/data/now` 为数值。 |
| 2) 触发时机 | `realTimeInterval`（0x115dab1a8）固定以 `syncServer=true` 进入 `realTimeIntervalWithSyncServer`（0x115dab238），优先返回 `BFCServerTime.timeInterval` 的非零值；为 0 时 `canUseNetwork`（0x115dab6a4）仅检查注入的 apiOptions/apiRequest/apiModelDescription 三个类非 nil（**不是 reachability 检查**），允许才走 helper 0x115dab37c，不允许才回 `localTimeInterval`。helper 比较 `preferences.boottime` 与当前 boottime：exact 相等即返回 `NSDate` Unix 秒 + 缓存 `slinterval`；不同且 `syncServer=false` 返回 0；不同且允许同步时，用 RAM flag 0x120dd11d0 阻止并发更新，先置 true，再创建请求。**此调用不等待网络，冷缓存返回值仍是 0。** |
| 3) 请求头 | 公共 `BFCApiRequest` 层。 |
| 4) 参数及来源 | 无业务参数。 |
| 5) 签名与编码规则 | 同 FEED-01 公共签名层。 |
| 6) 响应结构 | completion 0x115dab5c4 要求返回 `now>0`，才保存当前 boottime 及 `slinterval = now - 回调当时 NSDate Unix 秒`（0x115dab634/0x115dab678），**没有往返时延折半补偿**。无论 now 是否通过门禁，completion 尾 0x115dab690 都清 flag。**error 路径到不了 completion**：`requestWithOptions`（0x115dab524）与 `requestAsync`（0x115dab544）之间只调用过 `setCompletionHandler`（0x115dab53c），没有第二次 handler 写入，故 errorHandler 为 nil；失败分支 0x116093d0c 直接退出。全 `__text` 针对 0x120dd11d0 的 ADRP+byte LDR/STR 扫描只命中 0x115dab464 读、0x115dab470 置 true、0x115dab690 置 false 三处，**没有超时/取消清 flag 路径**。因此首次尝试失败或请求在途后，boottime 不等且 `syncServer=true` 的后续调用一律返回 0（0x115dab468 tbnz→0x115dab558）且不再发请求，`realTimeInterval` 收到 0 再返回 nil（0x115dab1f4/0x115dab228）——单进程内不会自动重试。持久化：`BFCServerTimePreferences` 的 configName 固定为 `BFCLaunchTimePreferences`（0x115dab180），`boottime`/`slinterval` 经通用 `BFCPreferences` 动态属性层写入（`_defaultsKeyForSelector:`⇒key=属性名），两次独立 setter 非事务提交。 |
| 7) 与 NeoBili 当前实现的差异 | 起播响应 data.ts 已由 PlaybackWatchReportSender 按播放 session 消费；历史保留 localStartTimestamp。登录续期独立请求服务器时间。真实观看仍按 systemUptime 计量，未照搬旧包全部时间网关。 |
| 8) 证据等级与版本 | 8.89 静态（0x115dab1a8、0x115dab238、0x115dab37c、0x115dab484、0x115dab5c4、0x120dd11d0 三处访问、0x115dab180）；T1 findings P2；当前源码。 |
| 9) 残余不确定项 | 非 ADRP 形式的间接写入不在此扫描内，进程重启后 RAM flag 归零；suite 名字面量唯一引用 0x115dab184、prefs classref 只有 3 处引用，未发现针对该 suite 的 `removePersistentDomainForName:`/`removeSuiteNamed:` 调用（方法存在性边界，不是“会被清”的证据）；实际存值未读取。`BFCTimestampGateway`（0x10518ce44）另从响应头忽略大小写匹配 `x-bili-app-ts`，`doubleValue>0` 直接当 Unix 秒写 `BFCServerTime`，未检查 HTTP 状态或 error，返回仍为原 wrapper；请求/响应各自重读 `ktorEnable`，不能外推 Ktor/Moss 同样校时。 |
