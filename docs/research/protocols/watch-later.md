# 稍后再看的旧 Phone 请求族

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 稍后再看的旧 Phone 请求族

BBPhonePegasusWatchLaterAddApi（class0x1200b3898）super由实际class metadata
确认为BBPhoneDeprecateApiV3Base（0x1200a4758），不是据API名推断Kotlin实现。
三个apiConfig均复制super配置后覆盖apiPath/requestMethod：

| API / config | endpoint | config method raw |
| --- | --- | --- |
| Add，0x10f53eb00 | https://api.bilibili.com/x/v2/history/toview/add | 12346 |
| Delete，0x10f53edcc | https://api.bilibili.com/x/v2/history/toview/del | 12346 |
| List，0x10f53f190 | https://api.bilibili.com/x/v2/history/toview | 12345 |

Base.options0x10f25ffe0若bfcRequest.options已存在就复用，不重建当前参数；缺失才
读取apiConfig，method减12345（0x10f2600cc–0x10f2600d8）写BFCApiOptions，
对应公共builder raw0 GET/raw1 POST。base config0x10f25f8bc默认timeout60、
cacheValidTime60、apiSignType34567、isNeedCacheResponseData=false；options将
signType减34567→0、ignoreCache取缓存Bool反值，并安装params/extraHTTPHeader/
modelDescriptions（0x10f2601bc–0x10f260228）。default cache life并不证明启用
缓存。base init0x10f25f7b4构造BFCApiRequest；addToQueueAsync0x10f25f834先
options/setHandler，再bfcRequest.requestAsync（0x10f25f864）。这是实际传统
HTTP发送入口，最终公共参数/签名/拦截器仍遵守前述公共层门禁。

Add.params0x10f53ebc4写aid为%lld decimal（0x10f53ec00–0x10f53ec34），
from输入String经BBPlayerFromHelper.numberFromWithTrace
（0x10f53ec4c–0x10f53ec64），返回对象非nil才加入from；不是直接透传原String。
未在该getter看到aid>0校验。Delete.params0x10f53ee90优先viewed Bool非0时
只返回viewed="1"（0x10f53eec4–0x10f53ef04）；否则按aidArray原序用%@及
%@,%@拼成aid String，无sort/dedup/逐项数值校验，nil/空array得到aid=""
（0x10f53ef08–0x10f53f02c）。viewed模式不再合aid数组。
Add结果mapping0x10f53ecc8指向根"/"字典；List mapping0x10f53f254将/data映射
BBPhonePegasusWatchLaterListModel，isArray=false，模型count/list有独立属性。
这不是以本地新增标记或animation成功代替服务端结果。

