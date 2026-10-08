# 首页请求的业务组装

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 首页请求的业务组装

`BBHD2PhonePegasusMainApi.baseUrl`（0x10df57790）返回 app.bilibili.com/x/v2/feed/index。
其 getApiOptions 继承 BBHD2PegasusBaseApi 的 BFCApiOptions 构造，再打开
 enableDeviceNameParam。init 只显式初始化 helper，没有在此方法给业务整数属性设非零默认值；
必须继续看调用者赋值。

params（0x10df56ed4）明确分离如下来源和条件：

| 字段 | 来源/条件 |
| --- | --- |
| pull | pullType=0 → `0`，=1 → `1`，其他值不加 |
| idx / column | 对象整数属性转字符串 |
| network | BFCReachability.currentStatus 映射，wifi/mobile/空值分支 |
| login_event | 对象属性非零才加 |
| open_event | helper getter 的返回值，nil 兜底空字符串 |
| banner_hash | helper 属性，nil 兜底空字符串 |
| ad_extra | BBAdReport.requestAdExtra，nil 兜底空字符串 |
| splash_id | 对象属性，nil 兜底空字符串 |
| 首次额外参数 | 将 helper.firstRequestInfo 的键值逐项合入 |
| flush / recsys_mode / autoplay_card | 对象整数属性转字符串 |
| fnval/fnver/qn/fourk/force_host/player_extra_content | getPlayerParams 合并，底层 BBPlayerPreloadUrlParamsHelper.preloadUrlParams |
| interest | 已有合并值优先；未出现时用对象属性或空字符串 |
| interest_v2 | 对象属性非 nil 才加 |
| device_type | isFirstCall 为真才加 `1` |
| https_url_req | httpsPlayurlEnabled 设置映射为 `1`/`0` |
| guidance | needShowGuidance 映射为 `1`/`0` |
| screen_window_type | BBHD2ScreenSwitchHelper.windowType 转字符串 |

这不是最终请求全字段表：之后仍有公共参数、签名与拦截器。尤其兴趣、广告、播放设置、
窗口状态均有真实来源，不应由抓包中一次值写成固定常量。上游赋值和响应处理见下文；
曝光、点击与播放事件的关系仍需继续追踪。

extraHTTPHeader（0x10df56d34）只在 BFCAppPreferences.isNewInstall 且
PegasusConfig.isFeedReqSuccessOnce 为假时加 DeviceInfo。明文是 idfa 单键 JSON，nil IDFA
退为空字符串，通过 BBHD2PegasusEncrypt.AES128Encrypt:key: 再 Base64。加密函数
（0x10df06d08）调用 CCCrypt 的 op=0、algorithm=0、options=3、keyLength=16、IV=nil，
即 AES-128-ECB + PKCS#7，key 来自调用处的包内常量。本文不记录该常量，也不能据此
推断现版新安装登记仍相同。
【9.13 抓包观测（线级，team-c12；build 91300100；证据 DerivedData/Validation/team-c12/
probe-fingerprint.jsonl、endpoint-params.jsonl、probe.jsonl）】现版仍是
`POST https://app.bilibili.com/x/resource/fingerprint`（28 条：mainland 21 / overseas 7），
`Content-Type: text/plain`，query 14–15 键，**body 为 JSON 且顶层恰为 `key` 与 `content` 两键**：
`key` 长度恒 **256**（=128 字节 hex，与 8.89 实际 1024 位 modulus 输出长度相容，非 2048 位密文）、`content` 长度
**992/1024/1056/1088**（=496/512/528/544 字节 hex，与 54 字段 protobuf 的 AES 密文体量一致），
两值字符集**全为小写 hex**。这支持"9.13 仍在用同一端点、同一 `hex(AES)`+`hex(RSA)` 形状"，
但不给出 54 项实际取值、也不能证明 AES 模式/PEM 与 8.89 逐字节相同（需解密或真机 dump）。
同批还观测到访客登记 `POST https://passport.bilibili.com/x/passport-user/guest/reg`（3 条，
`application/x-www-form-urlencoded`），body 键为 `device_info`(长 384) + `dt`(长 172) +
`actionKey/appkey/build/c_locale/device/disable_rcmd/mobi_app/platform/s_locale/sdk_ver(长 6)/sign(长 32)/statistics/teenagers_age/ts`，
与静态的"两业务键 + 公共参数"一致。

helper 单例初始化（0x10df579ec）设 isColdLaunch、isFirstRefresh、willFisrtLoad 为真，
读取 Documents/chooseInterest.plist 到 firstRequestInfo，随后删除该文件。
open_event（0x10df57b60）每次先清空保存值：isFirstRefresh 为真时按 isColdLaunch 返回
cold/hot，然后无论分支都置 isFirstRefresh 为假。**读取 getter 本身消费状态**，因此不能
先为日志/诊断读取，再期待实际请求仍得到首次值。

willResignActive 将 isColdLaunch 置假、isFirstRefresh 置真；didEnterBackground 保存当前
时间；willEnterForeground 检查该时间的 timeIntervalSinceNow，当为负且绝对值严格大于
1800 秒时清空 banner_hash。所选 HDhelper 的这些方法，当前有界注册/调用扫描未找到注册点（task-36）：三方法 0x10df57b34/0x10df57bdc/0x10df57c20 **无注册点**（对应 selref 0x11f782100/0x11f65a988/0x11f781ea8 的全部 35 处加载点枚举后无 Pegasus 区间命中）且无 BL 调用者；阳性对照 BBLiveHighFansRoomViewController.viewDidLoad 0x101df93cc（0x101df9454/9c/e0）。零命中只覆盖所选 selector/直接调用形态，不排除间接注册，也不推广到独立 Swift 首页链
（类名出现不等于已注册）；下一步 `$PY query_index.py '*PegasusConfig*' 40` 后反汇编 0x10df579ec
初始化体查 `addObserver:selector:name:object:`。Swift 侧已定位前台处理函数为 0x101a35b18（不是注册点），
0x101a35ca8/0x101a35cb4 判 fabs(timeIntervalSinceNow)>1800。返回前台是否触发请求同属该运行期链。

Swift首页另有独立banner_hash链，不能套用上述HDhelper时间条件：BannerV8Model
customMapper0x101ae5a88把属性banner_hash映射原响应键hash（0x101ae6024），
卡片JSON转换0x101afaab8→model→VM（**已闭合（task-36）**：读字典键 `card_type`→`swift_dynamicCast` String→BannerV8Model metadata 0x101ae5c78→`yy_modelWithJSON:`（selref 0x11f783318 @0x101afab84）→失败 nil（0x101afabec）→`objc_allocWithZone` BannerV8ViewModel 初始化 0x101afa904（0x101afabcc）；**单卡、无状态转换**，无缓存/过滤/重排逻辑；已见两处 BL 0x101b4b8d4/0x101b4bb1c，另有尾 B 0x101af571c，不能称唯一调用方。nearest ObjC symbol 仅邻近标签，不能据此确定 Swift caller 的 owner（root-static-audit/recovery）；列表级装配残余：需继续追 find_callers 0x101afa904 与 layout 准备 0x101af5a24 的调用方）；layout准备0x101af5a24读model.banner_hash并
存MainApiMarker+20/+28，新API首建读取，nil为空。不是收到任意响应立即写请求。
Swift MainApiMarker.applicationWillEnterForeground 的 ObjC 入口 0x101a35cd8
经 trampoline 转处理body0x101a35b18；对 Date跨度取fabs，严格>1800秒清banner。
该body没有 observer mask 或 addObserver，原“读取该处mask/注册selector”的下一步
错误撤回。实际安装函数为 0x101a34ccc：三条 UIKit 生命周期通知在
0x101a34d10–dbc 注册，账号 addActionObserver:type:block: 在 0x101a34e58 传
type=11。MainApiMarker 的 BBListPegasusServicePlugin witness 0x11b16c5a0
经 0x101a356f8→0x101a34ccc；服务组装 0x101b85bd8–bf4 采用共享实例与该
witness。账号弱引用回调 0x101a36030→0x101a34f34 按 hasLogined 将 lazy
login_event 写为未登录1/已登录2，清 banner_hash 与 april_fool_id；原始 ivar
偏移分别为 +0x38、+0x20、+0x88，不能泛称清所有游标。实际注册已是阳性证据，
仍未穷尽管理器间接调用安装的具体位置、次数和新版执行时序，type=11 的具体
事件位含义也不从数值自行命名（root-static-fnval/main-api-marker.md）。
两种实现及各自缓存时机需保留区别。

【9.13 抓包观测（DerivedData/Validation/capture-resume/session-background.json、
session-restart.json；官方样本 build 91300300）】后台约 45 秒与 95 秒后返回前台各触发一次
feed/index，两次均 `open_event=hot`、`flush=6`、`pull=1`；冷启动首请求为 `open_event=cold`、
`flush=0`、`pull=1`，随后一次普通刷新为 `open_event` 空、`flush=6`。即"返回前台触发请求且
标记为 hot"已由样本支持；样本后台时长均远小于 1800 秒且未含 `banner_hash` 取值，上述清空
边界与注册时机静态残余保留。这些是本次样本取值，不是协议只允许这些组合。

【9.13 抓包观测（线级，team-c12；本机 `work/bili-capture/` 32 组 .flows，官方 App
9.13.0/build 91300100，268 条 feed/index；证据 DerivedData/Validation/team-c12/wire-feed.jsonl、
feed-template.jsonl）】`banner_hash` 在 feed/index 上**始终出现**（可为空串，从不缺键）；
完整参数模板内（n=236）：`open_event=cold` → banner_hash 42/42 为空、`hot` → 13 空 17 非空、
`open_event` 空（普通刷新）→ 73 空 91 非空。返回间隔 ≥1800 秒的 8 次请求 banner_hash **8/8 全空**，
其中 `open_event=hot` 3 次（间隔 2441s/5449s/72658s，末次即
`round2/idle_after_exposure_area_cancelled.flows`）；但 <60s 短间隔桶同样 77/163 为空，
**空值不是 1800 秒阈值的可分离信号**——本次样本既不能确认也不能否证"1800 秒才清"，
上述静态清空边界（0x101a35ca8/0x101a35cb4 的 fabs>1800）仍保留为残余。新增耦合观测：
`banner_hash` 与 `splash_creative_id` 同空 128 次、同非空 76 次、仅 splash 空 32 次
（无"仅 banner 空"），二者基本同源（服务端 config）；同一 build 的 `/x/v2/splash/list`
其 `open_event` 取值域为 `cold/cycle/background`，与 feed/index 的 `cold/hot/空` **不同域**。
另：feed/index 现版有**两套参数模板**——47/48 键完整模板（含 open_event/banner_hash/
login_event/inline_*/client_attr/qn_policy/player_net/soft_fnval/autoplay_card/auto_refresh_state/
video_mode/teenagers_age/splash_ids/splash_creative_id/ad_extra/network）与 28/29 键精简模板
（以上 18 键全部不出现）；`ad_extra` 与 `network` 同现同缺，`access_key` 与登录态同现同缺；
观测取值域 `flush∈{0,1,2,5,6,8,14}`、`fnval∈{84948,2448}`、`column∈{2,3,4}`、
`login_event∈{0,2}`（海外组另见 1）、`inline_sound∈{1,2,3}`、`autoplay_card∈{4,10}`、
`force_host∈{0,2}`、`https_url_req∈{0,1}`、`auto_refresh_state∈{1,3,4}`。均为该样本取值，非协议常量。

Swift首页caid又是另一条首次上传链：Marker0x101a3515c检查
hasUploadedCaidSinceInstallation=false才global queue调用BBDeviceInfo.mergeCAIDParams
（0x101a35e0c），再main queue转JSON字符串保存Marker+48/+50（0x101a35ff0）；
MainApi0x101a33a34非nil才写caid，覆盖已有同键。key22无error事件0x101a35058在
flag尚false时先持久置true，再清该Optional；flag已true时不清。异步writer未复查flag，
存在成功事件先于写回的静态竞态可能，不能断言严格恰一次。不是HD firstRequestInfo/
chooseInterest文件。已补实际门禁0x101a35238–24c（旧反汇编截止35200过早），
且merge0x115fd8d78→getCAIDParams0x115fd8dfc是12项本地材料字典：
bootTimeInSec、countryCode、language、deviceName（非空设备名MD5）、systemVersion、
machine、carrierInfo、memory、disk、sysFileTime、model（hardwareModel）、timeZone。
非nil输入mutableCopy后addEntriesFromDictionary，材料覆盖输入同键；首页输入空字典。
本体没有调用CAID标识getter/发网络，不能与另一BBAdCAIDInfo.CAID标识混用。
JSON helper0x101b8cfd0的NSData/UTF8失败均返回非nil空String，Marker仍保存，
MainApi只nil门禁因此失败后可发caid空值；不是失败就省略。系统权限/真实字段值
另取运行证据，此处未读取设备实值（root-static-session/home-caid.md）。

