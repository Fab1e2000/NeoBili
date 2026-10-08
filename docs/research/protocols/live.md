# 直播播放信息与房间信息入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 直播播放信息与房间信息入口

BBLiveProcessScheduler.getRoomPlayInfoRoomID:...0x10f188a5c分别创建播放信息与
房间信息请求，两次dispatch_group_enter，0x10f188dc4在main queue挂group notify；
它们不是一条请求内的两份模型。四个回调分别为播放成功0x10f188f0c、播放失败
0x10f188f9c、房间成功0x10f189084、房间失败0x10f189114，均先loadWeak scheduler；
对象已释放时直接返回，且不执行group leave。对象仍存在时，播放成功/失败均置
processSchedulerStatus=3000，房间成功/失败均置3500；各自内部success/failure方法
发生在isCanceled检查之前。外部对应回调只有非nil且isCanceled最低位为0才调用，
随后无论成功或失败、外部回调是否被取消门禁跳过，都leave一次。因此取消标记主要
拦截外部通知，并未使这些内部处理跳过。group notify block0x10f1891fc同样弱引用
检查，随后置status=4000并调用_groupCompletion:nil；最后仅未取消且外部completion
非nil才调用外部。status=4000本身不证明两条请求业务成功。

cancelAllRequest0x10f1898b8依次对三个已保存请求（userInfo/roomInfo/playInfo）检查
非nil且isCancelled最低位为0后cancel，最后才置scheduler.isCanceled=true；此方法
没有直接leave group，也未清空请求引用。BBLiveBaseRequest.requestAsync0x111ed8310先计算_delayInterval；>0则创建不重复
NSTimer，target=self、selector=_requestAsync，存scatterTimer并加到currentRunLoop的
NSRunLoopCommonModes；否则立即调用_requestAsync。_requestAsync0x111ed848c在
调用super.requestAsync前写startTime为当前Unix秒，cost0x111ed82f0=endTime-startTime，
因此该cost不包括发送前scatter等待。requestSync0x111ed83c4直接写startTime并调super，
未走scatter等待。

cancel0x111ed8434先写manualCanceled=true；scatterTimer非nil时仅_clearTimer
（invalidate并清空timer），直接返回，没有super.cancel或完成回调。timer为nil才调
super.cancel。因此发送前的延迟请求可被取消而不触发上述四个group回调，不能断言
“任何取消最终都会leave”。已定位的_requestAsync本身也未清空timer引用，timer触发后
是否由其他路径清空仍须核对；这个分支不能仅靠timer已失效推断会调用super.cancel。
验证码重发的request归属已闭合：房间信息voucher链重发请求在0x10f18ae18–0x10f18ae40
新建后仅unsafeClaim、不写回scheduler，而cancelAllRequest0x10f1898b8的取消集合只有
userInfo/roomInfo/playInfo三个保存引用，故scheduler取消不到该重发请求；公共HTTP层
cancel到回调的最终保证属公共网络层运行期行为，在公共层章节处理，不在本节展开。

发送前延迟不是失败重试：_delayInterval0x111ed8530从options.baseUrl构造NSURL，
copy preference.scatters后按顺序找首个_needDelayWithURL返回true的scatter；无URL、
无scatter或无匹配返回-1。匹配器0x111ed8704依次遍历scatter.URLStrings，以scheme与
host字符串均相等为前提，relative=false时path必须相等；relative=true时配置path为空
则放行，否则请求path.hasPrefix(configPath)，没有路径边界或query比较。还要求
scatter.delay>=1。命中后_delayIntervalWithPreference0x111ed89f8仅支持mode=0固定
延迟delay/1000秒，mode=1为(arc4random()%delay+1)/1000秒（取余而非均匀上界API，
先转Float运算再转Double）；其他mode返回-1，不继续选后面的scatter。具体配置的
下载、持久化、默认值与哪些接口匹配仍需沿preference来源核对。
BBLiveBaseClientPreference的mapper0x111ed8cf0把scatters映射到live_network_delay，
容器mapper0x111ed8d98指定BBLiveBaseClientScatterPreference；后者mapper0x111ed8bb8
把URLStrings映射到urls。pre-transform0x111ed8e18若live_network_delay是NSString且
md_objectFromJSONString结果非nil，才用解析结果替换该键，其他输入原样copy返回。
这证明配置既可预解析，也有JSON字符串处理分支，不证明现版服务端实际下发格式。
播放接口handle0x10f189f50读取房间密码，并按currentUser.mid与roomID取得
InternalRoomUserDefault.authenticationModel的token；参数builder0x10f18a440写roomID、
httpsPlayurlEnabled、输入dolby/needPlayURL/needShowPIP、密码/token、HDR支持串及
免流类型，extra为special_scenario="0"、supported_drms="0,3"。
这些是保护房间的资料，不能与普通access_key或ticket混写，本文不读取真实值。

newRequestPlayWrapperWithParams:completion:0x10f7e8c28构造14项基础字典：

| 参数 | 来源/规则 |
| --- | --- |
| room_id / play_type / media_type | roomID直接值；playType/audioType经数值字符串helper |
| http | isHttps非0为"0"，否则"1"，不是BOOL原值字符串 |
| device_name | bfc_platformString，nil退空String |
| only_video / mask | 均为"0" |
| network | helper0x111ebaa94已闭合：BFCReachability.currentStatus==1→"wifi"、==2→"mobile"，其他（含0）→空String（0x111ebaab8–0x111ebaacc三路csel，空串常量0x11d0ce390） |
| protocol | qn==30000时"1"，其他"0,1" |
| format | format数组非nil即逗号join（空数组为空String）；nil才默认"0,2" |
| dolby | dolbyValue经数值字符串helper |
| codec | 从"0"起，H265支持则追加",1"，AV1支持则追加",2" |
| no_playurl | needShowPIP最低位为1直接"0"；否则needPlayURL非0为"0"，零为"1" |
| hdr_type | hdrTypes.length>0用原值，否则"0" |

然后0x10f7e8fd4无条件补qn字符串；freeType非0才加free_type；extra非nil则在
0x10f7e9058最后合并，可覆盖上述业务键。这里H265 getter0x10f7e92f8要求
bfc_rank>=70及iOS11或以后；AV1 getter0x10f7e9338在IJKFFUtils.isLiveAv1Supported
非0时返回1，否则组合softAV1.enable与isAv1SupportSoft结果。后者softAV1.enable取服务端下发配置、bfc_rank为运行期设备评分，取值静态不可定（服务端
下发/运行期计算），不能把codec视为固定设备平台字符串；下一步 disassemble.py
0x10f7e9338 0x10f7e93a0 复核isLiveAv1Supported分支。

