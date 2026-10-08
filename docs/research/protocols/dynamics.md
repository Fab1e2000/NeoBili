# 动态综合页请求

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 动态综合页请求

Swift DFSumViewController.loadAllData(refreshType:) 内部 0x10136b274 创建普通 DynAllReq，
随后清 BBMFRefreshSingleton.isCoolBoot；selectedUpItemModel 存在时另创建
DynAllPersonalReq 并调用 dynAllPersonalWithRequest，普通分支在 0x10136b4ac 调用
Dynamic.dynAllWithRequest。因此不能用普通综合页的请求字段替代选中 UP 分支。
入口 loading 门控（isLoading，0x10136aad4）与分页结束保护（0x101361b6c）闭合于
下文小节；登录门控与 UI 刷新枚举属可静态查残余，下一步
`$PY disassemble.py 0x10136b274 0x10136b4e8` 逐支核对。

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
因此不能把五项都描述为每次按最新能力重算；该静态引用在本 body 内只见创建与字段
更新、无清空写点，其余替换写者属 Swift 静态变量间接派发，静态不可定，
下一步 `$PY query_index.py '*PlayurlParam*' 30` 列候选后逐个 find_callers。
playerArgs 则另读 VC getter；rcmdUpsParam.dislikeTs 没有独立保存方：键
`dt_user_dislike_timestamp`（cstring 0x11785db00）全 __text 引用仅
0x101372024/0x101372160/0x1013722b8 三处且全部位于该 getter 体内（team-d6 本轮
ADRP+ADD 全量扫描），样本内无任何正值写入方。adParam.adExtra 由调用 getter 提供，nil 转空。localTime
取当前本地时区在 Date.now 的偏移秒数，整数除以 3600 向零截断（172,801 个假偏移
算术等价核对通过），不是分钟偏移。coldStart 取 singleton.isCoolBoot 的 1/0；
由于父调用在 builder 之后才清该状态，不能把首请求一律写为 0。

tabRecallExtra/bubbleRecallExtra nil 退空；sessionId 取 VC 的同名状态，其专用生成规则见下节。reqSortOption.sortType 取 0x10135a1d8 的设置 getter，
isColdRefresh 取 VC.isAllFirstReq。该 builder 未见显式赋 assistBaseline/from，
不能凭描述符补常量。排序设置与首次状态重置闭合于下节（0x10135a1d8/0x101360308）；
offset/baseline 响应更新与缓存持久化闭合于「综合页刷新与专用 sessionId」「综合页
响应状态与两种缓存」（0x10136c130/0x10136c9d4/0x101362e98）；卡片拼装与同版本包/
服务端执行属真机运行行为，静态不可定，仅 9.13 抓包可验。

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
是两个对象；静态样本内未检出该 PlayerArgs 缓存的失效/清空写点，其失效只能发生在
运行期（登录切换或显式 reset），静态不可定；下一步
`$PY query_index.py '*PlayerArgs*' 30` 列候选类型后对每个 setter find_callers。

综合页 rcmdUps 取值 helper（0x101371fdc）读取 standardUserDefaults 的
`dt_user_dislike_uid`。能转换为 NSNumber 时才与 currentUser.mid 比较；当前用户不存在
或 mid 不同，则把 `dt_user_dislike_timestamp` 写为 NSNumber(0)，并返回 0
（0x1013722ac–0x101372320）。uid 缺失或转换失败时却直接继续读取 timestamp，
并非一律返回 0；timestamp 能转换为 NSNumber 则取 longLongValue，否则退 0。
该 getter 有清理副作用；正值写入入口经全 __text 扫描证伪（键 0x11785db00 仅
0x101372160/0x1013722b8 两处 getter 内引用，team-d6 本轮扫描），时间单位为秒
（与本节 localTime 同为秒级算术，样本内无第二佐证源），不感兴趣 UI 是 H5/运行期
通道，静态不可定、仅 9.13 抓包可验。

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
重置段；触发控件对正在刷新状态的抑制由 bfc 下拉控件内部状态决定，属控件运行期
行为，静态不可定，已有 isLoading 门控（0x10136aad4）兜底。sortType=nil 的按钮路径没有
经过这里的缓存/事件/刷新正常分支，不能只凭点击就断言一定产生网络请求。

