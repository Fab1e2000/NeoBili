# 设置配置同步、上传与缓存

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 设置配置同步、上传与缓存

### Distribution 通用偏好

BBCDeviceConfig.init（0x114fa9204）建串行request/file队列，retryCount=0、
debounce=1秒、generation=0；启动加载ability/userOperation/universalConf及两种diff
PB缓存，universalBlocked则新建空RAM集合。缺失/空/解析失败的universal缓存退
新空UserPreferenceReply。这里只研究路径与代码，未读取真实配置文件或账号值（本地/账号数据，静态不可定；下一步 `disassemble 0x115ee8e40 0x115ee9a20`）。
cleanUniversalConfigCache（0x114fa93a0）仅清blocked集合，不删除配置、diff或磁盘；
因此此前账号观察者调用clean不能概括为“登录切换清空所有偏好”。

startCloudSync（0x114fa92d0）先syncDiff，completion拉PlayConf和UserPreference；
startUniversalConfigSync（0x114fa9348）只在该completion拉后者。completion即使
上传失败或debounce generation已过期仍执行，不以远端确认成功作为拉取门槛。
requestRemoteUniversalConfig（0x114faa4f8）发Distribution.UserPreference，
UserPreferenceReq descriptor（0x114faca38）零字段；Reply只有field1重复Any
preferenceArray。handler error非nil直接返回，没有业务重试；nil error则copy响应、
merge并排队raw3持久化，该handler没有另一层nil-response或业务status检查。

merge（0x114faac50）在blocked为空时替换universalConf；非空则保留本地blocked
类型，接收远端未blocked项，匹配键为Any.typeURL.lastPathComponent。设置写入
setUniversalConfig:typeUrl（0x114fab274）却按containsString(typeUrl)替换当前
和diff中的旧Any，并将typeUrl.lastPathComponent加入blocked。两处匹配规则不同。
新对象用GPBAny.pack(message,error:nil)，没有处理pack错误；getter
（0x114fab774）锁内copy数组后解锁，取首个substring匹配Any并unpack(error:nil)，
不查远端或diff。typeUrlForClass（0x114fab0b4）按类名缓存descriptor.fullName，
不是自行拼type.googleapis.com URL。

设置wrapper已连接这层：PegasusMid/Device/DeviceWithoutFplocal、CloudPlay/
MidPlay/Play/SpecificPlay、DynamicDevice、OtherSettings、Privacy/MidPrivacy、
SearchDevice的uploadConfig均尾调setUniversalConfig:typeUrl。例如
PegasusDeviceWithoutFplocalConfig.cachedConfig（0x114898fb8）/upload
（0x114898ff4）用完整PB名bilibili.app.distribution.pegasus.v1.
PegasusDeviceWithoutFplocalConfig读写。不能据Objective-C类名将这些偏好上传
误作设备指纹登记；wrapper名称中的Mid也不足以证明磁盘按MID分区。

syncDiffToRemote（0x114fa9eb8）原子递增generation，1秒后在request队列比较；
旧generation跳上传但仍completion。最新generation先处理PlayConf diff，再仅
universalDiff非nil且preferenceArray_Count>0时发SetUserPreference。
SetUserPreferenceReq（0x114facb0c）有field1重复Any preferenceArray、field2
extraContext/message；该builder只赋field1。发送helper（0x114faa7e4）等待
semaphore最多20秒，但忽略wait返回，没有合成超时NSError。非nil响应且nil error
才把universalDiff换为新空Reply并重置共享retryCount；失败保留diff，只有非nil
NSError调用retryLater。超时后response/error仍nil本身不安排重试。
成功清理的是当时的整个当前diff（0x114faa2bc–0x114faa2d8），没有与请求快照
做版本比较。generation仅延迟block入口检查；请求构造/等待期间setter仍可改diff。
因此并发新修改的保留不能由debounce推定；此处记录静态清理边界，未复现实际竞态。

retryLater（0x114faa9ec）在unsigned count<=4时先+1，再10秒global queue重入
syncDiff（另受1秒debounce）；count已有5不再安排。Play和Universal两种成功都
重置同一计数，同一pass的两种error也可各自增加/调度，不能写成单个Universal
请求固定五次尝试。排队后身份/配置变更的更高层处理仍需追踪。

持久化（0x114fa95b4）在file queue执行时才copy模型，调用Tools.syncMessage，
忽略write BOOL后仍通知delegate。路径由NSSearchPath raw14/userDomain1取得目录
再附DeviceConfig，不在这层附账号MID。模型映射为1:cloud_config、2:cloud_op、
3:cloud_universal_config、100:cloud_diff、101:cloud_universal_diff。
PB.data非空原子写；空data删除文件；nil snapshot跳写。因此成功上传后的新空diff
可删除diff文件，而不是nil对象触发删除。main异步syncDeviceConfigWith通知表示
写入尝试完成，不证明磁盘成功。ConfigureHandler（0x10068b3e4）消费通知后取
isAlbumAirdropEnable，写share extension suite的shareExtensionAirdropEnable字符串0/1；
这是派生设置同步，亦非设备登记。

