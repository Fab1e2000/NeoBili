# 评论列表 RPC、发布与互动

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

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
交failure，局部未见重发。code/message 具体映射闭合于本节 errorMessage/errorCode
（0x113f1e3c8/0x113f1e4f0，bapi_status 与 io.grpc domain 分支已读）；Moss 公共
自动重试属运输层运行期行为，静态不可定。

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
分页wire字段（GPB表32B/项解码）：请求`BAPIPaginationPagination`（descriptor
0x116450f8c，fields 0x120880020）仅1:pageSize、2:next两字段，客户端nextOffset或
prevOffset序列化时都进单个`next`字符串，没有独立pn/ps；回执`BAPIPaginationPaginationReply`
（0x116450ff8，fields 0x120880078）仅1:next、2:prev，updatePagination按此写回两offset。
对照组`BAPIPaginationFeedPagination`（0x116451064，fields 0x1208800b8：pageSize/
offset/isRefresh）与`FeedPaginationReply`（0x1164510d0，fields 0x120880118：
nextOffset/prevOffset/lastReadOffset）不属于评论链；评论链无lastReadOffset。
子回复DetailListReq的builder 0x113f1c60c反汇编复核只赋oid/type/root/rpid/mode/
pagination/scene/needSubjectTitle/extra/adExtra，cursor字段不赋；BAPIMainCommunityReplyV1Reply
服务面（0x114178e14–0x1141793b4）只有mainList/detailList/dialogList/previewList/
searchItem*方法，二进制内未见REST `x/v2/reply/reply` 子回复路径。广播插入链
（0x113f56080→0x113f5650c→ReplyInfoReq）不读不写BFCCommentPagination的next/prev，
也不更新sessionId，去重靠rpid与current/preInsertCard比较加waitingRequest/shouldInsert
门，插入条目不参与后续nextOffset分页计算。
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
loadFoldPage 的 UI 触发者属可静态查残余，下一步 `$PY find_callers.py 0x113f78a8c`
列直接调用者后逐个反汇编。

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
详情next/prev/fold 复用主列表同构 builder（requestDetail 0x113f1c60c 的
pagination 字段已列），排序选择复用 switchSortMode 链 0x113f44370；跳转 UI 绑定
属可静态查残余，下一步 `$PY query_index.py '*DetailVM*' 40` 逐方法反汇编。

### 排序操作到重新请求

ListContainer.switchSortMode（0x113f44370）转currentVC.switchSortMode。
ListVC实现（0x113f4f574）只处理VM.showType=1且当前sortMode非1；当前2改3，
其他非1值改2。它先写VM.sortModel，再在table可下拉且disablePullRefresh=false时
triggerRefresh(true)，其他分支直接refresh，进入前述tryLoadData/List RPC；
不是只本地重排。随后setOrdering读readableString（0x113f193cc）：mode2=time，
mode3=heat，其余空。业务埋点reportClickMore中的state由旧mode3产生2、其他产生1，
不能把该埋点state当成新RPC.mode。showType/mode1阻断以及刷新已有loading门槛
仍然适用；按钮/可访问性入口属可静态查残余，下一步
`$PY find_callers.py 0x113f4f574` 穷举 switchSortMode 调用者；详情 sortModel 来自
响应 mode 重建（0x113f695f8），复用同一排序链。

### 广播插入与单条评论补取

ListVC.didReceiveNotice（0x113f56080）对ReplySubjectReplyInsertionResp先比较
消息oid与当前oid.longLongValue；不同退出。ignoreInsertCard(rank)为true或
config.sourceType==2也退出。随后枚举supportModeArray与当前sortMode比较，
只有支持该模式才getPreInsertModel、保存insertTagModel，并调insertNewCommentV2。
同入口对ReplySubjectInteractionResp同oid则调用likeUpdateHelper.start/decelerate/
didReceiveMessage，不走单条补取。广播订阅与消息解码闭合于下节（注册 0x114025b80、
joinRoom 0x114025cf4、resolveCommentMessage 0x11402613c）；传输层握手与鉴权
metadata 属公共 Moss 层运行期行为，静态样本不携带握手凭据，属不可静态判定性质。