实际manager入口已匹配这些classrefs：addWatchLater0x10f53f598创建Add
（0x10f53f5f0），输入aid/from设于0x10f53f610/0x10f53f61c，再安装success/
error blocks并queueAsync0x10f53f6c8。loadWatchLaterListAtPage:pageCount:
completionHandle:errorHandle:0x10f53fd24创建List（0x10f53fd5c），只使用
incoming completion/error；该body未读取page/pageCount x2/x3，未设置pn/ps，
queueAsync0x10f53fdec，不能据selector参数声称分页请求。success/error blocks
0x10f53fe30/0x10f53fe44只在captured callback非nil时转发，未在此改列表缓存。
deleteWithAidArray0x10f53fe58创建Delete并设aidArray（0x10f53feb8），发送
0x10f53ff48；deleteHasWatched0x10f53ffb8同类设viewed=true
（0x10f540000），发送0x10f540088。
Add success block0x10f53f720先reportWatchLaterClick:pageName:
（0x10f53f798），使用captured aid的decimal及reportFrom nil→空String；这是成功
callback后的点击事件，不是该body证明点击瞬间已报告。读BBPhoneWatchLaterConfig
shared.hasShownFirstSuccess选择toast；首次分支写true（0x10f53f884），按captured
isAnimation选择动画。然后业务completeHandle非nil时交(error=nil,response)
（0x10f53f8b4–0x10f53f8c0），**callback返回后**才manager.sharedConfig.
addNewWatchLater.sendNext(NSNumber true)（0x10f53f8c4–0x10f53f90c）；未在此把
aid加入本地列表。error block0x10f53f944可按NSError.userInfo描述显示toast，
再交原error及cachedMappedResponse（0x10f53fa18–0x10f53fa2c），不发新增signal。
config marker持久保存桥已另核实：BBPhoneWatchLaterConfig（0x1200b3b40）
super是BFCPreferences（0x1202710f0），属性表0x11e483ab0将
hasShownFirstSuccess/isCloseWatchLaterList编码TB,D,N，playState编码Tq,D,N。
shared0x10f541114用once0x120c9adc0/cache0x120c9adc8，configName
0x10f5411b0固定BBPhonePegasusConfig；上述Bool setter因此经前述动态preferences
桥写RAM/UserDefaults，未在该suite名拼MID。实际磁盘提交、其他账号清理与callback
重入属运行期回调行为、静态不可定（下一步：`disassemble.py 0x10f53f9e0 0x10f53fa60` 后对完成回调打点观察是否重入），不能据名称推定exactly-once。
带登录包装入口0x10f53fa9c查BFCAccount.hasLogin（0x10f53fb08）：true直接Add；
false调用navigator.loginWithCloseBlock:nil/completeBlock（0x10f53fbc4）。完成block
0x10f53fc20只检查captured isAddAfterLogin字节恰1才Add，未在此重查hasLogin/
调用身份或处理关闭callback。不能把登录弹层出现等同已添加，也不能从该wrapper
推断所有直接Add入口都有登录门禁。列表完整模型、
账号清理与较新的BBListWatchLaterManager/Kotlin路径属独立实现、需分别取证（下一步：`query_index.py '*WatchLater*Main*' 30` 取 classref 后 `find_pointer_refs.py` 定位其 addObserver；并 `find_callers.py 0x101110078` 枚举 MainAction 族调用方），不能推广为全部
稍后再看入口已经采用这一旧实现。
manager.init0x10f53f47c另注册BFCAccount observer/actionType bitmask3
（0x10f53f4c8），创建RACSubject addNewWatchLater。其account callback
0x10f53f50c不检查incoming action/model，只对shared config写
isCloseWatchLaterList=false（0x10f53f534），不在这个body清first-success标记/
新增signal或取消待发请求；dealloc0x10f53f548移除observer。这是局部账号变化
消费，不能合并成用户列表或全部偏好的账号隔离。


### BBListWatchLaterManager 原生单条与批量添加

现代manager仍有不同endpoint。公开单条
addWith:spmid:from:isAfterLogin:container:snackBarEnable:（0x1043538c4）
转0x1043536e4：BFCAccount.hasLogined为true才0x104353cf4；false创建LoginConfig，
只有isAfterLogin bit1才装0x1043538b0完成closure，之后autoLogin。
完成closure直接回0x104353cf4，未在此重查登录/账号generation。该helper要求
router.navigationController非nil（nil到0x104353e74 BRK），取visibleVC，创建
options0x10434e60c。它用POST https://api.bilibili.com/x/v2/history/toview/add，
参数aid=输入Int64 decimal（0x10434e7d0–0x10434e7e8）、toview_version="v2"、
spmid及optional from→BBPlayerFromHelper.numberFromWithTrace，返回nil不加。
不将该入口改称资源数组协议；此options内未证aid正数门禁。
公开四参数addWith:spmid:from:isAfterLogin:入口0x104353c38把输入NSArray桥为
[String]（0x104353c60–0x104353c6c），转数组路径0x104353994（0x104353cc4）。
joined的typecache0x1202762d0→0x1196befa6也确为SaySSG。[String]数组路径
登录成立后用options0x10434e9b8，POST
https://api.bilibili.com/x/v3/fav/toview/adds（0x10434ea0c–0x10434ea54）。
resources为输入数组joined(separator:",")（0x10434eba4–0x10434ebb0），
另加toview_version="v2"、spmid，from也经上述转换；本体未排序/去重/空数组
拒绝。资源字符串的具体生产/编码需回到调用方核对（下一步：`find_callers.py 0x104353cf4 0x104353994` 枚举调用方后反汇编 resources 元素的构造点），不能把所有元素假定为aid。
两options都把/data映射同一optional非array Model（metadata0x10434f414）。
单条helper0x104353cf4和数组helper0x104353994创建BFCApiRequest，并经共同
0x104352f4c装completion（0x104352ffc）/error（0x104353078）后
requestAsync（0x104353094）。completion closure0x104353ef0先调用payload
adapter，再给业务Result tag0；error closure0x104353f7c给tag1。
单条adapter0x1043530c0→0x10435330c取/data动态cast Model，缺失/cast失败
则创建空Model（0x10435339c–0x1043533b0），并不把缺data自动改成失败。
单条业务closure0x104354038→0x1043530c4与数组0x104353ebc→0x1043533c8
负责toast/snackbar；后续Model字段、列表/删除、资源来源与缓存生命周期仍需
独立闭合，不能由请求completion推定本地列表已更新或Kotlin统一入口。
账号生命周期补充：BBListWatchLaterManager init 0x104353678–0x1043536b0仅
objc_msgSendSuper2 init（metadata accessor 0x104353658），dealloc
0x1043536b4–0x1043536e0同样只有super dealloc；两者都没有注册任何通知/账号
observer，即该现代manager无账号切换监听。账号归属因此仅由两处静态机制承担：
请求侧isAfterLogin完成closure不重查登录（上文），缓存侧cache ID helper
mid<1返回nil使登出态不写（v2列表段）；请求回执（success/error closure）不比较
发起时MID/generation。旧manager的BFCAccount observer仍只覆盖前述
isCloseWatchLaterList=false一处。