该ConfigureHandler确有注册：ShareIntentService.updateDataInfoAndAddAccountObserver
（0x1006971a8→0x100696db4）调用BBCDeviceConfig.addDelegate(self.configureHandler)
（0x100696fa8）。isAlbumAirdropEnable（0x10069669c）仅hit_album_airdrop_experiment
命中时读MidImConfig.canAirdropToIm.value，缺消息false；setter同实验且只改value
再upload，未写lastModified/defaultValue/exp。MidImConfig实际PB全名为
bilibili.app.distribution.home.v1.MidImConfig，不能据类名猜其他包。

StoryStatus另消费raw3通知（0x1132e7650），首次迁移0x1132e6ecc有进程once byte：
仅登录、StoryConfig非nil、gestureType.lastModified<=0且本地hadManualSetGestureMode
才迁移，local.gestureMode==1→remote.value2，否则1；只setValue/setGestureType/upload，
返回即设once，不等网络成功。supportedPlayControl0x1132e7078在登录且remote时间戳
>=1时用remote.value==2，否则local.mode==1。手动更新0x1132e7184先尝试remote（登录
且已有root才上传），再写本地manual标记/mode。这条链消费StoryConfig，非MidStoryConfig；
未设lastModified，不能依据字段名字推断客户端上传时自动更新时间戳。

新的Story bloc手动setter应独立于旧StoryStatus：STSingleDoubleGestureBloc.
updateGestureMode: 0x10419eb58→0x10419e754（0x10419eb74）。该helper先toast
（0x10419e7b0），取trackBloc并发点击事件
`main.ugc-video-detail-vertical.play-set-type.0.click`（0x10419e7e8/0x10419e8f4），
`play_set_state`=输入EXACT1时String2、否则String1
（0x10419e840/0x10419e848/0x10419e864），字典经此前十字段公共helper
0x1041efa34（0x10419e890）。这是writer之前的独立日志dispatch，不以Universal ACK为门禁。
然后CURRENT hasLogined（0x10419e93c/0x10419e940）为true才取StoryConfig.cachedConfig
（0x10419e958/0x10419e95c）；nil时实际alloc/init新StoryConfig
（0x10419e968/0x10419e970/0x10419e97c），与旧writer仅已有root的门禁不同。
读取gestureType（0x10419e984/0x10419e98c），setValue同映射2/1
（0x10419e9a0/0x10419e9a4/0x10419e9a8），setGestureType后uploadConfig
（0x10419e9b0/0x10419e9bc/0x10419e9c4/0x10419e9cc）。正常缺失message由前述GPB
autocreate语义处理，不能套用异常nil指针路径。该body未写lastModified/defaultValue/exp，
也没有等网络返回；后续getter若时间戳仍不满足>=1，继续采用local分支。
无论登录与否，随后取Story preferences.shared，非nil时设置hadManualSetGestureMode=true
（0x10419ea14/0x10419ea1c/0x10419ea24/0x10419ea28），另重新取shared并setGestureMode原始输入
（0x10419ea34/0x10419ea50/0x10419ea54/0x10419ea58）；没有相等旧值短路。
其gestureMode属性TQ,D,N（0x11f0fb5e8），与之前Bool模式PB的raw值不可互换。
gestureList wrapper0x10419e6e0→builder0x10419dca0（0x10419e6f4）实际创建
DetailModel（metadata accessor0x104b2fcac→class0x11ff04590）。两个模型捕获weak bloc，
通过metadata+0x1d0安装didClick：第一callback0x10419ed58
（0x10419e1c8/0x10419e1d8/0x10419e1dc/0x10419e1e0），第二0x10419ed74
（0x10419e494/0x10419e4a4/0x10419e4a8/0x10419e4ac）。该槽0x11ff04760指向
0x104b2ebb8，明确选择DetailModel.didClick ivar0x12049db28，转0x104b2f620，
写function/context pair（0x104b2f65c）。第一thunk传原始值0
（0x10419ed64/0x10419ed68），第二传1（0x10419ed80/0x10419ed84），同helper
0x10419e600 weak-load bloc（0x10419e634），非nil调用updateGestureMode:
（0x10419e640/0x10419e648/0x10419e64c）；不是从选项文案猜枚举。
具体DetailContent.setupViews 0x104b31720→0x104b308a4安装self.tapContent: gesture
（0x104b31644/0x104b31664/0x104b3167c）。tapContent:0x104b32e70→0x104b335c4
（0x104b32e9c）读CURRENT model，nil跳过；CURRENT model.disable低bit为true则返回
（0x104b335e0/0x104b335e4/0x104b335f8/0x104b335fc），否则读didClick pair并BLR
（0x104b33638/0x104b33640/0x104b3364c）。因此组件物理action、模型callback与writer
有具体接线；此处未将组件实际展示/运行或所有gestureList上游入口算作已验证。