0x10f7e90b0以相对路径xlive/app-room/v2/index/getRoomPlayInfo、HTTPMethod原始0、
BBLiveBasePlayInfo模型和nil keyPath建立请求。wrapper另构造Content-Type=
application/x-www-form-urlencoded、X-Live-Room-Password、x-bilibili-mid及
X-Live-Room-Token四个头，再与已有extraHTTPHeader组合；handle之后还合并当前
请求头并再次设置Content-Type/房间密码（0x10f18a2bc–0x10f18a330），再requestAsync。
合并helper0x112658e44先mutableCopy receiver，再addEntriesFromDictionary传入字典，
最后copy返回，因此传入字典覆盖receiver同名键；具体两次调用的receiver/参数分别
决定覆盖方向，不把所有extraHTTPHeader场合都外推成同一优先级。

房间信息路径独立：handle0x10f18a6fc→client0x10fbeb4bc构造room_id数值字符串、
device_model=bfc_platform（nil经helper回退）及network三项；extraParam.count>0
在0x10fbeb604合并，允许覆盖基础项。0x10fbeb650发相对路径
xlive/app-room/v1/index/getInfoByRoom、HTTPMethod原始0、BBLiveRoomInfo模型；
handle安装customResponseBeforeRequest，并补Content-Type/房间密码后requestAsync。
房间completion0x10f18aa6c先按request.cost/error.code写
live_room_combine_roomInfo_time，message取当前handle.playInfo.liveStatus。NSError非nil
时调用BBLiveUniversalHandle.handleByRoomInfoErrorCode映射，再存roomInfoError并调用
failure；映射器0x10f18b734保留原domain/userInfo，将19002002/19002003/19002004/
19002005分别改为60002/60004/60005/60006，其余code不变。映射后的code为60002或
60006时还调用BBLiveRoomBackManager.clearNode。这里不是自动重试或通用成功码。
NSError=nil时取roomInfo.gaiaInfo.v_voucher，调用
_riskValidationWithVoucher0x10f18b320：voucher.length>0即创建
BFCCommonCaptchaViewController、以router.navigationController.topViewController为parent
展示，记录live.live-room-detail.game.checklayer.show，并返回true以延后roomInfo写入
与success回调；没有voucher则返回false，立即存roomInfo并调用success。

这条正文验证码不以-352为门禁。其UI完成block0x10f18b4e4遇NSError.code=1或3，
先记录checklayer.click，并在非nil时调用quitRoomBlock；随后仍调用completion，
success非零传(token,nil)，否则传(nil,error)。下游0x10f18ad94只检查token.length>0，
非空时新建extraParam，先合并原extra再覆盖gaia_vtoken，递归调用同一房间信息请求
（0x10f18ae18、0x10f18ae40）；返回的新request只unsafeClaim，未在此写回scheduler。
空token则存roomInfoError=验证码error并调用failure（error可能nil）。本层未见次数上限。
这与公共HTTP层的x-bili-gaia-vtoken头是两种独立重发链，不能把字段或触发条件互换。
customResponseBeforeRequest对应block0x10f18aebc已闭合到字段：0x10f18aee0取block+0x20
捕获对象，0x10f18aee4读其+0x8字段，0x10f18aee8–0x10f18aeec向该字段对象+0x28槽写入
[NSDate date]后返回nil，即时间落在捕获handle的+0x8对象的+0x28。缓存与播放URL选择属
播放器运行期选择，静态不可在此闭合，下一步 disassemble.py 0x10f189f50 0x10f18a440 沿
playURL消费分支追。

两条路径进入BBLiveBaseClient公共构造：_optionsWithURLString:...0x111ed5158以
baseURL解析相对路径，创建BFCApiOptions；_mergeOptionParams0x111ed50c0先copy
getRequestCommonParams，再合并非空业务字典，业务值覆盖直播公共键。options保留
输入method，因此上述0进入已解码BFCApi默认GET分支；cacheValidLife/timeout均60秒、
ignoreCache=true、signType=0。此处不推断公共参数之后的最终覆盖或全部传输头。
liveClient工厂0x10fca8aa4读取常量槽0x11cf3a038，基础URL为
https://api.live.bilibili.com。getRequestCommonParams0x111ed8080仅在mainBundle的
bundleIdentifier等于live.bilibili.com或com.bilibili.live.broadcast时返回
platform=ios_link，其他标识返回空字典；不能把ios_link写成主客户端直播的无条件值。

entries dispatcher本身由once initializer0x100697dd8创建并保存静态槽0x1208a6168。
旧BBLiveConfigModule.initWithConfig对应body0x100697e08仅优化flag=false时向同dispatcher
加入五个entry：BBLiveBaseCommonEntry、BBLiveBaseRevenueEntry、BBLiveEntry、
BBLiveBCStudioEntry、BBLiveBCVirtualEntry。优化true的entry注册仍在追踪，不能把这一
条件列表当所有运行路径始终存在的集合。dispatcher.keys0x10edfbe9c遍历各entry.keys，
加到NSMutableSet后allObjects返回，去重但不在这里保证顺序；query键拼接的排序另待
确认。_runForEachEntry0x10edfbdc0枚举entries getter所得列表并调用block，资源回调
block0x10edfbd78先检查entry是否响应selector，再转发原BOOL。

已找到home setup到资源回调的桥：helper0x100698d10向once取得的entries dispatcher
发onHomePageInitialized，然后读取同dispatcher.keys，转Array[String]后交sharedManager
fetchResourceCommands（0x100698e0c），completion为0x1006981bc。后者将传入BOOL最低位转发给同一静态dispatcher，
没有成功/失败分支门禁，发送onLiveConfigFetched:；旧模块门禁已闭合：BBLiveConfigModule.onHomePageInitialized0x100698150经
common0x10069815c，仅runnableTaskOptEnable=false才调用该helper。
对应runnable LiveConfigModuleHomePageInitialized的producer0x1006985ec，execution
0x100698608也取同helper，经common0x100698614要求userInterfaceIdiom==0且同优化
flag==1，与旧callback互补；完整provider注册和dispatcher条目列表仍须核对，不以最近.cxx_destruct符号误归属Swift函数。

资源请求不必在每次入房发生：fetchResourceCommands0x111cc9db0先保存commands与
callBack，dd.key.live.bootstrap(default=false)关闭时立即queryCommands；开启时
返回nil、暂存等待queryLiveResourceCommands。入房_beforeFetchRoomInfo
0x10ed96e58确实向sharedManager调用后者，但它要求hasFetchedQuery=false且bootstrap
开启才执行，**发送前**就setHasFetchedQuery=true，再以暂存commands查询。
失败也未在该callback重置hasFetchedQuery；已读范围内没有自动允许下一次入房重试。
queryLiveResourceCommands完成block0x111cc9f9c仅callBack非nil时调用并清callBack/
commands；callback为nil时跳过清理。实际bootstrap开关值由服务端dd.key.live.bootstrap下发、reset的其余调用者属运行期配置面，
静态不可穷举；下一步 find_callers.py 0x111cc9db0 枚举queryCommands全部调用方逐一核对。