现代添加Model class0x11fe60680，RO0x11fe60620/property表0x11d8375a8：
isEnabled为Bool，toast/actionText/link为NSString，avids为NSArray；另有
iconStyle ivar0x120465460。init0x10434f2e0把isEnabled/iconStyle初始化0
（0x10434f300/0x10434f30c）。单条成功业务只在Model.isEnabled恰1且调用时
snackBarEnable bit1时交snackbar helper0x10434ff48（0x104353200），否则中心toast；
数组成功业务用isEnabled bit1（0x10435348c）选择snackbar，并把response.avids
（0x1043534a4）传入，而非原请求数组，visibleVC重新取当前router。
单条callback则保留请求时visibleVC/container，并把原aid封为数组；两者不能合并成
相同展示时机。错误分支用Error.localizedDescription→center toast，不在这些
业务callback body写共享列表缓存。Model customPropertyMapper0x10434efe8→0x10434f61c映射
isEnabled←show_toast、actionText←jump_text、link←app_jump_link；avids generic
class0x10434f078另指明元素类型。iconStyle在blacklist array0x120465400，
customTransform0x10434f268→0x10434f158读icon_type可cast Int，恰1才置Booltrue
（0x10434f22c–0x10434f23c），其他可cast数值置false；缺失/类型不符保留原状态。
该transform返回true不代表网络成功。snackbar后续动作/计时仍另核对。


### 新版 WatchLater v2 列表、清空与删除 builders