Story handleShareWithStoryItem:season:shareSuccessBlock:coinSuccessBlock:likeSuccessBlock:
0x11334fa98确实把callback0x1133511dc交operation.canonizeChannels返回的block
（0x113350310/0x11335033c/0x113350360/0x113350388），不是孤立getShareActionItems方法。
callback捕获weak service（0x113351204）、原始输入storyItem与season参数：
incoming x2 retain为x25（0x11334fae0/0x11334fae8），写block+0x20
（0x11335036c/0x113350378）；incoming w3保存stack+0x6c
（0x11334fac8），再byte写block+0x30（0x113350364/0x113350368）。若captured
season byte==1且原始storyItem.season非nil（0x11335120c/0x113351214/0x11335121c/0x113351230），
直接返回incoming channel list（0x113351238/0x1133512f0），不重排或装本地actions。
否则新建BFCShareChannelList，incoming aboveChannels.mutableCopy追加incoming
belowChannels（0x113351258/0x113351268/0x11335127c/0x113351294），copy后设新above
（0x1133512a4/0x1133512b4）；weak service.getShareActionItems设新below
（0x1133512c4/0x1133512dc），返回新list。此门禁读取原始输入item，而getShareActionItems另读CURRENT service.storyItem；
两者不是同一时刻的快照，不能泛化所有season菜单均有本地type19。
实际入口取BFCShare.operation（0x11335014c/0x113350150），其getter
0x115ee3a80返回global block，invoke0x115ee3a8c构造BFCShareSession后明确alloc
BFCShareOperation（0x115ee3b28/0x115ee3b34），不是仅凭同名方法选Swift operation。
initWithSession:0x115ee5e48把BFCShareModel保存operation+8（0x115ee5ea4）；
canonizeChannels setter block0x115ee7968把传入callback保存operation+0x20
（0x115ee7980/0x115ee7988）。execute的菜单处理body0x115ee98e8中，默认list分支
0x115ee9a4c和服务端list构造分支0x115ee9c04均读取此槽并调用callback
（0x115ee9a60/0x115ee9a70；0x115ee9c28/0x115ee9c38），返回list复制到
operation.model.channelList（0x115ee9aa4/0x115ee9c6c）后才presentController
（0x115ee9ab4/0x115ee9cc0）。callback实际消费时机已定位；外层execute wrapper
分享channel请求的公共参数链已具体接线：execute block 0x115ee8e40取BFCShareApi.get
（0x115ee8f24），传公开path `x/share/channels`（0x115ee8f40/0x115ee8f44）。get block
0x11622c120实际alloc/init BFCShareApiOperation并setPath:（0x11622c144/0x11622c150），
不在此显式setMethod。参数来自operation.model（非canonizeBlock）及其session：

| 参数 | 来源/构造 | 参数写入地址 |
| --- | --- | --- |
| share_id | model.session.shareId | 0x115ee8fb8 |
| oid | model.session.oid | 0x115ee9004 |
| buvid | BFCShareBuvidServices.buvid | 0x115ee9040 |
| share_origin | model.session.shareOrigin | 0x115ee9084 |
| sid | model.session.sid | 0x115ee90d0 |
| spm_id / from_spmid | model.spmid / model.fromSpmid | 0x115ee910c / 0x115ee9140 |
| panel_type | static CFString `1`，slot 0x11d0454f0→0x11d0d1f30 | 0x115ee9164 |
| share_session_id | model.session.identifier | 0x115ee91a0 |
| object_extra_fields | model.objectExtraFields.yy_modelToJSONString | 0x115ee91ec |
| trigger_parameter | NSNumber(unsigned model.guideTrigger).stringValue | 0x115ee924c |

