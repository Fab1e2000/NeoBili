# 收藏业务参数的入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 收藏业务参数的入口

MediaListApiManager.modifyFavourite（0x11456d698）向
https://api.bilibili.com/x/v3/fav/resource/deal发method1 POST；rid为传入String，nil退空，
type为resourceType十进制。addFids/delFids分别仅count>0才逗号join成add_media_ids/
del_media_ids，保持输入顺序，未排序；均空仍可发请求。签名公共项由通用层加入。
selector虽含from，入口保存参数x2/x3/x4/x5/x7、未消费x6，构造范围没有from键。
不能仅凭签名参数名声称该字段已发送；本分支也未显式加入scm_action_id。
/data映射成功completion(true,nil)，失败另包装BFCApiServerErrorDomain再回false；
该业务入口本体无本地重试已证；错误码→文案转换由通用 BFCApiRequest 层执行且**不是按
code 查表**（task-14 已闭合）：`BFCApiRequest _serializationFromRawData:`（0x116093474）
非零 code 分支 0x11609377c–0x116093994 中，顶层 `code`（integerValue）非零且
ignoreCodeNonZero==0 时文案优先取响应顶层 `message`（0x1160937c4），缺失再取
`error.message`（0x1160937fc/0x116093818）；两者皆 nil 时按
`options.disableDefaultErrorMessage` 决定：==0（默认允许）兜底文案为字面 CFString
`"None"`（指针 0x11d102310，disassembler 注解；底层字节因 chained fixups 未复核），
!=0 则不写 NSLocalizedDescriptionKey。错误域固定 BFCApiNonZeroErrorDomain
（0x116093960）、code=响应顶层 code。即收藏失败 toast 是服务端 message 原文透传（或
"None"），样本内没有错误码→本地化文案的 switch/字典；该结论对所有走 BFCApiRequest
的业务通用（该方法是 ObjC 方法，直接 find_callers 0 命中属已知工具特性，其调用经
_query 内部分派、见「options 默认值、缓存与响应入口」节）。
展示侧公共消费再闭合（task-13 补）：NSError 分类方法
`-[NSError bfc_localizedDescription]`（0x114946e64）按域分派——
NSURLErrorDomain/BFCApiServerErrorDomain/BFCApiParseErrorDomain/IgHttpErrorDomain
四域取 userInfo[NSLocalizedDescriptionKey]（0x114946e8c–0x114946f0c、0x11494708c–0x1149470a4）；
非这四域时 error.bapi_status 非 nil 取 bapi_status.message（0x114946f64–0x114946fa0）；
再判 domain==io.grpc（指针槽 0x11d0419d8→CFString 0x11d395df0，底层字节已用段表
VA→offset 实读确认为 "io.grpc"）时走资源格式串：格式文案经 BFCResString 资源对象
（BFCEmptyDataSet_string1 = `BFCResString resWithName:@"BFCEmptyDataSet_string1"
table:@"BFCEmptyDataSet"`，0x11494ffec）查表（0x116486dec→0x116486d4c→0x1167ca8d8），
以 @(error.code)（0x114947024–0x114947040）格式化（0x114946fd8–0x114947074）；
其余域兜底固定 CommonRes common_global_string_8（0x1149470a8–0x1149470cc）。
即 BFCApiNonZeroErrorDomain（不在四域表内、无 bapi_status）经此分类方法只会得到
固定兜底文案，收藏 toast 实际依赖的是上段写入 userInfo 的服务端 message 原文。