原生BBListWatchLaterInner中另外三项具体options builder已定位，不能套用旧列表
忽略page参数的结论。0x101108fc4设置GET
https://api.bilibili.com/x/v2/history/toview/v2/list（0x101109004），/data→
非array Response（metadata0x10110a0dc）。四String字段：start_key输入String、
asc由输入Bool bit1→"true"/"false"（0x101109180–0x1011091a4）、sort_field
由另一输入Bool bit1→decimal10/1（0x1011091d0–0x101109200）、split_key输入
String（0x101109204–0x10110921c）。builder不自行加pn/ps，具体输入生产另证。
first helper0x10110dd80给start_key空String（0x10110ddd4–0x10110ddd8），
后续helper0x10110e30c传入start_key原值；两者分别调用builder
（0x10110ddf0/0x10110e380），alloc/init BFCApiRequest后进入共同Rx包装
0x103714bd0（0x10110de3c/0x10110e3b4）。订阅、取消、回执归属和缓存更新仍需
沿该包装/效果consumer核对，不能把构造Observable当成已发送HTTP。
共同包装0x103714bd0捕获BFCApiRequest，创建Observable subscription closure
0x103714c84（0x103714c24–0x103714c3c；create helper0x1050f9f18）。只有该closure
执行才装completion/error并requestAsync（0x103714de0–0x103714de8），返回
0x1050e2514的静态NopDisposable（metadata0x11b353ef0，0x1050e2578）。
因此该包装没有订阅dispose→request.cancel桥；不等于整个页面绝无外层cancel，
也不据create返回断言已订阅。相邻另一包装0x103714ee4确创建dispose closure
0x1037151a4并调用request.cancel（0x1037151ac），不能把它的取消语义套用到当前
列表所选0x103714bd0。actual page effect subscription 的两块 builder 不能合并称“无取消”：
第一块 0x103714d54 completion → 0x103714dc4 error → 0x103714de0 requestAsync，
所选包装 0x103714bd0 未见直接 cancel 桥；相邻第二包装 0x103714ee4 保持可取消
disposable，0x1037151a4 读取保存的 request，0x1037151ac 加载 cancel selector，
0x1037151b0 尾调 objc_msgSend。原 team-c40 的扫描在该桥接入口前停止，
“整个族即发即弃/无法取消”结论撤回。证据 independent-dsh-review/0x103715140.asm；
账号/游标归属与取消回调交错仍需独立验证。
clear builder0x1011092c4设置POST
https://api.bilibili.com/x/v2/history/toview/clear（0x1011092ec），clean_type
为输入Bool bit1+1的decimalString，即false1/true2（0x101109454–0x101109478）。
v2/dels builder0x1011094fc设置POST
https://api.bilibili.com/x/v2/history/toview/v2/dels（0x10110952c），唯一业务参数
resources（0x10110966c–0x101109690）。输入collection按occupancy bitset/iterator
0x1011184e4枚举，每个Int64转decimal String（0x101109734–0x101109744），
数组joined comma（0x1011097fc–0x101109808）；空collection成空String，没有
显式排序或正数过滤。本体使用hash容器枚举，不假定用户点选顺序。
helper0x101114e94给该builder输入原collection，创建BFCApiRequest后直接
requestAsync（0x101114f00–0x101114f08），这个helper完整body没有装业务
completion/error handler。因此不能从该fire-and-forget helper声称删除成功后
才移除UI/缓存；实际业务触发与本地状态更新仍沿caller核对。
Response class0x11fb74c80/RO0x11fb74c20/property表0x11d5ca620含Bool
hasMore及String next/splitKey/playbackURLString、NSArray items。items generic
class0x101109d80绑定Item metadata0x10110b09c。custom mapper
0x101109d68→0x10110ba6c明确hasMore←has_more、next←next_key、
splitKey←split_key、playbackURLString←play_url、items←list；因此property名
不能直接当JSON key。willTransform0x101109e5c→0x10110bbe0另读tab_type
可cast Int，1→internal tab0、10→tab1（0x10110bcb0–0x10110bce8），缺失或
其他值保留初始化/已有值。
两条响应map thunk0x101110828/0x10111083c都到0x10110e2f8→0x10110e560，
读/data后dynamicCast Response（0x10110e5e4）；空dict、缺/data或cast失败
返回nil（0x10110e5ec/0x10110e604），没有在此构造空Response或发起重试。
Single入口0x10110e42c实际调用0x1050fb2c8→0x1050c10a4的CompactMap factory
（0x1050c10f4），输出MaybeTrait；nil转换结果在sink Optional tag1分支
0x1050c14ac–0x1050c14d0仅销毁、不forward，非nil才发next
（0x1050c1524）。因此这条入口缺/data/cast失败不会派发dataLoaded nil。
首屏helper0x10110dd80的feature byte两支也都过滤nil：byte==1分支直接调用
同CompactMap 0x1050c10a4（0x10110deb0），另一支经Single→Maybe helper
0x1050fb2c8（0x10110e040）。因此模型缺失过滤并非仅分页入口行为；
不把没有next事件等同networkFailed或构造空列表。
后续map0x101110574打包MainAction raw tag0x42，携带所捕获pageTab bit、
context和已解包Response（0x101110584–0x10111059c）；pageTab这个bit在options
控制sort_field10/1，不能将它误当独立用户sort设置。具体状态consumer
0x101113974接受tag族0x40/低位2，先把Response.splitKey写到state首String
（0x1011139c4–0x101113a18），然后按所携Bool查state的分支字典
（0x101113a28–0x101113a30）；未命中仍保留此前splitKey写入。
命中分支读取hasMore/play_url/next_key/items（0x101113acc–0x101113b38），
原捕获collection与响应items先通过0x101117d58追加，随后0x101114a98只裁掉
首尾连续cardType raw1（首端0x101114af8–0x101114c80、尾端
0x101114d48–0x101114db4），空数组原样返回；不是按aid去重，也不删除中间raw1。
组合列表与状态；缺模型的next过滤及networkFailed状态另见下段。
Swift reflection另提供业务名：MainAction descriptor0x1194eeaa8/fields
0x1197d4f1c的第三payload case是listAction；其type reference
0x1196ede26→ListAction descriptor0x1194eeac4/fields0x1197d4fc8，
payload case0/1/2/3/6分别refetch/loadMore/dataLoaded/networkFailed/deleteItems。
所以上述raw0x42对应listAction.dataLoaded，consumer低位6是deleteItems。
MainAction五payload后的无payload raw7对应hideManagementToolBar；delete效果
producer0x101114974/0x101114984包装fire-and-forget closure0x101118d44，
同时第二效果打包该hideManagementToolBar（0x1011149ac–0x1011149b4）。
包装0x10371598c的subscription closure0x103715adc→0x103715a34先执行业务
closure（0x103715a60），随后完成observer及返回NopDisposable
（0x103715a94/0x103715a9c），不等待删除HTTP ACK；0x103715984只swift_retain。
generic Store dispatch0x103715ba8先调用reducer（0x103715c3c），发布state
（0x103715c54），再forEach effects（0x103715cac）。实际页面dispatch、effects
订阅见下述实际slot/witness闭合；账号归属属服务端/运行期事实（下一步：`find_data_refs_root.py` 追 store 账号字段写入点，并以账号切换抓包核对列表归属），不把服务端接受当已验证。
首屏feature byte来源once initializer0x101119340：解析DeviceDecisionService，
getBoolForKey:watchlater_disk_cache_enable defaultfalse（0x1011193c4–0x1011193f8），
存global byte0x121069a30；首屏helper经once-token0x12030a578读取，因此不是每次
请求刷新远程开关。true分支成功map0x1011103ac先0x10110d46c写缓存，再发
raw0x42 dataLoaded，latestArray为空；false分支不走该缓存writer。
缓存ID helper0x10110d330每次读取BFCAccount.currentUser.mid，nil或MID<1返回nil；
否则拼MID decimal + "_" + pageTab映射10/1 + "_" + asc/desc，未输出实际MID/key。
writer0x10110d46c在**响应map时**调用它，先改Response.tab为捕获pageTab，
yy_modelToJSONString非空才交FallbackCacheOCBridge helper0x102124f0c，scene
main.later-watch.0.0。version来自once0x10110d1a8读取Bundle CFBundleVersion
String，缺失/错型为空；不是cache协议固定版号。writer明确传expirationTime=nil
（0x10110d548），completion是nullsub0x10110d5f8，并立即释放返回task
（0x10110d58c/0x10110d590）；没有等后端写入ACK。nil expiry在已定位FallbackCache实现的判定见后段，注入覆盖/存储边界仍另证。
在已查writer/key helper没有原请求MID或generation比较，当前MID读取与URL发送时
账号快照不是同一证据；未运行复现跨账号写入，不作发生过污染的结论。