直播在线资源请求有独立参数路径：BBLiveBaseOnlineConfigManager.queryCommands:
customParams:completion:0x111cca028检查commands并合成business键，编码customParams，
通过共享HTTP client构造请求后requestAsync；空/无效commands直接completion(false)，
未发网络请求。底层0x111cc53c4以GET /xlive/open-interface/v1/fetch_client_resource、
BBLiveBaseOnlineConfig模型请求，基础参数business来自合成键，customize只在编码后
字符串length>0时加入。这里的business不是固定设备号或登录MID。
失败callback0x111cca290仅日志及completion(false)，没有该body内的自动重试；成功交
_handleWithOnlineConfig0x111cc9840枚举keyValueInfos，更新本地info并收集command。
只有非空command才dispatchCommands，再通知manager delegate，completion按收集数
是否非零返回BOOL；不能把HTTP成功等同于某个network配置必已更新。

旧network保存command handler0x111cc7ae4读取task.value，md_objectFromJSONString后
直接set defaultEnvironment.networkConfig，未在此检查解析结果非nil/字典或保留旧值。
新存储delegate MDKVBundle.manager:didFetchOnlineConfig:0x10fca9a44将command.dictionary
数组交storage._didFetchResponses，再仅对返回changedKeys非空时通知mainBundle readers；
MDKVBundle.network0x111ebacd4读取mainBundle的live_mobile_network键。
旧command type映射已闭合：executeTask0x111cc8f24以type-1索引42字节jump table
0x118ffff50，其中type17进入_liveNetworkConfiguration。真实磁盘写入原子性及
存储失败处理仍须继续追踪。

scatter preference的业务更新入口已找到：BBLiveEntry.onLiveConfigFetched
0x10ec85194先loadRoomPlugins，随后读取BBLiveBasePersistentEnvironment.newKVEnabled；
true取MDKVBundle.defaultBundle.network，false取defaultEnvironment.networkConfig。
所取配置非nil且通过字典类型检查后，objectOfClass转换BBLiveBaseClientPreference，
再向共享BBLiveBaseHTTPClient.client调用setPreference（0x10ec852a8）。该callback
不直接使用传入参数当preference。下载、写入这两存储的路径仍须继续追踪，不能由
callback名称推断每次入房都联网更新。

BBLiveBaseHTTPClient按非空URL字符串缓存client（0x111e8b2f8），已有则复用，
没有则defaultClientWithBaseURL创建并存入字典；空URL返回nil。setPreference
0x111e8b3ac更新自身preference，copy当前cachedClients.allValues后逐client更新，
因此已有client也接收新scatter preference，并非只有新建实例才生效；配置下载来源
**部分闭合（task-38）**：`liveClient` stub 0x1173e9bc0 的原始 __text B/BL 扫描有 430 条边，包含 0x10f787b60 等其它业务调用；撤回“≥10处全部在BBLiveBaseHTTPClient request族”的不完整扫描推论（root-static-audit/recovery）；builder `initWithLogger:` 0x10fca8944 与 liveClient 本身**无直接 BL 调用方**；OnlineConfig 的下载源仍未定位（候选路径：先用 `__objc_classlist` 定 classref 槽位再跑 find_pointer_refs）。子类_BBLiveBaseHTTPClientBuilder.initWithLogger0x10fca8944从
BFCAccount.loginModel.accessToken取得token，从authority.userID取得currentUID，
并以main queue注册账号delegate。callback0x10fca8bec不按传入login BOOL分支，
而重新读取当前account/authority并更新这两个字段。cachedClient override
0x10fca8a3c将自身设为client.delegate；已读willStart/didComplete delegate仅转给
capture，不能由token ivar存在推断它在这里写入业务参数或HTTP头。

keyPath wrapper0x111ed6edc采用code/message路径。公共请求0x111ed52b8注册
“/”→SKVObject、isArray=false、isOptional=true，再创建BBLiveBaseRequest。
响应头handler0x111ed5838和预处理block0x111ed5880分别把httpHeader/rawData
存到弱引用request；公共completion wrapper0x111ed5788先写endTime为当前Unix秒。
成功block0x111ed58c8在回调对象非nil且request.manualCanceled为真时直接回
(nil, NSURLErrorDomain/-999)，否则记录rawData，并取models["/"].dictionaryValue
交给_validatedResponse0x111ed4e20。该验证器先_filteredResponse0x111ed4ff0：
数组取firstObject，再要求NSDictionary并调用md_dictionaryByFilteringValue:NSNull；
非字典返回nil。过滤helper0x11265925c逐key跳过与所传value指针相同的值（value=nil
才取NSNull.null）；数组交0x112657748，字典递归同helper。数组也按指针过滤并递归
数组/字典，所以这里是递归移除NSNull值，空容器保留；不是字符串/NSNumber等值比较。
随后对codeKeyPath值调用integerValue；
值缺失经nil消息得到0，没有“code必须存在且为整数”的显式验证。非零code返回nil，
并生成com.bilibili.live.base.http.error.domain的同码NSError，userInfo包括
NSLocalizedDescriptionKey（message缺失用内置文案）、NSLocalizedFailureReasonErrorKey
及BBLiveBaseClientErrorRequestResponseKey（后二者均为过滤前输入对象）。code=0则
返回过滤后的对象；这仍不能单凭业务码证明后续模型有效。

失败block0x111ed5a60收到nil原始NSError时补直播域/-900001（完整mov+movk常量，
不是第一条指令显示的-48033）。它记录失败rawData，复制原NSError.userInfo；有rawData
时用NSJSONSerialization、options=1尝试JSON解析，解析错误写入NSUnderlyingErrorKey，
保持原domain/code重建NSError。JSON解析成功时运行同一业务验证器：非零业务码的
NSError优先；没有业务错误则保留原domain/code，并把非nil过滤响应加入
BBLiveBaseClientErrorRequestResponseKey。因此传输失败带code=0正文也不会自动变成功。

失败结果再查dd.live_http_client_common_captcha，default=true。开关开启、最终NSError
code=-352且响应头x-bili-gaia-vvoucher字符串非空时，调用BFCCommonCaptchaService，
tag=live、viewController=nil、useCustomAlert=false，并暂不调用普通完成回调。
验证码block0x111ed5fb8先要求弱client与弱上下文仍存在；任一释放只记录日志并返回，
不补回调。success非零时复制同一options.extraHTTPHeader（nil则新建字典），写
x-bili-gaia-vtoken=helper转换后的token，回写options；随后以原code/message路径和
完成block重新requestWithOptions并requestAsync（0x111ed6234、0x111ed6244、
0x111ed6254）。该block不检查token非空，也没有可见重试次数上限；不能据此宣称
验证码服务内部无上限。success=0则回(nil, 直播域/-352)，localizedDescription设空串，
不直接透传验证码NSError。未进入验证码分支时走普通完成block。

