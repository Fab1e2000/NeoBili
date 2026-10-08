# 第三方 SDK、CDN 与网页容器的静态入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 第三方 SDK、CDN 与网页容器的静态入口

（证据：DerivedData/Validation/team-c4/findings.md 块2。）

### 依赖清单与来源边界

app 包（bili-universal_8.89.0.app.zip，zipfile 只读枚举，2595 条目）Frameworks/ 下
仅 BGM.framework、BilibiliVideoTools.dylib（及 `._` 元数据）与
libswift_Concurrency.dylib；PlugIns/ 为 0。global_index.py loaded_libraries 的非系统
依赖同样只有这两个（`@rpath/BGM.framework/BGM`、
`@executable_path/Frameworks/BilibiliVideoTools.dylib`）。即绝大多数"第三方 SDK"
是静态链接进主二进制的；以下 SDK 符号全部位于主二进制地址空间（来源：主程序
symbols.txt/query_index），不计独立库覆盖。

主二进制内检出的第三方 SDK 类与其网络入口：AlipaySDK（`+[AlipaySDK
payOrder:fromScheme:callback:]`0x114764d58，dynamicLaunch 0x114764f0c /
fromUniversalLink 0x114764fe8）、微信 OpenSDK（`+[WXApi sendReq:completion:]`
0x116277c90、sendReq:isAutoResend:forceScheme:completion: 0x116277d24）、QQ 互联
（`-[TCLoginViewKit initWithAppId:redirectURI:permissions:loginDelegate:]`
0x11640466c）。各 SDK 独立传输 host（endpoint-host-inventory.json）：支付宝 mpaas
（mobilegw.alipay.com、mcgw.alipay.com、render.alipay.com、mdap/mdgw.mpaas.*
aliyuncs.com、sgw-deepsec.antdigital.com）、银联（95516.com / cup.com.cn 族及固定 IP
101.231.114.217 等）、运营商一键登录（wap.cmpassport.com、log1.cmpassport.com、
e.189.cn、opencloud.wostore.cn、csapi.bol.wo.cn）、腾讯地图与安全（lbs/apis/cc.map.qq.com、
tdid.m.qq.com、mazu.m.qq.com、huatuocode.huatuo.qq.com）、Bugly（ios.bugly.qq.com、
rqd.uu.qq.com）、易盾（rp-mgw.yidun.com）、蚂蚁真实人（mgw.realperson.antdigital.com）、
阿里云 ASR（nls-gateway.cn-shanghai.aliyuncs.com）、分享/登录（api.weibo.com、
openmobile.qq.com、open.weixin.qq.com、long.open.weixin.qq.com）。这些 SDK 入口
类未检出引用 BFCApiOptions/Ktor（未做穷尽审计）；是否共享主程序 URLSession/Cookie
属运行期行为，静态不可判，需真机抓包。BCM 的初始化与传输见广告章节既有闭合。

字段/流程级增量（证据：DerivedData/Validation/team-c15/findings.md；以下符号均来自主程序
symbols/query_index，不涉及随包 Frameworks）：payOrder 主路径为 App 间跳转——
`+[AlipaySDK payWithType:orderStr:schemeStr:universalLink:dynamicLaunch:callback:]`
0x1147653e4 → `callAlipayWithOrderStr:dynamicLaunch:withBlock:`0x114765b64 读
NSUserDefaults `ali_launch_scheme`（0x114765bd0）选启动方式（scheme 表
`alipaymatrixbwf0cml3`/`aliminipayauth`/`alipayhkmatrixbwf0cml3`/`alipayhk`，
areaType 分支 0x114765c1c），进程内不发支付 HTTP；微信 sendReq:isAutoResend:forceScheme:
completion: 0x116277d24（SDK v2.0.4，0x116277e18）校验 appID/universal link 后
transformToUrl 生成跳转 URL（0x116278a18），同为跳转传输。进程内直连 host
（mpaas/Bugly/易盾等）与主程序 session 的共享关系不可判，需真机抓包看各 host 由哪条
会话发起。WXApi 调用方阳性对照（stub 0x10f86fbd0）：BBUperKingBattleVM
openWXMiniProgram:path: 0x10d611118、BBAdCommonJSBridge callupWxMini: 0x10ea77e30、
BBAdHotSpotResolverImp callupWXMini: 0x10ea7fd3c、BBAdStoryActionService
callupWXMiniWithModel: 0x10eae98cc、BBLiveShoppingScheduler genericAction...
0x10efaf460。

### CDN

图片 CDN：hdslb.com 族（i0.hdslb.com 341 条、s1.hdslb.com、dl.hdslb.com）以 URL
字面量为主，加载经主程序图片管线（BFCImageUrlOptions 0x100b11934、
`+[BFCImageConstWrapper isHitExperimentalGroupFor:]`0x105066ba4 等 Kotlin/Swift
侧类型；LightBrowserImageDownloader 0x10147e764 为轻浏览器独立下载器，BBLive*Service
注入 imageDownloader/fileDownloader）。播放 CDN（upos/core.bilivideo.com）由既有
UPOS/Laser 章节闭合。host inventory 中 `<dynamic>` 38 条为运行期拼 host，静态不可
列全。

URL 构造入口（team-c15）：hdslb 裁剪参数是 NSString 分类层字符串拼接——
`-[NSString bbhd2following_imageURLWithStandardSize:needClip:]`0x10e80b594
（含 isLongPic: 变体 0x10e80b59c；同类 bbmyfollowing_imageURLWithSize: 0x10ea48b64）
仅对正则 `i[0-2].hdslb.com`（0x10e80b73c）命中的 URL 注入模板
`%@...@%.0fw_%.0fh_1e.webp`/`..._1e_1c.webp`/`..._1e_1s`/`..._1e_1c_1s` 及区域裁剪
`...@%.0fw_%.0fh_1e_%.0f-%.0f-%.0f-%.0fa.webp`（0x10e80b638–0x10e80b6b0），旧路径
改写正则 `_[0-9]+x[0-9]+\.`0x10e80b760、`/[0-9]+_[0-9]+/`0x10e80b778；.gif 跳过 webp。
即裁剪参数是 URL 字段，构造与下载管线解耦；解码分派按扩展 png/jpeg/jpg/gif/webp/
apng/svga（`-[BFCAVAImageView isBFCImageSupportExtension:]`0x114645b6c，
0x114645b98–0x114645c90）。

### 网页容器