true分支error closure0x10111043c→0x10110e180收到捕获empty/ascendingChanged判定
Bool、pageTab和asc。仅Booltrue且同cache key helper能生成ID，才创建FallbackCache
读Observable 0x101110480→0x10110d5fc；同时保留networkFailed raw0x43事件的组合。
reader回调0x10110d7a8要求read code0、JSON非nil且YYModel Response有效，才发
dataLoaded raw0x42/latestArray为空，随后completed；其他结果仅completed。
其回调没有再比对当前MID/Store generation。组合0x10110e26c调用0x1051011e0，
metadata0x105101268明确SwitchIfEmpty；source是cache读AnonymousObservable
（0x1050c6448/0x1050c6480），alternative是networkFailed的Just
（0x10110e258→0x1050d9230）。sink ctor0x105101a98初始化empty=true
（0x105101afc/0x105101b00）；onNext0x10510170c把empty=false并转发，
completed0x105101734仅empty=true才订阅alternative（0x1051017b8）。
故有效cache发dataLoaded后完成，不再发原networkFailed；未命中/无JSON/无有效模型
完成空序列，才派发原错误action。不能写成同时派发两种action或无条件成功回退。
cache error事件若存在则走sink原error转发0x1051016f0，不自动转alternative；
实际reader业务失败的code映射见下述native bridge。