响应 modelDescriptions（0x10df575e4）包括 /data/items（数组、必需）、/data/config
（非数组、可选）、/data/config/auto_refresh_time（非数组、可选）。完整卡片映射、配置
应用及列表本地缓存/过滤/重排不能由单卡converter否证。所选0x101afaab8是纯映射：
0x101afab38 dynamicCast→0x101afab84 yy_modelWithJSON→0x101afabcc BannerV8ViewModel
init；这个body未实现缓存/过滤/排序。已知caller除两BL0x101b4b8d4/bb1c，还有
尾B0x101af571c；nearest ObjC标签不能当Swift真实owner，原“唯一FeedEmptyViewPlugin
调用方”撤回（root-static-audit/recovery）。后续0x101af5a24准备BannerLayout，
不能由converter无排序推广全首页或“重排只可能更上游”。列表业务组装须单独追。

### 首页 VM 的首次请求、重试与响应状态

`BBHD2PhonePegasusMainVM.init`（0x10df58690）按 hasLogin 初始化 login_event：
登录为 2、未登录为 1。账号 action observer 仅对原始 action 值 1/2 更新同一映射；
账号通知分派 0x11605e2d8 已确认 1/2 对应 Login/Logout；该观察者只处理这两类。

loadData（0x10df58a10）在 helper.willFisrtLoad 为真时，以 isNewInstall 设置
isFirstCall；设置 pullType=1、splash_id、列布局、login_event、播放自动播放设置及
FeedStateManager.followState。idx 来自首卡或本地保存的 Pegasus feed index。成功响应保存支 0x10df5969c 要求
卡数组非空、卡0为BBHD2PhonePegasusCardBaseModel，取其idx→savePegasusFeedIndex
0x10df2b6ec→BBHD2PhonePegasusConfig动态偏好setter→BFCPreferences→NSUserDefaults
suite BBHD2PhonePegasusConfig（0x1167d357c写入API）。不把该调用视为磁盘同步成功
（root-static-remaining/findings.md）；VM 的 flush=-555 是内部已派发标志，该值进入下一次 loadData 时先改为 0。
选择兴趣的两个 VM 属性赋给请求对象后清空；getApiOptions 的结果保存为 loadDataOptions。

apiProcess（0x10df58dfc）用已保存 options 创建 BFCApiRequest 并异步发送，随后将
VM.flush 置 -555、helper.willFisrtLoad 置假。错误回调（0x10df59ab8）在 retry 标志为真时
将 retry 改假，读取**原VM当前loadDataOptions属性**（0x10df59d44）再调用
apiProcess（0x10df59d64）。该options不是此请求block强捕获的快照；只有属性未被后续
load改写时才是同一options。这条retry不调用参数builder，不能据此说再次读取消费型
open_event getter，也不能排除后续load替换属性。这是业务层一次额外尝试，不能外推为所有请求
或传输引擎都遵循相同重试策略。

成功回调（0x10df59104）应用服务器配置中的 follow_mode、auto_refresh_time、列布局、
自动播放等属性，置 isFeedReqSuccessOnce；清空 helper.firstRequestInfo，并把
VM.login_event 置 0。converted array非空后取**第一张**卡
（0x10df5969c、objectAtIndexedSubscript index0@0x10df596a8/0x10df596ac），
且isKindOf CardBaseModel才读idx（0x10df596fc），经 DataManager.savePegasusFeedIndex
（0x10df59714）
保存到配置属性（setter入口0x10df2b6ec，写入0x10df2b718）；配置固定suite与默认值见后段，动态Int64 IMP见后段，落盘时序仍待追踪。下一次 DeviceInfo
条件因此会受首次成功状态影响，而不是简单按进程首次请求判断。下一步 = disassemble.py 0x10df2b6ec 0x10df2b72c 核对 setter 与落盘先后；跨启动耗时属运行期，需真机读取。

loadMore（0x10df5a4c0）有正在加载和审核模式分支；另建 MainApi，设置 pullType=0、
flush=8，取末卡 idx、当前布局/自动播放/推荐模式后发送。首次刷新与加载更多的 idx 来源
不同。buildObjects（0x10df5a28c）存在新旧数组合并、刷新卡处理、数量上限及有条件的布局prefix裁剪；
这些是本地展示处理的证据，尚不足以证明客户端执行了个性化算法重排。

### 推荐点击、展示与可见时长的业务触发

旧包同时包含 UIKit HD 与 Swift 实现，以下按实际函数体区分；运行时选择与 9.13
一致性**装配层已闭合（task-36）**：BBHD2PhonePegasusMainV2VC 唯一构造点 = `-[BBHD2PhonePegasusVC buildVCUseCurrentVC:]` 0x10df1a030——0x10df1a0a8 载 classRef 0x11f7c99e8→`objc_alloc`→`initWithMainVM:`（0x10df1a0d0）→addChildViewController，整条路径**无条件**（0x10df1a04c 的 cbz 仅处理已有 mainVC 复用），装配层**无配置分支**选择 Swift 替代 VC；classRef_0 0x11f7f8ce8 其余 16 处加载点全在 MainV2VC 自身生命周期方法内。残余=运行期是否另有 Swift 首页替换路径、与 9.13 一致性属运行期/跨版本事实，需 9.13 抓包或真机断点。MainV2VC.didSelect（0x10df3e318）对 bangumi_rcmd 卡路由后调用
HomeData.reportCardClick；其他卡走 superclass（0x10dee967c）。super 在实际 cell
支持 jumpDetail 时调用该方法，另行处理广告 click；只有 cell 的 **精确类名**属于
LargeCoverV1Cell、SmallCoverV1Cell、SmallCoverV9Cell、SmallCoverV5Cell 白名单
（0x10df18c40）才调 HomeData 点击报告，不是按继承关系匹配全部卡。

HomeData 通用报告器（0x10df30fd8）要求 ReportProtocol，actionType=1/2 分别建
Click/ExposureEvent，事件名由 from_spmid_v2/neuronEvent/submodule 与 click/show
拼接。22 个默认扩展键为 event/style/param/title/goto/sub_goto/sub_param/page_from/
page_id/from_type/state/up_id/rid/tid/type/track_id/converge_type/extra_info/card_type/
card_rel_id/card_material_id/position。字符串 nil 退空，args 的数值转十进制；
track_id 优先**非nil** report_args.track_id（空串也保留），否则 report_track_id；position 取
report_flush_idx。extraDic 最后覆盖默认值。track 后还发旧链 001365，并清
report_click_position；两个通道不能作为同一事件重发统计。
逐寄存器补证：click wrapper0x10df30338给neuronEvent=main-card、submodule nil
（字符串0）、action1/privateEvent=card_click，所以ID是
`[from_spmid_v2].main-card.0.click`（0x10df31728–0x10df31784）；from_spmid_v2
本体没有显式nil fallback。style只在page_from严格字符串1时取
FormatManager.getPegasusStyle（0x10df3109c/0x10df310b8）；page_from是
Config.reportPageFromForPage(model.page_from.integerValue)，type固定traffic。
param/title/goto/sub_goto/sub_param/from_type来自对应report_* getter；state来自
caller，up_id/rid/tid来自report_args十进制，converge_type及extra_info也来自args，
后者yy_modelToJSONString；card_type/rel_id来自report_card_*，material_id非零转
decimal否则空。22字段base在0x10df315a4，extra覆盖0x10df316b8。
随后001365用numeric String key0..13另组14字段：privateEvent/style/report_param/
report_title/report_goto/report_sub_goto/report_sub_param/mapped page_from/page_id/
report_from_type/privateState/args.up_id/rid/tid（0x10df317d8–0x10df31a2c），
重新读getter且不合extraDic，不能把22字段直接复制给旧链。

BaseEvent.initWithId（0x1161eebb4）设 logId=001538、pageType=1，Click/Exposure
没有在这里另行覆盖初始化。track（0x1161eea60）转 Neuron policy=0，trackInstantly
（0x1161eeab0）转 policy=1。HD real show（0x10df3083c）单独构造
`tm.recommend.feed-card.0.show` 并 trackInstantly，九个默认键为 card_type/card_goto/
goto/param/track_id/position/card_rel_id/card_material_id/is_background，extraDic
仍覆盖默认值；不能把它与上述通用 show 的全部字段合为一个固定表。
real-show track_id则要求args.track_id.length>0才使用，否则report_track_id
（0x10df308c4–0x10df30910）；card_goto取card_goto、goto取gotoType、param取
report_param，card_material_id仍非零decimal/否则空。getAppstate0x10df31b44每次
读UIApplication.applicationState，raw0/1/2分别映射String2/3/1，其他空；
is_background不是Bool，也不能据字段名写固定后台值。

HD MainV2 exposureRatio=visible_area/100，isRepeatedExposure=false；manager.enabled
受 isShow 与 splashStyle==0 控制。BBListExposureManager（0x103eb3744）检查
enabled/rootView、可选 throttleInterval 与可见 cell/subview。单项检查 0x103eb523c
要求非空 identifier、view 存在且未 hidden、alpha>0、有 superview、非空 bounds 与
intersection；可见比例为交集宽/自身宽×交集高/自身高。比例 >= item/delegate 阈值
才 exposedIn:item 并加入 identifier pool。HD identifier（0x10df31ba4）包含
时间戳/track_id/flush_idx/Appstate；普通离开不会按重复曝光机制清池，全部重置
调用方仍在追踪。

Swift RealExposure 的 durationDelegate 见证表 0x11b173da8 与 weak setter
0x103eb7410→0x103eb74f4 已核对。ExposureV2.Manager raw policy=3 时，visible
比例 >= startRatio 才建 Context 并保存 Date.now；已有 Context 在比例 < endRatio
时移出池并结算（等于阈值仍保留）。结算 0x103eb9998 要求 elapsed>=minimum，
通过才调用同一见证表的 duration 回调。hidden/空 view 或交集也有结算路径；
其他 policy 与完整池生命周期**部分闭合（task-36）**：池遍历仅 3/4/5 三支结算——0x103eb83d8 `cmp #5`（delegate conforms 门禁）、0x103eb8420 `cmp #4`（直接）、0x103eb8558 `cmp #3`（字典池）；#1/#2 是 retain/release 辅助而非策略。残余=policy 0/1/2 与服务端下发分布（运行期）；
下一步 `$PY disassemble.py 0x103eb7000 0x103eba000` 枚举 policy 立即数并逐支回溯入池/移出池写者。
后台 observer 的枚举值已用 field descriptor 和 Dispatcher 双重核对：
raw36=willResignActive、raw33=didEnterBackground、raw37=willTerminate。
RealExposure 的 raw36 handler（0x101b60ab0）受 durationRematchEndWithNonActive
控制才结算；raw33（0x101b60b18）与 raw37（0x101b60b70）都调用结算
0x101b60e7c→Manager 0x103eb9294。raw3 项先从池移除，再走同一 minimum
检查及 duration 回调，不能把进入后台视为仅暂停检查而保留未结算时长。

RealExposure 从 MainConfig 读取 exposure_duration_start_ratio/end_ratio，缺失或类型
错误各默认 0.8；exposure_duration_min_ms 读 Int 后除以 1000，默认 0 秒。普通
展示比例 visible_area/100 默认 0，与时长比例不同。Memex 的
pegasus.pgs_expose_check_interval 默认 Float=0，不能写成固定 0.3 秒检查周期；
durationRematchEndWithNonActive 默认 true，消费路径见上述 raw36 handler。
回调 0x101b6cf80 复制扩展字典，将两端 DateUnix×1000 有边界检查地向零截断为
Int64 十进制 card_start_time/card_end_time，再发
`tm.recommend.feed-card.duration.show` / policy=1，未单独添加 duration 秒字段。

首页离开也有具体duration结算入口：VC.viewDidAppear0x101a37618与
viewWillDisappear0x101a37628在super之后publish raw2/3；lazy创建的同一MainVM
在0x101a36540注册listeners，raw2/3分别经0x101a5cb98/0x101a5cbb4写
isShowing=true/false（0x101a4a114）。_checkReallyShow0x101a4a274用
isShowing && BFCSplashManager.splashStyle==0，只有真实显示状态改变才publish
raw7/8（viewRealAppear/viewRealDisappear）。RealExposure监听raw8的callback
0x101b60644先做可选manager check，随后无条件调用0x101b60e7c结算并移除duration
contexts，仍受前述最小时长门槛。因而已有duration在实际离开时结束，返回之后再建
context，不是暂停后累计；show identifier 全局去重池是否重置未解码（0x101b60644 起的结算/移出池写者；若为进程内单例池则
属运行期状态）；下一步 `$PY disassemble.py 0x101b60644 0x101b60f00` 反汇编结算/移出池写者
并回溯池 reset 调用方。
【9.13 抓包观测（DerivedData/Validation/capture-resume/full-exposure-events.json、
full-click-events.json、revisit-events.json、revisit-finish-events.json）】手动刷新与跨时间
重访会话中，`tm.recommend.feed-card.duration.show`（policy=1 通道）与
`tm.recommend.feed-card.0.show` 均对新一批卡片重新上报；duration 事件样本 extraKeys 含
position/card_start_time/card_end_time/tm_card_play_state/event_policy/track_id/card_goto/
card_type 等，与上文两段 DateUnix×1000 字段一致。这只证明事件跨刷新/跨会话重复出现，与
"普通离开不清池"的静态结论相容，不构成去重池被 reset 或其生命周期的证明；池语义残余保留。