主容器 BFCWKWebViewV2（initWithFrame:configuration: 0x115dd9ed0）：commonInit
0x115dd9f70（反汇编 0x115dd9f70–0x115dda06c）创建 BFCWebViewDelegateInternal 并
同时设为 navigationDelegate 与 UIDelegate（0x115dd9f88–0x115dd9fec），另建配置对象
替换 userContentController（0x115dda00c–0x115dda028），requestProtocols 初始化为空
数组；对外提供 addRequestProtocol:0x115dda06c、addUserScript:0x115dda10c、
addScriptMessageHandler:name:0x115dda240、setCustomUserAgent:0x115dda86c。
JS bridge 基建：JSBridgeAbility 0x1000f6288、JSBridgeSystem 0x1000fc154；业务域示例
`-[BFCVipJSBExport domain]`0x1044072c8（含 mobilePredict: 0x104407b54）；商城容器
BBMallVDWebViewController 0x103546314（globalBridge:closeBrowser: 0x103546878、
decidePolicyForNavigation* 0x103546914/0x10354691c）；支付充值经 BWAJSEventPayHandler
（见会员/商城章节）；游戏/HiLo 侧另有 Trizoa_WKWebViewWrapper（initWithWebView:
0x111bcaa34，decidePolicy 0x111bcaa7c，shouldStartLoadingCallback 0x111bcaebc）与
`-[HiloWebView setCustomUserAgent:]`0x102bfa1a4。UA 注入：Kotlin 侧
KUserAgentModule.userAgent 0x100204c7c；Gripper 侧 HttpUserAgentModule/
UserAgentModuleImp 元数据访问器 0x1000b8418/0x1000e7d5c。

字段/流程级增量（证据：DerivedData/Validation/team-c15/findings.md）：JS bridge 域及
域字符串（反汇编直接读出）——global（BFCGlobalJSBridgeExport domain 0x115deea58：
import: 0x115deea64、getAllSupport: 0x115deee5c、getContainerInfo: 0x115def54c、
closeBrowser: 0x115deff64）、net（BFCNetJSBridgeExport domain 0x115df039c：request:/
requestV2: 0x115df03a8/0x115df3dcc、requestWithSign:V2 0x115df1a5c/0x115df58f0、
uploadImage:V2 0x115df2ba0/0x115df7ab4、getCsrf: 0x115df8c54、
signForQueryItems:appKey: 0x115df9b3c、cookieStringForHost: 0x115df9cc4、
sendRequest:oriUrlString:completionHandler: 0x115df9f38）、auth（0x115dead1c：
getUserInfo:/getUserVipInfo:/refreshUserInfo:/login: 0x115debf0c/ios_purchaseLogin:
0x115ded0f8/exchangeTicket: 0x115dee154）、pay（BFCPayJSBridge domain 0x1146d12c4）、
share（0x115dd3244：setShareContent: 0x115dd3250、showShareWindow: 0x115dd3874、
shareQuickWord: 0x115dd4ec4、shareToTarget: 0x115dd60e8、launchMiniProgram: 0x115dd6bb4、
sharePlacard: 0x115dd7648）、ability（0x115ddc4ec）、secure（0x115dfb0b0：sendSms:
0x115dfb0bc）、storage（0x115dfb91c：getItem:/setItem:/removeItem:/clear: 与 space 命名
空间族 getItemInSpace: 0x115dfcc48–listSpaceKeys: 0x115dfe804）、ui（0x115dff1d0：
setTitle: 0x115dff1dc、hide/showNavigation:、setStatusBarVisibility: 0x115dffb84、
setStatusBarMode: 0x115e013d0、observeThemeChange: 0x115e01224 等）、offline
（0x115dcd074）、VIP 域字符串 'globalVip'（0x1044072c8 立即数解码）、
WebViewJSBUIExport 域 'ui'（0x104bb47cc）、BBLegacyUnitedvideoJSBridgeDefine 域
'unitedvideo'（0x103ebc344）。注册中枢 `-[BFCJSBridgeHandler setBridge:domain:]`
0x104e65474；分发入口 BFCWebScriptMessageHandlerInternal
userContentController:didReceiveScriptMessage: 0x115dd9934。

**net 域签名与 Cookie（关键结论）**：`signForQueryItems:appKey:`0x115df9b3c 按 appKey
映射 appSecret、passportKey 映射 passportSecret（0x115df9b78–0x115df9bf0），query items
排序后 '&' 连接尾接 secret，`bfc_md5String`0x115df9c58 → 主程序同款 appsign
（md5(sorted_query+appsec)）；`cookieStringForHost:`0x115df9cc4 读 currentSSO（0x115df9d08）
→cookieInfo→domains（hasSuffix 匹配）拼 `%@=%@; `（0x115df9e14）。即 H5 经 net 域由
原生代发携带主程序签名与 bilibili 登录 Cookie 的请求（是否同 URLSession 实例仍不可判）。

**请求拦截协议作用范围**：addRequestProtocol: 0x115dda06c 的实现只有
`[[self requestProtocols] addObject:obj]`（0x115dda08c–0x115dda0a0，getter 0x1174f0180；配套
removeRequestProtocol: 0x115dda0bc 同理），**不做任何 NSURLProtocol 注册**；
唯一消费点是 BFCWKWebViewV2 loadRequest: 0x115dda3bc（getter 0x1174f0180 调用方仅
add/remove/loadRequest 三处），对每个注册的**请求处理器**调
webView:canonicalRequestForRequest: 0x115dda424 改写顶层请求，再过 internalReqDelegate
webViewInternal:canLoadRequest: 0x115dda4bc——即作用于主框架 loadRequest 的请求改写，
非全局子资源拦截。业务注册方与实参具体类（team-c25 T1，classref 实读）：
BFCWebViewControllerProfessional 注册 `BFCWebViewInReviewHandler`（0x115dba718–0x115dba728；
class 0x1202311c0、webView:canonicalRequestForRequest: 0x115dc0e0c）与
`BFCWebRefererRequestHandler`（0x115dba754–0x115dba768；class 0x11ff38930、
webView:canonicalRequestForRequest: 0x104f9163c、init 0x104f9175c）；
BBLiveBaseWebViewController webView 懒建 `BBLiveBaseWebViewRequestProtocolProxy`
（classref 0x11f7da000+0xcc0，0x111e517dc–0x111e517e8）→ `setProvider:`（0x111e51844）→
addRequestProtocol:（0x111e51850）。**判据（阳性对照）**：`query_index '*canInitWithRequest*'`
命中 7 个真正的 NSURLProtocol 族类（`CPURLProtocol` 0x1051e2b04、`BWAFileURLProtocol` 0x112fca7fc、
`DeepBlueHttpInterceptor` 0x105063ac4、`BFCHttpTicketInterceptor` 0x1051f24f8、
`BBLivePureRoomHttpGateway` 0x10f819e60 等），上述三个处理器类**均不在其中** ⇒ 原「协议类名未知」
与「注册 NSURLProtocol」措辞已修正为「请求处理器类名已闭合」。