### 综合页刷新与专用 sessionId

loadAllData 的实际 body（0x10136aad4）先检查 isLoading，已有加载立即返回。
refreshType 原始值为 0 时设置 page=1、清 synthesizeHDHelper.offset、生成新的
VC.sessionId，并把它合入 trackExtra/pvExtras；非零值跳过该重置段，复用已有会话。
随后置 isLoading=true/isFeedRenderEnd=false 并进入请求。apiOffset 与 helper.offset
是不同属性，不能因这个清空动作断言请求字段 offset 也已清空；loadNextPage 路径的 offset 写回闭合于选中 UP 回调段
（0x101366564），其余分页入口下一步 `$PY find_callers.py 0x10136a9b0`
穷举后逐个反汇编。

sessionId helper（0x10136180c）明确生成：
`dynfeed_` + 跟踪 BUVID + `_` + Int64(FRINTA(DateUnix×1000)).decimal + `_` +
UUID().uuidString。浮点转整数有有限值/范围保护，FRINTA 是最近整数、半值远离零。
该字符串没有 MD5/FNV/大小写转换，并且带新 UUID，不能与公共 Session_ID、播放器
session 或 login_session_id 合并为同一个字段。上述刷新原始值 0 是已证消费分支，
已闭合下拉 UI：viewDidLoad 中 0x101368f3c 将 block 0x101371c1c 绑定
bfc_addPullToRefreshWithActionHandler，block→0x101369b1c 在综合页传原始值 0。
同一 viewDidLoad 尾部 0x101368fb4 明确置 singleton.isCoolBoot=true，因此此状态
并非已证仅在进程冷启动设置；VC 重建是否发生需另有生命周期证据。其他下拉入口需对
bfc_triggerPullToRefresh 做共享 stub 调用点扫描（selref 槽零引用≠无调用，需阳性对照），
下一步 `$PY query_index.py '*triggerPullToRefresh*' 30` 取 stub 后 find_callers。

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
长度进入同一个自动补页 helper（0x1013666e4）。选中项变化时该 closure（0x101366220
已读 body）没有取消或回执抑制比较；并发下旧回执是否更新新选中项属运行期竞态，
静态不可定，需真机断点验证；下一步 `$PY disassemble.py 0x101366220 0x1013665a0`
核对该 closure 已读范围外的尾段指令。

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
SwitchSortOption；对象缺失或其他 tab 返回 false。其余补页调用点需共享 stub 全量
扫描，下一步 `$PY find_callers.py 0x101361b6c` 穷举；SwitchSortOption 的写入链
闭合于上文排序按钮段（0x101360308 保存/替换、缓存 helper 0x10135a1d8）。

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
自动补页 helper（0x101358fe4）。nil/空 dynamicList 的特殊路径未在本回调
（0x1013589e4）已读段落出现，属可静态查残余，下一步
`$PY disassemble.py 0x1013589e4 0x101358d00` 逐支核对；综合页 fallback JSON 缓存
不经视频 tab，两者缓存结构不同已证。