【9.13 抓包观测（线级，team-c12；build 91300100；证据 DerivedData/Validation/team-c12/
neuron-events.jsonl，RDIO + protobuf 解码，含 gzip）】全语料 `tm.recommend.feed-card.0.show`
1,269 条、`tm.recommend.feed-card.duration.show` 2,194 条。按 (param, track_id) 统计：
`round2/watch_events_official.flows` 的 712 条 show 只对应 561 个不同 identifier，123 个重复
（最多 6 次），其中 **39 个跨 feed 刷新重复、84 个在同一刷新间隔内重复**；但把
`position`/`is_background`/`event_policy`/`card_material_id`/`tm_card_play_state` 一并计入键后，
全语料只剩 **11 组** exact-dup（4 组跨刷新，占比约 0.9%）；这仅是扩大统计键后
重复减少，不证明真实池lookup包含这些字段，也可能是owner替换/reset/可见周期不同；`is_background` 取值 `{2,1,3}` 分别为 1076/141/52（同一 track_id
常以不同 is_background 各上报一次）；`event_policy` 在**本次 9.13 线级样本**的全部 show 与 duration 上恒为 `1`，
`tm.recommend.0.0.pv` 亦恒为 `0`（均为该批样本取值，不等于协议常量）。这既证明"同 identifier 可跨刷新/同批次重复上报"，
不能据wire相关性确定去重键。所选V2池实际lookup按Item identifier；appearance条件重建
与raw8 duration settlement原指令已分别补证（home-exposure-findings.md），不能套用
静态8.89到9.13或以尚未定位的显式+90 caller说完全没有reset正例。
raw7则走0x101b60494的条件检查，不能把显示事件本身等同于已产生曝光记录。
apply completion0x101a44530另发布feedDataChanged raw24，包含账号empty Diff应用。
RealExposure订阅该事件，经0x101b6070c排main.async再进入0x101b60900；它忽略
Diff payload，读取执行时的共享provider/config，要求config非nil、witness+0x38
BOOL为true、manager非nil，才调用Manager.check。这不是直接全池reset。
具体check0x103eb78e4要求enabled==1且rootView存在；已有上次check时还要求
elapsed超过delegate throttle，无delegate则elapsed>0。未通过时保留旧状态。
成功收集当时可见items后，静态比较配置0x12044e608唯一元素为2，选择
0x103ebaddc计算old items减current items；按identifier匹配，不按位置/账号/模型身份。
departed项policy原值3（或5经delegate解析为3），identifier非nil且池中有context时，
0x103eba88c移除该context，再由0x103eb9998执行前述最小时长门槛及duration回调。
最后更新_lastCheckExposeItems。因而账号清空后成功check若实际可见items为空，
可以结算旧duration，即使header refresh被loading挡住；仍保留UI/config/节流/上下文
存在与多实例归属的门禁，不把每次raw24当作无条件结算或运行时空可见集证明。

Swift 普通 show（0x101b6b8c8）的 position 在配置字节 0x12106a631 为 true 且
模型 OptionalInt 非 nil 时直接取模型值（含 0）；其他情况调用 MainEventOperator.flushIndex，
此事件 builder 没有额外 +1。VC 初始化 0x101a366a8 实际绑定该 closure；实现
0x101a4e914 按卡片 uniqueID 字符串查 VM.cards，读取匹配模型 OptionalInt，
不符合协议/未找到/nil 都退 -1，不是 UICollectionView 行号。另一个只返回字典的
builder 0x101b6d3ac 在 fallback 后 +1，模型直接分支不加。具体 SmallCoverV2Cell 的
ItemsContainerProtocol witness 0x11b16f5b0→0x101ac6554 已闭合 duration 分支：
它调用专用同规则 builder 0x101a7b6a0，将字典赋给 receiver，按 raw policy=3
构造 ExposureV2.Item（0x101ac6884），最终进入上述时长结算。不能把所有时长
position 归为无条件 +1。SmallCoverV2ViewModel 的 OptionalInt getter/setter
（0x1035a2400/0x1035a2540）使用 associated object 键
BBListPegasusSettings_flushIndex，不应仅称为直接解码的服务器字段。
DataFactory 0x101a3e5a4 遍历 **compactMap 输出**的 `[BBPegasusSwift.CardData]`（元素 stride 8，
0x101a3e7e4/0x101a3e7e8 `ldr x19,[x22,x26,lsl#3]` +0x20；输入即 0x101a4340c 的转换结果，
转换失败的项不占号）。每轮先 0x101a3e95c `add x26,x26,#1`，再把该 1-based 序号作 x0 传给
CardData 的协议见证 witness 表 +0x40（0x101a3e978 `ldr x22,[x1,#0x18]`、0x101a3e98c
`ldr x28,[x22,#0x40]`、0x101a3e9b0 `blr x28`，x1 由 0x101a3e84c/0x101a3e960 的 `sub_101A3B8FC`
只做 `_swift_beginAccess` 得到）；该调用以 CardData 的 ivar +0x20 非 nil（存在 report model）为
门禁（0x101a3e808 `ldr x20,[x19,#0x20]`、0x101a3e974 `cbz`），但**递增无条件执行**，
所以没有 report model 的条目仍占号。见证表取自 CardData ivar +0x20/+0x28 的 existential，
被调用的具体 requirement（从而最终写入 position/flush_idx/report_flush_idx 哪一个）
属间接派发，本轮未闭合（见残余 R11-2）。异步 setup 0x101a3e1dc
在编号前调用 0x101a4340c compactMap，逐字典转 CardData，转换返回 nil 的项先丢弃，
成功数组才进入 0x101a3e5a4。转换 0x101a3feec 拒绝空字典、缺失/非 String card_type、
未识别 card_type 哨兵 raw0x29、缺少 provider，以及需要但不存在的 operator。
解析函数 0x1018bb498 在返回前将 unsigned index<41 的值保留，否则返回41；
reflection 共41合法 cases，unknown 为0，因此41不是一个合法的 unsupported case。
MainApi completion（0x101a340c0）从 /data/items cast 到 [[String:Any]]，缺失/类型
不符退空；**该函数的完整键序与回执形参已逐指令读出（本轮）**：按
`/data/config`（0x101a34130，小字符串立即数 x24=0x6f632f617461642f + x23=0xec0000006769666e，
判别位 0xEC=0xE0|12 → 12 字节）→ `/data/interest_choose`（0x101a342a4，Swift 字面量
0x1178959c0）→ `/data/items`（0x101a34340/0x101a34358，判别位 0xEB=0xE0|11 → 11 字节）
顺序取值，每次 `sub_10002943c`(字典查找，返回 w1=命中位) + `sub_10002a2f8`(取元素)；
最后 0x101a343c4–0x101a343d8 以 **x0=items、x1=config、x2=interest_choose、w3=0** 调
completion（`blr x19`）。三处缺省值不同：config 走错误分支并把 x22 留在
`sub_100060E24(__swiftEmptyArrayStorage)` 的结果上；interest_choose 丢命中时 x23=0（nil，
0x101a3432c）；items 丢命中/类型不符时 x24=`__swiftEmptyArrayStorage`（0x101a343bc）。
config 缺失或类型不符（0x101a3413c `tbz` / 0x101a34184 `tbz`）不是终止：0x101a341d0–0x101a341e8
构造含 `config` 键的字典后经 sub_104E4AA7C（0x104e4aa7c，`[BFCMikoto trackTech:extendedFields:policy:rate:]`，
selref 0x11f765ec0）打点，事件名是 26 字节字面量 `list.pgs.tech.error.config`
（0x117895980，x0=0xd0000000000015+5=0x1a 即长度 26），policy=100、rate=0；随后继续
interest_choose/items。0x101a5bcc0→0x101a55f8c 将数组交原 callback。正常 loadmore
0x101a52dbc 的 callback 0x101a5c1e4→0x101a55250 将同数组交 DataFactory
0x101a42b64；同步分支用同一个 compactMap，再从1编号，异步分支进入上述
0x101a3e1dc。故这条网络 loadmore 的编号按成功 CardData，不保留失败的原始
输入空洞，也不是累计显示行号。refresh callback 0x101a5bc64→0x101a55004→
正常refresh在error-tag=false时更新VM.config（0x101a5b554 `ldr x24,[x25+0x900]` 后
`str x28,[x25,x24]`），调用interestChoose/rawitems helper0x101a538d8；helper=true走单独
兴趣选择render而不进入0x101a53fd0，helper=false且额外CardData为空才走普通编号链。
**调用点与两支语义已逐指令读出**（0x101a5b544–0x101a5b9a0）：
0x101a5b608 `bl 0x101a538d8`、0x101a5b60c `tbz w0,#0 → 0x101a5b674`。
true 支（0x101a5b610–0x101a5b670）：0x101a5b614/0x101a5b618 把
`MainViewModel.isLoading`（ivar slot 0x1203518e8）写 0，0x101a5b620/0x101a5b62c 取包内
Swift 元数据串 `isLoading changed`（0x117896320）与 `refresh success interest with false`
（0x117896340），0x101a5b63c–0x101a5b648 组装小字符串 `Pegasus`（判别位 0xE7），
0x101a5b664 调日志体 `sub_101B51630`，0x101a5b670 跳到公共出口 0x101a5b994。即该支
只做"结束 loading + 记一条 interest 刷新日志"，不在调用方继续构造卡片。
false 支（0x101a5b674 起）：0x101a5b674 `lsr x8,x26,#62` 判 rawitems 的 tagged 形式，
0x101a5b680 `and x8,x26,#0xfffffffffffffff8` 后取 +0x10；0x101a5b968/0x101a5b974 用
`_CocoaArrayWrapper.endIndex.getter` 取元素数，**非 0 → 0x101a5b690/0x101a5b69c 调
sub_101A5AB5C（x0=rawitems、d0=d8）；为 0 → 0x101a5b980–0x101a5b990 以
(x0=rawitems, x1=VM.config, w2=1) 调 sub_101A53FD0**。因此"普通编号链"的真实入口是
sub_101A53FD0 且仅在 rawitems 为空时进入，与文档前文所写一致。
**两处订正**：（1）0x101a5b990 是本函数的 `bl sub_101A53FD0`，不是"将同数组交
0x101a40c40"；（2）0x101a40c40 是取 `type_metadata_accessor_for_Date` 的 5 参函数
（0x101a40c7c/0x101a40c80），把它接到这条编号链需要重新取证。
**重编号范围**：0x101a5b980 传入的 x1=VM.config、w2=1 之后再无下标参数，编号范围取决于
sub_101A53FD0 内部循环；该函数体内未见 `add …, #0x1` 后直接写卡片的模式
（grep 0x101a53fd0.asm 无命中），故"从1编号"落在其被调卡片构造里，属精确残余
（下一步：`$PY disassemble.py 0x101a53fd0 0x101a55004` 后按 `sub_101A5AB5C`/卡片 model 的
pos setter 反向追）。
网络refresh wrapper0x101a55004显式传空额外数组，不能将兴趣选择分支外推为同一render。