**UA 来源**：`+[BFCApiUserAgent userAgentString]`0x11609d6c0 拼 `%@/%@` +
`CFNetwork/%@`（com.apple.CFNetwork）+ `Darwin/%@` + `os/ios`/`model/%@`/`mobi_app/%@`/
`build/%@`（0x11609d734–0x11609d93c）；Moss 侧 BFCMossUserAgent 0x115e0bfb0 另含
`osVer/%@`/`network/%ld`。WebView 内 UA 改写：BBHD2PhoneWebViewController
modifyCustomUserAgent 0x10ca70e88 按远端配置
`webview.modify_custom_useragent_url_whitelist`（0x10ca7104c）白名单命中后
evaluateJavaScript 'navigator.userAgent'（0x10ca70fd4）取基 UA 并做 iPad→iPhone 替换
（0x10ca71114/0x10ca7111c）后 setCustomUserAgent:；直播 openDialogWebView 族
（0x10dfc1304/0x10e0280f4/0x10e101d14/0x10e13b74c）各自设置。

<a id="第三方发送侧与-cdn-管线分支task-30-补"></a>

#### 第三方发送侧与 CDN 管线分支

**WXApi（微信）在二进制内，但 `sendReq:` 是 QQ 的**：`WXApi` 类方法齐备
（`+registerApp:universalLink:` 0x11626e95c、`+isWXAppInstalled` 0x1162704bc、
`+isWXAppSupportApi` 0x116270578、`+handleOpenURL`/`handleAuthOpenUrl:delegate:` 族 0x1162487ec–0x11624e7d4）。
规范 stub `_objc_msgSend$sendReq:` 0x1175249c0 的**全部 8 个调用点都是 QQ**：
`-[BFCSharePlatformQQ sendNewsMessageWithShareTarget:object:]` 0x115e89510、
`sendMessageWithShareTarget:object:` 0x115e897ac、`sendMiniMessageWithShareTarget:object:` 0x115e89850、
`-[BFCSharePlatformQQV3 …]` 0x115e9274c/0x115e92960/0x115e92a28/0x115e92afc、
`-[BFCShare3rdPartyQQ shareMaterial:toChannel:completionBlock:]_block` 0x116233b98
⇒ `sendReq:` 属 QQ SDK（QQApiInterface）。微信发送器是
`+[WXApi sendReq:isAutoResend:forceScheme:completion:]` 0x116277d24（4 参，既有条目记的
`sendReq:isAutoResend:` 应更正为该方法名）。
**`WXApiDelegate onResp:` 的实现方已闭合**：规范 stub `_objc_msgSend$onResp:` 0x117450500 的
3 个调用点即回调派发点——`-[BFCShare3rdPartyWeChat _kntrOnResp:]` 0x11623679c（0x116236804为内含onResp转发调用）（微信分享适配器，
同类的 `registerWithAppId:universalLink:` 0x116234980、`shareMaterial:toChannel:completionBlock:`
0x116235084、`handleOpenURL:` 0x116234f64、`handleContinueUserActivity:` 0x116234ff4、
`+shared` 0x116234d04）与 `-[UMSPPPayWXPayManager onResp:]` 0x1147b9b18（银联微信支付），
另有 `-[BFCShare3rdPartyQQ _kntrOnResp:]` 0x1162341f0。⇒ 分享域→微信的 delegate 链落在
`BFCShare3rdPartyWeChat`（WXApiDelegate），支付链落在 `UMSPPPayWXPayManager`。
微信发送补证：0x1175249e0 实为两参 sendReq:completion:，全 text 直接边有18个
业务BL和2个转发B。当前分享 callback 0x116235fb8 走此stub→SDK包装器
0x116277c90，在0x116277cfc发四参，isAutoResend=0、forceScheme=0、completion原样。
另delaySendContextReq 0x116276734 在0x116276ab4发送四参：1/上下文字节/nil。
canonical selector槽0x11f7ac1d8逐点核仅上述两真引用，Weibo候选因寄存器覆盖为误报。
不推广至动态selector调用或真实微信交付（root-static-remaining/findings.md）。

**CDN 图片管线按 business 分流，三种 coder 的启用时机不同**：
`+[BFCWebImageManagerWrapper getWebImageManagerForBusiness:]` 0x116070798 按入参 business
（x2）分三支：business==2（0x1160707b0 `cmp x2,#2`）现场建专用管线
`+[BFCImageCache getCustomImageCacheForPath:nil business:2]`（0x1160707d4）+
`[[BFCWebImageDownloader alloc] init]` 且 `[downloader.config setMaxConcurrentDownloads:1]`
（0x116070808）+ `[[BFCWebImageManager alloc] initWithCache:loader:]`（0x116070828），结果存入全局槽
0x120e62a48（0x11607083c）；business==3（0x1160707ac `cmp x2,#3; b.eq`）走全局槽 0x120e62a50，
惰性调 `+[BFCWebImageManagerWrapper configImagePrefetcherBusiness:3]`（0x116070870）后返回；
其他 business 返回 `+[BFCWebImageManager sharedManager]`（0x116070888）；槽已存在则直接 retain
（每 business 只建一次）。编码器开关的取值关系：
`+[BFCImageConst enableBFCWebImageVideoCoder]` 0x11606c11c 本体读实验键
`image.enable-bfc-video-coder`（CFString 0x11d3d6ed0）经 `hitExperimentalGroupForKey:`，
其 4 个消费点全在 UIImageView 的 BFC 加载
（`bfc_autosetImageWithURL:ptSize:placeholderImage:options…` 0x11607609c/0x116076978、
`bfc_setImageWithOutClipURL:…` 0x116077214）⇒ **视频帧 coder 是加载期按实验键判断**；
而 `+enableBFCWebImageAvifCoder` 0x11606c354 与 `+enableBFCWebImageAWebpCoder` 0x11606c368 的
唯一消费点都是 `+[BFCImageInstaller install]`（0x11606d5b8/0x11606d5cc）⇒ **AVIF/AWebP 是安装期
一次性注册**。同区另有 `image.enable-bfc-image-log`（0x11d3d6ef0）与
`BFCImageConstWrapper isHitExperimentalGroupFor:`/`hitExperimentalDDGroupFor:`（0x11606c148–0x11606c15c）。
manager 内存/磁盘/网络选择已读（root-static-remaining/findings.md）：
0x11608aa60按context或manager选cache，options bit16跳过查询；真实cache
0x11607b6e4默认type3，type0不查、1仅磁盘、2仅内存、3组合。内存objectForKey
0x11607b818；组合命中且bit0清直接返回，否则进磁盘同步dataForKey 0x11607b930
或异步objectForKey:withBlock: 0x11607b990。磁盘解码有效后0x11607bd58回填内存。
下载判定0x11608af58：缓存miss或bit2请求下载，0x8000抑制，再AND delegate及
loader准入；缓存+bit2先交缓存再刷新网络，不是每个网络失败自动退缓存。
loader→downloader→operation已接NSURLSession dataTask 0x116084fd4、HTTP
0x116085124、Cronet0x1160852c8及resume；真实选择与结果由运行输入决定。
错误0x11608b3b8按delegate/loader策略维护failedURLs，成功按bit0清理并写缓存；
有限body未見第二host failover，不否定其他URL resolver/重试层。三种coder实际
实验值、缓存命中、物理落盘与请求交付仍需运行期。