另一个 Objective-C 视频页 BBDFVideoListViewController 使用 DFVideoCacheHelper，
不能与上面的 DFSumViewController.video 分支合并。其 loadAllVideo 回调
0x10e824b30 在 error=nil/request.refreshType=0 时调用 writeVideoCacheWithResponse，
helper 0x1014af924 仅 toJsonString 非 nil 才发 fallback writeAsync，scene 的 inline
字符串为 `dt.video-dt.0.0`，id 为当前 mid 十进制（无用户0），version 从 bundle
构建信息生成，expirationTime=0。version 由 0x1014af924 从 CFBundleVersion 字符串
生成已证；expirationTime=0 的时效语义由服务端解释，静态样本不可定，仅 9.13 抓包
比对同 scene 缓存命中行为可验。
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
隔离与列表恢复的磁盘层在 Kotlin/Native 区（provider IMP 0x10bf25968），ObjC/Swift
侧静态不可穿透；下一步 `$PY disassemble.py 0x10bf25968 0x10bf25c00` 起逐函数核对
或真机读沙盒目录，静态侧不将发起写入视为磁盘持久化成功。

fallbackCache getter（0x101367a38）懒读取并缓存
KntrFallbackCacheModuleKt.provideFallbackCache 的产物，不能仅凭类名确定磁盘实现。
该惰性来源已部分闭合：getter 在 ivar 槽 0x120316c88（`$__lazy_storage_$_fallbackCache`）
缓存产物，0x101367a64 classref 0x11ffd1c28 经 selref 0x11f78b108 发 msgSend（该槽位确有
0x101367a74 调用点），provider IMP 位于 Kotlin/Native 区 0x10bf25968。磁盘实现与目录仍未
闭合：`fallback_cache` 类路径字符串 0 命中（对照 `%FallbackCache%` 22 命中），不能仅凭
fallback_cache_swift_bridge（FallbackCacheOCBridge write 0x102125c10/read 0x102126cb4）
存在就断定 provideFallbackCache 的产物就是该桥。
readDynAllCache（0x101363778）使用同样 scene/id/version 调 readAsync。已确认直接
调用在 VC.viewDidLoad 的 body 0x101368cd4：dataSource 为空且 dataTypeName==`all`
时置 page=1 并读取，再进入后续 UI 初始化，不是已证的网络错误自动回退。

读取回调 0x101363d94 的 error 分支调用旧缓存读取 0x101364210；非
KntrCacheResultSuccess 或 Success.data=nil 也走旧缓存。Success.data 非 nil 时
parseJsonString:error: 为 DynAllReply，模型非 nil 即交 completion；模型 nil 则走
parse error 分支，未在这个分支尝试旧缓存。旧缓存按 VC.pvEventId 经
BBDFCacheHelper.cacheKeyWithFlag/objectForKey 读取 NSData，再 parseFromData。
恢复后列表状态、旧缓存键/有效期与后端的 expirationTime=0 语义仍需继续核对。

<a id="动态响应描述符辅助请求族与缓存过期回执task-14-补"></a>

### 动态响应描述符、辅助请求族与缓存过期回执

响应侧描述符（GPB fields 数组，0x20 字节/项：name/number/offset/flags/typeEnum）已解析：
DynAllReply（descriptor 0x116213364，fields 0x120856700）顶层 7 项 message：
1 dynamicList、2 upList、3 topicList、4 unfollow、5 regionRcmd、6 config、7 sortConfig，
即综合页响应除 dynamicList 外还有关注 UP 列表、话题、取关提示、分区推荐、配置与排序配置
六个顶层字段，不能把回复模型压缩成"只有 dynamicList"。分页游标在 DynamicList
（0x116213514，fields 0x1208568e0）内：1 listArray(repeated)、2 updateNum、3 historyOffset、
4 updateBaseline、5 hasMore；CardVideoDynList（0x116213148，fields 0x120856360）与其同构。
DynVideoReply（0x1162130dc，fields 0x1208562e0）：1 dynamicList、2 videoUpList、
3 videoFollowList、4 sortConfig。选中 UP 的 DynAllPersonalReply（0x1162140c8，fields
0x120857c00）与 DynVideoPersonalReply（0x116213908，fields 0x1208570a0）均为 8 项：
1 listArray、2 offset、3 hasMore、4 readOffset、5 relation、6 additionUp、7 title、
8 titleSub；选中 UP 回调只消费 offset/hasMore（0x101366564），readOffset/relation/
additionUp/title/titleSub 未在该回调消费。