objectClass解析wrapper0x111ed6988把原keyPath交给_parsingResponse:inKeyPath:
objectClass:error:。底层0x111ed7558仅当keyPath.length>0才调用valueForKeyPath；
nil或空路径直接使用当前根对象。因此播放信息构造器传入的nil keyPath在这一层
不会自动取data。输入或所取路径为nil、字典/数组count=0时直接返回nil，不生成该层
类型错误；目标class已匹配则返回对象，其他值再走转换。这不排除具体模型内部另有
JSON字段映射。实际cached client由BBLiveBaseHTTPClient.defaultClientWithBaseURL
0x111e8b174安装JSONValueSerialization，block0x111e8b1c0仅对MDObject子类调用
modelWithDictionary；该方法0x111edb0a4直接走yy_modelWithDictionary。BBLiveBasePlayInfo
继承MDEntity→MDObject，MDObject默认pre-transform0x111edb3d8原样返回字典。
BBLiveBasePlayInfo mapper0x10fbf3414的15组映射为：isPortrait←is_portrait、
liveStatus←live_status、liveTime←live_time、playURLInfo←playurl_info、roomID←room_id、
shortID←short_id、uid←uid、specialType←special_type、allSpecialTypes←all_special_types、
roomOfficialType←official_type、officialRoomID←official_room_id、
pureControlFunctionArray←pure_control_function、degradedPlayURLInfo←degraded_playurl、
subtitleInfo←subtitle_cfg、playerStrategyInfo←player_strategy。
modelCustomTransformFromDictionary0x10fbf37b4把输入copy到originalDictionary；
multi_screen_info非nil且为NSString时用BBLivePlayerMultiScreenInfo.yy_modelWithJSON
转换并setMultiScreenInfo，没有这一分支的NSDictionary直接转换。随后分别计算
_calculateChatRoomStyle与_calculateCloseLiveAndNoPlayer，写两个派生BOOL，并返回true。
派生计算0x10fbf40f0的isChatRoomStyle为liveStatus!=1且allSpecialTypes不含NSNumber207；
isCloseLiveAndNoPlayer计算0x10fbf41ac为liveStatus==0且同样不含207。nil/空数组按不含处理，
不在此为raw207猜业务名称。setLiveStatus0x10fbf4268仅数值改变才重算；
setAllSpecialTypes0x10fbf42f0仅对象指针不相同时更新并重算，两个派生BOOL也仅结果
改变才写回。各字段模型类型、默认值、播放器消费者、BBLiveRoomInfo仍需继续核对，
不把mapper或transform返回true当完整播放策略或有效播放URL保证。

上述闭合公共回执、验证码重发与nil keyPath选择规则；验证码重发request归属已按
0x10f1898b8/0x10f18ae40闭合为不受scheduler取消。其余为静态边界：具体业务模型字段与
before hook需逐模型mapper核对（下一步 query_index.py '*BBLiveRoomInfo*' 30）；请求
cancel到回调的最终保证属公共网络层运行期行为（manualCanceled门禁0x111ed58c8已闭合）；
入房鉴权、弹幕与观看心跳分别由对应小节独立闭合，不能声称
直播已完整复现。

<a id="直播入房权限消费者与配置存储task-29-补"></a>

### 直播入房权限消费者与配置存储

- **入房/SP 权限消费点（team-c25 L1）**：`-[BBLiveRoomBlocStore spLiveHasPermission]` 0x1028d35f4
  （ivar `spLiveHasPermission` 0x12038e360）的共享 stub 0x10f888e84 全部 4 个消费点都是挂件点击——
  `-[BBLiveAnchorLotteryPendantBloc pendantNodeDidClick:]` 0x10ef45090、
  `-[BBLiveCouponPendantBloc pendantNodeDidClick:]` 0x10ef46cfc、
  `-[BBLivePopularityRedPacketPendantBloc pendantNodeDidClick:]` 0x10ef47ad8 与
  `-[BBLivePopularityRedPacketPendantBloc roomExport:joinPopularityRedPac…]` 0x10ef47d78
  ⇒ 当前样本里 SP 权限只门禁「天选/优惠券/人气红包挂件」。另一侧是 Swift 计算属性
  `-[BBLiveRoomProcessURLBloc verifySPPermission]` 0x101f030b4（ivar 槽 0x12036b638；函数体
  `j_j__swift_beginAccess` 0x107c2b6a0 → `j_j___Block_copy` 0x107c2b724），共享 stub 0x10f894d28 的
  4 个消费点为 `-[BBLiveNewRoomBaseViewController _verifySPPermission]` 0x10ed100bc、
  `spViewControllerWithViewController:c…` 0x10ed35350、`SPAlertController:clickAction:` 0x10ed35854、
  `-[BBLiveSPController setAlreadyBuyGuard:]` 0x10f1726e0 ⇒ 入房鉴权的 UI 消费者就是
  `BBLiveNewRoomBaseViewController`（弹权限 alert）与 `BBLiveSPController`（已购守护态）。
  注：`+[BBLivePureRoomHttpGateway canInitWithRequest:]` 0x10f819e60 是直播自有原生 HTTP 网关
  （NSURLProtocol 族），与 WebView 的 addRequestProtocol 不是同一机制。
- **配置存储（team-c25 L2）**：`BBLiveBasePersistentEnvironment` 提供持久化环境：
  `+defaultEnvironment` 0x111e81fb4（+once block 0x111e82028）、`+version` 0x111e820c4、
  `-initWithStorage:` 0x111e820cc、`-_configDefaultValues` 0x111e821c8、`-_compatWithVersion:`
  0x111e82248 / `-_compatWithVersion0` 0x111e82254、`-existGuardGuideTimestamp:` 0x111e823e4 /
  `-updateGuardGuideTimestamp:forKey:` 0x111e82450、`-replaceTagIDsIfNeeds:` 0x111e8256c /
  `-replaceTagIDsIfNeeds:parentID:` 0x111e825e8、`-smallScreenIfNeeds` 0x111e826d4、
  `-preference:didUpdateKey:value:origin:` 0x111e8270c、`-storage` 0x111e827bc，协议
  `BBLiveBasePersistentEnvironmentPrivate` 0x11e7ee310。**默认键与迁移键已读出（task-30）**：
  `-_configDefaultValues` 0x111e821c8 只有两条「缺省填充」——`[self valueForKey:@"liveSeekFrameEnableV2"]`
  （CFString 0x11d27cbf0）为 nil 时 `setLiveSeekFrameEnableV2:1`（0x111e821fc/0x111e82200）、
  `valueForKey:@"lastRpType"`（0x11d27cc10）为 nil 时 `setLastRpType:2`（0x111e82238/0x111e82240）。
  `-_compatWithVersion:` 0x111e82248 仅在 version==0 时 tail 到 `-_compatWithVersion0` 0x111e82254，
  后者从两个存储把旧键搬进属性（**读取迁移，不写默认值**）：standardUserDefaults 的
  `SHOW_SUPPER_BANNER`（0x11d27cc30）→ `setBannerIDs:`、
  `BBLIVE_DISPLAY_GUARD_GUIDE`（0x11d27cc50）→ `setDisplayGuardGuideTimestamps:`；
  suite `BBLiveUserDefault`（`initWithSuiteName:` 0x11d27cc70，0x111e822ec）的
  `HAS_BEEN_SHOW_TAGS`（0x11d27cc90）→ `setTagIDs:`、
  `UNSHOWSMALLSCREEN`（0x11d27ccb0）→ `boolForKey:` **取反**（`eor w2,w0,#1`，0x111e82330）→
  `setSmallScreen:`、`ISUNFIRSTSMALLSCREENSHOW`（0x11d27ccd0）→ `setEverSmallScreen:`、
  `NO_LONGER_SHOW_ADD_LIVEROOM_TO_DESK_GUIDE`（0x11d27ccf0）→ `setEverShowAddLiveRoomToDeskGuide:`、
  `NO_LONGER_SHOW_VOICE_LINK_ENTRANCE_GUIDE`（0x11d27cd10）→ `setEverShowVoiceLinkEntranceGuide:`、
  `NO_LONGER_SHOW_GIFT_COMBO_GUIDE`（0x11d27cd30）→ `setEverShowGiftComboGuide:`、
  `NO_LONGER_SHOW_SVGA_GIFT_COMBO_GUIDE`（0x11d27cd50）→ `setEverShowSVGAGiftComboGuide:`。
  即 2 个进程内默认 + 9 个旧键迁移；suite 名已闭合为字符串 `BBLiveUserDefault`。