### 普通首页 V2 曝光池静态补证

仅8.89所选SmallCoverV2/RealExposure链（root-static-exposure/home-exposure-findings.md）。
RealExposure slot0x120358638持有ExposureV2.Manager。metadata+0x90→0x103eb72bc
将pool.dictionary置为空，是真实全池reset实现；未确定所有业务caller。raw8入口
0x101b60644只调用manager+0x158 check及+0x160 duration settle，后者只移除effective
raw3，不能称清所有show池。SmallCoverV2 show raw5经RealExposure delegate+0x20
解析为raw1；duration显式raw3。同Manager普通滑出/离开/后台路径保留raw1 Context，
只结束duration；threshold/接收器分流已核，不把V2 raw policy混作Neuron event_policy。
Manager新建替换已接完整appearance链：反射enum0x11986d920 ordinal1为
viewWillAppear；VC0x101a37608传raw1→dispatcher0x103d9ffd4→0x103da02d4按
行为筛选/排序注册项并调用。RealExposure.setup0x101b6000c注册raw1
callback0x101b61cac→weakloader0x101b60b70→0x101b60bc8，provider的root-view
existential存在才新建Manager、0x101b60c8c替换旧实例，fresh字典即刷新普通show池。
这不等于普通滚动或首页下拉刷新，不将条件执行说成无条件。显式+0x90 reset业务caller
仍未定位，但不妨碍上述新owner替换正例。reset后generic旧context仅提取/release，
已展开descriptor与destroy，无主动duration finalizer/report调用；不推广任意外部析构
副作用。其他卡片raw2/raw4和新版多实例/真实监听数量仍留边界。duration receiver tag2直接执行自身closure，字典接收器走delegate+0x28，
因此不能将所有policy等同feed-card.duration.show。


### Ticket maxTries 的有限消费边界

补证root-static-session/ktor-ticket-boundaries.md：KTicketServiceImpl/GTicket具体
native/Kotlin桥只传host/path→ticket字符串，update→固定字符串1，无cfg/maxTries
数值输出。7条cfg direct load逐项复读未消费+0x30。BFCTicketConfig nominal
0x1194779dc有10字段，vtable唯一entry0x100096624为10参初始化器；ObjC RO
0x11d4d09d0 method/property list为nil。Swift/ObjC offset槽都为0x30，当前ADRP
扫描无consumer。不能写成重试4次，也不能推广任意alias/其它间接计算全域不存在；
“未读Kotlin所以天然不可判”已由具体桥证据取代。


### 评论分享消息结构补证

root-static-remaining/comment-share-schema.json复核Req4字段oid/type/rpid/needTranslate；
Resp字段1..16为subjectMaterial、qrcodeURL、savePicText、openAppText、shareTimeText、
biliLogoIcon、extra、fromSubjectTypeText、openAppTextSubtitle、bgColor、contentBgColor、
contentAnchorImage、bgTopOverlayImage、reply、parentReply、subjectControl。子消息
Archive6/Dynamic4/Article4/Subject3/Extra3各字段已列，Subject一个oneof、hasIndex=-1
按实际descriptor解释，不把-1一概称无presence。微信通用桥IMP0x11623679c读取
WechatShareThirdParty.wxDelegate，验WXApiDelegate后在0x116236804转发onResp；
特定评论operation与delegate实例/结果handler相关性尚未由该generic桥单独证明。


### Swift NeuronCore 的独立过期清理

root-static-fnval/neuron-v2-clear.md补证：TraceNeuronModuleModuleInitialize task
witness0x11b2ef328→body0x10495def0，初始化NeuronCore并存singleton0x121071bd0，
再经实际metadata+0x138→start0x104972084。start→CacheManager.open0x104960190，
本地disk enabled且开库成功才算截止；checked signed天数×24×60×60，now>0且
now>age时算毫秒cutoff，经0x104965350 global.async→weakself worker→事务
0x1049659e4 DELETE WHERE _ctime < ?；失败rollback，完成回main。
新库UNIQUE(_sn,_logid)，旧ObjC库UNIQUE(_sn)，同表名不能证明共享/替代。
NeuralConfig初始化expire_days默认10存+c8/key+d0/+d8，但start对应key候选默认
从+e0读取（该槽初始化batch_size_factor默认7）；只记录已读偏移，不解释为bug，
远端resolver可覆盖。旧enable_clear_overdue_v2 flag与此新task选择条件尚未绑定：
真实旧getter所查直接/selector候选只在旧run，不能因名字或零扫描把两owner合并。
新链启动/清理API已闭；Config resolver具体实现、装配条件、实际DB/远端值仍待定。


### 首页自定义 raw policy 与明确 owner 覆盖

root-static-exposure/home-policy-owner-continuation.md核所选Pegasus区间的14个
Items构造实现及conformance getter：BannerV8政策5/2/4/4/5，NotifyTunnelV1为5/4/5，
多种大封面含raw2；Item独立flag位w4与policy字节w5不能混作Neuron event_policy。
raw1/2创建Context并按identifier入池，raw4直接执行比例callback而不入池。Banner
raw2 rematch_exposure进入当前子卡协议+28；raw4 switched/ratio进子卡轮播/比例，
Notify raw4按isFiring与可见比例控制timer+380/+390，非观看时长report。
Search/Live的真实Manager属性及getter caller均核，未在这些owner链找到+90；
reset函数地址绝对引用仅metadata slot、直接边/地址材料化扫描无额外caller，
只是明确寻址覆盖，不证明全程序动态reset不可达。普通首页viewWillAppear重建
池的正例不依赖这个显式reset。


### Swift Neuron 配置 resolver 与通用任务门

neuron-v2-clear.md增量已核：Core+f0是NeuronDelegate，constructor0x104963cb4
保存x6/x7到+100/+108，producer0x10495faf4传具体closure0x10495e384；该闭包
通过DeviceDecisionService Inject key0x120274918/938发getIntegerForKey:defaultValue:。
DD mapper/provider工厂已接V2/legacy双分支，默认Int先转String，getString后radix10
checked解析，无效退default。具体resolver不再标“不明DI”；后端选中实际值另验。
通用Gripper ConfigableRunnableTaskInterceptor读gripper.runnable.interceptor.config，
blacklist按task name抑制执行，modified走独立配置修改，非旧neuron clear布尔键的
硬编码别名。旧isClearOverdue getter/setter在所查体仅访问独立字段，无绑定副作用；
尚未找到旧布尔值生成此字典的边，不据字面名或0callers宣称永不关联。