setParams block接完整map（0x115ee926c），timeout=5.0秒（0x115ee9294/0x115ee9298），
describe BFCShareChannelInfo（0x115ee92bc/0x115ee92d0），安装response callback
0x115ee95e0（0x115ee930c/0x115ee9360），实际invoke async block（0x115ee9384）。
没有读取任何标识符实际内容。
async body 0x11622c568要求CURRENT Injector.delegate存在且支持apiBaseHost、
optionsWithBaseUrl:、requestWithOptions:、modelWith:mappingClass:isArray:isOptional:
（0x11622c5b8..0x11622c608）；取host/path组成 `https://%@/%@`
（0x11622c618/0x11622c62c/0x11622c644/0x11622c64c），不在此硬编码最终host。
传optionsWithBaseUrl:（0x11622c664），params先appendShareSessionExtraParams
（0x11622c6a0）再setParams（0x11622c6b8）。此helper仅session_id非空且delegate支持
shareSessionService时取getExtraParamsWithSessionId（0x11622e0cc/0x11622e0e4/
0x11622e100），先add extra、后add调用方原params（0x11622e120/0x11622e134），
所以相同key调用方覆盖extra。extra 具体 schema/生产时点未解码（下一步 `disassemble 0x1141fd984 0x1141fda40` 枚举写入者）。
仅uppercase(method)==POST才setRequestMethod raw1（0x11622c6f8/0x11622c71c）；
GET具体options默认需另核，不能以日志fallback `GET`代替sender配置。
非零timeout才setTimeoutInterval（0x11622c728/0x11622c73c）。模型描述设置path `/data`、
class=BFCShareChannelInfo、isArray=false/isOptional=false（0x11622c744..0x11622c760），
通过delegate requestWithOptions取request（0x11622c7b8），安装completion/error/
preProcessRawData handlers（0x11622c800/0x11622c830/0x11622c860），requestAsync
（0x11622c868）。这是一条静态发送连接，不证明运行请求成功。
completion 0x11622ca58要求CURRENT operation.responseBlock存在，读取mapped result
的 `/data`键，以error=nil、model=该值调用（0x11622ca90/0x11622cab4/0x11622cad4），
不额外要求model非nil。error handler 0x11622cafc同样读取CURRENT responseBlock，
传incoming error和model=nil（0x11622cb4c/0x11622cb68/0x11622cb70）。raw preprocessor
0x11622ccb4仅JSON解析用于日志，最终返回原incoming data
（0x11622cd00/0x11622ce40/0x11622ce58）；业务code转换在具体request/backend继续核。
ShareBaseModule实际initializer 0x10018cda8分配ShareCoreInject
（0x10018cdbc/0x10018cdcc），设置同对象为Injector.delegate和arguments
（0x10018cdf0/0x10018ce04）。setter 0x11622dfa8用storeStrong写global
0x120e67210，getter 0x11622dfb8读同槽；不以BSS推运行时对象。
缺delegate或必需selector不支持时只记录注入失败日志并返回
（0x11622c9f0/0x11622ca0c/0x11622ca50），该分支不调用responseBlock；所以不自动
推导execute group已leave或fallback菜单已经触发。另一group participant也已定位：
operation.prepareBlock非nil时enter并传completion 0x115ee98e0
（0x115ee93f0/0x115ee93f8/0x115ee9418/0x115ee9440），其完成时点与channel response
分开；provider具体body继续核。
ShareCoreInject.apiBaseHost 0x1001887fc→0x1001886e8用config.getStringForKey
`share.api_base_host`（0x100188770/0x100188798），返回nil才fallback公开
`api.bilibili.com`（0x1001887b0/0x1001887d4），空字符串不触发nil fallback。
其options/request/model分别通过依赖类method转发
（0x1001888d4/0x1001888fc/0x100188a20/0x100188a30/0x100188afc/0x100188b38），
这些转发的依赖类型缓存与公共API层相同：constructor初始化
_apiOptions/_apiRequest/_apiModelDescription时用0x120280d90/0x120280d98/0x120280da0
（0x100187444/0x1001874ac/0x100187514）。既有ApiClientModule provider对应
BFCApiOptions/BFCApiRequest/BFCApiModelDescription，因此此native绑定上的channel请求
进入前述公共签名、header、gateway及ORM链；动态重绑定仍保留。BFCApiOptions默认
requestMethod=0→公共builder GET的规则适用，不能排除后续injection改写。
_apiErrorDomin使用cache 0x120293aa8（0x10018757c），相对type为
So24BFCApiRequestErrorDomain_pXp；ApiClientModule.register以provider witness
0x120497280注册（0x1049be7b4/0x1049be7dc），其+0x10→0x1049be010明确返回
BFCApiRequestErrorDomain classref 0x11f7be1a8（0x1049be02c/0x1049be034）。
ShareCoreInject.isForbiddenAPIError: 0x100188d88→0x100188c04比较error.domain与此类
nonZero domain（0x100188c30/0x100188cc0/0x100188d1c），相等才检查error.code
==110000（0x100188d44/0x100188d54/0x100188d58/0x100188d5c），其余false。
不是所有非零业务码、网络错误或未登录错误都禁止菜单；本地后续complete error −1012
与原server code110000分开。ShareCoreInject别的API错误加工、channel模型字段映射及
session extra schema继续核。