兴趣响应有独立的共享状态链：MainApi从/data/interest_choose取dictionary
（0x101a342a4/0x101a342ec），类型不符退nil。VM helper0x101a538d8要求非nil、
非空，依次调用InterestManager的!hasShown、processJson/cards、fake-card门禁
（metadata0x11fde2d98的+0x188/+0x1e8/+0x190）。这不是另外的isRequestEnabled
新安装/preferences门禁。process0x103c74660在model解析前已经将source置raw1
（0x103c7468c）并替换共享tmpPegasusCards（0x103c746b0），因此拒绝模型也可能
改变临时卡片。支持style为17、22、23、24、26–38，且!hasShown时才prepare；
prepare0x103c74cf4遇已有model立即返回，process仍可返回true。已有token直接
显示，否则借BBSerialGroup.addEvent排队。fake-card门禁0x103c73dc4对35–38返回
false，32返回!isLowActivityScene，其他样式或nil model返回true；经理处理/显示
与是否替换首页卡片是不同条件。
另一个启动消费者MainVM setup0x101a49e68调用metadata+0x180的
isRequestEnabled0x103c73c7c：!hasShown且（isNewInstall为true，或
InterestPreferences.disableActionOpenHomepage=true且hasSubmitedInterest=false）。
BFCAppPreferences.shared为nil时走非new-install分支，不直接返回true。
true时调用manager的metadata+0x1d8方法0x103c74308
（0x101a49eb8/0x101a49ec4），注册BBPegasusLaunchTransactionProtocol item并保存
返回token（0x103c743c0）；false改走showOverseasAgeGateIfNeeded0x101a49ee8。
这闭合的是launch transaction的本地启动门禁，不能直接当作推荐HTTP字段或把它
替换为上述响应消费的!hasShown门禁；具体请求及后续状态见下一段。
launch item的scene0x103c763b4为raw2，process0x103c766fc→0x103c763bc置source=0，
把空String字典交统一interest builder0x103c6e0d0（0x103c764b4）。该builder请求
https://app.bilibili.com/x/v2/feed/index/interest，requestMethod raw0（公共builder默认GET）
（0x103c6e13c/0x103c6e17c），与首页feed响应中附带interest_choose是不同入口。
自有参数顺序为非空manager CAID→caid；cny_info JSON String；合并调用方字典；
最后条件性dp_status。调用方字典同键覆盖caid/cny_info，但生成的dp_status后写覆盖
同键；本launch caller给空字典。没有读取或保存实际CAID。
cny_info始终由两键对象生成：cny_active=TabDisplayManager.isCnyTabDefaultSelected
的Bool转Int，ab_test_vars=cnyAbTestVars字典（nil→空）；helper0x103c6f200用
NSJSONSerialization options0及UTF8，失败返回空String，不请求sortedKeys。
这也闭合上文T10 click数组/字典转String的JSON格式，不保证字典键稳定序列。
builder每次先递增进程counter0x120442df8，再取BFCLauncherContext.hasAction；
hasAction=true且count1→dp_status="1"，count2→"2"，其他省略（0x103c6e4d4–528）。
该值捕获到completion，不是账号epoch，也不代表HTTP已经成功发出。
modelDescription三条optional/nonarray路径为/data/interest_choose、
/data/config/close_small_window、/data/config/interest_popup_logic_exp；安装
completion0x103c6e868/error0x103c6e8e8后requestAsync0x103c6e900，未在此body设置
timeout/auth/cache/responseQueue，也未把request存manager ivar，公共默认仍适用。
回执0x103c6d610先消费config：close_small_window Int1→自动小窗helper
0x104b1ae2c，2→自动PiP0x104b1ae04，3两者；对应helper先检查手动操作标记，
已手动则return，未手动才setIsAuto*Enabled(false)（0x104b1ae40–0x104b1ae98）。
interest_popup_logic_exp Int先写共享manager。随后captured dp_status=="1"直接
success(nil)并discard兴趣内容（0x103c6d7bc–0x103c6d838），不parse/prepare，
不能把此主动discard归因为防旧账号回执。其他dp_status才解析InterestModel；
成功先写固定suite的disableActionOpenHomepage，再用model非nil的
interest_popup_logic_exp覆盖config实验值，最后success(model)
（0x103c6d930–0x103c6d9b4）。解析缺失/失败也是success(nil)，不走errorhandler。
launch success0x103c74508还检查showOverseasAgeGateIfNeeded/model/style/hasShown；
拒绝或HTTP失败走finisher0x103c764f4：发Unavailable通知（message="error"），
取manager当前transactionToken.done（0x103c766a0）后清token（0x103c766d4）。
这里没有request-owned token一致性或账号epoch门禁。具体token.done
0x113c3c018转operator.finishItem0x113c3c2d8移除item，再start下一个item
（0x113c3c338）；accepted prepare 本体未见对应 done/clear，外围完成**已核对为纯间接派发（task-36）**：finishItem 0x113c3c2d8 尾调 `msgSend$start`（0x1176a0a20），完成块 0x113c3c018 经 `msgSend$finishItem:`（0x113c3c054）；三者 find_callers 均空（派发方式所致）。launch finisher done 仍是唯一静态可见完成点，剩余需运行期断点。
同一builder另有guide入口processWithGuide0x103c7489c：hasGuideShown已true直接
返回，首次先置true（0x103c748c8），后续guide action0x103c74bac带静态
{"action":"1"}、source raw1进入builder（0x103c74c00/0x103c74c74）。
它与launch共享上述counter/参数和config消费，但其error callback0x103c7465c
及success捕获的finisher0x103c74ca0均为bare ret；不能把全部interest请求失败
都写成launch的Unavailable/token.done。物理actionButtonDidTap0x103c7226c
选择actionClosure，common helper0x103c722a4在track/dismiss之前调用closure
（0x103c722ec/0x103c72318）；manager创建guide时将0x103c78cd0存为action
（0x103c74b00），thunk直接转0x103c74bac，因此上述action="1"有UI来源。
close按钮选择独立cancelClosure，不经过该网络action。
cancel closure0x103c78cd8取manager另一个serial token.end（0x103c78cfc）并清
该token（0x103c78d04），不是上述launch transactionToken.done。
prepareIfNeeded0x103c741f8另经background helper0x103c75c60/0x103c75f2c，
调用BBDeviceInfo.mergeCAIDParams(empty)（0x103c76028），再排main closure将
JSON String存manager.caid（0x103c7621c/0x103c76240）；该入口本体不直接请求，
已读链没有launch等待CAID完成的同步屏障。完整manager有界范围
0x103c73950–0x103c76724及token.done/finish/start链中，accepted prepare与dismiss
均未见显式done；外围动态完成仍未知，不能据此宣称事务永不结束。

二次兴趣有独立builder0x103c6e96c，URL为
https://app.bilibili.com/x/v2/feed/second/interest，requestMethod raw0。
参数为可选非空manager.caid；interest_id=model.unique_id的Int64十进制；
interest_result=传入String；interest_type=传入Bool true→half/false→full；
device_type=固定suite BBPhonePegasusConfig中stringForKey
isFeedReqSuccessOnceSinceInstallation的原String，缺值→"0"
（0x103c6ecd8–0x103c6ed9c）。该字段不是硬件型号；此builder不递增index counter，
没有cny_info/dp_status或任意调用方字典合并。optional/nonarray描述路径为
/data/interest_choose及/data/config/close_small_window；requestAsync
0x103c6f0a0未设置自有timeout/cache/auth/responseQueue或manager持有cancel。
回执0x103c6dbdc只解析interest_choose，经YYModel与nested-model归一化
0x103c77974后success(model)，缺失/失败success(nil)。该body没有消费
close_small_window，也没有index parser的disableActionOpenHomepage/popupLogicExp
写入或dp_status discard，不能把两个endpoint的响应策略混为一条。
其中device_type标记默认在LocalPreferences.defaultConfig0x101b8aa78以Bool false
初始化（0x101b8ab10），配置名固定BBPhonePegasusConfig。首页已有nil OptionalError
成功链0x101a34fcc→0x101a35058先读该标记，false才set true（0x101a35108）。
二次兴趣却用NSUserDefaults.stringForKey读取；不能把系统对Bool→String的行为
写成IPA内显式编码，未实际读取此suite。
T37实际caller0x103d86e74要求model非nil且style37；其他style仅本地展开。
_isRequesting=true时返回，否则先置true，再将选中sids commajoin交builder
（0x103d86f3c/0x103d870c8）。
SID helper0x103d858a8保留selectedItems数组顺序：Item.sub_items为空时用Item.id；
非空时按selectedSubItems数组顺序筛weak SubItem.item.id匹配parent id，生成
parentId.SubItemId（0x103d85c64–0x103d860d4），没有匹配项则不回退parent-only id。
之后追加gender/age再commajoin，无id排序/去重。S2 didSelect0x103d96fe4→0x103d968fc
按NSObject equality搜索已选SubItem；新选追加尾部，取消稳定移除，重选移到尾部
（0x103d96a58–0x103d96a8c），不能根据展示网格顺序推断编码顺序。
interest_type Bool来自共享manager.source，
raw1→half，已读raw0→full；不是屏幕尺寸。callback context捕获原model，同时保留
weak查找box与strong原T37View；不能描述成仅弱持有UI。
success/error context在0x103d8701c/0x103d8705c存weakbox与strong原view，原view
retain于0x103d87074/0x103d8708c；completion Block copy后retain业务context
（0x103c6efdc/0x103c6efec）。thunk0x103d9f57c只转发到body，析构
0x103d9f588才release strongview（0x103d9f59c）；parser调用业务callback前未释放
context。因此这条持有链保留原view到callback body，而weak读取不提供账号归属隔离。
物理首屏_confirmButtonDidTap0x103d87d9c直接调用此入口（0x103d87db0），与
S2最终确认0x103d97798→0x103d8a940不同。
成功0x103d87134先安排main now+0.5秒清_isRequesting
（0x103d87258/0x103d87370→0x103d875f4），nil response随后直接返回。
非空items先在原view仍存在时写absoluteModel，再无条件向共享manager写response
（0x103d87418/0x103d874d8–0x103d87508），之后才弱gate原UI更新。
weaknil分支结构上仍写共享model，但strong原view双捕获不能证明请求持有期内会
自然析构；无request/account epoch或current-model比较，跨账号实际交付属**运行期账号切换行为、
静态不可定**（需真机/运行时复现，本轮不执行）；下一步可 `$PY disassemble.py 0x103d87400 0x103d87600`
复核写共享 manager 段是否有漏读的 epoch 比较。
空items构造NSError domain interest.second.api.items.empty、
code -1234，回退捕获的原model并reload/report。network error0x103d87648则立即
清_isRequesting，可转NSError才原model fallback/reload/report。延迟success clear
只弱取原view，没有请求身份门禁，不能写成取消或自有loading token。