### Ktor attrs 的真实 map、复制与 key 等价

root-static-session/g-attrs-producers.md补证AttributesNative interface hash12380
method+28→0x105d07878→底层map0x105d0826c。HttpRequestBuilder clone
0x105d432c4在0x105d434a0逐key复制source attrs，故写者不必再次引用G全局槽。
所查23个AttributeKey ctor直接入口区分21静态名字与2动态：createPlugin注册key，
InfraNetTrackSimpler从IgnetAttributes临时map生成key后put；后者已读空map起源、
domain-downgrade/transport项与header write once=true，不把任意true指认成G。
AttributeKey.equals比较名字及+10类型信息，不只比指针，也不只比同名String。
原始G值写者已找到：CommonParamsPlugin callback10a9aec60按kn.new.interceptor（默认true）返回值装箱，经实际Attributes.put写同G键；具体应用client采用面与实际配置值仍保留独立边界。

### 补证：请求构造与回执的静态范围

以下补证仅适用于所选8.89 build88900100原始指令，不能替代9.13 wire或实际服务器结果。二次兴趣回调的早期weak门只限制absoluteModel；两路仍汇入共享manager.model写入，之后才weak检查helper/reload。Item与SubItem曝光标记是不同实例字段；Item初始化false及11个业务true写点、SubItem T17已有对象false重置各自成立，不互相替代。完整站点见root-static-exposure/feed-residual-closure.md。

原生公共参数完整覆盖次序是base字段→customParams→审核hook（in_review时appver/filtered）→authentication包装（ts/access_key）→business options.params→sign。disable_rcmd由baseParams供给，审核hook所选body不改它；Story body无直接literal不能推出最终缺席。Dislike始终id/goto，12个附加键各按length非零写入，extraParams最后覆盖。Ktor启用路径独立分析。

动态发布Req真实16字段，其中sketchType为int64；Resp真实11字段。Card/Tag/Topic构造及主要发布成功消费已展开，来源与覆盖不能只从schema推断。评论DetailList主consumer实际更新session及prev/next分页；验证码发布error=-352且voucher非空才进验证，成功且token非空后复用原参数/回调递归sender，取消/空token走原failure，所选循环不含有限retry上限。互动弹幕按scene分平铺post与post2 JSON text/cmd，撤回/删除各有不同builder；完整键与地址见root-static-social-rpc/findings.md。直接通知literal扫描不能证明全局消费者不存在。

BUVID底层已追至Security查询/删除；访客setup直接及active通知load桥成立；logout/change缓存清理已追至FMDatabaseQueue同步DELETE FROM T_KVTTable；RSA返回hash仅options bit0真时前插，所选访客dt默认0。系统实际保留、SQL成功和服务器结果另属运行边界（root-static-session/device-boundaries.md）。评论native微信completion在adapter+20，与Swift shareCallback为两个分支，不能把generic桥归给所有评论operation。

#### 辅助模块的确定映射与分支

Comic字典classref已解为NSDictionary，GetComic两callback的消费键与任意远端schema区分。SeasonList实际root data/isArray0并映射ObjC BBUperSeasonDataModel，不借sortSubmit的optional规则。五小游戏入口实为原生runtime/JS handler经BFCApiRequest；snake-case业务键与common追加camel-case键不同，本地URL/spm注册字典已找到producer。Mall真实thunk能经x2 helper解析，空apiUrl另走host/path fallback；支付charge回执status1/2与其它retry分支已展开，≤2等待5秒、3/4等待30秒、>4失败，余额仅status1成功。完整地址/字段见root-static-peripheral-api/findings.md；有限索引不等于全部远端schema或全版本完成。

播放器预加载long_edge/short_edge取UIScreen bounds×scale、Int32短长像素边，所选getteronce缓存，与当前横竖points无关。Unite默认音轨优先Dolby首项、否则lossless、否则普通首项；defaultQuality影响localResponse stream复用，不能写死一个音轨ID。Swift评论分享面板两BFCShare send复用原model的shareBlock/completeBlock，归native adapter链，不把Kotlin直连微信writer冒充这两个sender（root-static-fnval/player-followup.md、root-static-remaining/findings.md）。

#### 两枚投币与诊断服务注销

CoinWidget真实twoCoinsBtn选择2，经CoinService/provider与Swift builder把Int.description写multiply，已闭UI选择到请求值。channel SingleCoverV9 cell的finish/state接线也已定位；该event是channel-detail，不推广所有首页。Diagnoser witness+10有实际unregister，component deinit经间接BLR调用并从resolver注册字典remove，取owner+10锁对象后锁其+10。仅零直接调用/指针扫描不能否定注销；注册remove不证明取消已有task、登出触发或9.13行为（root-static-exposure/auth-action-diagnoser.md）。

#### 启动事务、心跳缓存与日志结构补证

Token.done与Transaction.finishItem真实ObjC方法表及item/token/operator身份已闭。兴趣accepted完成仍缺限定寻址外的间接source；这不是不存在或静态不可能的证明。心跳成功后按captured hash选首个相等字典，再调用Foundation removeObject，没有额外视频/session/account核验；是否实际发生碰撞仍未知。

BLog C++ job+0是排序/代序号、string起+8，旧把首8字节当日期解释撤回，不能借另一DDLogFileManager默认配额填补。Debugger canonical injector改host/trackSession并受debug配置门禁，不是通用认证注入。文本8静态+4动态列与编码期身份快照已明确；实际队列交错另验。Pre/Part/Merge builder及Part显式PUT已补，tryAv短纯数字≤5返回nil而非原数字（root-static-remaining/findings.md、root-static-exposure/final-feed-heartbeat-tail.md）。

小游戏common builder补充：APPLET-ID取bizId去build前缀，miniapp-key来自全局槽而非appletInfo；五所选GET均跳过仅non-GET/有效body时的requestInjection，requestAsync真实在113088964。RewardAd的ad_unit_id非空门先于构造fallback，不能以nil转空后备分支声称正常发送空adunit。

DDLogger配置真实caller已追到1049559b8→双thunk→11539bdc4；prefs missing/invalid缺省30/5MiB，非零才覆写底层20/2，stored0跳过覆写，不能把共享stub当不能追的假阳，也不能与C++BLog配额混用。LIVE指定completion已读至a7c，按共享状态可条件重启但未比room/uuid/end代次；这不证明实际stale交错发生。WatchLater旧单条/batch指定options及response闭合，转发资源的更上游另追（root-static-remaining/findings.md）。

