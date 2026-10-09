# UGC 播放地址请求入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

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
**gRPC 全名（本轮闭合）**：`-[BAPIAppPlayurlV1PlayURL initWithHost:callOptions:]`（0x114facdcc）
在 0x114face2c–0x114face44 调
`+[BFCMossServiceWrapper createMossServiceWithHost:packageName:serviceName:callOptions:]`，
x3=CFString `bilibili.app.playurl.v1`（0x11d3961d0）、x4=CFString `PlayURL`（0x11d389c50）
→ Moss 包名 `bilibili.app.playurl.v1`、服务名 `PlayURL`；`+defaultService`（0x114facfc4）
用 host `grpc.biliapi.net`（0x11d0e5a70）isRest=0、`+defaultRestService`（0x114facfe8）
同 host isRest=1。五个方法都走
`+[BFCMossServiceWrapper handleRpcRequestWithRequest:responseClass:service:serviceName:handler:]`
（0x10509f20c，实现 0x10509f668→包注册工厂），其 serviceName 形参就是 RPC 方法名常量：
`PlayURL`（-playURLWithRequest:handler: 0x114fad00c，0x114fad064，reply=BAPIAppPlayurlV1PlayURLReply）、
`Project`（0x114fad110，0x114fad168，reply=BAPIAppPlayurlV1ProjectReply）、
`PlayView`（0x114fad214，0x114fad26c，reply=BAPIAppPlayurlV1PlayViewReply）、
`PlayConfEdit`（0x114fad318，0x114fad370）、`PlayConf`（0x114fad41c，0x114fad474）。
故 wire 上的 gRPC 方法是 `/bilibili.app.playurl.v1.PlayURL/<方法名>`；
"包名.服务名/方法名"的拼接发生在 Moss 工厂（0x10509f3d8 把 host/package/service 三个
NSString 桥接后交给 0x121073840 注册表里的实现），主程序内只剩这三个字符串常量。
共享 stub 判据下的真实调用点（`_objc_msgSend$<方法>` 的 BL 调用方，非 selref 零引用）：
playURL → 0x114a5b760 `+[BBResolverUGCHelper resolverWith:completeBlock:]`、0x114a589a0
`+[BBResolverPodcastHelper resolverWith:completeBlock:]`、0x11393e3d8/0x1139410d8/0x11394d6c8
（MALL 三个 helper）、0x114a67eec（UGCHelper resolverForPipUrl）与 0x114a7034c
（BAPIAppListenerV1Listener 转发）；project → 0x114a684b8（UGCHelper
resolverForUgcPlayUrlWithAid:cid:protocol:deviceType:qn:completeBlock:）、0x114a29254
（PGCHelper resolverForPgcCastPlayUrl…）、MALL cheese/ugc 与 PgcGateway/Cheese 转发；
playView → 0x114a5c180（UGCHelper resolverV2With:localResponseModel:completeBlock:）、
0x114a36740（Cheese）、0x114a127d8（PGC）与 0x114a2984c（PIP URL）、0x1139277d0/0x113941af4（MALL）；
playConf → `-[BBCDeviceConfig requestRemotePlayConfig]`（0x114faa458，即「PlayURL 旧操作配置」链）。
上传请求类已定（team-c11）：PlayConf edit 走
`[BAPIAppPlayurlV1PlayURL playConfEditWithRequest:handler:]`（stub 0x117481ee0，
调用点 0x114faa680，syncEditToRemote: 0x114faa5c4 内 semaphore 等待），请求体
SKVObject setPlayConfArray:（0x114faa11c）；Universal 走
`[BAPIAppDistributionDistribution setUserPreferenceWithRequest:handler:]`
（stub 0x117657fa0，调用点 0x114faa8a0）。

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
另有缺值转 NaN 分支，完整默认音轨与参数消费未逐项核对（下一步 `query_index.py '*audio*' 40` 后反汇编参数写入者）。

完整 UI→请求模型赋值、V2/统一接口实验选择、预加载复用、离线文件检查、成功响应
映射与播放器建立未完成（下一步反汇编该入口并回溯映射/建立点）；上述入口不代表所有 UGC、PGC、投屏和下载共用的全协议。

<a id="弹幕请求族与传输分支task-29-补"></a>

### 弹幕请求族与传输分支