0x115ee8df0捕获原operation（0x115ee8e28），执行block 0x115ee8e40把同operation
交group notify block（0x115ee9470/0x115ee9478），明确在main queue等待group
（0x115ee94ac/0x115ee94b8）。notify先dismiss loading（0x115ee9908/0x115ee990c），
operation._terminated byte+0x49低bit为true便返回（0x115ee9914/0x115ee9918；
ivar descriptor 0x11f8b1c74）。非terminated路径读保存error byref
（0x115ee9938..0x115ee9944）；有error才调用BFCShareApi.isForbiddenError block
（0x115ee9950/0x115ee9970），false走上述default list（0x115ee9980→0x115ee9a48），
不是所有请求失败均退出。forbidden true则toast localizedDescription
（0x115ee9998/0x115ee99b0），若model.completeBlock存在，调用raw0及由rawcode−1012
构造的本地error（0x115ee99d8/0x115ee99f4/0x115ee99f8/0x115ee9a18），不呈现菜单。
isForbiddenError实现 0x11622c1e0要求error非nil且CURRENT BFCShareInjector.delegate
respondsToSelector:isForbiddenAPIError:（0x11622c1fc/0x11622c220/0x11622c230），
才调用delegate（0x11622c24c），否则false（0x11622c260）；具体ShareCoreInject规则见上述110000/domain门禁。
**真实 delegate 规则已闭合**：ShareBaseModule 的模块初始化体 sub_10018CDA8（模块名引用
`ShareBaseModuleModuleInitialize` 0x11778a820，经 swift_once 0x100186634 与尾跳 0x100186660 到达）
在 0x10018cdbc 取 `type_metadata_accessor_for_ShareCoreInject` 后 `objc_allocWithZone`+`init`
（0x10018cdc0/0x10018cdcc）新建 ShareCoreInject 实例，再把同一实例同时交给
`[BFCShareInjector setDelegate:]`（0x10018cdd4/0x10018cdd8 载 classref 与 selref 0x11f7071a8、
0x10018cdec 传 x2=x19）和 `[BFCShareInjector setArguments:]`（0x10018cdf8/0x10018ce00/0x10018ce04）。
因此 respondsToSelector:isForbiddenAPIError: 在该初始化完成后成立，判据为
`-[ShareCoreInject isForbiddenAPIError:]`（0x100188d88）的 nonZero domain 且 code==110000；
被禁止后的行为保持前述 toast localizedDescription + completeBlock raw0 与本地 −1012 error、
不呈现菜单（0x115ee9998–0x115ee9a18）。
无error才按operation._disableTitle byte+0x48（descriptor 0x11f8b1c70）选择title
（0x115ee9a2c..0x115ee9b1c）并转换服务器above/below lists。响应callback
0x115ee95e0有error只保存error（0x115ee9618..0x115ee9634），无error则分别保存
aboveChannels/belowChannels/text（0x115ee963c/0x115ee9664/0x115ee968c）及
extra.quick_message_on（0x115ee96b4/0x115ee96c4/0x115ee96d0）；只有后者==1
才group enter并requestShareList（0x115ee96e8/0x115ee96f4/0x115ee974c），随后本请求
group leave（0x115ee975c）。这些消费及等待点不是服务器业务ACK；具体HTTP解析、
channel转换/过滤和其他group participant仍继续核。

服务器菜单转换与Story追加的先后进一步明确：above/below各先交group helper
0x115ee9cf8（0x115ee9b5c/0x115ee9b70）。它按输入顺序查看当前/下一项category
（0x115ee9dac/0x115ee9dbc/0x115ee9df4），连续category相等且下一项category非空时
暂存group；边界有暂存项则追加当前项，构造BFCShareOnlineChannel，把group copy存
stateArray（0x115ee9e30/0x115ee9e3c/0x115ee9e5c/0x115ee9e78），key取首项category、
name/image/picture/textColor取首项（0x115ee9ea0/0x115ee9ec8/0x115ee9ef0/
0x115ee9f18/0x115ee9f40）；无暂存group则原项直接追加（0x115ee9f74/0x115ee9f7c）。
末项用fresh空OnlineChannel作为next sentinel（0x115ee9d80/0x115ee9d8c），非全局按key重排。
随后callback 0x115ee9fd4分别过滤转换后的above/below
（0x115ee9be8/0x115ee9bfc）：逐channel.key调用operation.channelIsAvailable:
（0x115eea080/0x115eea098），true才append（0x115eea0a8/0x115eea0b4）。
该过滤先于BFCShareChannelList构造及Story canonize callback
（0x115ee9c04/0x115ee9c38）；不能把Story在canonize中追加的custom key自动套用
此前的服务器channel过滤。
availability body 0x115ee66c8对微信/QQ等指定channel有对应平台isAppInstalled门禁
（0x115ee675c/0x115ee6774/0x115ee67e0/0x115ee67f8），随后还要求固定allow-list
contains key（0x115ee6978）。该列表initializer 0x115ee69d0以89项公开String构造并存
global 0x120dd1e40（0x115ee6f00/0x115ee6f04/0x115ee6f18），包含公开
`PLAY_SETTING`、`PLAY_MINISCREEN`（静态String slots 0x11d055170/0x11d0551a8），
与Story自定义literal `kShareActionItemPlaySetting`/`kShareActionItemMiniScreen`不同。
未读取运行时安装状态或该global实际值（运行期/本地数据，静态不可定；下一步 `query_index.py '*global*' 60` 与 `disassemble 0x115fd2f94 0x115fd3000`）；各平台完整sender/全部列表项另核。