### 直播观看时长的独立通道

播放/房间信息与观看计时不是同一请求。BBLiveBaseHTTPClient.requestLiveEnterWithBody
0x10f0e7968以POST /xlive/data-interface/v1/heartbeat/mobileEntry、
BBLiveWatchDurationEnter模型创建请求；requestLiveHeartBeatWithBody:sign:
0x10f0e7a34复制body（nil用空字典），最后合入client_sign，可覆盖body同名键，
再POST /xlive/data-interface/v1/heartbeat/mobileHeartBeat，模型BBLiveWatchDurationHeartBeat。
两者都使用liveTraceClient，其工厂0x10fca8b14以常量URL
https://live-trace.bilibili.com取cached client，单请求timeout改为5秒；不在这里调用
requestAsync，实际触发来自reporter。普通直播API域与trace域不能混写。

BBLiveWatchDurationReporter._generateBaseBody0x10f0f0e74生成八项：platform="ios"；
uuid取self._uuid的copy，经nil字符串helper；buvid取BFCTracker.trackID经同helper；
trackID实际0x115fd2ab8直接转BFCBuvid.buvid，非另一个独立随机tracker ID。
room_id/parent_id/area_id取当前reportModel对应字段；seq_id取_sequenceID；
client_ts是当前NSDate Unix秒向零截断整数。这里没有乘1000，不套App日志毫秒格式。
_reset0x10f0ecda8生成新NSUUID.UUIDString赋_uuid，同时清secretKey/strategy、sequenceID、
server timestamp/next heartbeat time及失败/本地时长状态；不是公共Session_ID重置。
这是基础八字段；watch_time与其余附加字段、补交和签名顺序见后续完整body链。

_initialize0x10f0ec2d0创建专用UserDefaults suite com.bilibili.live.watch_duration，
从固定键读取dictionary并mutableCopy到临时存储，不能仅凭读取证明全部补报成功。
_startTimer0x10f0eccc4创建重复GCDTimer，interval固定Double60秒、target=self、
action=_timerAction，随后schedule；这是检查timer，不是固定60秒一次HTTP心跳的证据。
_updateLocalConfiguationsWithHeartBeats:retry:0x10f0ecf54只在model非nil且retry=0时更新：
heartBeatInterval>=1才写_nextHeartBeatTime，timestamp>0才写_lastServerTimestamp；
secretRule非nil经_strategyPredicated过滤后替换strategy，secretKey.length>0才替换旧key。
本文不读取真实key。重试回执跳过这批配置更新，具体发送条件、响应签名规则、重试与
持久补交尚需闭合；不能把该局部写入当完整直播观看上报实现。

报告门禁已有具体数值：_shouldEnterRequestStart0x10f0ecea0仅要求roomID!=0；
_isEnterRequestComplete0x10f0ecec0要求strategy.count>0且_nextHeartBeatTime>0，
不是仅凭HTTP完成。_shouldReport0x10f0ecef4还要求roomID、areaID、parentArea都>0。
liveStart0x10f0ec7a4先检查isHeartBeating的bit0，已置位直接返回；未置位才_clean
与更新reportModel，通过入口门禁后置isHeartBeating，
发start request。completion0x10f0ec8c8只有配置完成且isHeartBeating仍true才
启动60秒timer并记最后本地Unix秒；否则清isHeartBeating、把实例+0x30 retryCount加1，
加完signed count<=2时直接liveStart，无delay/error-code分类；>2停止并清counter。
成功尾部也清counter，_clean/_reset本身不清该counter；初始零状态下最多两次追加
启动尝试。重试重新_clean/_reset会生成新uuid，不能将其当原body无变化重放。
completion读取当时共享reporter状态，未比捕获room/uuid或结束代次；结束之后旧
entry回调若到达不满足isHeartBeating条件，也可进入这条重启尝试；实际并发交错属运行期
线程调度，静态不可验证，下一步 disassemble.py 0x10f0ec8c8 0x10f0ec960 复核completion
全分支后以真机日志证实。
liveEnd0x10f0eca7c更新model、发end request后立即_clean，
并非等网络成功才停止timer。

timerAction0x10f0f1e68先更新model，localWatchDuration增加Double60，更新最后
本地Unix秒，并以isLiveEnd=true构造body存入临时缓存。正常发送分支比较累计
localWatchDuration>=服务器给的_nextHeartBeatTime，sequenceID先加1，再调用
_liveHeartBeatRequest0x10f0f0078；调用后立刻以累计时长推进_lastServerTimestamp并
清本地时长，没有等网络ack。该被调函数先保存body/sign/sign_input到
_lastFailedHeartBeat（0x10f0f0398），之后才检查_shouldReport；不满足时不发HTTP。
因此上述时间推进甚至不能单独证明已发送。不足阈值仍可能处理_lastFailedHeartBeat，因此timer
频率、服务器间隔与实际HTTP频率不能合为一个常量。
不足阈值的旧失败项分支已具体闭合：0x10f0f1fc0取_lastFailedHeartBeat，再取旧body
mutableCopy、旧sign和sign_input；body/input非nil才继续。若旧body的room_id、
parent_id、area_id经longLongValue都非零，0x10f0f20d0直接进入发送0x10f0f24c4，
沿用旧body/sign/input，不重读_shouldReport或与当前room/account/uuid比较。
任一旧ID为零则走0x10f0f2374，先要求当前_shouldReport，再仅把这三个ID替为当前
model值，重生成input/sign、覆盖_lastFailedHeartBeat并发送；其他旧body字段仍沿用。
因此补发不能概括成原样重放或全量按新model重建，也不把非零判断写成>0。
该发送callback标isRetry=true，复用普通completion；配置更新retry!=0会被门禁拒绝。
不足阈值补发不走正常阈值分支的serverTimestamp推进/本地时长清零。
这些是静态状态转换；跨房间送达与外部清理属运行期网络结果，静态不可定，需9.13抓包
（POST /xlive/data-interface/v1/heartbeat/mobileHeartBeat）验证；公共取消入口已闭合至
0x111ed8434与0x10f0ecbfc。
watch_time helper0x10f0f1828在isLiveEnd=false时原样返回累计时长；true时返回
nowUnixSeconds+localWatchDuration-lastLocalTimestamp，没有看到负值clamp。
不能用总播放墙钟时长或固定60替代所有watch_time。