Mall DynamicApi来源已追到commonRequest注册与router request命令原JS字典转发，KMApi为KMMRequest String桥接后的direct字段写；实际运行JS产生值另验。miniapp-key全局槽已在文件中初始化至CFString包内对象，仅审metadata未读取key内容，header及appStart共用（root-static-peripheral-api）。

CloudSyncService代理真实类绑定与forwardingTarget已闭：manager按class取缓存或alloc/init，proxy存weak target并记目标class；只有非nil且active才把普通setSourceType转给服务。Interactive写1，OGV写业务传入值；四独立ParamsModel场景不混为服务source。DEV04三个具体caller已全文核无本地expiry时间阈值，只对应无条件validate/update或avatarId0&&hasLogin条件。DeviceConfig账户清理只重置universalBlocked set再sync，不称清五GPB或全部账号数据（root-static-session/last-tail.md）。

BLog目录真实来自CFString包装与ObjC setup，自定义非空logDir/cacheDir优先，否则NSTemporaryDirectory附BLog/logs/cache。YYYY-MM-DD由gettimeofday/localtime_r/snprint生成，更新门用epoch墙钟毫秒，非单调钟；job+0仍独立序键。FAV最后链已闭到Chronos UpdateRelationshipChain输入须weakself存活且isActive、当前meta.relationship非nil、至少一个输入关系字段非nil才应用；favorite_state非nil时再经event→现有状态更新，不声称物理folder按钮发起收藏mutation。WL指定MainVC setup/appearance与batchwrapper已读，外部账号notification与未知indirect资源element来源尚未定位，属于有限寻址未证，不是全程序缺席（root-static-remaining/findings.md）。

FallbackCache真实Kotlin export已找到，placeholder brk非最终producer；DI key→NamedBean root+458 id139→ProviderAsProducer→DoubleCheck root+450 id140→FallbackCacheImpl的声明链已读，generic map安装/lookup已接（下列补证），运行期replacement/child override另验，不能叫巨型switch天然不可判。IM实际delegate注册至GroupManager：full真groupList集合diff，假relationLogs type3/4增删；好友列表其他receiver另核。im_session_refactor门禁真实BBIMHelper/deviceDecisionService默认false已闭，实际命中另验（root-static-social-rpc/f-group.md）。

#### 所选播放器入口与预加载边界

V2UGC wrapper正向转UGCHelper，自身不选实验。offline Task admission按state与computed couldPlay，DASH两段均严格>20%、非DASH≥20%；不是此层直接fileExists。预加载JSON要求字典，expire_time<1或≥truncate(now)接受，正值严格过期才错误；valid V2Preload并行fresh V2且localResponse=nil，InlinePreload所选body只验证后asset delivery。V2成功解析构建MediaPlayerItem并可增补localResponse streams。既有quality UI与Story Unite路由复用，不扩大所有播放scene；taskcommand1005闭至cachedtask查询，未知UIfactory边界单列（root-static-exposure/player-routing.md）。

Download command1005已追到底层Message1036及NotifyManager.notifyUi，从allTaskInfoDict[key]取cachedtask并回调，不是即时filesystem existence/size检测；再由上层state/couldPlay准入。此前“filesystem executor待追”标签撤回，OS实际文件可用性仍不能由cachedtask保证（root-static-exposure/player-routing.md）。

IM totalUnreadStyle2常量槽118e40740已闭为__TEXT64位标量-10086，不是缺失fixup对象。PauseSession继承到Count，count属性Tq,N；setCount10e5b8294才将传入NSInteger包装NSNumber后写KV。实际运行count语义/9.13行为不从哨兵数猜（root-static-social-rpc/f-group.md）。

#### 发布成功消息的真实注册

8.89 主镜像中，`BPCFollowingPublishSuccessMessage` 的 NSString 常量与 Swift 字符串须分别追踪。所选四处正向注册为：MainViewController 0x1012a2c54 安装 weak-self action（0x1012aa0f4→0x1012a376c）；IndexContainer 0x10e8da5c8 安装 0x10e8da60c，isCampusJoin 为真直接退出，否则在当前 tab/index/count 条件满足时才 switch；DraftManager 0x10e9ba564 安装 0x10e9ba60c，currentType.length 非0时异步调度 mainThread，删除当前 draft-type 后在 delegate 支持时调用 publishSuccess；SaveManager 0x10e9e997c 安装全局 block 0x11cdaa608。Main action 要payload topicId匹配当前topic，sortType3或全部子VC原数据空才延迟1秒对选中子VC pull-refresh；Save invoke仅lastPublishInfo非零时deletePublishInfo。此消息与 `BFCCommentShouldRefreshList` 不是同一通知，不能移用其消费者证据。证据：`root-static-social-rpc/f-group.md` 所列原始函数。

style2 的 count 元数据须区分表头与属性条目：0x11d4afbf8 为三行、stride16 的属性表头；真实 count 条目位于 0x11d4afc20，attrs 指针槽 0x11d4afc28 指向 `Tq,N`。原常量 -10086 与 setter 后续 NSNumber 包装的局部结论不变。

#### DD 服务实际构造与 legacy 缓存的局部补证

8.89 的 V2 Swift lazy getter 经 KntrKDeviceDecision.shared.dd、原始 Kotlin adapter 和 Gripper 类型键 IDeviceDecision，实际声明 provider root+0x88/id17→root+0x80/id18→scope lambda→0x10a9c05a0→0x10a9c0738 分配 DDContainer，并在 0x10a9c077c 调 constructor。其 getString itable 对应 0x10a9c68d8，不再只是同名类候选；此构造链不排除运行期 binding replacement。legacy 的结果读取 0x1000617fc 与写回 0x1000620bc 分别使用 rwlock 与字典，后者仅 w4 bit0 允许时写；0x1000672cc 是递归规则解释 body。0x1000445f8/0x10004191c 为 operator 字符串与枚举转换，0x10005f494 为 Error witness accessor，不应再将它们列作未知外部 evaluator。CoreData._nodes 包装来源和 V2 下级实际 receiver/context/解释 body 已按后续具体补证接起，不能把前置快速查询 0x10a9dcb4c 仅因短路返回命名为结果缓存。证据：`root-static-fnval/neuron-v2-clear.md`；实际远端配置、当时选择 legacy/V2 与 9.13 路径均需另证。

#### Gripper Gripper 安装与覆盖规则