T37原始selection物理入口0x103d8dd88→0x103d87dc4：gender/age替换所选index，
同index早退；Item以NSObject equality查已有选择，新选仅在当前数量低于正值
select_num_limit时追加尾部（≤0用Int.max），达到限制只toast；取消稳定移除
（0x103d88050–0x103d8814c）。取消parent后按parent id删除匹配子项，weak parent
nil的子项保留。S1物理selection0x103d92930→0x103d92208沿用相同限制/追加/
稳定移除，但child清理修改弱delegate原T37View的selectedSubItems，原view失效
时跳过child清理（0x103d923e4–0x103d92434）。这些局部变更不直接发HTTP。
S1 confirm0x103d92d60弱delegate有效才交父helper0x103d87740；该helper先筛当前
children，只保留weak parent非nil且与incoming selectedItems中某个NSObject-equal
者，再按原顺序复制incoming父数组（0x103d87788/0x103d877cc）。这个过滤与取消
parent时的id比较/nil保留规则不同，不能统一成一类选择清理。
选中父项sub_items总数为0（包括空父数组）时，直接调用最终Confirmed builder
0x103d8a940、dismiss raw1、立即setHasSubmitedInterest:YES
（0x103d87898/0x103d878c4/0x103d878f4），不创建S2或在此请求second HTTP。
总数>0只保留有sub_items的父项、保持父项顺序，helper0x103d898b0构造S2并传
当前model/父数组/保留children。S2 configure0x103d95958分别存这三项
（0x103d9598c/0x103d959b0/0x103d959e8），未见自动追加默认选中child；不能把
展示子项等同用户已选。configure完整body至0x103d95c48只retain这些输入，未
deep copy或reset曝光flag；随后readiness0x103d95c28，再菜单show helper
0x103d97adc（0x103d95c2c）。后者要求model存在且show_skip_three_point字节
恰1（0x103d97b08/0x103d97b1c/0x103d97b20），发three-point.0.show
（0x103d97ccc）三String style/unique_id/strategy，没有hasShown/_isExposed
门禁；每次eligible configure都安排该事件，不套用子项一次曝光规则。
T37首屏parent Item曝光独立willDisplay0x103d8de8c→0x103d9d094：raw section
0/1是Gender/Age，其他取current model.items；Item._isExposed
（ivar0x120443a70，0x103d9d264/0x103d9d268）为true省事件。false发
interest.0.show（0x103d9d920）六String interest_name/interest_id/pos/style/
unique_id/strategy，没有S1子项字段。pos用current model.items的NSObject equality
search0x103d810d0（0x103d9d74c），first match+1/missing0
（0x103d9d760–0x103d9d768），不是物理index或absoluteModel。track后同Item置true
（0x103d9d940）。Item.init0x103c799e4→0x103c79910置markerfalse
（0x103c799bc），blacklist0x103c797d0静态array0x120442fd8仅_isExposed；
customTransformFrom0x103c79908只返回true，没有reset。动态setter0x103c797c0
仍可写 Bool，其他重置未穷举；下一步 `$PY find_callers.py 0x103c797c0` 与
`$PY disassemble.py 0x103c79908 0x103c79a00` 枚举写者/consumer。T37数据选择→编码顺序与首屏/second/S1/S2提交边界
已配对，具体响应对象是否重用须逐 consumer 判断（属对象复用，静态只能给候选）。
T37 S1 parent show也独立willDisplay0x103d9293c→0x103d9e350，取S1.items
物理item对应Item，flag0x120443a70 true时省事件（0x103d9e3d8–0x103d9e3dc）。
false发同六字段interest.0.show（0x103d9e6d8），track后同Item置true
（0x103d9e6f8）；pos取S1.items equality search（0x103d9e50c）first+1/missing0，
不是原页面物理位置。configure0x103d91b18直接retain同model/items
（0x103d91b44/0x103d91b68），完整body至0x103d91dcc只菜单/text/button/reload/
readiness0x103d92e28，未自动选parents/deep copy/reset marker。
second-error fallback0x103d88f60使用captured原model.items，因此首屏已曝光的同Item
可压掉fallback S1 show；换view不等于换对象。成功response的新对象分配仍属parser
边界，不能据此声明全局无dynamic setter/reset。
S2 readiness0x103d97880→mapper0x103d9c69c为每个display parent检查其
sub_items与selectedSubItems是否有NSObject-equal交集
（0x103d9c760/0x103d9c870/0x103d9c8a4/0x103d9c8e0）；任一匹配返回true，
空或穷尽返回false。true数量恰等display parents.count才setEnabled
（0x103d979b8/0x103d979d8），不是min_limit/parent ID门禁；程序态空parents的
0==0也可启用。该检查不修改选择或曝光标记。
S2 child show独立willDisplay0x103d970bc→0x103d9e988：先从current S2
model.items逐parent取sub_items，按原序flatten全部children
（0x103d9ea54–0x103d9ecc4），无sort/dedup/无子项时父ID替代。随后读
same display child._isExposed（0x103d9ede8/0x103d9edec），false才发九String
interest.0.show（0x103d9f258），track后同child=true（0x103d9f284）。
interest_pos为display selected parents数组的first NSObject-equal位置+1/missing0
（0x103d9ef34–0x103d9ef7c）；sub_interest_pos为上述**全model扁平child**数组
的first equal位置+1/missing0（0x103d9f088–0x103d9f0cc），不是组内物理item。
flatten在flag门禁前，重复show被抑制也先执行数组构造；同SubItem跨页/重建保留
marker的结论依赖对象复用，不推广成相同数字ID自动去重。
S2 child click不使用show的扁平位置：实际mutation后reload
（0x103d96ad0）、readiness（0x103d96ad8）再发十String interest.0.click
（0x103d96f10）。parent pos仍为display selected parents的first equal+1/missing0
（0x103d96bdc–0x103d96c20），child pos却在**display parent.sub_items**中找
tapped child（0x103d96adc/0x103d96d20），first equal+1/missing0
（0x103d96d34–0x103d96d64）。因此第二组以后show/click子位置可不同，不能
共用一个位置公式。action select/cancel来自实际append/remove；无曝光flag门禁
或child click weak-parent门禁，九个共同字段外加action_type。

其他style不可套用T37的请求中门禁。T35物理confirm0x103d6c1c4→0x103d6b5b4
只有model.style35走同second builder（0x103d6b7c0），其余本地展开；同source
raw1→half/raw0→full。完整admission body到0x103d6b808未见_isRequesting读写或
owned request cancel，按钮交互层门禁未在本函数出现；是否存在重复 tap 并发属**运行期交互行为、
静态不可定**；下一步 `$PY disassemble.py 0x103d6b5b4 0x103d6b820` 复核有无漏读的守卫字节。
成功context0x103d6b740同时存weakbox/strong原view，0x103d6b744存原model；error
context0x103d6b760也强捕获原view/model。因此不是仅弱持有UI，weaknil只作结构
分支记录。成功0x103d6b824 nil response直接返回；非空items先弱gate原view.absoluteModel，
随后即弱view失效也写共享manager.model（0x103d6b8c4/0x103d6b8f4），再弱gate
原UI/reload；没有T37的0.5秒清loading，也未见账号/请求身份比较。
T35 lazy confirm按钮0x103d67ce0→0x103d77b88→0x103d73ad4直接addTarget
_confirmButtonDidTap/ControlEvents raw0x40（0x103d73d5c–0x103d73d74），未见Rx
throttle。已闭合selection-readiness helper0x103d6a87c：非style35要求已选数量
≥1且≥select_num_min_limit；style35要求实际呈现的gender/age section已选index
≥0，缺title/空section作为neutral，最终AND设enabled（0x103d6af00）。已读请求/
回执/error未按in-flight disable；这些只是有界静态按钮链，不排除外部交互限制。
T35空items构造interest.second.api.items.empty/-1234，HTTP error可cast NSError
才同样回退捕获原model、reload并经0x103d6bf50报告
main.interest-select.client.0.show（0x103d6c194），五个String字段style/unique_id/
strategy来自原model、code/msg来自NSError；不是使用非空响应model或提交成功事件。

T18/T19的physical second路径又有不同payload：T19 confirm0x103d24370→
0x103d23ba8调用sids helper0x103d22568时传Bool=true（0x103d23be0/0x103d23be4），
跳过selectedItems reducer和selectedMixedItems，只顺序追加符合title/非空数组/
selectedIndex≥0条件的gender.id、age.id（0x103d225a0–0x103d225b4、
0x103d227e4→0x103d22850），commajoin后交second builder0x103d23d58。
T18 confirm0x103cff000→0x103cfe838独立传true给0x103cfd1f8
（0x103cfe870/0x103cfe874）；同样跳过items/mixedItems，仅追加gender/age，
second builder调用0x103cfe9e8。两个admission body只检查model非nil，未见style/
_isRequesting gate；不据此推断按钮外部交互。这里的interest_result是人口属性
子集，不能统一表述为全部当前选择；同helper的Bool=false其他caller不套此结论。

T33/T34 physical confirm分别0x103d45a84→0x103d44fa0、0x103d58390→
0x103d578ac；model非nil且_isRequesting=false才入，先置busy=true再调second
（0x103d45050/0x103d45198、0x103d5795c/0x103d57aa4）。其sids helper
0x103d443f4/0x103d56d00直接按selectedSubItems顺序生成parentID+"."+childID，
弱parent缺失取parentID=0，再追加符合条件的gender/age。不按selectedItems分组，
没有裸parentID项或排序/去重，区别于T35/T37的父项分组编码。
成功0x103d45204/0x103d57b10在nil/items判断前安排main+0.5秒弱取原view清busy
（0x103d45700/0x103d5800c），nil success也安排清除；error
0x103d45718/0x103d58024则在nil/NSError cast前立即清busy
（0x103d45764/0x103d58070）。非空items对原absoluteModel/UI弱gate，但仍写共享
manager.model（0x103d455d8/0x103d57ee4），没有账号/请求epoch比较。空items
-1234及可cast HTTP error回退捕获原model，报告同五字段client exposure；两者
callback context也同时持weakbox、strong原view与strong原model，不能把weaknil
结构分支解释为请求仅弱持有UI。这里busy解除及模型替换都不代表最终兴趣提交回执。

T33实际child选择入口在S1子view：0x103d4ed6c→0x103d4e554取
items[section].sub_items[item]，NSObject equality查找；未选项追加到
selectedSubItems尾部（0x103d4e708/0x103d4e70c），已选项稳定删除
（0x103d4e748）。正select_num_limit限制整个child数组，<=0取Int.max；重选追加
到末尾。outer didSelect0x103d49c4c→0x103d45aac只改gender/age index。
T34独立S1入口0x103d60a58→0x103d60240，追加0x103d603f4/0x103d603f8、
删除0x103d60434，具有同样选择顺序和全局数量门禁。S1 confirm T33
0x103d4f28c→0x103d4f164、T34 0x103d60f78→0x103d60e50均弱取delegate，
live时原序复制child数组到outer，调各自final builder，再dismiss raw1，立即设置
本地submitted=true（0x103d4f234/0x103d60f20），此body不再发second HTTP。

T33 final builder0x103d46e48另要求current model和absoluteModel同时非nil
（0x103d46e74/0x103d46e84）。缺失时直接返回，而S1 caller仍dismiss并设本地
submitted，故该标记不能证明Confirmed已经发出。通过门禁后Confirmed通知
0x103d48280恰有三个String字段：unique_id取current model，sids复用
0x103d443f4的child点分ID和符合条件的人口属性，interest_pos_ids则取
**完整absoluteModel展示ID列表**，并非已选位置。具体flatten按absoluteModel.items
原序，parent.sub_items非空时加入其全部children，否则加入parent
（0x103d478a4–0x103d47aac）；Item输出自身ID，SubItem输出弱parentID+"."+childID，
弱parent缺失/错型compact掉（0x103d47cec–0x103d47f9c）。该数组commajoin
0x103d480c4→通知字段0x103d48204，不筛选当前选择、不按max_subitems_show_count
截断、不包含人口属性。它与下述click位置列表独立。

随后T33发BFCNeuronClickEvent main.interest-select.submit.0.click
（0x103d48c0c）。base八字段interest_id_list、interest_list、interest_pos_list、
content_cnt、extra_select、style、unique_id、strategy；后三个取current model。
前两个列表分别从selectedSubItems的弱parent ID/name构造（缺失取0/空字符串），
位置列表0x103d51278取弱parent在absoluteModel.items的首次NSObject相等索引+1，
缺失取0；三列表均经Set<String>→array→JSON（0x100066c38/0x103d9cae8/
0x103d6f200），去重且不保证tap/server顺序。content_cnt取去重parent ID数量
（0x103d4873c），不是child数量。extra_select是String:String字典JSON：每个
人口属性section要求title非nil、候选非空、selected index>=0，以实际section title
为key、所选Gender/Age.title为value（nil取空）；age后写，同key覆盖gender
（0x103d482b0–0x103d4851c），并非固定gender/age key或数字ID。
最多再有四个非空child字段：sub_interest_id_list取child ID decimal经Set→JSON
（0x103d48904）；sub_interest_list取child name原序JSON（0x103d48988），不去重；
sub_interest_pos_list用0x103d5155c生成parentPosition.childPosition，分别在
absoluteModel.items与live parent.sub_items取首次NSObject相等索引+1，缺失索引
取0，弱parent缺失compact掉，保留其余选择顺序后JSON（0x103d48a4c）；
sub_content_cnt取原selectedSubItems.count decimal（0x103d48b30），不去重。
这些click字段不能代替通知sids或interest_pos_ids序列。
T34独立final builder0x103d592a8也要求current model/absoluteModel同时存在
（0x103d592d4/0x103d592e4），S1同样不检查返回后设置submitted。其Confirmed
0x103d5a750有四字段：unique_id、sids、全部absoluteModel flatten的
interest_pos_ids，以及额外Bool disable_refresh_after_submit。该Bool来自
**current view.model**（0x103d592f4→0x103d5a5f0→0x103d5a6c4，boxed
0x103d5a6d0/0x103d5a6d4），非absoluteModel/global配置。sids helper
0x103d56d00→commajoin0x103d5a514，完整展示ID flatten
0x103d59d08→commajoin0x103d5a540；click0x103d5b088另行构造位置字段。
这一额外Bool对应下述MainVM typed Bool消费门禁；缺失时的false行为不能推广到T34。