Swift bridge的具体read结果加工0x102126354首先dynamicCast为
KntrCacheResultSuccess（0x102126380–0x102126394），成立时回调code0、data可选String、
error:nil（0x102126478–0x10212648c）；Success.data=nil仍保留code0，并非非空数据保证。
其他结果用String(describing:type)再依次contains CacheResultMiss、Expired、
VersionMismatch、Corrupted（0x102126400/0x102126458/0x1021264f4/0x102126544/
0x102126594），对应code1/2/3/4，data:nil/error:nil；未知类型也退code1
（0x1021265a4→0x102126468）。这里失败分类依赖类型描述String子串，未使用每类
dynamicCast。async error另回code4、data:nil、加工后的error
（0x102126740/0x102126750–0x102126764）。read success callback先检查isMainThread
（0x102126174）：main直接加工（0x102126188），非main dispatch main.async
（0x1021262c8）。上述WatchLater消费者不发Rx error，而以非0/nil/模型失败完成空序列，
因此这些cache失败仍由SwitchIfEmpty发原networkFailed；不把bridge NSError等同Rx error。

cache读的dispose与HTTP NopDisposable不同：0x10110d5fc把返回FallbackCacheOCTask
包装进闭包0x1011104e0，再0x1050a8718构造disposable；闭包到task helper
0x102124e00，调用非nil cancelBlock后将其function/context清零
（0x102124e30/0x102124e54）。read bridge0x102125d54调用
KntrFallbackCacheNativeKt.readAsync:scene:id:version:（0x102125dfc/0x102125e14），
订阅async对象virtual+0x10返回handle（0x102125f80），捕获它安装task.cancelBlock
0x102128248→0x102127bc0：调用captured handle的virtual+0x10。
write bridge0x102124f0c同样将可选expirationTime转KntrLong，nil保持nil，再调用
writeAsync:scene:id:data:version:expirationTime:（0x102125000/0x102125020）；
其返回task的cancelBlock也走0x102127bc0。这证明取消调用桥，不证明底层磁盘事务
已经中断，也不因Swift task释放推断自动cancel。native cache expiry/存储路径及运行
投递时序未运行验证；具体注入、nil expiry及文件后端见后述FallbackCache章节，
未读取实际cache/账号key。
清空列表与v2/dels的fire-and-forget不同。MainAction无payload raw3
clearAllWatched由0x1011152c0→0x10110d9d8传Booltrue，clean_type=2；raw4
clearAllInvalid由0x101115308→0x10110d9e8传false，clean_type=1。共同helper
0x10110d9f8构造clear request，再同Rx包装0x103714bd0；之后用Materialize
0x1050db7c4（metadata accessor0x1050db84c）把next/error/completed变成事件，
flatMap交0x10110db8c/0x101110814→0x10110dba0。其next raw0只返回empty
Observable；error raw1显示FavoritesRes.string_65后返回empty，不产生refresh action；
completed分支显示string_111，再发MainAction raw0x80 refreshAllData，Boolfalse
（0x10110dd28–0x10110dd60）。所以这是成功结束后的重拉效果，不能把批量delete的
乐观本地移除或无ACK handler套用到clear。这里先派refreshAllData action，
不据action名字认定立即发HTTP。MainState reflection descriptor0x1194eeae0/
fields0x1197d50a4、metadata0x11b127200的field vector确认splitKey0/isAscending16/
selectedTab17/listData24/isManagementSheetShown32。

clearAllWatchedAlert raw1由0x101115164的0x1011151a8分支清management sheet Bool，
构造AnonymousObservable→0x10110d058，BFCAlertController builder0x1011088a8；
confirm closure0x10110d1a0传raw3到0x10110fe80，向observer发clearAllWatched再completed。
clearAllInvalidAlert raw2分支0x101115214→0x10110d8b4→builder0x101108b50，
confirm0x10110fe78传raw4，cancel0x101110898→0x1011101a4只completed。
两个alert都经通用0x1004e7380到
alertControllerWithTitle:message:confirmTitle:confirmHandler:cancelTitle:cancelHandler:dismissOnEmtpyTapped:
（0x1004e7508），confirm bridge0x1004e7594调用捕获closure；builder的confirm wrapper
0x101108fb4/0x101108fb8→0x101108f7c，cancel wrapper0x101108fbc/0x101108fc0→
0x101108f2c。navigationController非nil才present；未提供这些alert的全部上游菜单入口。