FallbackCache 注册不止有同名声明：8.89 root NamedBean builder 0x10b92b088 所产 list 被 0x10b93ca78→0x105345abc 转入 interface2a00 slot2，其已解实际实现 0x10b8e2020；实际 factory receiver 来自 root+0x30→DoubleCheck→SwitchingProvider id0→0x10b93c248 constructor0x10b8dac74，allocation typeinfo0x11bd14b30确为DefaultGripperSettings，其2a00 slot2=0x10b8e2020。该实际函数分配 DefaultGripper 并调用 0x10b8e4b0c 建立 DefaultProducerContainer，存 Gripper+0x28。容器分 default+0x38 与 qualified+0x40 maps；原 HashMap.put 0x1052462e8 按相同 key 索引替换旧 provider，故同 key+qualifier 后项胜前项。lookup 0x10b8d5750 有效 local 优先，nil/typeid 特殊结果才同键同 qualifier 转 parent。此前 0x1053478e8 实为 component class 检查/unwrap，不是 bean map getter。此正向安装链接到已证 FallbackCacheImpl producer；不能据此排除后续运行期 replacement、child scope 或动态模块，也不能证明磁盘实际内容/9.13实现。证据：root-static-social-rpc/f-group.md Final finite actions 原始 body 与 metadata。

V2 DD 新增 receiver identity 补证：0x10a9c3994 构造 DataCenter 存 DDContainer+0x28，随后将同对象复制到 backend+8 并将 backend 存 DDContainer+0x38。因此 getString→backend 的前置查询实际在该 DataCenter 上找 hash28680 slot+0x28，模块槽 0x120c6c4e8+0x10 仅提供 CoreDataType 参数，不是 receiver。DataCenter 0x10a9d500c 按 ordinal0/1/其它选择自身+0x38/+0x40/+0x30；原 tables分别绑定 CoreData 0x10a9cac98 与 CoreDataV2 0x10a9cea14 的 getters。前者读包装 map，后者读锁保护 map，miss 获取/转换后有效值回填。0x10a9ddbf0 是求值上下文 constructor，0x10a9de610 才是递归布尔解释 body；局部读取不等于全部 typed operator 语义已逐条验证。前置查询 nil/失效返回 nil，但成功分支构造包装并写输出，不能写总返回nil。CoreData/CoreDataV2选择getter 0x1053df370 与 legacy解释函数末尾已补读：前者用初始化enum KEnableCoreDataV2 / dd.default.enable_core_data_v2 从服务取boxedBool，非本地写死；后者完整至下一prologue0x100068038，context构造与比较witness分别dispatch，不混为一次求值。

DD 最后指定三 helper 的用途也须分别记录：0x10a9e04cc 是 DecisionMaker.Prop 属性缓存/解析，0x10a9ef644 从已初始化时间重复模式 enum 集合按字符串匹配：Year/Month/Week/Day 的 codes为 y/m/e/d；它不是比较器registry，0x10a9e1f90 为 DDTimeStampComparator 执行入口。legacy JSON 解码 0x100044504→DDNodeOperationConfig，factory0x10005d35c 选择默认版本/时间戳/默认比较器；witness+0x10先通过class+0xd0建立context，随后另一witness+8经class+0xd8实际比较。不能把这些不同分工都写成网络参数原样透传，也不能从已选入口正证推出全部generic DD算子语义或实际配置值。legacy CoreData._nodes实际包装已由下列metadata补证接起；它曾是工具定位空洞，不是运行期才能生成。

legacy `_nodes` 最后构造链也已定位：CoreData 实际 initializer0x10004ade0 的 0x10004af08 读取负编码 Swift metadata cache0x120277c38，经0x100027650解析；0x10004af2c调用包装 init0x104f8d65c，0x10004af30存 CoreData+0x18。原始 symbolic references 分别绑定 RWLock 与 DDNode nominal，包装类型为 `RWLock<Dictionary<String,DDNode>>`。RWLock trailing vtable offset13/count10 中 getter第7项→0x104f8d6a4，对应metadata+0xa0；其读取路径为rdlock→value-witness复制字典→unlock，initializer复制初值并初始化pthread锁。因此 DDDecide→DDDataCenter→CoreData._nodes→字典lookup 不再剩未定位的虚调用来源；实际规则内容/下载结果仍需另证。这里不证明全部 CoreData 写者或所有 generic DD 算子语义穷尽。证据：root-static-fnval/neuron-v2-clear.md 最末原始metadata/切片。

DD 之前列出的命名算法叶子已进一步读取：legacy membership 0x10005dae8/0x10005de0c 按配置进行大小写处理、默认逗号分拆与可选 `~` 数值范围（含端点）；版本转换 0x1000604ac 按点分段，缺段补0，数值可解析时数值比较，否则String比较；时间模式 0x10005f9c8/0x10005fa24/0x10006024c 处理 Calendar/时间重编码与序列范围，双侧转换不成立仍可fallback整项转换，不能简化为总丢弃。0x10a9efbb4 初始化的集合实际是 `DDNodeOperationConfig.RepeatMode`：Year/Month/Week/Day，codes y/m/e/d；0x10a9ef644 是该模式匹配，不是比较器注册选择。Foundation Calendar/时区与实际规则内容仍为环境输入。证据 root-static-fnval/neuron-v2-clear.md 新算法小批，独立核对 dd-leaf-round2-delta.md。

兴趣引导 accepted 收尾进一步按 capture 追：success context 保留 weak-manager 与失败 finisher，实际 0x103c74508 在 accepted 分支 prepare 后跳至 0x103c74638，不执行拒绝分支的 finisher。Transaction.start 对 process 不传 completion/token；T17 的具体 dismiss witness 明确 completion=nil，实际两个类钩子为 bare RET，随后 serial token.end 与 launch transaction token 不同。此局部正证不能证明事务卡死或全局没有完成源；实际 MainVM delegate.scene/update 路径已追到 weak-self/模型应用门；MakeDismiss 已追到登录弹窗实验门与真实通知 producer。14 种指定 view 的实际 factory/witness 及五种 shared-sheet 的 nil completion 已核。这些路径未提供 accepted launch token 的完成调用；该完成源仍未定位。证据 root-static-exposure/final-feed-heartbeat-tail.md accepted-completion follow-up，独立 accepted-interest-round2-delta.md。

收藏文件夹的物理操作已从真实 UI 注册补起：BBPlayerFavoriteGroupWidget 的 table constructor0x104a6abd8 把 dataSource/delegate 设为同一 self；Done button constructor0x104a6ae3c 在0x104a6b014注册 self.doneBtnAction/event0x40。row tap 只切换 favoured，Done 以resourceType2进入同 FavoriteService 请求修改文件夹集合；实际 response callback 的成功门才 setIsFavorite。已定位 RAC isFavoriteSignal subscriber 更新所选视频模型并发 `BBListCollectionStateChangedNotification`。这条实际 UI→提交→成功状态链并不自动等于 Chronos `UpdateRelationshipChain` 发出链，二者关联仍未定位。证据 root-static-remaining/findings.md 本轮 physical favorite folder UI，独立 fav-physical-round2-delta.md。