T33 S1 MoreAction0x103d4f2b4先清outer child数组0x103d4f2f4，再呈现Feedback
controller；callback0x103d462cc弱取原view、cast InterestMoreActionItem，raw Bool
true分支0x103d46374要求current model存在，发Skipped通知0x103d465a0，仅
unique_id/current helper sids两String字段。因为child先清，此时sids可仅含符合条件
人口属性；随后dismiss raw2和事件helper0x103d48ce0，没有second HTTP或本地
submitted setter。Bool=false分支0x103d493c0仅发
main.interest-select.continue.0.click，三个current model字段style/unique_id/
strategy（0x103d49590），没有dismiss、通知、submitted setter或请求。
Bool=true后close click0x103d48ce0有current model三字段、is_initiative="1"和
reason="three_point"（0x103d48f68）。另outer S0 more入口0x103d495c4→
0x103d4608c不清child数组；仅上述S1 More先清，所以相同menu回调发Skipped时，
outer入口的sids仍可保留孩子，不能统一写成人口属性子集。
T34独立child click position helper0x103d631b0已核实同一索引规则：weak parent
缺失Optional nil（0x103d633b0），parent/child首次NSObject相等索引+1，缺失
分别取0（0x103d63298/0x103d63308），与Confirmed完整展示ID列表分开。
T34人口属性物理didSelect0x103d5bd48→0x103d583b8要求model非nil，点击当前
index直接返回，不toggle-off；变化才写index、readiness/reload，发
main.interest-select.extra-btn.0.click（0x103d588f8）。八String字段name取所选
Age/Gender.title、interest_id取其ID decimal、title取对应model section title，
nil title/name取空；pos=item index+1，style/unique_id/strategy取current model，
action_type固定select。body未见busy gate或网络请求。
T34 S1 child变化完成后先reload/readiness（0x103d60464/0x103d6046c），再弱取
parent；parent缺失省略事件但不撤销选择（0x103d60480/0x103d60484）。数量上限
拒绝则toast并退出，无该事件。live parent才发
main.interest-select.interest.0.click（0x103d60988），十String：interest_name/id
取weak parent Item，interest_pos取它在当前S1.items首次NSObject相等索引+1
（缺失0），sub_interest_name/id取本次tapped child，sub_interest_pos取物理
IndexPath.item+1；style/unique_id/strategy取捕获S1.model，action_type按追加/
删除为select/cancel（0x103d60404–0x103d60454）。不取shared/absoluteModel，
也不把tap pos、submit JSON positions、Confirmed全展示IDs统一编码。
T33 S1同样已由物理入口独立核实，0x103d4ed6c→0x103d4e554，变化后
readiness0x103d4e780、弱取parent0x103d4e794；parent缺失保留选择但不发事件，
上限拒绝toast0x103d4e92c也不发事件。十字段同族事件实际report
0x103d4ec9c；parent位置从S1.items首次相等索引+1（0x103d4e9b0/
0x103d4e9cc，缺失0），child位置取物理IndexPath.item+1
（0x103d4eadc/0x103d4eae0），三身份字段取S1.model。select/cancel取本次
追加/删除分支，不用提交后的去重ID数组推导tap位置。
T34 S1 readiness0x103d60fa0以raw selectedSubItems.count>=1且
count>=model.select_num_min_limit决定setEnabled（0x103d61004–0x103d61054）；
model nil则直接返回、不改旧按钮状态。min<=0仍不允许空选择；此计算不按parent
去重，也不检查人口属性/busy。文案独立按min<1或enabled选
subpage_confirm_text，否则格式化剩余数量（0x103d61104–0x103d61160）。
物理confirm body0x103d60e50没有重读enabled/count，不能把UI按钮门禁推广为
程序调用final函数的同等拒绝条件。

T34空白区关闭的物理触发也已闭合到继承PopupViewController：
touchesBegan0x104e236bc→0x104e23514，首touch坐标与container.frame做
CGRectContainsPoint（0x104e23638）；inside返回，outside调用动态slot+0x1e8。
T34 metadata0x11fdef978对应0x104e22a5c固定true，再slot+0x200调用
0x104e22df0启动animated dismiss，随后slot+0x1d8同步进T34 body
0x103d569d4，不等待animation completion。该body要求current model，先清
selectedSubItems（0x103d56a1c）；仅pageIndex==0再清age/gender index为-1
（0x103d56a38–0x103d56a58），非零页保留人口属性。Skipped通知
0x103d56c40带current unique_id及helper0x103d56d00的sids，故孩子必排除，
非零页仍可含eligible demos，并非所有blank close都空sids。随后close helper
0x103d5b1b0以is_initiative="1"、reason="blank_click"发
main.interest-select.close.0.click（0x103d5b438），其余style/unique_id/strategy
取current model，再manager dismiss raw2（0x103d56cac）。没有submitted setter、
second HTTP或请求取消。另forwarding thunk0x103d5b800传is_initiative=false和
传入reason进入相同helper，其物理caller未定位（0x103d5b800 无 BL 调用点，属**运行时 selector/闭包
派发**）；下一步 `$PY find_callers.py 0x103d5b800` 与 `$PY query_index.py '*is_initiative*' 20`，
不归因 swipe/back。（本段下一步见上句：find_callers.py 0x103d5b800 与 query_index.py '*is_initiative*' 20；物理调用者属运行时 selector/闭包派发，需真机断点确认。）
T34 S1返回物理入口_previousButtonClick0x103d60e28，经0.25秒UIView animation
0x103d60d28、completion0x103d65160→0x103d60dd0；completion不检查finished
Bool，先removeFromSuperview0x103d60dec再弱取delegate，调用outer
0x103d5c180（0x103d60e08）。动画closure强捕获S1（0x103d60cbc/
0x103d60cfc）；parent nil则不执行outer reset。
outer两models非nil分支先发main.interest-select.step-btn.0.click
（0x103d5cf30），九字段：current style/unique_id/strategy、action_type="2"；
interest_id_list/name list/position list三项均由**outer旧selectedSubItems**的
weak parent映射、分别Set→array→JSON，无排序承诺。位置helper0x103d62ecc查
absoluteModel.items首次相等索引+1（缺失0）；content_cnt为去重parent IDs count，
extra_select按前述人口属性门禁构JSON（同section key时age覆盖gender）。没有
child list/sub_content字段，不读取当前S1 pending child数组。
随后explicit EmptyArray（0x103d5cdc0/0x103d5cdc4）写outer selectedSubItems
（0x103d5cf54）；model/absoluteModel nil分支0x103d5c34c也清选择但不发上述
事件。两路最终absoluteModel=current model、pageIndex=0
（0x103d5cf68/0x103d5cf80）。相对进入S1 helper0x103d58998在安排animation
后同步写pageIndex=1（0x103d58bf8），second error fallback也复用这个helper。
T34 S1 willDisplay0x103d60b18→0x103d646d0（0x103d60bbc）先查display child
SubItem._isExposed（0x103d64aa0/0x103d64aa4），true省事件；false发
main.interest-select.interest.0.show（0x103d64eac），九String：display parent
name/id/位置、display child name/id/位置，以及S1.model style/unique_id/strategy。
这条曝光用display parent，不借child click的weak parent门禁。track返回后直接
same child._isExposed=true（0x103d64ed4），不等网络ack；同对象再次willDisplay
被抑制，不因后续发送失败恢复业务曝光资格。它不是按MID/ID/IndexPath保存key。
SubItem 的 `_isExposed` 必须区分实例属性与序列化 blacklist：
0x120443080 是 `modelPropertyBlacklist` 返回的 `["_isExposed"]` 常量，不是实例 marker 槽。
独立原始复核的实例 offset 槽为 0x120443b68，getter 0x103c79e90、setter
0x103c79ea0；原 0x103d79ea0 地址不能作为该属性的断点或写者证据。
已知置 true 除两条 willDisplay 路径外，还包括 0x103c91bfc；因此撤回
team-c38 的“只有两处写者”和“无全局 reset”强否定。blacklist 不赋 marker
只约束 JSON 属性映射，不约束 setter、直接实例写入或对象替换。
同 model 重建沿用 child 的局部证据见下段；运行中 false 写者现已有正例：T17View._confirmButtonDidTap 0x103ce77cc →
0x103ce75f8 在 selectedItems 子项总数>0 时转 0x103ce77f4；后者遍历现有
model.items 全部 sub_items，0x103ce7cb0/7cdc 分别对 Cocoa/native 数组分支写 false，
再配置新 T17ItemS1View。它是清已有对象 marker，不是仅初始化新对象。
真实 offset 槽的 19 个候选逐一展开，已见 15 个业务 true store，原“两/三处”计数
不完整。正例限 T17 兴趣步骤切换，不推普通首页去重池/账号切换/9.13；固定偏移、
动态派发与外部模块全部写者尚未穷举（root-static-exposure/findings.md）。
独立原始证据：`DerivedData/Validation/independent-dsh-review/c38.md`、
`0x103c79e90.asm` 与 `0x103c91bec.asm`；team-c38 原 findings 的强结论已撤回。
S1创建0x103d58998直接取input model.items（0x103d58b10），将同array/model
传configure0x103d5f4bc（0x103d58b24）；configure分别保存model/items
（0x103d5f4e8/0x103d5f50c），retains array0x103d5f514，reload后readiness
（0x103d5f700/0x103d5f720），未deep copy child、重parse或reset _isExposed。
因此同model重建S1（包括second失败沿用原model）保留子对象marker；新HTTP响应
的YYModel分配/对象复用策略另属边界，不把此结论推广为所有新model永不重报。
T33 S1也由独立物理willDisplay0x103d4ee2c→helper0x103d52ba4核实：读same
SubItem._isExposed（0x103d52f74/0x103d52f78），false才发同名interest show
九字段（0x103d53380），track后置true（0x103d533a8），不等HTTP回执。
这里只闭合T33标记接受时序，不以T34 configure证据替代T33视图重建/重置链。
T34原页人口属性willDisplay0x103d5be4c→0x103d637d8（0x103d5be50）按raw
section bit1选择Age、bit0选择Gender，以物理IndexPath.item取display对象；
Age._isExposed（0x103d63898/0x103d6389c）或Gender._isExposed
（0x103d63948/0x103d6394c）为true省事件。false发
main.interest-select.extra-btn.0.show（0x103d63d00），七String：name/displayed
title、interest_id/displayed ID decimal、title/model section title、pos=item+1、
current model style/unique_id/strategy。没有click的action_type，也不检查该项是否
selectedIndex。track后same Age/Gender marker=true（0x103d63d20），不等HTTP
回执。Gender.init0x103c79b94置false（0x103c79bf0），Age.init0x103c79cfc
置false（0x103c79d34）；各自blacklist0x103c79b88/0x103c79cf0分别引用
0x120443010/0x120443048，均仅含_isExposed并转公共0x103c79ebc。
因此新对象未曝光，普通blacklist-aware JSON不赋marker；同对象的post-track标记
保留。动态setter0x103c79b78/0x103c79ce0仍可写Bool，外部reset未全部排除。
T33首屏独立链willDisplay0x103d49d50→0x103d51ca0同样按raw section bit
选择Age/Gender；flag0x103d51d60/0x103d51d64或0x103d51e10/0x103d51e14
为true省事件。false发相同七String extra-btn show（0x103d521c8），pos来自
实际IndexPath.item+1（0x103d52058），无action_type/selectedIndex门禁；track后
同对象置true（0x103d521e8）。这是对象标记，不是view/session/key级去重。

三个门禁均通过时，helper滚动到(0,0)，构造20个LocalSmallLoadingViweModel，
CardData raw25、无report编号，Diff before空/after占位卡、flags=0。同步路径
0x101a53c68–0x101a53f90与默认异步producer0x101a57be4均已核实；helper返回true
只代表此分支被安排。经理dismiss0x103c7578c清view/model，排主队列工作，才在
0x103c75a34将hasShown置true并发Dismissed通知，不是在首次构造弹窗时置true。
已核实该ivar0x120443898的直接写仅init false与dismiss true；动态或账号reset未知。

MainVM0x101a49c40注册object=nil的Dismissed、Confirmed、Skipped通知观察者。
Confirm0x101a4b104将disable_refresh_after_submit按Bool解码，缺失/错型为false。
true且共享tmpPegasusCards非空时，交DataFactory0x101a41f10恢复卡片，不调用refresh
operator。同步分支先compactMap0x101a4340c再由0x101a42638从成功数组的1开始编号；
默认异步分支0x101a42130→0x101a43844→0x101a41524→0x101a3e1dc使用同规则。
回传Diff0x101a43724→0x101a4bad4弱取原VM/updater，实验同步开直接0x101a43a90，
否则经队列0x101a5830c安排apply；该包装无账号代际门禁。其他confirm条件先清空
卡片，completion0x101a4bf00保存选择，再读当时共享MainEventOperator+0x30并调用
raw reason4（0x101a4bf2c/0x101a4bf3c）。前述UI/loading门禁仍可拒绝实际新请求。

选择marker写入0x101a4b8cc要求unique_id与sids都为String，才写
0x12106a5c8的+0x68/+0x70和+0x78/+0x80；缺失/错型保留旧值。Skipped消费者
0x101a5becc同样写这两值，但没有卡片更新或refresh调用。MainApi首次惰性构造
params时读取marker为interest_id、interest_result（0x101a32f58/0x101a32ffc），
已缓存params并不每次发送重读。Dismiss消费者0x101a4aa3c要求typed DismissReason，
raw1直接返回，raw3另有first CardData类型门禁，详见下文具体UI链；不凭raw值
命名未核实的全局UI语义。通知、
共享tmp cards与marker均未带账号过滤，这只是已读路径边界，不证明运行时跨账号显示。