首页InlineController._requestFavorite（0x11418a0c8）依isPGCSourceType分流：
PGC取epid走modifyCompilations、resourceType24；UGC取avid十进制走上述
modifyFavourite、resourceType2，以默认文件夹String0列表和空列表传入add/del。
并先读meta.tracker.from传给selector，这不改变目标函数忽略from的证据。
_updateFavoriteState0x1141884d0先要求输入非0，false直接return；true未登录仅showLogin，
登录才固定_requestFavorite:true。成功callback0x1141885b8要求weak self存在，
把token的BPInlinePlayableFavorite设true（0x114188664），通知relationship变化并toast；
失败toast localizedDescription或fallback，没有这段状态回滚。此入口不能作为取消收藏
协议证据；物理按钮与选文件夹入口是 UI 层事件接线，0x1141884d0 之前的触发者属
可静态查残余，下一步 `$PY find_callers.py 0x1141884d0` 列直接调用者后逐个回溯。

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
并boolValue，缺data/键退false；后续状态应用闭合于共同 update callback 0x1141887f8
（error 仅 toast，成功按项置位并 makeTripleLike 本地同步），登录门控见
_updateLikeState 0x114187a9c 的 hasLogined 分支；本 callback 不代表长按卡片等其他三连入口。
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
_updateLikeState把输入状态xor1后传给登录/未登录两个request，这里仅能确认输入翻转后编码，不能由此断言网络1表示点赞。原目标状态解释已撤回：
社区说明与用户“点击点赞却取消赞失败”的运行反馈支持0点赞/1取消；Neo已据此修正，
修复后的双向服务器状态仍需实际使用确认。
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
finishTripleLikeBlock/tripleLikeStateChange 的上层赋值点未在本 view 已读 body
出现，属可静态查残余，下一步 `$PY query_index.py '*finishTripleLike*' 30` 与
`$PY query_index.py '*tripleLikeStateChange*' 30` 取候选后 find_callers。

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
verifyToken空，直调provider。该 service 方法本段无 login 门控已证（body 0x104a8bef4
全读）；上层门控闭合于前文 Chronos handler 0x1143a9f28 与旧动画链"已登录或iPad"
分支 0x1144bbd04，本方法自身不负责登录。
字段helper优先级已核对：from0x104a8c56c、fromSpmid0x104a8c7bc先取service
对应String并检查长度，**非空才优先**；空串继续经context.director.currentScene.model
读取相应属性，最终nil转空串。spmid0x104a8c6b8及trackID0x104a8c90c直接走当前
scene.model，无本段service覆盖值，最终nil转空串。四个helper各独立读当前scene，
与入参avid不构成同一时刻的固定model快照；service 覆盖属性（from/fromSpmid）的
setter 属属性间接写，需共享 stub 全量调用点扫描（selref 槽零引用≠无调用），
下一步 `$PY query_index.py '*LikeOrDislikeService*' 40` 列 setter 后逐个 find_callers。

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
最终共用该网络入口；animationCompleteSignal 其他接收者的展示消费属可静态查残余，
下一步 `$PY query_index.py '*animationCompleteSignal*' 30` 取候选后 find_callers。
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
再调用synchronize，未检查其返回值；本层键不含MID或avid。读取/清除方已静态闭合为
零引用：键CFString对象0x11d113140（cstring 0x1178afb40）的find_data_refs_root为0处，
加早前ADRP+ADD扫描仅写入点0x104a8cec4一处，即静态样本内该键只有写入者；
阳性对照通知CFString 0x11d366f70同法命中2个代码引用（其一为addObserver调用点）。
chained-fixup或运行期拼键无法静态排除，措辞保留"未见静态引用"。
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
Swift body0x104a8cb18在0x104a8cb70写默认true。另有公开setter0x104a8a0f8；外部
注入方经三重扫描证伪（team-d6 本轮）：find_callers 0 BL 调用点、`setSupportUnloginLike:`
无 msgSend stub（getter stub 0x10f88af40/0x1171048c4 存在为阳性对照）、ivar 偏移槽
0x12049a718 全 __text ADRP+LDR 引用仅 getter/setter 本体与 init 写 true 处
0x104a8cb6c。故静态样本内唯一写入是 init 默认 true；chained-fixup/运行期拼
selector 无法静态排除，措辞保留该限定。
kBBPlayerUnloginLike字面量的限定ADRP+ADD候选扫描只找到上述写入点；补做的CFString对象
引用扫描（0x11d113140，0处）与阳性对照（0x11d366f70，2处）使该否定达到静态可证强度。

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
决定数量。twoCoinsBtnEnabled 的实际写入闭合于本节末段（0x103b22070 经
setTwoCoinsBtnEnabled，条件 (copyright byte & 0xfd)==1）；面板默认数量由该 flag
决定，不由余额决定。

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
此偏好层没有MID分区；coinToLikeSwitch 的其他写入者与整 suite 清理属可静态查但
需全量扫描的残余，下一步 `$PY query_index.py '*coinToLikeSwitch*' 30` 列全部
setter/getter 后逐个 find_callers（共享 stub 需阳性对照）。
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
版权enum各raw的含义及其他模型分支不能由掩码猜测。其他 setter 候选属可静态查残余，
下一步 `$PY query_index.py '*setTwoCoinsBtnEnabled*' 30` 后 find_callers；
不同播放器场景不能推广为全客户端两枚规则。
