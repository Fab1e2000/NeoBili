# 传统 HTTP 参数与请求构造

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 传统 HTTP 参数与请求构造

`BFCApiSignHelper.baseParams`（0x11609c68c）创建可变字典，包含 platform=`ios`、
device（phone/pad）、Bundle build、mobi_app、appkey、actionKey=`appkey`（字面字符串），以及有值时的
c_locale/s_locale。statistics 是 JSON 字符串，内部有 appId、platform、version、abtest；
它不是外层 platform 字符串的复用。青少年、课堂、海外青少年与关闭个性化参数带条件分支。
customParams 最后合并，可覆盖已有键；随后审核分支可再写 appver、filtered=`1`。
这些 getter 的来源已逐项定位：platform为字面量`ios`（0x11609c6c8）；device按
userInterfaceIdiom在0x11609c6e0选`phone`/`pad`（0x11609c6f8/0x11609c700）写0x11609c718；
build取mainBundle.infoDictionary（0x11609c72c/0x11609c73c）写0x11609c778；mobi_app与
appkey分别调+[BFCApiConst mobiApp]0x11609c79c、+[BFCApiConst appKey]0x11609c7cc；
actionKey为字面量（0x11609c800）；c_locale调+[BFCApiConst clientLocale]0x11609c814、
s_locale调+[BFCApiConst sysLocale]0x11609c860，两者都只在返回值非nil时写入
（0x11609c828与0x11609c87c门禁，写点0x11609c850/0x11609c89c）。
残余：clientLocale/systemLocale（wrapper 0x105067b34/0x105067b24）最终字符串来自注入服务的
运行期locale，不是镜像常量；本层只产出字典值，字节编码在Ktor0x105d0b070与原生
createSign/_encodeUrl，另见对应章节。

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
authenticationHeaderParams；后者目前仅返回非 nil 的 BFCBuvid 作为 Buvid
（0x11609d4b4加载classref BFCBuvid→0x11609d4b8调_objc_msgSend$buvid 0x11722b880）。
+[BFCBuvid buvid]0x1167cbe68的取值为prefs trackID→Keychain(service枚举2=trackId、
key=buvid；-[BFCKeychain initWithService:]0x1167cd224查3项静态表0x11d085568，
2→0x11d1060d0 `trackId`)→BFCIDFA.idfaStringWithoutDash0x1167cbfe4→
identifierForVendor去连字符（0x1167cc0fc/0x1167cc158），Keychain命中后回写prefs
（0x1167cbfc4）。**首次生成分支（已证）**：prefs/Keychain 均无效时生成体
`+[BFCBuvid buvid]_block` 0x1167cbedc 先置全局"已再生成"标志 0x120e71220=1
（0x1167cbfd8 `strb w9,#1`）；IDFA（idfaStringWithoutDash 非 nil 且 length>0）→ 取
idfa[2]/idfa[12]/idfa[22]（substringWithRange (2,1)/(12,1)/(22,1)，0x1167cc01c/0x1167cc03c/
0x1167cc05c）以 `'Z%@%@%@'`（0x11d3fc730）拼 4 字符前缀（'Z'+3 个单字符切片）再追加完整 idfa（0x1167cc0b0）
⇒ 36 字符；IDFA 缺失 → identifierForVendor.UUIDString 去 '-'（0x1167cc158）同样切片，
`'Y%@%@%@'`（0x11d3fc750）⇒ 'Y' 前缀 36 字符。接受门 `+[BFCBuvid isValidTrackID:]`
0x1167cccfc：NSString+length>0+≠32 位十六进制黑名单常量（0x11d3fc7b0）+≠
'Z'+35 个'0'（0x11d3fc7d0），**不查长度**。过门后 `setTrackID:`（0x1167cc2c0）并
dispatch_async(main) block 0x1167cc38c 写 Keychain(service 2,'buvid')；IDFV 也无效时兜底
为 `'%ld'`×(timeIntervalSince1970×1e6)（常量 0x1182ebd00，0x1167cc314 fmul/0x1167cc318
fcvtzs），**只写内存缓存 0x120e71228（0x1167cc348），不落 prefs/Keychain**，重启即重走
生成。缓存全局 0x120e71228 经 dispatch_once 0x120e71230（0x1167cbeac–0x1167cbed4）。
注意格式确认为 36 字符（'Z'/'Y'+3 位切片+32 hex）；接受门 isValidTrackID 本身不查长度。
全二进制按classref邻近+stub BL统计到117个调用点，明细见
DerivedData/Validation/team-t1/buvid-class-callers.json。
因此认证 Buvid 可以覆盖 extraHTTPHeader 中同名字段。正文后还会执行 requestInjection，
再进入 gateway canonicalization/suspend 拦截。这里不是最终发包头的完整列表。