_storageWithBody0x10f0f28f4复制body并加is_patch="1"，依次生成sign input与sign；
以sign作temporaryStorage字典键保存七项body、local_time、server_time、user_id、
sign_input、sign_output、extend，再写上述固定suite/key并synchronize。
user_id来自_currentUserIDString0x10f0f2d40的BBLiveBaseAuthority.userID；extend取
reportModel.extendParameters，nil用空字典。此处只记录键及来源，不输出key或签名值。
_removeTemporaryStorageWithSign:body:0x10f0f2c04按sign查找/移除并保存字典；
body没有用于该移除判断，也没有重读当前账号进行比较。_dropAllLocalWatchTime
0x10f0f2cdc清空整个临时字典并保存。这些局部不是全局账号隔离证明，补交入口的
user_id/有效期校验和成功回执移除门禁仍须独立追踪。

签名输入是自定义有序文本。_generateSignInputWithBody0x10f0edf74依_keyOrderList
逐键取body并按`"%@":"%@",`拼接，随后删最后逗号、加花括号；不是任意字典的
系统JSON序列化。_signWithInput0x10f0ee328依_strategy顺序迭代，block
0x10f0ee42c取上一轮String.UTF8String，同时以NSString.length作长度参数，调用
0x10f17c9d4，返回C字符串转NSString后用于下一轮。非ASCII输入的字节长度边界不能
用UTF8 byte count猜替换。过滤器0x10f0ec5f8接受integerValue>=0且<12；C dispatcher
的jump table0x10f17cbdc及digest factory0x10f17cd14给出本样本映射：
0–3为SHA3-224/256/384/512，4为RIPEMD-160，5/6为BLAKE2b-512/BLAKE2s-256，
7为Whirlpool，8–11为SHA-224/256/384/512。factory直接读取对应descriptor的digest
函数并编码输出；0x10f17ce54使用%02x小写hex。这里没有独立HMAC key参数。
secret_key已作为body中的有序文本字段参与，不把它改成另一个HMAC公式。
这些结论限8.89静态样本；假数据向量与9.13复核属运行期/新版验证，静态不可替代，
下一步用9.13抓包对比 heartBeat 的 sign_input 明文串。
_checkSignOriginalBodyCorrect:sign:0x10f0f1148并未重新计算digest或比较签名：只要求
传入sign.length>0，再遍历body现有keys，对命中_needsCorrectSignParameters的字段
拒绝nil/空String/"0"。它未遍历检查名单寻找body中缺失的键，空body也能越过该遍历。
不能把这道参数门禁写成密码学签名验证。

持久补交发起在_liveStartRequestWithComplete:retryCount:0x10f0ee4f8：temporaryStorage
非空即把isSupplement设true，将新base body交_supplementWatchTimeIfNeeded:body:
0x10f0f1330，输出heart_beat数组文本并放入entry POST body。该helper遍历缓存项，
读取旧body/sign_input及timestamp，经_checkSignOriginalBodyCorrect与_checkTimeAfterCST
门禁，重建JSON后以_specialSignInputWithBody:clientSign:生成补交对象。
此已检查路径没有读取存储项user_id再与当前账号比较；外部切账号清理属运行期账号生命周期，
静态不可穷尽全部触发，下一步 query_index.py '*DropAllLocalWatchTime*' 30 与 '*_reset*'
30 列出全部清空入口核对。
时间helper0x10f0f10d4实际要求timestamp>nowUnix-(UTC hour×3600+minute×60+second+28800)，
没有日期进位分支，不能仅凭方法名简化成严格“当天CST”的判断。

entry completion0x10f0eeabc先按isSupplement调用_trackPatchTimeIfNeededWithEnterModel:error:
消费reason数组；随后直接保存过滤后的secretRule、timestamp、heartBeatInterval与
secretKey（不同于普通heartbeat配置更新的>0/非空门禁），调用外部completion，再
_dropAllLocalWatchTime0x10f0eee9c。error非nil与nil路径都收敛到此尾部。
reason消费者0x10f0ed344只要求reason.count与temporaryStorage.count非零，再枚举reason；
block0x10f0ed4a0按reason的index从当时temporaryStorage.allKeys取key
（0x10f0ed500），读取对应存储项，以reason元素isEqual:"success"
（0x10f0ed5c8，实际stub0x10f8588b0→_objc_msgSend$isEqual:）判断结果并上报局部事件。
这里没有按body/sign匹配回执、固定allKeys顺序或显式index<count门禁，不能将事件中
的旧body与服务端对应关系视为已证明。逐项"success"也不是尾部整字典清空的条件。
因此不能把缓存清空当所有旧观看记录服务器确认。
timer每次还先removeAllObjects再保存当前body，持续活动中也不是无限累积的补交日志。

普通heartbeat completion0x10f0f0684的error=nil分支先无条件清当前_lastFailedHeartBeat，
按捕获sign移除持久项，再更新回执配置；未在这个RAM清除点比较captured seq/room/uuid。
error非nil则调用_retryIfNeededWithHeartBeatsError0x10f0ed0d0：nil输入为false，
非nil除code1012001/1012002/1012003外都为true。该数值规则来自shift/compare/bit
指令，不能补未知的业务错误名称。true保留失败项供之后timer处理，false只记录drop
事件；此completion没有立即重复HTTP。完整并发行为与跨房间隔离需真机实测，静态不可定；
静态侧边界已闭合至 _retryIfNeededWithHeartBeatsError 0x10f0ed0d0 的错误码分支。