具体T10View确认动作0x103c83500→0x103c82294有可核对的UI来源，不能泛化所有style。
didSelect0x103c8590c→0x103c84914按section raw0/1/其余分别选gender/age/item；
相同gender或age再次点击直接返回。item将cell选择Bool异或1，新选IndexPath追加
数组尾，取消稳定过滤移除，重选追加末尾。换gender经0x103c8153c通常清item路径，
首次显式选择gender0才保留；这是UI实例状态，是否落盘未解码（0x103c8153c 起是否出现 preferences 写入属 UI 交互 + 持久层写入，
静态不可定）；下一步 `$PY disassemble.py 0x103c8153c 0x103c81600` 查是否出现 preferences/userDefaults 写入。
确认helper0x103c86900按当前选择路径顺序取chosenGender.items[item].id十进制，
不排序；追加gender.id（未选gender index=-1归0），age仅ages非空且index>=0才
追加。sids逗号join；interest_pos_ids独立由选中item位置+1组成，不包含gender/age。
Confirmed通知0x103c82ad0只有unique_id、sids、interest_pos_ids三个字段，
unique_id为model Int64的十进制String；没有disable_refresh_after_submit，因此这个
UI变体走默认false的清卡→marker→refresh operator路径，不走上述直接恢复分支。
T10 skip动作0x103c8226c→0x103c82044的Skipped通知0x103c821cc只有unique_id，
未带sids；因此具体落到0x101a5becc时缺第二String而返回，保留旧marker，不能把
“存在skip writer”外推为这次UI跳过会保存interest_result。之后dismiss raw2
（0x103c8220c），随后由关闭通知另行触发页面处理。
Dismissed消费者0x101a4aa3c中raw2直接进入清卡路径；raw3另要求当前first CardData
经0x1035a4648映射为local_small_loading才继续，raw1返回。清卡producer
0x101a571e8构造before=当前卡片、after=空、flags=0，同步0x101a4ae6c→
0x101a43a90或默认异步0x101a5ce28→0x101a58314应用；completion0x101a4b084
读CURRENT MainEventOperator函数对并调用raw reason1，仍受loading/UI门禁。
因此T10 skip的页面处理是清卡再尝试刷新，不是直接恢复tmp cards。
该UI后续0x103c83528(true,nil,nil)还报告close click，is_initiative="1"并带style、
unique_id；reason参数nil所以不带reason字段，不能从事件名字推一个服务器跳过回执。
另一T37View more面板不是相同通知形状：0x103d889e8构造两item，action回调
0x103d88bd4要求弱view有效、类型匹配且所选item+0x20 Bool=true，才进入
0x103d88c7c。这里Skipped通知0x103d88ea8同时带unique_id与sids（helper
0x103d858a8的结果commajoin），能满足首页marker writer的双String门禁；之后
dismiss raw3（0x103d88eec），再发reason=three_point的close click。
raw3仍受首卡local_small_loading门禁，所以该T37路径也不能保证清卡/刷新。
T37ItemS2View物理more入口0x103d97858→0x103d977c0→0x103d977cc经
delegate ivar0x120446290弱取parent T37View，先清selectedItems/SubItems
（0x103d9781c/0x103d97830），再present上述more面板。因此这一路后续sids的item
选择已清空，而不是仍携之前的全部选中item。其他子面板未逐面板核对（属逐 UI 面板枚举）；
下一步 `$PY disassemble.py 0x103d96b00 0x103d97800` 枚举各面板的 willDisplay/confirm 入口；T10 skip与
T37 more的字段和动作不同，不能合并成一种确认或跳过协议。
T37的S2确认物理入口0x103d97798转0x103d97670，弱parent有效时先复制S2的
selectedSubItems到parent（0x103d976c8），调用0x103d8a940构造Confirmed；其
userInfo除unique_id/sids/interest_pos_ids外，还把InterestModel ivar
disable_refresh_after_submit（0x1204439d0）读成Swift Bool并透传
（0x103d8bd9c/0x103d8bddc/0x103d8bdec，post0x103d8be68）。这个Bool来自
前述yy_modelWithJSON解析的模型，不是UI硬置true；只有实际为true且共享临时卡片
非空时才满足首页Confirm恢复卡片的分支。T10的3字段默认false与此不同。
随后dismiss raw1（0x103d97710），直接向InterestPreferences设置
hasSubmitedInterest=true（0x103d97740）；这一本地标记没有HTTP成功回执门禁。
具体偏好receiver是BBPegasusInterest.Preferences（metadata0x11fde22f8），继承
BFCPreferences；configName0x103c6f864固定返回BBPegasusInterestPreferences，默认
hasSubmitedInterest=false（defaultConfig0x103c6f808→0x103c6fbc8）。property list
0x11d7e9318明确该属性为动态Bool（TB,N,D）；processAllProperties0x1167d3798为
它安装Bool getter0x1167d4adc/setter0x1167d4b5c，getter与setter都映射原始属性名
hasSubmitedInterest作为存储key。setter先更新实例configCache，再向这个固定suite的
NSUserDefaults setObject（0x1167d355c/0x1167d357c），不走Universal/HTTP回执。
初始化持久值非nil优先于默认值；随后getter仅加锁读取cache。这条闭合链没有MID/
账号分区参数，也没有显式synchronize；OS磁盘完成时刻及别处账号切换清理未知。
其他 style 是否同样透传/写标记未逐 style 核对（属多 style 逐支枚举）；下一步
`$PY disassemble.py 0x1167d34cc 0x1167d3600` 与 `$PY find_callers.py 0x11719dfa0`（`_objc_msgSend$_setObjectWithKey:value:` stub；0x1167d355c 是该实现内 +0x90、0x1167d34cc 是入口）枚举各 style 的写入点。

通知后，T10动作调用BFCNeuronClickEvent.trackEventWithId:extendedFields:
（0x103c83184），事件main.interest-select.submit.0.click。七字段来源为
content_cnt=选中item数、interest_list=选中item.name、pos_list=item位置数组、
extra_select=已选gender_title/age_title字典、style、unique_id，以及
interest_id_list=所选gender的全部items.id，后者不能与仅选中项组成的sids混同。
数组/字典经helper0x103c6f200转String，其JSON细节继续核对。最后dismiss raw1
（0x103c831bc）才将hasShown置true；这闭合raw1与T10确认的关系，而非所有样式的
全局枚举语义。该动作未另写Universal preference或直接发选择专用HTTP；后续feed
请求与Neuron发送各有自己的门禁，不把通知/点击调用视为兴趣已在服务端生效。

refresh失败时，0x101a5b3b0的x1是Error而非rawitems，w4为Result失败tag；
0x101a57e20的true分支仅swift_errorRetain，不是发起重试。失败先从本次params读取
open_event并比较cold_back。只有配置字节0x12106a633为true、flush原始值属于
mask0x1f7dff（0–8、10–14、16–20）、当前VM.cards空、open_event!=cold_back时，
才调用兜底缓存helper0x101a54d44，否则立即呈错0x101a54b70。

缓存producer也有具体正常响应入口：refresh在配置字节0x12106a633=true且flush属于
同一mask0x1f7dff时，0x101a5b540将rawitems/config交0x101a5a13c，发生在VM.config
更新和卡片转换之前。helper逐输入字典复制extra_rpt_fields，将
is_cache_local_data设为String "1"（已有键覆盖），写回工作数组；此工作数组经Swift
COW独立于继续网络渲染的原数组，不能称为当前卡片model setter。它构造顶层
JSON的datas/config两键，经writeAsync:scene:id:data:version:expirationTime:
0x101a5a914写入：scene=tm.recommend.0.0、id同0x101a5a02c当前账号+style，
version为VM.diskCacheVersion（初始化String "1"），expirationTime明确传0。
返回订阅保存cacheWriteDisposable（0x101a5aadc），其dealloc dispose已闭合。
config先经0x101a59e50→0x101a59bb4过滤，明确剔除scene_uri与interest_guide两键；
其他配置键保留。存储后端已接线到 FallbackCache 桥：writeAsync:scene:id:data:version:expirationTime:
（selref 0x11f78b0e0）由 `+[FallbackCacheOCBridge writeWithScene:id:data:version:expirationTime:completion:]`
（0x102125c10）承接，后者把参数交 sub_102124F0C（0x102125cf8）再进 FallbackCache 原生导出层；
expirationTime=0 的解释落在该层（属尾部 FallbackCache 章节，归尾部席位）。本区只固定调用点
0x101a5a914（sub_101A5A13C 内）、scene=tm.recommend.0.0、version=String "1"、expirationTime
显式为 0，**不能据此称永久缓存**；下一步命令 `$PY disassemble.py 0x102124f0c 0x102125c10`。
读出的cacheitems再经普通render，所以该缓存标记可随
extra_rpt_fields进入Reporter合并；不是另发一种网络推荐请求。

helper调用KntrFallbackCacheNativeKt.readAsync（0x101a54df4），scene=tm.recommend.0.0，
id由0x101a5a02c读取发起缓存查询时currentUser.mid与当前style生成，version取
VM.diskCacheVersion；不记录真实MID。它切到MainScheduler，continuation
0x101a5ba94→0x101a54878仅weak-load原VM；VM已释放则返回。cacheitems非nil时
以cacheconfig替换VM.config（0x101a54938），publish key26，再将cacheitems交普通
render0x101a53fd0（0x101a549ec），仍先compactMap并从1编号；nil缓存走错误呈现。
这条路径没有创建新MainApi，不是重新请求推荐服务。**账号边界本轮复核**：续体
0x101a54878–0x101a54a00 内无 objc_msgSend、无 mid/账号读取指令（只有 weak-load VM、
替换 config、publish、交 render），即**读缓存本身不做账号二次校验**，账号隔离只由发起时
`0x101a5a02c` 生成的 id（currentUser.mid + style）提供；若 VM 跨账号存活，旧账号键的
缓存仍会被消费（与后文晚回调无代次校验同口径，属运行期交错，静态不写成已复现）。
磁盘后端的 expirationTime=0 语义属尾部 FallbackCache 章节，不在本区改。
读结果parser0x101a56628在Result失败或无有效success/data时回(nil,nil,nil)；
有效JSON dictionary即使datas缺失/不能cast仍用emptyArray，config缺失/不能cast用
emptyDictionary并回非nil，因此空datas也可走缓存恢复分支，不能把非nil缓存当非空卡片。
原VM的_transactionToken在0x101a49dc8来自LaunchTransaction.registerWithItem，
0x101a57198调用done，是启动事务句柄，不是request-generation凭证。
缓存readAsync桥0x101363a5c返回cancel closure0x1013648e0，但替换Optional订阅本身不是cancel。已读Rx AnonymousDisposable.destroy
0x1050a867c仅释放disposeAction context，BinaryDisposable.destroy0x1050b0980仅
销毁两个existential，SinkDisposer.destroy0x1050e87d0仅销毁optional sink/subscription，
这些析构都未调用dispose。具体Observable经Producer.subscribe0x1050e78d0分两路：
已有CurrentThreadScheduler队列时返回ScheduledItem；否则同步创建并返回SinkDisposer。
前者metadata0x1196b7870的destroy0x1050f51b0只释放action context、state及
SingleAssignmentDisposable，后者destroy也只释放成员；两路在Optional替换/释放时
都不会自动dispose。ScheduledItem另有显式Disposable witness0x11b356640，
经0x1050f58c0→0x1050f5894调用SingleAssignmentDisposable.dispose0x1050fb8d0。
因此必须证明显式dispose的调用，不能仅凭引用释放认定旧查询已取消；额外取消入口未穷举
（属逐订阅枚举）；下一步 `$PY find_callers.py 0x1050fb8d0` 并反汇编 0x1050f5800–0x1050f5900。