弹幕请求的主程序内承载类是 `BFCDanmakuRequest`（team-c25 D1）。段请求
`+[BFCDanmakuRequest requestDanamkuListWithCID:AID:segmentIndex:tracker:completeHandler:errorHandler:]`
0x114fc04d8：先校验 CID ≥ 1（0x114fc0530 `cmp x24,#1; b.lt`）与 AID > 0（0x114fc0538 `cmp x23,#0; b.le`），
不合格且 errorHandler 非 nil 时直接回调（0x114fc05a8–0x114fc05b8）；
**传输二选一**由实验键决定：0x114fc0550 `[BFCMemexABTest hitExperimentalGroupForKey:@"grpc-danmaku"]`
（CFString 0x11d3987b0）命中 → 日志 `[BFCDanmaku] - [DanmakuRequest] request dm/list/seg brpc
avid/cid/segmentIndex`（0x11d3987d0，源文件
`srcs/common/BFCDanmaku/BFCDanmaku/Danmaku/BFCDanmakuRequest.m` 第 82 行）+ 调
`+requestDanamkuListByGRPC:AID:segmentIndex:completeHandler:errorHandler:` 0x114fc0640；未命中 →
`+requestDanamkuListByAPI:AID:segmentIndex:tracker:completeHandler:errorHandler:` 0x114fc0920
（HTTP `/x/v2/dm/list/seg.so`，成功/失败块 0x114fc0d30/0x114fc0f38）。gRPC 侧为
`-[BAPICommunityServiceDmV1DM dmSegMobileWithRequest:handler:]` 0x114fc788c（类方法 0x114fc7918），
Req/Reply descriptor `DmSegMobileReq` 0x114fc8e18 / `DmSegMobileReply` 0x114fc8e84
（同族 DmSegSDK 0x114fc8c68/0x114fc8cd4、DmSegOtt 0x114fc8d40/0x114fc8dac、DmSegCache 0x114fc8b28、
DmSegConfig 0x114fc9f98）；HTTP 侧另有完整 URL
`https://api.bilibili.com/x/v1/dm/list.so?oid=%lld`。同族其余请求（地址级）：
`requestUserHashCompleteHandler:errorHandler:` 0x114fc01dc、`postDanmakuWithAID:scene:danmakuMeta:platform:checkBoxType:reportParams:avatar:…`
0x114fc1024、`postDanmakuWithSendModel:…` 0x114fc1db0、`postCommandDanmakuWithAID:…:countDown:success:failure:`
0x114fc2fa4、`recallDanmakuWithMeta:…` 0x114fc3888、`deleteDanmakuWithMetaArray:…` 0x114fc3da4、
`+[BFCDanmakuRequest transPlatform:]` 0x114fc01bc；对应 HTTP 端点族
`/x/v2/dm/post`、`/x/v2/dm/post2`、`/x/v2/dm/command/post`、`/x/v2/dm/recall`、`/x/dm/assist/del`、
`/x/dm/user`、`/x/v2/dm/exposure`（字符串表）。残余：实验键 `grpc-danmaku` 的线上取值。
**「其他详情/UI 源」已闭合（task-30 更正 task-29 的阴性）**：8.89 **存在** View/ViewProgress，
只是类名是 `Viewunite`（用 `*DetailReq*`/`*ViewProgress*` 搜符号名会漏，方法名才叫 ViewProgress）：
`-[BAPIAppViewuniteV1View viewProgressWithRequest:handler:]` 0x114fb1944（类方法 0x114fb19d0）经
`BFCMossServiceWrapper handleRpcRequest…`，serviceName `ViewProgress`（0x114fb199c 是 `add x5,x5,#0xc50` 指令地址，CFString 对象在 **0x11d2fcc50**；team-c30 复核更正口径）、
responseClass `BAPIAppViewuniteV1ViewProgressReply`（classref 0x11f7be000+0xb90），service 由
`-[BAPIAppViewuniteV1View initWithHost:callOptions:]` 0x114fb14fc 建（package
`bilibili.app.viewunite.v1`、service `View`）⇒ 与方法名同族的 `/bilibili.app.viewunite.v1.View/ViewProgress`；
同服务族另有 viewWithRequest: 0x114fb173c、arcRefreshWithRequest: 0x114fb1840、
relatesFeedWithRequest: 0x114fb1a48、cacheAuthenticationWithRequest: 0x114fb1b4c、
storyWithRequest: 0x114fb1c50、floorAdSearchWithRequest: 0x114fb1d54、viewEndPageWithRequest:
0x114fb1e58。业务消费者（stub 0x11774d420 全部 6 处）：`-[BBPlayerChronosViewProgressService
requestUniteProgress:cid:upperId:…]` 0x11484f7d8 与 `requestV1Progress:cid:upperId:com…]` 0x11484fdf8
（播放器 chronos 服务，getter 0x10cc3b470）、`-[BFCDownloadBaseEntity
fetchCRONPackageDataWithAvid:cid:cronPackageEx…]` 0x115943684、`+[BAPIAppViewV1View
viewProgressWithRequest:handler:]` 0x1164493c0、`+[BAPIMallTab3ViewuniteV1View
viewProgressWithRequest:handler:]` 0x113557150（转发）。
请求字段（team-33，8.89 静态属性表）：`BAPIAppViewuniteV1ViewReq`（descriptor 0x114fb306c，
fieldCount 常量 w8=0x1c=28；属性表 0x11d4c0668）实测键 `bvid`/`spmid`/`sessionId`/`playCtrl`/
`playMode`/`extraContent`/`adExtra`/`danmakuID`/`removed`/`playerArgs`（BAPIAppArchiveMiddleware
V1PlayerArgs）/`relate`（BAPIAppViewuniteV1Relate）；`BAPIAppViewuniteV1ViewProgressReq`
（descriptor 0x114fb40c0，属性表 0x11f356f90）与 `BAPIAppViewV1ViewProgressReq`
（descriptor 0x11644f6e0，属性表 0x11f588c18）实测键 `aid`/`upMid`/`engineVersion`/
`messageProtocol`/`chronosParam`（BAPIAppViewuniteV1ChronosParam）/`fragmentParam`/`fromScene`/
`type`/`playCtrl`，V1 变体另有 `videoGuide`（BAPIAppViewV1VideoGuide）/`chronos`/`arcShot`。
UI 侧回包消费者：`-[STLandscapeSeekBarComponent didReceivedViewProgressResponse:error:]`
0x10426c8e0、`-[BBHD2MPPlayerVideoUpdate requestViewProgress]` 0x10cc391f8。