Story分享服务有具体gesture面板producer，与前述未闭的selectPlayModeBlock菜单项区别：
getShareActionItems 0x113351b24要求CURRENT storyItem非nil，按其share_bottom_button顺序
逐model调用shareChannelForModel:，只有非nil返回才append
（0x113351b54/0x113351b68/0x113351b9c/0x113351c00/0x113351c10/0x113351c1c）。
shareChannelForModel:0x113351cac先要求BBStoryPanelsHelper.isFunctionModelAvliable:
（0x113351cec/0x113351cf0），再按CURRENT model.type−1查20项u16跳表
0x119058d80（0x113351d84..0x113351dac）。原始type19项目标0x1133521c8，创建
BFCShareCustomChannel，以公开key kShareActionItemPlaySetting（0x113352218）和weak
service action0x113354044初始化（0x1133521f0/0x113352210/0x113352224）。
该action weak service非nil且CURRENT selectPlaySettingBlock非nil才BLR block
（0x113354058/0x113354060/0x113354068/0x11335407c/0x113354094/0x113354098），
随后独立报告`main.ugc-video-detail-vertical.share-pannel.play-set.click`
（0x1133540c8/0x1133540d4），即使block缺失也仍有该日志路径；weak service不存在则不报。
可用性helper0x11335edb4实际把model.type NSNumber化后在avaliableFucntionTypes中
contains（0x11335edf4/0x11335ee0c/0x11335ee24），不是远程Bool配置读取；后者
0x11335ee50的固定array含19（0x11335f014/0x11335f018/0x11335f044/0x11335f0a4），
故普通type19通过此静态allow-list。菜单subtitle另取CURRENT storyContext.status.
currentGestureMode（0x113352234/0x113352244/0x113352254）交metaForGestureMode:
（0x113352264→0x11335e4d0）；按gesture值0取StoryRes36、非零取39
（0x11335e69c/0x11335e6a0/0x11335e6b0），遍历model.button_metas找button_status
等于该resource text（0x11335e53c/0x11335e594/0x11335e5a8）；无匹配时取firstObject
（0x11335e5f0/0x11335e600），空数组则nil。这是动态文字选择而非writer枚举映射。
服务端是否提供type19仍另核，不将type表等同每次菜单显示。
presentController按BFCShareConfigV2.enableNewSharePanel选择BFCShareControllerV2
或BFCShareController（0x115ee5f74..0x115ee5f98），同一model通过setModel:
（0x115ee5fb4）传入，再presentViewController（0x115ee6068）；不读取当前开关值。
该开关getter0x1162277f4只调用global block0x120e671f8；setter
0x11622780c复制外部block入此槽（0x116227824），不把nil或BSS内容当当前配置。
ShareModule安装helper0x10018ca88选block0x1001870dc
（0x10018cd48/0x10018cd80）。该block在bfc_isIPad=true时直接返回false
（0x100187104/0x100187108/0x10018710c），否则解析DeviceDecisionService依赖
（typeref0x1196beb30、0x10018717c），CURRENT getBoolForKey
`dd_share_poster_new_ui`、defaultValue=false（0x100187188/0x1001871a8/0x1001871b4/
0x1001871b8），返回结果（0x1001871d8）。因此面板选择有DD动态读取，未读取实际值；
实际初始化任务provider也已定位：184项Runnable公开名清单index160/slot
0x120274550为ShareModule._$GripperRunnableTaskProviderShareBaseModule。metatype
accessor0x10018d20c返回class0x120293308；conformance0x11825cf60、witness
0x11b0b82d0+8→0x1001866c4以once0x12089af78取task array0x121064e00，
initializer0x100186664保存entry metadata0x11b0b82f0/witness0x11b0b82a0
（0x100186694/0x1001866a0）。entry witness+0x20→0x100186644返回公开task名
ShareBaseModuleModuleInitialize，+0x28→0x100186660尾调0x10018cda8，后者明确调用
上述安装helper0x10018ca88（0x10018ce08）。trigger/thread getter分别使用既有
moduleInitialize/main producer（0x100186508/0x100186520）。此为具体生命周期静态
接线；公共dispatcher准入仍适用，后续getter替换与运行执行不由清单单独证明。
V2 collection选择入口0x115f07b74同样取model.channelList.allChnannels或分组channel
（0x115f07c44/0x115f07c54/0x115f07c74/0x115f07c1c），交clickOnChannel:
（0x115f07cac）；其click入口0x115f07cf0以channel.key调用同model.clickBlock
（0x115f07d50/0x115f07d98），许可后通用路径performClick
（0x115f07fe0）。Story实际onClick安装的callback0x113351318
（0x113350a20/0x113350a40/0x113350a70）由BFCShareOperation setter block
0x115ee7e0c保存operation.model.clickBlock（0x115ee7e20/0x115ee7e28）。callback先
reportShareClickWithChannel:avid:（0x113351348），再CURRENT hasLogined
（0x113351354），登录则true；未登录时仅channel.key等于公开biliIm或biliDynamic
（0x11d055088/0x11d055080，比较0x113351374/0x11335138c）返回false，并标记捕获的
共享Bool（0x113351394..0x1133513a4），其他key仍true（0x11335135c）。所以type19
play-setting不会仅因未登录被此callback拒绝；不能把分享登录门禁泛化所有自定义项。
旧Controller collectionView:didSelectItemAtIndexPath:0x115ef60f4按实际collection
取model.channelList.allChnannels或分组channel，再clickOnChannel:
（0x115ef61bc/0x115ef61cc/0x115ef61fc/0x115ef6224）。click入口0x115ef63e8
若有model.clickBlock先传channel.key，返回低bit为false绕过执行
（0x115ef6448/0x115ef6490/0x115ef64b0），其后还存在青少年限制及特定key分支；
通用允许路径调用performClickWithChannel:isMessage:（0x115ef66d8）。
该执行器0x115ef0e18明确isKindOf BFCShareCustomChannel
（0x115ef1038/0x115ef1048/0x115ef104c），捕获原channel后把completion
0x115ef1e18交dismissWithCompletion:（0x115ef106c/0x115ef1088/0x115ef10a0）。
completion读取原channel.action并直接BLR（0x115ef1e38/0x115ef1e48/0x115ef1e4c），
没有action非nil防护；随后若model.completeBlock存在才调用raw1、nil error
（0x115ef1e70/0x115ef1e8c/0x115ef1e90/0x115ef1e94）。V2独立执行器
0x115f028e4同样识别该custom class、交completion0x115f038e4
（0x115f02b04/0x115f02b38/0x115f02b6c），后者action BLR
0x115f03918、complete raw1/nil（0x115f03928..0x115f03960）。因此此处的成功
回调是本地action返回后的完成通知，不是设置上传ACK；物理collection点击与Story clickBlock安装已定位，
其余青少年/特殊key分支、dismiss completion 实际运行与菜单呈现属运行期 UI，静态不可定（下一步 `disassemble 0x1159613c4 0x115962000` 复核同步分支）。