请求属性 G 的原始写入已由新接口寻址补起：`commonParamsPlugin$1$invoke$2` 实际回调0x10a9aec60，将 requestBuilder+0x30 attrs、同一G键0x120c5e410及装箱后的KConfig布尔值传Attributes.put。配置名为 `kn.new.interceptor`，默认参数true，但实际服务返回值决定写入，不能把它写死。另 `kn.new.net.param` 写另一键。真实 callback TypeInfo/方法表和安装0x10a9b2144已核；实际root client DI声明路径由下列补证接起；运行期采用面与实际配置仍需另证。旧“只有consumer/无原始true来源”分类撤回。证据 root-static-session/source-recovery.md，独立 c-source-recovery-delta.md。

五种设备GPB实际保存后端是DeviceConfig二进制文件，Tools.syncMessage message.data非空才atomic写，长度0则removeItemAtPath；nil模型在syncModel快照路径直接跳过，不能说nil自动删文件。成功且generation一致的syncDiff回执清reqDict后保存cloud_diff；universal成功新建空Reply替换universalDiff后保存cloud_universal_diff，可在data为空时删除这两个diff文件。账号退出所读清理仍只重置universalBlocked，不能把上传成功清diff推广logout清全部五文件。证据同source-recovery.md及独立c-source-recovery-delta.md。

DD 属性求值实际来源进一步接起：DDContainer 构造 PropertyCenter 并经 backend+0x10/context+8 到原属性resolver。resolver 先mock，再按策略读本地cache，再从DataCenter/CoreData取得property node及provider/static值；不是每次网络取属性。hash287 对应配置构成的空/singleton/HashSet，`dd.default.observable.props`、`dd.default.focus.props` 按逗号切分；observable native回退集合为 mid/buvid，不是远端策略服务类型。hash3c80 的实际 NativePropNode/DDMidProp ctor、注册、getter已接起。native DDArgsProvider 默认十项属性读取版本/系统/设备/存储/电量/内存/时区/设备类型；av来自CFBundleVersion；mid从账户Long转字符串。它们是DD求值属性，不能全部当作推荐请求query字段，更不能推每次都上报。实际配置/规则何时选哪项仍另证。证据 root-static-fnval/neuron-v2-clear.md 新三小批，独立 recovery/b-native-delta.md。

G 写者的安装时机也已按真实metadata核：HookHandler 保存并转发实际RequestHook，RequestHook.install 在 client.requestPipeline 的 State phase 安装回调；具名CommonParamsPlugin factory/callback接线已闭。具体root客户端provider与注册包装适配已由后续补证接起；不能把这条路径推广每个client都会执行。证据 root-static-session/source-recovery.md G hook节，独立 recovery/c-hook-delta.md。

本轮来源定位更换了间接寻址方法：WL 从真实 Store constructor、MainReducer 捕获及七个 middleware 注册表读入业务 body，仍未定位账号通知发出者；modern batch 从非 text 指针、相对引用、tagged capture 与方法表追到数组转发，尚未定位元素构造来源。评论侧已读取继承生命周期注册、resource 动态 accessor/class_addMethod、GPB storage getter 与 Kotlin Follow/Thumb decoder；这些证明动态访问与模型构造机制，不能替代 `BFCCommentShouldRefreshList` observer、其余 cursor/seekRpid 业务消费者、辅助 RPC 业务发送者或好友列表消费者。`comment_global_string_219` 实际供 Toast；通知由独立固定 CFString 发出。以上属于明确定位空白，不能称全局不存在或天然仅运行期可判。证据 root-static-remaining/findings.md、root-static-social-rpc/f-group.md；独立 wl-localization-round2-delta.md、f-dynamic-round2-delta.md。

T17 确认通知的业务消费者也已接起：实际四字段 payload 经同名固定通知、MainVM 已安装 observer 及真实 IMP/capture，进入选择标记保存和当前刷新 operator（确认路径 raw4；另 dismiss 分支按原因门禁走 raw1）。MainVM 的独立 done descriptor 与 InterestManager launch token 不同，因此这些刷新正链不能替代 accepted launch 收尾源。14 个指定 view 的实际 factory/witness 及五个 shared-sheet hooks 已独立核对；marker-save 和 submit 的 regular RET 后仍有 swift_once/CocoaArrayWrapper 慢路，函数边界按下一 prologue 而非第一 RET 定义。证据 root-static-exposure/final-feed-heartbeat-tail.md 第三小批；独立 recovery/a-feed-final3-delta.md。

CommonParams 的具体 DI 来源已进一步定位：Dagger case39 调具名 provider constructor，ctor 接收组件 getter0x10b92fe30的返回对象（不是直接原root）；该 provider 以 id39 scoped 后存 root+0x2e8。case38 取它与另一插件组成有序两项集合，provider 存 root+0x2f8；真实两个 consumer 分别进入 internalCreateKtorHttpClient 与 Factory，所得 callable+0x10把集合传给0x10534605c。该 helper 对集合元素调用 hash587/slot8，且本身不是 HttpClient allocator。原 CommonParams factory 与587接口身份不同，实际注册包装适配已按下列正向receiver链补证；不能把集合流向的正证直接说成 live client 已安装。证据 root-static-session/source-recovery.md Concrete Dagger节；独立 recovery/c-di-delta.md。

CommonParams 注册包装的实际 receiver 已补齐：root+0x788/id11 经真实 DefaultGripperSettings factory 分配 DefaultGripper，+0x28存 DefaultProducerContainer；组件getter经1481/slot0取这个container。603 Builder build返回 StaticSuspendProducer，+0x38按cache byte+0x41条件保存 ContextProcessingProducer或其Cacheable包装，再接 WrappedProducer所捕获原provider。配置写+0x40与cache门+0x41分开，不能以前者true推后者true。587/slot8实际是async：先分配协程并返回包装，集合求值helper当下append该async返回包装，不是直接Plugin实例；后续协程适配→provider.get→原factory clone/invoke的声明链已定位。实际调度/await完成与live client采用面仍需运行证据，不能直接等同已安装。证据 source-recovery.md 注册包装节；独立 recovery/c-wrapper-delta.md。

cache+0x41=true 的已命名中介也补读：Builder将同Context存 FunctionWithSubscribers+8，再包 DefaultCacheableProducerNew。其调用 body0x10b8e0368–e0890 在需要求值的 record 分支读取同source，调用hash981/slot0；Context同981与405实际共用0x10b8dd1c0，因此接回已证原factory协程。已有完成记录则给continuation返回cache结果，另有订阅/await/error分支，不是每次无条件调用factory。两cache分支的有限receiver转发均接起，实际+0x41值和调度/完成不由静态声明链证明。证据 source-recovery.md Cache-enabled intermediary节；独立 recovery/c-cache-delta.md。