end request0x10f0eef38先计算trunc(localWatchDuration+now-lastLocalTimestamp)，
要求>=1且lastLocalTimestamp>0才继续；sequenceID加1，body用isLiveEnd=true。
随后先清临时字典并_storageWithBody，再检查_shouldReport；delay>0时保存
dispatch_block、排main.dispatch_after并设randomlyDelaying=true，delay<=0立即
requestLiveHeartBeat/requestAsync。cancelRandomLiveEndEvent0x10f0ecbfc取消保存的
dispatch block并清randomlyDelaying，不等同于取消已经发出的HTTP。
随机end入口liveEndIfNeededDelay:model:0x10f0ecb30还要求isHeartBeating原始字节==1，
接受后copy传入model到reportModel，再进入上述end helper；它没有当即_clean。
待发block0x10f0ef810弱取reporter非nil才继续，先清isHeartBeating与randomlyDelaying，
用捕获body/sign/completion发HTTP，然后_clean；没有在这段发送前再校验当前
room/uuid/代次。这与立即liveEnd在调用后马上_clean的时点不同，取消dispatch block
是否赶在其执行前仍是独立边界，不能把随机delay当本地时长永久延续或网络取消。
end completion0x10f0ef8e4复用上述错误分类：error=nil或error非nil但不需重试时
按patchSign移除持久项；需重试时保留。它也调用普通配置更新helper，retry参数固定0。
这些是入房/心跳/退出三种不同状态转移；外部取消与并发隔离属运行期行为，静态不可定；
取消侧已闭合至 cancelRandomLiveEndEvent 0x10f0ecbfc，残余仅需真机时序日志验证。
body与播放器延迟来源的后续证据如下。
body字段已进一步闭合：_generateBodyWithIsLiveEnd0x10f0f18d0先生成18项，再后合入
上述八项base body，得到26项。额外项按签名顺序为timestamp、secret_key、watch_time、
up_id、up_level、jump_from、gu_id、play_type、play_url、s_time、data_behavior_id、
data_source_id、up_session、visit_id、watch_status、click_id、session_id、player_type。
timestamp取_lastServerTimestamp、watch_time取计时helper，各向零截断再转String；
s_time固定"0"，jump_from仅nil改"0"（空串不在此改）；其他附加值取reportModel。
完整_keyOrderList把前三个base字段platform/uuid/buvid、seq_id/room_id/parent_id/area_id
放最前，18项随后，client_ts最后。session_id取reportModel.sessionID，是直播模型
字段，不应自动替换成HTTP公共Session_ID。

播放器适配器入口已找到：BBLivePlayerAdapterReport._startWatchDuration0x10f0e8db4
把自身playerHeartReportModel交可响应delegate的playerAdapterReportModel:补充字段，
再检查delegate的playerLoadedType原始值恰为1；
满足时把self设shared reporter.dataSource，再liveStart。这里检查的是loadedType，
不能因拒绝日志写着not live就改称liveStatus判断。_stopWatchDuration0x10f0e8f84
先检查/取消尚在随机延迟的end，另reportAbsoluteDuration，再调用liveEnd。
_randomStopWatchDuration0x10f0e93d8取arc4random()%50+10作为Double秒delay，
传入当前playerHeartReportModel的copy。1,006个假数离线核对该除法/余数指令等价，
零差异，只验证10–59秒的算术，不证明运行时分布或实际停止触发频次。
pausePlayerHeartReport0x10f0e7e10读取isWillEnterBackground字节（getter0x10f0ea2e0，
实例+0x11）：恰为1走_stopWatchDuration，否则走随机延迟end；stopByNotice
（getter0x10f0ea2d0，+0x10）为1时随后清零。continue0x10f0e800c与resume
0x10f0e82e8先检查/取消待发随机end，再清stopByNotice并重读randomlyDelaying；
false才调用_startWatchDuration；其后shared reporter.liveStart另有上述isHeartBeating
门禁，不能将adapter调用本身当已发HTTP，也不能把这个共享BOOL当账号/房间代次校验。
terminalPlayerHeartReport0x10f0e850c只停止自身playerHeartTimer并置nil；该方法体
没有调用watch-duration reporter.liveEnd，其计时器与reporter的60秒timer不同。