insertNewCommentV2（0x113f5650c）检查waitingRequest、tag.shouldInsert及rpid与
current/preInsertCard的重复；通过后计算插入位置、置waitingRequest=true，再调
ListVM.loadNewCommentV2→_getNewComment（0x113f7e880）。非nil tag才发
MossAPI.requestCommentWithRpid（0x113f1d434），构造ReplyInfoReq赋rpid及
bizScene=1，交Reply.ReplyInfo。descriptor（0x11417dce8，表0x1207b7350）
三项为1:rpid/int64、2:scene/enum、3:bizScene/enum；该builder未赋scene。
nil tag分支只记录日志，本体未调用completion，不概括为false回调。

补取成功callback（0x113f7e9cc）在model为nil、blocked或已在indexFilter时
complete(false)；其余先addItemToIndexFilter、setTagModel、applyToListRootComment、
enableFold=true、预计算高度，保存preInsertCard后complete(true)。此处只保存模型，
插入动作在 VC callback 0x113f56810 中执行。
失败callback（0x113f7ebe0）记录并complete(false)，没有业务重试。
VC callback（0x113f56810）先清waitingRequest，仅success非零继续；当当前tag.rpid
匹配preInsertCard或currentInsertCard时清insertTagModel，随后调用
insertNewComment(preInsertCard)。不匹配时保留tag但仍进入该插入调用，不能写成
“响应与最新tag不一致就丢弃”。实际索引计算与替换规则闭合于下文 insertNewComment
0x113f5716c（按 tag 重算 indexPath，nil 仅记日志并清 waitingInsert，有效时
insertObject+insertRows）；此链不证明键盘
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
scm_action_id，不直接复用先前 BFCApiOptions。此局部没有次数上限或延迟回退。
captcha service 侧限制已核：onVoucherWithTag:voucherInfo:completionBlock:
（0x114583440）生成 `OnVoucher-%@` 事件名与 `BFCRiskControl-<UUIDString>` uuid，
track type=1/result=1 后调 showCaptcha（VC 传 nil、useCustomAlert=1）。
showCaptchaWithCaptchaInfo:uuid:tag:viewController:useCustomAlert:completionBlock:
（0x114584374）先 saveCallBackInfoWithTag:uuid:block:（0x114584538）再查
commonCaptchaIsShowing：已在展示时只 track type=2/result=1 并 return，新回调已入
callBackInfos，由当前展示中的验证码完成时 callBackAllBlocksWithSuccess:token:error:
（0x1145849fc）统一派发（排队而非丢弃）。成功派发条件为 success 且 token 非空才
setToken: 并回调，随后 isShowing=false；token 存 commonCaptchaResultToken，过期时间
= now + tokenEffectiveTimeInterval（0x1145849d0），tokenIsExpired（0x1145847d0）
为 now>=expireTime 比较。service 内部没有重试次数上限或退避字段，客户端此链路的
限制仅单实例展示互斥、token 有效期与每次重新生成的 UUID。
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
列表插入闭合于下文：ListVC postSuccessBlock 0x113f541f4→_addNewCommentWithModel
0x113f550fc→addPostedComment 0x113f795b8（success_action==1 时跳过插入）。

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
callback 0x104803968 向其 weak delegate 发 lpDidClickPublish（0x1048039c4）；
物理 button→此 callback 的 Swift UI 接线属 Swift 合并代码间接派发，selref 扫描
不可用；下一步 `$PY find_callers.py 0x104803968` 核对直接调用者再回溯注册点。

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
另发MainList/ReplyInfo。这是成功响应后的局部插入链；子评论分支 addPostedSubComment
未在本节展开，属可静态查残余，下一步 `$PY query_index.py '*addPostedSubComment*' 30`
定位后反汇编；多请求并发去重属运行期竞态，静态不可定。

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
已激活的键盘。后端注入对象即上述DraftServiceImpl唯一构造根（见前文0x100e2b04c链）；
读取触发已闭合到ListVC lazy sendMessageView的恢复callback，删除范围见下文clearDiskDraft。