refreshAllData的state reducer0x101115978识别action族0x80，传Bool到0x101110a0c，
逐现存分支重组ListState后写回字典（0x101115a28），返回空effects。
helper保存items/offset/hasMore/playURL/totalCount等，清networkError、selectedItems并
isToolShown=false；items为空时isLoading=true/pullToRefresh=false，非空时
isLoading=false/pullToRefresh=true（0x101110cec/0x101110cf4/0x101110cf8、
0x101110dac/0x101110dd0），isAscendingChanged取incoming Bool（0x101110dd4）。
clear完成传false。结合已查UI consumer，非空且headerState1才beginHeaderRefresh，
随后header action仍经refetch reducer；不能把所有分支或空分支都说成已重发请求。
其余combined reducer/外部观察采用范围继续核对。

左滑删除物理TableViewAdapter.tableView:commitEditingStyle:forRowAtIndexPath:
0x101108538→0x1011086f8，按indexPath取component并cast ItemComponent，成功才
读item.aid（0x1011087b8），store非nil才dispatch slot+98（0x10110881c）。
打包raw0x47 singleDeleteAlert，byGesture固定true（静态word0x1182502d0=1，
0x1011087f8/0x101108800）；此body没有按incoming editingStyle再次分支。
其reducer low7 0x101111434在byGesture true分支把单aid包装Set
（0x101111498/0x10111149c），产生raw0x46 deleteItems effect
（0x1011114c4/0x1011114dc），不走另一路确认弹窗。这里只归属系统commit动作，
非所有删除菜单均免确认。
deleteItems consumer0x101113c90枚举state分支字典occupancy，逐个分支对items的aid
查所传Set（0x101113f84–0x101114010）；匹配项分区后通过0x101118c24移除tail，
再裁掉首尾连续cardType raw1，保留中间分隔项。结果items写回当前分支、更新state
字典（0x101114740、0x101113d60/0x101113d90）；不是仅删除当前pageTab。
完成遍历才构造删除HTTP fire-and-forget和hideManagementToolBar两个effect
（0x101114920–0x1011149c8）。结合Store先发布state后订阅effects，证明本地删除
发生在该网络effect发出之前。这个发送helper无业务ACK/error handler，所以在已查
删除consumer/发送路径中未见失败回滚；外部通知/重新拉取仍可能纠正，不能声称整个
客户端永无恢复。后续hideManagementToolBar raw7进入0x1011154b8，读取当时
MainState.selectedTab，只清这一个分支selectedItems（0x101115574/0x101115578），
再对其isToolShown=false（0x101115808），经0x101110fd4写回字典；所查body保留
该分支totalCount，没有在此重拉或遍历全部分支清选中集合。不要把跨分支删除items与
当前分支toolbar清理合并为同一范围。