原网络completion0x101a55f8c在0x101a55fd0及0x101a56038向同一个已捕获MainApi取
lazy params。getter0x101a32340在instance+0x18非nil时直接复用，仅nil时重新构造并
缓存；user callback及key22 report因此使用该请求的已缓存参数，不再消费一次
open_event或重新读取设置。缓存回调0x101a54878没有可见MID/request-generation比较；
cacheReadDisposable赋值helper0x100893fc8是Optional assign-with-take，不能称为显式
dispose旧查询。MainViewModel.dealloc0x101a48e50→0x101a48ce0才明确通过Disposable
witness+8 dispose cacheRead（0x101a48db0）与cacheWrite（0x101a48e10）。普通刷新入口0x101a4893c先丢弃已有EarlyRefreshCache结果与continuation，再读isLoading；true时直接返回，
不发送新refresh且不dispose旧cacheRead。false时发feedWillRefresh、通知并置isLoading=true，
再调用网络入口；卡片处理completion0x101a56250弱取VM后清isLoading。
这说明普通loading期重复下拉是拒绝新刷新，不是取消旧缓存读取；实验提前刷新有
独立门禁与取消入口。VC setup读取process-once缓存bool0x12106a632；initializer
0x101b483b4要求pegasus_pull_refresh_opt_enable与infra.eu.opt都true，二者default=false。
开启才安装earlyAction/cancelAction；early UI0x101a372d8要求pan velocity.y>0，
才以reason raw7进入0x101a485e4，loading=false时设loading/pending并发请求。
物理拖动接线在BFCRefreshHeader0x116065044：drag期间offsetY跨过
-originalInsetTop-headerHeight阈值使state1→2，再拖回阈值使2→1；前者通过
setState0x116065300在early enabled时调earlyBlock，后者调cancelBlock。
停止drag且state2会beginRefreshing，state3走正式headerRefreshingAction。
因此这里的cancel是越过完整header阈值后拖回，不能泛称离页/HTTP失败自动取消。
main action0x101a484b4在pending=true只安装continuation，不另发请求；已存结果则
由0x101a584f8处理，均无结果时退普通refresh。处理要求params非nil、result tag非ff、
reason非raw21 sentinel，交0x101a5b3b0后清缓存；deferred0x101a58694采用同门禁。
cancelAction0x101a374d0→0x101a487f8清已有payload/continuation/pending，明确将
isLoading=false（0x101a48918），但没有本层请求dispose/cancel。
pending=false且result tag=ff也仍清loading；没有“本次early请求拥有loading”门禁。
因此early入口被既有loading挡住后，若UI仍触发拖回cancel，可解除其他普通在途请求
的loading；是否实际允许该UI交错与公共网络取消仍未运行验证。
late response0x101a5837c只有原VM weak非nil门禁：无条件清loading0x101a58430，
重新写缓存params/result/reason/pending，再读取当时continuation并调用；没有读取
先前pending/取消代次/当前账号。因此晚回调可重填已取消的缓存，甚至消费后来
安装的continuation；无continuation时不会直接apply。公共网络全局取消和真实送达
尚未验证，属**运行期并发行为、静态不可定**；下一步反汇编该晚回调写入点并回溯 continuation
安装点（本段上文所列缓存写入者），不把静态交错可能性写成已复现污染。该分支也不能套作默认普通刷新行为。
账号empty Diff链未清earlyCache；实验main action收到新的Marker reason时，ready-cache
分支却取cache.reason及旧params/result交0x101a5b3b0，新的reason只供无缓存时的
普通请求分支。因此同活VM有ready旧缓存时，账号触发header action存在处理旧结果
的条件路径；仍须满足实验、launch、loading、collectionView和UI action门禁，不当
真实跨账号送达证明。
其它订阅取消与防串扰未穷举（属逐订阅枚举）；下一步反汇编本 VM 订阅装配点并回溯账号通知链
（见下段 0x101a48f88 起的注册链）。
数据最终写入也已定位：VM.cards getter0x101a48ba0返回FeedUpdater，+0x28是
DataFactory，后者datas在+0x10。默认pegasus_process_data_sync_exp_enable=false时，
render0x101a53fd0排到FeedUpdater.concurrentQueue，0x101a43bfc先等待semaphore，
再main.async执行producer；producer0x101a562f4从原VM当前FeedUpdater取DataFactory
生成Diff。nil Diff直接signal；非nil进入apply0x101a43e2c。实验true分支则直接
调用DataFactory，绕过上述wait入口，不能用默认串行行为概括全部配置。
usingDiff=true时生成UI diff，data setter0x101a44560只weak-load捕获的FeedUpdater，
非nil就写DataFactory.datas（0x101a445b8）；batch分支0x101a447f0同样只weak-load，
将Diff.after写入datas（0x101a4488c）并reloadSections。UIcompletion再publish24并
signal。上述commit点没有可见账号、请求代次或before==current datas检查。
这闭合了本地串行apply与写入点，semaphore本身不使旧响应失效；外部collection
diff引擎与非典型寻址的外部重置未逐一核对：descriptor 直引扫描对动态/不同寻址形式不封闭，
属**有界扫描的静态盲区**；下一步对 VM._updater 槽做 `find_data_refs_root` 并反汇编 diff 引擎
入口复核，不能将局部缺少校验直接当实测污染。
全__text的descriptor直引扫描中，VM._updater的引用仅见getter、初始化及析构；
getter0x101a48bb4已有实例就retain返回，nil才新建并保存0x101a48c34。
VC.viewModel同类扫描仅见两种init的初始nil、lazy getter首次保存与析构，没有
识别到账号回调替换writer。这是有界扫描，不能排除动态或不同寻址的写入。
普通请求0x101a550b0→0x101a34a4c在requestAsync0x101a34ba8后立即release局部
BFCApiRequest，没有把取消句柄回传或存入VM；公共网络层的全局账号取消属**公共层职责**，本区不复核（下一步：公共层章节反汇编 0x101a34ba8 起 requestAsync 冒烟点并回溯取消入口）。
该业务构造入口没有设置custom response queue，故异步completion/error沿公共层默认
主队列送达。MainApi error closure0x101a34c14也没有按-999过滤：保留error，置config/
interest=nil与Result tag1，再调用注册callback（0x101a34c30）。因此即使外部实际调用
公共cancel，只要afterwrapper/gateway/errorHandler继续送达，取消错误仍可进入原
weak VM业务回调与earlyCache；不能把transport cancel概括成业务层天然静默。
具体账号入口已有一条闭合链：VC lazy VM初始化时以该MainVM作observer注册
BFCAccountNotification.addActionObserver:type:block:（0x101a3663c，mask raw0xb），
closure0x101a3b788→0x101a4a4d8弱取原VM，LaunchTransaction.isAllDone=false直接
返回；true则用原FeedUpdater生成Diff，before=当时DataFactory.datas、after=empty、
flags两字节0。默认实验false仍走上述queue/semaphore，true直接apply。
apply completion0x101a4aa34调用MainEventOperator的flush函数对，参数raw17；这是
独立operator动作，不能因相同数字叫成Dispatcher raw17事件。该completion执行时
重新读取共享MainEventOperator的函数对；当次绑定closure0x101a5c464捕获同VM，
但另一VC再次绑定可覆写共享闭包，因此不能把其接收者总认定为原Diff的VM。
绑定入口0x101a48f88与completion0x101a4b08c支持此归属限定，真实多实例选择未证。
closure进入0x101a4fa88：collectionView非nil且isLoading=false时
写MainApiMarker raw17，再scroll到(0,-60)，0.3秒main.asyncAfter触发header refresh。
这个已读链没有替换VM、dispose cacheRead、reset isLoading或检查账号代次。
isLoading=true时仍可完成空Diff应用，随后拒绝header refresh；静态路径可以成立，
不把这条静态链当实测时序。通知层0x11605d16c以item.type & action筛选，mask0xb
覆盖Login1、Logout2、Change8，不覆盖Update4。普通命中main.async后读取ssoModel并
回调原action；Change专用路径0x11605d2ac因item.type含bit3，排相对3秒dispatch_after，
再以action8回调。这是账号通知的3秒，独立于上述header refresh的0.3秒。
VC header handler0x101a3b7e8经0x101a37538弱取VC，取其viewModel、读取当时Marker.reason，
再调用普通refresh0x101a4893c。raw17经Int64映射表0x1182c9138变成wire flush=21，
不能写成wire17；普通refresh的isLoading门禁及缓存不自动取消的结论仍适用。
replumeFlushIndex（0x101a5133c）
确实对传入数组从 1 重编号，目前已找到 BannerV8 替换调用，原始响应批次的调用未证。
Swift didSelect（0x101a380e4→0x101a37e38）注入的是 BBListPegasusAdapterProtocol，
不是 MainEventOperator；MainService witness+0x30（0x101b866f8）要求模型符合
CardViewModelProtocol，再调用其 +0x70。SmallCoverV2ViewModel 的见证
0x101b1d8cc→0x101b1d204 以 action=1、main-card 调专用 Reporter
0x101a974c0，构造 `tm.recommend.main-card.0.click`（调用者 default0）并 track，
进入 ClickEvent policy=0。该专用 builder 初始22字段中没有 position；只有后续
extra_rpt_fields/additionalDic 合并可能增加，不能套普通 show/duration 的 position。
它直接用 model.track_id，不走 HD args.track_id fallback；card_rel_id/
card_material_id 为 OptionalString，不套 HD 数字格式。其他模型 click 仍需逐一核对。

HD 原始响应 position 已闭合：刷新解析 0x10df59518 取 data.items，经 CardPool
循环 0x10df17fc0 从输入下标 0 开始，先调用模型配置回调（0x10df1807c），再执行
isValid/类白名单过滤。配置回调 0x10df59978 将原始下标+1 赋 report_flush_idx；
被过滤项仍会占用原始编号，留下的卡不按显示行重新排号。加载更多回调
0x10df5af0c 同样按本次输入数组下标+1 赋值，未加累计列表 count。因此这个位置是
原始单批次位置，不能套用到 Swift 响应分支。**Swift 侧的"+1 循环"是标准库 `sort` 的归并 run 记账，
不写任何卡片字段（R11 P0 已闭合）**：循环不在 `sub_101A3E5A4`（其函数体 0x101a3e5a4–0x101a3ebf4）里，
而在 `sub_101A3ECAC`（0x101a3ecac–0x101a3eebc）里；调用链是
`sub_101A3E5A4`（async 函数，0x101a3ea94 装配主队列 block `sub_101A4367C`）→ block 0x101a4367c →
`sub_101A3DDB8`（0x101a3ddb8，闭包上下文 x20，0x101a3de50/0x101a3de64 经 beginAccess 读被捕获数组）
→ 0x101a3de88 `bl sub_101A3EC44`（0x101a3ec44）→ 0x101a3ec90 `bl sub_101A3ECAC`。
三条标准库特征（阳性判据）：0x101a3ecd4 `bl _minimumMergeRunLength(_:)`（0x107c2b8b0，Swift stdlib
`_$ss22_minimumMergeRunLengthyS2iF`）、0x101a3ed18 `bl static_Array._allocateBufferUninitialized(minimumCapacity:)`、
0x101a3ed28/0x101a3ed30 把 [sp+0x18] 的数组槽初始化为 `__swiftEmptyArrayStorage`（0x11b093ef0）。
于是 0x101a3ed5c `mov x28,#0` 是该归并 run 的**起点下标**、0x101a3ed60 `add x8,x28,#1` 只做"单元素 run"
边界比较、0x101a3eddc `add x27,x24,#1` 只写 run 数组 count、0x101a3edf0 `stp x28,x23,[x8,#0x20]`
把 `(runStart,runEnd)` 对写进 **sort 自己的临时 run 缓冲**（stride 0x10、元素区 +0x20，与卡片对象无关）。
0x101a3ecac–0x101a3eebc 内无任何 selref/classref 卡片 setter（区间内唯一 `init` msgSend 在 0x101a3f6fc，
已在该函数体外）。排序结果唯一的写出点是 `tmpCardDatas`：0x101a3df28 取
`_OBJC_IVAR_$__TtC14BBPegasusSwift15FeedMixinAction.tmpCardDatas`（0x1203577a8），0x101a3df44
`str x27,[x28,x21]` 写回——与 position/flush_idx/report_flush_idx 三者都无关。
故 R11 的"存在 +1 循环 ⇒ 从 1 编号"**不成立**，"适用卡型"提法随之作废：该循环输入是
`- [BBPegasusViewController homeViewControllerHorizonalScrollWithProgress:isDragging:]`
（0x101a38eb0）区间内被闭包捕获的局部数组，不按 card_type 分派；卡型门禁在喂给它的上游
刷新/过滤链（0x101a3e1dc→0x101a4340c 的 compactMap、0x10df17fc0 CardPool 过滤）上，与编号无关。
真正写 `report_flush_idx` 的仍是上面 HD 链 0x10df59978（原始下标+1），不是本条 Swift 链。

### 不感兴趣的本地操作与请求

BaseCollectionVC 删除入口 0x10dee8598 先做 cell 广告 close/dislike 报告，再通过 VM
0x10dedceac 本地替换为 DislikeVideoModel，随后发送入口 0x10dedcd5c；本地改变发生
在服务端确认之前。disablePersonalizedRcmd 在该入口影响 toast，所有分支仍走
sendDislikeApiRequest。广告卡有独立分支；普通卡未登录则 0x10dede80c 不发。

通用请求 0x10dedeb28→0x10dedefc8 构造 API 并 requestAsync；URL 是
app.bilibili.com/x/feed/dislike（0x10df563cc）。params（0x10df563d8）始终放
id=param_id、goto=gotoType，nil 退空；reason_id/feedback_id/mid/rid/tag_id/ad_cb/
from/cm_reason_id/from_spmid/from_module/nature_ad/track_id 仅 length>0 时加入。
extraParams 最后 addEntries 覆盖默认值。此处 mid 来自卡片 args.up_id（UP），
不是账号 mid；rid/tag_id 来自正数 args.rid/tid。reason_id>0 且 reasonType=3 时
放 reason_id、=4 时放 feedback_id；includeCmReason 且 cm_reason_id>0 才放该字段。
from_spmid 来源是卡片 from_spmid 加 `.0.0` 或 default-value，goto 来自 card_goto。
该请求的响应、本地恢复、广告专支字段与当前版本验收仍未完成。