ServiceLocator保存桥（0x1047e5bd8）要求输入能cast为DiskDraftData，否则不保存；
把oid十进制字符串放入仅含oid键的字典，调用该数据的协议setter，再以上述key调
DraftService witness+0x20；读取桥0x1047e53f4用同key调用+0x28。
静态协议表只找到DraftServiceImpl一个conformance（0x118295854，
witness0x11b10ce28），其保存/读取分别转0x100e31850/0x100e32028。
组件构造根已闭合：find_callers对type_metadata_accessor_for_DraftServiceImpl
（0x100e33608）全二进制仅1个调用点0x100e2b0b8，位于惰性初始化体0x100e2b04c——
swift_beginAccess(provider+0x10，对应`$__lazy_storage_$_instance` 0x1182951d8)后
0x100e2b08c经0x100e2b724查缓存，未命中才swift_allocObject(0xd8,7)并按调试常量
`EPDataModule/DraftServiceImpl.swift`（行35）与
`srcs/.../DataIO/DraftServiceImpl.swift`（行96）执行init。链条：
0x100e2b894（thunk）→0x100e2b304用metadata accessor 0x100e2b6b4构造
_$GripperDraftServiceProviderDependencyProvider（allocObject 0x40，weak component存+0x30）
→witness形态thunk 0x100e2b238（无BL调用者，仅0x202eb9a8/0x21b4bac0数据槽引用）→
0x100e2b04c。同区DraftFilter/DataTransfer两个provider的0x100e2b258/0x100e2b2b4同构对照成立。
因此"唯一conformance + 唯一构造点"成立；`$PY find_pointer_refs.py 0x1182951d8`
已执行，结果为空——`$__lazy_storage_$_instance` 槽全二进制零静态指针引用，唯一
访问路径仍是 0x100e2b04c 惰性初始化体（同区 DraftFilter/DataTransfer provider
0x100e2b258/0x100e2b2b4 为同构阳性对照）。provider 实例注册进
ServiceLocator/Inject 容器发生在 DI 运行期（间接派发、无静态引用），静态不可定；
下一步真机 LLDB 断点 0x100e2b04c 观察注册顺序。

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
不能把HTTP成功概括为删评、拉黑都成功；其通知名来源与消费侧见置顶节（BFCCommentShouldRefreshList
全静态引用均为post、零观察者）；deleted/blocked 两 bool 的上层处理取决于
deleteAndDefriend（方法本体 0x113f848b4；0x113f846a0 只是其体内调用点）completion 的调用方，属可静态查残余，下一步
`$PY find_callers.py 0x113f848b4` 逐 caller 反汇编 completion 块。

### 评论置顶与取消

SetTopApi.makePars（0x113f25fd8）构造oid/type/rpid/action/spmid/from_spmid/track_id/
container_uuid；数字转十进制，字符串直接字典赋值、nil省略，不在此加入scene/ordering。
request0x113f26208向https://api.bilibili.com/x/v2/reply/top发method2（POST加URL query），
映射根对象，mutableCopy参数覆盖当前scm_action_id再发送；未见业务重试。
Manager.bringReplyToTop0x113f83870传action1，cancelTopReply0x113f83ba8传0，
均取模型oid/rpid、sheetParam的type/页面追踪项。clickTopAction0x113f84dcc依isTopped
选择取消/置顶，再由完成closure接外部handler；此入口没有确认对话的证据。
成功0x113f83a38先toast、发BFCCommentShouldRefreshList通知，再调用可选completion；
通知消费侧仍有界未定位；不能称“零观察者”：该通知名CFString常量0x11d340470的
find_data_refs_root恰4处且全部是`postNotificationName:object:`（置顶成功0x113f83ab0、
cancelTopReply block_2 0x113f83df4、删除成功0x113f84188、删评拉黑成功0x113f84cc8），
另一 selector `comment_global_string_219`（stub 0x117269100）的 find_callers 仅
0x113f84140/0x113f84c7c两点，但这两处并非通知名获取路径：其返回值经
0x113f8414c / 0x113f84ca8 进入 `showCenterToast:`（0x113f84158），是提示文案；
通知名由 0x113f84188 / 0x113f84cc8 处直接加载的 CFString 传入 post。阳性对照
BFCPaymentManagerLoginStatusDidChangedNotification的CFString 0x11d366f70同法命中
0x1146e9810的`addObserver:selector:name:object:`，证明方法能发现观察者；故不能声称
任何评论VC已静态注册响应该通知刷新，运行期动态拼名注册无法静态排除。

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

<a id="评论失败恢复与分享链task-29-补"></a>

### 评论失败恢复与分享链