ListState reflection metadata0x11b127290/descriptor0x1194eeafc确认字段offset：
items0、offset8、networkError24、hasMore32、playbackURLString40、isLoading56、
isToolShown57、selectedItems64、totalCount72、pullToRefresh88、isAscendingChanged89。
请求reducer0x101111f30只接listAction族0x40，low0 refetch进入0x1011122a4，
low1 loadMore进入0x101111f8c。两支先要求state分支字典非空且含pageTab；否则
无请求effect（0x1011126e8/0x1011126d0）。所检查这两支在分支存在时未用旧
hasMore/isLoading值拦截请求，而是清networkError、写isLoading=true再存回分支；
UI源仍可能另行门禁，不能外推任意触发频次。
loadMore读取该分支offset String原值（0x101111ff0/0x10111277c），捕获其items
作latestArray，asc来自state.byte+16、split_key来自state首String
（0x10111276c/0x101112770），进入0x10110e30c（0x101112784）。refetch同样
读取state asc/split_key，经0x10110dd80把start_key置空（0x1011128e4–0x1011128f4）；
另传入Bool来自isAscendingChanged或现items为空的判定（0x101112800–0x1011128b8），
不是额外HTTP字段。两支均先更新state再返回effect，Store随后订阅发送。
networkFailed low3进入0x1011124b0，分支存在才写捕获error到networkError24，
isLoading=false、pullToRefresh/isAscendingChanged=false
（0x1011125f4/0x101112608/0x101112620），保留items/offset/hasMore等其余字段，
没有在这支发自动retry。模型nil被CompactMap过滤时不进入这支；是否有另一个
完成事件重置UI仍沿订阅consumer核对，不直接推断永久loading。
列表页物理入口已缩小：ListViewController.viewDidLoad0x10111b9a4→
0x10111a25c装header refresh action closure0x10111c104
（0x10111a3a0/0x10111a3fc），其0x10111b8fc先resetNoMoreData，再携
当前pageTab dispatch listAction.refetch raw0x40（0x10111b974–0x10111b988）。
footer refreshing action装closure0x10111c124（0x10111a448/0x10111a49c），
传raw0x41到0x10111d6e0，weak VC有效才读当前pageTab并dispatch loadMore
（0x10111d72c–0x10111d74c）。这证明拖刷新/底部分页动作的业务生产，
不把viewDidLoad安装action误写成它已立即请求。另一个binding0x10111acbc
订阅该ListVC.viewWillAppear:，先映射Void，再TakeCount1
（0x10111aed4/0x10111aee0→0x1051031f8，实际TakeCount factory
0x105103244），首次appearance回调0x10111cacc携当前pageTab dispatch
同refetch raw0x40（0x10111caf0–0x10111cb10），disposable进VC.disposeBag。
此为每次binding的首次appearance，不等于所有页面/整个进程只请求一次；
reducer请求门禁仍决定是否发HTTP。
ListVC binding另从store virtual+80读BehaviorRelay（0x10111b5dc），CompactMap
0x10111f0b8→0x10111d768要求weak VC有效并取其当前pageTab对应ListState，
订阅0x10111b6a4→callback0x10111d860→UI consumer0x10111d8ac，disposable进VC bag。
pullToRefresh=true且headerState1时先contentOffset0再beginHeaderRefresh并返回；
其他路径有networkError时headerState3才endHeader，items非空show error toast、空则
error展示。无error时items空且isLoading=true进入加载展示；items非空或isLoading=false
才到0x10111db04：pullToRefresh=false/headerState3时endHeader，再按hasMore选择
endFooterRefresh或endRefreshingWithNoMoreData（0x10111db80）。因此结束刷新不能
概括为只看loading=false；列表是否非空与pullToRefresh也参与。
已查effect订阅只传onNext action callback，其error/complete handler参数为nil
（0x103715d4c–0x103715d60）。nil模型被过滤不生成dataLoaded/networkFailed，也未在这条
完成回调另派reset action；仍不外推所有UI状态永久不变，因为其他action/外部生命周期
可以改state，实际空响应情况未运行验证。
MainVC.initWithNibName:bundle:0x1011233c4→0x1011271c4初始化其disposeBag/
cachedViewControllers，并新alloc Store后调用0x103715b2c，存入该VC.store
（0x1011273bc–0x1011273ec）。所检查构造不是全局共享Store；cached ListVC工厂
0x10112752c把这个Store传给列表页。MainVC.cxx_destruct0x10112556c释放disposeBag、
cached页数组与Store（0x101125588/0x1011255a8/0x1011255d8）。Store ctor
0x1037164ac创建独立DisposeBag存+28、BehaviorRelay存+10，并保存reducer function/
context；析构0x103716318释放relay/reducer context/disposeBag。实际effect subscribe
0x103715ce4传该Store作callback context，回调0x1037167cc返回同Store dispatch；
所查链未携MID/request-generation做回执比对。页面对象释放时机仍取决于外部持有，
不能从析构入口存在推断pop/换号即已取消请求；该请求包装NopDisposable边界仍适用。
全局账号通知是否重建/关闭这一MainVC、外部reload和请求取消需按通知名反查（下一步：`query_index.py '*WatchLater*Main*' 30` 后查其 addObserver 的通知名 CFString 引用点；请求取消以真机断点核对 0x103716318 析构）。
Store nominal descriptor0x1195e8ef4的vtable header offset15/count6
（0x1195e8f34/0x1195e8f38），第五method entry0x1195e8f60解析到
0x103715ba8，对应metadata slot(15+4)*8=0x98，闭合上述VC实际dispatch接收者。
该方法state发布后逐effect调用0x1037165d4→0x103715ce4；它用
0x1050e2aa0安装回调0x1037167cc（再dispatch返回Action）并将disposable加入
store+28（0x103715d64–0x103715d94）。Rx helper在0x1050e2d58实际调用
ObservableType witness+10，而不是只返回未订阅的效果对象。该conformance
0x1183a4f80明确protocol ObservableType0x1196b6198、type Effect
0x1195e8ec4、witness pattern0x11b26bf78，slot+10=0x103715940→
0x103715910读取Effect内实际Observable并调用virtual+60
（0x103715924–0x103715930）。列表所选Observable subscription已在上文闭合
completion/error/requestAsync；dispose没有直接request.cancel。页面销毁、
外层账号/并发响应归属还需独立证据。