上游BBLivePlayerAdapter.playbackStateDidChange0x10f0c9eb8按原始状态分派：
3走continue；1、5、6跳过pause/continue；4更新binder后pause，其余值走pause。
这些是原始枚举值；其业务语义名属上游播放器框架定义，本镜像无符号可证，属不可静态判定项，
保留原始值1/3/4/5/6不命名（对照 disassemble.py 0x10f0c9eb8 0x10f0c9f60）。
playerDidLoadHandle0x10f0c3c20先执行其他tracker，再要求willStartupHeartTrack
字节恰为1（0x10f0c3d10），当即清零，随后更新playerHeartReportModel的gu_id
（resolverModel.neuronSession）、data_source_id、data_behavior_id及click_id
（后三者来自roomAdapter），尾部0x10f0c3ff4在updateFirstReport后调用resume。
不满足入口字节时跳过这一段，不能概括成每次first-frame都重新入房。
loadStateDidChange:reason:0x10f0ca1ac的非零入参分支会pause（0x10f0ca400）；
零分支执行buffer结束处理后直接跳过pause。这里保留BOOL分派，不补未知业务枚举。
报告模型更新0x10f0f2dac仅在dataSource响应
reportModelForWatchDurationReporter时取其模型copy，未识别到账号或请求代次比较。
该dataSource方法0x10f0ea1f4实际tail转playerHeartReportModel getter0x10f0ea25c，
getter非nil复用同模型、nil才分配BBLivePlayerAdapterReportModel。桥接stub的邻近
符号标签可能误导，已按其实际branch目标核对selector。
shared reporter由0x10f0ec1e4的process dispatch_once缓存；dataSource是weak属性
（0x10f0f3bc4/0x10f0f3bdc）。adapter先改shared dataSource0x10f0e8efc，之后才
调用liveStart，故已在上报而拒绝新start时仍可能改变之后timer更新模型的来源；
没有在此setter或start门禁比较source/room一致性。_reset保留reportModel字段，
_updateReportModel在source不存在或不响应时不主动清旧模型。这是局部复用边界，
真实多播放器选择与并发房间行为属运行期装配，静态不可验证；静态侧已闭合至 shared reporter
once 0x10f0ec1e4 与 weak dataSource 0x10f0f3bc4，下一步需真机双房间时序日志。
字段补充从adapter.playerAdapterReportModel:0x10f0b8c20转给可响应dataSource的
playerAdapter:reportModel:；DelegateCenter0x10f0d4a14分别转发主delegate与delegates。
已定位NewRoomBaseVC0x10ed7fd78、RoomCoordinatorVC0x10ed95b7c，都读取
dd.live_coordinator_update_report_model（default=true），开启才调用房间分发器
updatePlayerAdapterReportModel:0x10eda1a54。此分发器补roomID、visitId、jumpFrom、
roomInfoModel.areaID/parentAreaID/upSession/upID、roomAnchorModel.level，以及自身
sessionID（0x10eda1dc0→0x10eda1dd8）。model.sessionID getter0x10f0eb7e8是ivar读取，
setter是nonatomic copy，非HTTP公共session getter。分发器sessionID getter
0x10edab5c0读取实例+0xb0；Coordinator._setupRoomInfoDataDispatcherWithParams
先从路由params[sessionID]取值、bfc_urlDecodedString后保存0x10ed8f040，
若保存值length为0，再从params[session_id]同样解码保存0x10ed8f228。
另一个RoomNavigator入口0x10ecd7a20直接取params[session_id]并保存0x10ecd7a60。
因此至少这些入口来自跳转参数，不是每次心跳自动生成session；上游参数最初生成与
其他writer仍需核对。false配置下保留旧model字段与外部其他delegate写入不能省略。
另外mutableCopyPlayerRoomDataDispatcherWithRoomID:officialRoomID:params:store:
0x10ed9b7d4创建新房间分发器，读取旧self.sessionID后mutableCopy，再set到新对象
（0x10ed9ba78/0x10ed9ba88/0x10ed9ba98）；同路径也复制data_source_id、data_behavior_id、
clickID和launchID。已定位caller为Coordinator.bigRefresh0x10ed8b884，以当时旧
roomInfoDataDispatcher和入参roomID/officialRoomID/params发起复制（0x10ed8b920）。
捕获新对象的后续block0x10ed8bfe8先reset旧module/store，再将捕获分发器安装到
弱取的Coordinator（0x10ed8c070）。捕获保存于block+0x20
（0x10ed8bd8c/0x10ed8bd98）；helper0x1153a0398在main直接调用block，off-main
dispatch_async到main（0x1153a03d4/0x1153a03dc）。因此该路径会沿用旧session，
而非必从新params重建；其余writer属运行期路由入口集合，静态不可穷尽，下一步
query_index.py '*sessionID*' 30 列出全部setter/caller逐一排除；跨房间实际送达需抓包验证。
系统入口也有真实接线：initWithRoomAdapter在0x10f0b7280调用installNotifications
（0x10f0c0810），把自身以object=nil注册didBecomeActive、willResignActive、
didEnterBackground、willEnterForeground及protectedDataWillBecomeUnavailable等通知。
willResignActive0x10f0c0b24先对当前playerReport写willEnterBackground=true，
willEnterForeground0x10f0c0ed4则写false；不是reporter从UIApplication自行推断。
resign方法只在delegate可响应且isPlayMiniScreenplayer返回真、PiP未开启、mini后台
音乐未开启时tail调用adapter.pause；其余该方法分支不主动pause，不能把所有
resign通知都算观看结束。didBecomeActive0x10f0c11a8走recoveryPlaybackAndResetData
（0x10f0c11e4）：delegate若实现isAutoPlayInApplicationStateLaunch且返回false则
不调用play；未实现或true时，mini=true可绕过manualPause，否则要求未手动暂停，
并且readyToPlay=true才调用play。该入口本身不直接调用reporter.liveStart；后续播放
状态回调与前述continue/resume门禁仍适用，不能把每次active都算入房HTTP。
adapter.playerReport getter0x10f0c8a90已有对象则复用，nil才创建
BBLivePlayerAdapterReport并把delegate设为该adapter，不是全局shared adapter report。
同一adapter初始化还addHeartbeatTracker0x10f0c2ab8，将BBLiveOldHeartTracker与
BBLiveOldHeartRepairTracker加入以自身identifier创建的PlayerEventDispatcher，再注册
到EventCenter。这是并存的不同报告接收者，不能把旧事件通道与watch-duration HTTP
合成同一个timer/请求/去重状态；具体旧handler事件门禁仍须分别核对。

销毁入口playerControllerWillDestroy0x10f0c926c先比较传入controller与当前实例
相同，才继续；先terminalPlayerHeartReport停自身timer，再destoryPlayerEvent
（0x10f0c9348）。后者0x10f0e8cbc先取消待发随机end，再检查stopByNotice的bit0；
置位则返回，否则调用_stopWatchDuration→liveEnd。因此“terminal不发end”只描述
该单个方法体，上游组合销毁路径另有有条件的观看结束，不能遗漏或视为无条件。

房间 socket 重连补拉调度器（长连接候选的第二入口，task-11 补齐）：
`-[BBLiveSocketReconnectScheduler initWithDataDispatcher:]` 0x10edac53c weak 保存
dataDispatcher 于 +0x20；ivar +0x8 _isConnected、+0x10 _durationTime、+0x18
_disconnectInterval（0x11f848bf0–bf8）。_initialize 0x10edac5b0 置 connected=0、
_disconnectInterval=60。_socketDidDisconnect 0x10edac5c0 仅在 connected==1 时记
_durationTime=_currentTime（NSDate 截断，0x10edac648）。_socketDidConnect 0x10edac5f4
置 connected=1；_durationTime 非零时算 now-_durationTime 并清零，差值 >=
_disconnectInterval（默认60秒）才 tail 到 _refreshData——短断线重连不补拉。
_refreshData 0x10edac68c 读 defaultEnvironment.socketRefreshDuration：==-1 返回、>0
采用、否则回退5秒（0x10edac6d0–0x10edac6d8 csel），先 cancel 旧 performSelector 再
afterDelay 调 _requestData（0x10edac6f8–0x10edac718；真体 0x10f8339dc）。
_handleRoomPlayInfo: 0x10edac730 前后两次读 roomPlayInfo.liveStatus 比较，变化且 !=-1
时（0x10edac790 cmn #1）经 respondsToSelector 后向 delegate 发
socketReconnectScheduler:liveStatus:（selref 0x11f751280）；==3 走另一分支 0x10edac82c。
_handleLotteryInfo:/_getLotteryInfo（0x10edac844/0x10edac9c4）为独立抽奖信息补拉。
构造点闭合：classRef 0x11f7d11f8 唯一数据引用 0x10ed19ee0/0x10ed19ee4，即
`-[BBLiveNewRoomBaseViewController _initializeRoomBaseSubviews]`（method 0x10ed19d60）
在 0x10ed19f08 经 stub 0x10f881afc 唯一 BL 调用 setSocketReconnectScheduler:（setter
0x10edabb34）挂到房间数据分发器——不是全局单例。边界：scheduler 只有
socket:didConnectToHost:port: 等 SocketRocket 风格回调桩（0x10edacbd4–0x10edacbdc），
主二进制内无 BBLiveSocket/WebSocket 实现类（query_index '*BBLiveSocket*''*DMWebSocket*'
均无实现），房间长连接传输实体（地址、心跳帧）不在本镜像，静态不可判，需真机抓包直播
房间数据通道取证。
观看时长账号清理边界闭合：_dropAllLocalWatchTime 0x10f0f2cdc 的消息桩 0x10f8330fc
全镜像唯一 BL 调用点 0x10f0eee9c（entry completion 体内），这只证明所选消息桩的直接调用来自「entry 上报完成」，不覆盖间接派发、其它 setter
或持久化后端清理，不能据此排除登出/切账号清理路径（阳性对照：selRef 0x11f603e28
存在、stub 仅 1 个调用方）；账号切换时本地补交缓存是否清理属运行期账号生命周期，静态
不可定，需真机切账号日志验证。