辅助请求族入口（均为 +[BAPIAppDynamicV2Dynamic 类方法]）：
`dynVideoUpdOffsetWithRequest:handler:`（0x11620d05c）——DynVideoUpdOffsetReq descriptor
0x116213974，fields 0x1208571a0：1 hostUid、2 readOffset、3 footprint、4 personalExtra；
业务调用点为 `-[BBTLUPerUpdateItemVC updateReadOffset:]` 经 __objc_stubs 0x10f84a3f8
（0x10e8a92f4），是 UP 主页动态已读 offset 上报。`dynDetailsWithRequest:handler:`
（0x11620ce54）——DynDetailsReq descriptor 0x1162137c4，fields 0x120856e80：
1 dynamicIds、2 playurlParam、3 localTime、4 playerArgs、5 config；调用点
`-[BBDFCardSectionController loadFoldData:]` 经 stub 0x10f84a374（0x10e8021b8），
即综合页折叠卡片补取。`dynAdditionCommonFollowWithRequest:handler:`（0x11620d160）——
Req fields 0x1208578c0：1 status(enum)、2 dynId、3 cardType，Reply（fields 0x120857920）
仅 1 status；`dynThumbWithRequest:handler:`（0x11620d264）——DynThumbReq fields
0x120857940：1 uid、2 dynId、3 dynType、4 rid、5 type(enum)。静态调用点已收口
（task-13 补）：两 selector 的共享 stub（0x1172d8940/0x1172d9040）除各自 +方法 IMP
内尾调（0x11620d1b0/0x11620d2b4）外零业务调用点；直接派发核查——selref
0x11f6610f8（follow）find_data_refs_root 3 命中（0x1056d8080/0x1056d8a70/0x1056d8c20）
经反汇编全部为 Kotlin/Native 原子计数同页 ADRP 假阳性（`add #0xf8` 后接 ldaxr/stlxr，
真 selref 加载是同函数 0xcc0 偏移的 `edges`）；selref 0x11f6612b8（thumb）0 命中。
阳性对照：dynAllWithRequest:handler: 的真实业务派发形态是 selref 加载+`bl _objc_msgSend`
（0x10136b49c，selrefs dynAllWithRequest:handler:），该形态在两条 selref 扫描中均无命中，
故样本内这两个 RPC 无业务生产者，入口仅作为已生成 RPC 存在；动态重绑定/下发驱动不可静态排除。动态发布入口族为
BBMFPublishCreateDynamicRequestWarpper（warpWithModel 0x10e9769d8、constructMeta
0x10e97711c、constructTextContent 0x10e977824、constructRepostWithScene: 0x10e9775dc），
provider `DynamicPublishModule dynamicPublisher` 0x100200cb0 /
`DynamicPublishImp publishToDynamicContent:` 0x102bfcde8，完成后
`MainViewController reloadContentAfterDynamicPublish` 0x1012a6b7c。

<a id="动态发布-endpoint-与字段表task-26-闭合"></a>

### 动态发布 endpoint 与字段表