写操作的失败分支逐对读出（team-c25 C1，证据 DerivedData/Validation/team-c25/findings.md）：
`bringReplyToTop:sheetParamModel:completeHandel:` 0x113f83870 的成功块 0x113f83a38 在
`[BFCToast showCenterToast:[CommentRes comment_global_string_74]]`（0x113f83a6c/0x113f83a84）后
`postNotificationName:BFCCommentShouldRefreshList object:nil`（0x113f83ab4）；失败块 0x113f83af4 读
`[error userInfo][NSLocalizedDescriptionKey]`（槽 0x11b091048，0x113f83b1c）→ `length` 非 0 时用该串，
否则回退 `comment_global_string_424`（0x113f83b60），只调 `showCenterToast:`（0x113f83b90）后返回——
**不回滚、不重试、不 post 刷新**。`cancelTopReply:` 0x113f83ba8（成功 0x113f83d70 / 失败 0x113f83e2c）、
`deleteReply:type:spmid:fromSpmid:` 0x113f83ee0（成功 0x113f8410c 用 `comment_global_string_219` 显示Toast，再独立加载固定通知名并post
0x113f84188 / 失败 0x113f841c8 用 `comment_global_string_369`）、`deleteAndDefriend:…` 0x113f848b4
（成功 0x113f84b80 / 失败 0x113f84d18）、`clickDeleteAction:isMainReply:type:spmid:fromSpmid:`
0x113f84efc（成功 0x113f851fc / 失败 0x113f85238）同构。即**只有成功分支才 post 刷新通知**
（所选literal扫描只找到post，不能证明全局无消费者）；所选失败handler只toast、不post该刷新，不能推出全部列表只能靠页面重拉（局部静态证据，
最终状态需真机断网验证）。发布侧验证码续提交维持既有 CMT-02 结论。

评论分享链（team-c25 C2）：入口 `+[BFCCommentShareService shareWithRpid:oid:type:needTranslate:spmid:fromSpmid:imageWidth:]`
0x114039524（完成 0x114039660 / 失败 0x1140396dc）→ `createShareImageWithRpid:…:withBottomComponent:succeed:failed:`
0x1140396e8 → `_createShareImageWithRpid:…` 0x114039834 → `_fetchDataForShareModel:fetchDataSucceed:fetchDataFailed:`
0x114039ca8 → `_preloadMaterialsForShareModel:preloadMaterialsSucceed:preloadMaterialsFailed:` 0x11403b04c
（blocks 0x11403b63c/0x11403b670）→ `_createImageForShareModel:createImageSucceed:createImageFailed:`
0x11403b854 → `_launchShareComponentWithModel:image:` 0x11403bd98。**回执 RPC**：
`-[BAPIMainCommunityReplyV1Reply shareReplyMaterialWithRequest:handler:]` 0x114179a44（类方法 0x114179ad0）
经 `+[BFCMossServiceWrapper handleRpcRequestWithRequest:responseClass:service:serviceName:handler:]`
（0x114179aac），serviceName CFString `ShareReplyMaterial`（0x11d348110）、responseClass
`BAPIMainCommunityReplyV1ShareReplyMaterialResp`（classref 槽 0x11f7e9208），service 同
`BAPIMainCommunityReplyV1Reply`（`defaultService` 0x114178dcc）
⇒ `/bilibili.main.community.reply.v1.Reply/ShareReplyMaterial`；Req descriptor 0x11417e4dc
（fieldCount=4、storageSize=32、fields 0x1207b7a50），回执子模型 ArchiveMaterial 0x11417e5c8 /
DynamicMaterial 0x11417e648 / ArticleMaterial 0x11417e6c8 / SubjectMaterial 0x11417e748 / ExtraData
0x11417e7e0（另 ShareReplyInfo 0x11417e244、ShareReplyTopic 0x11417e2c4）。本地渲染/解析：
`_parseContentTopFromCommentModel:hasParentReply:` 0x11403cc54、`_parseBackgroundLayoutFromResp:maxWidth:`
0x11403ca30、`_createQRCodeWithContent:size:` 0x11403d320、`_filterComponentsForShareModel:` 0x11403bd34、
`_matchAvaterRightBottomBadge:` 0x11403d030。**Req 4 字段已读出（task-30）**：
`$PY inspect_data.py 0x1207b7a50`（descriptor 0x11417e4dc，fieldCount=4、storageSize=32）=
1 `oid`（int64 族，flags 0x80028，offset 8）、2 `type`（同族，offset 0x10）、3 `rpid`（同族，
offset 0x18）、4 `needTranslate`（标量/bool，flags 0x28，offset 4）——与
`shareWithRpid:oid:type:needTranslate:…` 的形参一一对应，即该 RPC 只按 (oid,type,rpid) 取素材，
`needTranslate` 控制是否带翻译。