真实RigthModule.makeShareService为此service安装weak module block0x1132c2b68
（0x1132c27e4/0x1132c27f8/0x1132c2814）。block weak-load module后
_showPlaySettingPanels（0x1132c2b78/0x1132c2b80→0x1132c3384）；该body CURRENT
storyContext.store（0x1132c3394/0x1132c33a4），resolve具体STSingleDoubleGestureBloc
（0x1132c33b8/0x1132c33c8），返回receiver调用show（0x1132c33ec）。
show0x10419da18→0x10419d7f0（0x10419da2c）要求weak layout.mainVC非nil
（0x10419d84c/0x10419d85c），取gestureList（0x10419d86c），构建VKSettingVC
（0x10419d8a0/0x10419d8ac），session设singleDoubleGestureList
（0x10419d8d4/0x10419d910），调用poper helper0x1041ce6a4
（0x10419d9a4/0x10419d9bc），将返回swipeVC弱保存（0x10419d9dc）。
因此menu action→具体bloc→列表→前述DetailContent choice→日志/本地writer/条件Universal
上传具有静态连接；Store.resolve实际实例安装及最终UI呈现结果仍未运行验证。

<a id="实验devicedecision值来源与-upload-账号边界task-14-补"></a>

#### 实验（DeviceDecision）值来源与 upload 账号边界