发布 endpoint 为 gRPC/Moss：service `bilibili.main.dynamic.feed.v1` + serviceName `Feed`
（CFString 0x11d29ab70/0x11d29ab90，见 `-[BAPIDynamicInterfaceFeedV1Feed
initWithHost:callOptions:]` 0x11463ac30 段 0x11463ac94/0x11463ac9c），host
`grpc.biliapi.net`（0x11463ae38）。方法 `bilibili.main.dynamic.feed.v1.Feed/CreateDyn`：
`+[BAPIDynamicInterfaceFeedV1Feed createDynWithRequest:handler:]` 0x11463b104 →实例
0x11463b078，0x11463b0e0 经 `BFCMossServiceWrapper
handleRpcRequestWithRequest:responseClass:service:serviceName:handler:`（'CreateDyn'
CFString 0x11d360bf0 @0x11463b0d0），responseClass `BAPIDynamicCommonCreateResp`
（classref @0x11463b0a0）。业务链：`BBMFPublishInfoViewModel dispatchPublishInfo:`
0x10e943094 →(BL 0x10e943744→stub 0x10f8962dc)→ warpWithModel 0x10e9769d8 →
`constructCreateModelWithType:` 0x10e976a30（0x10e976a68 classref 0x11f7cf590 建
`BAPIDynamicInterfaceFeedV1CreateDynReq`）→ construct* 族（constructMeta 0x10e97711c 写
dynType/from/fromSpmid/dynId/revsId/rid(rid+rId 双读)/repostMode/appMeta/loc+lat+lng——
后者走 CLLocationManager getCachedLocation: 前置 hasLocationAuthorization 0x10e9775b4；
constructRepostWithScene: 0x10e9775dc、constructTextContent 0x10e977824、
constructContentArrWithHighLight:andEmoji: 0x10e977b28、constructSketch 0x10e9788e4、
constructProgram 0x10e978b0c、constructCard 0x10e978d2c、constructTag 0x10e97965c、
constructOptionWithScene: 0x10e979b00、constructTopic 0x10e97a0ac）。CreateDynReq 完整
字段表（GPB fields 数组 0x1207c5078，inspect_data 实读）：1 meta 2 content 3 scene
4 picsArray(repeated) 5 repostSrc 6 video(BAPIDynamicCommonCreateDynVideo，descriptor
0x114642bcc) 7 sketchType(int64) 8 sketch 9 program 10 dynTag 11 attachCard 12 option
13 topic 14 uploadId 15 extraInfo 16 draft。descriptor0x11463f814的w6=0x10；
原inspect_data默认只显示12行不能当完整schema，已更正（root-static-social-rpc/create-schema.txt）。
`DynamicPublishImp publishToDynamicContent:` 0x102bfcde8 体内无 endpoint 常量——它是
Gripper KntrIDynamicPublish 桥（0x102bfd7d4），endpoint 由上述 BAPI service 类承载，
provider 不承载 URL。除编辑器主链外，CreateDynReq 还有两条静态生产者（分享/静默链）：
`+[BBEduGuideDynamicApi shareDynamic:]_block` 0x10f5564d0（classref 0x10f556518，
0x10f556664 BL createDyn stub 0x11728dca0，RACSignal createSignal+deliverOnMainThread）与
`+[BBMallShareHelper silentPostBiliDynamic:trackChannel:]` 0x113859c88（classref
0x113859cb4，0x113859e34 BL 同 stub，'SilentPostBiliDynamic success'）。以上为 8.89 静态
证据；CreateDyn 的 wire 级字段顺序仍建议 9.13 抓包对照。

缓存过期回执：KntrCacheResult 为封闭类，子类齐全——Success 0x11d99aa80、Miss
0x11d99a9f0、Expired 0x11d99a960、VersionMismatch 0x11d99ab10、Corrupted 0x11d99a8d0。
过期是独立回执类型而非静默 miss；Swift 读回调 0x101363d94 只判 Success，故
Expired/VersionMismatch/Corrupted 一律落入旧缓存 0x101364210 路径。FallbackCache真实export selector表→adapter10bf16a58→1089bf32c已闭，不再把SelectorsHolder placeholder10bf25968当实现。实际声明producer：keyFallbackCache→NamedBean root+458/id139→ProviderAsProducer→DoubleCheck root+450/id140→FallbackCacheImpl1089bef90，Kotlin interface table/jump表和接收字段已核（root-static-social-rpc/f-group.md）。generic Gripper map安装/覆盖正在定向补，声明链不是现场live instance或实际diskcontents；新版本/磁盘结果仍需单独证据。