实验值写入通道已闭合：selref 0x11f783c58（`updateWith:force:test:from:completion:`）
全镜像引用点中实际派发方为 `-[DDApiGatewayInterceptor canonicalGatewayResponse:]`
0x100135360（site 0x100135b80）与 `-[DDMossGatewayInterceptor canonicalGatewayResponse:]`
0x1001377f0（sites 0x100137be0/0x100137e4c），即 HTTP 与 Moss 两条通道的响应都经 DD
网关拦截器推入 `-[BFCDDContainerV2 updateWith:force:test:from:completion:]` 0x100051780；
`-[DDContainer start]` 0x100049be0 亦调用（启动加载持久化容器）。观察侧另有
`HttpModule.DeviceDecisionDataObserverImp didUpdatedFor:status:value:` 0x10009bd74。
命中值本身由服务端决定，静态不可定。

upload 请求体无账号字段：UserPreferenceReq descriptor 0x114faca38 零字段；
SetUserPreferenceReq descriptor 0x114facb0c 仅 field1 preferenceArray + field2
extraContext，而 builder（syncDiffToRemote 0x114fa9eb8→发送 helper 0x114faa7e4）只赋
field1——上传内容不含 mid/账号维度，账号归属完全由公共层登录态（access_key/cookie）
承载；wrapper 名中的 "Mid" 不进请求体也不进磁盘键，与上文单文件 DeviceConfig（无 MID
后缀）一致。登出仍仅 cleanUniversalConfigCache 0x114fa93a0 清 blocked 集合，本轮未发现
新的清理调用方。

### PlayURL 旧操作配置

旧配置与Any偏好分开：requestRemotePlayConfig（0x114faa3f4）发零字段
PlayConfReq到PlayURL.PlayConf，nil NSError时copy reply.playConf保存abilityConf
并排队raw1写；error时返回无业务重试。PlayAbilityConf有30个CloudConf字段，
包括后台/翻转/投屏/字幕/模式/画质/弹幕/Dolby/无损等；PB tag不能直接当confType枚举。
cloudConfigForType（0x114fa99a4）优先本地userOperation.opDict[confType]；
没有本地值才要求propertyName/testSetPropertyName非空且abilityConf[testName]
boolValue=true，复制confType/fieldValue/confValue成PlayConfState，不赋show。

updateCloudConfig（0x114fa9b94）按confType写userOperation.opDict和
syncDiff.newDict，排队raw2/raw100持久化，再syncDiff。最新generation把newDict
合并reqDict并清newDict，reqDict非空才发PlayURL.PlayConfEdit；PlayConfEditReq
只有field1重复PlayConfState，其字段1:confType/enum、2:show/bool、
3:fieldValue/message、4:confValue/message。EditReply零字段。helper也等20秒且
忽略wait结果；非nil响应+nil error清reqDict/重置retryCount，本地userOperation
继续保留。这里没有额外业务code检查，不套用Universal的Any/blocked规则。

实际旧getter wrapper（0x114fa5d50–0x114fa6c40）传入confType与PB tag的对照：
backgroundPlayConf tag1→confType9；flip2→1、cast3→2、feedback4→3、subtitle5→4、
playbackRate6→5、timeUp7→6、playbackMode8→7、scaleMode9→8；tag10..30才与
confType10..30相同。setter原样交incoming PlayConfState给updateCloudConfig，
不替调用者改正confType。不能把描述符声明顺序直接当操作配置编号。

### 章节偏好的直接 Distribution 请求

BBPlayerChapterService._fetchReomteConfig（0x114440a3c）在currentScene.scene_cid/
scene_avid均非0时直接发GetUserPreference，不经过BBCDeviceConfig缓存。
请求typeURLArray仅bilibili.app.distribution.play.v1.SpecificPlayConfig，extraContext
含String mid/aid/cid：currentUser.mid、self.aid、self.cid十进制；本方法无hasLogined门槛。
error非nil、valueArray为空或firstAny unpack对象无enableSegmentedSection selector
时回退true；正常则读该BoolValue.value，缺wrapper的nil getter反而得到false。
所以传输失败fallback与响应缺字段不是同一种默认。

configResidentChapterSwitcherShow（0x114441c40）先写aid/cid，show=true才fetch；
loginProxy.hasLogin KVO callback0x114440314也在show=true时fetch，忽略new bool，
不能只称登录成功重取。changeResidentChapterStatus0x114442500仅状态不同才sync；
UI章节widget.didClickSwitch0x1144857c0把sender.isOn传入，无登录门槛。
PlayerScene.start0x11450510c也以model.showChaptar调用该change，因此上传不限于手动。
_syncRemoteConfig0x1144414f4构造新SpecificPlayConfig+BoolValue.value=current状态→Any，
发SetUserPreference，extra仍mid/aid/cid；此方法自身无login/nonzero scene门控。
handler0x114441754仅return，未见失败回滚/业务重试，不能将fetch条件套到写入。
