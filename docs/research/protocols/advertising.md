# 广告加载与归因的静态入口

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 广告加载与归因的静态入口

UGC播放器广告有独立HTTP：BBAdPlayerAdUGCManager._requestUgcPlayerAdWithAid:cid:
0x1133e2c84先cancel当前request，创建新BFCApiOptions，GET
https://api.bilibili.com/x/v2/dm/ad（0x1133e2cf0/0x1133e2ffc）。四个业务params为
type="1"、oid=入参cid十进制、aid=入参aid十进制、ad_extra=下层返回String。
额外归因不是顶层字段：仅BBAdCmConfigManager.shared.avid等于入参aid时，分别
检查cm_from_track_id与ocpx_target_type非空，复制到ad_extra输入字典的
track_id/ocpx_target_type（0x1133e2d34–0x1133e2ea8）。两者多次读shared/getter，
未见一次性账号/归因快照。/data按BBAdPlayerAdModel、非array映射；新request
替换manager实例ivar后requestAsync（0x1133e3090/0x1133e3134）。此body未设置
timeout/auth/cache/responseQueue自有值。成功callback0x1133e31d8弱取原manager，
将/data model交_updateWithModel:；error0x1133e3250则交nil。两者不比较请求身份、
aid/cid或账号epoch；cancel不证明已排队回执不会更新。后续UI门禁已闭合：见下文UGC展示/事件侧触发段（五个KVO与chronos事件入口）。
updateWithAid:cid:0x1133e232c先reportEnter、清mixList/hasAd/icon并把当前aid/cid、
upperAvatar/from_spmid/from_track_id/ads_control存实例，再用_hasAdWithCid:
0x1133e44ac检查ads_control.has_danmu且cids中存在longLongValue==当前cid；通过
才上述请求（0x1133e26e0/0x1133e26f4），不由enableShowDanmaku直接阻止HTTP。
BBAdPlayerUGCAdService._fetchDanmaku0x1133f0ec8先把PlayerDanmakuPreference的
enableShowDanmaku传manager，再从两次currentScene读scene_avid/scene_cid交update。
manager.init另观察共享cm_config，skip1/takeUntil自身dealloc；回调只在共享avid≤0
或等于实例aid时用当前实例aid/cid再update（0x1133e220c–0x1133e22b8）。
成功model消费0x1133e3280先对每个mixList item及icon.ad_info报告raw61，即
UIEvent表中的danmaku_advert_result（0x11cf88798的raw61位置）。mixList报告在
Danmaku/Floating额外校验之前，不代表通过这些校验，也不是实际展示事件。
_reportWithEvent:model:0x1133e6154要求model.ad_cb非空，构造av_id/c_id（NSNumber，
零值仍0）、enable_show_danmaku字符串0/1及可选extra.cm_from_track_id，交
BBAdReportUIEvent.reportUIEventWithAdcb:event:url:params:，url空String
（0x1133e639c）。UIEvent普通入口0x11433f4d8使用needFilter=false/salt=nil，
具体发送/缓存/失败恢复见下述独立UIReport链。

requestAdExtraWithParams:0x114326f64将update=false交
_requestAdExtraWithUpdate:params:0x1143276c4。adExtraSwitch false直接返回空String；
true时先合并_adExtra基础字典，再只拣允许键及匹配class的调用方值
（0x1143277c0/0x114327b3c），JSON options0成功才交BBAdReportCrypto.
AESUpperStringWithDefaultKeyFromData:（0x114327808/0x114327834），最终nil也返回
空String（0x11432788c–0x1143278a0）。不是明文JSON直接透传；该UGC caller的
update=false不走更新位置一次性分支。基础字段、允许键类型、AES模式和加载触发/
展示/点击链仍在核对，未读取实际身份或发起广告请求。
基础字典_adExtra0x114327c40的候选String键为lng/lat/lbs_ts/network/operator_type/
ap_name/ap_mac/vendor/model/screen_size/idfa/ua/mobi_app/ua_sys/ua_web/os_v/
bootTimeInSec/countryCode/language/deviceName/systemVersion/machine/carrierInfo/
memory/disk/sysFileTime/hardware_model/timeZone/network_v2/boot_mark/update_mark/
story_shown_ids/dns_client_ip/initial_time/opensdk_ver。String setter
0x1143448d4要求非nil、NSString且length>0才插入，因此不是所有字段每次存在。
build另用ParamInfo.build.intValue（缺/空→0）boxed NSNumber；user_apps用probe
返回对象，nil→空String，通过safeSetObject（非nil对象/key才插入）。基础构造
先apInfoWithUpdate:true、locInfoWithUpdate:false及postbackInfo，再逐getter读取；
这些getter是否实时采集、权限是否通过属运行期系统行为（定位/IDFA/安装列表需真机权限），静态镜像不可判定，仅真机/9.13抓包核对ad_extra实际取值可验；候选键表见_adExtra 0x114327c40。
允许覆盖表0x1143278f0的19键有具体class：NSNumber的
disable_component_click_url/linked_creative_id；NSDictionary的
tab_req/view_req/comment_req/tab3_req/native_req/dynamic_req；NSString的
track_id/from_track_id/ocpx_target_type/ai_track_id/ai_from_track_id/creative_id/
request_id/caid/from_spmid/nature_ad/ad_story_extra。回调0x114327b3c只在输入值
isKindOfClass匹配时覆盖基础字典，未知键/错型忽略；此处允许空NSString，不能套
基础String setter的非空条件。
加密实际encryptAES:key:0x1143400c8使用CCCrypt Encrypt/AES、options raw1
（PKCS7、未启用ECB）、keyLength16、固定16字节IV（0x114340190–0x1143401ac），
即AES-128-CBC包装。key先以UTF8 getCString写17字节零初始化buffer，未在此body
检查转换BOOL；没有输出key内容。失败返回nil，成功data经每字节两位hex后
uppercaseString（0x11433ffb0–0x11433ffdc），空data/nil→空String，不是Base64。

UIReport实际请求与回执也已静态闭合。普通UIEvent的customBlock
0x11433fe8c先合并generateParameters，再合并caller params；后者覆盖同名字段
（0x11433fedc/0x11433fefc）。reportEvent:adCb:url:customBlock:
0x11433ccf0创建新item，timestamp为NSDate epoch秒×1000后截断到Int64
（0x11433cdb8/0x11433cdbc），生成参数、复制customBlock结果，再installParameters。
generateParameters0x11433e874含event/ad_cb/track_id/url/build_id/buvid/idfa/mid/
network/operator_type/ts/vendor/model/bootTimeInSec/countryCode/language/deviceName/
systemVersion/machine/carrierInfo/memory/disk/sysFileTime/hardware_model/timeZone/
dns_client_ip/initial_time/os_v；mid此时读BFCAccount.currentUser.mid并转十进制String
（0x11433ea30/0x11433ea40），不是API发出时重新读取。
installParameters0x11433efac只保留NSString key与NSString或NSNumber value，未要求
String非空；NSDictionary等嵌套value被过滤。这些是静态getter/schema，没有读取实际值。
_reportItem:0x11433d150要求item非nil、event非空、parameters非空，再排串行queue
com.bilibili.bbad.report.ui（init0x11433d038，dispatch0x11433d20c），单item参数
包装成一元素array交API（0x11433d2a0/0x11433d31c）。返回不等于网络成功。

BBAdUIReportApi.requestWithParametersArray:completionHandler:errorHandler:
0x11433e098使用NSMutableURLRequest/NSURLSession.sharedSession，POST
https://cm.bilibili.com/cm/api/conversion/mobile/v2。空array直接return，不调用成功/
失败handler。User-Agent来自uaWithEncode:false（nil→空String），Content-Type为
application/json，timeout15秒，body为{"uploads":参数array}的YYModel JSON data。
Memex.shouldCompressedByBrotli为true时Content-Encoding=br并替换压缩body；否则
才检查gzip（0x11433e210/0x11433e250）。压缩返回nil仍setHTTPBody:nil，未见回退
原JSON分支（0x11433e284–0x11433e290）。此路径不经过BFCApiRequest，不套用其签名/
ticket拦截器；URLSession自身的共享配置与Cookie实际行为属运行期会话行为（该body未创建URLSessionConfiguration），静态不可判定；验证需真机抓包核对cm.bilibili.com该POST的Cookie/头。
dataTask resume后释放局部task句柄，锁NSCondition并无条件waitUntilDate(now+
timeoutInterval+1)，即16秒；未在wait之前先检查done，wait返回BOOL也未使用
（0x11433e390–0x11433e3e0）。若完成信号早于wait，静态次序存在仍等到期限的可能，
未执行调度实验。wait后done=false才置done=true并生成domain
BBAdUIReportApiFailErrorDomain/code=-1001；未见在此分支cancel task。
网络completion0x11433e6f0在同一condition锁下只首次写data/response/error；done
已true时丢弃这些结果，仍signal/unlock。因此超时后的迟到成功不再转成业务成功。

成功须无transport error、HTTP status 200–299，且_BBAdUIReportApiModel非nil、
code字符串isEqualToString:"0"（0x11433e474–0x11433e4e8）；成功handler在此调用栈
接原data/response，未排main queue。失败统一新建上述domain、userinfo=nil的NSError：
transport error只保留code，非2xx用statusCode，模型缺失或code不匹配用model.code.
integerValue（模型nil→0），不是保留原错误说明（0x11433e524/0x11433e634）。
_reportItem成功handler0x11433d368随即_retryMoreThanInterval:0；失败
0x11433d374保存含原item的record。filename按event+identifier+url+timestamp
直接拼接，其中identifier0x11433f058是ad_cb+track_id（nil→空String）；没有分隔符/
账号分区。缓存为Caches/com.bilibili.bbad/report.ui的YYCache
（0x11433d090–0x11433d124），record与kUIAllRecordKeys分别写入；未证明两次写入
具有事务原子性。下一步 = disassemble.py 0x11433d038 0x11433d150 核对该两次写入（0x11433d090–0x11433d124），并 query_index.py '*RecordKey*' 10 收键集合来源。

_retryMoreThanInterval:0x11433d7cc逐缓存key处理，record缺失、f_index>4或
now_ms−item.timestamp≥86400001时删除（0x11433d8d4–0x11433d928）。入参interval
>0时还要求原item年龄>interval；读取的是item.timestamp，不是last_report_ts。
_reportAllRecords排相同串行queue后传3600000ms（0x11433d7c0/0x11433d7c4），
不是在此建立每小时timer。符合条件先从缓存移除、将原item.parameters与
is_reupload="1"合并，最多10条一批交同一API；原parameters后合并，若自身含
is_reupload会覆盖标记（0x11433d994–0x11433db0c）。未重新generateParameters，
因此mid等沿用创建item时的值；此body没有current账号/epoch校验。
批量成功handler=nil，先移除的record不再写回；批量失败callback0x11433db90对
捕获record逐个f_index+1、last_report_ts=本轮now_ms并_saveRecord
（0x11433dc30–0x11433dc54）。删除后发送前/失败重写前进程退出可能丢失队列项，
不能宣称恰好一次或持久化可靠投递。失败另发KntrAdAlarm.reportUiFailed，首次
is_retry="0"，重传is_retry="1"；该告警的出口后文已闭合为KntrAdAlarm.fire：
cm.ff.tt_alarm_enable与report采样率（fallback5）门禁通过后经epoch
mPlatformNeuron$1→BFCMikoto技术/metrics路径上报，非本POST的直接retry
（见本节末KntrAdAlarm段）。
这里另有尾批控制流缺口：发送判断只在当前record获准加入后检查count==10或
当前key为最后一项（0x11433da70–0x11433da90）。若已有不足10条的待发送项，
后续直到末尾的key均因缺失、过期、次数或interval被跳过，循环直接到
0x11433db38释放数组，没有循环结束后的flush；此前这些获准项已经从缓存删除。
这是本样本静态可达路径（0x11433da70–0x11433da90分支）；是否实际丢失取决于运行期缓存内容，静态不定量，复现需真机构造不足10条的待发送重试缓存后触发批量发送观察。
外部重传触发已定位：BBAdModule.onModuleInitialize0x10ea736b4先ParamInfo.
prepareInfo，再BBAdSingleton.shared.observeAppLaunch（0x10ea736c8/0x10ea736e4）。
observeAppLaunch0x10ea73fbc以object=nil登记UIApplicationDidFinishLaunchingNotification；
selector0x10ea74014先BBAdReporter.retryFailReportWithType:7，再UIEvent.retryFailReport
（0x10ea74028/0x10ea74038）。后者0x11433f894→_retryFailReport0x11433ff28取
UIReport.shared→reportAllFailEvents0x11433cfd8→_reportAllRecords，进入上述一小时
原item年龄门禁。不是每小时定时发送；这里也没给已经发生的启动通知做补发。
模块初始化真实注册/执行时机及实际通知交付仍未证，不能仅凭selector宣称启动必重传。
BBAdReport.retryFailReportWithType:0x114326e20按bit0/1/2分别触发AdOwn/AdMMA/
CntReport；它自身不调UIReport。UI重传是启动selector的另一显式调用，不把raw7
错误映射为四通道，也不把该模块扩展为全部广告SDK重传。

UIEvent filter语义另有边界：_reportUIEvent0x11433fbc4总要求eventStr非空；只有
needFilter=true才进一步要求adcb非空（0x11433fc38–0x11433fc50）。过滤key按
event/adcb/url/salt直接拼接后MD5，命中实例filters就丢弃，未命中在发送前加入，
不是网络成功后去重；ordinary needFilter=false无需非空adcb。
reportWithName:adcb:url:params:的默认repeat=true（0x11433f7a0），最终对repeat
xor1得到needFilter（0x11433f834）。因此以下App前后台使用空adcb仍能进入独立
UIReport请求，不能套用UGC manager自有的model.ad_cb非空门禁。

BBAdAppEnterStateReportManager.shared的首次构造0x11415f5bc创建实例，保存
ParamInfo.ts为coldStartTs、初始化RAM任务数组，并以object=nil注册DidBecomeActive/
WillResignActive通知（0x11415f66c/0x11415f6a8）。广告模块初始化会取此shared
（0x10ea736f8）；模块注册表的实际执行次序属运行期模块容器行为，静态仅穷举注册项。下一步：query_index '*BBAdModule*' 30 复核该模块全部注册入口。homeFirstScreenImageLoaded0x11415f6c0
报告app_enter_foreground，start_type="cold"、ts=coldStartTs（缺失退当前ts），
空adcb/url。该方法自身不检查是否首次报告；**调用方已穷举（team-c32）：外部去重不存在**——
实现 0x11415f6c0 无直接 BL 调用者（`find_callers`=0），共享 stub `_objc_msgSend$homeFirstScreenImageLoaded`
0x1173677c0 的 2 个命中都是 trampoline 自身（0x10f85372c / 0x1170ccb30，后者 0 调用点）；
回溯 trampoline 后**唯一真实调用点 = `bl 0x10f85372c` @0x10ea73b88 ∈
`-[BBAdModule onHomeFirstScreenImageLoaded]`**（0x10ea73b60 起），该 body 取 shared 后**无条件**调用，
且同 body 还做 `BBAdStartupAppsReport.execute`(0x10ea73b9c)、
`BFCPlayerCenter registerPlayerWithName:@"BFCPlayer_BBAd" fetchBlock:<全局 block 0x11cdab408>`(0x10ea73bb8)、
`BWAppletBizModuleManager`/`BBAdAppletBizModule` 构造 ⇒ 它是**模块初始化回调**，无首次上报门禁。
残余：模块初始化的实际执行次数属运行期模块容器行为。
DidBecomeActive0x11415f978保存Date epoch秒×1000的Double reportActiveTime，
捕获当时CFAbsoluteTimeGetCurrent，并main dispatch_after **30000000ns（0.03秒）**
（0x11415f9d4/0x11415f9d8）。该延迟callback先按捕获时间消费callup task，再在
isReportActive=true时报告app_enter_foreground/start_type="hot"；false只置true。
未在此callback读实际UIApplication状态或新的时间/代际，排队后快速失活仍可能
执行这段逻辑；main queue 0.03秒延迟（装载点0x11415f9d4）的实际调度次序属OS运行期行为，静态不可判定，验证需真机前后台切换日志。
WillResignActive0x11415fe98用当时epoch毫秒减reportActiveTime，比较常数Double
30.0（0x11415fee8–0x11415fef4），即此局部单位为30毫秒，不能写成30秒。差值
低于门槛仅isReportActive=false；达到门槛置true并报告app_enter_background、
空adcb/url。这些是本样本的运算/分支，不推断设计意图或其他版本同样行为。

callup停留任务makeCallupStayTimeReportTask0x11415f7e0新建对象、isCanceled=false/
isCallupSuccess=false、startTime=CFAbsoluteTimeGetCurrent，保存adInfo/url/extra；
在main直接append，否则main.async append（0x11415f8a0–0x11415f914）。
_performCallupStayTimeReportWithCurrentTime:0x11415fb38仅处理!canceled、success、
adInfo非nil，show_time=truncInt64((传入currentTime−startTime)×1000)，负数跳过。
构造BCMUIAdEvent/name=na_callup_app_stay_time、原adInfo/url，先合原extra再写
show_time十进制String覆盖同名字段（0x11415fcf8/0x11415fd40），最后report。
随后逆序清除canceled或success任务，不依据网络回执；success但adInfo缺失/
show_time负数的任务也会清除。这是本地任务消费，成功标记局部来源见下；
BCM事件发送桥见下文，不能把“唤起成功”当广告回执成功。
task.callupSuccess0x11415ffc0只setIsCallupSuccess(true)，写self+9；cancel
0x11415ffb8只setIsCanceled(true)，写self+8。没有网络ack、清另一个flag或直接
消费任务的逻辑，因此两flag可独立保持true，消费仍按canceled优先门禁。
已核实concrete openScheme:naCallupReportExtraParams:item:errorHandler:
0x114139888先构bcmModelFromItem、manager task（0x114139974–0x1141399b0），
将task强捕获于completion+0x20，再调用UIApplication.openURL:options:
completionHandler:0x114139a88。completion0x114139bbc按传入Bool bit0，true
callupSuccess0x114139be8、false cancel0x114139bf0，之后另行
reportCallUpStatus。即使弱取业务receiver结果nil，task flag分支仍执行。
另openScheme:item:openWhitelist:errorHandler: callback0x114139f80和
openScheme:item:trackID:reportParams:errorHandler: callback0x11413f16c也按
传入Bool对捕获task分支（0x114139fac/0x114139fb4、0x11413f19c/
0x11413f1a4）。这证明OS completion接受会标记本地成功，不证明目标app已呈现、
停留结束或服务端广告回执成功；任务只在后续DidBecomeActive延迟消费路径报告。
限定direct selectorstub0x117232740的其他caller也已定位：card callback
0x11413653c按Bool标记/取消（0x114136578/0x114136580），button callback
0x114137188按Bool尾调，AppStore callback0x114137fd4同样按Bool
（0x114138000/0x114138008）；trackID变体0x11413cb04、0x11413e668另有同selector
调用。它们的上层forceCallupSuccess/业务completion producer仍需分别审计，不把
全部callupSuccess写成仅UIApplication原始Bool或扫描穷尽全部动态调用。
button installedSchema分支也已闭合：public wrapper0x114136d70先将输入
forceCallupSuccess写**共享BBAdClickManagerHelper**（classref0x11f7b6ff0→
class0x1201c0038，0x114136dfc），再调用inner0x114136e64。inner自身未读取
incoming w5；isButtonShowOpenWithUrl:installedSchemaUrl:通过才构task、调用
UIApplication.openURL completion0x114137188，按原Bool标记成功/取消；否则转普通
clickButtonWithUrl:item:successBlock:failBlock:（0x114137134）。trackID inner
0x11413c7dc也不读取incoming w7，其installed branch同样openURL
0x11413ca00→completion0x11413cb04。不能从参数名推定该OS completion被改true。
共享force实际reader在needCallbackAfterCallup helper0x11413a034：先清
helper.callupCancel；原Bool true直接needCallback=true。false且URL转换nil同样
返回needCallback=true（0x11413a0dc→0x11413a22c）；有效URL才检查第三方
判据，发旧BBAdReportUIEvent raw40/41及open-white alarm raw2/3，随后置共享
callupCancel=true（0x11413a18c），再读共享force（0x11413a1ac）：true返回
needCallback=false，false返回true（0x11413a1bc–0x11413a22c）。这不是任务flag。
上述openScheme completion把helper返回作needCallback，却仍把**原OS Bool**作
reportCallUpStatus（0x114139c2c–0x114139c44）；report helper0x11413a274按原Bool
选择NA_callup_suc/fail（0x11413a524–0x11413a530），无条件报告旧UIReport
（0x11413a5a8），只有errorHandler非nil且needCallback=true才调用业务callback
（0x11413a5ec–0x11413a604）。force改变回调门禁，未在此改任务成功标记或该
UI事件的原始status；共享属性在completion时读取而非任务捕获快照，其他点击
写入的交错/账号代际未运行验证。

BCMUIAdEvent使用另一concrete发送链，不能直接套旧UIReport缓存规则：其report
0x114168954在日志后调用super，superclass已按class metadata确认为BCMAdBaseEvent；
super.report0x114168414→BCMReport.shared.report:。dispatcher为concurrent queue
com.bilibili.bcm.report.dispatcher（0x11416f708–0x11416f714），异步block
0x11416f7e8要求BCMReportItem protocol与shouldReport。UI subclass.shouldReport
0x1141684dc只要求name非空或extendedFields[event] String非空；reportType raw1。
该type经BCMReport.ui.reportParams:context:info:（0x11416f988/0x11416f9a4），
lazy ui0x11416fe0c构造BCMUploadsReport(name="ui")、reportURL为同conversion/mobile/v2。
UI subclass.buildReportParams0x114168574先base params、name/url及model归因字段，
再非空显式adcb覆盖model.ad_cb、extendedFields最后覆盖（0x1141688d4/0x11416890c）；
最终helper0x11416bc00读取bbad_params，若为NSDictionary就最后addEntries合并，
再无条件移除bbad_params/bbad_report_urls/bbad_tap_rect/bbad_filter_salt
（0x11416bc14–0x11416bc94）。因此嵌套bbad_params还能覆盖event/adcb/show_time等
此前字段；callup方法的show_time覆盖extra只是该层先后，不能宣称最终body必保留
计算值。helper没有旧UIReport.installParameters的String/NSNumber白名单过滤。
UI base helper0x11416ad04设置is_sdk_v2="1"、当下epoch毫秒Int64十进制ts，
再取BCMInfoCenter的buvid/mid/idfa/build_id/network，以及BBAdDeviceInfo的vendor/
operator_type/model；缺失值退空String。随后合BBAdDeviceInfo.CAID dictionary，
再写dns_client_ip/initial_time/os_v，返回copy（0x11416aff4–0x11416b108）。
BCMInfoCenter.registerInfoSource0x11416bd1c强存source；模块runnable name
BCMSDKModuleModuleInitialize0x10209e4d8对应entry0x10209e4f4→0x1020a0498，
body构造BCMSDKModule.AdSource后通过BCMConfig.initWithInfoSource
（0x1020a052c–0x1020a054c）注册，并调用BCMReport.retryFailedEvents
（0x114166f5c/0x114166f88）。该retry异步转ui/feeAd/feeMMA各自retryFailures
（0x11416fd94–0x11416fdf8），不是旧BBAdSingleton启动selector。
AdSource constructor0x1020a0348把当时BFCBuvid.buvid复制到自身buvid String
（0x1020a03b0–0x1020a03d4）；buvid:0x10209e62c读取该保存值，不每次读BFCBuvid。
mobi_app:同样读constructor传入的配置String。mid:0x10209e6b0则经helper
0x1020a0760从注入_account读取mid、转Int64 decimal String
（0x1020a07dc–0x1020a0808）；_account的静态type reference确认为BFCAccountService
protocol。其DI key cache0x120276360相对type reference0x1196bf256确认为
BFCAccountService；root334-service库存0x120272628的index6/slot0x1202726a8
确含AccountModule._$GripperAccountInfoModule。注册0x104c6f164通过0x10513162c
（0x104c6f1ec）绑定provider factory0x104c6fbc8→0x104c6f0b8→0x104c6f040。
factory构造_$GripperAccountServiceProviderDependencyProvider，service witness
0x1204a6d10的getter槽+0x10→0x104c6eed0→0x104c6ee54；后者首次分配
AccountServiceImp（0x104c6ee70–0x104c6ee84），保存provider+0x10并复用。
AccountServiceImp.mid:0x104c6e620每次调用BFCAccount.currentUser
（0x104c6e658），存在user再取mid（0x104c6e674），nil返回0
（0x104c6e69c）。这里缓存的是service对象，未缓存user/mid；没有mid存入buvid
快照的分支。注册存在不证明模块运行顺序或运行时没有替换该binding。
InfoCenter.buvid/mid若source不响应对应带参数selector就返回空String；idfa/build/
client_version/ua则先取BBAdDeviceInfo默认值，再允许source同名selector覆盖。
这些是当前source类及getter的有界证据，模块真实执行次序属运行期DI/模块容器行为，source替换需运行期证据，静态不可判定；静态可核残余：find_callers 0x104c6eed0 穷举 AccountServiceImp 构造方确认唯一 provider。不能把buvid和mid都写成相同生命周期的“实时公共身份”。
params是在dispatcher消费event时生成，不是在BCMUIAdEvent.report调用前冻结，
mutable event引用直到该阶段的所有权/并发影响需运行期线程调度证据，静态不可判定；静态可核残余：反汇编 dispatcher 消费点核对事件对象所有权转移（沿BCMUploadsReport 0x114174858串行queue下游）。

BCMUploadsReport.reportParams:context:info:0x114174858要求非空params，copy三项后
排自身串行queue com.bilibili.bcm.report.uploads.ui。reportURL及completion setter
也排同queue（0x114174708/0x1141747e8）。消费0x1141749bc构造单元素uploads请求
→BCMReportSession.sharedSession.request:modifier:，modifier为BCMUploadsModifier。
_requestWithParamsArray0x114175010使用NSMutableURLRequest、BCMInfoCenter.ua/
User-Agent、application/json、POST、timeout15秒（0x114175118），body为uploads
JSON；返回copy request，不在这个builder直接resume。modifier
sessionRequestCustomWillSendRequest0x114174308 copy请求后按BCMMemex选择br优先/
否则gzip；压缩nil仍替换body，没回原JSON。无压缩保持原body。
BCMReportSession.request:modifier:0x1141724c4只接受符合modifier protocol的传入对象，
否则用默认SimpleModifier；预处理返回nil直接返回nil。非nil则NSURLSession.sharedSession
dataTask/resume→NSCondition无条件wait(now+request.timeout+1)，done与迟到结果门禁
同旧链的结构（0x114172674–0x11417270c/0x1141728e0–0x114172944），超时NSError
BCMReportNetworkErrorDomain/-1001，无task cancel。wait返回BOOL未使用，早到signal
仍可能等待期限；这里未执行线程调度或真实请求。
Session将data/response/error包装后交modifier响应加工
（0x114172728–0x114172754）；UploadsModifier0x1141740e8要求无transport error、
HTTP200–299、_BCMUploadsModel非nil/code String="0"才留下error=nil。其他情况
另建NSError：transport用BCMReportNetworkErrorDomain/原error.code，非2xx用
BCMReportServerErrorDomain/HTTPstatus，业务码/缺模型用BCMReportNonZeroErrorDomain/
model.code.integerValue（常量slots0x11cf85938/0x11cf85940/0x11cf85948），userinfo=nil；
模型nil的code路径仍为0。Uploads自身_validateSessionData0x11417521c只检查
sessionData非nil且error=nil，不能把它当第二次解析业务码。
首次成功会_retryMoreThanInterval:0；失败保存BCMReportRecord，随后调用自己的
completion（0x114174adc/0x114174d28/0x114174d64）。缓存名report.uploads.ui与
旧report.ui不同。首次失败新建record，filename为原builder请求的URL.absoluteString、
未压缩HTTPBody的MD5及发送前epoch毫秒，用"|"分隔（0x114174b04–0x114174bdc）；
新record.f_index再加1，first_report_ts与last_report_ts都取该发送前时间
（0x114174c1c–0x114174c40）。保存params时先放is_reupload="1"再合原params，
原值可覆盖标记；reportURL/context/adInfo一并保留。这里没有账号分区或切换账号
时重建params的分支，重传沿用保存的归因及身份值。

BCM retryFailures0x114174f8c排自身queue，block0x114175000传3600000ms；
同样是原记录年龄门禁，不是每小时timer。_retryMoreThanInterval:0x114175260
先删除缺失record或空reportURL的key；URL非空但与当前sender.reportURL不相等时
跳过并保留（0x1141753a0–0x114175408）。匹配URL后，f_index>3或
now_ms−first_report_ts≥86400001才删除（0x114175414–0x114175454），与旧UIReport
的>4及item.timestamp来源不同。可选abandon回调reason raw0用于空URL等无效记录、
raw1用于次数超限、raw2用于过期；缺失record不传nil对象给该回调。
interval≥1时还要求now_ms−first_report_ts>interval，没用last_report_ts
（0x114175564–0x114175584）。获准后先removeRecordForKey，再把保存的params
加入最多10条的batch（nil params退空dictionary）。批量失败才对各record的
f_index+1、last_report_ts=该batch发送前now_ms并saveRecord；成功不重写缓存
（0x114175750–0x114175794）。两种结果都逐record调用completion，传success、
本轮递增前的f_index、保存的params/context/adInfo及sessionData.error
（0x1141757a4–0x114175840），不能把completion中的retry数当递增后值。

BCM也存在上述尾批缺口：flush仅在获准分支检查count==10或当前key为最后项
（0x1141755f4–0x114175614），跳过末尾key会经0x114175538–0x114175560直接退出
到0x114175a18，未补发已删除且不足10条的待发送batch。URL不匹配也能走该跳过
路径；这是静态控制流结论（0x1141755f4–0x114175614分支），是否实际发生取决于运行期缓存记录数，属需真机复现性质。AdAlarm的KNeuron/Mikoto出口及
BCM source账号DI见本节独立链；实际模块调度/事件触发仍需区分。

BCM UI completion0x11416fe7c在请求结果后调用BBAdInterceptor.syncWithBlock
（0x11416ff54）。此concrete helper0x104838c70先检查BBAdConfig.isInspectorEnabled，
false不执行传入block；true取KntrAdInspectorManager.shared并同步调用block
（0x104838cec–0x104838d18）。观察block0x1141703d0由保存params重建单条uploads
JSON字符串，addUIReportJobRequestBody/adId=adInfo.ad_cb/isRetry=(旧f_index>0)，
再按success调用job.successData:nil或job.failReason:错误码格式串
（0x1141704a4/0x1141704f0/0x114170560）。它不是发送前拦截器，不修改已经发送的
请求，也不是批量重传实际HTTPBody的原始捕获；一批多条时这里仍逐record造单条body。

success=false另发KntrAdAlarm.reportUiFailed（0x114170134），commonParams来自
adInfo.makeKntrAlaramParams，nil退empty。extra有is_retry=(旧f_index==0?"0":"1")、
fail_count=旧f_index十进制、is_bcm_report="1"、desc/code来自加工后的NSError、
ad_cb和保存params[event]，不是新解析response payload。旧f_index==0还会调用
BBAdKtTracker.trackWithEvent raw9（0x1141701a0–0x11417031c），success时desc="success"/
code="0"，failure用错误说明/码；重传不进入此raw9分支。这两种观察事件与原POST
回执是后续动作；其最终sender与采样门禁已在本节后文闭合：raw9经
KntrAdTrack.uiReport到AdTrack/KNeuron/Mikoto，受cm.ff.tt_track_enable与
data/action/report三采样率门禁（见下AdTrack采样段及enum rate表）；
KntrAdAlarm侧受cm.ff.tt_alarm_enable与data/click/status/report四率采样，
出口为同一epoch mPlatformNeuron$1→BFCMikoto技术/metrics路径（见本节
"KntrAdAlarm不是另一条已证直连URL"段）。因此门禁通过时这两类事件确会
经BFCMikoto产生后续上报调用，但函数返回不等于HTTP成功。

计费与MMA是另外两类BCM传输：BCMFeeAdEvent.reportType=0x100
（0x114168f64），shouldReport0x114168f6c要求model.bcm_is_ad_loc且name或
extendedFields[event]非空。其params按common helper0x11416b10c→model归因
helper0x11416b798→name→extendedFields→最终bbad_params合并，交dispatcher
bit8分支feeAd.reportParams（0x11416fb04–0x11416fb20）。lazy feeAd0x1141705bc
构造BCMUploadsReport(name="fee.ad")，POST
https://cm.bilibili.com/cm/api/fees/wise（0x114170604/0x114170608），沿用同Uploads
JSON/压缩/session/业务码/批量cache机制，但cache名为report.uploads.fee.ad。
它不是UI conversion地址；Once去重已闭合（FeeAd Once.shouldReport 0x1141692e0，见下文Once段）。业务触发者与common完整字段为共享stub全量扫残余：下一步 find_callers 0x1141705bc 穷举 feeAd lazy getter 调用方，common字段沿0x11416b10c逐helper展开。

BCMFeeMMAEvent.reportType=0x200（0x114169800），shouldReport0x114169808要求
bcm_is_ad_loc且stringURLs.count>0；单条URL能否发送成功属网络运行期性质，静态不判定（构造闭合于0x114169884逐项替换/长度过滤）。buildReportURLs
0x114169884按原stringURLs顺序逐项用bcm_MMAURLWithInfo:extendedFields:替换/
加工，只保留返回String.length>0；模板替换字段与编码细节尚待追踪。
dispatcher bit9分支0x11416fce4–0x11416fd00交feeMMA.reportURLs:context:info:；
lazy feeMMA0x114170f60构造BCMURLReport(name="fee.mma")，不是Uploads sender。
该对象queue com.bilibili.bcm.report.url.fee.mma、cache report.url.fee.mma，
modifier为BCMReportSessionSimpleModifier（0x114172db8–0x114172e50）。

URLReport.reportURLs0x114173044 copy URL数组/context/info，排自身串行queue，
block0x1141731a8逐URL新建currentTask(index=0)并分别同步走同BCMReportSession。
_requestWithReportURL0x114173764对NSString trim首尾空白/换行→NSURL.URLWithString，
非nil才构造GET、BCMInfoCenter.ua、timeout15秒，无uploads body
（0x1141737a4–0x11417389c）。这里未见host/scheme allowlist或业务签名；NSURLSession
实际允许的URL与系统拒绝仍不能从该局部body替代验证。URL解析nil会先存
BCMReportRequestErrorDomain/-3001；随后_validateSessionData:nil又以同domain/-1
覆盖currentTask.error（0x1141738ec/0x1141739c4）。SimpleModifier0x1141729ec只以
transport无error及HTTP200–299判成功，不解析JSON/code；失败分别归Network/Server
domain。URLReport._validateSessionData0x11417392c只看sessionData/error，并把error
写currentTask。故MMA的2xx成功不能套UI/fee.ad的业务code="0"条件。

首次URL失败在请求结果之后取now_ms，保存record.f_index+1、first_report_ts/
last_report_ts=此时now、原加工后URL/context/adInfo（0x11417343c–0x1141735fc）；
filename由builder URL/HTTPBody MD5/now用"|"拼接，缺失项为空String。它不保存
参数dictionary，也不在重传时重新做MMA模板替换。每次结果随后_complete调用
completion(currentTask)，没有统一main切换（0x114173614/0x114173a00）。
首次URL成功会increase sentinel并排同queue **10秒**后_retryMoreThanInterval:0，
closure仅当sentinel仍等于捕获值才执行（0x1141733a4–0x114173430、
0x11417369c–0x1141736d0），一串成功中的较旧排队重传会失效；不能写成成功后
立即重传。公开retryFailures0x1141736e0仍排interval3600000ms。

URL retry0x114173a84删除缺失/空URL、f_index>3或首次失败年龄≥86400001ms；
interval≥1则要求now−first_report_ts>interval。符合条件先从cache删除，再逐条
以保存URL发GET，新currentTask.index取旧f_index，失败才f_index+1并保存本次
失败后的last_report_ts；两种结果都_complete（0x114173d08–0x114173f38）。
这里没有Uploads的batch或sender.reportURL匹配，不能复制其尾批漏flush结论。
删除后发送/重写前的进程退出仍可能丢失项；MMA completion/abandon告警与真实
业务URL producer继续追踪，未运行第三方URL请求。

MMA模板helper0x11416da88先copy原String；空String直接原样返回。非空时
BCMAdInfo.modelWithItem取model，再构造宏dictionary：__TS__取调用时epoch ms
Int64 decimal（0x11416db44–0x11416db9c），__OS__取BBAdDeviceInfo.os；
__BUVID__/__MID__取BCMInfoCenter可选String，__IDFA__取InfoCenter.idfa，
空值采用静态占位，__IDFAMD5__取该String的MD5。占位IDFA时另检查
model.macro_replace_priority：raw1对非http前缀或命中origin-macro domain list
删除IDFA/MD5两宏，使原URL占位符保留（0x11416de60–0x11416de9c）；raw2对非http
前缀或命中empty-list domain list将两宏置空（0x11416ddfc–0x11416de48）；其他
情形保留静态占位及其MD5。这里仅hasPrefix("http")，不是严格scheme验证，
BCMMemex列表实际配置内容由服务端下发（macro_replace domain list消费点0x11416de60–0x11416de9c），静态镜像不含取值，属9.13抓包核对项。
__UA__单独经bfc_urlEncodedString（0x11416dec4），__REQUESTID__/__IP__取
model.bcm_request_id/bcm_client_ip，__CREATIVEID__/__SHOPID__/__UPMID__仅
正整数decimal，__TRACKID__取track_id。六个motion宏__WIDTH__/__HEIGHT__/
__DOWN_X__/__DOWN_Y__/__UP_X__/__UP_Y__先有静态缺省；非nil motionValue经
0x11416cb2c转换dictionary后覆盖（0x11416e134/0x11416e154）。tapRect入口
0x11416d984仅非empty CGRect生成motionValue，Double→Int64截断，宽高及
down/up两组坐标都取同一rect origin（0x11416d9f0–0x11416da20）。
最后extendedFields整dictionary再merge，能够覆盖上述任意宏
（0x11416e160–0x11416e170）；bbad_formatToStringKeyValue0x1141782c0保留
NSString或能respondToSelector(stringValue)的key/value，无法转换者省略。
enumeration block0x11416e2b0只处理同时以"__"开头/结尾的key，对当前结果串
stringByReplacingOccurrencesOfString全量替换（0x11416e2e0–0x11416e334）。
不是统一URL query编码，除UA之外不在此helper额外encode；dictionary枚举顺序
不保证，若扩展value带其他宏，嵌套替换结果可能受顺序影响。未知宏保留，helper
没有hostallowlist、最终URL有效性或签名检验，后续GET builder才URLWithString。
因此MMA缓存保存的是已替换URL，重试不重新读此宏dictionary/当前身份/时间。

BCM Once admission与网络成功独立。UI Once.shouldReport0x114168b74、FeeAd
Once.shouldReport0x1141692e0先过super shouldReport，然后取eventHash（非nil即
采用，空String不fallback）或defaultHash；extendedHash非nil时追加"|"+值，
再追加"|"+event.name，nil片段经0x114177b78转空String。UI defaultHash
0x114168dbc为MD5(model.ad_cb+"|"+event.url)，FeeAd defaultHash0x114169528
为MD5(model.request_id+"|"+source_id decimal+"|"+creative_id decimal)。查询
共享BCMEventRecord.contain，未命中先record再返回true
（0x114168d44–0x114168d80、0x1141694b0–0x1141694ec）；已命中返回false。
去重key未直接加入账号/时间/类型前缀；**业务eventHash producer已穷举（team-c32）：只有 3 个类声明 `eventHash`**
——`BCMUIAdOnceEvent`（getter 0x114168eec / setter 0x114168efc / ivar 0x11f89d344）、
`BCMFeeAdOnceEvent`（0x114169710 / 0x114169720 / 0x11f89d354）、`BCMFeeMMAOnceEvent`
（0x11416a724 / 0x11416a734 / 0x11f89d36c）；共享 stub `_objc_msgSend$eventHash` 0x1172efb40、
selref 0x11f666d78。`find_callers.py 0x117586080`（`setEventHash:` stub）的 3 个命中里 2 个是
trampoline 尾跳（0x10f876578、0x1170efa10，后者 0 调用点），回溯后**真实写入点只有 2 处**：
`-[BBAdUserSpaceEnterpriseBaseCell reportShowForExpose]` @0x10f6bc794、
`+[BBAdIMServiceImp enterpriseLinkDidShowedWithImContext:message:]` @0x10ea74854。
另：UI-Once 家族用**独立键**——`+[BCMUIAdOnceEvent reportUIOnceEventWithName:adcb:url:params:]`
（0x1141676e8）在 `setName:/setUrl:/setAdcb:/setExtendedFields:` 之后读
`extendedFields[@"bbad_filter_salt"]`（CFString @0x1141677cc），过 `isKindOfClass`+`length` 门禁后
调 **`setExtendedHash:`**（0x114167820）再 `report`（0x114167828），该 body 内**没有** `setEventHash:`。
⇒ 去重键（`eventHash` / Once 的 `extendedHash←bbad_filter_salt`）确实不含账号/时间/类型前缀；
残余：两个 `eventHash` 站点传入串的上层构造与 Once 登记语义（是否只在成功后登记），
共享片段转空 String helper 仍为 0x114177b78。

MMA Once在buildReportURLs0x11416a1a8逐条检查**原stringURLs**，同样取
eventHash或defaultHash（0x11416a53c，request_id/source_id/creative_id三项MD5），
可选extendedHash后拼"|"+当前原URL，而非event.name。未命中项先加入输出再
record（0x11416a400–0x11416a42c），输出覆盖self.stringURLs
（0x11416a49c），之后才super.buildReportURLs0x11416a4c0做宏替换。故宏替换
或后续URL解析失败前已占去重资格，同一串里后续重复原URL正常会被前项挡住。
其buildReportParams0x11416a138直接返回super.extendedParamsFields或空dictionary，
不能据method名推断它走Uploads POST。

BCMEventRecord.shared0x11416ab24用进程once创建，init0x11416ab80创建mutable
set及semaphore(1)。contain0x11416ac04与record0x11416ac74分别wait forever、
查containsObject/加addObject、signal；nil参数分别false/no-op。已检查这些body
没有磁盘持久化、时间expiry、移除或账号监听。但contain与record之间释放了锁，
caller没有跨两步锁，不能宣称并发原子check-and-record；实际dispatcher外部串行
约束与进程生命周期外reset仍需另证。这个内存Once记录与失败retry磁盘cache分开。

UI completion的BBAdKtTracker raw9进一步闭合为KntrAdTrackEvent.uiReport：
trackWithEvent ObjC桥0x104912d20→通用bridge0x104913020→callback
0x104913794，event转换0x104913724查十项selector表0x11b2eb7a0，raw9对应
slot0x11f798c00/uiReport。callback把BBAdTrackParams转
KntrAdTrackCommonParams（0x1049134ec，initWithRequestId:resourceId:srcId:
creativeId:cardType:extra:），nil参数先创建空BBAdTrackParams；extraMap nil取空
dictionary，再KntrAdTrack.shared.trackEvent:commonParams:extraMap:
（0x1049138b0）。此已检查路径没有读cm.ad_track_disable。另独立
adTrackEnabled getter0x1049133fc按配置cm.ad_track_disable整数==0返回true；
wxCallUp专用helper0x1049138f4自行读取同配置，非零直接返回
（0x1049139dc），但它不是raw9通用callback。不能因getter/其他helper存在，就
宣称UI completion也已过该门禁。KntrAdTrack内部另有如下tt_track_enable和采样
门禁，实际Mikoto service binding如下，网络行为仍按其独立链判断。
Kotlin导出表也已定位，避免把SelectorsHolder dummy方法当业务实现：
type adapter0x120595930关联TypeInfo0x11b748360
（kntr.app.ad.domain.track/AdTrack），ObjC名KntrAdTrack；唯一instance method
entry0x11ccc7720取trackEvent:commonParams:extraMap:→export shim0x10bcb3b88，
转换参数后0x10bcb3cf0调用实际AdTrack body0x107ab8924。body已追到KNeuron
singleton0x120c5e448→wrapper0x105d60bc8，以接口hash raw0x13780、slot+0x38
间接dispatch（0x107ab9664）。wrapper初始化0x105d60a10分配TypeInfo
0x11b4fa4b0（kntr.base.neuron/KNeuron），通过injected provider接口hash0x901
取service并保存+8（0x105d60b74/0x105d60b7c）；实际provider implementation和
该slot具体sender现已由如下DI闭合；最终发送仍需按Mikoto/Neuron独立链判断，
不据KNeuron名称认定复用普通BFCNeuron click出口。
KNeuron provider mPlatformNeuron$2.invoke0x105d61454解析KClass
0x11c643b90（TypeInfo0x11b4fa210，NeuronEntryPoint），interface hash0x18e
slot0实际为0x10b928fcc；经root getter0x10b91f73c取component+0x98，调用
provider hash0x584→producer hash0x587/method2。该field由0x10b931068存储，
SwitchingProvider raw id21（0x10b93105c），group0 table0x118652e72[index21]
raw0x3bf→0x10b93d09c→0x10aab14ec。singleton raw producer0x11cb3e168的
getter0x10aab159c→initializer0x10aab1a68，返回cache0x120c6cbf8，具体type
0x11bb40710为kntr.base.neuron.epoch.impl/mPlatformNeuron$1。
初始化经epoch NeuronModule classref0x11f7bf170创建module，neuron getter
0x10aab1c50结果存+0x10、mikoto getter0x10aab1d54结果存+0x18；原生neuron
getter0x100205b94的keypath0x118269168/0x118269190目标确为BFCNeuronService。
但AdTrack调用hash0x13780/+0x38实际是table0x11c34b2d0[7]→0x10aab5388，
该方法用**+0x18 Mikoto**。调用Function0取boxed Bool
（0x10aab54a8/0x10aab54b0），event String不等infra.metrics且Bool false时
返回（0x10aab5528）；true时trackTech:extendedFields:policy:rate:
（0x10aab58d4），rate100，输入Bool非零policy1、零policy2。
infra.metrics路径从fields[command]构URL，成功trackNetWithURL:extendedFields:
（0x10aab59dc），另加kmikoto::simpler按Function0 Bool为"1"/"0"；缺command/
URL转换失败走trackTech policy1/rate100（0x10aab5c38）。此是边界分流，不是
本调查发送URL。相对普通click接口slot1→0x10aab5f30才读+0x10，创建clickEvent
0x10aab6098、设置extendedFields后trackEvent:trackPolicy:0x10aab6340。
epoch mikoto getter0x100205c54的keypath0x1182691b8目标
0x1196bee2a为BFCMikotoService.Type。实际MikotoProviderModule.register
0x104958138用key0x120274f78，factory0x1049582a0→0x104958100→provider
constructor0x104958088；witness0x12048db40/+0x10→0x104958060→lazy getter
0x104958014，未缓存时builder0x104958254取ObjC classref0x11f7b6e08
**BFCMikoto**，Swift ObjC metadata缓存0x12048db58，再写provider+0x10。
这供应类/元类型，符合epoch initializer的metaclass+conformsToProtocol
BFCMikotoService检验（0x10aab1df4–0x10aab1e28），不是任意同名service。
334项root false/raw0 service inventory中index195/String slot0x120273278
确为MikotoModule._$GripperMikotoProviderModule，补齐注册库存关系。
依赖注册/解析执行仍为运行条件。上述ad.track.*非infra.metrics事件在配置和随机
门禁接受后转BFCMikoto.trackTech，适用前述logId002312/native trackEvent采样
与异步Neuron入队边界；不能把函数返回、本地observer通知当HTTP成功。

AdTrack基础map已定位：request_id（0x107ab8af4）、resource_id decimal
（0x107ab8b84）、src_id（0x107ab8bec）、creative_id decimal
（0x107ab8c7c）、card_type（0x107ab8ce4），nullable String取空。
cm.ff.tt_track_param_with_large_param对应lazy global0x120c65468、getter
0x107aba324；true才加入common.extra（0x107ab8d58），false且incoming extraMap
含item则复制map并移除item（0x107ab8de4–0x107ab8e24），不修改原incoming map。
filtered extraMap先复制为输出，再遍历common map覆盖同key
（0x107ab8f64、0x107ab9328），不能按ObjC extendedFields优先规则类推此合并。
另cm.ff.tt_track_enable lazy0x120c65460在发送前要求Bool==1
（0x107ab95b8/0x107ab95bc），不满足绕过KNeuron；与前述cm.ad_track_disable
独立。initializer0x107aba204创建五个lazy：track_toggle$2、
param_with_large_param$2、data_sampler$2、action_sampler$2、report_sampler$2。
后面三项读取cm.config.tt_track_data_rate、cm.config.tt_track_action_rate、
cm.config.tt_track_report_rate（0x107abaafc/0x107abab48/0x107abab94）；最终
采样Function0由TypeInfo0x11b748400、+8捕获event
（0x107ab9614/0x107ab9650），funcTable0x11c037770/+0x10实际invoke
0x107ab9880。读取kotlin.random/Random.Default global0x120c5a930
（initializer0x10528ff94、TypeInfo0x11b37cad0），对+8 delegate
TypeInfo0x11b36f940（kotlin.random/NativeRandom）的virtual+0xf0
0x105290198传from0/until100（0x107ab9928/0x107ab992c）；实现取range=until−from，
100走UInt随机右移1、remainder和拒绝重采样（0x10529028c–0x1052902a0），
until排他，即0..99。用signed
random<event.+0x14 Int32决定Bool（0x107ab9934–0x107ab9940）。没有在该body
按用户hash或固定种子稳定分桶。AdTrack传入sender Bool=0
（0x107ab9658），非infra.metrics被lambda拒绝就不trackTech；接受才raw policy2/
native rate100。metrics则把该Bool写simpler字符串而不按false直接丢弃。
捕获event阈值producer已闭合为enum initializer0x107ab9978：创建十个
AdTrackEvent TypeInfo0x11b7484a0并存array global0x120c65450；ordinal存+0x10、
rate存+0x14、实际event String存+0x18。下表是enum ordinal，并非未经证明的其他
bridge raw值；上述ObjC转换按selector选择同名enum。

| Ordinal / event | 实际event String | rate来源 / 写入site |
| --- | --- | --- |
| 0 appstoreLoadStatus | ad.track.appstore-load-status | action_sampler，0x107ab9d48→0x107ab9d90 |
| 1 adData | ad.track.ad-data | data_sampler，0x107ab9dec→0x107ab9e88 |
| 2 click | ad.track.click | action_sampler，0x107ab9e94→0x107ab9ed8 |
| 3 wxCallUp | ad.track.wxprogram-callup | action_sampler，0x107ab9ee4→0x107ab9f28 |
| 4 appCallUp | ad.track.app-callup | action_sampler，0x107ab9f34→0x107ab9f78 |
| 5 appDownload | ad.track.app-download | action_sampler，0x107ab9f84→0x107ab9fc8 |
| 6 webViewLoad | ad.track.webview-load | action_sampler，0x107ab9fd4→0x107aba018 |
| 7 mmaReport | ad.track.report-mma | report_sampler，0x107aba024→0x107aba068 |
| 8 feeReport | ad.track.report-fee | report_sampler，0x107aba074→0x107aba0bc |
| 9 uiReport | ad.track.report-ui | report_sampler，0x107aba0c8→0x107aba10c |

action getter0x107aba438读lazy0x120c65478、report getter0x107aba54c读
0x120c65480；data读0x120c65470。三个配置String经处理helper0x10529f5ac，
再按十进制Int解析，
nil/解析失败走调用fallback（0x107aba660–0x107aba7e4），此body未做0..100
clamp。三个caller的静态fallback分别data100（0x107abab20）、action100
（0x107abab6c）、report5（0x107ababb8），不是读取本机/远端的实际配置值。
enum initializer按once flag0x120c79e08只写这些rate快照；本次静态检查
没有每次track重读远程配置或对现有enum改rate路径。random比较仍每次调用，
不能把lazy rate缓存写成一次随机决定，也不因native rate100断言全量上传。

KntrAdAlarm不是另一条已证直连URL。导出表0x11ccc4610的fireEvent桥
0x10bc93474转换参数后调用AdAlarm body0x107ab486c
（0x10bc935dc），TypeInfo0x11b747a40。common接口hash0x19b00五个getter
（0x107ab49bc/0x107ab4a2c/0x107ab4a94/0x107ab4afc/0x107ab4b68）生成
request_id/creative_id/src_id/card_type/extra；nullable值先替为空String。
0x107ab4bbc→0x105283fd4创建新map，先复制common（0x10528408c），后合
extraMap（0x105284098→0x1052463f4），故extras覆盖同key，与AdTrack次序不同。
之后first pass读取Map.Entry slot+0x8的**value**，nil则跳过
（0x107ab4f44/0x107ab4f4c）；非nil才取key/value放入输出。实际
HashMap.EntryRef TypeInfo0x11b372240的hash0x980 methods0x11bd24198
为0x105249a94（keys）/0x105249b50（values），已核实槽位而非猜测key过滤。
put旧entry允许nil（0x1052463bc），因此extra nil能覆盖common后被过滤移除，
不会回退common。second pass的非nil断言0x107ab5210→0x107ab5450
是异常分支，不能将正常过滤过程写成常规业务崩溃。

initializer0x107ab64b4创建alarm_toggle及data/click/status/report四个lazy。
总开关cm.ff.tt_alarm_enable（invoke0x107ab6d38，default Bool1）缓存于
0x120c65420；fire要求boxed Bool==1（0x107ab4d20–0x107ab4d34）才调用sender，
未证每次重新查询配置。四rate配置分别cm.config.tt_data_rate（0x107ab6e00，
fallback5）、cm.config.tt_click_rate（0x107ab6e4c，100）、
cm.config.tt_status_rate（0x107ab6e98，80）、cm.config.tt_report_rate
（0x107ab6ee4，5）；helper0x107ab6a2c按radix10解析，缺失/解析失败用fallback，
未见clamp。这些是静态默认值，不是本机或服务端实际配置。
AdAlarmEvent initializer0x107ab55b8创建21项；ordinal+0x10、rate+0x14、
独立reportName+0x18，fire取后者（0x107ab4d84）。event name/rate赋值如下：

| rate getter | reportName（前缀ad.ops.） | name写入site |
| --- | --- | --- |
| data，0x107ab65dc | data.no-adinfo；data.unsupport-card-type；data.material-invalid | 0x107ab5d18；0x107ab5d68；0x107ab5db8 |
| click，0x107ab66f0 | appstore.load-status；click.no-react；click.wxprogram-callup-failed；click.openwhitelist-failed；click.downloadwhitelist-failed；webview.load-failed；iaa.load-failed；iaa.show-failed | 0x107ab5cc8；0x107ab5e08；0x107ab5e58；0x107ab5ea8；0x107ab5ef8；0x107ab5f48；0x107ab6178；0x107ab61c8 |
| report，0x107ab6918 | report.mma-failed；report.fee-failed；report.ui-failed；report.fee-abandon；report.ui-abandon；report.mma-abandon | 0x107ab5f98；0x107ab5fe8；0x107ab6038；0x107ab6088；0x107ab60d8；0x107ab6128 |
| status，0x107ab6804 | iaa.load-status；iaa.show-status；iaa.playable-load-status；iaa.plugin-request-status | 0x107ab6218；0x107ab6268；0x107ab62bc；0x107ab6308 |

其中appstore.load-status明确走click，不能按后缀猜status。fire创建
AdAlarm$fire$$inlined$runCatching$1（TypeInfo0x11b747ae0）并捕获event+0x8
（0x107ab5274）；KNeuron wrapper0x105d60bc8调用site0x107ab5284传
Bool1/name/finalMap/采样Function0。lambda invoke0x107ab54c0每次取Random
整数0..99（0x107ab5568–0x107ab5570），signed比较random<event.rate
（0x107ab5578/0x107ab557c），返回boxed Bool。它是采样判据，不是response
callback；下游已证复用epoch mPlatformNeuron$1→BFCMikoto技术/metrics路径。
本体没有direct completion、递归send或timer retry；此范围不排除下游持久化/
重试，也不能由fire返回或采样接受推断实际HTTP成功。


Monitor producer的有限审计需保留receiver边界：class0x1201c2b30/RO0x11f090bd8
是BCMMonitorUIAdEvent，class0x1201c2b80/RO0x11f090c88是
BCMMonitorUITrackEvent。BCMAdBaseEvent.eventWithInfo0x114168338确会alloc输入
class receiver（0x114168358）；reportName:info:url:params:0x114167438保留
incoming class并交该builder，理论可构造subclass；实际receiver结论见本段末闭合段。
常见reportUIEvent两variant0x114167520/0x114167624则硬编码BCMUIAdEvent
classref0x11f7b9cb8（0x114167548/0x11416764c），不能按继承selector推Monitor。
BBMallAdHelper.reportMonitor0x103a338a8→0x103a33fbc实际是宏替换URL→
URLRequest（0x103a34310）→NSURLSession.shared/dataTask/resume
（0x103a34374/0x103a343e4/0x103a34418），也不证明BCM Monitor endpoint。
Monitor业务实例/事件名producer在本静态镜像内已闭合为不存在构造点：
find_data_refs_root.py与find_pointer_refs.py对0x1201c2b30、0x1201c2b80、
0x11f090bd8、0x11f090c88四个类对象/classData地址均返回零引用（同工具对
已知BCMUIAdEvent classref 0x11f7b9cb8可返回命中，排除工具漏检）；即全镜像
无任何代码构造这两个类或以其为receiver调用eventWithInfo。残余边界仅剩
运行时动态构造（非镜像代码、反射或下发配置），静态不可再收敛。


HD2首页广告strict producer另有实际链：BBHD2PhonePegasusAdSingleCell
strict0x10df15718只把rect/extra转adView（0x10df1579c）。lazy factory raw3
（0x10df14e88）→BBAdPGView mapper0x113ba0cb8→BBAdPGHDOddView
（0x113ba0df4–0x113ba0e10）；strict0x113bcc378转其mapped cell
（0x113bcc3fc），已核001/003/Live063等family继承BBAdPGHDOddCellView。
base BBAdPGView.strict0x113ba0fb4本身RET，不能统一推广。
HDOddCell.strict0x113bc814c先BBAdReporter.innerReportType raw3/event15
（0x113bc829c），随后visibleMark，再intersection双轴50%→viewDidStopWithVisible
（0x113bc8300–0x113bc833c）；后者阈值不是前面wrapper的发送门禁。
Reporter0x113c4a2e8→0x113c4aa38按type bit0/bit1分别Own/MMA，所以raw3是
同时两支，非一种strict enum。Own0x113c4ace4先丢nil/空params；event15另调用
_containerTypeWithRectParam0x113c4a928：任一rect空或intersection空返回-1；
双Infinite返回raw1；其他交集高/宽分别>=0.5*第一rect高/宽才raw0
（0x113c4aa18–0x113c4aa30）。物理HD packing0x113bc81f0–0x113bc81fc已证
第一rect为VIEW，故Own真正门禁也为双轴>=50% VIEW，而非面积50%。
-1丢弃（0x113c4ae64–0x113c4ae68）；non15 events不走此几何门禁。
通过event15门禁后**立即reportType1/event0**（0x113c4afe0），有container和
syncQueue时额外创建operation入队，延一秒再event15
（0x113c4af40–0x113c4af9c→0x113c4b068→0x113c4b04c）。这两个调用不能
误写成有队列只有延迟/无队列才立即；所有通过者都走立即event0。
Manager0x113c4b5dc创建两serial queue，raw0 common、raw1 noCancel
（0x113c4b6b8）；operation init0x113c4bb3c复制执行block，guard初值及
isDisposed=false。execute0x113c4bbc8先置disposed=true，然后仅block非nil且
 guard.value==0才执行（0x113c4bbfc–0x113c4bc38），未重查可见矩形、未以旧
isDisposed挡重复execute。cancel0x113c4bc50递增guard
（0x114340d20→OSAtomicIncrement32），只能压制未来event15，撤不回event0。
addOp0x113c4b7dc同步到自身queue，先移已disposed，再containsObject新operation
（0x113c4b8f4–0x113c4b95c）；不是creativeID/payload去重，每次Own调用新建对象。
标准cancelStrictShowEvent0x113c49ff4先通知再cancel type0（0x113c4a048）；
WithType0x113c4a4dc对-1/raw1直接返回，其余container.cancelAllOp
（0x113c4a540）同步枚举cancel并清数组（0x113c4ba88/0x113c4bac4）。
MMA独立body0x113c4b070也已核对：params非空、raw15调用同rect gate
0x113c4a928，通过后同container/一秒Operation/取消guard；立即
reportType2/event0（0x113c4b40c），延迟event15（0x113c4b4e8），
缺container/queue只立即event0，非15直接原event（0x113c4b448）。
payload却不同：立即event0用copy base并补validatedUrlsWithOriUrls结果的
meta x23（0x113c4b110/0x113c4b154/0x113c4b16c）；延迟closure
0x113c4b4ac捕获原baseParams x19（0x113c4b328–0x113c4b32c），没有继承
这份URLs补充。Own/MMA各建freshOperation；Operation队列没有creative-ID
dedup证明，但下游另有item filter：Own._reportWithItem0x114336164要求
needReport及context.bbad_is_ad_loc非零，needFilter时取filterHash查实例+10
集合，已含丢弃，未含在发送前加入（0x114336224）。event0/15的Own/MMA
item表均设置needReport/needFilter=1；hash组成和清理范围另追，不能由队列层
结论声称端到端无去重或恰好一次。Own.filterHash0x114335ddc为MD5 of
无分隔concat五对象：request_id(nil空)、NSNumberLongLong src_id/creative_id、
NSNumberInt EVENT、filter_salt(nil空)（0x114335f5c/0x114335f6c）。
MMA.filterHash0x114331b30第四项却是raw reportURL，不含EVENT
（0x114331c1c–0x114331ca0）；因此Own event0/15不同，而MMA两URL及其余字段
相同可跨event命中。OwnReport+10/MMAReport+18各shared初始化SafeArray，
contains/add在API排队前，所核失败callback没有undo；清理生命周期需全类反汇编确认dealloc/模块卸载路径。下一步：query_index '*SafeArray*' 30 定位shared初始化与dealloc后 disassemble 对应区间。
context从params取bbad_filter_salt存内部+b0后从最终params移除
（0x114329ae8–0x114329b2c），没有读取实际盐值。MMA URLs precedence为
显式reportUrls→context.bbad_report_urls非nil（空数组也屏蔽fallback）→extra中
event0 show_urls/event15 show_1s_urls；保持数组顺序，仅非空String生成item。
该取消现已配对HD2 MainV2物理生命周期：handleAdShowEventWithMainV2VC
0x10dfa2a74的RAC绑定viewDidDisappear→0x10dfa2ff8→cancel
（0x10dfa3000），scrollViewDidScroll→0x10dfa3004→cancel
（0x10dfa300c），shouldScrollToTop callback0x10dfa3010仅tuple.first为
UIScrollView且scrollsToTop true才cancel（0x10dfa30a8）。重新start来自
viewDidAppear、endDragging且second Bool false、endDecelerating及didScrollToTop
（0x10dfa2e8c/0x10dfa2f34/0x10dfa2f90/0x10dfa2fdc）。startReport
0x10dfa30c8要求VC.view.window存在，collection.bounds转换到Topmost坐标后
与其bounds相交，交集WIDTH>=10（0x10dfa3200–0x10dfa3208）才遍历visibleCells。
广告卡ad_info.is_ad_loc非零转AdSingleCell strict（0x10dfa340c），其余
reportType1/event15/ad_info（0x10dfa3454）。VIEW为cell.frame→collection→
Topmost，LIST为collection.bounds同坐标；这是HD2 MainV2，不推广PhoneSwift。
同HDcell click0x10df154a4先取report_args.state，nil退report_click_position，
再HomeData.reportCardClick（0x10df155a8）后optional internaljumpdelegate
（0x10df15624）；incoming jumpBool在该body未保存。adClickEventReport
0x10df157c8 RET。exposedIn:item:0x10df15dd0用CURRENT self.model交
HomeData.reportRealCardShow（0x10df15e1c），不是strict event15；字段见上述
HD通道。_neuronReportParams0x10df15e3c给sub_goto=ad_info.report_card_type
decimal、sub_param=creative_id decimal；nature_ad恰1才加ad_image_md5=
creative_content.image_md5（nil空，0x10df15fc0–0x10df1606c）。这份extra覆盖
Neuron base；旧001365没有合入extra的步骤。没有读取/输出实际广告ID或hash值。

BBAdModule.onModuleInitialize0x10ea736b4还有独立启动producer：main.async
block0x10ea738e8取BBAdDeviceInfo.userApps（0x10ea73914），makeAdInfo后创建
**BCMUIAdEvent**，name=realtime_user_apps，extendedFields仅user_apps（nil取空），
report0x10ea739bc。同初始化安排main+6秒block0x10ea73a08
（0x10ea73754–0x10ea73774），同样创建BCMUIAdEvent，而非MonitorUIAdEvent；
name=cm_ui_report_monitor，extendedFields仅mobi_app取BFCBuildConfig.mobiApp，
report0x10ea73af8。随后另发BFCNeuronExposureEvent
ad.neuron-report.monitor.0.show.trackInstantly（0x10ea73b0c/0x10ea73b1c）。
这是UI Uploads与Neuron的两个调用，不据监控命名合并endpoint。实际启动任务调度
先后与成功发送未运行验证，userApps实际内容未读取。
初始化也向BCMAdExtra装SimpleModifier（0x10ea73714/0x10ea73730），handler
0x10ea7384c mutableCopy输入params，读取BBAdSingleton.postbackInfo.storyShownIds，
以story_shown_ids覆盖输入同key（nil取空，0x10ea738ac），再copy返回；
modifier.valueCustomWillEncryptParams0x11416e7b0有handler时采用该返回，否则
原params。这是AdExtra加密前扩展producer，不是MMA宏模板或上述UI event扩展。

fee.ad completion0x11417063c对每次结果排Inspector sync block
0x114170b20，创建单条uploads JSON job addFeeReportJobRequestBody:adId:isRetry:
（0x114170bf4），以**旧f_index>0**为retry，成功successData:nil、失败failReason，
仍受BBAdInterceptor.isInspectorEnabled门禁。失败每次另KntrAdAlarm.reportFeeFailed，
五extras is_retry/fail_count/is_bcm_report/desc/code（0x114170898），common取
adInfo.makeKntrAlaramParams或Empty。只有旧f_index=0才BBAdKtTracker raw8
（0x1141708f4/0x114170a60），对应selector表feeReport；五extras为
is_bcm_report/desc/code/ad_cb/event，
成功desc/code取success/0，失败取NSError，事件名取reportParams[event]。
abandon0x114170d0c转KntrAdAlarm.reportFeeAbandon，四extras fail_count/
is_bcm_report/reason/event，reason通过abandonReasonStringFromReason；上述Kotlin告警出口已闭合（KntrAdAlarm.fire→epoch mPlatformNeuron$1→BFCMikoto采样门禁，见本节前文AdAlarm段），非直接HTTP endpoint。

fee.mma completion0x114170fd0先取currentTask.error/URL/info/index，Inspector
block0x114171b04创建addMMAReportJobUrl:adId:isRetry:（0x114171b58），index>0为
retry、结果处理同上；是发送后的job记录，不拦截GET。index=0才先发
BBAdKtTracker raw7/mmaReport（0x1141710f4/0x114171800），五extras
is_bcm_report/desc/code/ad_cb/url，success或error取值。随后所有index的失败均
KntrAdAlarm.reportMmaFailed，七extras url/desc/code/is_retry/ad_cb/fail_count/
is_bcm_report（0x114171130–0x1141712e0）。失败分类若
BCMReportRequestErrorDomain且code=-3001，发BCMUIAdEvent mma_url_error，url取
currentTask.URL（0x114171394–0x1141713d8）；否则发mma_submit_failed，extended
先有code decimal（0x1141714b0–0x114171558）。成功所有index发BCMUIAdEvent
mma_submit_success（0x114171890–0x114171a7c）。成功/一般失败两种UI event还从
adInfo.extra非空dictionary补submit_type、submit_action_from（缺失取空），
保留原extended中的code。不是BCMMonitorUIAdEvent，不混成Monitor endpoint；
它们走普通UI Uploads，不触发MMA再次发送。
此-3001分类不代表nil URL一定产mma_url_error：已闭合GET builder写-3001后
validate(nil)覆盖为-1，具体nil URL路由应按最终error看；其他error producer未
穷尽。MMA abandon0x114171c28另reportMmaAbandon，四extras fail_count/
is_bcm_report/reason/url（0x114171dc8），同样与UI/Kotlin first-result事件分开。

BCM Monitor是另一个发送器：BCMMonitorUIAdEvent.reportType0x11416bcb0和
BCMMonitorUITrackEvent.reportType0x11416bcb8均固定raw0x10000。dispatcher
0x11416f7e8检查bit16（0x11416f9b8），将已build/copy的同params/context/info
送monitor.reportParams:context:info:（0x11416fa20/0x11416fa3c）。monitor getter
0x114171e64懒建BCMUploadsReport name="monitor"（0x114171e90），URL固定
https://cm.bilibili.com/cm/api/conversion/mobile/v2（0x114171eac/0x114171eb0）。
故它走已闭合Uploads JSON uploads POST、压缩、HTTP2xx+code0判据，独立串行
queue com.bilibili.bcm.report.uploads.monitor、cache report.uploads.monitor
（name模板0x114174508/0x114174560）。getter未安装UI/fee.ad/MMA completion
或abandon observer，不能套用那些Inspector/Kotlin/UI反馈事件。
公共BCMReport.retryFailedEvents block0x11416fd94只调用ui/feeAd/feeMMA
（0x11416fda8–0x11416fdf8），未调monitor。因此已闭合SDK启动公共retry入口
不能宣称会排Monitor旧缓存。Monitor仍继承Uploads单次成功后立即
_retryMoreThanInterval:0（0x114174adc/0x114174ae0）、失败saveRecord
（0x114174d28）及通用retry限制/尾批未flush边界。Monitor重试入口同样闭合：
retryFailures在本镜像只有selector stub 0x1174fff60一个ObjC出口，find_callers
命中且仅命中3个BL（0x11416fdb8/0x11416fdd8/0x11416fdf8），全部位于
BCMReport.retryFailedEvents block0x11416fd94内，反汇编确认三个receiver依次为
msgSend$ui/feeAd/feeMMA（0x11416fda8/0x11416fdc8/0x11416fde8），无monitor；
结合上文Monitor零构造点，monitor cache report.uploads.monitor在本镜像内
没有任何写入者，其重传链只在"存在首次Monitor发送"这一不可达前提下才可能
启动。不要因事件名cm_ui_report_monitor或mma_submit_success含监控语义而把
普通BCMUIAdEvent路由到此地址。

UGC广告的真实加载触发已静态闭合：BBPlayerServiceManager三个入口经stub
0x117528440调用serviceOnStart——bindService:内BL 0x114822b4c（方法0x114822a3c）、
createAndStartService:内BL 0x114822ccc（方法0x114822c9c）、startService:内BL
0x114822d44（方法0x114822ce0）。serviceOnStart 0x1133ef6ec装完manager代理与proxy
绑定后，在0x1133ef848对self.context.chronos以keyPath"isRunning"（CFString
0x117a70000+0x8f5）options:7挂KVO，block 0x1133ef914要求weak self存在且change
boolValue非零才调_fetchDanmaku（0x1133ef950），即chronos播放器isRunning变为
true是x/v2/dm/ad请求的直接触发；block不比对isRunning旧值。serviceOnStart另有
一ivar byte门禁（0x1133ef874–0x1133ef890，adrp 0x11f887000+0x930）：恰为1才
执行_addObserver与_registerDanmakuEvent。展示/事件侧触发点同样闭合：_addObserver
0x1133efec4注册五个KVO——context.playback.currentTime（keyPath CFString
0x117892000+0xf30，block 0x1133f0454→_playerCurrentTimeChanged: 0x1133f0498）、
playback.playbackState（0x117a76000+0x4e0，block 0x1133f04c0→
_playerPlaybackStateChanged: 0x1133f0508）、controlWidgetService.controlActive
（0x117b1a000+0x542，block 0x1133f0530→_controlBarControlActiveChanged:
0x1133f0578）、controllerService.lifecyclePhase（0x117a86000+0x389，block
0x1133f05a0→_containerLifecyclePhaseChanged: 0x1133f05e8）、status.fullScreen
（0x1179fd000+0x318，block 0x1133f0610→_dismissPanelWidget 0x1133f0628）；
另有_adPanelLifeStateChanged:isVerticalScreen:的dispatch点在
_bindProxyEvent_block_2 0x1133efd44（BL 0x1133efe48），非_addObserver链。
弹幕广告事件入口_registerDanmakuEvent 0x1133f063c由ivar byte一次性守卫
（0x1133f0650–0x1133f06d4），把weak self block装到
chronosBizControlService.adDanmakuEventHandlerBlock（0x1133f06c4）；该block
0x1133f0718要求event非nil且danmaku_id非空，否则BFCChronosMsgException
exceptionWithCode:-6000（'event nil'/'danmaku_id nil'，CFString
0x11d2f8000+0xd30/0xd50），合格后进_adDanmakuEventWithParams:result:
0x1133f1048：取video_id/danmaku_id（nil或length==0丢弃）、event、
extra.integerValue（0x1133f1154）后调handleChronosEventWithDanmakuId:event:extra:
（0x1133f117c），异常分支统一记
'[CRON MESSAGE] :@"Chronos msg data code : %ld"'（main.player.core）。
据此，前文UGC段遗留的"后续UI门禁"问题已闭合到以上五个KVO与chronos事件
入口；各handler内部校验（Danmaku/Floating额外校验）仍按本节前文各自闭合段判断。
采样配置（cm.ff.tt_track_enable等）的键字符串为Kotlin UTF-16字面量（如
0x11c845e32起），全镜像无直接代码adrp/add引用（find_data_refs_root/
find_pointer_refs对0x11c845e32均返回空），仅在AdTrack initializer
0x107aba268–0x107aba2d0经sub_10520EF90按0x11c8450fb0/0xfb8/0xfc0/0xfc8字面量
槽构造并写入lazy global；本镜像内未找到对键值的运行期改写者，"一次性快照、
无更新路径"边界维持前文结论。

### dm/ad 响应模型字段与响应侧消费

响应模型字段（证据：DerivedData/Validation/team-c4/findings.md 块3）：
`+[BBAdPlayerAdModel modelCustomPropertyMapper]`0x1133f4284把`mixList`映射到JSON
`ads`、`foreverFloatList`映射到`permanent_floating`、`activities`原名
（0x1133f42a4–0x1133f42c0）；`modelContainerPropertyGenericClass`0x1133f4310对
mixList/foreverFloatList/activities三数组统一指定元素类BBAdPlayerAdDetailModel
（0x1133f4340等）。顶层ivar仅_icon/_mixList/_foreverFloatList/_activities
（0x11f887a10–0x11f887a1c），无code/message字段——业务码判定在BFCApiRequest公共
层，dm/ad响应侧无独立错误分支。BBAdPlayerAdMixListModel仅_mixList+_index两ivar
（0x11f88786c/0x870）；BBAdPlayerAdIconModel字段ad_cb/creative_id/extra/src_id/
ad_info/source_id（getter 0x1133f3d68–0x1133f3e64）；BBAdPlayerAdInfoModel字段
extra/ad_cb/creative_id（0x1133f3cc0–0x1133f3d18）；三者均无mapper（键名即属性
名）。BBAdPlayerAdDetailModel为纯Swift存储属性类（无ObjC方法/ivar表，仅_$metaData
0x11ed0b9a8/_$properties 0x11ed0bdb0），字段清单本轮未解码，见findings残余。

响应侧消费分支：面板分派族`+[BBAdPlayerAdPanelHelper
viewTypeWithClickType:mixListModel:]`0x1133e7b54按click类型分viewType，子分支
_viewTypeClickIconWithMixListModel:0x1133e7c84、
_viewTypeClickDanmakuWithMixListModel:0x1133e7df0、
_viewTypeClickListCellWithMixListModel:0x1133e7f8c、
_whichDetailTypeWithViewTypeModel:data:0x1133e7d4c、_detailIsH5WithData:
0x1133e8054、_realUrlWithData:0x1133e8114、_playerAdCanOpenListWithDetail:
0x1133e7ed8。dm/ad响应无独立缓存写入（BBAdPlayerAdBaseManager仅mixList getter
0x1133dfa48；YYCache缓存属UIReport/BCM链，见上文）。广告明细卡片内直接挂商城写
操作：BBAdPlayerAdDetailBaseCell.requestAddToShoppingCart0x1133c0e44（成功回调
0x1133c1598）。

### 广告去重容器的锁与生命周期边界

Own.shared0x114336084缓存global0x120da0b68，once-token0x120da0b70；
MMA.shared0x114332154缓存global0x120da0b48，once-token0x120da0b50，
各通过0x117051e9c/0x117051e74进入dispatch_once。已检查Own完整方法范围
0x114335ff8–0x114336fdc和MMA 0x1143320c8–0x11433367c，未见初始化后的
hash数组替换、remove/clear或成功/失败/retry清除，亦未见类内账号observer注册。
这只是所检查类范围，外部动态调用是否清除仍未知，不能称账号隔离或永久去重。
SafeArray.init0x114340ee4创建mutable array和count1 semaphore。
containsObject0x1143415d8独立wait FOREVER→contains→signal
（0x11434160c/0x114341620/0x114341634）；addObject0x114342684再次独立
wait→add→signal（0x1143426b8/0x1143426cc/0x1143426e8）。这三方法内未见
TTL/容量淘汰。两个锁区不保证调用方check→add组合原子；实际线程交错未运行验证，
不能把静态同hash过滤写成并发exactly-once。

### Story选集面板与卡片翻译的实际入口

Season公开tableView:didSelectRowAtIndexPath:0x1040ef044→0x1040eef20，
按row从storyItemArray取item，要求delegate非nil才调用0x1040ea4d8。
面板工厂0x1040e85d0创建STSeriesSeasonView并弱设adapter为delegate
（0x1040e8634）；外层0x1040e96a8要求weak store/current series.item。
config缺失或showDescPopr!=1进入0x1040e7f20的session=season面板；flag1则
构造DescVCConfig locatedVideo=true/infoStyle2/current storyItem，进入
0x1040aa0b8。此分支选择UI，不是额外网络mode。
Season选择consumer0x1040ea4d8发送
main.ugc-video-detail-vertical.content-select-panel.0.click，select_content_id
取所选playerArgs.avid decimal、position=row+1，再merge0x1040e9dbc。
随后构造avid/cid来自所选playerArgs、epid0/failded nil的anchor，再调用
selectedAction（0x1040ea8cc）；无失败UI回调不能等同HTTP失败无处理。

Story卡片翻译公开STMoreBloc.translate:0x104185330→STCardTranslateBloc
0x10412f058，分别检查current.item与focusItem；后者缺失不发请求。
GET https://app.bilibili.com/x/v2/feed/index/story/trans，新建五字段：aid/cid
取focus.playerArgs Int64 decimal（缺失0）；goto/trackid取focus字符串（nil空）；
translation_status取focus.translation.status signed decimal（缺失0）。
/data/translated_item映射optional非array StoryItem，requestAsync0x10412f670。
此函数未使用STLoadBloc请求中byte，未见业务retry或偏好写入。
成功0x10412ffb8→0x10412f6b4要求weak bloc和原focus item仍活着，模型有效才
排main closure0x104130004。主线程0x10412fb78重新读取live focusItem，写入
响应title/desc/translation；双方chapters非nil且count相等才替换
permanent_entrance。此body没有avid/cid/原item equality或generation检查；
仅属静态写入边界，不推断发生过运行时旧响应覆盖。error0x10412fae4仅日志。
未来Series params的need_translate来自当前item.isTranslated0x1042efd68，
仅translation.status==1返回true（0x10411ab78），不是全局翻译设置Bool。

More物理菜单raw type37在0x104184a40跳表（0x104184de0/base
0x104184aa4）落0x104184b74，调用translateWithItem:customModel:
0x104185324→0x104184e84，要求HorizonGridModel并安装autoDismiss=true点击
callback0x10418f4d0。callback经0x104185594的weak bloc/live current.item门禁，
objc translate:0x104185674→上述0x104185330；菜单捕获item与实际focus请求item
分开，未见generation比较。外层虚方法调用者经Swift witness间接派发，find_callers不能直接归属；下一步：find_callers 0x104185324（translateWithItem:customModel:）穷举ObjC侧调用方，再对witness槽反查。
Portrait cell 0x113294fdc先dispose旧translationDisposable，再RAC观察translation，
skip1/takeUntil self.dealloc→0x113295214读取live cell.storyItem/watchMode/position，
调用installWithItem:watchMode:position:（0x11329526c），没有网络或全局偏好setter。
shouldAddAiTranslate0x104191a34仅要求current.item.type==1，nil false，不能按名称
把它作为上述card trans端点的账号/翻译状态门禁或独立AI请求证明。

### HDMainV2普通曝光项、检查触发与页面复用

AdSingleCell.exposedItems0x10df15c30读取当前model的report_timestamp_str/
report_track_id/report_flush_idx生成ExposureIdentifier，取self.contentView创建一个
BBListExposureItem（0x10df15ce0/0x10df15d50）。它没有设置单项ratio/repeated；
convenience init0x103eb2884→默认init0x103eb2a88留下exposureRatio none和repeated
optional raw2。因此普通曝光采用HDMainV2 delegate策略，不套广告Reporter双轴50%门禁。
MainV2.exposureManager0x10df401a0仅cached ivar nil时创建，rootView=collectionView、
先enabled=false/delegate=self（0x10df401f0–0x10df40220）；setter0x10df407c4仅
strong store，析构0x10df407d8释放。BBListExposureManager.reset0x103eb3060只
removeAllObjects。已扫描直接call和reset/setExposureManager三层selector，未找到该VC
具体clear/replace调用；动态ObjC、Swift间接和外部运行时仍未知，不声称永不重置。

checkFeedExposure0x10df40238先读disableRealExposureInTianma，true直接返回。
isChangedSwitchSize=true则延迟200ms main，以strong self capture到0x10df40300，
读当时manager→checkExposure（0x10df40324）后清sizeflag；false立即check
（0x10df402dc）后清flag。所检查body未清池或取消延迟任务。
viewDidLoad安装collectionView.contentOffset RAC观察（0x10df38ca8），weak self
callback0x10df38f88先tryInlinePlay，再checkFeedExposure（0x10df38fa8），
不是仅scroll end触发。bindVM观察VM.objects（0x10df3b2c8），callback
0x10df3bbf8重新读当前VC.viewModel；其isUpdateDislike=true跳过reload/check。
false按当前VM.willLoadFromBottom选择reloadBottomItems或allSections reload，layout后
要求VC.isShow && shared.hasFirstCheckAutoPlay（0x10df3be98/0x10df3beb8），
才main async weak self→0x10df3bfec先checkFeedInline再checkFeedExposure
（0x10df3c00c）。count仅影响emptyView/首batch，未作为最终check的非空门禁。
此callback未比对发射VM和当前VM或账号generation；未运行复现旧VM发射，保留静态边界。

addPegasusMainViewReallyShowObserver0x10df3fd90 merge self.isShow、self.isCoverBySplash、
SplashAppear/SplashDisappear通知四源，弱self callback0x10df400f4→0x10df4010c。
实际enable计算current isShow && SplashManager.splashStyle==0；另一
isReallyShowing0x10df3fd60计算isShow && !isCoverBySplash，两个谓词不混写。
backgroundBecomeActive0x10df3c83c先resign=false，splashStyle0时cover=false，始终
bannerExposure；isReallyShowing为true才main queue零延迟strong self→0x10df3c940
调用checkFeedExposure，复用当前cached manager，所检查body无pool reset。

### 日志附件Laser：实际按钮、归档、上传与结果反馈

LaserUploadViewController.uploadLogs0x100076b9c→0x1000766f4创建feedbackTask，
controller.taskID同时作taskType/tag，再uploadLogsWithTask:completionBlock:
（0x114a8a78c）。此直接入口不套uploadAllLogsWithTag:0x114a8a464的时间节流；
后者提交时即更新lastUploadTime，未等网络回执。提交保存UUID completion，
didReceivedTask0x114a8af24按actionName非nil选BaseOperation、nil选TaskOperation，
设置BFCLaser delegate并入队；TaskOperation.main0x114a90c30→uploadAfterPackup。
LogModule multibinding0x12028f0c0注册BFCLaserAttachmentProvider，两个witness
0x12048d060/+10→0x1049514a0 BLogAttachment、0x12048d048/+10→0x1049514d8
BFCLogAttachment。Laser setup0x1000777f4解析同协议数组key0x120279490，
逐项对实际BFCLaser receiver registerAttachmentProvider:（0x100077b48），
闭合实例注册。BLogAttachment.localPaths0x104953c98→0x104955284先flush
BLogger，再枚举Documents/BLog按yyyy-MM-dd筛日期；没有读取实际日志内容。
operation附件收集0x114a8bd04调用注册provider localPaths/data并保留name关联。

TaskOperation.uploadAfterPackup0x114a91348取得date/dateList对应附件，空列表error1；
非空先createZip，失败退createTar（0x114a917dc/0x114a918c0），计算归档size/MD5。
实际uploadServiceForOperation:0x114a8c790缺getter默认raw2；实验getter
0x100074a94查询laser.upload_to_upos preset1，true2/false0。因此默认UPOS，
而非备用Uploader固定URL。raw0走BFCLaserUploader0x114a967d8→0x114a96834，
options.localPath、requestMethod2/taskType1/ignoreCache1/timeout60/cacheLife0，
/data模型、completion/error后requestSync0x114a96a50，/data.url非空才接受。
raw2先复用task identifier匹配的UPOS task，未找到才新建BFCUploadRequest，设置
profile/options.mid/归档file location，再装completion0x114a92290并resume。
回调error nil才从storageInfo.bucket/key构造download URL/UPOS URI，任一结果均
signal semaphore（0x114a923e8）。等待后删除归档0x114a92124，不等同删除原日志文件。

UPOS taskWithRequest0x114a996a8→TaskManager0x114a9c510创建UploadTask并设
performer=self，resume0x114aa56d0→0x114a9cd84创建BFCOperation包装
OperationManager并入队；enableRealTimeTranscoding另分支。普通start0x114a9a9dc按
phase/enableSimple/size阈值选simple，否则Pre/Initial/Part/Merge managers。
fresh request options ctor0x114aa7410未显式设置simple/transcode，恢复task配置
仍需区别。BaseRequestManager.sendRequest0x114aa89ac调用实际apiRequest构造
BFCApiRequest，设callback queue/timeout/handlers后requestAsync0x114aa8c38，
不是按SDK名推断Ktor。pre-upload0x114aac48c选非空request.preUploadUrl或内置
endpoint（后者已闭合为CFString 0x11d2c42d0=`https://member.bilibili.com/preupload`，
0x114aac69c–0x114aac6ac在preUploadUrl length==0时装载；0x114aac6bc
setRequestMethod:#0）、options query+archive basename/profile；merge endpoint由
storageInfo及uploadId/taskConfiguration构造。**part/merge 的 options 构造已定位（team-c32；backlog 给的
`*MergeRequestManager*`/`*PartRequestManager*` GLOB 均为 0 命中，正确类名如下）**：
merge 类 `BFCUpOSMergeUploadRequestManager`（0x12020c708，方法表 0x11f31fd88），其
`-[… apiRequest]` **0x114aa9f34** 逐指令为——`activeEndpoint`(0x114aa9f74) 定 host；
URL 由 `context.task.storageInfo.bucket`(0x114aa9fb8) + `.key`(0x114aa9ffc) 经
`stringWithFormat:@"https:%@/%@"`(0x114aaa018) 拼出；参数经
`dictionaryWithObjects:forKeys:count:`(0x114aaa160)+`mutableCopy`(0x114aaa170) 构造，**键集合 =
`output` / `json` / `profile` / `uploadId`（值←`storageInfo.uploadId` 0x114aaa0cc）/ `biz_id`
（值←`context.task.taskConfiguration.bizId` 0x114aaa130）/ 一个空键**，请求头含 `X-Upos-Auth`。
part 类 `BFCUpOSPartUploadRequestManager` 的构造分布在 `createPartInfos` 0x114aab62c、
`createForegroundOperations` 0x114aab9b8、`createBackgroundOperations` 0x114aabca8、
`cancelAllOperations` 0x114aac0ac，发送统一经 `-[BFCUpOSBaseRequestManager sendRequest]` 0x114aa89ac；
分片策略在普通 start 0x114a9a9dc：读 `context.task.phase/request/options/enableSimple/size` 与
`context.config.maxSimpleUploadSize`(0x114a9ab0c)，再调 `createSimpleOperations:`(0x114a9ab84) /
`createOperations:`(0x114a9aba0)，**不是按类名分派**。残余：`createPartInfos` 内每片的 URL/参数来源与
`profile`/空键取值需逐行读（下一步 `disassemble.py 0x114aab62c 0x114aab9b8`）。
error callback0x114aa8d48递增currentTimesOfRetry，交替continuousFailure时按
optionalEndpoints count轮换endpoint；current<timesOfRetry才main dispatch_after
interval后重启。Base默认timeout120/timesOfRetry10/interval3
（0x114aa9030/0x114aa9038/0x114aa9040），子类可覆盖，不当全局固定策略。
正常Merge.success0x114aaa55c设置resultInfo/phase→notifyTask:error:nil，失败另传error；
CallbackManager0x114a9bc38调用completion(error,storageInfo)0x114a9bca0→上述Laser
0x114a92290。这是实际上传回执链，未证明服务端持久性或所有恢复任务均可续传。**回调链调用方已收齐
（team-c32）**：0x114a9bc38 不是函数入口，而是
`-[BFCUpOSTaskCallbackManager notifyTask:didCompletedWithError:]_block`（`sym_at` 证据），
故对它跑 `find_callers` 结构性为 0；宿主方法 0x114a9ba44 的 msgSend stub
`_objc_msgSend$notifyTask:didCompletedWithError:` **0x1174403e0 有 6 个真实调用点**，全在 UPOS 管理器内：
`-[BFCUpOSBackgroundOperationManager part:didCompleteWithError:]` 0x114a97140、
`-[BFCUpOSOperationManager start]` 0x114a9ada0、
`-[BFCUpOSBaseRequestManager failureWithError:]` 0x114aa9458、
`-[BFCUpOSMergeUploadRequestManager successWithResponse:]` 0x114aaa688、
`-[BFCUpOSPartUploadRequestManager failureWithError:]` 0x114aab3e0、
`-[BFCUpOSSimpleUploadRequestManager successWithResponse:]` 0x114aadb2c；block 内再走
`completion(error,storageInfo)` 0x114a9bca0 → Laser 0x114a92290。
**服务端持久性/续传仍不可判**，且**本地 9.13 抓包也无法判定**：team-c12 的 32 组 `.flows` 里
没有 `member.bilibili.com/preupload`、UPOS part/merge 或 `x/feedback/uploadFile` 任何一条
（`endpoint-inventory.json` 无该族）；取证=真机触发一次真实上传抓 UPOS 全链，或服务端侧确认。

上传后TaskOperation.main按URL是否nil写status3/-2等reportContext，report
retryTimes3/retryInterval3（0x114a91020），具体feedback0x114a92708→LaserApi
0x114a89448，requestSync0x114a89820。报告error时循环，最多3次总attempt、
间隔3秒，区别UPOS stage retry。如果上传error nil但report error非nil，合成error6
（0x114a91094）；最终delegate completion0x114a911ec携URL/error。BFCLaser
0x114a8d160删缓存task、main派发UUID completion并移除callback；本地清理不是远端ACK。
上传成功和报告成功是两层判定，不能用Crash.reportIssueComplete(true)代替。
Laser setup业务触发余项、UPOS缓存恢复/各stage覆盖、BLog最终daily-file写入继续追踪；
没有网络/文件内容/设备采集验证，不推广所有诊断均走Laser。

### BLog缓冲区、压缩、最终文件写入与flush限度

**BLog 引擎配置注入点（本轮闭合，含二级 thunk 链）**：`-[BFCLogEngine initWithConfiguration:]`
= 0x11539bfb8，`find_callers.py 0x11539bfb8` 为 0（无直接 BL/B）；其创建代码在
`sub_11539BDC4`（0x11539bdc4–0x11539be78，紧邻 `+[BFCLogConfiguration defaultConfiguration]`
0x11539be78）内，`[BFCLogEngine alloc]` 站点 0x11539be3c 是该函数的**内部地址而非函数入口**
（对它搜调用方无意义）。对 0x11539bdc4 的调用方搜索结果 0x10f82fc4c **不是真实调用点，而是
一条 4 字节 thunk**（`b 0x11539bdc4`，位于 thunk 表 0x10f82fc0x–0x10f82fc5c）；该 thunk 又被
另一 thunk 表的 0x107c24f4c（`b 0x10f82fc4c`，表 0x107c24f40–…）指向。**逐级回溯后的唯一真实
调用点**是 `bl 0x107c24f4c` @0x104955adc，位于 Swift 函数 `sub_1049559B8`（0x1049559b8–0x104955b0c，
紧邻 `-[DDLogger logWithLevel:message:tag:]` 0x104955b0c），调用前有
`String._bridgeToObjectiveC()` 与 `swift_bridgeObjectRelease`（构串）⇒ **这就是 BLog 引擎的
配置注入点**。因此“0x10f82fc4c 是共享 stub 假阳”的旧记法可精确化为“它是二级 thunk 链的一环，
真实调用点 0x104955adc ∈ `sub_1049559B8`”。残余：`sub_1049559B8` 自身由谁调用（其入口
0x1049559b8 的调用方）与 `BFCLogConfiguration` 的键来源仍需闭合；下一步 =
`find_callers.py 0x1049559b8` 与 `query_index.py '*BFCLogConfiguration*' 20`。

BLog setup0x11647f9f4→0x1164864ec对nil global一次alloc/ctor并存
0x1210df460；core0x1164802d0分别读console/file阈值。允许写文件才加newline、
mutex保护buffer.append0x116480a78（0x1164808e0）。buffer ctor0x116483b2c
open/ftruncate后mmap prot3/flags1（0x116483c98），失败退heap；append memcpy
0x116480aec更新used/header，满块切换后owner virtual+30（0x116480b84）。
owner vtable0x11d05ead0/+30=0x116484838转job/SharedPools压缩；另一输出owner
0x11d05ea40/+30=0x1164843a0→0x11648441c入core+80队列。
压缩worker vtable0x11d05eb40/+30=0x116485434→0x116485594，TLS缓存状态，
初始化传level1/method8/windowBits-15/memLevel8/strategy0，符合raw DEFLATE参数；
helper内部未完整重推，不作加密归因。stored-block fallback显式LEN/NLEN+memcpy。
disk worker vtable0x11d05e8c0/+30=0x116481bfc→0x116481c84，从队列取得
BLockJob（0x116482518），更新day/path，再file helper0x1164828c4→lazy open
0x1164834e8→实际_open0x116483540（EINTR重试）。实际_write0x11648298c
处理partial write和EINTR，失败另报diagnostic。job顺序/轮转筛选已定位，不能把它等同日期配额，
**job序/order筛选已闭；旧daily/quota归属撤回**（team-c21，证据 DerivedData/Validation/team-c21/findings.md
C1/C2）。类名为 C++ `DiskWriter`（mangled typeinfo 串 0x11936e4c7，相等判定 0x116481c04/0x116481c58），
队列元素 0x60 字节（count=(end-begin)/0x60，0x116482584–0x11648258c）：
（1）**旧 job 丢弃**：job+0为序/order键，std::string起+8（SSO标志job+0x1f）；字符串为空走 0x116481dac，
`cmp [x19+0x210], job序键` 相等才以 w1=1 调 sub_116482610（0x116481dc4）；非空则 0x116482100 取
`[x19+0x208]`、0x116482104 `cmp x9,x10; b.lt 0x116482178` ⇒ **job+0序键早于writer+0x208时不写文件**，直接做 job completion（vtable+0x30，0x116482188）；否则
sub_1164828C4 写文件（0x116482114），成功后锁 mutex(+0x188) 清 +0x1e8/+0x1f0 并把 +0x208 更新为
当前代（0x116482128–0x116482174）。
（2）**排序门禁**：sub_116482518 在 mutex(+0x58)/condvar(+0x98) 上等待，直到底层向量非空且
**队首元素首 8 字节 == `[x19+0x200]`**（0x116482554–0x11648256c），取走后 `[x19+0x200]+=1`
（0x1164825b0–0x1164825b8）；sub_116482E04 是 96 字节元素的堆排序（`mov w26,#0x60`、`lsl x8,#1`、
比较 `[x24+0x60]` vs `[x24]`，0x116482f18）⇒ 队列按job+0序/order键有序。
（3）**原子替换与失败日志**：sub_116482610 走 `_rename`（0x116482668/0x116482678），失败组
`rename file failed: `（0x1181ca80c）+ `, errno = `（0x1181ca821）+ `to_string(errno)`，tag
`blog.writer`（0x1181ca800）、级别 w0=3（0x116482774）；写失败串 `write file failed, errno = `
（0x1181ca82c）在 0x1164829d4，`blog.writer` 全镜像 4 处引用（0x116482768/0x116482a54/0x116483674/
0x116483794）。
（4）**另一DDLogFileManager family的quota落点（不作为C++ BLogDiskWriter配额证明）**：`+[BFCLogConfiguration defaultConfiguration]` 0x11539be78 = 20 个文件 /
20（MiB）总配额 / 2（MiB）单文件 + zip1/mmap1/useOSLog0/ttylevel0/aslevel1/fileLevel7；
`-[BFCLogEngine initWithConfiguration:]` 0x11539bfb8 把 `maximumFileSizeInMetaBytes << 20` 交
`setMaximumFileSize:`（0x11539c170）、`maximumNumberOfLogFiles` 交 `[logFileManager
setMaximumNumberOfLogFiles:]`（0x11539c198）、`limitOfSizeInMetaBytes << 20` 交
`[logFileManager setLogFilesDiskQuota:]`（0x11539c1c8），并 `setDoNotReuseLogFiles:1`（0x11539c1dc）、
`addLogger:withLevel:[config fileLevel]`（0x11539c1fc）⇒ **单位是 MiB，daily 滚动与数量/容量裁剪由
DDLogFileManager 执行**；BFCLogEngine 另暴露 fileTotalCount 0x11539c5b8、dirSize 0x11539c6c4、
oldestLogFileTimestamp 0x11539c8b4、archive: 0x11539c314 作为配额观测/归档原语。
误报排除：`, total quota_size: `（0x1181ecf5b，0x116713b6c/0x116718974）属 gRPC
`external/grpc+/src/core/lib/resource_quota/memory_quota.cc`；`config.dailyTotalLimit `
（0x1179f4b30，0x103b2b824）属 UGCShareGuide 的 Swift 日志。不读取实际路径或日志内容。
flush0x1164809b0装semaphore、调用相同owner、wait FOREVER0x116480a5c；
关键边界是disk worker写成功、失败或旧job跳过均可到job completion0x116482188，
原block callback vtable0x11d05ec10/+30=0x116485c44重置header并signal
（0x116485c70）。所以flush返回只证明本地排队job完成，不能证明文件写成功、
落盘持久性或服务器收取；Laser的flush→附件收集仍受这一区别限制。

### HD2外层账号事件、重建与新曝光池边界

BBHD2PhonePegasusVC.loginStateObserve0x10df1a670注册BFCAccount observer
mask6（0x10df1a6e8），沿已闭合公共action映射即Logout2+Update4，不包含Login1/
Change8；桥0x11603a2b8保留mask，callback wrapper0x11603a354不改action。
Update且current hasLogin时homeVM.clearTime→tryLoadData
（0x10df1a77c/0x10df1a79c）；Logout且!hasLogin时homeVM.clear
（0x10df1a7c8），之后都比较VC.isLogin与当时Account.hasLogin。
Bool不同才setIsLogin、新MainVM（0x10df1a8a0）、rebuildVC0x10df1a8e4，
再新MainVM.tryLoadData；Bool相同不重建Main，但不能说homeVM不刷新。
这里homeVM是下述notice VM，与推荐MainVM及其feed请求分开。
rebuild0x10df1a028强制buildVCUseCurrent=false→0x10df1a030，旧内页
willRebuildSignal.sendCompleted0x10df1a090，再new MainV2 alloc/initWithMainVM
0x10df1a0d0，移除旧view/parent并设置新mainVC。新MainV2.init0x10df385f0
创建RACSubject作willRebuildSignal，再setViewModel输入VM。这样重建形成新VC和
新lazy曝光池，区别旧manager.reset。旧VC析构时机与在途HTTP取消属ARC/运行期行为，静态不可判定（重建点0x10df1a8e4已闭合）；验证需真机Instruments或对MainV2 dealloc挂符号断点。
所扫描willRebuildSignal getter direct/selector调用未找到takeUntil/subscribe消费者，
内联ivar/动态使用仍未知。refreshBlock0x10df1a38c仅current hasLogin才读取weak外层
homeVM.tryLoadData0x10df1a3c8，所检查closure不reset曝光池。

### Laser启动任务、服务器任务与预先去重

LaserModule Runnable witness0x11b0a6c60的构造入口0x10007461c/0x1000745b4→
moduleInitialize、0x10007463c/0x1000745cc→main，priority360，name
LaserModuleModuleInitialize；exec+28→0x1000746d4→setup0x1000777f4。
时序上BFCLaser.setup0x100077a84先于附件provider注册0x100077b48。
setup0x114a89c34从cache.tasks0x114a8fc38→Preferences.tasks解dict恢复任务并
queue.addOperation0x114a89ed8，因此未证明恢复任务总能看到后注册的所有附件；
未测线程交错，不把静态先入队次序当成运行竞态已发生。下一步 = disassemble.py 0x114a89c34 0x114a89f00 核对 addOperation（0x114a89ed8）与附件注册先后。
registerMossStreaming0x114a8ab3c注册V1 Laser.watchLogUploadEvent及V2.watchEvent；
生成方法0x114afa028/0x114afb59c经MossCenterWrapper→sharedCenter→registerSvr，
response class分别V1LaserLogUploadResp/V2LaserEventResp。V1 handler
0x114a8ac24把taskid/date映dict→fawkesTask0x114a8ad24→didReceivedTask；
V2 0x114a8ad84把taskid/action/params映dict→0x114a8aec0→didReceivedTask。
具体stream底层重连/外部所有权仍属于Moss公共层余项，不把此注册当已接到真实任务。
didReceivedTask0x114a8af24仅laserType1/2先containsTaskId（0x114a8afcc），
hit记录后退出；miss先addTaskId0x114a8b074，再cache.addTask/入队。
addTaskId0x114a90858将新ID插index0，count>=11移除last，setTopTaskIds
0x114a90954，普通单插保留10。标记发生在执行/回执前；已查body无时间或账号拼接，
外部清除未知，不能称成功后去重或完整账号隔离。
BFCLaserPreferences动态属性tasks NSArray/uploadInfos NSDictionary/topTaskIds NSArray，
继承BFCPreferences；其方法表无configName override，继承getter
0x1167d33b8通过NSStringFromClass生成namespace。BFCPreferences.userDefaults0x1167d4ccc调用configName后initWithSuiteName
（0x1167d4cfc/0x1167d4d14）并缓存到instance+8，故此类固定suite
BFCLaserPreferences，所查body未拼账号。suite级外部clear已排除（removePersistentDomainForName: 0x1174d7ea0 全镜像仅UASDKStorage调用，见team-g3证据）；逐key removeObjectForKey写入方为精确残余：find_callers 对 BFCPreferences removeObjectForKey: stub 穷举。不读取实际缓存或ID。


### HD2 notice 的门禁、参数和回执时间归属

外层init0x10df193d0创建MainVM（0x10df19504/0x10df19514）；viewDidLoad
0x10df19cf4另创建HomeVM并保存（0x10df19d98/0x10df19da8），先buildVCUseCurrent=true，
再以当时BFCAccount.hasLogin初始化isLogin（0x10df19dd4/0x10df19de0），然后装账号observer。
此Bool不能按默认false处理。HomeVM.wiredInfo经RAC、main scheduler、skip1
（0x10df19e84/0x10df19ed8/0x10df19eec）到weak外层updateUIByWired
0x10df1a014；这是notice UI来源，不是MainVM.objects。viewDidLoad尾端当前登录才
homeVM.tryLoadData（0x10df19f70/0x10df19f8c）。outer dealloc0x10df1958c
移除Account observer和NotificationCenter observer（0x10df195ac/0x10df195cc），
所查body没有内页HTTP cancel；不能把观察者移除当请求取消。

HomeVM.loadData0x10df57e90先读当前NSDate和共享global0x1210741d0；已有date且
elapsed<1800秒则只结束loading、清error，恰好1800可继续。BFCAppPreferences.inReview
为true也同样退出。通过才构造GET https://api.bilibili.com/x/member/v2/notice
（0x10df57f78/0x10df58024），/data映射NSDictionary、isArray=false
（0x10df57fa4，静态JSON pointer0x11d0ef8d0），requestAsync0x10df580dc。
params0x10df58508只组两个String：uuid来自BFCIDFA.idfaString移除全部连字符，
nil/空→空；mid来自BFCAccount.userSID（0x10df585ac），nil→空。
没有读numeric MID，不能按字段名替换来源。这里没有读取实际IDFA/SID或响应。

completion0x10df58188把捕获的请求开始Date写共享global（0x10df58214），再按/data
status/type处理：status0→wiredLoginType0/wiredInfo=nil；security→type1/security对象；
realname→type2/realname对象；其他→0/nil，最后loading=false/error=nil。
共享Date写入不依赖weak VM仍存在，所查body没有当前账号/当前HomeVM比较。
error0x10df58334忽略incoming error，weak VM有效时只loading=false/error=nil，不写Date。
clearTime0x10df584f8只共享Date=nil；clear0x10df584bc还type0/info=nil。
这两个body没有清推荐数据/曝光池或cancel。共享Date跨HomeVM实例；外部重置、响应到达顺序与真实账号切换的交错属运行期行为，静态不可判定（共享Date写入0x10df58214已闭合），验证需真机换号抓包。

<a id="hd2-设置页路由与-vmtype-映射task-13-补"></a>

### HD2 设置页路由与 vmType 映射

HD2 设置主入口 `BBHD2PhoneSettingMainVC.setParams:`（0x10c91bec4）先把入参当
LynxRoute 复制（-[LynxRoute copyWithZone:]_0_0，0x10c91bee4）再走 super，随后从该
route 字典读三项：`vmType`（bfc_integerForKey，CFString 0x11d0f76d0）、`vcTitle`/
`pvEventId`（bfc_stringForKey），vmType 经 `+[BBHD2PhoneSettingVMFactory
createSettingVMWithVMType:]`（0x10c927038）映射，>0xC 回退 BBHD2PhoneSettingBaseVM。
跳表（字节表 0x118e385f8，基址 0x10c927078）解码出的完整映射：
0→MainVM、1→SafeVM、2→CacheVM、3→PlayVM、4→PushVM、5→OtherVM、6→AboutBiliVM、
7→PicQualityVM、8→PicWatermarkVM、9→PrivacyRightsVM、10→PlayVM（经
initPlaySettingVMFromEntranceType:，入口键 CFString
`BBHD2PhoneSettingEntranceTypeFromVideoDetail` 0x11d0f8610）、11→PersonalizedRcmdVM、
12→DarkVM。vcTitle 写 navigationItem、pvEventId 经 setPvEventId: 并伴随
`main.setting.0.0.pv`（0x10c91c08c/0x10c91c098）展示埋点。页面跳转子页由
`-[BBHD2PhoneSettingBaseVC navigateToSettingPages]`（0x10c91b258）安装 pushVCBlock：
块 0x10c91b314 复制 LynxRoute 后 pushViewController:animated:1（0x10c91b358）；
cell 点击 didSelectCell（0x10c91ba18）只转 tapCellModel 的 tapMethod performSelector:。
即设置子页导航是 LynxRoute 复制+原生 push，与此前"feedsetting transfer 注册内容
静态不可判"互补：vmType 层映射已闭合，host 字符串→LynxRoute 的注册仍不可判。

### 设置上传缓存与重试边界

BBCDeviceConfig.init 0x114fa9204 设 delay=1.0、retry=0，分别建 request/file 串行队列，
读取 DeviceConfig 目录下 cloud_config/cloud_op/cloud_diff/cloud_universal_config/
cloud_universal_diff 五个 GPB 文件。Tools.syncMessage 0x114fabd38 非空 data 走
writeToFile:atomically:YES（0x114fabdd4），空则 removeItem；路径没有 MID 参数，
但不由此排除外围换号清理。triggerRetryLater 0x114faa9ec 计数>4拒绝，否则递增并
固定延迟10秒再syncDiffToRemote；初始0最多安排5次延迟重试，两成功腿0x114faa19c/
2e8清0。无指数退避证据，也不是全进程总共只重试5次。
证据 root-static-remaining/findings.md；成功IO/账号外围清理与实际配置合并另验。

<a id="设置上传入口的账号门禁task-13-补"></a>

### 设置上传入口的账号门禁

`startUniversalConfigSync`（0x114fa9348）入口无登录门禁：body 直接构造 completion
block（block 0x114fa9398→requestRemoteUniversalConfig）并以 self 调
syncDiffToRemote:（0x114fa9388），不查 hasLogin/用户；上传内容不含 mid/账号字段
（SetUserPreferenceReq builder 只赋 field1，既有结论），账号归属完全由公共层登录态
承载。调用方是否在登录后才调用该入口属运行期装配，静态不可定。

### 字幕选择、AI翻译目标偏好与公共 Locale 元数据

STCaptionBloc主字幕菜单builder0x10412e040安装click0x10412ef60→0x10412dae4，
选择副字幕0x10412eee0同helper；weak bloc有效才向捕获caption service发
chooseMainItem:/chooseViceItem:，再sendSutitlelanguageTrack:，scene字面量"3"。
BBPlayerCaptionService0x114855f30/0x114856010→0x114856c98更新selectedMain/Vice、
currentLanguage文本及context.danmaku.config.enableCaption/mainLanguageCode/viceLanguageCode。
config setter0x11485b6b0/0x11485b6cc是copy ivar setter。changed block由播放器
0x1041a9090安装（0x1041a9174），经0x1041a9464→0x1041a86d4到可选服务
subtitleLanguageDidChanged:secondaryLanguage:；native实现0x1143b6d70只更新Chronos
OnDanmakuConfigChanged，nil language→kBBPlayerSubtitleNone，所查路径无全局目标偏好writer。
sendSutitlelanguageTrack:0x11485733c上报player.player.subtitle.language.player，字段
bilingual_subtitles_status/language_code/scene/status/big_subtitles_status；这是事件入口，
不能当字幕下载或语言持久化。其他字幕设置入口仍需单独核对。

AI target则有实际偏好writer：BBPlayerAITranslateService.switchLanguage:
0x1049cccd8→0x1049cc80c比较currentLanguage与incoming对象指针，相同（含nil/nil）
直接返回；变化时设置currentLanguage并调用VBPreferences.shared.setTranslateLanguage:
（0x1049ccbb0），值incoming.lang、缺失→nil。随后currentScene.reloadType=4
（0x1049ccc40）并调用重新获取的currentScene.reload0x1049cccac。
closeTranslate0x1049ccd20传nil，也受相同指针门禁；reload调用不等于已发HTTP。
Story AI菜单0x104126e1c要求live player/service key0x1203f2550及language.items，
row selected同样用对象指针（0x104127084），languageType2加AI badge。
row click0x1041293b8→0x104127764要求weak bloc/weak row有效，重新resolve live service，
可选openToast后switchLanguage:capturedRow（0x104127910），dismiss/clear swipeVC，
再发main.ugc-video-detail-vertical.half-aidubswitch-option.0.click、option=row.title。
该callback没有把captured row与fresh service语言列表再次匹配；不据此声称实际竞态。

VBPreferences class0x11ff10888继承BFCPreferences0x1202710f0；translateLanguage是
NSString dynamic-copy属性，configName0x104b9872c固定VBPreferences，不拼MID。
init0x104b9844c→0x104b98284订阅KntrTranslation.alwaysTranslateFlowIOSAsync；callback
0x104b984f4忽略传入Bool，重读alwaysTranslate：true取KntrLocalization.current.language，
false取nil，再写translateLanguage（0x104b985f4）。所查setup没有dropFirst；实际首次
投递时机仍未知。此订阅可覆盖播放器先前选择，账号/上游flow写入边界继续追踪。
已闭合的preload helper读取此偏好作cur_language；不要等同Story card-trans五字段请求。

Locale元数据走独立缓存：0x105060e60创建LocaleCache，初始六空String/+0x78 false，
同步refresh0x1050624ac重读KntrLocalization.SYSTEM/current两组language/script/region和
KntrTranslation.alwaysTranslate，然后在锁内替换六String与Bool。观察0x1050627e4
组合localeFlowIOSAsync/alwaysTranslateFlowIOSAsync，SkipCount factory0x1050fc84c
（metadata0x1050fc894、count写+0x18@0x1050fc8c0），caller0x105062adc传1。
callback0x1050638ac→0x10506382c忽略tuple，weak cache有效才完整fresh-read refresh。
因此先同步初始化，再跳过一个组合投递；不猜具体投递频次/运行值。

0x10505f9ec和0x105060cb8均在锁内snapshot六String/+0x78，调用builder0x105060f44
构造BAPIMetadataLocaleLocale，设置sLocale/cLocale/alwaysTranslate及系统Timezone/GMT offset。
这里setAlwaysTranslate:0x10506115c是PB setter，不是KntrTranslation setter。
不读VBPreferences.translateLanguage。header producer0x10505f9ec对Locale.data非nil时
base64EncodedString(options:0)（0x10505fb84），插入x-bili-locale-bin
（0x10505fba0）；nil data省略。conformance0x118436c80解析protocol LocaleRegionService
0x1196b139c、type MetadataStore0x1196aed58，wtable0x11b347318：+8→0x10506043c→
header map，+0x10→0x10506045c→0x10505ffcc二进制map，+0x18→0x10506047c→
0x105061414 region。provider0x10008da60以once0x120897bc8/cache0x120897bd0返回该
existential，initializer0x10008dfd4。最终HTTP/Moss overlay和采用范围继续追踪；
不能从header builder推断所有请求必带，也不能把player target-language与此Locale合并。


HD2 notice close 的UI与网络效果另有完整入口：WiredNoticeView第一个UIButton
0x10df52cfc经RAC control0x40（0x10df52f24）、throttle0.3秒（0x10df52f40）到
weak view closure0x10df53ecc，把frame置CGRectZero后closeSignal.sendNext:nil
（0x10df53ef4/0x10df53f10）。外层closeSignal0x10df1ab34经main deliver订阅
0x10df1b088，读当前homeVM.closeWarning（0x10df1b0b0），随后立即hideLoginWiredView
（0x10df1b0c0）。hide0x10df1b61c只remove notice view、重做当前mainVC view constraints，
没有清wired type/info/shared Date/推荐曝光池。closeWarning0x10df58370构造
POST https://api.bilibili.com/x/member/v2/notice/close（0x10df5845c），同uuid和
mid=userSID及NSDictionary /data parser，无业务completion/error handler，
requestAsync0x10df58478后释放局部request。UI隐藏不等待ACK，所查路径无rollback；
后续wiredInfo投递仍可能重新显示，不能声称服务端已关闭或永久清除notice。


### UPOS 各阶段配置、分片状态适配与取消通知

Initial class0x12020c6b8/Merge0x12020c708/Pre0x12020c848的原始method lists均无
Base timeout/times/interval覆盖，沿已查正常manager用120/10/3。
SinglePart class0x12020c8e8则明确覆盖：0x114aaef40/0x114aaefb4/0x114aaf028
读取taskConfiguration.timeout/timesOfChunkRetry/delayIntervalOfChunkRetry。
configuration parser0x114aa82a8解析chunk_size/threads/timeout/chunk_retry/
chunk_retry_delay/endpoint/endpoints/upos_uri/put_query：zero chunk_size→8388608，
threads unsigned≤1→1，zero timeout→900，zero chunk_retry→200，zero retry_delay→3
（0x114aa83cc/0x114aa8404/0x114aa8444/0x114aa8500/0x114aa853c）。
这些是pre响应解析默认值，不是实际服务配置或全局retry budget。Simple timeout
0x114aadc18另按options.size作移位/高位乘法后+5，不能套固定120。
SinglePart.retryOnFailure0x114aaedd4增加partInfo.timesOfRetry并发retry通知，
实际重试调度仍走Base failure closure。

Pre.apiRequest0x114aac48c优先非空request.preUploadUrl，否则
https://member.bilibili.com/preupload（0x114aac698/0x114aac6a8），GET。
mutable-copy options.queryDictRepresentation，加入r=upos、name=filePath.lastPathComponent、
profile。success0x114aac970解析configuration，仅endpoints非空才记ctimeOfPreupload/
taskConfiguration、推进phase并通知更新（0x114aaca38/0x114aaca7c/0x114aacb94）。
Initial0x114aa97b8使用公共URL format "https:%@/%@%@"，activeEndpoint及
NSURL(uposUri).host/path填入，不自行补slash或固定动态域名。params uploads=""、
output=json，customInitialParas后合并可覆盖；method raw2，X-Upos-Auth来自configuration.auth，
BFCApiRequest init0x114aa9ba4。Merge0x114aa9f34同format，改用activeEndpoint及
storageInfo.bucket/key；output=json、uploadId、biz_id，needTranscode才添profile，
customMergeParas后合并可覆盖（0x114aaa308）；method raw2、auth非nil才添同名头，
init0x114aaa4fc。不读取实际auth/endpoint/上传资料。

SinglePart0x114aadd4c同URL规则及auth头、ignoreCache1/signType1，params为decimal
partNumber及uploadId。非background路径seek partInfo.offset、读partInfo.size字节，
taskType4/localData；background为taskType3/localPath。requestInjection0x114aae5ac
mutable-copy最终request并明确设置PUT（0x114aae5cc）。preProcessRawData
0x114aae5e0仅HTTP status200合成JSON code0（0x114aae630/0x114aae6a0），其他nil。
这是传输状态适配，不是服务端返回JSON code0或所有分片已持久化的证明。

Task.cancel0x114aa5740→TaskManager.cancelTask0x114a9d1c8；running operation存在才
cancelOperation、删UPOS task cache、state0，再notifyTaskDidCanceled；无operation也通知，
但跳过这段删cache。OperationManager.stop0x114a9b4c8取消uploadQueue，Base.stop
0x114aa88a0设isStop1并main common modes排BFCApiRequest.cancel、waitUntilDone=false
（0x114aa8960）。取消通知0x114a9be9c→block0x114a9bfbc只向delegate发
uposUploadTaskDidCanceled（0x114a9bfe4），不调用task.completionHandler。
因此不能把它当Laser upload-completion0x114a92290或semaphore signal；底层request
指定error回调0x114aa8d48–8fec已复核（root-static-remaining/findings.md）：weak nil直接return，预算未尽dispatch_after重入sendRequest，isStop/checkError命中走epilogue不completion；预算耗尽failure0x114aa8f8c→notifyTask→delegate block→实际completion间接call0x114a9bca0（旧bc90仅加载block指针）→Laser0x114a92290合流0x114a923e8 signal。所选error链无直接signal但有条件间接completion；真实取消是否到该error及交错仍另验，不声称必然hang。

Laser Task.init0x114a92930记录UUID/createTs；缓存parser0x114a92c08恢复createTs，
cache.tasks0x114a8fc38重建后直接加入（0x114a8fd38/0x114a8fd50），所查循环无age门禁。
createTs selector stub0x117292060的直接B/BL扫描只见metrics及dictRepresentation；
不覆盖直接ivar/动态访问。Laser任务无TTL字段已闭合（cache恢复无age门禁）；generic suite clear已排除（removePersistentDomainForName: 0x1174d7ea0 仅UASDKStorage，team-g3全量扫）。十项task-ID上限
不能写成TTL。UPOS自身另有expired-task数据库路线，不能移植给Laser Preferences。


Story More的AI两种动作与card translation独立：raw35 jump0x104184d94→
aiAudioWithItem:customModel:0x10418d3b0→0x10418cb04要求SwitchModel，观察
live service.base.currentLanguage，callback0x10418ef18→0x10418cf5c只按非nil设置isOn。
switch click0x10418ef20→0x10418cfc4重新resolve service，Booltrue→openTranslate
（0x10418d0a8），false先dismiss再closeTranslate（0x10418d194/0x10418d1a4）；
可选open/closeToast及More事件报告，不直接发HTTP。
openTranslate0x1049cd0cc→0x1049ccd30按items顺序寻找lang等于新读的
KntrLocalization.current.language，未匹配再取fresh items首项，nil/空→nil，
然后switchLanguage:（0x1049cd08c）。这个body不读取保存的translateLanguage来恢复选择。
raw36 jump0x104184af4→aiAudioExchangeWithItem:customModel:0x10418dad4→
0x10418d3bc，click0x10418ee88→0x10418d954→STAITranslateBloc0x104128f94，
旧swipeVC dismiss/raw0并清引用，再建上述language rows、VKSettingVC，以
STPoperOptions.session=translateList呈现（0x1041290bc/0x1041291a0），weak保存结果。
只打开panel不修改语言/偏好；raw37仍是前述card-trans。

AI reset0x1049cbe3c→0x1049cbd78只清service.language/currentLanguage、四组handlers和
guide/toast状态，没有switchLanguage、VBPreferences setter或scene.reload。
STAITranslateBloc virtual0x104126324→service.reset（0x1041263cc）的**归属已闭合（team-c32）**：
`sub_104126324` 的地址位于 `__objc_data 0x11fe2d998`，该槽紧邻
`_OBJC_CLASS_$__TtC5Story17STAITranslateBloc`（0x11fe2d870）与其 method list
（0x11fe2da08）⇒ 它是 **`STAITranslateBloc` 类数据里的 Swift 虚函数槽，不是 ObjC method-list
条目，因而没有 selector 名**，`find_callers.py 0x104126324` = 0 属结构性结果。body 逐指令：
`[x20 playerBloc]`（selref `playerBloc` 0x11f6ccc8，0x10412633c）→ `[. player]`
（selref `player` 0x11f6ca28，0x104126354）→ player 为 nil 即返回（0x104126370 `cbz`）→
`swift_getObjectType`(0x104126378) + 懒元数据 accessor `sub_100027650`（描述符 0x1203f2550）+
`sub_10408C904`（Swift 动态转换/一致性查找）→ **0x1041263c4 装载 `__objc_selrefs reset`
（0x11f6cc4c8），0x1041263cc 用 `objc_msgSend` 对 `playerBloc.player` 发 `reset`**。
即旧文的“service.reset 0x1041263cc”是**该虚函数体内的一条 msgSend 指令**（不是函数入口，
故对它 `find_callers` 也为 0）。残余：`playerBloc` 属性写入方与 STAITranslateBloc 实例装配点
（Swift 侧间接装配）；下一步 = `query_index.py '*setPlayerBloc*' 10` 取 setter stub 后
`find_callers` 该 stub。
因此显式close写偏好nil与局部reset清内存不能混同；其他生命周期writers继续核对。


### HD2 MainVM 迟到回执的原VM与共享状态边界

apiProcess0x10df58dfc的success0x10df59104/error0x10df59ab8均捕获weak原VM于block+28；
success+20强捕获requestparams.open_event，error+20捕获请求时appstate字符串，
另捕获retry/isActiveRetry两个byte。requestAsync0x10df59030后局部request释放
（0x10df590a4），所查body无VM-owned request setter/cancel token。MainVM.dealloc
0x10df58880只移除Account/Notification observers再super；继承链
MainVM→3PointListVM→BaseListVM→BaseVM的**继承链已闭合（team-c32，按 objc_class superclass 指针逐跳）**：
`BBHD2PhonePegasusMainVM`（0x120041b08，74 个方法）→ super `BBHD2PhonePegasus3PointListVM`
（0x12003ef48，21）→ super `BBHD2PhonePegasusBaseListVM`（0x12003efe8，27）→ super
`BBHD2PhonePegasusBaseVM`（0x12003f128，26，其 super 指针读为 0）。**该族全系没有
`cancel`/`cancelAll`/`cancelRequest` 之类“public 全局取消”API**——唯一含 cancel 的方法是
`-[BBHD2PhonePegasus3PointListVM cancelDisLikeCardWithModel:]` 0x10deddb14（取消“不感兴趣”卡，
不是请求取消）；全索引 `*VM*cancel*` 的其它命中均属别的类（`SpecialStyleBiliVM cancelTask`、
`BBUperUploadTask cancelRequest`、`BBStudioVideoExportVM cancel` 等）。
⇒ **“穷举全局 cancel 调用方”没有对象**（不是没找全，而是该族不提供取消入口），
这与本段“所查 body 无 VM-owned request setter/cancel token”一致且现有继承链级证据。
残余：hop3 的 super 读为 0（根类或类数据布局差异），其上若还有 Swift 基类的取消语义需元数据层核对；
运行期仍需确认请求是否被上层（scene/账号）取消，**不据“本族无 cancel”断言旧请求一直存活**。
不据局部无cancel断言所有旧请求一直存活。

success完整0x10df59104至0x10df59978无nil VM、当前outer.mainVM或账号generation门禁。
原VM仍作为sceneUri/needShowGuidance/follow_mode/noDataTip/visible_area/interest/
login_event/updateArray/error/loading/objects/isEnd/shouldShowBottom的receiver；
weak VM消失只令其ObjC消息无效，不使完整callback退出。共享Config的
isFeedReqSuccessOnce=true（0x10df591f8）、pegasusCloumn（ipad_hd_abtest NSNumber
true→3/false或错型→4）、BBAdPegasusHelper.setIPadCloumn、RefreshHints autoRefreshTime、
FormatManager column、InlineShared autoplay都可继续执行。
config.home_transfer_test→global0x1210e10d4（0x10df59440），
show_inline_danmaku intValue==1→global0x1210e10d0（0x10df5947c）；
shared MainApiHelper**当前**firstRequestInfo非nil才清空（0x10df595dc/0x10df59614），
无请求归属比较。missing key的numeric ObjC消息多为0，typed fallback要单独保留。
因此不能把原VM消亡写成旧回执没有共享副作用；是否真实发生与外部取消属运行期弱网/换号交错，静态不可判定（共享写入清单0x10df591f8/0x10df595dc已闭合），验证需真机复现。

CardPool conversion callback0x10df59978强捕获success阶段读到的原VM，用page_from="1"、
原VM from_spmid_v1/v2及conversion callback index+1→report_flush_idx，timestamp
来自card.getCurrentTimestamp；CardPool.dataArrayFromArray:modelAnalysisCallback:needToReport:0x10df17f54的x23从0
逐raw input增加（0x10df17fc0/0x10df17fe4/0x10df18674）；转换后在nil/isValid过滤和
加入结果之前调用callback(model,x23)（0x10df18074/0x10df1807c）。因此该HD回调的
report_flush_idx是raw input ordinal+1，unknown/missing/invalid不压缩编号；嵌套items
子卡callback仍用parent raw x23（0x10df1832c/0x10df18330）。banner_item子项另用
child index+1（0x10df18564–0x10df18594）。不要套Swift compactMap的编号规则。
first converted CardBaseModel idx保存见前述修正，与loadMore末卡不同。

error完整0x10df59ab8至0x10df59fdc同样无nil/currentVM/account门禁。
trackTech0x10df59d00先使用incoming error.description、捕获retry/activeRetry/appstate及
当前launchState/当前UIApplication.appstate；没有error.code=-999绕过。
retry byte恰为1才读原VM当前options再apiProcess，retry分支暂不清loading/error；
nil VM不重试，但tech仍可执行。最终分支原VM当前objects.count=0（也包含nil VM）
生成tm.recommend.load-error.0.show（0x10df59e54/0x10df59e64），error_code来自incoming
error.code decimal，load_scene来自原VM.emptyErrorReason、nil VM numeric0。
随后空分支reason=3，全部final errors向原VM写loading=false/errorincoming；net error→
overflow String1，否则objects非空→String3，空则无overflow。无当前outer VM重定向或
UI exposure pool reset。仅记录静态来源，不读取实际error或声称已复现迟到回执。

### UPOS 自身数据库过期与停机后的回调门禁

Config.init0x114aa5050的expiredDay默认2（0x114aa5088/0x114aa508c），可被setter改变。
CacheManager.ensureCacheEnabled0x114a9f844首次置enabled=true后alloc/open，传
config.cachingDirectory/expiredDay。openDatabase0x114a9f91c调用getExpiredTask：
transaction0x114aa0590用signed truncation(now Unix seconds - unsigned(days*86400))
执行SELECT task_identifier FROM upos_config WHERE ctime_of_preupload < ?
（0x11d38d830/0x114aa0658），ctime来源pre成功回执，不是LaserTask.createTs。
有expired IDs先delegate.tasksHaveExpired，再逐deleteTask0x114a9fa78。
实际Client.tasksHaveExpired0x114a9988c删file cache（0x114a998f4），可选delegate
每ID收到taskDidFinish(identifier,error7)（0x114a999e0）；这不是upload completionHandler。
首次enable/open做过期处理，不是所查restore每次读取都重新比较age；未读实际DB/目录。

BFCOperation.cancel0x114ab02b8只有executing才performer.stop（0x114ab0300/0x114ab0318）。
UPOS error callback0x114aa8d48若weak manager存在，仍可clear internalRequest、
sessionEnd/增retries/排delayed retry（0x114aa8f2c），该callback无isStop检查；
但下一sendRequest0x114aa89ac先构造apiRequest/保存，再checkError/isStop，
isStop门禁0x114aa8a18在requestAsync之前阻止新send。停机仍可能发生构造/通知/调度，
不能等同又发网络；该路径仍不足证明Laser completion收到取消或wait一定释放。

pre query producer0x114aa7a1c无条件字段traceId/device/osVersion/build/version；
mid/appKey/accessToken/networkType各nil-gated，size非零才decimal String，path非nil才加。
之后pre覆盖r/name/profile。只记字段来源，不解码凭据、身份或实际设备值。


### Story AI语言偏好到 Unite 播放解析及响应回显

BBStoryPlayableScene.getPlayItemFromPreloadItem0x1132f7704要求preloadItem非nil，
读取VBPreferences.translateLanguage，交preload.response.availableWithLang:
（0x1132f7774）。允许复用时从preload.resolverItem构建play item；不允许时清除
当前model.resolverModel.preloadUrl（0x1132f7880），重新读取目标偏好写curLanguage
（0x1132f78b0）、curLanguageType=0（0x1132f78cc）、clientAttr&~2
（0x1132f78e0），存回model并返回nil。playWithParams0x1132f61e4在nil分支调用
resolveToPlayEnablePreload:true（0x1132f650c）；后者0x1132f6540要求resolverModel
符合BBResolverUniteParms，才调用UniteHelper（0x1132f6644，updateBlock=nil）。
这闭合了请求材料变更与解析入口，不把偏好setter或reload直接当成已发送请求。

availableWithLang0x114a0b300在language.items.count=0时立即true；否则读取
alwaysTranslate，true才取当前locale.language作自动目标。扫描语言列表：非空传入偏好
在列表中时要求response.curLanguage等于偏好；否则自动目标在列表中时要求等于自动目标；
两者均不可用时仅curLanguage.length=0允许复用（0x114a0b558–0x114a0b5d4）。
该body不比较curLanguageType、不写偏好；列表及locale是fresh reads，未观察实际并发。

UniteHelper.resolverWith0x114a4c8d8：isCantUseLocalCache=true直接IgnoreCache；
否则kmpOffline决定KMP或native离线解析。离线callback0x114a4ca90/0x114a4cbe0
有response就向原completion交付，即使error非nil；仅response=nil回退IgnoreCache。
IgnoreCache0x114a4cd30重新读preloadUrl，非空走PreloadResponse、空走PlayViewResponse。
Preload失败且response=nil也回退PlayView（0x114a4cef4）。通用helper的离线路径仅适用于isCantUseLocalCache=false。具体Story初始factory
tranfromUniteParsModelFromParams0x11330c148显式setIsStoryMode=true（0x11330c1a4）、
setIsCantUseLocalCache=true（0x11330c1b0），末尾fresh VBPreferences.translateLanguage
写curLanguage（0x11330c510/0x11330c528），该factory完整body无curLanguageType setter。
所以这个producer的参数直接走IgnoreCache；若后续语言不匹配清preloadUrl且仍使用该model，
进入PlayView。其他model来源仍保留通用离线条件，不把所有切换都宣称为实际联网。

PlayViewWith0x114a4dcfc构建BAPIAppPlayeruniteV1PlayViewUniteReq与VideoVod：
params.curLanguage→vod.curLanguage（0x114a4dfec），curLanguageType→
vod.curProductionType（0x114a4e008），clientAttr→vod.clientAttr；Story回退的type0
确实进入PB字段。aid/cid/qn来自params；fourk来自IJKFFUtils.isUhdSupported，fnver=0，
softFnval/fnval来自BBResolverUtils两个支持函数，voiceBalance来自enableLoudNorm，
isNeedTrial来自params，qnPolicy仅params.qnPolicy==1时true。download=true设置
下载raw2/forceHost2；普通播放forceHost2由forceHttps或播放器httpsPlayurlEnabled决定。
request的spmid/fromSpmid/bvid/adExtra/fromScene/playCtrl来自params，extraContent.copy
（0x114a4e090/0x114a4e0a0）；lastReply.fragmentVideo非nil时清片段reports后复用。
codec及其余分支另证，不读取实际身份/广告字段值。

实际dispatch0x114a4e350调用Player.playViewUniteWithRequest:handler:；class入口
0x114a6ec84取得defaultService，instance0x114a6ebf8将request、Reply class、
service对象+8和方法字面量PlayViewUnite交BFCMossServiceWrapper.handleRpcRequest
（0x114a6ec60）。这是业务到Moss wrapper的调用证据；公共transport元数据采用范围
需沿独立transport链核对，未运行RPC。

RPC callback0x114a4e3d8：incoming error非nil构造type2业务错误，优先非零bapi_status.code、
非空bapi_status.message，分别回退NSError.code/localizedDescription；reply=nil且无error
为30004/type2。reply非nil但hasVodInfo=false为30005/type3，stream count0或parser.asset=nil
为30004/type3。type3仍执行parser，内部completion可带parsedresult/supplement但asset等nil；
外层0x114a4d180有error时直接main completion(nil,error)，不会把该parsedresult应用到Story。
无error才构建BBResolverUniteResponseModel，继承initWithPlayViewInfo0x114a0bb2c复制
language（0x114a0bca8）、curLanguage（0x114a0bcd0）、type（0x114a0bcec）。
Story completion0x1132f66a0要求weak scene存活；error→_playError（0x1132f66ec），
无error→setResponse（0x1132f66f8）→_playWithResolverResponse，enablePreload取捕获true
（0x1132f6708）。这些局部body未见MID/avid/generation比较，未据此宣称已复现串回执。

Parser0x114a48ec4把reply.language经parseLanguageWith0x114a43ebc变成BBResolverLanguage，
保持items顺序；item.productionType→languageType（0x114a44078），并复制lang/title/
buttonTitle/subtitleLang及语言菜单/开关toast字段。reply.vodInfo.curLanguage→result.curLanguage
（0x114a4951c），curProductionType signedInt32→result.curLanguageType（0x114a49550）。
Story updateTranslate0x1132f7f38及Swift入口0x1041c0eb8把response三字段交AI service.setup
（0x1132f7fd0/0x1041c0e70）。setup0x1049cbe64选择首个optional lang匹配且languageType
匹配的item（helper0x1049d0740），直接setCurrentLanguage（0x1049cc0f8）；缺/空items清本地
language选择与flags。它不调用switchLanguage、不写VBPreferences、不reload；因此服务器回显
恢复当前选项与用户目标偏好writer是不同阶段。

### HD2 loadMore 的原VM当前数组与入口门禁

直接MainVM.loadMoreData0x10df5a4c0仅检查isLoadingMore；正常tryLoadMoreData
0x10dedfa14另要求!isLoading和tryLoaded，super.loadMoreData0x10dedfa54设置两个loading flags。
成功0x10df5a898及错误0x10df5b04c捕获weak原VM，不在这些回执body比较当前outer VM、
账号或generation；producer requestAsync后释放局部request，未见VM-owned cancel handle。
成功即使原VM消失仍可更新共享autoRefreshTime/autoplay及home_transfer_test、
show_inline_danmaku（0x10df5a938/0x10df5aa20/0x10df5aa5c/0x10df5aa98）。
转换后读取原VM的CURRENT objects（0x10df5acb0），追加本次转换数组（0x10df5acc4），
超过loadMoreMax裁prefix（0x10df5ad0c），再setObjects（0x10df5adf4）；不是请求起点数组快照。
达到max或review置end/bottom，低于max且新数组非空可继续；新数组空则end并overflow4。
转换callback的flush_idx也采用上述CardPool raw ordinal+1。

错误先tech上报（0x10df5b1b8），再清loading/more并写incoming error；该完整body无retry或
-999静默分支。当前reachable=false时overflow用先前捕获currentStatus raw值；reachable=true
且原VM当前objects非空才固定overflow4，否则不发该overflow。正常入口门禁仍适用，缺generation
比较不等于已观察并发乱序。BaseListVM/BaseVM method table无own dealloc，其destruct只释放字段；
全局dispatcher、外部所有者和完整运行时取消边界仍未知。

### WatchLater 管理菜单到确认与工具栏动作

管理sheet producer0x10110f67c读取静态三项数组0x12030a768；MoreAction.Action
reflection0x1194eebbc/0x1197d51bc的empty cases依次为clearAllWatched、clearAllInvalid、
batchManagement、delete。数组前三项tag2、ordinal0/1/2映射前述三动作。
SheetModel经MoreAction.Item转换；ActionSheetController.init0x1011333b4把传入row callback
存到clickItem（0x1011334b0）。viewDidLoad helper0x10112f82c向contentView witness+0x10安装
0x10113365c→0x10112fde8；该callback弱controller有效时启动dismiss动画
0x10112ff74，completion0x101133890→0x10112fe9c先dismiss(false)再读取live clickItem
（0x10112ff24/0x10112ff50）。该witness对应contentView的clickItem setter，物理row事件已在下段闭合。

row callback0x1011100c4→0x101119cd8读取Item.action并交captured action consumer；
0x101110078→0x10110f908在tag2时把ordinal0/1/2分别转MainAction族0xa0的1/2/6：
clearAllWatchedAlert、clearAllInvalidAlert、showManagementToolBar，然后交Store action callback。
前两项由已述确认弹窗才转clear_type2/1；批量管理转工具栏状态，未在菜单转换body直接请求HTTP。
菜单上游入口已定位为 Swift 装配点（team-c33）：闭包体 0x101110078 的**唯一** ADRP+ADD 引用在
0x10110f798/0x10110f79c（`add x8,#0x78`；0x10110f7a0 `stp x8,x23,[x0,#0x10]` 存入闭包对象），
该装配函数同时构建 `MoreAction.SheetModel`（type metadata accessor 0x10111993c，0x10110f740）与
`ActionSheetController`（accessor 0x101133664 + `objc_allocWithZone` 0x10110f7ac），并把四个兄弟闭包
0x101110078/0x1011100c4/0x101110080/0x101110088（0x10110f7e0–0x10110f7fc）作为按钮 handler 传入
⇒ `find_callers 0x101110078` = 0 是 Swift 闭包经元数据/闭包描述符间接引用的正常现象
（阳性对照：同区 ObjC 方法 0x1011100c4 的 find_callers 能回 2 点 0x10111080c/0x101110810）。
账号分支：0x10110f800–0x101110080 段内无 login/account/uid/mid 选择器（有界扫描阴性）⇒ 账号态
不在这段装配里。残余：该 Swift 函数入口与 ActionSheet 展示处的账号判断（下一步
`$PY disassemble.py 0x10110e800 0x10110f800`；运行期断点 0x10110f79c 观察 handler 装配时登录态）。
row物理接收者已闭合如下。


PlayView Vod codec分支由enable_new_playview_rule AB（0x114a4debc）决定：true取
min(params.preferCodecType,IJKFFUtils.preferVideoCodecId)，包括params=0，映射
getVideoCodecTypeWithId再减1，经0x114fbd490要求unsigned<5，否则raw0。
AB=false且hitAV1Support=true时params非零才与device prefer取min，零用device prefer；
相同映射/范围检查的invalid fallback却是raw1（0x114a4df60）。AB=false且AV1不支持
默认raw1，HEVC支持且params.preferCodecType!=7时变raw2（0x114a4df7c）。
最终写vod.preferCodecType（0x114a4df8c）；这里只保留已证raw值，不猜PB enum语义。

### HD2 刷新旧卡保留与布局裁剪

buildObjectsWithNewArray:clearOld:0x10df5a28c从CURRENT原VM.objects复制引用到OLD，
不是clone模型。needReloadForFeedStateChange=true且NEW非空时先丢OLD并清该flag
（0x10df5a31c），NEW空保留flag。clearOld=true或OLD空直接NEW；否则移除旧
refreshModel，NEW非空时在OLD index0插当前refreshModel（0x10df5a3b8），结果NEW+OLD
（0x10df5a3cc）。NEW空时只去掉旧separator而保留旧卡。完整builder不重新赋旧卡
track/timestamp/report_flush_idx，也不reset曝光池；其他writer/运行时行为另证。

combined count>=101才先prefix100（0x10df5a400），再调用evenNumbersArrayWithDataArray
（0x10df5a418）；<=100不调用。该selector stub0x10df5b2d4经machine-verified
0x10f835540→0x117185340实际到_pad helper0x10df5b2d8。helper按当前pegasusCloumn、
每个model.cellclass.cellSizeType、累计行宽和已完成prefix边界裁剪，并非简单count%2。
raw size1/2累计1/2，恰好column宽记录当前位置并清宽，超过则保留前一完成边界；
raw size4或refreshModel在不完整行时提前结束，其他情况可记当前边界。BannerList清宽且
完成边界递增1，不能直接等同循环index。空数组或无完成边界可返回nil，否则稳定prefix；
不排序、不改report字段，不推断raw size4的业务名称。关键累计/边界地址为0x10df5b4ac–0x10df5b4d4，nil返回0x10df5b548、prefix返回
0x10df5b578–0x10df5b584；结论仅适用本样本静态实现。


WatchLater sheet的contentView来源也有具体witness：MoreAction.SheetModel witness
0x11b1273a0的+0x20→0x101119974→0x10112f630，分配本模块ActionSheetContentView，
返回contentView witness0x11b127870（0x10112f6b8）。其+0x10→0x10112de98，
确把安装callback写入ActionSheetContentView.clickItem（0x10112ded8）。实际UIKit
method table入口tableView:didSelectRowAtIndexPath:0x10112e55c→0x10112f500
（0x10112e5dc），取IndexPath.row、校验当前items边界、读取该item，clickItem非nil
才调用（0x10112f5a8）。由此闭合row点击→弱controller→dismiss animation completion→
live controller.clickItem→MoreAction ordinal→Store确认/工具栏action。
动画helper的完成投递时序未运行；不把页面显示/菜单构造当成已选择或已经发送clear HTTP。

### HD2 notice 第二按钮的安全页面路由

showLoginWiredView0x10df1aa08每次新建NoticeView；当前type1取wiredInfo.location，
其他取title，再重读type==1作isDiffPlace（0x10df1aad0）。第二UIButton的control raw0x40
经throttle0.3（0x10df53708/0x10df5371c）→弱view发送enterSafeSignal
（0x10df53f58）；outer将signal交main scheduler→弱outer callback0x10df1b4e8。
callback重新读取当前type：1使用固定https://passport.bilibili.com/mobile/index.html；
2读取当前wiredInfo.url，要求非nil但没有空String长度门禁；其他返回。
BFCBusModel设置url后，以main/login_diff_place调用BFCBusMagiSystem，validator=nil
（0x10df1b5ec）。该完整callback不hide notice、不调用notice/close；页面路由并不代表
服务端安全处理成功，后续页面实现仍另证。


WatchLater上游实际管理按钮也已定位：MainVC.lazy manageButton0x1011251e0，作为
navigationItem.rightBarButtonItem.customView装入（0x101123c38–0x101123c78）。
绑定0x1011249bc取得同一按钮，以control raw0x40调用Rx helper0x105028f14
（0x1011249d0/0x1011249d8），订阅callback0x10112579c（0x101124a34），disposable
存页面bag。callback读live manageButton.isSelected：true→MainAction族0xa0 raw7
hideToolBar；false→raw5 showManagementSheet，交当前Store.slot+0x98（0x10112580c）。
raw5 reducer0x101115354先managementSheetShown=true（0x101115370），创建
AnonymousObservable、producer0x10110f67c（0x1011153b8/0x1011153c4）；Store订阅才呈现sheet。
raw6 batchManagement则清managementSheetShown并把当前分支isToolShown=true。
所以管理按钮、row选择、确认、请求是分开的实际阶段；按钮为selected时点击只退出工具栏。
完整账号变化处理与页面外部销毁/取消边界继续核对。


### HD2 follow_mode 响应持久化与 Logout 清理

MainVM.feedStateChangeWithDic0x10df5b62c由刷新/分页成功在原VM上调用；weak VM=nil时
ObjC调用自身无效，因此此方法内共享写入不能列入nil VM仍执行的清单。非空dic且能映射
FeedStateListModel时shared FeedStateManager.setFeed_mode（0x10df5b6b0）并
needFeedStateSetView=true（0x10df5b6bc）；空dic置该Bool false（0x10df5b6d4），
且仅当前followState==1时原VM.feedStateExitViewNeedShow=true、shared.followState=2
（0x10df5b6f0/0x10df5b6fc）。**推荐卡的按钮创建/注入已排除在该范围之外（team-c33）**：全函数
0x10df5b62c–0x10df5b71c 读完，只有 `shareFeedStateManager`（0x10df5b654）、
`BBHD2PegasusFeedStateListModel` 映射（0x10df5b674–0x10df5b6a4）、`setFeed_mode:`（0x10df5b6b0）、
`setNeedFeedStateSetView:`（0x10df5b6bc/0x10df5b6d4）、`followState` 比较（0x10df5b6dc）、
`setFollowState:2` 与 `setFeedStateExitViewNeedShow:`（0x10df5b6f0/0x10df5b6fc）这些**数据写入**，
无任何 UIButton 创建/`addTarget`/视图注入指令。阳性对照：同模块
`-[BBHD2PegasusFeedStateExitView installSubView]` 0x10df4d960 内可直接看到
`myTitleLabel` 0x10f860918 / `descLabel` 0x10f848090 / `closeButton` 0x10f842f58 的 `addSubview:`
（0x10df4d988/0x10df4d9b0/0x10df4d9d8）与 `closeButton` getter 0x10df4de8c ⇒ 本模块按钮是可静态
定位的，故此处阴性可写。残余：承载「推荐卡 follow-state 按钮」的卡片视图类未定位（阳性对照 0x10df4d960 可静态看到 closeButton 0x10df4de8c；下一步
`query_index '*BBHD2Pegasus*View*' 30` 后反汇编候选 view 的 installSubView/layoutSubviews）；
点击落地走集合视图选中代理（见下条 0x10df3dcbc→0x10df3de20）。

FeedStateManager是once0x120c97ff0/global0x120c97ff8；init0x10df070b0创建固定
NSUserDefaults suite字面量feed_state_userDefaults（0x10df070f4/0x10df070f8），不拼MID。
setFollowState0x10df07158仅incoming不同于RAM+8才写RAM、setInteger key
kBBHD2PegasusFeedStateType（0x10df07188）并synchronize；getter0x10df0719c在RAM非0
复用，否则每次integerForKey（0x10df071c0）。needFeedStateSetView的Bool缓存规则类似：
相同值setter不写，true复用、false重读defaults。feed_mode getter在RAM对象非nil复用，nil时
读归档key kBBHD2PegasusFeedStateSettingKey（0x10df0727c）并unarchive；setter0x10df072d0
每次strong存、归档/setObject/synchronize（0x10df07340），nil传nil。
所以响应follow_mode可以落本地固定suite，后续MainVM.loadData/loadMore读取shared.followState（0x10df58d08/0x10df5a5e4），
仅raw1→请求recsys_mode=1，其余raw0/2→0（0x10df58d18/0x10df5a5f4）；
不是把followState直接发成follow_mode，follow_mode是响应键。
缓存零/false不能解释成默认无条件磁盘零；未读取任何实际defaults内容。

outer账号observer mask6只接Logout2/Update4，前述Logout2且hasLogin=false分支
0x10df1a85c实际向shared FeedStateManager发clean。索引nearest symbol的clearButtonPressed
曾有误导；machine branch0x10f8425c0→0x117254620确为_objc_msgSend$clean。
followState==1只决定前置toast，不限制common clean调用。clean0x10df07120依序
setFollowState0（0x10df07134）、setFeed_mode:nil（0x10df07140）、
setNeedFeedStateSetViewfalse（0x10df07154）。整数/Bool setter仍受RAM相等门禁，不能把clean
描述为无条件强写全部defaults；此Logout分支先读取followState。该固定suite的清理边界不代表
所有账号Change8都收到此observer，也不证明旧请求取消或曝光池转移。

管理按钮Rx physical绑定补足：0x105028f14创建订阅producer0x105029288→0x1050290b0，
weak control有效才创建ControlTarget（0x105029174），传入捕获controlEvents raw0x40。
ControlTarget.init0x1050074b8把callback和events存入自身，并实际向control
addTarget:action:forControlEvents:，action=eventHandler:（0x1050075c8）。这是物理事件注册；
订阅disposable取消的target removal与eventHandler forward仍需沿各自body核对。


管理按钮事件与dispose现已闭合：ControlTarget.eventHandler:0x105007268要求callback非nil、
weak control仍有效，调用callback（0x1050072dc）；该订阅安装callback0x10502995c发
next(Void)，进页面管理回调。返回disposable0x105029990→0x105029834解除retainSelf，
weak control有效时removeTarget:eventHandler:forControlEvents（0x105029898），
再把ControlTarget.callback函数/context清零（0x1050298b8）。这里取消的是UI target绑定，
不能套用为BFCApiRequest的HTTP cancel；list网络包装仍是NopDisposable。

### Locale 元数据的具体 HTTP/Moss 采用范围

公共producer/cache/LocaleRegionService witness见上节；具体注入key0x1204c28e8解析为
Inject<LocaleRegionService>。BaseInterceptorModule在334-class inventory index69
（0x120272a98），conformance0x1182514b0/witness0x11b0a8018的+8→0x10008dc3c→
registrar0x10008e010。registrar将LocaleRegionService作为flag0单绑定（0x10008e098），
HttpApplicationInterceptor/ApiGatewayInterceptor.Type/GRPCInterceptor分别flag1多绑定
（0x10008e114/0x10008e190/0x10008e20c）。API/GRPC exact keys0x120276370/0x120276378
接既有ApiClient.moduleInitialize的registerClass（0x1049bea30）及Moss.moduleInitialize
的registerGateway（0x100151914/0x100151920），不是只凭类名推断启用。
184-runnable inventory index36（0x120273d90）执行0x10008de7c，也把相同once MetadataStore
经BFCDeepblueWrapper virtual+0x70真实setter0x10505e5ec赋到localeRegionService。

API gateway interceptor0x10506436c取当前gateway.request，nil直接返回；非nil解析
LocaleRegionService并调用witness+8（0x105064480），遍历headers→
URLRequest.setValue(_:forHTTPHeaderField:)（0x105064b38），写回gateway.request
（0x1050644ec）。相同名称覆盖先前request header。native HttpApplicationInterceptor
另有witness0x11b3476f0，+0x10→0x105063ed8→0x105063d68，取request.urlRequest，
同样调用Locale witness+8（0x105063e4c）并用同setter，最终setUrlRequest（0x105063e98）。
两个body未见host过滤，但入口/transport选择仍限制覆盖范围。

Moss interceptor0x105064530调用Locale witness+0x10（0x105064644），获取metadata map，
与existing gateway.extraHTTPHeader合并，producer同名值覆盖旧Any或新增（0x105063f90），
setExtraHTTPHeader（0x105064744）。这个map值类型混合：x-bili-locale-bin是Foundation.Data
（0x105060024/0x105060038），x-bili-metadata-ip-region与
x-bili-metadata-legal-region是String（0x105060158/0x105060294）；可选值缺失时省略/移除，
不是全部raw bytes，GRPC consumer这里也没有再base64。现有native defaultAutoRPC正常路径
最终addEntriesFromDictionary到callOptions.initialMetadata（0x115e09110/0x115e09124），
所以gateway同名元数据在该阶段又覆盖早先callOptions，再构造/start unary；gateway-response
fastpath不启动unary。未读取实际locale/region或身份值。

范围限制仍显式保留：BFCApiRequest.build在ktorRequestEnable=true时跳过API gateway
（0x116095ab8/0x116095b48）；旧task runner0x1000aae78在requestType2跳native application
遍历，其他type才调用该集合witness+0x10（0x1000aaf88）。这两项是不同门禁，不从旧type2
或wrapper赋值推断独立Ktor/KMoss/GrpcEngine拥有相同metadata plugin。之前经过gateway的
URLRequest可带已有headers，独立Kotlin consumer仍继续核对。
【9.13 抓包观测（线级，team-c20 本轮采集；证据 DerivedData/Validation/team-c20/locale-hosts.jsonl，
样本 round2/watch_events_official.flows + wireguard.flows，仅统计头名存在性）】把
`x-bili-locale-bin` 与三个 `x-bili-metadata-{ip,legal,recent}-region` 按 host 统计（共 3,611 条命中）：
api.bilibili.com 736（三个 region 各 662）、app.bilibili.com 547/528、**dataflow.biliapi.com
1,030/1,030（Neuron 日志通道）**、passport 169/169、pay 25、mall 25、member 21、show 2、data 2、
**grpc.biliapi.net 864/864（Moss/gRPC）**、**cm.bilibili.com 190/190（webview）**。
⇒ Locale/region 元数据的实际采用面**大于静态已闭的三个消费者**：Neuron 日志通道与 webview
广告请求同样携带同一组头；api 上 locale-bin(736) 多于 region(662) ⇒ 可选字段各自独立省略，
与静态“缺失则省略/移除”一致。本次未读取 locale/region 的**值**；`x-bili-locale-bin` 的
Foundation.Data 字节序列化与独立 Kotlin consumer 的装配点仍属残余（需抓包字节 + 反汇编对照）。


FeedState 代理的局部行为已闭合；**物理绑定已定性为集合视图选中代理，而非 UIButton（team-c33）**：
`-[BBHD2PhonePegasusMainVM clickFeedStateCellWithModel:event:]` IMP 0x10df5b71c 由代理
0x10df3dcbc→0x10df3de20 在 `didSelect` 路径调用；规范 stub
`_objc_msgSend$clickFeedStateCellWithModel:event:` 0x1172598e0 的 find_callers 只回共享桩页
自身地址（0x10f842afc 的 `j__` 页与 0x1170bbf00 的 canonical 页，桩归属不可信），**无业务
addTarget 调用点**；`query_index '*FollowState*' 30` 的结果全是模型/状态 setter
（如 `BBHD2PegasusFeedStateManager setFollowState:` 0x10df07158、`needFeedStateSetView` 0x10df07218），
没有把 follow-state 动作绑到 UIButton 的类。阳性对照＝同模块
`BBHD2PegasusFeedStateExitView closeButton` 0x10df4de8c 及其 `addSubview:` 0x10df4d9c0 可静态定位，
故本处阴性可写。残余：卡片内是否另有可点子视图（UIButton）需按上条候选卡片类核对。MainV2代理
0x10df3dcbc在SelectedModel、event等于right_button_event且当前未登录时，调用
Navigator.login（0x10df3ded8）直接返回，不移除卡。不属于该分支时要求CURRENT
VM.objects.containsObject(model)，随后以indexOfObjectIdenticalTo取得index，调用VM
clickFeedStateCellWithModel:event（0x10df3de20）。VM返回true时代理手动
collectionView.deleteItemsAtIndexPaths（0x10df3de74），false不做该删除。
VM0x10df5b71c在SelectedModel且shared.followState!=1时比较left/right event；
right匹配写followState1（0x10df5b95c），移除CURRENT objects中的同一模型。
返回true的移除用isUpdateDislike=true包住setObjects再恢复false
（0x10df5b828/0x10df5b850/0x10df5b864），对应代理手动删除；right匹配的false支路
setObjects不包该flag（0x10df5b890），交一般objects订阅重载。这两个完整body没有
API/RPC/tryLoadData；更改影响下一新建API的recsys_mode，不等于按钮立即请求刷新。
MainApi.params的recsys_mode写入在firstRequestInfo merge之后（0x10df57334），
因此这里对象Bool覆盖更早同名firstInfo值，之后player params merge及公共拦截器另有边界。


### WatchLater 列表实际行点击与 URI 来源

TableViewAdapter.tableView:didSelectRowAtIndexPath:0x101107d08先调用super
（0x101107dfc），再向selectPublisher发送当前IndexPath（0x101107e44）。
ListVC绑定0x10111b00c读取该publisher并订阅callback0x10111f04c→0x10111cb2c
（0x10111b14c）；订阅closure捕获页面，disposable存bag。callback读live tableView的
allowsMultipleSelection（0x10111cb68），通过当前Store.slot+0x80取得状态快照
（0x10111cb90），按页面pageTab查当前分支items，不使用请求发起时的旧items。

普通模式先校验当前分支与row边界，读取所选Item.targetURLString；只要求Optional非nil
（0x10111cdfc），完整分支未检查String长度。随后deselectRow:animated=false
（0x10111ce2c），BFCRouter.shared.processUrl:animated=true（0x10111ce90），
再报告main.later-watch.video-card.0.click，扩展avid来自所选Item.aid
（0x10111cfe8/0x10111d074）。Item mapper0x10110a3f0→0x10110bd00将
JSON uri映射targetURLString（0x10110be34–0x10110be64）；初始化该Optional为nil
（0x10110aee4）。这与Response.play_url映射到分支playbackURLString、工具栏播放
当前分支的入口不同；router后续解析/播放请求不从此callback推断。

批量模式同样读取当前分支items；row对应Item.cardType的bit0为0才派发
（0x10111ccc4），bit0为1或分支/row不成立则只取消选中。派发携带该Item.aid，
ListAction族0x40低位4，即tag0x44（0x10111d0c4/0x10111d0dc），交当前
Store.slot+0x98（0x10111d0f0）。不把这个选择action直接等同deleteItems或HTTP删除；
该回调完整body没有请求构造、网络发送或ACK处理，选择状态reducer继续单独核对。

### HD2 卡报告时间精度与请求局部序号

CardBaseModel.getCurrentTimestamp0x10df9166c读取NSDate.date
（0x10df9168c）、timeIntervalSince1970（0x10df9169c），FCVTZS截断为signed64
（0x10df916a0），以静态%lld格式生成String（0x10df916b4）。单位epoch秒，
没有乘1000、单调计数、随机盐或请求generation。刷新callback0x10df59978与分页
callback0x10df5af0c在解析每卡时分别调用并写report_timestamp_str
（0x10df59a94/0x10df5b028）；items子卡按同callback分别取时，banner_item则复制
父timestamp（0x10df185ec）。此处没有读取或输出实际运行时日期值。

CardPool转换每次将raw ordinal归零（0x10df17fc0）；刷新与分页均将ordinal+1写
report_flush_idx，没有加当前objects.count或page offset。因此这个字段是请求内原数组
位置，不是组合显示列表下标或跨分页递增序号。保留旧卡仍保留旧报告字段；同一epoch秒
解析的卡可得到同timestamp，不能用它单独认定唯一请求代际。完整曝光标识还依赖
track/ordinal/app状态，静态精度结论不代表已观察到运行时标识碰撞。


ListAction raw4的状态consumer0x101112a7c按tag族0x40/低位4跳到
0x101112c64，重新查state当前页分支；缺分支走空结果返回。命中后读取该ListState，
对其+0x40集合调用0x10111fc38（0x10111315c），helper对incoming aid作hash查找：
已有元素直接返回false（0x10111fcc8），缺失则copy-on-write插入
（0x10111fcf4），并写回集合；之后0x101110fd4存回页分支（0x10111318c）。
所以这一行“选中”事件是幂等添加aid，不是同一action切换选中/取消；取消选择走另一个publisher/action，见下段。此分支没有删除effect或请求ACK。


取消选择则由TableViewAdapter.tableView:didDeselectRowAtIndexPath:0x101107e9c
向deselectPublisher发送IndexPath（0x101107fa0），ListVC订阅安装
0x10111b218→0x10111f094→0x10111d1ac。只有live tableView允许多选才继续
（0x10111d1fc），重新读当前Store/current pageTab/items及row，取当前Item.aid
（0x10111d3c4），派发ListAction tag0x45（0x10111d3d8/0x10111d3f0）。
状态consumer低位5分支调用集合helper0x10111ff74（0x101112f68）：查aid缺失则返回
nil且不改集合（0x10112003c），命中copy-on-write并移除对应bucket
（0x101120028→0x1011211a8，count减1写入0x1011212f0），存回分支。
因此选中/取消分别为集合插入/移除，均不发送删除HTTP；删除仍由另述确认效果执行。


### Kotlin 翻译设置与 alwaysTranslate 派生状态

KntrTranslation真正export由classadapter0x1205b5858指向instance table
0x11ccf97b0：alwaysTranslateFlowIOSAsync→0x10be39c4c、alwaysTranslate→
0x10be39f20；static table0x11ccf97e0的translation/shared分别到
0x10be3992c/0x10be39abc。不是同名KotlinSelectorsHolder占位方法。
Bool adapter调用0x105c2fc5c→0x105c2fbd4，读取Translation.+0x40派生flow，
接口hash0x901 slot0取底层flow、hash0x406 slot0取boxedBool，并解包+8
（0x105c2fd28）。不能直接把alwaysTranslate等同用户开关值。

Translation singleton init0x105c2f148使用TypeInfo0x11b4c7490，global
0x120c5d8d8；namespace为translation、key为user-enabled，+0x20保存
SerializableSharedPreferencesProperty（TypeInfo0x11b3b6550）。构造0x1053e183c
后读取delegate0x1053e1d98（0x105c2f34c），初始Bool转MutableStateFlow
（0x105c2f370），保存userEnabled到+0x28（0x105c2f414）。该initializer未拼MID。
setter0x105c2f870读取+0x28当前Bool，同值直接返回（0x105c2f960）；不同才记录
Localization日志并用hash0x487 slot1更新flow（0x105c2fb98），不直接写+0x40。

userEnabled的apply1 collector TypeInfo0x11b4c75d0、table0x11be471a8→
0x105c30154→0x105c2ff5c；实际emit0x105c30264读取incomingBool与singleton.+0x20，
调用property setter0x1053e1fa0（0x105c30348）。后者序列化0x1053a680c
（0x1053e206c），将backing、key和serialized value交0x1053e2a2c
（0x1053e2070）。这闭合flow到存储property更新调用；最终native后端见下段，持久化完成
时序另证，不声称setter返回时已落盘。

alwaysTranslate初始值由0x105c31040计算（init0x105c2f424），apply2 collector
TypeInfo0x11b4c77d0/table0x11be47368→0x105c3063c→0x105c30744，收到
userEnabled后重算（0x105c307b8）并更新派生flow（0x105c3080c）。独立locale collector
0x105c30bfc也重算（0x105c30c68）并更新同flow（0x105c30cbc）。计算函数在缺省
参数时重新取Translation.userEnabled和Localization.current：userEnabled=false→false；
current等于Localization.SYSTEM→false；否则调用locale predicate0x105c1c2e0
（0x105c311e4），其配置匹配见下段。因此locale变化本身也可能更新派生Bool，
再影响此前VBPreferences订阅/LocaleCache，而非只有用户toggle产生变化。

UI侧共用setter0x10a49f6ec同时比较当前locale与userEnabled，仅两者都相等才跳过
（0x10a49f818）；不同则先调用Localization setter0x105c20e68
（0x10a49f848），再调用Translation.userEnabled setter0x105c2f870
（0x10a49f878）。两个具体closure0x10a4a66cc/0x10afc45d4已接到此helper，
UI注册、按钮label与完整设置页触发属Compose/UI装配，静态只能给候选closure，不把任意closure存在视作用户实际操作；下一步：query_index '*LanguageSettingsPage*' 30 枚举该页面装配函数后逐个反汇编确认调用0x10a49f6ec的入口。

外部清理边界已闭合（有界直接扫描）：userEnabled setter0x105c2f870的直接BL
调用方全量仅两处——Kotlin export thunk 0x105c30ffc（先经once 0x120c72000+0x828
初始化singleton，再取global 0x120c5d8d8调用）与上述UI helper 0x10a49f878；
未发现Logout/账号或配置观察者直接写userEnabled。suite级清除亦无：`translation`
namespace backing是NSUserDefaults initWithSuiteName实例，而
removePersistentDomainForName:（stub 0x1174d7ea0）在全__text的直接调用仅
UASDKStorage.deletePersistentObjectWithKey: 0x1167b4a5c，与该suite无关。
阳性对照：同两条find_callers命令对已证调用点（0x1002397a8/0x10a49f878）均命中。
残余：经全Kotlin共享property writer0x1053e2a2c（56个直接调用点，覆盖所有
SerializableSharedPreferencesProperty）按同suite其他key的写入、以及defaults
单key removeObjectForKey的动态路径不在本扫描范围。

海外guidance另有export classadapter0x1205cbc08/table0x11cd100a0，构造selector到
0x10bf248d4→0x105758f10（0x10bf24b94）；Swift0x102afa7d0传入title/pic/bullets/
tip/buttontexts/settingsURI/onDismiss。其onDismiss0x102afabac→0x102afaa0c只在
weak guidance有效时调用外部可选callback、dispose popper并置nil；完整body没有写上述
翻译设置。实际guidance按钮的Kotlin action继续另证。


### WatchLater 页面返回检查与列表重拉的边界

MainVC ObjC method table0x11f8dd9a8的viewWillAppear:0x101124bac、
viewWillDisappear:0x101124ec8、viewDidDisappear:0x101124edc共用helper
0x101124ef0：先调用super，再调用utility.isPopbackWithViewController:record:
（0x101124fc4），record raw分别1/4/8。此helper不派Store.refetch、未调用Account
getter/observer或请求cancel；super与页面外部账号处理仍另证。

viewDidAppear:0x101124e98→0x101124bc0的record raw2检查为true时进入
0x101124cb8，创建MainActor Task；async global0x12030b420首relative指针到
0x1011277ac→0x101125f44。Task调用utility.checkingWidgetStateFor:from:completionHandler:
（0x1011260cc），For raw1、from为main.later-watch.0.0.pv。callback0x101126358
将error交throw continuation、成功可选guide交resume。成功续体0x10112620c要求weak
MainVC有效，再写alertGuideModel（0x101126268）；错误续体0x1011262f8抛出，外部
Task错误处理为精确残余（async续体调用图需反汇编）：disassemble 0x1011262f8 0x1011263f0 核对抛出后的外层catch。此body不派列表action、不处理Account；widget引导完成并不等于
列表回执或换号重拉，账号通知是否关闭/重建外层页面继续保持未证。


### 独立 Kotlin Locale hook 的 Ktor 采用与覆盖门禁

这条来源是KLocale/GLocaleImpl/LocaleCache，TypeInfo分别0x11bb48190/
0x11bb480f0/0x11bb48410，initializer0x10aae8140/0x10aae910c写global
0x120c6cc80/0x120c6cc88。尚无它是Swift MetadataStore adapter的证据。
Root GInterceptor id58的成员getter0x10b9213fc读root+0x1d8，constructor
0x10b9324a8/0x10b9324b8装SwitchingProvider id67，branch0x10b93c71c→
0x10aae7184。id58在0x10b93c880/0x10b93c888解析该成员并加入此前已接
CommonParamsPlugin的18成员collection，仍受Enable GInterceptor=true门禁。

provider TypeInfo0x11bb47c50/table0x11c353bf8→0x10aae79dc创建Lambda
0x11bb47ef0→0x10aae7eb8，构造RequestHook名locale、callback0x11cb41dd0
（0x10aae7f6c→0x105d53940）。callback TypeInfo0x11bb482d0/table
0x11c354440→0x10aae9400；实际RequestHook chain callback执行0x105d53470，
返回request后继续chain（0x105d5356c）。Locale callback clone MutableRequest
（0x10aae9484），读KLocale经0x10aae85c8取得序列化String（0x10aae94d0），
以virtual+0x108写header x-bili-locale-bin（0x10aae94f8），不是URL参数。
沿已证toRequest$1/header setter0x10a9b285c，仅Enable header write once显式true且
原header已存在时保留；缺失/false则替换。不能把native无条件setValue规则套到此门禁。

serializer0x10aae86d0结果非nil时调用byte编码helper0x10528e34c
（0x10aae8688），nil则返回静态空String（0x10aae86a4）；callback写header前无
非空检查。编码helper准确变体/换行规则见后段；这里
空String fallback也不同于native Data nil遗漏。

独立binary producer TypeInfo0x11bb47e30→0x10aae7d1c创建0x11bb48230，
factory0x10aae92bc读原始bytes（0x10aae935c），nil→nil metadata，非nil创建
KBinaryMetadata0x11b4cd2e0并设置同header名与bytes（0x10aae93b8/0x10aae93bc）。
Root getter0x10b926814读+0x600，constructor装id195；六producer集合branch
0x10b93e5ac解析此成员并构造collection（0x10b93ed64）。该集合到GrpcEngine的具体注册见下段，不外推全部KMoss/stream请求。


Translation property最终backing也已接到NSUserDefaults：constructor0x1053e183c
用namespace translation调用0x1053e0058（0x1053e1904），后者将namespace存
native wrapper.+8，classref0x11f7b5c10确为NSUserDefaults，调用initWithSuiteName:
（0x1053e02f0），结果存wrapper.+0x10（0x1053e034c）；nil构造会trap。
writer0x1053e2a2c先经0x1053e20c0检查options，再对同wrapper defaults调用
setObject:forKey:（0x1053e2c10），key=user-enabled，object为此前序列化结果。
此具体namespace/key链没有MID成分；外部clear与实际落盘时序仍未证。

alwaysTranslate末predicate0x105c1c2e0经0x105c1c0fc读取配置key
 dd_localization_language_config（getter0x1053df890）；缺失/空String返回EmptyList
（0x105c1c1c0），非空JSON经serializer0x105315994与decode0x1053a6cac，
已检查的可接受decode异常也回退EmptyList（0x105c1c2d4）。predicate顺序遍历row，
跳过row.+8=nil，以当前NSLocale.localeIdentifier作exact比较（0x105c1c488），
第一个匹配返回row Bool byte+0x20（0x105c1c4b0），无匹配返回false
（0x105c1c4b8）。重复配置first wins，缺配置并非默认true；这是配置标识匹配，与此前
Localization.SYSTEM对象比较门禁不同。配置row准确JSON字段名见后段，未读取实际配置值。


binary集合的实际consumer也已闭合：上述六producer branch是id194，constructor
0x10b9369dc/0x10b9369e4存root+0x648，getter0x10b926d1c读该字段
（0x10b926d74）。其Locale首成员的id195 branch0x10b93ee40调用
0x10aae7714（0x10b93ee54）。CommonHeader注册branch分别读ASCII getter
0x10b92675c、binary getter0x10b926d1c（0x10b93e9dc），交0x10aa2a850
（0x10b93e9f0）；generated provider TypeInfo0x11bb2f070保存两collection
（0x10aa2a914）。hash584 getter0x10aa2b0e0创建wrapper0x11bb2f290，解析两个
getter后存wrapper.+0x10/+0x18（0x10aa2b244）。沿此前factory0x10aa2c178逐个
解析producer，实际CommonHeaderInterceptor binary loop0x10aa42570/0x10aa425a8
调用Locale producer，非nil metadata经GrpcMutableRequest virtual+0xc8
（0x10aa425cc）写MutableHeader.binary。由此证明该GrpcEngine common-header链
采用独立Kotlin Locale bytes；其他platform/Moss/stream engine路径需逐engine反汇编其common-header interceptor（有界扫描仅闭合GrpcEngine）。下一步：query_index '*MossCenterWrapper*' 30 定位Moss侧后同型核对binary header写入。
采用范围可先按构造点收窄（8.89 静态，identity-crypto 补）：`classRef_BAPIMetadataLocaleLocale`
0x11f7be570 全镜像仅 **1** 处引用（0x105060fec ∈ sub_105060F44，Locale 元数据构造器），
`classRef_KntrLocale` 0x11f7be588 仅 **2** 处（0x1050628a8/sub_1050627E4、0x105063710/sub_1050636E0），
native 侧注入由 `-[DeepBlueGRPCInterceptor …]` 的 `metadataInjector`（ivar 0x1204c28f0，
引用点 0x105064050→0x105064530）承担；因此"哪些 engine 实际带 Locale"不取决于构造点数量，
而取决于运行期 Gripper 对 `LocaleRegionService` 的绑定（flag0 单绑定 registrar 0x10008e098）与各引擎
interceptor chain，静态不可枚举；9.13 抓包比对同一请求在 Grpc/Ktor/stream 三条 transport 上的 metadata 是直接证法。


AiTranslateConfig的准确schema也已定位：token0x11c62bc80→0x11c62bc60→
0x11c62bc40/0x11c62bc20→0x11c62bc08，KClass TypeInfo0x11b4c3c90，serializer
0x11b4c3dd0的descriptor initializer0x105c1ac44声明四个optional key：
language_tag、support_ai_translate、ai_translate_title、ai_translate_sub_title。
deserializer0x105c1b2d4→0x105c1b960在缺字段时默认nil/false/nil/nil，对应
row.+8/+0x20 Bool/+0x10/+0x18。因此上述predicate取第一个language_tag与当前
localeIdentifier exact匹配项的support_ai_translate；首匹配缺Bool也为false，不继续找
后续重复true。这只解码schema/default，不读取实际配置row。


### HD2 follow配置来源与设置页提交触发

MainApi.modelDescriptions0x10df575e4明确/data/items为required NSDictionary array
（0x10df57634），/data/config为optional非array NSDictionary（0x10df5766c），
/data/config/auto_refresh_time为optional NSString（0x10df576a8）。成功callback
读取config（0x10df5915c）的follow_mode（0x10df59174），调用原VM.feedStateChange
（0x10df59354）。JSON键是follow_mode，本地manager属性才叫feed_mode；这些body不走
Moss RPC，服务端实验/决定发送字段的原因无法从客户端静态样本证明。
FeedStateListModel.modelContainerPropertyGenericClass0x10df06e44只映射
option→BBHD2PegasusFeedSettingModel（0x10df06e70/0x10df06e90）；SettingModel
value为qword（0x10df06f94），selected为byte（0x10df06fb4）。

FeedSettingVC.viewDidLoad0x10df076e0从shared.feed_mode.option浅复制数组
（0x10df077a0/0x10df077c0）；followState1且value1、或followState0/2且value0时才
置selected=true（0x10df07888），其他模型此初始化不清false，不能推唯一选中。
随后直接读suite的kBBHD2PegasusNeedFeedStateSetView（0x10df078e0），true才重新取
CURRENT feed_mode.option并setDataArray（0x10df07930），false不填此数组。
init0x10df07664设置disableAutoLoadData/disableAutoKVOObjects/disableShowingEmptyStatus
true；不从基类名称推它自动请求option或填默认列表。

真实tableView:didSelectRowAtIndexPath:0x10df07c84校验row<count，逐项selected=false
（0x10df07d5c），重读当前array/row并置选中项true（0x10df07dd4），reload后只写
selectedModel（0x10df07e00）。此回调不持久化followState、不请求。
viewDidDisappear0x10df07a20在selectedModel非nil时才提交：chosen.value1→state1；
value0且旧state1/2→state2；其他→state0，最后shared.setFollowState
（0x10df07b20）。读取旧state在消失时（0x10df07a8c），不捕获row点击时状态。

MainV2.bindVM0x10df3b564注册feedStateObseve0x10df3a138，KVO followState经
 distinctUntilChanged→skip1（0x10df3a22c/0x10df3a240），owned scoped disposable
（0x10df3a2cc）。callback0x10df3a49c先更新弱原VC显示；manager CURRENT state非0
且needFeedStateSetView=true才继续。state1另写CURRENT VC.viewModel.flush4
（0x10df3a4fc）；state1/2均写CURRENT VM.needReloadForFeedStateChange=true
（0x10df3a520），再scrollToTopAndRefreshData（0x10df3a530），不捕获旧VM。

该helper实际BaseCollection0x10dee8450先animated滚顶，再main dispatch_after0.3s
（0x10dee8510）；block强持原VC并延迟取它的collectionView，调用
bfc_triggerPullToRefresh（0x10dee8580）。MainV2 bind0x10df3aec4装handler
0x10df3b6e4（0x10df3af50）；具体collection override0x10deebf44仅尚无refreshview时
创建并装handler（0x10deebfd4），已有不替换。trigger0x115f5bf54先state1/startAnimating
再state2；setState0x115f5d410仅旧1→新2且handler非nil才调用
（0x115f5d4b4）。弱原VC有效时handler读取CURRENT VM→tryLoadData
（0x10df3b728/0x10df3b738），BaseVM0x10df02780先置tryLoaded，isLoading=true直接
返回，否则loadData（0x10df027bc）。设置commit/KVO不绕loading门禁、不取消在途请求，
也不保证立即新发送；下一次允许load才重新读当前followState形成recsys_mode。

物理TopView gesture安装0x10df4e0cc/0x10df4e0dc→action0x10df4e558，登录时路由
/main/feedsetting（0x10df4e598），未登录时Navigator.login（0x10df4e5bc）。但是HD2
FeedSettingVC注册0x10def14a8/0x10def14c0使用不同literal /pegasus/feedsetting；另一个
/main/feedsetting注册0x10f50afd8–0x10f50aff0的class是BBPhoneSetThemeViewController。
没有证到两URL别名/模块覆盖关系，故不能把TopView tap宣称已进入上述HD2设置页。
设置页row→消失提交→KVO→pull→tryLoadData链独立成立；TopView路由是否真到HD2设置页受运行期注册覆盖影响，静态有界扫描未见别名。下一步：query_index '*feedsetting*' 50 枚举全部注册点后 find_callers 0x10f50afd8 注册块复核覆盖关系。


HD2 idx的配置归属：BBHD2PhonePegasusConfig class0x1200420a8继承
BFCPreferences0x1202710f0；property table0x11df94b38中pegasusFeedIndex为Tq,D,N，
即动态Int64。configName0x10df8648c固定BBHD2PhonePegasusConfig；shared
0x10df863f0为once/global0x120c980d0，未按MID分实例。defaultConfig0x10df86498将
pegasusFeedIndex默认值写为String "0"（0x10df864f8/0x10df864fc），不是NSNumber0；
列数默认值另为NSNumber4（0x10df865cc）。沿此前通用BFCPreferences.userDefaults
0x1167d4ccc，configName→initWithSuiteName:（0x1167d4cfc/0x1167d4d14），可定位
固定suite；动态q getter/setter的IMP安装见后段，setter末端持久化已闭合为同步写NSUserDefaults（_setObjectWithKey 0x1167d34cc→setObject:forKey: 0x1167d357c，见team-g3证据）。

刷新idx只在CURRENT objects非空且FIRST为CardBaseModel时读取首idx
（0x10df58bcc）→MainApi.setIdx（0x10df58bd8）；空或首非base才dataDM.read
（0x10df58c04/0x10df58c10），不扫描第一个兼容模型。分页只在非空且LAST为base时
读末idx（0x10df5a69c/0x10df5a6a8）；空或末非base不fallback磁盘，也不setIdx。
MainApi.init0x10df56cd8只调用super并初始化helper，未证此case的最终默认idx值；
不将刷新 fallback误套到分页。save入口0x10df2b6ec与read入口0x10df2b72c分开。


### FallbackCache Native export 与 nil expiry 的静态实现边界

WatchLater所用Swift桥有具体提供者：once0x1208e4d80→0x102124ed4调用
KntrFallbackCacheModuleKt.provideFallbackCache（0x102124ef0），保存对象global
0x1208e4d88；读写都复用它。实际classadapter0x1205cac48/static table0x11cd0f7f0
把此selector接到0x10bf16a58→0x1089bf32c（0x10bf16b04）。后者解析注入provider
再调hash0x587 slot+0x10（0x1089bf458）；下述Root绑定已闭合，外部override仍有边界。
NativeKt classadapter0x1205cabd8/static table0x11cd0f760把writeAsync selector接
0x10bf162f8、readAsync接0x10bf15c7c。writer捕获cache/scene/id/data/version/expiry，
lambda TypeInfo0x11b8606f0/interface0x981→0x1089b7940，实际调cache的hash0x1d300
slot5（0x1089b79dc）。因此不是ObjC占位类的方法名证据。

该接口的已定位实现FallbackCacheImpl TypeInfo0x11b8614f0、interface table
0x11c100e50/witness0x11c100e20，slot5=0x1089bb458，读slot2=0x1089bb5ec。
writer wrapper取instance.+8 manager→0x1089bc61c→coroutine0x1089bc350→emit
TypeInfo0x11b861b10、hash0xc81→0x1089bdb2c→0x1089bd3b4。它构造
CacheMetadata0x11b860ef0：version来自参数，timestamp为当时epoch毫秒
（0x1089beee4；秒*1000加subsecond整除），expirationTime沿incoming Optional保留，
scene来自参数（0x1089bd86c/0x1089bd870）。没有把nil expiry换成600秒或其他TTL。
CacheMetadata serializer0x11b861030、descriptor initializer0x1089b948c的准确JSON
keys为version/timestamp/expirationTime/scene；timestamp与expirationTime optional，
version/scene required（0x1089b959c/0x1089b95b0/0x1089b95c4/0x1089b95d8）。

read wrapper0x1089bb5ec→0x1089bc74c→emit TypeInfo0x11b861db0/hash0xc81→
0x1089bdcd8。解析CacheEntry后取metadata.expirationTime：nil直接跳过年龄判定
（0x1089be140→0x1089be278）；非nil仅CURRENT epoch毫秒严格大于stored expiry才
进入失效分支（0x1089be150/0x1089be154），等于仍通过。失效时调用后端删除
（0x1089be164→0x105cd7044）并构造非成功结果；后端/取消完整实现另证。
跳过expiry后仍比较stored metadata.version与read请求version
（0x1089be280–0x1089be298），不匹配另走失败分支。因此WatchLater nil expiry在这个
具体实现没有自动年龄失效，但并非永久保证命中：版本、内容/解析与其他删除仍能使读失败。
还需保持注入实现/覆盖范围边界，未读取实际文件、缓存内容、账号key或运行时日期值。

读结果类型有具体TypeInfo名：Success0x11b861150、Miss0x11b8611f0、
Expired0x11b861290、VersionMismatch0x11b861330。过期分支删除后构造Expired，
携带原metadata（0x1089be22c/0x1089be270）；版本不匹配同样先删除该path
（0x1089be2cc–0x1089be2d8），再构造VersionMismatch，保存请求version与stored
metadata.version（0x1089be3a0/0x1089be3e0–0x1089be3ec）。版本匹配才调用传入
deserializer，input为CacheEntry.data（0x1089be29c/0x1089be2a0/0x1089be428），
返回Success保存解析data和原metadata（0x1089be43c/0x1089be480）。这些不是任意
非成功均自动重试的证明；WatchLater Swift消费者的旧缓存/错误回退另有自身门禁。

metadata反序列化0x1089b99a8还有独立默认规则：required mask0x9要求version与scene
（0x1089b9fcc–0x1089b9fd4）；timestamp缺失时调用CURRENT epoch毫秒helper
（0x1089b9fdc–0x1089b9fec），expirationTime缺失时存nil
（0x1089b9ff0–0x1089b9ff8）。这不会给缺失expiry补TTL；同时，缺失timestamp得到
解析时刻不代表文件新写入。写metadata与读metadata默认分别发生在不同环节。

read异常cleanup有额外类型门禁：exception TypeInfo.+0x5c的值落入raw
0x3e4–0x49e范围才进入已核Corrupted路径
（0x1089be504–0x1089be510/0x1089be6dc–0x1089be6e8），部分路径先删除当前file
（0x1089be520/0x1089be6f8），构造CacheResult.Corrupted TypeInfo0x11b8613d0并
保存exception（0x1089be790–0x1089be7a0）。范围外走rethrow
（0x1089be7a8），尚未将该raw类型范围命名为所有IO/解析/取消错误；不是所有异常
都会被吞成缓存miss，也不能仅由cleanup推断某次运行时文件已删除。下一步 = disassemble.py 0x1089be740 0x1089be7b0 把该 raw 类型范围逐类命名。

整体失效入口已闭合：Bridge还有导出方法`+[FallbackCacheOCBridge
clearAllWithCompletion:]`0x102127a34——Block_copy（0x102127a4c）后Swift包装
completion（0x102127a64），经通用suspend桥0x102126e18（0x102127a88）交Kotlin侧
closure0x102127cb4；该方法在__text无直接BL调用方，物理触发只经msgSend stub
0x117255660，其全量调用点唯一：0x10f2fff94，位于BBPhoneSettingMainVC清理缓存链
——cacheState==2门禁（0x10f2fff10/0x10f2fff14）→setCacheState:3
（0x10f2fff24）→enumerate datas并reloadClearCacheCell（0x10f2fff44/
0x10f2fff54）→BFCDDWrapper service getBoolForKey `pegasus_disk_cache_enable`
default false（0x10f2fff74–0x10f2fff80），true才以classref
0x11f7cd000+0xf80调用clearAll（0x10f2fff88/0x10f2fff94）；同链随后
bfc_clearImageCache（0x10f2fffa8）、BFCApiRequest cleanAllApiCache
（0x10f2fffb4）与URLCache removeAllCachedResponses。因此结果缓存的整体失效由
设置页“清理缓存”动作触发且被pegasus_disk_cache_enable门禁；本扫描未发现设备
属性事件、账号事件或其他观察者直接触发clearAll（阳性对照：find_callers对
0x117255660命中该唯一调用点，对其他已证目标命中多点）。clearAll进入Kotlin后的
目录/逐文件删除边界仍在0x102126e18包装之后，逐文件粒度另核。

### FallbackCache 的 Root 注册、文件后端与取消边界

export使用的key0x11c93d4d0有具体Root registration
（0x10b92bb3c–0x10b92bb48），provider来自Root.+0x458（0x10b92bacc）。
constructor0x10b934c00–0x10b934c08安装SwitchingProvider id139；跳表分支
0x10b93e9fc调用getter0x10b924a9c，实际读Root.+0x450（0x10b924af4），
经0x1089b80a4→scope hash0x1501 slot+0x10（0x1089b814c）解析其provider。
该field是id140经cache wrapper0x1053450c0构造
（0x10b934ba0–0x10b934bb0），分支0x10b93e298实际调用factory0x1089bef90
（0x10b93e2a8）构造此前FallbackCacheImpl和manager。故是实际注入路径，
不是由唯一conformance猜实现；运行时scope/override仍不从静态注册排除。

factory初始化files库0x105cd8520，manager.+8保存global0x120c5dfd8
（0x1089bf0ac），此global由SystemFileSystem$1 TypeInfo0x11b4e0a70构造
（0x105cd858c/0x105cd85c8）。lazy目录callback0x1089bd08c调用
NSSearchPathForDirectoriesInDomains，raw directory13/domain1/expand=true
（0x1089bd15c–0x1089bd168），取首Caches候选后join固定list_fallback_cache
（0x1089bd240）；候选空或类型不符另有fallback，不猜绝对沙盒路径。
path helper0x1089bcf90用regex `[^a-zA-Z0-9._-]` 将匹配字符替换为 `_`
（0x1089bd044/0x1089bd05c），scene与id分别处理，id追加 `.json`；write path
0x1089bd7e4–0x1089bd938，read镜像0x1089bde34–0x1089bded8。
schema为 `<Caches候选>/list_fallback_cache/<sanitized scene>/<sanitized id>.json`；
未读取实际path/key/文件。同名sanitize可能产生碰撞，不宣称哈希隔离或完整路径防护。

0x1089bc248只是lockScene coroutine：0x1089bbebc先锁manager.+0x20 Mutex
（0x1089bc038），查询scene map，缺失构造Mutex（0x1089bc11c）并存map
（0x1089bc174），解manager锁（0x1089bc1dc）后返回scene Mutex。
write emit拿该Mutex并lock（0x1089bd5ac），等待可suspend
（0x1089bd5fc→0x1089bd750）。继续后检查/创建scene目录；mkdir后端
0x105cd90c8→0x105cd946c。sink helper0x105cd71ac（0x1089bd69c）以append=false
dispatch到0x105cda87c，选`wb`并fopen（0x105cdaa14），包装FileSink
TypeInfo0x11b4e0c90；再buffer为RealSink、写JSON String、close
（0x1089bd6a4/0x1089bd6e0/0x1089bd6f0）。RealSink.close0x105cd30d4先把剩余
buffer交FileSink write，再尝试close，最终C调用为fwrite0x105cdc8b4、
fclose0x105cdccb0；正常close后scene unlock0x1089bd744。
异常cleanup另close/unlock/rethrow（0x1089bdad8/0x1089bdb20/0x1089bdb28）。
该body直接打开目标文件，未见temp-file rename；不是原子替换或fsync持久保证。

read source slot8（0x1089be0b4）到0x105cda17c→fopen0x105cda310，包装
FileSource TypeInfo0x11b4e0bf0。buffer/read String
（0x1089be0c0/0x1089be0d0），解析JSON前close（0x1089be0e4）；具体fread
0x105cdc4b0/fclose0x105cdc704。此前过期/版本失败的delete helper0x105cd7044
以mustExist=true调slot2（0x105cd7088/0x105cd708c），具体0x105cd8954→remove
（0x105cd8ab4），目录另rmdir。读取与写入的真实IO已闭，实际文件内容未检查。

write coroutine在0x1089bc4e4调用context-change0x1052b32fc→Job校验
0x1052bf420→0x1052bfda0；Job非active取取消异常并throw
（0x1052bfe8c–0x1052bfe9c）。context来自shared KCoroutineScope，不按用途猜
Dispatchers.IO。此检查可阻止进入block，scene Mutex等待另有suspend边界；
具体同步write/close段0x1089bd604–0x1089bd6f0及C FileSink没有Job检查或token参数，
不能推取消会中断fwrite或恢复被`wb`截断的目标。此前Swift/native handle cancel调用
与这些协程门禁分开记录；静态调用证据不证明运行时取消完成。


### Kotlin Locale 的编码与独立缓存更新

Kotlin Locale编码选择global0x120c5a928的Base64.Default（TypeInfo0x11b37c8b0）：
init0x10528dbec在0x10528dd44将urlSafe/MIME两个flag清0，padding取enum-array
0x120c5a918.+0x20，即PRESENT/ordinal0（0x10528e1e0/0x10528e1e4）。encoder
0x10528e520–0x10528e52c选普通64字符alphabet，静态比对匹配A–Z、a–z、0–9、+、/；
tail写 '='（0x10528e614/0x10528e9e8），MIME=false分支0x10528e620使用INT_MAX
chunk bound，不插MIME换行。故具体HTTP helper0x10aae8688是标准padded Base64、无
换行；没有选择另存Default.+0x28/+0x30的UrlSafe/Mime实例。nil仍为空String。

独立GLocaleImpl init0x10aae8140创建自己的LocaleCache0x11bb48410和
CachedLocaleData0x11bb485f0，两LocaleInfo0x11bb48690初始六空String/Boolfalse，
立即refresh0x10aae966c（0x10aae83dc）。refresh读取Localization.SYSTEM getter
0x105c20cd0（0x10aae971c）、current getter0x105c20de0（0x10aae9750）；export表
0x11ccf9558/0x11ccf9570确到adapter0x10be37f10/0x10be38098并调用同两getter。
两个native locale分别经languageCode/scriptCode/countryCode helper
0x105c331c0/0x105c333b0/0x105c335bc转三String；Translation getter0x105c2fc5c
（0x10aae978c）提供此前派生alwaysTranslate，保存到CachedLocaleData.+0x18。
所以缓存Bool不直接等于user-enabled，且不是从Swift MetadataStore对象取。

观察安装读取localeFlow0x105c20d58（0x10aae8454）和alwaysTranslateFlow
0x105c2fbd4（0x10aae8494），combine0x1052f6704→drop1 wrapper0x1052ef5f0
（TypeInfo0x11b38c570，literal count1写0x1052ef6a4）。callback TypeInfo
0x11bb48550/table0x11c354600→0x10aae9a0c忽略incoming tuple并重读上述全部来源
（0x10aae9a28/0x10aae9a2c）。refresh以stlr替换缓存对象（0x10aae990c），请求serializer
0x10aae86d0以ldar读取一个snapshot（0x10aae8760–0x10aae8770），再从该对象读取
两LocaleInfo与Bool（0x10aae87b0/0x10aae87b4）。实际UI setter使用相同Localization/
Translation上游，但setter返回与观察刷新先后、实际延迟仍未运行验证；不是每个请求
同步重新读取所有设置，两个缓存实现也不因此统一。


### HD2 idx 的动态 Int64 getter/setter 与重新启动读取

BFCPreferences.processAllProperties0x1167d3798对属性type q/raw0x71
（0x1167d3b24/0x1167d3b28）选getter0x1167d429c和setter0x1167d431c
（0x1167d3b88/0x1167d3b90），动态缺method时class_addMethod
（0x1167d3c8c/0x1167d3d14），selector-map保存具体property key。
getter经_defaultsKeyForSelector→RAM _getObjectWithKey（0x1167d42d4）→
longLongValue（0x1167d42f0）；setter经同映射→NSNumber.numberWithLongLong:
（0x1167d435c）→_setObjectWithKey:value（0x1167d4378）。所以idx默认String "0"
确被转为Int64 0，保存idx为NSNumber，经此前RAM/UserDefaults writer复用；不是猜key名。

init0x1167d36c8创建RAM dictionary（0x1167d3734）并process properties
（0x1167d3780）；每property先userDefaults.objectForKey（0x1167d3d30），非nil优先；
nil才取defaultConfig匹配key的value（0x1167d3d8c）。非isNilValue时存RAM
（0x1167d3dfc），origin标记disk2/default1。随后getter只读RAM，不逐请求重读磁盘。
由此闭合保存idx→新实例初始化读固定suite→刷新builder fallback读取的静态链；
落盘环节已闭合：动态q setter末端0x1167d4378交_setObjectWithKey:value:
0x1167d34cc，后者willChangeValueForKey（0x1167d3508）后持锁（self+0x28 lock，
0x1167d3510），同步写RAM self+0x18（0x1167d3540）与backup dict self+0x10
（0x1167d355c），并对self.userDefaults直接setObject:forKey:（0x1167d3564–
0x1167d357c）；value为nil的分支backup removeObjectForKey（0x1167d3588）并向
defaults写标记对象（0x1167d35a4–0x1167d35c4），didChangeValueForKey后返回
（0x1167d35e8）。即idx setter返回时该NSNumber已交NSUserDefaults（无显式
synchronize，依赖系统落盘策略）；外部进程更新与注销清除仍未运行验证，分页无
fallback分支仍保持区别。

### LanguageSettingsPage 的 Compose 生命周期提交

codegen有公开`bilibili://settings/language` route：URI array0x11cb99f80长度1，
element0x11cb99f90→KString0x11c871a20。collector TypeInfo0x11bbdf090/body0x10afc199c
复制array（0x10afc1a28），与static wrapper0x11cb99f98交registry hash18000 slot0
（0x10afc1ae8）。wrapper body0x10afc1b24返回DefaultFunctionWrapper，捕获
functionref0x11cb9a158，其body0x10afc1c08创建FunctionTarget
TypeInfo0x11b4c22b0，content取singleton0x120c6e8f0.+8（0x10afc1ca8），public name
LanguageSettingsPage（0x10afc1d6c）。content TypeInfo0x11bbdf3d0/body0x10afc2294
调用page0x10afc3e6c（0x10afc238c），再取singleton0x120c6e900.+8并经theme helper
0x1060a8bf8（0x10afc3ffc/0x10afc4018）到真实页面body0x10afc49d8。
这是route定义→target→render entry。实际collectRoutes binding也进入BRouterC：
DaggerSingletonC.BRouterCImpl.SwitchingProvider TypeInfo0x11bd18c90/body0x10b901e5c
读取raw ID（0x10b901ed0），table0x118652dd4 index33→0x10b902240，创建
Root_BRouterModule provider TypeInfo0x11bd1cfc0（0x10b90229c/0x10b9022d8），用
public key collectRoutes.7d76c4b2c1249142c1ac7c62036ddf0f981fa491（该 40 位 hex 是 Kotlin/Native binding 的签名/键散列，**不是凭据**；team-c30 复核点名要求加注）
（0x11cc67c80/0x10b903bac）注册binding（0x10b903b58/0x10b903ba8）。provider body
0x10b94be58 alloc实际Lambda TypeInfo0x11bbdf270（0x10b94bed4），resolve captured
provider并保存context.+0x10（0x10b94bf5c/0x10b94bf64）。Lambda init0x10afc1e84
构造registry（0x10afc1f58/0x10afc1f5c）；get0x10afc1f94要求.+0x18非nil
（0x10afc202c），才registry hash782 slot4→hash10780 slot0执行static collector
0x11cb99f78（0x10afc2090/0x10afc20ec/0x10afc20fc）。不能只凭binding注册当已执行。

BRouterC constructor真实provider rawID33保存component.+0x120
（0x10b8eb53c/0x10b8eb540/0x10b8eb54c），getter0x10b901ab0读取该字段
（0x10b901b08），实际map assembly将其与同public key配对
（0x10b9046a8/0x10b9046bc）。外层BRouterCBuilder TypeInfo0x11bd162b0的build
0x10b8ea290 alloc该component并存parent/self（0x10b8ea30c/0x10b8ea34c）。Builder来自
SingletonC rawID122/table0x118652f3a index22分支0x10b93e990
（0x10b93e9a0/0x10b93e9a8），provider保存root.+0x3c0（0x10b934368/0x10b934370），
getter0x10b923fd4实际传入BRouterCore createBRouter provider TypeInfo0x11b4bd140
（0x10b93e7b8/0x10b93e7dc/0x105bef274）。生成provider工厂0x105bef1b0的
incoming x1 builderprovider保存在+8，incoming x0 context在+0x10
（0x105bef1d4/0x105bef1d8/0x105bef274），不把context槽误写为builder。
生成provider0x105bef790构造实际BRouterCoreKt_createBRouter_Lambda
TypeInfo0x11b4bcfc0（0x105bef80c），保存resolved builderprovider+0x10
（0x105bef950）。具体get0x105bee90c读此provider（0x105bee988），hash0x584
slot0取得实际Builder（0x105bee9d0/0x105beea08），捕获在coroutine
TypeInfo0x11b4bd300+0x20（0x105beee34）。coroutine0x105befa60取Builder
（0x105bf038c），hash0xfe00 slot0（0x105bf03d0）；实际Builder TypeInfo0x11bd162b0
itable0x11c5089d0的同hash→funcarray0x11c5089c0→上述build0x10b8ea290，
所以createBRouter静态路径确实构造含语言ID33 binding的BRouterC。
get自身要求lambda+0x30非nil（0x105beed5c），nil throw（0x105beeeac），
init0x105bee388必须先行；具体binding的init/get排序见后段，导航完成仍另核。

build返回交helper0x105345b94（0x105bf03dc），该helper以KClass0x11c52f4e0
→BaseGripperFetcher TypeInfo0x11b39c650求值（0x1053478e8/0x105345c04），
hash0x702 slot0（0x105345c58）。actual BRouterC TypeInfo0x11bd18bf0
itable0x11c50b710、entry0x11c50b730→funcarray0x11c50b708→0x10b901c20，
取component getter0x10b9002f8（0x10b901c88）再provider hash0x584
（0x10b901cdc）。这一步是取得Fetcher，不把helper当作已经执行所有route collector。
该getter读component+0x18（0x10b900350/0x10b900398）的SwitchingProvider ID0。
其branch构造34项Pair map（count34：0x10b9041d4/0x10b9041d8），语言Pair
（0x10b9046bc/0x10b9046c0）放element32（0x10b9047a8），map factory
0x1052838c8（0x10b9047b8）。对应34项TriggerBean list含同语言element32
（0x10b905d10），TypeInfo0x11b39cfd0公开类型名TriggerBean；该bean+8静态key
0x11c62adc0为CollectRoutes，+0x10为语言bindingprovider（0x10b905b94），
+0x18 rawflag1（0x10b905b88），不由名称推运行。list factory0x10522e81c
（0x10b905d24）。Fetcher factory receiver hash0x2a00 slot2（0x10b905dd8）
实际收到map x3/list x4（0x10b905db8/0x10b905dd0），组件类型KClass
0x11c6295a8→BRouterComponent TypeInfo0x11b4b9920。已闭具体collection成员与
工厂输入；其后具体执行链见下段，不等同已发生运行时导航。

createBRouter coroutine的hash0x4181 slot3 receiver是BRouteCentral
（interface TypeInfo 0x11b4c0200，0x105bf04d0/0x105bf04dc），不是ConfigurationImpl。
BRouterCore TypeInfo 0x11b4bd3c0保存central/configuration/BaseFetcher
（0x105bf0430/0x105bf046c/0x105bf0470）；DefaultRouteCentral TypeInfo
0x11b4c0280同hash slot3→0x105c04774，将Core存.+0x18（0x105c047e8），
lambda 0x11b4c0a40→0x105c0a168→coroutine 0x105c0998c读取Core.+0x18
（0x105c09a8c..0x105c09a94），以literal CollectRoutes调用Fetcher hash0x2500 slot3
（0x105c09ae4/0x105c09af4）。实际DefaultGripper 0x11bd12ff0→0x10b8d9d00
→TriggerExecutor.execute 0x10b8e43dc（0x10b8d9f08）→coroutine 0x10b8e3c7c。
它逐TriggerBean取provider（0x10b8e41a8），调用producer hash0x587 slot1
（0x10b8e4200），nil跳过（0x10b8e4208）；要求返回对象hash0x2c00，bean rawflag1
时再调用该接口并收集（0x10b8e4230..0x10b8e4260/0x10b8e4008/0x10b8e4028）。
语言bean已证raw1；后续0x1052b25dc/0x10b8db878（0x10b8e42b8/0x10b8e4320）
的跨binding等待语义仍另核，不称所有binding严格逐一完成。

语言binding的缓存wrapper不能省略：DSL tail经builder hash0x603 slot0
（0x10b9068bc）→0x10b8d78dc置byte+0x41=1（0x10b8d78ec）；finalizer
0x10b8d7a5c创建ContextProcessingProducer 0x11bd13830，其WrappedProducer
0x11bd12370捕获generated provider（0x10b8d7b94）。缓存分支包入
DefaultCacheableProducerNew 0x11bd14470，FunctionWithSubscribers 0x11bd145b0
保存function（0x10b8d7c8c），atomic reference保存wrapper.+8
（0x10b8d7c94/0x10b8d7c98），最终StaticSuspendProducer 0x11bd14310.+0x38
（0x10b8d7d84）。async方法0x10b8dc5ec→0x10b8dc90c→virtual+0xb0
（0x10b8dc948）→0x10b8dfdd8取.+0x38并调用hash0x405（0x10b8dfe4c）。
缓存invoke 0x10b8e0368读atomic state（0x10b8e063c..0x10b8e0648）；function-state
分支取function（0x10b8e0688）→0x1052157e8（0x10b8e07ec），该helper创建stack
adapter 0x11b36c6f0，保存function（0x105215860）并直接调用0x105216290
（0x10521589c）→captured function hash0x405（0x105216304）。
因此该分支接到ContextProcessingProducer 0x10b8dd1c0→coroutine 0x10b8dc978；
无context override路径取WrappedProducer（0x10b8dcc3c）并invoke
（0x10b8dcd74），其body 0x10b8d7dc8 resolve generated provider
（0x10b8d7e78）并调用语言Lambda hash0x405（0x10b8d7ed4）。其他atomic状态复用、
成功CAS及异常恢复分支需完整反汇编atomic状态机（0x10b8e0368起），不称每次CollectRoutes都会fresh注册；下一步：disassemble 0x10b8e0368 0x10b8e0d00 逐分支核对CAS与异常路径。

实际语言Lambda 0x11bbdf270 invoke 0x1053466ec先virtual+0x98 clone
（0x105346770），具体0x10afc1da8分配同TypeInfo并只复制context.+0x10
（0x10afc1e18/0x10afc1e50/0x10afc1e54）。ProducerBase coroutine 0x105346840
依次调用clone virtual+0xb0 init（0x105346a58→0x10afc1e84）和+0xa8 get
（0x105346bf8→0x10afc1f94）；init存registry dependency.+0x18
（0x10afc1f5c），get要求非nil（0x10afc202c），通过registry hash0x10780调用
static collector 0x11cb99f78（0x10afc20fc）。collector 0x10afc199c最终route注册
hash0x18000 slot0（0x10afc1ae8）。首次函数执行的init-before-get及静态注册链已闭，
导航完成、通用竞争注册/替换和缓存后续状态仍是独立边界。

顶层BRouter get的具体冷/热调用也已闭。SingletonC ID121写入及cached provider存
root.+0x3d0（0x10b934470/0x10b934474/0x10b93447c/0x10b934480），getter 0x10b924144。
factory 0x105bef1b0通过builder cache slot0→0x10b8d78dc
（0x105bef37c）明确设置cacheflag，再finalize（0x105bef490）；其trigger slot4参数
0x11c356e70为empty String（0x105bef3dc），不能命名启动trigger。
SingletonC实际BRouter.EntryPoint interface 0x11b4b9aa0/hash0x488实现
0x10b929388调用root getter/provider/producer hash0x587 slot2
（0x10b9293f8/0x10b929450/0x10b9294a8）。具体StaticSuspendProducer slot2
0x10b8dc0ec先virtual+0xa0（0x10b8dc168）→0x10b8dffb0→cacheable hash0x2283 slot0
0x10b8e01a8，检测atomic state是否ValueHolder TypeInfo 0x11bd14510/hash0x155fa
（0x10b8e01fc..0x10b8e022c）。true走virtual+0xc0（0x10b8dc188）→0x10b8e00a4
→cacheable slot1 0x10b8e0278，返回已保存state.+8（0x10b8e0304），不新运行collector。
false取context（0x10b8dc1dc），创建AbstractSuspendProducer$get$1 0x11bd13650
（0x10b8dc288），捕获原producer（0x10b8dc2c4）→0x10b8e4940（0x10b8dc2d0）
→0x1053086e8（0x10b8e4ad4）。后者创建BlockingCoroutine 0x11b3917e0
（0x105308974），启动该lambda（0x105308b90），处理/等待state及mutex
（0x105308c4c/0x105308c6c/0x105308d00）。lambda 0x10b8dc838读原producer并调
virtual+0xb0（0x10b8dc85c/0x10b8dc874）→上述冷函数执行链，所以slot2不只是返回
未执行provider；等待线程策略、其他atomic状态与异常恢复仍另核。
正常函数返回的cache writer也有实证：0x10b8e0368把结果与singleton
0x120c5a8e8.+0x10比较（0x10b8e0798/0x10b8e07b4），相等绕过写入；非相等或nil
交0x10b8e0bfc（0x10b8e07bc/0x10b8e0830/0x10b8e0834）。writer分配同ValueHolder
0x11bd14510（0x10b8e0c88），把结果存.+8（0x10b8e0cc4），调用0x1052ae97c
（0x10b8e0cd0）以ldaxr/stlxr更新atomic state（0x1052aea44/0x1052aea50）。
所以ValueHolder存在不保证payload非nil；此正常返回写入不覆盖悬挂完成、异常或reset策略。
CollectRoutes实际产物亦持久存入central：0x105c0998c校验RouteCollectorImpl
0x11b4c0570（0x105c09be0/0x105c09be8），创建FinalRouterTable 0x11b4c04a0
（0x105c09c24），存central.+0x20（0x105c0a0cc）。central hash0x4181 slot2
0x105c062c4→0x105c0400c读取该字段，nil抛错（0x105c040b8）。**该 slot 已复核（team-c33）**：
0x105c0400c 实现体（0x105c0400c–0x105c04094）只做 `ldr x8,[x19,#0x20]`（central+0x20＝FinalRouterTable，
写点 0x105c0a0cc）→ `cbz x8,0x105c040b8` → 非 nil 直接 `ret`，**没有任何清空/置 nil 分支**；
0x105c040b8 是 `adrp 0x11c62a000; add #0xc70; bl sub_1052299B0`（Swift 报错/元数据 0x11c62ac70），
0x105c04098 的旁路 `sub_10BFAFD38`（0x105c040a0）是 once 槽 0x120c842a8 未命中的首次初始化，
不是 cache 清空。`find_callers 0x10b8e0bfc` 全镜像只回 **2** 处且都在同一冷函数体内
（0x10b8e0834 即 0x10b8e0830 的调用、0x10b8e0f88），即 0x10b8e0368 起的 cache writer 路径
（ValueHolder 0x11bd14510、atomic state ldaxr/stlxr 0x1052ae97c）⇒ **无账号/登出调用边**；
0x105c0400c 的 4 个调用点（0x105c04508/0x105c04e48/0x105c062e4/0x105c06308）同属该 RouterTable 读取族。
残余：泛型 witness 的清理对象类型与账号变化触发 reset 仍不可判（静态无写者）——下一步反汇编上述
4 个调用点所在冷函数体找「替换/置 nil」路径，运行期断点 0x105c0a0cc 与 0x10b8e0834 观察是否被重写。
实际KRouter$2 TypeInfo 0x11b4c17d0/body 0x105c0e178 resolve BRouter.EntryPoint
KClass 0x11c62b1a8（0x105c0e1f0）并调用hash0x488（0x105c0e244）。lazy initializer
0x105c0e020以static function 0x11c62b1b8构造lazy、保存global 0x120c5d740
（0x105c0e080/0x105c0e090），getter 0x105c0e0b8经once 0x120c726c8及lazy hash0x901
（0x105c0e0dc..0x105c0e0f8/0x105c0e148）取值。既有Guidance URI dispatch
0x105c0cce8路径调用该getter（0x105c0cd64），可迫使冷BRouter初始化并注册语言路由。
另一个实际caller 0x10692601c属Compose container构造callback 0x11b622290：
创建IosComposeContainerViewModel 0x11b620610（0x106925fac），取KRouter后URI处理
（0x106926050/0x106926058）→BRouter dispatcher hash0xfe80 slot4（0x106926114）。
具体URI来源/是否language、运行时导航完成和app启动时点均不由这些静态调用证明。

页面实际collect Localization.localeFlow（0x10afc4b40/0x10afc4b50）与Translation.+0x38
lazy flow（0x10afc4b8c/0x10afc4c18）。remember为空才用collected locale创建mutable state
（0x10afc4d1c/0x10afc4d28），Bool同样取collected value后box并remember
（0x10afc4e6c/0x10afc4e88/0x10afc4e90）；已有holder分支不自动覆盖编辑值。
该lazy producer0x105c30d00实际来自Translation$2 TypeInfo0x11b4c7bd0，读取singleton.
+0x28 userEnabled flow（0x105c30d8c），返回readonly wrapper（0x105c30d94）；页面初始
Bool来源因此是userEnabled，不能混作derived alwaysTranslate.+0x40。
Locale callback TypeInfo0x11bbe0050捕获holder（0x10afc5c74），传AppLanguageSettings
0x10afc5fe8（0x10afc5cd0/0x10afc5cdc）；实际invoke0x10afc4600只将incoming Locale
写captured holder hashb82 slot1（0x10afc466c/0x10afc46b4），没有立即调用全局writer。
随后事件`main.setting-language.option.0.click`（0x11cb9aaf0/0x10afc4788），单字段
text来自incoming Locale的native localeIdentifier（0x10afc46f8），不是已提交CURRENT值。

真实候选行callback TypeInfo0x11bbe0230捕获optional onSelect functionref及row Locale
（0x10afc6ea4），作为modifier callback交0x105819084（0x10afc6f0c/0x10afc6f10）。
其body0x10afcc3e4读functionref.+8，nil跳过，非nil hash981 slot0传captured row Locale
（0x10afcc450/0x10afcc454/0x10afcc45c/0x10afcc460/0x10afcc498/0x10afcc4ac），闭合到
上述local edit callback；候选列表来自已知固定七locale（0x10afc6a88），行Locale以virtual+0x80与incoming selected Locale比较
（0x10afc6d4c/0x10afc6d54/0x10afc6d58），enabled=比较结果XOR1
（0x10afc6ef0）；故已选行在此click modifier disabled。不把recomposition callback
0x10afcc4e8当onClick。
Bool callback TypeInfo0x11bbe00f0捕获另holder（0x10afc5e24），传AiTranslationSettings
0x10afc7be4（0x10afc5e84/0x10afc5e90）；invoke0x10afc47c4 box incoming Bool并写holder
（0x10afc4868/0x10afc48b4），也不立即写Translation全局。其同名点击事件
（0x10afc4990）单字段always_translate_switch按incoming非零→String1、零→0
（0x10afc4910/0x10afc4920/0x10afc4964）；这报告用户编辑值，不能当派生effective状态。
实际switch绑定已闭：AiTranslation helper0x10afcaa24将onChange装入Ref
（0x10afcab44），调用SimpleSwitch0x10afcc124→0x106c77a10，x1为该callback、w0为
页面当前Bool（0x10afcc0e8/0x10afcc110）。其具体callback TypeInfo0x11b658f80捕获
onChange与rendered Bool（0x106c789a4/0x106c789e4/0x106c789ec），以modifier callback
交0x1058191ec（0x106c78a58）。实际click body0x106c79b38要求callback非nil
（0x106c79ba4/0x106c79ba8），计算BIC(1,capturedBool)
（0x106c79bac/0x106c79bb4），box后hash981 slot0转发（0x106c79bbc/0x106c79c0c）；
页面forwarder0x10afcc5d4经optional Ref提取/再box/调用
（0x10afcc604/0x10afcc648/0x10afcc654/0x10afcc660/0x10afcc6b0）到0x10afc47c4。
这条实际控件action先反转rendered值，再写页面holder，仍需下述cleanup才提交全局。

compose0x10afc4f74创建并remember捕获两个可编辑state holder的callback，
以Unit key交0x1054378bc（0x10afc501c），构造DisposableEffectImpl
TypeInfo0x11b3bdc40。RememberObserver table0x11bd63438/hash0x1901的slot2
0x105439674调用effect（0x10543975c），保留cleanup到+0x10；effect callback
0x10afc447c创建cleanup0x11bbdffb0并复制两个holder。slot1 0x1054397a4在cleanup
非nil时调用其hash0x4680→0x10afc4558（0x10543984c）再清nil，slot0
0x105439888不执行cleanup。这是effect离开composition的提交，不据此推某具体按钮
独占写入或精确iOS导航/消失时序。
cleanup读取holder CURRENT locale（0x10afc42f0）与Bool（0x10afc4394），交此前
common setter0x10a49f6ec（0x10afc45d4）；捕获的是可变holder，不是初始值快照，
且Unit key不随locale/Bool值本身重新key effect。same-value门禁仍有效。

既有用户翻译guidance另有真实Button writer：构造0x10a4a4ee0创建callback
TypeInfo0x11bab9dc0并remember（0x10a4a4f78），将其与content交Material3 Button
helper0x1059ef600（0x10a4a5020），helper内TypeInfo0x11b490280/0x11b4903c0
对应Button$2/$3。callback0x10a4a65bc先报告
main.homepage.translation-popup-olduser.translation.click（0x10a4a6670），再读fresh
Localization.SYSTEM经0x105c20cd0→0x105c1ea9c与captured Bool holder当前值
（0x10a4a66b4/0x10a4a66c0），调用common setter（0x10a4a66cc），再调用关闭callback
（0x10a4a671c）。不是无条件写true，也不同于Swift guidance.onDismiss的无writer分支。
content外层label与config来源由下述schema/map链定位，事件名不替代可见label证据。

实际提交用的captured Bool holder有独立初始化/编辑链：outer.+0x40 holder来自
0x105460c00（0x10a4a0894），初值为静态boxed Bool true
（0x11cd1e280.+8），不读Translation.userEnabled。Column$3 callback
TypeInfo0x11bab9be0捕获同holder（0x10a4a3878），经modifier callback安装
（0x10a4a38e4→0x105819084）。invoke0x10a4a6044读当前Bool、XOR1并写回holder
（0x10a4a6070/0x10a4a60b0/0x10a4a6104），只改变本地编辑state；draw读取同holder，
最后translationButton callback0x10a4a66c0读取当前值后common writer才进入持久链。
用于config A/B选择的outer.+0x38是另一个默认true holder，不能混作翻译开关值。

guidance内部两config对象的schema已定位为ExistingUserGuidanceData
TypeInfo0x11baba0e0，serializer0x11baba180。descriptor init0x10a4a6f94–0x10a4a705c
列9字段：title、desc、tip、iconUrl、confirmButtonText、cancelButtonText、
gotoSettingsText、gotoSettingsUri为required；langChineseName optional。
deserialize0x10a4a7570以required mask0xff校验（0x10a4a7f88–0x10a4a7f94），
前8依次写+8/+0x10/+0x18/+0x20/+0x28/+0x30/+0x38/+0x40
（0x10a4a7f98–0x10a4a7fa4），第9缺失存nil到+0x48。
ExistingUserGuidance$1捕获derived config state；invoke0x10a4a174c按当前Bool state
选configA或configB。Button content0x10a4a6754取选中config.+0x28
（0x10a4a685c）交Text，故实际label为confirmButtonText。另一settings callback
0x10a4a6b84读config.+0x40→0x105bd1508→0x105c0cce8，然后关闭guidance
（0x10a4a6bf8），未见Translation writer。helper0x105bd1508构造StringUri
TypeInfo0x11b4b8620（0x105bdae24），再0x105c0cce8经0x105c0e0b8/
0x105be8440/0x105be9764到BRouter dispatcher hash0xfe80 slot4（0x105c0ce50）。
这是路由派发；provider/target由BRouter运行期容器解析，成功回执静态不可定，callback未检查派发结果便关闭。下一步：反汇编dispatcher hash0xfe80 slot4 0x105c0ce50 下游核对目标解析。
两config外层来源继续核对；下述locale-keyed map链不把export位置参数直接套入内部schema。

两config的实际上游是远程配置key `dd_localization_existing_user_guidance`
（0x11cad07b0）。getter0x10a4a8e08→0x1053df890（0x10a4a8ec8），以token链指定
Map<String,ExistingUserGuidanceData>，decode0x1053a6cac（0x10a4a8f20）；缺失/blank
退EmptyMap；decode exception处理在decoder通用层，需反汇编0x1053a6cac全函数归类（下一步：disassemble 0x1053a6cac 0x1053a7000）。Native builder的A取map中的localeA
localeIdentifier键（0x10a4aff48；key helper0x10a4a8b50）；B则取fresh
Localization.current的localeIdentifier（0x10a4afff8/0x10a4b0070）。要求A/B均非nil
（0x10a4b06a8/0x10a4b06ac），把两对象存render closure.+8/+0x10
（0x10a4b0858），callback0x10a4af664→ExistingUserGuidance调用0x10a4af980。
因此pair来源是按locale查map；localeA准确来源由后述lazy list闭合。B.langChineseName在render
前被写入（0x10a4b068c），这些config对象不能一概称为immutable快照。

map decode的catch只在raw TypeInfo.+0x5c减0x3e4后小于0xbb时记录日志并退EmptyMap
（0x10a4a8fec/0x10a4a8ff4），其他异常rethrow（0x10a4a9004），不称全异常容错。
A helper0x10a4a8b50遍历Localization.+0x10 lazy list（0x105c20c48），首个candidate
以virtual+0x80 equals fresh SYSTEM（0x105c20cd0→0x105c1ea9c）成立便返回；
无匹配退Localization.+8 lazy getter（0x105c20bc0，0x10a4a8db0）。list和fallback
公共名称及其producer另沿lazy初始化核对；B的current getter
0x105c20de0仍与SYSTEM 0x105c20cd0分开。

fallback lazy0x105c211d0→Locale.Companion getter0x105c1c990，实际读Companion.+0x10
（0x105c1c9ac）对应lazy0x105c1cfc4、公开固定tag `zh-Hans-CN`
（0x11c62bd70）。不要误套相邻.+8的zh-CN producer0x105c1cee0。
list lazy0x105c212a0构造7项（0x105c214b8/0x105c214c4–0x105c214d0），依次getter
0x105c1c990/0x105c1ca18/0x105c1caa0/0x105c1cb28/0x105c1cbb0/0x105c1cd48/
0x105c1cdd0分别读Companion.+0x10/+0x18/+0x20/+0x40/+0x48/+0x60/+0x68，
对应zh-Hans-CN、zh-Hant-HK、en、ja、es、pt、ar。故A是该固定候选list中首个等于
concrete SYSTEM的Locale，无匹配退zh-Hans-CN，B仍是当前用户所选current。

SYSTEM本身另有具体lazy producer：Localization.+0x18 lazy由function object
0x11c62c130/TypeInfo0x11b4c4eb0接0x105c21528，getter0x105c20cd0；不是七项
候选列表或直接取current。producer取得standardUserDefaults（0x105c2164c），以
公开key `AppleLanguages` objectForKey（0x105c217dc）保存旧对象，再
removeObjectForKey（0x105c21a00）。随后resolve cached service0x120c5d8c0并
调用hash0x11180 slot0（0x105c21b48），以raw index0交0x105c1ff7c
（0x105c21b54/0x105c21b58）；此helper仅取返回wrapper.+8的get(index)，
没有已证空数组fallback。旧对象非nil才在正常返回路径setObject:forKey恢复
（0x105c21db0）；旧对象nil跳过恢复（0x105c21b6c→0x105c21dec）。异常/finally
恢复需核对函数尾部landing pad/defer路径才能称always restore；下一步：disassemble 0x105c21528 0x105c21e00 检查异常表。这里只分析静态body，未执行或读取真实defaults。

该service initializer0x105c2ebb8直接分配createPlatformLocaleDelegate$1
TypeInfo0x11b4c7f90；itable0x11be47950的hash0x11180接0x105c339b8。实现对
NSLocale调用preferredLanguages（0x105c33afc），按原iterator顺序逐tag构造
NSLocale.initWithLocaleIdentifier（0x105c33dfc），转Locale wrapper
（0x105c33e64）并append（0x105c33e70–0x105c33e7c），最终列表放wrapper.+8
（0x105c33ee0）。因此这里SYSTEM取临时移除覆盖之后的首preferred language，
七项匹配/回退是之后guidance helperA的独立步骤。restore后的0x105c32784
已查前段为UIView.appearance.setSemanticContentAttribute raw3
（0x105c32870/0x105c32960），后续UINavigationBar appearance；不是已证Locale
observer刷新。SYSTEM lazy的外部reset为静态可查残余：query_index '*Localization*' 50 枚举该模块全部入口后 find_callers 写0x105c20cd0对应global的调用方；OS语言变化通知属系统运行期，需真机验证。

Localization.current的存储及回流另已闭：initializer0x105c2042c以namespace
`localization`、key `custom-locale`（0x11c62c0c0/0x11c62c0f0）构造
SerializableSharedPreferencesProperty（0x105c20638），保留到.+0x30/+0x38；
共同backing constructor0x1053e0058使用NSUserDefaults.initWithSuiteName。
这段构造不加入MID，不能据此否定其他账户清理writer。启动缓存byte0x120c5a4e1
来自initializer0x105c31e74读取UIDevice.userInterfaceIdiom，计算raw!=1
（0x105c320e8/0x105c32120/0x105c32124/0x105c32138）。byte==1时current初始
读property→MutableStateFlow（0x105c2068c/0x105c20698），否则取上述fallback
getter（0x105c206b8），flow存.+0x40（0x105c20784）。未读取真实偏好值。

current setter0x105c20e68首先要求该缓存byte==1（0x105c20f4c/0x105c20f50），
再以Locale.equals比较incoming与flow当前值，同值返回（0x105c20fbc/0x105c20fc0）。
变化才写flow hash0x487 slot1并调用platform apply0x105c322cc
（0x105c211a0/0x105c211a8）。后者取incoming localeIdentifier
（0x105c324c4），向standardUserDefaults.AppleLanguages写单元素数组
（0x105c324e4–0x105c324f4、0x105c325e0），再调用appearance helper
（0x105c32614）。这是标准defaults的语言覆盖，另有suite中的序列化存储；
这些body没有替换.+0x18 SYSTEM lazy。启动对旧zh-CN匹配时转zh-Hans-CN
并经同一setter（0x105c207e4/0x105c208dc/0x105c208e8），迁移仍受此门禁；
其他分支直接应用当前Locale（0x105c20870）。

current flow的apply collector TypeInfo0x11b4c4ff0接emit0x105c22e5c，取fresh
singleton.+0x38（0x105c22ef4），交共同writer0x1053e1fa0（0x105c22f24），
再0x1053e2a2c到native setObject:forKey；不宣称同步落盘。反向collector
Localization$6/0x105c23054取.+0x30.property.asFlow（0x105c230c0/0x105c230c8），
以consumer TypeInfo0x11b4c5330→0x105c23110接收，旧zh-CN替换zh-Hans-CN
（0x105c231b8/0x105c2320c），调用同一setter（0x105c2324c）。同值比较阻止
相同Locale反复写flow，未见该callback的generation/account检查。

propertyflow0x1053e1a44→0x1053e05b0→SharedPreferences$asFlow$1
TypeInfo0x11b3b62d0/body0x1053e0718，给backing.+0x10注册
addObserver:forKeyPath:options:context（0x1053e0c44，raw options3/context nil）。
listener TypeInfo0x11b3b6370/body0x1053e0dd4 reload当前value
（0x1053e25d4，call0x1053e10a4），交captured producer hash0x407 slot6
（0x1053e1108）；awaitClose注册cleanup（0x1053e0ce4），cleanup0x1053e1188
removeObserver:forKeyPath（0x1053e15d0）。这条观察suite localization/custom-locale，
不是已证SYSTEM/AppleLanguages的OS语言变化通知；具体ObjC KVO adapter仍可另核。

KntrLocalization实际adapter0x1205b5548的instance exports表0x11ccf9540仅四项
localeFlowIOSAsync/SYSTEM/current/setCurrent:；该表未导出SYSTEM setter/reset。
current setter另外两组大量调用分别来自NumberFormat preview callback
0x107d52930→0x107d585f0（TypeInfo0x11b77be60、vector0x11c060500）及
DateTimeFormat preview callback0x107d55890→0x107d2266c（TypeInfo0x11b77c720、
vector0x11c060d18），package均kntr.base.localization.preview。其生产UI可达性
未证，不能当账户/配置监听writer。以上有界body未替换SYSTEM lazy，仍不宣称
全应用没有间接reset、OS通知或账户触发路径。

公共query另有实时Locale producer，与binary LocaleCache分开。TypeInfo
0x11bb42390的provideCLocaleGNetPublicParam$1/function object0x11cb3ed70接
0x10aac4474，每次读取fresh Localization.current、Locale String getter
（0x10aac4518/0x10aac4520→0x105c1ded4），以公开key c_locale
（0x11cb3ed80）交Param factory0x105d52fe4（0x10aac4538）；value nil退nil，
非nil存Param.+8/+0x10（0x105d5304c/0x105d53098）。s_locale sibling
0x10aac49f0每次读SYSTEM（0x10aac4a94/0x10aac4a9c），key0x11cb3edb0；
SYSTEM自身lazy仍缓存，producer再次调用不等于刷新OS语言。

Locale String getter0x105c1ded4读每个Locale.+0x10 lazy，接Locale$1
TypeInfo0x11b4c4910/body0x105c1df5c。它拼languageCode（0x105c1e168），scriptCode
非空时加`-script`（0x105c1e054），countryCode非空时加`_country`
（0x105c1e104），组合0x105c1e17c/0x105c1e18c/0x105c1e19c。因此不是裸
languageCode，schema形状为language[-script][_country]；未输出真实设备值。
各Locale对象有自己的String lazy，c_locale producer每次取当前对象，服务缓存不
固定语言值。

NetPublicParam constructor0x10aac220c只存function object到.+8
（0x10aac22b4），实际hash0x13180 slot0→0x105d52e20每次invoke所存producer
（0x105d52e80/0x105d52ed0）。CommonParamsPlugin loop0x10a9aca6c明确调用
hash0x13180（0x10a9acd00/0x10a9acd38），nil跳过、existing query key则保留
（0x10a9acd08/0x10a9acd40/0x10a9acd7c/0x10a9acda8）。c_locale实际collection
绑定见下段；公共hook启用时，后续hook执行会读新current，无需该对象自己监听flow。
DI已接SingletonModule provider0x11bb41250/static0x11cb3e6a8→DSL定义
0x10aabecd4→lambda0x11bb41ad0→constructor0x10aac220c；实际Root注册也已闭：
DSL body0x10aabec18的调用0x10b93c74c位于SwitchingProvider ID44分支
0x10b93c738，jump table0x118652e72的index44 UInt16=0x166、base0x10b93c1a0。
constructor以ID44包装provider并存Root.+0x120（0x10b9318d0/0x10b9318d4/
0x10b9318e0），getter0x10b920374。实际11-member public-param collection的ID40
分支0x10b93cb18调用此getter、resolve并保存结果
（0x10b93cb6c/0x10b93cb74/0x10b93cb78），写array element3
（0x10b93cc30/0x10b93cc34）；count11 header0x10b93c09c/0x10b93c0a0、arraybase
0x10b93cc48，经factory0x10522e81c（0x10b93d788）形成集合。该ID40 provider存
Root.+0x170（0x10b931df8–0x10b931e00），getter0x10b920aa4。

CommonParamsPlugin的实际Root分支0x10b93d2d0取同collection getter
（0x10b93d2ec），以x1交0x10a9ab6fc（0x10b93d318/0x10b93d324）；generatedprovider
TypeInfo0x11bb1d9c0捕获collection provider到.+8（0x10a9ab7cc）。factory0x10a9ab9cc
invoke该provider hash0x584 slot0（0x10a9abacc），把resolved collection存concrete
lambda TypeInfo0x11bb1da60的.+0x10（0x10a9abb80）。所以c_locale不是仅存在DSL定义，已经接CommonParamsPlugin factory捕获集合；
该集合实际进入commonParamsPlugin$publicParam$1，TypeInfo0x11bb1dc60/callback
0x10a9ade68（methodvector0x11c32c2e0）。构造处取原lambda.+0x10/.+0x18后swap并存
callback.+8/.+0x10（0x10a9abcd8/0x10a9ac320/0x10a9ac324），故callback.+0x10正是
上述11集合。callback每次读.+0x10、取iterator（0x10a9ae2b4/0x10a9ae35c），逐binding
hash0x587 slot2产实际NetPublicParam并收集（0x10a9ae37c–0x10a9ae3a8），再转换/组合
（0x10a9ae4b8/0x10a9ae4c4）；hook最终request采用仍按此前公共执行门禁。
invoke0x10a9abca4在
0x10a9abce0实际读取lambda.+0x20作为迭代集合，不能把0x10a9abe18–0x10a9abe24的
另一dependency转换当作.+0x10公共参数集合消费。它与GInterceptor 18-member集合
分开。s_locale也在同collection的zero-based element4：ID45 provider存Root.+0x128
（0x10b931958/0x10b93195c/0x10b931968），getter0x10b92042c；ID40集合分支调用
getter、resolve，写element4（0x10b93cb84/0x10b93cb8c/0x10b93cc38）。ID45分支
0x10b93d234→DSL0x10aabee80（0x10b93d248），binding0x11cb3e770接generatedprovider
TypeInfo0x11bb412f0/factory0x10aac0ca8→concrete lambda TypeInfo0x11bb42010。
其槽0x11bb420b8→0x10aac39e4把static function object0x11cb3ed78存NetPublicParam.+8
（0x10aac3a84/0x10aac3a8c），接已证SYSTEM producer0x10aac49f0。因此两query均是
实际集合成员，s_locale重复执行仍读SYSTEM lazy。不能宣称所有HTTP/Moss/Ktor请求
均采用该集合或绕过现有enable门禁，OS locale reset仍未证。

公共callback产物到执行loop也已连接：plugin构造0x10a9abca4创建configure callback
TypeInfo0x11bb1dd00（0x10a9ac330/0x10a9ac338），将上述publicParam function存.+8
（0x10a9ac378），以CommonParamsPlugin name和createClientPlugin helper 0x105d3f61c
构造（0x10a9ac394）。configure actualbody 0x10a9b200c分别通过0x105d3eaac注册
TransformRequestBodyHook（TypeInfo0x11bb1dda0/0x11b4f23d0，0x10a9b20e0）、
RequestHook（0x11bb1de40/0x11b4f2290，0x10a9b2144）和Send
（0x11bb1dee0/0x11b4f1bd0，0x10a9b21ac）。第一actualcallback 0x10a9ae500在条件
分支读取publicParam function（0x10a9ae784），接口hash0xa01 slot0调用
（0x10a9ae9f8..0x10a9aea08）到具体0x10a9ade68；返回producer collection保存在x22
（0x10a9aea0c），交wrapper 0x10a9ac72c（0x10a9aea30），wrapper保持collection
（0x10a9ac754/0x10a9ac888）并调用fillloop 0x10a9aca6c（0x10a9ac894）。
RequestHook sibling也有直接fillloop调用0x10a9af354。因此实际公共集合→provider解析→
注册callback→参数执行loop已闭合；此前CommonParamsEnable/typed tag/method/content/
rpc门禁仍适用，configure callback创建不等于所有client都运行其hook。

### Phone 推荐设置页的点选写入与 recsys_mode 三层值

具体设置列表行的tapMethod是`pushToHomeConfigVC`：MainVC.init 0x10f2fea38调用
getMainSettingDatas（0x10f2fea58），再super.initWithDatas（0x10f2fea84）。构造body
0x10f307a84中，该行title/vcTitle取SettingsRes.string189
（0x10f3085f4/0x10f308628），detail合并getFormat和inline自动播放描述
（0x10f308658/0x10f30866c/0x10f30868c）；CFString0x11d208390存值栈.+0x10e0
（0x10f3086f4/0x10f3086fc），公开tapMethod key 0x11d2082d0存对应key栈.+0x10a0
（0x10f308704/0x10f308708），count8 dictionary（0x10f308780）加入行数组
（0x10f308798），最终settingModelWithDic→yy_modelWithJSON（0x10f30c024/0x10f323940）。
海外Teen whitelist也明确包含相同resource189（0x10f30b934/0x10f30b944），不把配置
运行值或所有用户可见性视为已知。

通用cell物理手势实际安装在0x10f32f2c8的contentView，self为target、tapClickGesture:
为action（0x10f33090c/0x10f330914/0x10f330954）。BaseVC取CURRENT datas[row]并安装
weak-self tapBlock（0x10f2fe600/0x10f2fe704）；gesture.state EXACT3
（0x10f330a04/0x10f330a08/0x10f330a0c）才tapClickCell，将CURRENT cell.model交block
（0x10f330b74/0x10f330b90），block保存tapCellModel再didSelectCell
（0x10f2fe7bc/0x10f2fe7cc）。MainVC.didSelectCell 0x10f2ff590读model.tapMethod→
NSSelectorFromString（0x10f2ff5cc），respondsToSelector=true才performSelector
（0x10f2ff5ec/0x10f2ff5fc）。该具体selector 0x10f3070e4先直接上报
`main.setting.setting-layout.0.click`（0x10f307100/0x10f307108），再创建
BBPhoneSetThemeViewController（0x10f307138/0x10f30713c），以animated=true push
（0x10f307150），这条入口不走router。Theme.init 0x10f2f28d8仅super.init及pv/highlight
初始化，没有本body的isThemeMode赋值；普通ObjC新实例零初始化使该Bool默认为false
是此处静态推论，未冒充一次setParams调用或运行时值。独立存在的
pushToPegasusFeedRecommandSettingVC 0x10f301740仍未找到其具体row绑定；新闭合的
物理入口不据此填补该方法来源或HD2路由alias。

`/main/feedsetting`已注册的BBPhoneSetThemeViewController虽名Theme，实际有推荐
设置分支。setParams0x10f2f29a4读公开 `isThemeMode` Bool
（0x10f2f29ec/0x10f2f29f0→0x10f2f2a14）；另 `setting` 只接highlight
（0x10f2f2a4c），不把class名字当仅主题页。_prepareDatas0x10f2f32c4在
isThemeMode=false（0x10f2f32f0/0x10f2f32f4）构造推荐sections；只有manager.
isDisplayFeedModeSetting及VC.feedModeArray.count>0（0x10f2f3808/0x10f2f3824）
才加入PegasusRes.string214作标题的section（0x10f2f3884）。viewDidLoad
0x10f2f2d24在manager显示门禁true时取feedModeSettings→setFeedModeArray
（0x10f2f30e8/0x10f2f3110/0x10f2f3128）。cell配置从feedModeArray[row]取value
（0x10f2f44b4/0x10f2f44d0），以CURRENT isFollowFeedMode XOR (value!=1)写
isSelected（0x10f2f44d8/0x10f2f44f4/0x10f2f44f8/0x10f2f4500）。value1在follow
时选中，所有非1值在非follow时选中；响应若有重复/非标准value，不保证唯一选中。

FeedModeSetting.setup0x101b8983c向BBListPegasusEventDispatcher注册raw26 callback
（0x101b898a8→0x101b8a388→0x101b899f8）。callback要求payload dictionary.
follow_mode可转非空dictionary（0x101b89ab4/0x101b89b14），经Model.yy_modelWithJSON
（0x101b89b6c）成功才helper0x101b8a3ec并setDisplay=true
（0x101b89b98/0x101b89bcc）。helper保持Model.option原索引顺序逐项创建
BBListPegasusSettingObject，写title/desc/value
（0x101b8a5a0/0x101b8a600/0x101b8a620），最后setFeedModeSettings
（0x101b8a6dc），这段循环不写isSelected、不排序去重。接受的Model可含空option，
display=true仍需前述VC.count门禁；不是服务端selected字段决定选择。
missing/空payload或转换失败的两条fallback，在CURRENT feedModeSetting==1时
updateFeedMode(0)（0x101b89c54/0x101b89c90、0x101b89d14/0x101b89d50），
随后setDisplay=false（0x101b89cc0/0x101b89d80）；这里的input0不要套物理取消input2。
raw26完整网络producer及账户重置边见后文。helper还将Model.yy_modelToJSONData
交feed_mode文件writer（0x101b8a420/0x101b8a47c→0x104e298d0），namespace见后文；native createFileAtPath返回Bool被丢弃（0x104e29ae8），不据调用断言落盘成功。

tableDidSelect0x10f2f5614当前section标题匹配该资源（0x10f2f5a20/0x10f2f5a48）
才进入此branch，先全部item.isSelected=false（0x10f2f5ab4，真实stub
0x10f87a0b8→0x1175bd980），再row项=true（0x10f2f5b30）。chosen.value==1
调用updateFeedMode(1)（0x10f2f5b60）；value==0且CURRENT isFollowFeedMode=true
（0x10f2f5b94）则updateFeedMode(2)（0x10f2f5ba8/0x10f2f5bac）；value0但非follow
或其他value不调用writer，但均reportRecommendWithOption(row+1)
（0x10f2f5bc0）。这是点选即时提交，与HD2 settings页disappear提交分开。

manager.updateFeedMode0x113cee678把input1转cachedPegasusDeviceConfig.mode的
Int64Value.value=2，其余input转value=1（0x113cee744/0x113cee74c）；与旧PB.value
相同便返回（0x113cee75c），不同才setValue、uploadConfig
（0x113cee768/0x113cee770），之后发公开
BBPegasusFeedModeSettingDidChangedNotification（0x113cee7f0），userInfo为
`value`:NSNumber(original setter input)（0x113cee7a4/0x113cee7cc）。这条notification
紧随uploadConfig调用返回，body没有等待upload业务成功的门禁；实际持久化/失败策略
另查。随后logEvent UserPreference FeedMode Setting，info为原input.stringValue
（0x113cee838/0x113cee844）；same-PB gate跳过upload/notification/log全部。

getter feedModeSetting0x113cee5c0要求cachedConfig、hasMode及mode.hasValue
（0x113cee5d8/0x113cee5f0/0x113cee614），PB.value==2才返回1
（0x113cee630/0x113cee638），其他或缺值返回0；isFollowFeedMode
0x113cee5a4→0x113cee5ac比较该结果==1。Swift首页builder取shared.isFollowFeedMode
（0x101a32d74/0x101a32d8c），转ASCII `1`/`0`（0x101a32da4），写
`recsys_mode`（0x101a32de8/0x101a32e04）。因此setter input1、PB2、wire1三层
不同；取消关注input2写PB1、wire0，不能直接把input2或PB2作为请求码。下次新API
读此getter。FeedModeSetting另注册上述NSNotification
（0x101b899b4–0x101b899d4），destructor移除observer（0x101b8a28c）。receiver
0x101b8a1cc→0x101b8a794仅在userInfo.value可cast Int时，向同一dispatcher发
raw27、payload单Int数组、d0=0（0x101b8a7fc/0x101b8a86c/0x101b8a8ac/
0x101b8a8c4/0x101b8a8cc）；缺值/类型失败返回。Home实际刷新消费者及账号/
服务器更新边见下段，不能把notification或raw27派发本身当刷新请求已发。

RefreshHelper实际注册raw27/flag1（0x101b65a50/0x101b65a54），callback
0x101b6911c→0x101b663b8只接受payload首项可cast Int且EXACT==1
（0x101b66400/0x101b6640c/0x101b66410），weakHelper存活才调用0x101b646e0。
因此UI取消input2及fallback/logout input0不经这条consumer刷新。helper在
pegasusIsShow=true时取operator.+0x30、reason5并dispatch
（0x101b646fc/0x101b6471c/0x101b64774/0x101b64778）；未show时，配置
mode_switch_refresh_exp getter0x101b63054仅Int2返回raw2，匹配才先operator.+0x60
再.+0x50、同reason5（0x101b6472c/0x101b64758/0x101b64768），否则仅置
followStateChanged=true（0x101b6479c）。viewWillAppear到0x101b638a8消费延后标志，
优先级为userHasChangeFormat→rcmdStatusChanged→playStyleManualChanged→follow。
follow获胜才operator.+0x30/reason5（0x101b63ab8/0x101b63ad0/0x101b63ad8），
dispatch后ALL四flag清零（0x101b63980/0x101b6398c–0x101b639a4）；高优先变化可
以其他reason消费followflag，不保证每个flag各发一次请求。

MainVM的operator.+0x30绑定0x101a5c464→0x101a4fa88
（0x101a4939c/0x101a5c474），沿已闭collectionView/!loading/0.3s/header refresh
链；.+0x50绑定0x101a5c404→0x101a4893c（0x101a492e8/0x101a5c414），仍受loading
准入；.+0x60绑定0x101a5c424→0x101a4f1f8（0x101a49324/0x101a5c434）。准入后
0x101a550b0 alloc新MainApi、保存reason（0x101a550ec/0x101a55100）；builder表
0x1182c9138的qword index5=4，故reason5→wire flush4，recsys_mode仍独立读取
CURRENT manager（0x101a32d8c），不从通知input直接生成。

raw26实际config producer包括normal refresh0x101a5b3b0更新VM.config后取当前
config作payload[0]并publish（0x101a5b554/0x101a5b5a8/0x101a5b5bc/
0x101a5b5dc/0x101a5b5e4），fallback cache0x101a54878同样更新/publish
（0x101a54938/0x101a549c0/0x101a549c8），loadmore0x101a55088亦然
（0x101a55448/0x101a554e4/0x101a554ec）。因此options及缺失follow_mode回退不只
由新网络refresh结果触发；callback未校验account generation，真实跨账号行为未运行。

feed_mode本地JSON的namespace witness0x11b175230+8→0x101b8a330返回
feedmodesetting；路径helper0x104e2a030取NSSearchPath raw9/userDomain1首路径
（0x104e2a050/0x104e2a080）追加/com.bilibili.list/（0x104e2a0bc），再namespace/
feed_mode（0x104e29c08/0x104e29c2c/0x104e29bac），构造中无MID输入。
已有文件先remove再create，未证原子写或成功ack；它与Universal PB选择存储分开。
账户observer注册mask0xa（0x101b89978），但consumer0x101b89d94仅incoming
EXACT2（Logout，0x101b89ddc/0x101b89de0）且CURRENT模式==1才读此文件，取首
option.value==1的title或资源254回退（0x101b89e30/0x101b89e64/
0x101b89f54/0x101b89f58/0x101b89fa4），showCenterToast后updateFeedMode(0)
（0x101b8a10c/0x101b8a138/0x101b8a13c）。incoming8不会执行此reset，mask10
不等同两事件都重置；该body不清文件、不setDisplayfalse/清options。实际setup实例安装见下段；
这些文件读取不等于首次本地options恢复。

实际MainService.setup0x101b85a58把FeedModeSetting静态object（0x12034eff8）
放入plugins array（0x101b85d88/0x101b85d98/0x101b85da8），witness
0x11b175260的+8→0x101b8a310→setup0x101b8983c（0x101b8a320）。plugins setter
0x1035a4050先存array，再按40-byte existential顺序调用各witness.+8
（0x1035a408c/0x1035a40d8），因此已接实际订阅安装。0x101b85564仅初始化
MainEventOperator，不应当作此setup。ServiceCenter.register0x101b8831c写serviceMap
后调用service metadata.+0x150（0x101b88430/0x101b88444/0x101b88484/
0x101b88488）；MainService该槽0x11fbf8d10正指0x101b85a58。

BBPegasusSwiftModule.setup0x101a09378→0x101a08f74（0x101a093dc）resolve registry，
默认fallback0x101a08464提供shared ServiceCenter/global0x12106a6b8及witness
0x11b1751f0。它新建MainService（0x101a09040/0x101a09044/0x101a09050），以rawscene1
交registry witness.+8（0x101a0905c–0x101a0906c）；默认witness0x101b88a74接上述
register。外部registry override的实际identity仍另核。legacy onModuleInitialize
0x101a083a8仅runnable optfalse才setup（0x101a083c0/0x101a083e0）。opttrue替代
为库存index135/slot0x1202743c0的provider0x1001ca8a4/class0x120299640；lazy task
array0x1001ca844由0x1001ca7f4创建一组metadata0x11b0be940/witness0x11b0be8f0
（0x1001ca830）。name槽.+0x20→0x1001ca744返回PegasusSwiftModuleModuleInitialize，
execute槽.+0x28→0x1001ca760要求idiom0及opt EXACTtrue
（0x1001ca79c/0x1001ca7ac/0x1001ca7cc/0x1001ca7d0），再调用static thunk
0x101a083a4（0x1001ca7e0）→同setup。trigger helper0x1001ca608接moduleInitialize
producer0x105138060，thread helper0x1001ca620接main producer0x10513818c；静态门禁
不保证实际每次执行。setup0x101b8983c不读feed_mode文件；已知logout及FeedTopView
label读文件，不据持久JSON推settings options启动恢复。

Phone首页模式条有独立的物理导航入口：TopFeedModeView.initWithFrame wrapper
0x101b979ac→0x101b977c4将self.tapView作为gesture target/action安装到self
（0x101b97940/0x101b97960/0x101b97978）。tapView 0x101b983fc→0x101b984e8
读取CURRENT BFCAccount.hasLogined（0x101b9850c），true选`/main/feedsetting`
（0x101b98518），false选`/login`（0x101b98570），以空参数调用route helper
0x101b6fd30（0x101b98588）。该helper先transferFromHttpScheme（0x101b6fe04），
合并URL query，解析或序列化失败时沿用transferred string；先设置
PersonalizeGuidance.hasClickedInPegasus=true（0x101b6ff94），再以animated=true调用
BFCRouter.processUrl（0x101b6ffe0），不以router成功返回为该标志门禁。已知Phone
`/main/feedsetting`映射仍受外层Compose/native-transfer影响；此入口不证明settings列表
某行的tapMethod，也不解决HD2的main/pegasus alias。

FeedTopView的模式条状态consumer实际安装在0x101b96148→0x101b964bc：raw27/flag1
（0x101b96590/0x101b96594/0x101b965a0）callback 0x101b96d9c经weak-self helper
0x101b966bc→0x101b9685c；raw26/flag1（0x101b965fc/0x101b96600/0x101b9660c）
callback 0x101b96e1c直接tail同raw27 callback。两者忽略event payload，重新读CURRENT
feedModeSetting（0x101b968a0），desiredHidden=(mode!=1)
（0x101b968b0/0x101b968b4）；与当前isHidden相等即返回
（0x101b968cc/0x101b968dc/0x101b96a10）。只有hidden改变，才setHidden
（0x101b96904），读取feed_mode JSON（0x101b9694c）并解析Model
（0x101b96994），取可选title（0x101b969cc）设置titleLabel.text（0x101b96a40），
缺失model/title则text=nil（0x101b96a24/0x101b96a2c），最后layoutIfNeeded
（0x101b96a94）。所以同mode的raw26即使替换JSON，也未必刷新显示标题；该handler
不检查isDisplayFeedModeSetting或options.count。lazy view创建时先hidden=true
（0x101b95fd4/0x101b95ffc/0x101b96048）。JSON读取不恢复settings option数组。

### Phone 播放模式引导：入口、曝光与当前实例移除

PlayModeGuideManager有独立的公开路由`/main/feedsetting?setting=playStyleSetting`
（literal0x11789c420），不与PersonalizeGuidance混为同一入口。onOpen body
0x101b404dc先用空参数调用公共router helper0x101b6fd30（0x101b40580），之后才处理
引导状态。onJump body0x101b40934要求CURRENT currentModel非nil且cardJumpEnable
EXACT1（0x101b40998/0x101b4099c/0x101b409ac/0x101b409b0），才route
（0x101b40a08）。这两个body在route之前没有login门禁；公共router仍有前述转换与
hasClickedInPegasus写入。实际show创建PlayModeGuideView并绑定weak-manager
onClose/onOpen/onJump（0x101b3fb68/0x101b3fbbc/0x101b3fbfc），weak helper
0x101b408dc在manager仍存在时执行对应body（0x101b4090c/0x101b40918）。

View背景安装jumAction gesture（0x101b41870/0x101b41890/0x101b418a8），action
读onJump并BLR（0x101b4349c/0x101b434bc）。左右按钮安装target=self及raw control
0x40（0x101b421fc/0x101b4220c/0x101b42214）；leftButtonTapAction0x101b434f0
和rightButtonTapAction0x101b435c8共用0x101b43528。CURRENT view.model非nil且isV2==1
（0x101b43548/0x101b43558/0x101b4355c）时左close、右open，否则左open、右close；
选中closure非nil才调用（0x101b43568/0x101b435b4/0x101b43588）。不能根据按钮侧别
固定推断动作。

旧model factory0x101b3e0d8读Memex公开key `pegasus.story_mode_guidance_config`
（0x101b3e12c），要求config/dictionary非nil，yy_modelWithDictionary
（0x101b3e1d8）；Model默认cardJumpEnable=false、isV2=false
（0x101b3dea8/0x101b3ded4）。新factory0x101b3e294读
`pegasus.story_mode_v2_guidance_config`（0x101b3e2e8），解析WapperModel
（0x101b3e394），storyGuide存在才强制child.isV2=true
（0x101b3e3c8/0x101b3e3d4/0x101b3e3d8）。公开Model属性表0x11d63f278包含
imageUrl/title/subTitle/showTimeSec(double)/cardJumpEnable/setButton/cancelButton/isV2；
wrapper表0x11d63f3b0含timeoutForDismiss/timeoutForClick(Int)及typed storyGuide。
本类metaclass没有自有custom mapper，继承/category行为另核，不猜snake_case别名。
wrapper默认timeoutForDismiss=30、timeoutForClick=180（0x101b3e044/0x101b3e054）。

两个model是实例lazy cache：helper0x101b3e220仅缓存字段为sentinel1时执行factory
（0x101b3e248/0x101b3e24c/0x101b3e254/0x101b3e260），包括nil结果也缓存。
init0x101b3efc0将两个字段设1（0x101b3efe0/0x101b3efec）。raw26/flag1注册
（0x101b3e54c/0x101b3e550/0x101b3e55c）weak callback0x101b4376c→0x101b3ed88
只把CURRENT feature字典中need_show_story_mode_guide成功Int cast且==1转换成
oldGuideEnable（0x101b3ee50/0x101b3ee54/0x101b3eea4），把
story_mode_v2_guide_exp成功Int原值或失败0存newGuideExp（0x101b3ef68/0x101b3ef8c）。
该完整callback不重置lazy models/currentModel/guideView；不据此推全局永不刷新或按账号分区。

真实entrance注册包括foreground selector _showPlayModeGuideIfNeeded
（0x101b3e5fc/0x101b3e618），以及raw2/flag1 weak callback0x101b43744；两者到
0x101b3e6e8。old admission先拒绝miniScreenPlayerManager.showing
（0x101b3e740），再要求oldGuideEnable==1、CURRENT videoMode==2、weak page provider
可用且其page字符串等于`main.ugc-video-detail-vertical.0.0.pv`、未hasShownOld
（0x101b3e750/0x101b3e794/0x101b3e7b8/0x101b3e8a8/0x101b3e900/0x101b3e914）。
先currentOldGuide=1（0x101b3e924），再要求Chinese locale、仍未hasShown、!isShow、
currentOldGuide==1和oldModel非nil（0x101b3e988..0x101b3e9e0）才enqueue
（0x101b3e9ec）。其fallthrough还独立判断newGuideExp>=2/currentNewGuide>=2
（0x101b3ea08/0x101b3ea1c）。new admission0x101b3f2a4要求Chinese locale、
nextShow时间STRICTLY小于now、!isShow、currentNewGuide为raw2或4、wrapper/storyGuide
非nil（0x101b3f358/0x101b3f38c/0x101b3f390/0x101b3f3a0/0x101b3f3b0/
0x101b3f3bc/0x101b3f3e8/0x101b3f410），才enqueue（0x101b3f41c）。不为raw值猜枚举名。

Enqueue0x101b3f624先存CURRENT currentModel（0x101b3f64c），再BBSerial.addEvent
priority raw0（0x101b3f744/0x101b3f750），closure捕获weak manager与strong supplied model
（0x101b3f6d0）；thunk0x101b4381c到实际show0x101b3f7e4。当前oldGuide==1存old token，
否则当前newGuide>=2存new token（0x101b3f784..0x101b3f7b4），替换旧token时此helper
未显式end。实际show要求weak manager可用、TopmostView.viewForApplicationWindow非nil、
page provider及其protocol metadata可用；已有CURRENT guideView则退出
（0x101b3f8fc/0x101b3f91c/0x101b3f950/0x101b3f98c/0x101b3fa40）。view以captured model
构建并add到上述window view（0x101b3fc14），保存guideView、isShow=true
（0x101b3fc1c/0x101b3fc44）；oldGuide==1时此后才hasShownOld=true（0x101b3fc6c）。

Attach后实际BFCNeuronExposureEvent `tm.recommend.play-mode-guidance.0.show`
（0x11789c3f0/0x101b3fe58）trackInstantly（0x101b3fec4），无该body额外dwell门禁。
trigger_type String：当前oldGuide1→0，否则newGuide2→1、4→2、其余→3
（0x101b3fcac..0x101b3fd28）；tm_card_play_state是CURRENT videoMode经枚举metadata和
_print_unlocked格式化（0x101b3fd98/0x101b3fdb0/0x101b3fdd0），不能标成decimal raw值。
这证明日志dispatch，非服务端收到。

Attach/曝光之后，showTimeSec>0用原Double，否则5秒
（0x101b3fee4..0x101b3fefc），main.asyncAfter（0x101b40088）strong捕获manager
（0x101b3ff6c/0x101b3ffcc）。timer thunk0x101b438c0→0x101b40d98仅dismiss
CURRENT manager（0x101b40df4），未比较原view/model/token/generation，也未保存取消handle。
不能声称迟到旧timer天然屏蔽新引导；实际serial是否允许该交错仍未运行验证。
Dismiss0x101b3f46c要求CURRENT isShow==1且guideView非nil
（0x101b3f490/0x101b3f494/0x101b3f4a4），匹配old model/guide时end/clear old token
（0x101b3f564/0x101b3f56c），匹配new时end new token（0x101b3f594）。后者机器码却选择
oldGuideToken descriptor0x120357098清零（0x101b3f59c/0x101b3f5a4），保留此实测区别。
随后isShow=false、remove CURRENT view并清guideView/currentModel
（0x101b3f5ac/0x101b3f5bc/0x101b3f5cc/0x101b3f5d8），不清memoized models。
Timer、background _autoDismiss0x101b3ebd0（注册0x101b3e5b4/0x101b3e5d4）及raw3
callback0x101b3ea58仅dismiss成功+wrapper可用+CURRENT newGuide>=2时更新冷却：
now+timeoutForDismiss*86400，overflow trap，随后清currentOldGuide/currentNewGuide
（0x101b40e70..0x101b40eac；0x101b3eca4..0x101b3ece0；0x101b3eadc..0x101b3eb94）。
因此默认30在此consumer是天。

持久实现亦有具体证据：原Mach-O dyld rebase superclass slot0x11fbf6028→BFCPreferences
0x1202710f0，metaclass-super0x1203570b0→0x120271118；属性表0x11d63f100中
hasShownOldStoryModeGuide为TB,N,D，nextShowStoryModeGuideTimeInterval为Td,N,D。
configName0x101b40f98返回固定BBPegasusPlayModeGuideManager
（0x101b40fa4/0x101b40fb8），default builder0x101b43984分别Bool false
（0x101b43a10）及boxed Int0（0x101b43a44），后者实际dynamic getter仍为Double。
BFCPreferences的ASCII d分支选getter0x1167d49c8/setter0x1167d4a50
（0x1167d3adc/0x1167d3bd8/0x1167d3be0）；getter读RAM object→doubleValue
（0x1167d4a04/0x1167d4a20），setterNSNumberDouble→通用RAM/UserDefaults writer
（0x1167d4a94/0x1167d4ab0）。普通初始化disk值优先default，固定suite无MID参数；
不证明跨账号外部清理，也不把NSUserDefaults调用当磁盘成功。singleton once
0x12034eeb0→initializer0x101b3e0ac保存0x12106a618（accessor0x101b40efc）。

BBListPlayerBehavior注册receiver已具体定位：module installer0x101a08f74取pgs bridge
（0x101a09078），将同一PlayModeGuide singleton0x12106a618与protocolRef0x11f7b0580
交virtual+0x68（0x101a0911c/0x101a09124/0x101a09134/0x101a09154）；singleton未初始化
分支swift_once→initializer0x101b3e0ac（0x101a09348/0x101a09354/0x101a09358）。
bridge accessor0x104e4ddac与ObjC pgs0x104e4ddec共享once0x120a33508/global0x1210730e8，
实际BFCResolver0x11ff35d30经init0x104e4e064存underlying Resolver到ivar0x1204b07f8
（0x104e4e078）；underlying是once0x120a33580/global0x121073160的Resolver实例。
class slot+0x68指0x104e4e2d0，检查conformsToProtocol（0x104e4e2f8/0x104e4e2fc）；
manager protocol list0x11d48ff08含BBListPlayerBehavior0x11d62d1b0。接受后用
NSStringFromProtocol→SwiftString（0x104e4e31c/0x104e4e32c），强捕获同manager
（0x104e4e358/0x104e4e360），factory0x104e4e3e0返回原receiver，交Resolver.register
0x105127fd4（0x104e4e380），不另建manager。

Phone objectFromProtocol0x104e4e720调用同bridge lookup0x104e4e674
（0x104e4e750），用同generic type及protocol-name String查询0x105129240
（0x104e4e6a0/0x104e4e6ac/0x104e4e6bc/0x104e4e6f0）。Phone protocolRef0x11f7b5148
虽指另一protocol对象0x12078c070，但name同为BBListPlayerBehavior；key输入为type+name，
因此接到上述exact-manager factory。竞争注册、scope、override或miss语义属Resolver容器运行期行为；静态可核残余：find_callers 0x105127fd4 穷举Resolver.register全量调用方确认无同key二次注册。另两实际消费者0x10359b4ac（Mall VDToStoryBloc shareGotoStory日志helper）
及0x103c322a0经lookup/cast后发送playerDidChangePlayModeToStory
（0x10359b648/0x10359b678/0x10359b690；0x103c3275c/0x103c327c0/0x103c327d8），
Mall入口具体用户动作属UI事件装配（静态仅给候选）；下一步：find_callers 0x10359b4ac 穷举shareGotoStory helper调用方核对触发与Bool callback门禁，不能由日志名推行为；
BBVideoModule拖动入口如下已闭。

其中BBVideoModule.VDToStoryBloc helper0x103c322a0先写willTransType raw3
（0x103c32318）、isEnterStory true（0x103c32364）及snapshot（0x103c323b0），
然后才做分享播放准入。Memex公开key `ff_story_new_share_player_825` 默认hit=true
（0x103c32404），命中且share-player helper0x103f8e518返回>=1
（0x103c32440/0x103c32444）走替代参数路径；否则beginSharePlay helper0x103f8e5e4
（0x103c325d4）必须true（0x103c325e4），false绕过DidChange退出。该helper要求
player.context.shared非nil（0x103f8e668）及share record非nil（0x103f8e67c），
设role/setupMode/phase均raw1（0x103f8e6a4/0x103f8e6b8/0x103f8e6cc），调用service
virtual+0xb8（0x103f8e6f8）后返回true；record来源另核。通过后才lookup/cast并
通知playerDidChangePlayModeToStory（0x103c327d8），之后再处理BFCRouter route，
故guide状态触发发生于导航之前，不能当作导航成功回执。

具体拖动producer与此helper已有静态接线。安装器resolve VDDetailContainerBlocProtocol
（0x103c2fd58..0x103c2fda4），非nil PublishSubject<DraggingFlowState>订阅callback
0x103c3292c（0x103c2fe04/0x103c2fe2c）。该callback只接受原始byte3
（0x103c32940/0x103c32944），route lookup(input0)必须非nil（0x103c32954），
helper0x103c31dc0 false则直接进入VDToStory rawreason4/Booltrue（0x103c32998），
true走helper0x103c31f64(raw4)另经分享播放与route准入。enum descriptor0x119624580
有0 payload、4 empty cases，reflection0x119875a54依次begin/dragging/recover/dismiss，
所以此raw3是dismiss，不是账号通知值。实际V3协议conformance0x1183c3860、
witness0x11b2a7870+8→0x103f3051c返回其draggingFlow field0x1204521c0；初始化
0x103f2f648保存同一个subject。Coordinator初始化将self.handlePanGesture:装到view
（0x103f34354/0x103f3436c），ObjC action0x103f32198→0x103f31d88，sender.state
（0x103f31e18）raw1/2分别begin/change，所有其他值取Y velocity
（0x103f31f30/0x103f31f64），不能仅称ended。结束helper0x103f32044要求
CURRENT offset<0或abs(velocity)<=20（0x103f32070..0x103f3207c），才以CURRENT
onPanGestureEndScroll和offset/Y velocity回调（0x103f32124..0x103f3214c）。
该槽已绑定weak V3 thunk0x103f318a8（0x103f2ee2c），经weak helper0x103f2f244
到0x103f295ac（0x103f2f290）。后者对有限值要求offset<0且
(offset<=-pullDismissThreshod或velocity>600)（0x103f296f0..0x103f29720），
content view非nil（0x103f29770）后才向同subject发raw3/Rx next tag0
（0x103f297ac..0x103f297cc），发生在dismiss动画之前。subject nil只跳过emit，
仍继续动画；不能把所有退出都算作guide触发。订阅dispose、其余入口和运行呈现另核。
替代共享路径helper0x103c317bc进一步要求CURRENT video.avid/cid均>=1
（0x103c31858/0x103c318c8）、playback非nil且raw playbackState>=3
（0x103c31948/0x103c31964）、shared与record非nil
（0x103c319d8/0x103c31a10），以及helper0x103c34ae8返回false
（0x103c31a1c）。后者读取CURRENT playback.inQueuePlay（0x103ed6ddc），非队列
直接false；队列且ijkItem nil或其cid与CURRENT currentVideo.cid不等则true拒绝。
不从原始state>=3命名为playing，也不读取具体标识值。前述isEnterStory/snapshot
先写后准入的本体未见rollback，不能把写入当作准入成功。

第二物理入口是左侧edge backpan。安装器0x103c2fd30将weakself thunk0x103c329f4
交VDBackPanGestureBloc.addBackGesture:0x103f1f64c；后者init target/action
（0x103f1f730）、setEdges raw2（0x103f1f744）、安装到CURRENT mainVC.view
（0x103f1f7e0），保存callback/context（0x103f1f8a0）。ObjC backAction0x103f1fdd8
→0x103f1fa9c，只接sender.state raw3（0x103f1fad8）；位移比例translationX/window
width（keyWindow或mainScreen）clamp到[0,1]（0x103f1fba4..0x103f1fbbc）。有限值
fraction>0.25或velocityX>800才调用CURRENT action
（0x103f1fd44..0x103f1fd7c），经0x103c329f4→0x103c328d4→0x103c31f64(rawreason2)
（0x103c32910），仍受上述共享路径helper及route(input1)非nil门禁。
播放器Story按钮还有独立入口：installer 0x103c2f874取VDPlayerBloc.player
（0x103c2f8c0），getService helper 0x103f437a4以flag1与精确protocol typeref
0x11973975c/缓存0x12041af98（So24BBPlayerGotoStoryService_p）求service
（0x103c2f8e8），非nil才安装weak bloc callback/thunk 0x103c32a3c
（0x103c2f8f8/0x103c2f91c/0x103c2f924/0x103c2f95c/0x103c2f988）。
service.addClickActionHandler 0x104a7dabc只替换单slot，copy新block/强保存context
并release旧handler（0x104a7dad8/0x104a7dafc/0x104a7db34/0x104a7db38），不是监听数组。
实际BBPlayerGotoStoryWidget的lazy button 0x104a7dc9c→0x104a7dd00创建UIButton，
action handlerSwitchBtnAction:以self/event0x40 addTarget
（0x104a7dd40/0x104a7dd4c/0x104a7dd50/0x104a7dd54）。ObjC handler
0x104a7e75c→0x104a7e614若CURRENT context.tracker存在，先track公开事件
`player.player.story-button.0.player`、extends=nil（0x104a7e69c）；tracker缺失仍继续。
取CURRENT _gotoStoryService（descriptor 0x12049a1c8；0x104a7e6b4），nil时同protocol
flag1 fallback 0x104b10294（0x104a7e6dc）。clickHandler存在
（0x104a7e70c）才Block invoke（0x104a7e730），之后仍调0x104a54a18。
callback thunk→0x103c2ff0c先weakself、route(input0)非nil
（0x103c2ff54/0x103c2ff68），再weak reload并要求共享准入helper 0x103c317bc true
（0x103c2ff84/0x103c2ff90/0x103c2ffa0），故仍受上述avid/cid/playbackState/shared/
record/queue门禁。isHitBackToStory false（0x103c2ffc8/0x103c2ffd8）才调用
VDToStory rawreason3（BL site 0x103c3012c）；true释放该route，改调0x103c31f64(reason3)
（0x103c2ffe0/0x103c3000c），独立重核share gate和route(input1)。按钮点击日志先于这些准入，
不等同导航或DidChange通知成功。服务lookup也不能简单称具体class实例：player lookup
0x103f437a4读player.context（0x103f437cc）→0x104b0ff1c（0x103f437e8）；widget
fallback读widget.context（0x104b102c0/0x104b102cc）→同helper 0x104b0faac
（0x104b102e4），由protocol描述转类名并NSClassFromString
（0x104b0faf4/0x104b0fb5c/0x104b0fb98），CURRENT context.serviceManager
（0x104b0fbd4）以flag1 createProxyAndBindService（0x104b0fc00）。具体
0x114822968先createProxyForService（0x11482297c），proxy非nil才bindService
（0x11482298c/0x114822998）。具体proxy target/cache已闭，但有同manager前提：
createProxyForService 0x114822904→_findOrAdd 0x114822694
（0x114822914），先_serviceForClass（0x1148226a8），nil才_add
（0x1148226c0）。lookup在锁下按Class查dictionary（0x114822654/0x114822668/
0x11482267c）；add alloc该Class、initWithContext后另锁写同dictionary
（0x1148226f4/0x114822718/0x114822734/0x11482274c/0x114822754）。
两者不是同一get-or-create critical section，首次并发是否串行由外层政策另核。
每次成功lookup后都新建BBPlayerServiceProxy（0x11482292c/0x114822938），其init
0x114822e94弱存actual service并保存actual.class
（0x114822ec4/0x114822ee4）；class override 0x1148234bc返回保存Class
（0x1148234c4）。故不同proxy可以指向同manager缓存的actual service。
bindService 0x114822a3c经proxy.class查actual（0x114822a68/0x114822a78），
missing时新建并rebind（0x114822a94/0x114822ab0）；actual inactive才serviceOnStart，
然后serviceOnBind(proxy)（0x114822b40/0x114822b4c/0x114822b58）。具体服务继承与
Video/player/widget是否安装同context由运行期模块装配决定；下一步：query_index '*PlayerServiceManager*' 30 反查各模块service装配入口核对context。不能把两lookup当同一proxy。
forwardingTargetForSelector 0x1148230c8只在weak actual存在且isActive=true时普通转发
（0x1148230f0/0x114823100/0x114823108）；inactive仅
rac_valuesForKeyPath:observer:与rac_valuesAndChangesForKeyPath:options:observer:
两个selector例外（0x1148231a4..0x1148231c0）。forwardInvocation
0x1148232b4也只对active actual invokeWithTarget
（0x1148232dc/0x1148232ec/0x1148232fc），其余setTarget:nil再invoke
（0x11482330c/0x114823314）。因此inactive旧proxy不保证执行具体icon setter或click
registration；返回值语义仍在NSInvocation边界，未作运行验证。
Widget init 0x104a7dee4→0x104a7e7fc（0x104a7df1c）初始化bag/service/lazy button后，
调用display 0x104a7df50及订阅helper 0x104a7e208（0x104a7e928/0x104a7e92c）。
display在CURRENT context/status nil时不改现态（0x104a7dff4/0x104a7e01c）；
status.isVerticalScreen true、service nil、gotoStoryIconUrl nil或URL转换失败
（0x104a7e030/0x104a7e064/0x104a7e0a8/0x104a7e0f4）写Gone/Hidden true
（0x104a7e110/0x104a7e128）。valid URL则setImage、completed=nil
（0x104a7e1a0），立即Gone/Hidden false（0x104a7e1c4/0x104a7e1e0），不等待图片回执。
service.base.gotoStoryIconUrl观察（0x104a7e318）→callback 0x104a7e5c4重读CURRENT
display（0x104a7e5d4），disposable进own bag（0x104a7e408）。controlActive KVO
keypath 0x1183f6e68→getter 0x104aed2ec，观察结果经MainScheduler
（0x104a7e470/0x104a7e4f4）→callback 0x104a7e5e4→0x104a54a18(rawfalse)，
按钮后同helper rawtrue；FlexControl实际attachment及该helper的完整显示控制另核。

该backpan安装还有上游参数gate：0x103c2fcb8调用isHitBackToStory helper
0x103c31dc0，false（0x103c2fcf4）跳至0x103c2fd4c→0x103f1f8ec，不绑定上述
reason2；true才执行0x103c2fd30。helper取CURRENT VDDataBloc.routeParam
（descriptor0x12044fee8）非nil后virtual+0x5c0；具体VDRouteParam
class0x11fe11a38槽0x11fe11ff8→0x103f11438 getter，读back_to_story_id
（descriptor0x120451860→0x103f126e0）。该String非nil且count>=1
（0x103c31e58/0x103c31e64/0x103c31e74）才true，不把此gate称Memex或设置toggle。
播放器Story图标的具体writer为0x103c2f4ac：取CURRENT player、resolve同协议service
（0x103c2f500），service nil不写；enable helper 0x103c32fd8为false时明确写icon nil
（0x103c2f518/0x103c2f5fc）。true取CURRENT basicModel（descriptor 0x12044fef8；
0x103c2f558），经BBVDBasicModel.+0xe8/getter 0x103ee783c取viewBase
（descriptor 0x120450740；0x103c2f584），其.+0x20为storyEntrance（0x1183c31d0）；
StoryEntrance class 0x120451d48.+0xc0/getter 0x103f15e4c读取landscapeIcon.+0x30，
桥接后setGotoStoryIconUrl:（0x103c2f5d8/0x103c2f634）。basic缺失亦写nil，不保留旧icon。
enable helper要求非vertical（0x103c33004/0x103c33014）、basic存在及
storyEntrance.arcLandscapeStory.+0x28为true（getter 0x103f15db0；0x103c330c4），
随后common 0x103c33104：BBPlayerPlaySettingService存在时supportShakeItem或
supportCubicPanorama任一true拒绝（0x103c33184/0x103c33204），service缺失仍继续
restricted gate。0x107c24ef8→0x10f82fb54→0x1145f1e74分别询问RestrictedModeManager
rawmode0/1、business `player`（0x1145f1e94/0x1145f1ea8），OR bit0任一true拒绝
（0x103c332a0），不由raw值猜模式名称。
StoryEntrance构造helper 0x103f16200从incoming ObjC receiver复制arcLandscapeStory
（0x103f1626c/0x103f16270）及landscapeIcon（0x103f16280/0x103f162a8）；后者nil走
trap（0x103f162dc），不是empty fallback。具体响应来源也已闭到Viewunite：BBVDBasicModel.initWithReply wrapper
0x103ee7fbc→0x103ee810c（0x103ee7fd8）读reply.viewBase（0x103ee8280），构造
VDViewBaseModel（0x103ee82b0）并存basic.viewBase（0x103ee82c8）。其constructor
0x103f163b4读incoming.config.storyEntrance（0x103f163e0/0x103f165a0/0x103f165bc），
构造VDStoryEntranceModel并复制上述Bool/String（0x103f165d8/0x103f165f0），存
viewBase.+0x20（0x103f16600）。相关必需reply.viewBase/config/storyEntrance缺失各有
trap分支（0x103ee86a8/0x103f16770/0x103f16774），不称网络fallback。
CURRENT DataBloc.basicModel writer 0x103eca5a8以原reply构造basic
（0x103eca5e8），直接替换descriptor 0x12044fef8并释放旧值
（0x103eca618/0x103eca61c）。parse helper 0x103ec9ecc先调注入parser witness+8
（0x103ec9f3c），status bittrue且reply nil才走该错误分支
（0x103ec9f54/0x103ec9f58）；其余分支先store CURRENT response
（0x103eca054），读viewBase/bizType/pageType，另要求admission helper
0x103eca1ec=true（0x103eca178/0x103eca17c），才交basic writer（0x103eca190）。
admission按bizType raw1/2/3解析plugin并调witness+8（0x103eca22c..0x103eca23c/
0x103eca350），未识别biz/provider缺失则true（0x103eca388）。**分派已逐支读出（team-c33）**：
helper 0x103eca1ec 先 `swift_beginAccess`（0x103eca224）读 `_OBJC_IVAR_$_BBVDDataBloc.bizType`
（槽 0x12044fed0，0x103eca210/0x103eca228），再 `cmp x8,#0x3/#0x2/#0x1`
（0x103eca22c/0x103eca234/0x103eca23c）分别选三个 Resolver 容器。
0x12044ead0/ad8/ae0 是 swift_once token，0x121070da0/da8/db0 是对象结果槽；
原文把二者写反。初始化 0x103ee1bf4/1c40/1c8c→0x103ee1c98 创建 Resolver，
0x104e41220 是日志格式化 wrapper，并非这些 initializer。
解析类型键 0x120372248 是 BBVideoDetail.VDModelParserProtocol。静态模块注册已闭合：
biz1容器注册 BBUGCVideoDetail.VDParserImp（0x103b0a3e4→factory0x103b09574）；
biz2注册 BBOGVUniteVideoDetail.VDParserImp（0x1031c2ab8→0x1031c23b8）；
biz3注册 BBEduVideoDetail.EduVDModelParserImp（0x10200f5d0→0x10200f348）。
这撤回“具体插件类名静态不可判”。UGC witness+8→0x103b0e37c 在正aid与当前
flow aid不同时记录日志并更新player flow config，已读正常返回仍true；OGV/Edu所选
witness+8直接true。nil arc的trap不作为正常false分支。
精确注册/类型/witness/raw证据 root-static-exposure/series-parser-findings.md；
运行期注册覆盖顺序、其它注入与9.13仍不由此证明。
线上source取BAPIAppViewuniteV1View classref 0x11f7ba550
（0x103ecf678），调用viewWithRequest:handler:（0x103ecf74c）。handler thunk
0x103ed0cb8→0x103ecfa18弱取捕获VDLoadTask（0x103ecfa58）；task已释放才令Booltrue
（0x103ecfa70/0x103ecfa74），经0x103ed0c5c→0x103ecf7b0时该Booltrue只取消日志并退出
（0x103ecf7d0/0x103ecf920），不是error code判断。false继续weak LoadBloc，存在才把
原reply/error、cacheflag=false交0x103ece87c（0x103ecf9c8/0x103ecf9ec）。VDLoadTask
实际分配后存CURRENT LoadBloc.task（descriptor 0x120450020；0x103ecf60c/
0x103ecf774），不将task寿命门禁称账号代际、也不以字段替换推立即释放。
至少一条icon重算触发来自supportCubicPanorama观察（0x103c2fbc8/
0x103c2fc08/0x103c2fc5c）：callback 0x103c3535c→0x103c328b0调CURRENT icon writer
（0x103c328c4）。响应解析后所有刷新hook、proxy target身份和请求参数仍继续核。

false分支具体是removeBackGesture 0x103f1f8ec：pan nil时早退（0x103f1f910），
否则从CURRENT mainVC.view移除（0x103f1f9ac），清pan及action pair
（0x103f1f9bc/0x103f1f9d4）；mainVC nil仍清字段，view nil走异常路径。
delegateShouldBegin 0x103f1fe28另读CURRENT player.context.status.isFullScreen，
true拒绝（0x103f1ff08），status nil或非全屏允许（0x103f1ff20）。
route mapper 0x103f12858→0x103f14834给back_to_story_id配置两个别名
`backToStoryID`/`back_to_story_id`（静态array 0x12044f3f8），不由此推别名优先级。
具体route producer 0x103c30140检查incoming Bool（0x103c3016c/0x103c310f4）；
false分支新建UUID/uuidString（0x103c312b4/0x103c312b8），覆盖旧entry或插入
`back_to_story_id`（0x103c31310/0x103c3132c），true跳过（0x103c31330）。
目的端BBVDDetailVC.setParams 0x103edf498先super.setParams（0x103edf53c），
helper 0x103edf56c重读CURRENT self.params（0x103edf598），nil早退（0x103edf5a4）；
桥字典→0x100028bf8（0x103edf5c8/0x103edf5dc），转换nil亦早退（0x103edf5ec）。
通过后从self.store（descriptor 0x120450320）取VDDataBloc，设flag1
（0x103edf750..0x103edf75c），转换params 0x1000f8ee8（0x103edf768）并调用
parser 0x103f138a4（0x103edf77c）。返回optional直接替换CURRENT routeParam
（0x103edf7b0），释放旧值后调用side effect 0x103ec9798（0x103edf7c4/0x103edf7c8）。
因此params/桥转换nil保留旧routeParam，parser nil则清空。上述特定outgoing route
跨导航如何成为下一次destination setParams输入经BRouter运行期容器传递，静态可核残余：disassemble 0x103ec9798 0x103ec9ecc 追outgoing route写入目标。未读取实际UUID或参数值。



伴随Bool callback的false分支已接回深度writer：manager conformance0x1182cc070
指VideoEventObserver descriptor0x119640c98，witness0x11b172f38.+8→0x101b413d0→
0x101b41294；Bool=false时恢复栈并尾调0x101b410f8（0x101b413b0..0x101b413cc），
传原position，不是只释放/无动作；true才进入下述raw2门禁。实际Story
STPlayBehaviorBloc body0x1041a41c4/virtual+0x138 slot0x11fe32bd0要求incoming x0非nil
（0x1041a41dc），更新counter后读dataBloc.current.index（0x1041a42d4），w1=0
（0x1041a42e8），调用VideoBroadcastService witness+0x18（0x1041a42f4）。具体广播
witness0x11b0f2208.+0x18→0x1009cd598→0x1009cd2a8对weak hash table取快照，filter
VideoEventObserver，解锁（0x1009cd484）后逐一witness+8同步回调
（0x1009cd4c8），传original index与Bool bit0；manager接收路径因此能进入raw4。
该service依赖实际factory0x1009cd920→0x1009cd698→0x1009cd620创建nested provider，
witness0x1202cc1e0.+0x10=0x1009cd5c4返回精确Broadcast singleton0x1210679a8与
witness0x11b0f2208；receiver边界已定位。virtual+0x138的上游是focus改变分派：
STDataBloc.setFocusItem:0x1040a7514先will helper，再写CURRENT focus
（0x1040a7588），did helper0x1040a7868接OLD item。NEW focus非nil且
new.isSameArcTo(old)=true（0x1040a78c0/0x1040a78c4）跳过；否则先发raw11 OLD
（0x1040a7a68），再raw13 NEW focus（0x1040a7ab8/0x1040a7ac0→0x10432963c）。
STBlocStore tag13跳表0x1183d23f4→0x104329aa8，捕获payload+0x10，交closure
0x10432a40c（0x104329afc）→具体bloc virtual+0x138（0x10432a43c），
STPlayBehavior实际槽为上述0x1041a41c4。payload nil不广播；非nil才读CURRENT
current.index，不能直接将focus payload当index或称每次播放进度都触发。
实际setFocusItem UI caller、generic bloc枚举准入与Bool=true生产者继续核。

currentNewGuide两个真实producer应与show分开：playerDidChangePlayModeToStory
0x101b410d0→0x101b40fcc要求nextShow<now、CURRENT videoMode==1、newGuideExp低byte
bit1为true（0x101b4104c/0x101b41050/0x101b41090/0x101b41094/0x101b410a4），
写raw2（0x101b410b0/0x101b410b4），本body不enqueue。另callback0x101b41294要求incoming
Bool bit0 true（0x101b412ec），再经同门禁写raw2（0x101b41390），上游另核。
playerDidPlayStoryAt0x101b41264传caller position到0x101b410f8（0x101b41280），同样要求
cooldown<now、videoMode==1（0x101b41180/0x101b41184/0x101b411c4/0x101b411c8），
每次读Memex公开pegasus.story_mode_v2_depth_for_story default10
（0x11789c480/0x101b41200/0x101b4120c/0x101b41210），position>=threshold且exp bit2
（0x101b41220/0x101b41224/0x101b41234）写raw4（0x101b41240/0x101b41244）。拒绝分支
不自动清旧值。StoryFeedVC.loadPlayer:isAutoPlay:isShared:0x1132e0064实际通过resolver.
pgs.objectFromProtocol(BBListPlayerBehavior)（0x1132e0650/0x1132e0668）取receiver，传
CURRENT self.storyIndex（0x1132e0684/0x1132e0688）给playerDidPlayStoryAt
（0x1132e0690）；receiver注册及同name lookup见上述桥接，loadPlayer完整上游仍另核。

close0x101b40130、open0x101b404dc及jump0x101b40934的点击日志均有独立门禁：
dismiss必须成功且new wrapper非nil（close0x101b40194/0x101b401c0；open
0x101b4059c/0x101b405c8；jump0x101b40a24/0x101b40a50）才进入字段构造。
open/jump已在这些门禁前route，close无route；缺click不等于没导航。
CURRENT newGuide>=2时用timeoutForClick*86400而非Dismiss字段，写nextShow后先清
currentOld/currentNew（0x101b40210..0x101b40248；0x101b40618..0x101b40650；
0x101b40aa0..0x101b40adc）。默认180同样是天。随后才读取CURRENT state构造trigger_type，
因此走上述清零分支的新卡点击落String3，不能沿用曝光时raw2/4映射1/2。
click_area分别close String2（0x101b402a8/0x101b402ac）、open String1
（0x101b406b0/0x101b406b4）、jump String3（0x101b40b3c/0x101b40b40）。
点击tm_card_play_state对CURRENT videoMode用Int.description
（0x101b4037c/0x101b403a4；0x101b4077c/0x101b407a4；0x101b40c30/0x101b40c58），
与曝光的enum _print_unlocked不同。`tm.recommend.play-mode-guidance.0.click`使用普通
track（0x101b40478/0x101b40878/0x101b40d2c），非trackInstantly；open本body不更新
feed mode，实际设置选择另属页面writer。旧卡内容也受new wrapper是否可用的点击门禁。


### HD2 与 Phone feedsetting 路由的解析和同名 bus 门禁

Phone BBPegasusBus.didBeenRegistered（0x113a5fbe4）也把
BBPeagasusFeedSettingVC（类拼写Peagasus，0x113a5fffc）注册到
`/pegasus/feedsetting`（0x113a6000c/0x113a60014）；这不是物理页面调用。
公共mapBiliNative0x115fb396c→_bfc_map0x115fb4064→genUrlComponent0x115fb40d0，
component.config0x115fbb4dc对无scheme路径取首非 `/` component为host
（0x115fbb6ac），其余join为path（0x115fbb6c8）。所以main与pegasus在此层host
不同、path同为/feedsetting，无parser alias证据。缓存映射0x115fb688c在existing
`:b`/`:m`且新model.feature=nil时返回error10002（0x115fb6d20），不是无条件后者覆盖；
mapBiliNative丢弃该error。外层URL改写/alias由运行期host映射transfer block产生，静态可核残余：find_callers 0x115fb2d90 穷举native transfer调用方与host映射注册点。

实际processUrl:animated:runtimeList（0x115f589f8）每次读
`dd_enable_compose_router` defaulttrue（0x115f58a5c/0x115f58a60）；true先
blockingAndExecuteKntrRouterRequest（0x115f58a70），handled true便返回
（0x115f58a78）。false/未handled才transferFromNativeScheme
（0x115f58a98）、callNativeBlock（0x115f58ab8）及正常push（0x115f58b18）。
native transfer0x115fb2d90遍历router.+0x10的host映射，匹配后调用block
（0x115fb2ec0），可产生新URL。因此前述parser无alias不代表全局无改写；有限引用
仅确认author注册0x1009ce9cc及BBMallRouter包装0x1039c1c80/0x1039c1ca4，
main/pegasus转换依赖运行期注册的transfer block；下一步：反汇编0x1009ce9cc与0x1039c1c80注册块内容核对是否含/main、/pegasus host映射，TopView `/main/feedsetting` 到HD2页由此闭合或排除。

HD2 setupModuleInitialize0x10def17c8以NSClassFromString(BBHD2PegasusBus)
（0x10def17e4）→initWithName(pegasus)（0x10def17f4）→registerSubBus
（0x10def1804）。Phone入口0x1001c8924要求userInterfaceIdiom==0及once Bool
0x121073908==true（0x1001c8974/0x1001c8994），再创建BBPegasusBus同名pegasus
（0x1001c89a4/0x1001c89d8/0x1001c8a00）。Bool来自
`infra.ue.opt.gripper.runnable` defaultfalse（0x1051301ec/0x105130208），有swift_once
缓存，不读取实际配置。registerSubBus0x1162406c4对nil/reentrant/name空/同名已存在
直接返回（0x116240768/0x116240780→0x1162407d0）；首次成功才will/register字典/did
（0x116240790/0x1162407b8/0x1162407c8）。同名注册门禁成立，正常任务另有互斥的
设备条件，不能由两个class同名推正常启动存在覆盖竞赛。

Phone的184项Runnable库存index134、slot0x1202743b0接provider accessor
0x1001c9498；conformance0x118262200→witness0x11b0bdf28的+8接lazy任务表
0x1001c88e4→initializer0x1001c87f8。8项表的首pair（0x1001c8834）为metadata
0x11b0bdf48/witness0x11b0bdda8；name槽+0x20→0x1001c8108返回
PegasusModuleModuleInitialize，execute槽+0x28→0x1001c8124→上述0x1001c8924。
priority/trigger/thread getter分别0x1001c8050/0x1001c806c/0x1001c808c；trigger
转0x105138060的moduleInitialize，thread转0x10513818c的main，不推实际执行时刻。

HD2 设置路由映射的静态闭合尝试（task-14）：路由字符串存在——`/main/feedsetting`
（cstring VA 0x11789af10，CFString 0x11d197b40）、`/pegasus/feedsetting`（0x117bba834，
CFString 0x11d1958e0）、`/main/feedsetting?setting=playStyleSetting`（0x11789c420）。
但三者的引用全为零：find_string_refs（ADRP+ADD 全 __text 扫描）0 命中、全 section
8 字节字面指针扫描 0 命中；阳性对照为同一工具对已知被引用的 CFString
`BFCApiNonZeroErrorDomain` 0x11d11be50 返回多命中（如 0x10cda0520），工具工作正常。
因此上文"反汇编 0x1009ce9cc 与 0x1039c1c80 注册块"无法在该样本闭合：两注册块为 Swift
代码且无内联 CFString，字符串可能经 Swift 字面量合并或运行期拼接，main/pegasus host→
HD2 页的 transfer block 注册内容**静态不可判**；取证需真机断点
`-[BFCRouter processUrl:animated:runtimeList:]` 的 transferFromNativeScheme
（0x115fb2d90）观察运行期注册表。

HD2的provider为index133、slot0x1202743a0，名
PegasusHDModuleGripperModule._$GripperRunnableTaskProviderPegasusHDModule。
nominal0x119488ab8→conformance0x1182648c0→witness0x11b0c0d20的+8接
0x1001d4e54→initializer0x1001d4d68，也是8项；首pair0x1001d4da4为metadata
0x11b0c0d40/witness0x11b0c0ba0。name槽接0x1001d4658的
PegasusHDModuleModuleInitialize；execute0x1001d4674经setupModuleInitialize
selector0x11f745a60转helper0x1001d4cc0。它要求idiom==1及相同once Bool==true
（0x1001d4d14/0x1001d4d18、0x1001d4d38/0x1001d4d3c），才对
BBHD2PegasusModule发送setupModuleInitialize（0x1001d4d44–0x1001d4d50），
接0x10def17c8。Phone idiom==0与HD2 idiom==1在稳定设备类型下互斥。
LegacyApp.registerModules0x105139388另以bfc_isIPad（0x1051393c8）选择
BBHD2Module.registerHDModuleWithLiveClass（0x105139434→0x10c86c154）；其6项
common modules数组index2含BBHD2PegasusModule（0x10c86c4fc/0x10c86c504），
交registerCommonModules（0x10c86c55c）。常规模块onModuleInitialize的optfalse
分支与上面opttrue Runnable分支接同一setup；不读取实际flag或启动顺序。

### VIP HD 素材请求、响应模型、入口点击与首页回执

8.89的BFCVipHDEntranceApi.requestUrl（0x10e32cd34）直接返回
`https://api.bilibili.com/x/vip/ads/materials`；requestUrlParam0x10e32cd40创建字典，
把实例.position赋给position（0x10e32cd64/0x10e32cd84），无本地MID/会员状态参数
生成；公共HTTP参数/身份头另由公共层处理。类0x1200514e0的superclass
0x120116df8为BBPgcBaseApi。这三个具体producer每次new该API并设置固定公开位置值：

| producer | position | setPosition / runAsync |
| --- | --- | --- |
| fetchHDHomeToastWithSuccess | 53 | 0x10e32d17c / 0x10e32d204 |
| fetchHDHomeTopBarWithSuccess | 54 | 0x10e32d3e0 / 0x10e32d468 |
| fetchHDVipUserCenterWithSuccess | 3 | 0x10e32d8a8 / 0x10e32d930 |

BBPgcBaseApi.init0x1120a8b0c创建BFCApiRequest存instance.+8
（0x1120a8b40–0x1120a8b50）；runAsync0x1120a8b70先setupOptions、setupHandler
（0x1120a8b80/0x1120a8b88），再requestAsync（0x1120a8ba0）。setupOptions
已有options非nil便跳过创建（0x1120a8cb0），不能把复用实例看成每次重建参数。
新options signType=0（0x1120a8cc8），读取isIgnorCache，base默认true
（0x1120a93cc）；isPostRequest默认false（0x1120a93bc），builder选requestMethod raw0
（0x1120a8dd0–0x1120a8de4），该VIP subclass已列method没有override。URL经过
checkValueToHTTPS，url params经过checkValueToStringWithDictionary，再赋options
（0x1120a8da0/0x1120a8db8/0x1120a8e4c/0x1120a8e64）。customOptions能影响cache
interval/timeout（0x1120a8d08–0x1120a8d70），不把该base默认提升为全部PGC请求常量。
cancel0x1120a8bb4转发到当前bfcRequest.cancel（0x1120a8bd0），实际运输/取消回调
仍按公共HTTP层门禁；三producer局部未保留单独公开cancel handle或自建retry。

Toast success callback0x10e32d240从response[`/`].data.list_v2取数组
（0x10e32d288/0x10e32d2b0/0x10e32d2c8），以BFCVipHDEntranceModel转换
（0x10e32d264/0x10e32d2e4）；非空只取第0项（0x10e32d310/0x10e32d320）构造
BFCVipHomeToastView.initWithModel（0x10e32d340），交捕获success callback
（0x10e32d354）。空数组交nil（0x10e32d378）；fail callback0x10e32d394同样交nil，
不在这个失败body重发。不把首次model理解为服务端排序/最优候选保证。

TopBar success0x10e32d4a4也取response[`/`].data.list_v2
（0x10e32d508/0x10e32d520/0x10e32d538），转同一model数组（0x10e32d554）；
空列表交两个nil（0x10e32d658–0x10e32d668）。非空只取首model
（0x10e32d590），按image_list原顺序枚举（0x10e32d5c8），取首isTopLeft=true
的image.url（0x10e32d60c/0x10e32d644，实际url stub0x117739a20），没有候选
用空String。仅url.length>0、track_params.vip_status确为NSString且等于公开
String `1`、完成时BFCAccount.hasLogined=true，才BFCVipAvatarIconView.initWithUrl
（0x10e32d6a8/0x10e32d6f0/0x10e32d75c/0x10e32d778/0x10e32d788/
0x10e32d7a0）；否则avatar nil。无论该avatar是否nil，非空model都会创建
BFCVipEntranceButton.initWithModel（0x10e32d7d0），callback交avatar和button
（0x10e32d7e8）。fail0x10e32d858交两个nil；这里的登录检查只门控avatar，
不是position54请求发送或整个button的登录门禁。

UserCenter success0x10e32d96c不同，取response[`/`].data.list（不是list_v2，
0x10e32d9b8/0x10e32d9dc/0x10e32d9f4）转同一model数组（0x10e32da10）。
非空创建BFCVipEntranceSectionController，把完整数组setEntrances再callback
（0x10e32da4c/0x10e32da58/0x10e32da68），不只取首项。之后取lastObject的
track_params，nil退空字典，发BFCNeuronExposureEvent公开事件
`vip.my-page.vip.entrance.show`（0x10e32da70/0x10e32da88/0x10e32daa8/
0x10e32dab8）；这个producer的曝光调用发生在交付section之后，不是已证实际
cell可见检测。空数组0x10e32dad8、fail0x10e32db00均callback nil，不构造该曝光。
两个入口的外部消费者已有下述实际调用，其他刷新/账户生命周期仍分别核。

BFCVipHDEntranceModel的container映射0x10e32db10明确5项：click_target→
EntranceClickTarget（0x10e32db34/0x10e32db40），style→BFCVipEntranceStyleModel
（0x10e32db50/0x10e32db5c），image_list/title_list→BFCVipEntranceContentModel
（0x10e32db6c/0x10e32db78、0x10e32db88/0x10e32db90），button_list→
BFCVipEntranceButtonContentModel（0x10e32dba0/0x10e32dbac）。自身还公开theme、
position、entrance_id、track_params、extra_params的accessors
（0x10e32dc58/0x10e32dc74/0x10e32dc94/0x10e32dcb4/0x10e32dcd8）。
EntranceClickTarget公开link/code/jump_type（0x10e32de68/0x10e32de84/0x10e32dea0）；
下述两个点击body使用link，未据jump_type分流。model.diffIdentifier每次调用
UUID.UUIDString（0x10e32dc04/0x10e32dc18/0x10e32dc28），不是缓存entrance_id；
isEqualToDiffableObject0x10e32dc50固定返回true，不推差分框架最终刷新行为。

顶部按钮initWithModel0x10e32e96c保存model、showAnimation=false，再buildUI
（0x10e32e9c8/0x10e32e9d4/0x10e32e9dc）。buildUI注册自身clickAction，
controlEvents raw0x40（0x10e32f118–0x10e32f128），随后以model.track_params发
`vip.home-page.top-navigation.vip-icon.show`（0x10e32f148/0x10e32f168）；
这是构建按钮阶段的曝光调用，早于Home回调安装view，未证可见检测。
clickAction0x10e32f698取model.click_target.link（0x10e32f6bc/0x10e32f6cc）；
该link stub0x10f85bb4c实际接0x1173e68a0的objc_msgSend$link，不能采用
nearest-symbol bannerLink名。link.length>0才BFCRouter.shared.processUrl:animated:true
（0x10e32f6f0/0x10e32f6f4/0x10e32f718）。不论link是否为空，后续均调用
showAnimationIfNeeded:false（0x10e32f72c），以model.track_params发
`vip.home-page.top-navigation.vip-icon.click`（0x10e32f74c/0x10e32f76c），没有
路由成功回执门禁；此body未给nil track_params另造空字典。

个人中心section.didSelectItemAtIndex0x10e3323d8没有按incoming index挑素材，
取entrances.lastObject（0x10e332400/0x10e332410），在其button_list找code
`vip_center_tip`（0x10e33242c/0x10e332440/0x10e33244c）。helper0x10e33269c
按原列表顺序比较item.code，首相等即返回item.click_target.link
（0x10e332750/0x10e332764/0x10e332774/0x10e3327a8/0x10e3327b8）；
无匹配/空列表返回空String（0x10e332724/0x10e3327d4），首匹配的nil link
不会继续找后续匹配。选择body把公开参数onlyFullScreen=String `1`追加到
所得String（0x10e332468/0x10e332470/0x10e3324a4），直接processUrl:animated:true
（0x10e3324e4），没有顶部按钮的length检查。随后取同一last model.track_params，
nil退空字典，发`vip.my-page.vip.entrance.click`
（0x10e3324fc/0x10e33251c/0x10e33252c）。两入口这里只调用公共路由，不能把
服务端link当已固定的后续HTTP endpoint；外层Compose/Native路由及目标页面请求
需另闭，点击上报不代表路由成功。append helper0x1167a6144要求传入非空NSDictionary
（0x1167a6184–0x1167a61ac），NSURL.URLWithString失败返回原String
（0x1167a61bc/0x1167a61cc→0x1167a6510）。成功时枚举allKeys，用String key和
非nil value构造`%@=%@`（0x1167a629c/0x1167a62a4/0x1167a62b8），已有query后拼
`&%@`（0x1167a62e8），此完整body无percent-encode或同名key去重。原query非空
按原String中的`?query`范围替换query（0x1167a63d8/0x1167a6558）；没有query时
把`?newQuery`插在fragment前或String末尾（0x1167a64e0/0x1167a6524/0x1167a6564）。
因此追加onlyFullScreen不会覆盖已有同名query项；空/异常URL的最终解析及push结果
未运行，不把helper调用当目标页面必定打开。

HD HomeViewController.viewDidAppear wrapper0x10024352c接implementation
0x100242d4c（call0x100243548），先super.viewDidAppear（0x100242d88）、
resumePlayView.inHomeVC=true（0x100242dbc）及续播准备（0x100242ea4），然后
topBarShowing=true（0x100242ef8），resolve/cast上述PGC BFCVipHDService后调用
fetchHDHomeTopBarWithSuccess（0x100243030）。完整implementation中没有本地
会员/登录/首次一次请求门禁；不推super或服务端同样无门禁。callback
0x100246224→0x10023f420分别weak-load原HomeTopBar（0x10023f458/0x10023f490），
存活才把avatar交0x10023f4c0、button交0x10023f764；callback body没有request
generation或Home VC身份比较。avatar helper先移除/清旧avatar再看incoming是否nil
（0x10023f4f4–0x10023f504），因此nil回执也能清旧头像角标。button helper
incoming=nil时先看旧vipEntranceBtn（0x10023f788→0x10023f9cc）；旧btn存在才
移除其view/清ivar并重设message trailing constraint
（0x10023f9e8/0x10023f9f8/0x10023fa00），旧btn也nil直接返回。incoming非nil
则移除旧btn并保存/添加新btn（0x10023f798–0x10023f7e0）。这两个helper都能
响应nil回执移除已有VIP UI，前置producer的请求失败也走两个nil回执。

HD UserCenter请求helper0x1002521d0先BFCRestrictedModeManager.enableOfMode
raw0（0x100252204），true便返回（0x100252208→0x100252318），否则resolve/cast
PGC BFCVipHDService、fetchHDVipUserCenterWithSuccess（0x10025230c）。
UserCenterViewController.bfc_tabDidGetSelectedAgain（0x1002579ac）明确调用此helper
（0x100257a28）；viewDidLoad wrapper0x1002505a8→implementation0x10024fe84
（0x1002505bc）另直接调用该helper（0x100250208），随后注册
BFCAccountNotification.addActionObserver:type:block raw7（0x1002502a4）；callback
0x100252354→0x100250504只要求weak原VC仍存活（0x100250530），再调用
（0x10025058c）。公共postAction0x11605d16c按observer.type & action筛选，沿前述
已闭action映射，mask7覆盖Login1/Logout2/Update4而不含Change8；observer callback
未按incoming action分开这次VIP刷新。不能把raw7误读成单个第7事件，也不使用
nearest-symbol AvatarConfig.destruct作为触发名。callback0x1002596a0转
0x100257ce4，把收到section打包、以main queue.async调度
（0x100257da4/0x100257edc），执行closure0x1002596dc→0x100257f34。该closure
先weak-load原UserCenterVC（0x100257f74/0x100257f78），存活才加工当前dataSource、
setDataSource和reloadDataWithCompletion:nil（0x100258458/0x100258484），没有
复读restricted mode/账号/MID/generation的门禁。不能把producer曝光记录当成
这一main queue UI更新完成。

UserCenter UI更新按CURRENT isHasVipCenterItem Bool（ivar0x1202a3580）定位第0项，
不是按creative/model身份搜索。incoming section非nil先包装ListDataSectionItem
（0x100258008–0x100258020），读取CURRENT dataSource.items（0x100258074/0x100258088）；
flag=true且数组非空先删除range[0,1)（0x100258208–0x100258214），再在range[0,0)
插入新wrapper（0x100258238–0x100258244），flag=true（0x100258254）。flag=false
跳过删除，同样插入第0项；数组空也跳过删除。删除helper0x100259824将replacement
count0交0x100259728（0x1002598a8/0x1002598bc），后者destroy旧range并memmove
后段（0x100259774/0x1002597b4），不是仅隐藏cell。单item替换helper0x100259a20
按newCount=oldCount+1-rangeLength计算（0x100259a64–0x100259a98）。结果创建新
ListDataSource、保存到VC.lazy dataSource（0x1002582d8–0x1002582e4）。
incoming=nil且flag=false只走公共reload；nil且flag=true则当前items非空时删除第0项
（0x100258378–0x100258388），创建新dataSource并flag=false（0x100258424/0x100258430）。
失败回执能移除先前VIP section；若其他writer破坏flag/第0项约定，此body不做class/
identity校验，未观察实际不一致。所有这些更新用响应完成时的当前数组，不是请求起点快照。

HD HomeViewController有实际toast调用消费者：注册段读取resumePlayView.needShowRelay
（0x100241c34），安装callback0x100246134并把disposable交原VC.disposeBag
（0x100241cb4/0x100241cf4）。callback转0x100245054，只接受incoming首byte raw0；
relay具体为BehaviorRelay<Bool?>，raw0=false/raw1=true/raw2=nil，来源见下段。
之后weak-load原VC
（0x100245098），displayedVipToast=true或bfc_vcStatus!=2均返回
（0x1002450b0/0x1002450c8），resolve BFCVipHDService并校验协议后调用
fetchHDHomeToastWithSuccess（0x1002451cc）。具体PGC注册链见下段，运行时其他
注册/覆盖仍另有边界。返回toast非nil且原VC仍存活才0x1002451f8→0x100245268；
该helper首先要求VC.vipToast=nil（0x100245290），随后保存toast并置
displayedVipToast=true（0x100245294/0x1002452a4），才继续addSubview/动画。
consumer成功回调未重新读bfc_vcStatus；未见request generation/MID比较。
nil失败/空列表不写此展示标志，不证明实际发生过后台展示或重复请求。

HomeResumePlayView reflection field descriptor0x11979935c中needShowRelay typeref
0x1196c87bc的symbolic ref经0x11b08fbc0指向BehaviorRelay nominal
0x1196aef88，后缀`ySbSgG`为Bool? generic。init把raw2交BehaviorRelay initializer
0x105065bd0并保存relay（0x10023a2b0–0x10023a2dc），不是初始false立即取素材。
producer0x105065aac转所持BehaviorSubject→Event.next构造
（0x105065ad8/0x1050e5768），不是把Bool? raw2当Rx终止事件。
续播显示准备helper0x1002395d8先读BFCAccount.hasLogined及needShow==true
（0x100239608/0x100239620）；成立才new BBHD2PegasusResumePlayApiHelper并
requestLatestHistoryWithHandler（0x10023963c/0x1002396e4）。不成立直接发
didBecomeActiveTriggle ? nil : false（0x100239714–0x100239730），再清该flag。
history callback0x1002397d0先needShow=false（0x1002397f4）；返回model=nil时
同样发上述nil/false（0x100239840–0x10023985c），model非nil取item交
0x100238330（0x100239938/0x10023994c）。该render helper中item.uri非空时准备
续播view并发flag ? nil : true（0x1002387b4/0x1002387bc/0x1002387d8–0x1002387f4）；
uri nil/空时走隐藏helper0x1002389c0，再发flag ? nil : false
（0x100238878–0x1002388b4）。这限定toast入口在普通续播不可展示的false分支，
不是每个history响应都请求VIP；具体helper的发送/错误加工见下段。
didBecomeActive0x100239754仅parentView非nil且inHomeVC==1才置该flag=true
（0x10023976c/0x100239780/0x100239790）并再调用准备helper
（0x1002397a8）；这些flag=true路径发nil，会被toast subscriber排除。
原VC存活/status/展示标志门禁仍独立，不把账户检查提升为VIP请求自身登录必需。

运行可达性与uri消费末端已闭合：准备helper0x1002395d8的直接BL调用方全量扫描
仅两处——didBecomeActive 0x1002397a8与HomeViewController.viewWillAppear:
0x100242ea4，后者在self.view非空检查（0x100242e9c cbz）之后调用，不推该页每次
出现必然发请求（仍过hasLogined/needShow门禁）。`requestLatestHistoryWithHandler:`
的selref0x11f784aa0在全__text的数据引用唯一命中0x1002396d4（即该helper体内），
无第二发送方，也无其他helper复用此writer边。点击消费：clickToPlay
0x100239240（Neuron `main.homepage.resume-play-popup.0.click` 上报体
0x100239268）转0x100238fc8：print `HomeResumePlayView: click to play`
（0x100239018），读自身uri ivar（slot 0x1202a2000+0x3c0），nil跳过路由
（0x100239084 cbz→0x100239224），非nil桥String交BFCRouter.shared
processUrl:animated:（animated=1，0x1002390c4），随后隐藏helper0x1002389c0并
发点击Neuron事件；路由成功与否不被等待。

BBHD2PegasusResumePlayApiHelper.requestLatestHistoryWithHandler0x10c86cd38
另有CURRENT BBHD2MCPlayerSettingPreferences.enableResumePlaying门禁
（0x10c86cd74/0x10c86cd84）；false直接handler(nil,nil)
（0x10c86ce30–0x10c86ce40），不发RPC。true创建LatestHistoryReq，business固定
`archive`（0x10c86cd90/0x10c86cda0），取playerPreloadParams并setPlayerPreload
（0x10c86cda8/0x10c86cdc0），调用History.latestHistoryWithRequest
（0x10c86ce18）。class方法0x115e1e804先取defaultService（0x115e1e83c）；
defaultService0x115e1e014每次alloc并init host `grpc.biliapi.net`、isRest=false
（0x115e1e024/0x115e1e028/0x115e1e02c），而非defaultRestService。
initializer0x115e1dee0以package `bilibili.app.interface.v1`、service `History`
创建Moss service（0x115e1df38/0x115e1df40/0x115e1df4c）。instance method
0x115e1e778交LatestHistoryReply class、所持service及方法名`LatestHistory`
到BFCMossServiceWrapper.handleRpcRequest（0x115e1e7c0/0x115e1e7d0/0x115e1e7e0）。
这闭合具体Moss入口，实际metadata/transport沿公共层；helper未保留cancel句柄。

preload getter0x10c86d08c首次nil才new并缓存参数对象（0x10c86d09c/0x10c86d0b4），
首次写qn、fnver=0、fnval及fourk（0x10c86d0d4/0x10c86d0e0/0x10c86d0f8/
0x10c86d110）；qn从bus `main/qn_playurl`结果的qn取long，负值归0，无结果0
（0x10c86d1a0/0x10c86d1c0/0x10c86d1c4/0x10c86d1cc），fnval来自supportFnval，
fourk来自isSupported4K。每次getter都会重新读httpsPlayurlEnabled，true写
forceHost=2，false=0（0x10c86d12c–0x10c86d140），不能把整个preload称每次全重建。
前述Home准备每次new helper；writer边已枚举闭合：selref0x11f784aa0全__text唯一
引用在0x1002396d4（Home准备helper体内），无其他复用方。

RPC callback0x10c86ce60若error非nil且带bapi_status，构造NSError：domain取旧error，
code取status.code，NSLocalizedDescriptionKey取status.message、nil退空String
（0x10c86ceb8/0x10c86cedc/0x10c86cf00/0x10c86cf2c/0x10c86cf48/
0x10c86cf84），handler(nil,error)（0x10c86d024–0x10c86d034）；无status保留原error
（0x10c86d018）。error=nil且reply.items非nil才构造BBHD2HomeResumeReplyObject
并handler(model,nil)（0x10c86cfc4/0x10c86cfd0/0x10c86cfe8/0x10c86d004）；
items=nil跳过handler（0x10c86cfd0→0x10c86d040），不是在此body主动交nilmodel。
wrapper initializer0x10c86cbd0把reply.items映射到自身item，并复制hasItems/scene/
rtime/flag（0x10c86cc18/0x10c86cc38/0x10c86cc44/0x10c86cc64/0x10c86cc70）；
这里的items不是数组count门禁：LatestHistoryReply.descriptor0x115e21240交4项
field table0x120844230（0x115e21288/0x115e2128c），其items field1的class明确
BAPIAppInterfaceV1CursorItem，是单message；scene field2、rtime field3、flag field4
依次在0x120844250/0x120844270/0x120844290，raw dataType为14/8/14。
LatestHistoryReq.descriptor0x115e211d4交2项表0x1208441f0
（0x115e2121c/0x115e21220）：business field1/raw14，playerPreload field2/raw15
（entry0x120844210）的class为BAPIAppInterfaceV1PlayerPreloadParams。
items entry的raw15亦与该单message相同。GPBMessage.resolveInstanceMethod的getter
type table0x1193a5cda/base0x116798670（0x116798664/0x116798668）已按binary解码：
raw8→0x116798adc/getInt64，raw14→0x116798884/getString，raw15→
0x116798974/getMessage。所以business/scene/flag为String、rtime为Int64。
message getter block0x116799ec8转helper0x116792e84：raw15/16读取storage指针
（0x116792eac–0x116792ecc），空则按field.msgClass alloc/init
（0x116792ed4/0x116792ed8），保存父对象/field并以原子compare/store安装
（0x116792ee0/0x116792eec/0x116792ef0–0x116792efc）；竞争已有值则释放新对象、
返回已安装对象（0x116792f50–0x116792f64）。正常message getter缺值会自动创建
CursorItem，不以hasItems为此getter门禁；reply=nil或异常对象/分配路径仍分开。
因此helper的items=nil跳过callback是代码分支，不能据此推正常空PB响应必然走该分支。
wrapper虽复制hasItems，却未在前述render前用它拦截。CursorItem.descriptor
0x115e2094c交16项表0x120843628（0x115e20994/0x115e20998），uri field7为
String/raw14（entry0x1208436e8），非oneof。descriptor flags0x1c的bit0=0，
FieldDescriptor constructor0x116775284不载入显式defaultValue
（0x1167752c4/0x116775308）；String getter block0x116799eb8也转0x116792e84，
无presence走field.defaultValue（0x116792f14/0x116792f38）。defaultValue getter
0x1167754cc对非repeated/raw14且default nil返回空String
（0x1167754dc/0x1167754f4/0x116775500）。因此正常空CursorItem.uri缺值会为空，
接前述render的不可展示false/nil分支，而不是helper.items=nil分支；reply/error与
Home status/active flag仍有独立门禁，不推服务端所有空数据必然请求toast。

Toast自身还有独立操作/计时链。initWithModel0x10e33286c保存model，buildUI、
updateUI并autoDismiss（0x10e3328c8/0x10e3328d0/0x10e3328d8/0x10e3328e0）。
buildUI给actionButton/closeButton分别注册jump/closeAction，controlEvents raw0x40
（0x10e333798/0x10e3337a4/0x10e3337c8/0x10e3337d4）。updateUI按button_list
原顺序取首code=top_reminder_bubble_button_title的click_target.link作为jumpUrl
（0x10e3338c4/0x10e33390c/0x10e33391c/0x10e333950/0x10e333960/
0x10e333994），无匹配空String。随后发Neuron曝光
`vip.home-page.avatar.renew-toast.show`（0x10e333b50/0x10e333b5c）；track_params.
count>0时另交BFCVipMaterialReporter.reportExposureEvent（0x10e333b94/
0x10e333bac/0x10e333bf4）。均在view初始化时，早于Home安装view，不证明物理可见。
jump0x10e332948仅jumpUrl.length>0才processUrl:animated:true并dismiss
（0x10e33297c/0x10e3329b8/0x10e3329d0），无论空/非空都发Neuron事件
`vip.home-page.avatar.renew-toast.click`（0x10e332a04/0x10e332a10），不等待路由成功。
closeAction0x10e332a30先dismiss（0x10e332a44），track_params非空才mutableCopy并
覆写code=close_button（0x10e332a84/0x10e332aac/0x10e332ac8/0x10e332ad8），
交素材reportClickEvent（0x10e332b08）；不是同一个Neuron jump事件。

autoDismiss0x10e332cfc以dispatch_time的delta=0xee6b2800（4,000,000,000ns）
排main queue weak callback（0x10e332d1c–0x10e332d24、0x10e332d6c/0x10e332d78），
callback0x10e332d9c调用dismiss（0x10e332db4）。此4秒计时起于init，不起于首页
addSubview；未见该body保存可取消timer。dismiss0x10e332b40先weak动画alpha=0
（0x10e332c58/0x10e332c6c），completion只在weak view及superview均存在时移除
shapeLayer/清引用/移除view（0x10e332c90/0x10e332cb4/0x10e332ccc/
0x10e332ce0/0x10e332ce8）。dismiss stub0x10f849448实际接objc_msgSend$dismiss
0x1172c9580；该移除body没有清HomeVC.vipToast或displayedVipToast，其他外部writer
仍可另核，不把关闭动作推成下一次即可再展示。

素材reporter的无eventId overload0x11465ead8/0x11465eae4传空String，核心补公开
event_id为vip.vip-operation-position.tips-track.0.show/.click，并写event_type
show/click（0x11465eb34/0x11465eb70/0x11465eb88、0x11465ec00/
0x11465ec3c/0x11465ec54）。input要求NSDictionary，再mutableCopy；report0x11465ec88
读取调用时currentUser，将mid、vip_status、vip_type、vip_due_date各转String并
覆写同名键（0x11465ed24/0x11465ed8c/0x11465ede4/0x11465ee3c），这里仅分析
取值指令，不读取真实身份。单事件包装数组交report:completion
（0x11465ee70/0x11465eed4），后者创建BFCVipMaterialReportApi并requestAsync
（0x11465f2d8/0x11465f2e8）。重发批次走同一API constructor但不再经过上述
单事件账户覆写body，不能称重发自动重取MID。

API factory0x11465e678把事件数组放private_params，另取buvid
（0x11465e6e4/0x11465e710），base URL固定
`https://api.bilibili.com/x/vip/ads/material/report`（0x11465e734），requestMethod
raw2（0x11465e7b8），按公共builder先拼query到URL再POST
（0x116095550/0x116095554→0x1160955d4/0x116095618→0x1160956d0），设置
requestInjection（0x11465e818）。injection0x11465e900
mutableCopy原request，向捕获字典加filtered=String1/0，来自CURRENT
BFCAppPreferences.inReview（0x11465e948/0x11465e960/0x11465e970）；JSON序列化
options0/error nil（0x11465e990），赋HTTPBody及Content-Type
application/json; charset=utf-8（0x11465e9b0/0x11465e9d0）。completion handler
0x11465e9e8交Booltrue，error handler0x11465ea00交false，不在这里另查响应业务code。

单事件结果callback0x11465ef74锁reporter：false时failedDatas.count>=20先移除第0项，
再append捕获事件（0x11465f024/0x11465f044/0x11465f068）；true且failedDatas非空、
reportingFailedDatas=false才置true并reportFailedDatas
（0x11465efcc/0x11465efdc/0x11465eff0/0x11465eff8）。这是后续成功触发的补报，
未见此body自设重试timer。reportFailedDatas0x11465f0b0复制当前队列作batch
（0x11465f100/0x11465f174）；batch callback0x11465f1c8只有true时从当前队列
removeObjectsInArray(batch)并置reportingFailedDatas=false
（0x11465f200/0x11465f21c/0x11465f230）。false分支直接unlock
（0x11465f200→0x11465f234），这个body不复位flag、不移除batch；其他writer/reset
其他writer/reset需全类反汇编枚举，不推实际永久卡住或账号清理行为；队列持久化与其他物理reporter入口为下一步：disassemble 0x11465ea74 0x11465f300 全类 + query_index '*FailedDatas*' 30。
shared0x11465ea18使用once token0x120da1b20及global0x120da1b18，initializer
0x11465ea48 alloc/init并存global（0x11465ea58/0x11465ea64），不是每个事件新reporter。
init0x11465ea74新alloc队列对象、存.+0x10（0x11465eab0/0x11465eab8），此body不从
磁盘恢复；failedDatas getter/setter0x11465f324/0x11465f32c仅读/strong-store该槽，
reportingFailedDatas getter/setter0x11465f338/0x11465f340仅读/写.+8 byte；destruct
清.+0x10（0x11465f348/0x11465f350）。完整text的直接BL/B到flag setter及其stub
0x11760ff40仅命中上述0x11465eff0/0x11465f230，selref0x11f72ee78的有限ADRP邻接
扫描未见另外调用；未闭动态selector/其他寻址/直接offset writer，保留reset缺口，
不能把未找到的调用当全应用无复位证明。

reportFailedDatas在当前queue为空时直接返回（0x11465f0e8→0x11465f198），也不清flag。
batch持有拷贝数组strong、reporter weak（0x11465f118/0x11465f154/0x11465f15c/
0x11465f164）；completion load weak nil跳过队列/flag修改
（0x11465f1e4/0x11465f1ec）。成功清掉batch后没有递归drain较新事件。
once thunk 0x117052b14 materialize token并tail dispatch_once（0x117052b18/0x117052b24），
不是reset方法；有限global引用扫描只证明已观察initializer writer，不排除其他寻址。

额外业务入口已按实际reporter.shared receiver确认：

| 入口与触发 | 输入/门禁 | dispatch边界 |
| --- | --- | --- |
| PGCDynamicVipNativeModule.dynamicCallMethod:args:completionBlock: 0x111fe9bf8 | method必须`report`（0x111fe9c24）；eventId必须NSString且非空（0x111fe9cac–0x111fe9cbc）；eventType integerValue为0/1 | 0→ExposureWithEventId（0x111fe9d94），1→ClickWithEventId（0x111fe9dbc），其余skip；completionBlock在此body不调用，非API ACK |
| BBStoryFreeBandWidthComponent.willDisplay 0x104204628→0x104204120（0x10420463c） | contentView.hidden则skip（0x10420420c/0x104204210）；weak item.freeFlowToast.track_params必须存在（0x104204370/0x10420439c/0x1042043d8） | shared（0x104204448）→reportExposureEvent（0x104204468），present dictionary无count>0门禁；同时安排8秒后close，计数defaults不是failedDatas持久化 |
| 同Story freeClicked 0x104205720→0x104205358（0x104205734） | button_uri非空才route（0x104205414/0x104205428/0x10420547c）；URI缺失仍close（0x1042054a8）后尝试读track_params | shared（0x10420553c）→reportClickEvent（0x1042055a0）；不以route成功为report门禁，不据此把普通close或8秒autoclose算click |
| BBPgcDetailPayView strictExposure block 0x11212bdd4 | weak view及reportData非nil（0x11212bdf0/0x11212be0c） | reportExposureEvent（0x11212be44）后本地true，不等待API结果 |
| BBPgcPhoneBangumiDetailDialogView strictExposure block 0x1122469b4 | weak view及ePWidgetVM.report.extends非nil（0x1122469d4/0x112246a20），converter 0x11263c9ac | reportExposureEvent（0x112246a9c）后本地true，converter error/nil可仍使reporter拒绝输入 |
| BBPgcPlayerDialogViewWidget strictExposure block 0x112507e40 | dialogViewModel.report.extends（0x112507e60/0x112507eac） | 同converter→Exposure（0x112507f28） |
| BBPgcPhoneBangumiFollowVipTipHeadView strictExposure block 0x111f4de08 | currentTipModel.report.extends | Exposure（0x111f4decc） |
| BBPgcPhoneBangumiInfoPayForPlaybackHintView strictExposure block 0x11224c0ec | weak view、presenter及respondsToSelector:payForBangumiHintViewStrictExposureData（0x11224c108/0x11224c120/0x11224c158） | 取得data（0x11224c170）→Exposure（0x11224c1a4），本地true（0x11224c1b8）未检查data/接受/服务器成功 |
| BBPlayerVipTipsWidget didAppear 0x104b05504→0x104b050b4、closeAction、vipAction | 当前vipInfoModel.track存在（0x104b05358/0x104b05380/0x104b05944/0x104b0596c/0x104b05f6c/0x104b05f94） | ExposureWithEventId（0x104b0542c），两个ClickWithEventId（0x104b05a14/0x104b0603c）；显式eventId不同于默认overload，物理target/appearance链见后文 |

Dynamic输入extendedFields可选非空JSONString，经pgcdynamic_dictFromJSONString
（0x111fe9d04）；枚举（0x111fe9dfc）保留NSString值，其他仅respondsToSelector:
stringValue者转换（0x111fe9e40/0x111fe9e68/0x111fe9e78），不支持值skip。
缺eventType依ObjC nil integerValue为0，不据此称required-field校验。
Dialog converter 0x11263c9ac使用UTF8/raw4及JSON options1/NSError
（0x11263c9c4/0x11263c9ec），error/nil返回nil（0x11263ca04/0x11263ca2c），
因此strictExposure localtrue与合法event及服务器成功必须分开。上述strictExposure
callback的可见性/dwell调度安装及两种具体UI入口见后文，其他触发不从方法名推已执行；统一身份覆盖及失败队列
仍沿此前reporter链，未读取真实eventId、身份或队列。

Player VIP tips的曝光入口实际是didAppear: 0x104b05504→Swift body 0x104b050b4
（0x104b05520），super.didAppear（0x104b050fc）后走前述track→ExposureWithEventId
（0x104b0542c）；0x104b051e0仅该函数中段，不能当entry做caller归因。
initWithContext 0x104b03e08→0x104b062f0（0x104b03e24）在super.initWithContext后
buildUI（0x104b06380/0x104b06390→0x104b03e44）。buildUI取lazy closeBtn/vipBtn
（0x104b03ee4/0x104b03f68），各factory把widget作为target，分别注册closeAction
（0x104b03848/0x104b03858/0x104b0385c/0x104b03860）及vipAction
（0x104b03bbc/0x104b03bcc/0x104b03bd0/0x104b03bd4），controlEvents均raw0x40。
这接通两种物理点击到上述material reporter；不概括其他dialog close/desc按钮。

strictExposure的调度和本地去重：PayView.pgc_strictExposureEvent 0x11212bd14创建
BBPgcStrictExposureEvent（0x11212bd34/0x11212bd38），把weak-view callback
0x11212bdd4传initWithTriggerHandler（0x11212bd84）；event.init 0x114669a2c保存handler
（0x114669a78）。实际collector 0x114669be4枚举对象，要求protocol/selector门禁
（0x114669cbc/0x114669cd0/0x114669d08），已有filterKey则skip
（0x114669d50/0x114669d60），取相关view并fullyVisible检查（0x114669d78），
event.handler非nil（0x114669da4/0x114669db0）才记录filterKey、加入filteredKeys
（0x114669dbc/0x114669de0）并创建rawflags16 cancellable dispatch block
（0x114669e84/0x114669e88）。event关联源object（key0x120da1b78/policy1，
0x114669eb4），dispatch_time偏移1,000,000,000ns再main dispatch_after
（0x114669eb8/0x114669ec4/0x114669ecc/0x114669efc）。delayed callback 0x11466a06c
要求weak collector/source/event/view都有效（0x11466a0b4..0x11466a0c0），再次同view
fullyVisible（0x11466a0c8）才执行handler（0x11466a0e8）；handler的本地Bool直接写
event.collected（0x11466a0ec/0x11466a0f4）。false移除filterKey
（0x11466a104/0x11466a13c），最后清源object association（0x11466a164）。这是两次
可见性观察间隔名义1秒，不是持续可见一秒/服务器确认；localtrue可使collector去重，
即使此前event JSON转换或reporter接受失败。

UIView.pgc_checkFullyVisibled 0x11466967c实际检查self/immediate superview.hidden、
superview/window存在（0x1146696a4/0x1146696bc/0x1146696d8/0x11466971c），把self
frame及superview bounds转换到window坐标（0x114669788/0x114669804），与window/
superview bounds求交（0x114669860/0x114669894/0x1146698b8），交集非empty/null且
width/height等于转换后的frame（0x1146698cc/0x1146698e4/0x114669914/0x11466991c）。
本body不证明兄弟遮挡、alpha、前台scene、所有祖先hidden或实际用户注意力。
cancelEventsForMayReportableObjects 0x11466a21c删除filterKey、取消dispatch block并清
block/association（0x11466a304/0x11466a348/0x11466a35c/0x11466a370）；这不是网络
task cancel，也不撤销此前已调用reporter。

具体UI collection入口之一是SeasonDetailVC.videoPlayerListViewDidReload
0x112007de4→collectVipStrictExposure（0x112007e14→0x112007e30）：先交可选per-VC
batch，再交videoPlayerListView.visibleCells（0x112007ed8）到shared collector
（0x112007ef0/0x112007f08）。另FollowSubVC.viewDidAppear 0x111f37aa0→collect
（0x111f37b5c→0x111f3b698），派weak main callback（0x111f3b6fc），要求vipHeadView
存在且CURRENT tableView.tableHeaderView pointer==vipHeadView
（0x111f3b768/0x111f3b7c4/0x111f3b7c8），才交该view到同collector
（0x111f3b824），接前述VipTipHeadView callback。其他controller/cell触发仍按独立
证据核查，未由这两个入口覆盖全部VIP业务。

具体绑定由BBPgcPadModule.setupModuleInitialize（0x10e32c794）取得
BFCResolver.pgc（0x10e32c7c4），把BFCVipHDServiceImp class（0x10e32c7d8）
registerClass:forProtocol:BFCVipHDService（0x10e32c7e8/0x10e32c7f0）。Home使用
0x104e4de1c、ObjC pgc getter0x104e4de5c经0x104e4daf4使用相同once token
0x120a33510/global0x1210730f0；initializer0x104e4de08→0x104e4df6c包装
SwiftResolver到ResolverBridge。其supplier0x104e4eba4另once创建SwiftResolver
（0x104e4ec88→0x105127b08，global0x121073168），未按请求新建scope。
registerClass0x104e4e1d8取NSStringFromProtocol（0x104e4e22c），转SwiftString
作为key交0x105127fd4（0x104e4e28c）；closure0x104e4e89c→0x104e4e1d0→
0x104e4e170以NSStringFromClass生成所注册class的String（0x104e4e188→
0x107c2c064→0x10f8976c8→0x11711ada4）。classFromProtocol helper
0x104e4e528同样以NSStringFromProtocol（0x104e4e548）查0x105129240
（0x104e4e590），非nilString经NSClassFromString（0x104e4e5c8）变回class。
因此Home/注册端两个静态protocol对象虽地址不同，均名BFCVipHDService并按名称
查找，不能因指针不同否认该绑定。class与object注册槽/覆盖规则仍分别核对，
不宣称运行时永无其他registration。

BBPgcPadModule.name（0x10e32c6f0）为BBPgcPadHD；常规模块
onModuleInitialize0x10e32c6fc读runnableTaskOptEnable（0x10e32c718），true直接
返回（0x10e32c72c），false才发setupModuleInitialize（0x10e32c774）。opttrue替代
入口已接：184项Runnable库存index129/slot0x120274360为
PGCPadGripperModule._$GripperRunnableTaskProviderPGCPadGripper；nominal
0x119488ee8→conformance0x118265280→witness0x11b0c1530的+8接
0x1001d9288/lazy initializer0x1001d9200。3项任务表首pair（0x1001d923c）为
metadata0x11b0c1550/witness0x11b0c14a0；name槽+0x20→0x1001d8f1c返回
PGCPadGripperModuleInitialize，execute槽+0x28→0x1001d8f38→0x1001d92c8。
后者要求idiom==1（0x1001d93ac/0x1001d93b0）及相同runnable once Bool true
（0x1001d93b4/0x1001d93d0），才发送BBPgcPadModule.setupModuleInitialize:
（0x1001d93d8/0x1001d940c），接上述VIP class注册。其余两项名称为
PGCPadGripperApplicationInitializeFinished（0x1001d8fe8）及
PGCPadGripperHomePageInitialized（0x1001d9130），各selector经0x1001d9158同样
idiom1/opttrue门禁（0x1001d91ac/0x1001d91d4）。常规模块的全局注册顺序、
动态DI覆盖/实际flag需穷举任务表引用与运行期Gripper图，不能从库存推每次启动所有任务无条件执行；下一步：find_data_refs_root 0x11b0c1550 0x11b0c14a0 穷举任务表引用方。

### PGC 番剧详情、播放入口与 follow/付费请求族

PGC 番剧详情 base 请求构造（证据：DerivedData/Validation/team-c4/findings.md 块1.1）：
`-[BBPgcPhoneBangumiUniversalApi option]`0x1121d91f0 lazy 构造 BFCApiOptions
（0x1121d9228），`setBaseUrl:` CFString 0x11d290df0 =
`https://api.bilibili.com/pgc/view/v2/app/season`（0x1121d9244），
`setRequestMethod:` 0 即 GET（0x1121d9250），响应映射
`BFCApiModelDescription modelWith:'/data' mappingClass:BBPgcPhoneModelBangumiSeasonM2
isArray:0`（0x1121d9280）。分集 tab：`-[BBPgcPhoneBangumiEpsTabApi requestUrl]`
0x1121ec94c → `/pgc/view/v2/app/eps`（候选引用 0x1121ec950）。播放入口：
`+[BBResolverPGCHelper resolverWithPars:completeBlock:]`0x114a1d45c →
`/pgc/player/api/playurl`（候选引用 0x114a1dc78）；同族还有
`/pgc/player/hls/playurl`、`/pgc/player/api/playurlproj`、
`/pgc/player/api/v2/cache/play` 及 gRPC `bilibili.pgc.gateway.player.v1/v2`。
追番族均指 `/pgc/app/follow/add`（字面量 0x1177fa8e0；del 对应 `/pgc/app/follow/del`）：
BBPgcPhoneBangumiFollowSeasonApi requestUrl 0x1120d2a7c、
`+[BBPgcTripleLikeApi followSeason:isFollow:flag:reserve_id:completionBlock:]`
0x112402074、`+[BBDFApiHelper ogvAddWithSeasonId:withAdd:completion:]`0x10e7b68ec、
`+[BBHD2PhoneSearchFollowBangumiApi requestFollowWithStatus:seasonId:...:]`
0x10de7428c、`+[STDramaFollowButton followSeason:isFollow:completion:]`0x1042b8730。
PGC 付费下单：`+[BBPgcPhoneStore requestWithSeasonModel:sceneMode:extraParams:
completeBlock:error:]`0x112132dc8 → `/pgc/pay/api/season/order/create`（候选引用
0x112132e50）。

PGC 详情 params 字段级（0x1121d8964，证据 team-c11）：params 共 10 键
（dictionaryWithObjects:forKeys:count:10，0x1121d8bb8）——`season_id`（入参
longLong→stringValue，0x1121d8a8c）、`track_path`（requestFrom，缺省 `''`）、
`from_spmid`（缺省 `default-value`）、`spmid`（常量 `pgc.pgc-video-detail.0.0`，
0x11d288ef0）、`from_av`（缺省 `''`）、`autoplay`（缺省 `'0'`）、`trackid`
（缺省 `''`）、`pgc_play_abtest`（BFCABTestConfig
getValueByName:'pgc_play_abtest'，0x1121d8a10）、`is_show_all_series`
（BFCMemexABTest hitExperimentalGroupForKey:
'ogv_player_detail_all_series_abtest'→'1'/'0'，0x1121d8a68）、
`ugc_ogv_unity_exp`（BBPgcBaseHelpTools.shared hitSeasonDetailCommonUI→'1'/'0'，
0x1121d8b94）；adExtra 非空追加 `ad_extra` 键（0x1121d8c08）。referSeasonId ivar
（0x11f86f9fc）非 nil 时追加请求头 `bili-referer:
bilibili://bangumi/season/%lld#recommend`（0x1121d8c68–0x1121d8cb8）。
响应侧 SeasonM2 mapper 0x1121db1b4：newest_ep←new_ep、season_type←type、
season_status←status、total_ep←total、limitPlay←limit、roomInfo←room_info、
ipPhoneInfoList←earphone_conf.sp_phones；container 泛型 0x1121db2a8 覆盖
stat/rights/publish/rating/user_status/payment/up_info/episodes/seasons（递归
SeasonM2）/section/modules/reserve/dialog 等 33 键；payment 子模型
BBPgcPhoneBangumiPayment 字段 price/vip_promotion/vip_first_promotion/
quality_guide/vip_badge_info/vip_pay_link/pay_type/pay_tip/dialog/
dialog_type_map/coupon_info/report_type/vip_report/report/order_report_params
（0x1121e0948–0x1121e0cc4）。

### 会员状态读取与权益提示

`+[BFCVipUserFaceApi requestWithMid:isSync:completeHandler:errorHandler:]`
0x114662488 构造 BFCApiOptions `setBaseUrl:`
`https://api.bilibili.com/pgc/vipinfo/get`（0x1146624fc，反汇编 0x114662430–0x114662520）
——大会员资料读取走 PGC 侧接口；请求 params 单键 `mid`（dictionaryWithObjects:forKeys:count:
0x1146625a8），响应 `modelWith:'/data' mappingClass:<槽 0x11f7b5c38> isArray:0`（0x11466250c–
0x11466252c），classref槽0x11f7b5c38由symtab识别为NSDictionary，经objc_opt_class
实际传给mappingClass。原qword0→不可判推论撤回；无需用候选CommonGetUserVipInfoResp
替代已证binding（root-static-remaining/findings.md）。姊妹requestUploadWithMid:
probability: 0x114662720走/x/vip/user/unsign_probability/hand。
/x/vip/privilege/remind和/x/vip/v1/order/status使用Swift具体表单构造，前者选中
rights_type，后者两个producer有不同scene来源，不能凭nearest ObjC标签说全由
VipSVGA动画结束触发。状态消费模型VipStatusModel
（status/orderNo/dialog/payment_success_page，getter 0x1043d2390–0x1043d240c）。
冻结检查 `+[BFCVipFrozenTool checkFrozenWithIsFrozen:success:]`0x1043e3d34 对应
`/x/vip/v1/frozenTime`、`/x/vip/v1/unfrozen`。全局账号态布尔读取点
`-[AccountServiceImp isVip]` **0x104c6e864**（team-33 修正笔误 0x10c6e864）：链路
`BFCAccount.currentUser`（selref 0x11f651000+0xc88）→`vip`（0x11f77e000+0x7d8）→
`status`（0x11f754000+0xfb8）→ `cmp x20,#1; cset w0,eq`（0x104c6e8f4–0x104c6e8f8），
即 `currentUser.vip.status == 1`；相邻 `-[AccountServiceImp vipStatus]` 0x104c6e9d0。
其他静态可定位 VIP UI 消费点：`-[BBPhoneMineVipCardV2VM vipStatus]` 0x10f3a1410、
`-[BBHD2MPDescPhoneUserVipModel vipStatus]` 0x10cb6f364、
`+[BBPgcPhoneBangumiPayVerify userIsNeedPayWithPayStatus:EpStatus:isVip:]` 0x11212dab0。
VIP 两条 Swift 表单现已闭合（root-static-remaining/findings.md）：
`privilege/remind` raw3 的producer0x1043f7e00..7f80要求选中rights String非空，
构造单键rights_type并按VipPrivilegeResponse映射。
`order/status` raw6 的VipMallPayService body0x104404980从输入字典取非空vipOrderNo，
构造order_no（该值）、app_id（服务params或空）、scene（服务params或vipmall）；
捕获后经0x104405920→0x1043fe644→VipStatusModel wrapper→generic builder发送。
另一个status producer 0x1043ff898..ffd58 同样构造order_no/app_id/scene：
order_no取vipOrderNo，app_id取弱owner的模型String，scene枚举0/1/2/3/4/5/6/7
分别映射ipad/mini/story/routine/privilege/play_page/extra_release/fast_track，其它
为tvvip_preview；owner消失填空。raw6经0x104402314→同VipStatusModel builder。
原0x104401dd4只是generic builder的endpoint选择调用，nearest ObjC标签不能证明
请求属于VipSVGAView。Swift值类型不等于静态不可追；实际支付状态/其它producer另验。
failedDatas/reportingFailedDatas的本类完整body也已核：普通失败最多保留20条，
普通成功且未补发才置flag并补发batch；补发成功0x11465f21c删除batch、230清flag，
补发失败234不清flag。所选类未见持久化或失败复位，但不排除外部账号/动态setter。


### 漫画/商城/支付/游戏/创作请求族入口


**番剧 episode 请求与 payment 子模型的补充（8.89 静态）**：`optionForEpisodeRequest:`
0x1121d8d50–0x1121d91f0 逐槽解出 episode 键集 `ep_id`/`product_id`/`product_type`/`sp_id`/`server_name`（取
`freeBandwidthServerName`）/`trackid`/`track_path`/`from_av`/`from_spmid`/`spmid`/`autoplay`/`ad_extra` 与三个 AB 键，
`sp_id`/`product_*` 经 `numberWithLongLong:`+`stringValue`，组装用 `dictionaryWithObjects:forKeys:count:`，并按 `referSeasonId` 加
`bili-referer` 头。payment 容器 0x1121e09d4–0x1121e0ae4 的子映射：`dialog`→`BBPgcPhoneBangumiSeasonDialog`（含 `dialog_type_map`）、
`pay_type`→`BBPgcPhoneBangumiSeasonPaymentPayType`、`coupon_info`→`BBPgcPhoneModelBangumiCouponInfo`、`vip_badge_info`→`BBPgcBadgeInfo`，
另有 `BBPgcPhoneBangumiSeasonPaymentDetail` 与 `pay_tip`。商城子类 path 只取到 `https://mall.bilibili.com/mall-c`（0x103336e94、0x103337144）
与 `https://mall.bilibili.com/mall-ugc`（0x1033e7f84）；其余子类的符号索引地址多为 Swift 桥接 thunk，需按真正实现入口重取。

漫画走 Twirp（POST JSON RPC，host manga.bilibili.com）：`+[BBComicRequest
**商城域 path 全貌（8.89 静态字符串表穷举，48 条）**：`mall.bilibili.com` 下可分四类——① **API 基址**：
`/mall-c`（0x179e2596）、`/mall-ugc`（0x179ad6e9）、`/community-hub`（0x1799da38）、`/mall-c-search`（0x179e256e）、
`/mall-dayu`（0x1802a2bd 为 `/mall-gateway%@` 前缀，基址 0x179e256e 区）、`/mall-marketing-c`（0x18029f4a）、
`/mall-up-search`（0x17f95d61）、`/magic-c-search`（0x1802e066）、`/mall-c-community`（0x17f95dbd）；
② **具体 API 路径**：`/mall-c/cart/na/sku/new`（0x1802024b）、`/mall-c/picture/image`（0x1806c964）、
`/mall-ugc/picture/upload`（0x179afab8）、`/mall-c-search/user/ar/list`（0x179c4078）、
`/mall-c-search/activity/mini-game/status`（0x17892508）、`/community-hub/activity/support_rank/operate`（0x179b0568）、
`/mall-dayu/open/shield/native/check`（0x1803766e）、`/mall-search-items/items/panel/spu/info`（0x1802a023）、
`/mall/ashbringer/app/abtest`（0x18030039）、`/mall/noah/feed/sceneRec`（0x1802df1e）、`/mall-gateway%@`（0x1802a2bd）；
③ **H5 页面**（`/neul-next/…`、`/list.html`、`/detail.html`、`/cart.html`、`/shop/…` 等，供网页容器加载，不是接口）；
④ 相对路径常量 `https://mall.bilibili.com/mall-c`（0x103336e94、0x103337144）与 `…/mall-ugc`（0x1033e7f84）、
`…/community-hub`（0x1033e8294）三个已由子类函数体内取到；其余子类的符号索引地址多为 Swift 桥接 thunk，
需按真正实现入口重取（或用 9.13 线级抓包按 host+path 反查）。香港域替换为 `.dreamcast.hk`（见上文支付/商城段）。

getComicWithComicId:andEpid:isInstallBiliComic:trackId:completion:error:]`
0x10ec79c58 → `/twirp/column.v1.ColumnPay/GetComic`（候选引用 0x10ec79e1c）；同族
`pay.v1.Pay/GetBCoinLevel|CreatePayAndConsumeOrder|GetOrderState|GetExchangeConfig`、
`column.v1.ColumnPay/BuyComic`。

漫画传输与字段（team-c14，反汇编 0x10ec79804–0x10ec7addc）：公共层
`+[BBComicRequest requestWithUrl:andParams:completion:error:]` 0x10ec79804 构造 BFCApiOptions
（setParams: + **setRequestMethod: 2（POST）**，0x10ec798a0–0x10ec798a8），响应按
`modelWith:'data' mappingClass:<classref 0x11f7b5c38> isArray:0` 映射后交 BFCApiRequest
initWithOptions:→requestAsync（0x10ec79964）；requestRaw 变体 0x10ec799ac 唯一差异映射根 `'/'`（整包）。
mappingClass 已闭合（task-32）：槽 0x11f7b5c38 虽为 chained-fixup（静态 qword=0），但
symtab 将该槽命名为 **`classRef_NSDictionary`**（`_OBJC_CLASS_$_BBLinkModel` 0x120064e28 与
`classRef_BBLinkModel` 0x11f7cda20 各有独立槽，非混用），且加载后经 `_objc_opt_class` thunk
0x10f898f98（符号 `+[BBLinkModel modelCustomClassForDictionary:]_0`）——即 `[NSDictionary class]`，
静态判定 **mappingClass=NSDictionary**：/data（requestRaw 变体 0x10ec799ac 用整包根 `'/'`）按
原生字典承接、不映射业务模型类。全族一致复用同槽（0x10ec79a60/0x10ec79dc0/0x10ec7a99c/
0x10ec7aa34/0x10ec7ab58/0x10ec7ad18）。运行期复核：lldb 断
`+[BFCApiModelDescription modelWith:mappingClass:isArray:]` 打印 x3。GetComic 请求键：
`comic_id`/`ep_id`（numberWithInteger→`%@` 字符串化，0x10ec79c9c–0x10ec79d64）、
`is_install_bilicomic`（numberWithBool→stringValue，0x10ec79d68–0x10ec79d98）、
`track_id`（nil 取常量 ''，csel 0x10ec79dab–0x10ec79db8），4 键字典 0x10ec79dd0。
其余：CreatePayAndConsumeOrder（0x10ec7a438，URL 常量 0x11d1e1a10）键 `pay_amount`/`start_ord`/
`with_ord_scope`（常量 '1'）/`business_type`/`limit`/`comic_id`，并把入参 trackInfo 字典合并进 params
（0x10ec7a6b0–0x10ec7a6ec）；GetOrderState（0x10ec7a76c，0x11d1e1a50）键 `order_id`/`order_ctime`；
BuyComic（0x10ec7a8d8，0x11d1e1a70）键 `pay_amount`/`comic_id`/`ep_id` + otherParams 合并；
GetExchangeConfig 带 `source`='1'（0x10ec7ab44）；ReportRestoreScene（0x10ec7abf8，
`community.v1.Pink/ReportRestoreScene` 0x11d1e1ab0）键 `idfa`/`scene`/`comic_id`/`ep_id`/
`is_install_bilicomic`/`uri`。错误分支在 BFCApiRequest 公共层（已闭合），本类无独立错误枚举。

商城 base 构造 `-[BBMallBaseApi requestUrlWithConfigUrl:]`0x11381580c（反汇编
0x1138157c0–0x113815980）：config url 非空直接采用并按 isHKDomain 把
`.bilibili.com`→`.dreamcast.hk`（CFString 0x11d104930/0x11d30b650，
0x113815848–0x113815874）；为空则拼 requestUrlPath +（requestHost 或默认
CFString 0x11d0e1290 = `https://mall.bilibili.com/mall-c`）。configUrl 来源已闭合
（team-c11）：唯一调用方 `-[BBMallBaseApi makeOptions]`0x113813630
（stub 0x1174f2460 仅 0x113813714 一处调用），值 =
`[[self requestApiConfig] copy]['apiUrl']`（0x1138136d0–0x113813714）→
setBaseUrl:；makeOptions 另装配 requestMethod/timeoutInterval/headers/
params(requestQueryWithValidate)/modelDescriptions/handlerTokenFailureShowLogin
（0x113813744–0x11381389c）及 setSignType:/setIgnoreCache:/setCacheValidLife:/
setIgnoreCodeNonZero:。请求模型 BBMallRequestModel 完整 ivar 族
url/query/body/extraHTTPHeader/method/needAntiInterceptor/needGzip/
pinnedCertificateHash（ivar 0x120435ad0–0x120435b08，getter/setter
0x103a0228c–0x103a02c84，指定初始化器 0x103a02f78）。Api 族（requestApiConfig 指向 mall-c 前缀）：购物车
BBMallCartAddApi 0x1136ea5f8/BBMallCartApi 0x1136eaabc/BBMallCartCheckApi
0x1136eb330，订单 BBMallOrderUserStatusApi 0x1136f09f4，评论 BBMallCommentApi
0x113816320，收藏 BBMallFavoriteGoodsApi 0x1128fce54，IP 订阅 BBMallIPSubscribeApi
0x112901a30 等；搜索 `/mall-c-search`、推荐 `/mall/noah/feed/sceneRec`；模块入口
BBMallModule onModuleInitialize 0x1031e50e0、路由 BBMallSwiftEntry
onRegisterRouters 0x1031e6d4c。

支付：B 币余额快付 `-[BBPhoneMineWalleBpBalancePayApi apiPath]`0x10f4da154（pad 侧
BBHD2PhoneMineWalleBpBalancePayApi 0x10ca31228）→
`https://pay.bilibili.com/api/client.quick.pay.do`（字段级 team-c11：params 单键
`pay_order_no` ← ivar _pay_order_no 0x11f8535ec，nil 则 `''`，0x10f4da184–
0x10f4da1c4；响应 mappedClass=SKVObject、defaultResultKey=nil，0x10f4da20c/
0x10f4da218。pay_order_no 写入方为 BBHD2PhoneStore 下单/充值回执块：
addBpPayment 0x10c9ff010/0x10c9ff340、addBpRecharge 0x10c9ffc28、
checkRecharge 0x10ca00914、checkCharge 回执 0x10c9fe638，即先下单拿
pay_order 再回填发快付；回执真实consumer读取status并分1成功/2失败/其它5秒或30秒重试，>4失败（详root-static-peripheral-api），
需抓包 pay.bilibili.com 响应）；网页容器 JS bridge 充值
`-[BWAJSEventPayHandler doRequestRechargeWithParams:payRawStr:callback:]_block`
引 pay.bilibili.com `/payplatform/fund/out/recharge/req`（0x11302b280 候选引用）；
番剧承包 bangumi.bilibili.com `/sponsor/api/v2/pay/order/create|success`、
`/pay/api/season/pay_by_ticket`。

游戏（字段级 team-c14）：`+[BBGameCenterReporter dataDictionary]`0x113ebf24c 是
**H5 页面 spm 注册表**（反汇编 0x113ebf24c–0x113ec1300），每条目 3 键 `url`/`spmId`/`pageCode`
（如 `https://app.biligame.com/home`↔`555.0.0.0`↔`home`，共 40+ 条）；
**`small_game_list_recent|attention|like` 即注册表内 H5 页面条目（spm 555.138–140.0.0，
0x113ec1180–0x113ec1270），不是 JSON API**；路由形式另有
`bilibili://game_center/small_game_list_*` 与 `%@/small_game_list?typeName=home&name=%@`（0x11804d6f0）。
原生曝光/点击走 BBTrack：`createExposureReport:params:` 0x113eb8778 装配
BBGameCenterReportData（`sourcefrom`←入参/查表、`versionGameCenter`←常量 '1.7.0'、
`screenResolution`←`+[BBGameCenterReporter screenResolution]`、`browser`←'native'、
`url`/`spmId`/`page`←`+[BBGameCenterReportData dataWithType:params:]`0x113eb79f0 按 params['id'] 查表、
`referUrl`/`spmIdFrom`/`bgamefrom`/`fromgame`/`module`←''、`sessionId`←0x113eb85a4、`extra`←入参），
消费端 0x113eb89f4 → `yy_modelToJSONObject` →
`trackCoustomEvent:'001556' params:<json> uploadType:'0'|'1'`（0x113eb8f68–0x113eb8fb8）；
事件 params 键 `index`/`sub_index`/`value`/`module`/`isCommunity`/`sourceGameCenter`（0x113eb8bc0–0x113eb8eb4）。
小游戏 H5 原生 API（line3-h5-mobile-api.biligame.com）入口已定位：
`/game/center/h5/small/game/mini_game_exit_popup`←`-[BWAManager fetchGameQuitAlertServerDataIfNeeded:]`
（ref 0x112fd81fc）、`/small/game/advertising_position`←`BWAJSEventAdHandler loadRewardedVideoAdWithParams:`、
`/user/smallgame/iaa_ad_style_exp`←`queryHitSidebar`、`/small/game/setting` 与
`/small/game/relation/chain/list`←`BWAJSEventAuthorizationHandler getRelationWith:callback:` block1/2、
`/disaster/game/center/h5/detail/gameinfo/v2/2/`（line3-statics-…biligame.net）←
`BBGameCenterDetailBaseBottomView bookResultWithGameId:type:`。
**12 条端点已全部经 CFString 反查闭合（task-32）**：代码不直接引用裸 __cstring（页面 0x11800b000/
0x118011000 等 adrp 引用=0；注意早前记录的 0x1800xxxx 是**去 scheme 后子串的文件偏移**（比 CFString data 指针小 7/8 字节），**建议引用口径改为 CFString VA**，如 0x11d2da230；team-c31 已逐条复验 12/12），
而是引用 `__cfstring` 条目——12/12 均有唯一或多个代码引用：`mini_game_exit_popup` CFString
0x11d2da230→0x112fd81f8（GET，0x112fd8218 `biliRequestWithUrl:isGetMethod:paramsAddId:params:appletInfo:callback:`）；
`advertising_position` 0x11d2dce70→0x11300337c；`iaa_ad_style_exp` 0x11d2dd1d0→0x1130056dc；
`setting` 0x11d2dd970→0x11300b9cc（getRelationWith block1）与 0x11317293c
（`BWAOpenSettingViewController requestGameSetting`）；`relation/chain/list` 0x11d2dd9d0→0x11300bcf8
（block2）；`relation/auth` 0x11d2dda10→0x11300c104（block_block_5）；`version/reserve_notice`
0x11d2e0e30→0x113037670 与 `version/reserve` 0x11d2e0ed0→0x113038060（均
`BWAJSEventSubscribeHandler requestSubscribeNewVersionEvent:params:callback:`）；`report/v2`
0x11d2e6fb0→0x113097878（`BWAServiceTracker reportUseToGameCenter:reportFrom:`）；`report/dev`
0x11d2e6ff0→0x113087a0c（`BWAServiceModManager upgradeGameBaseResouceIfPossible`）、0x113087a98
（`forceCheckGameBaseMode`）、0x113097988（`BWAServiceTracker reportDevUseToGameCenter:params:`）；
`relation/setting/update` 0x11d2ecf10→0x113173244（`updateGameRelation`）；`notice_switch`
0x11d2ecf30→0x1131733cc（`updateGameVersionSubscribeInfo:`）。host CFString 0x11d32f470
（`https://line3-h5-mobile-api.biligame.com`）另被 BWA* 域 90+ 处引用。

创作（UP 主，字段级 team-c14）：`+[BBUperSeasonURLString addEpisode|modifyOrder|modifySeason|
sortConfig|sortSwitch|sortSubmit]` 0x1004b6ef0–0x1004b6fcc（Swift 内联常量）→ member.bilibili.com
`/x2/creative/app/season/section/episodes/add`、`/season/section/edit`、`/season/switch`、
`/season/sort/config`、`/season/sort/switch`、`/season/sort/submit`；
domain `+[BBUperSeasonHttpClient HTTPDomain]`0x1004b7014 = `https://member.bilibili.com/`。
列表 `-[BBUperSeasonListApi requestUrl]`0x1004a5f18 = `x2/creative/app/seasons`、
requestMethod 0x1004a5f10 = GET；params 0x1004a5f44（sub_1004A5F50）5 键均由 ivar 转字符串：
`pn`/`ps`（Int）、`order`/`sort`/`source`（String）；modelDescriptions 0x1004a6158 →
ObjC映射 **BBUperSeasonDataModel**（accessor1004c2454→objc_opt_self），root真实`data`、isArray0、未setIsOptional。旧将同名Swift描述符借给此accessor的归属撤回；totalCount/sortMode/canAddSeason分别映射total/sort_mode/can_add_season，seasons容器为BBUperSeasonModel，sections为BBUperSectionModel。完整字段与映射见root-static-peripheral-api/findings.md。
`requestSortSwitchWithSortMode:` 0x1004b7bf8 参数键 `sort_mode`（小串 0x1004b8534，POST）；
`requestSortSubmitWithSeasonIds:` 0x1004b7ebc 参数键 `season_ids`（小串 0x1004b8694–0x1004b86b0，
Int 数组），响应映射根 `/data`、isOptional（0x1004b8024–0x1004b8060）。
`requestAsyncWithPath:params:postParams:modelClass:completionHandler:` 0x1004b76b8 把 postParams
JSONSerialization→setHTTPBody:（0x1004b7254/0x1004b7318）后走主程序共享传输（sub_10003D5DC/
sub_10002E94C），NSError→Swift Error 透传（0x1004b706c）。creative-tool 族
（`/x/creative-tool/...`，ai-creation/story-video/asr/rubick-interface，member.bilibili.com）
与文章创作 `/x/article/creative/...`（api.bilibili.com）仍为入口级。


**小游戏 API 与 H5 页面的域清单（8.89 静态字符串表穷举）**：`line3-h5-mobile-api.biligame.com` 下共 **12 条** API，
全部形如 `/game/center/h5/…`：`small/game/advertising_position`（0x1800b1ae）、`small/game/mini_game_exit_popup`（0x1800950f）、
`small/game/notice_switch`（0x180150f7）、`small/game/relation/auth`（0x1800ba49）、`small/game/relation/chain/list`（0x1800b9dc）、
`small/game/relation/setting/update`（0x1801509c）、`small/game/setting`（0x1800b965）、`small/game/version/reserve`（0x1800db30）、
`small/game/version/reserve_notice`（0x1800dab2）、`user/played/smallgame/report/dev`（0x180116af）、
`user/played/smallgame/report/v2`（0x18011631）、`user/smallgame/iaa_ad_style_exp`（0x1800b390）；
另有 `biligame.com/api/v2/sso`（0x18186f27）。**注意区分**：`biligame.com/<页面名>` 约 130 条是 **H5 页面路径**
（即上文 spm 注册表条目的 `url` 取值），不是 JSON API；`small_game_list_attention|like|recent`
（0x18052290/0x180522e9/0x1805223d）同为页面路径而非接口——这与上一轮"`small_game_list_*` 不是 JSON API"的判定一致。

### Ktor 开关的重复读取、client once 与已创建 task

BFCApiConstWrapper.isKtorRequestEnabled0x105068c64每次resolve注入的
DeviceDecisionService，再getBoolForKey `dd.api_request_use_ktor`、defaultfalse
（0x105068d18/0x105068d1c）。它是独立于dd.http_client_opt和dd_http_client_use_ktor
的第三个开关，未读取实际值。BFCApiRequest的build、completion、queryString及
Operation.main分别读它（0x116095ab8/0x116095e5c/0x11609734c/0x11609751c/
0x11609ac8c），未证构建/发送/响应共享不可变flag snapshot。

main开关true且BFCApiConst.httpClient非nil才client.task(built request)
（0x11609aca4–0x11609acdc），把返回task保存operation ivar
（0x11609acf0，offset global0x11f8b3ed0），安装onCompletion再request
（0x11609ad60/0x11609ad70）；false/nil去另一运输分支0x11609b040。
启动前改变开关可能影响这里选择，不证明已经启动的task迁移engine。
client wrapper0x105067e70另有swift_once token0x120a8e988，initializer0x105067dd0
resolve BFCHttpClient optional并保存object或nil到global0x121073678
（0x105067e5c），后续只读/retain（0x105067e8c/0x105067e90）。真实provider
0x10009b7d0调用此前config-selecting factory0x10009be10，registration0x10009b900
在0x10009ba04接此service；不从registration raw Bool推缓存语义。
有限whole-text ADRP邻接ADD/LDR/STR查找仅找到slot初始化store和getter load，支持
该寻址模式未发现直接cache-reset writer，不能排除间接写/运行时重注册。没有证到
账号或配置observer使这个wrapper重新选择client。

Operation.cancel0x11609c16c→cancelTask0x11609c1b4对已存NSURLtask与BFCHttptask
分别cancel并清ivar（0x11609c1dc/0x11609c1e4、0x11609c1fc/0x11609c204），不重读
ktorflag也不创建替代task。旧task.request的dd_http_client_use_ktor true且disable attr
缺失才set requestType=2（0x1000aa224）；false/nil service/disable key存在分支在
0x1000aa228汇合，**该 gate 已读全（team-c33）**：判据 = `[.. getBoolForKey:defaultValue:]`
（selref 槽 0x11f675250，0x1000aa1a0）为真（`cbz w23` 0x1000aa1c8），**且** `BFCHttpTask.attrs`
（ivar 槽 0x1210644e8，0x1000aa1cc–0x1000aa1d4）为 nil（`cbz x8` 0x1000aa1dc）**或**其中
`bfc_http_disable_ktor` 键不存在（字符串 0x1177759a0；字典查找 `sub_10002943C` 0x1000aa204，
命中则 `tbnz w23,#0` 跳过）→ 才写 `requestType=2`（ivar 槽 0x121064500，`mov w9,#2; strb`
0x1000aa220–0x1000aa224）；其余分支在 0x1000aa228 汇合，其后到 0x1000aa280 只有两次
`swift_getKeyPath`（0x1000aa240/0x1000aa250），**没有任何对 requestType 的写/重置指令**
⇒ **gate 后 requestType 复用（保留旧值）静态成立**（原先标注的不确定口径可据此去掉）。
旧 task 对象能否复用/重发仍是运行期事实，需抓包或断点确认。

邻接HttpModule DD observer0x10009bd74→0x10009c96c只匹配
`http_load_balance_enable`（0x10009c9a8–0x10009c9cc），要求value非nil，重读配置
后更新LoadBalances（0x10009cb6c→0x10009ed84），不是该body证到的client热替换。
四个公开开关/disable key有限直接引用扫描均为已查读取；业务disable attrs/Enable GInterceptor writer可能经KVC/动态selector，未找到不能推永不启用。下一步：find_string_refs 'dd_http_client_use_ktor' 与 query_index '*GInterceptor*' 30 扩大扫描。DeviceDecisionService具体DI
实现、remote/local更新及账号context生命周期继续追踪。

DeviceDecisionService已有具体DI绑定：334 component库存的DDModule index85
（0x120272b98）和DDModuleMapper index86（0x120272ba8）；mapper0x10003c8e4在
0x10003c9fc/0x10003ca64绑定该service，provider0x10003d840→callback0x10003d910
resolve/cast BFCIDDContainer（0x10003d91c/0x1000389c0/0x1000389e8），返回container
本身。DDModule注册的container provider0x1000381ac首创建后缓存到.+0x10
（0x100038250），其factory0x10003c3a8实际alloc DDContainerProvider，virtual+0x50
接0x10005832c→0x100058410。这个factory先创建DDContainerV2，再读
KDeviceDecision.shared.defaultDD.isDDAppDisabled（0x100058528）；false返回V2
（0x100058688），true创建legacy DDContainer并把同一个V2挂其containerV2
（0x100058590）。未读取实际disabled值，不能概括实际service必为V2。
V2 getBoolForKey0x10004fbdc以config:nil转core0x10004fc6c，再到Kotlin
IDeviceDecisionKt.getBool（0x10004fd04）；context更新和内部key求值继续核对。
container对象缓存不等于Bool值缓存；API/旧task仍逐次问service，API httpClient
once另冻结已选client对象，两者生命周期分开。

账户通知也有具体DD属性更新入口：184项Runnable库存index46/slot0x120273e50的
DDPropObserverModule，单任务witness0x11b0a49e8的execute槽+0x28接
0x100038f64→0x10003cf20。它resolve BFCAccountNotifyManagerService.Type后初始化
static DDMidPropObserver（0x10003cfac–0x10003cfbc），addNotifyService
（0x10003cfcc）。accountDidLogin0x1000391e0以及logout/update/change
0x10003dbfc/0x10003dc00/0x10003dc04均转0x10003d3f0，resolve optional
BFCDDPropertyService，非nil才propertyChangedFor公开key `mid`（0x10003d498）。
该body不读取实际MID，不取消现有HTTP task、不替换httpClient once、不重跑factory。
V2 propertyChangedFor0x10004f570取lazy property interface（0x10004d608），首次经
KDeviceDecision.shared.property取得并缓存（0x10004d644，ivar0x120277c68），再
onPropertyUpdatedName（0x10004f5c8）。这是账户属性更新边，具体property绑定/
缓存处理见下段；不能等同Ktor开关必变或已选client迁移，legacy0x100046e68另核。

实际KDeviceDecision.shared.property已闭到PropertyCenter。Kotlin export shared
adapter0x10be27910初始化0x1053de844，instance property adapter0x10be28460读
KDeviceDecision.+0x18（0x10be28534）。initializer以DI key0x11c544a58 resolve
（0x1053deb78），调用provider hash0x587 slot+0x10并存.+0x18
（0x1053debd0/0x1053debd8）。Root registration0x10b92ca8c使用相同key
（0x10b92caf4），捕获getter0x10b91fad4的provider（0x10b92cafc）；该getter读
Root.+0xc0，其cached SwitchingProvider id26分支0x10b93d4d4→0x10a9bdf98。
lambda TypeInfo0x11bb206a0/invoke0x10a9bf214最终取DDContainer hash0x1c83
slot+8（0x10a9bf378）。依赖Root.+0x80的id18分支0x10b93d134→0x10a9bdbe4，
lambda0x11bb204c0/invoke0x10a9bed10再构造factorylambda0x11bb20ba0。
其invoke0x10a9c05a0分配DDContainer TypeInfo0x11bb21500
（0x10a9c0734/0x10a9c0738），constructor0x10a9c3994分配PropertyCenter
TypeInfo0x11bb272e0（0x10a9c4488/0x10a9c448c）并存container.+0x30
（0x10a9c4ec0）；所选hash0x1c83 slot+8 getter0x10a9c656c正读.+0x30
（0x10a9c6578）。因此不是只凭唯一interface候选推注入；不提升为全部legacy路径。

onPropertyUpdatedName export row0x11ccf7818→adapter0x10be23ccc，hash0x3c00
slot+0x10接PropertyCenter0x10a9f5ea4。它捕获center/name到lambda0x11bb274c0
（0x10a9f5f64），以scope.+0x20 launch0x1052b31c0（0x10a9f5f7c），返回不等
重求值完成。lambda invoke0x10a9f6d94在center.+0x40按name同步Map.get
（0x10a9f6df8/0x10a9f6e00→0x10a9c0a18），nil跳过（0x10a9f6e04），非nil
才处理entry0x10a9f5fac（0x10a9f6e18）。这不是按通知name直接删全部决策cache。

entry处理先锁center.+0x38（0x10a9f6064），按0x10a9f5d3c判断eligibility
（0x10a9f6080），再原子取entry.+0x10内的当前provider
（0x10a9f60ac–0x10a9f60b8）。eligibility=false或provider缺失时，按name从
center.+0x28 cache remove（0x10a9f6150→0x10a9c0de4）。该cache同步holder
0x10a9c0920内分配Kotlin HashMap TypeInfo0x11b371e80
（0x10a9c0990/0x10a9c0994），hash0xa00 slot+0x30→0x1052468e8先find index
（0x105246964→0x105247f7c），再remove index（0x105246998→0x105248628），
这里是实质单name删除；entry.+8及center.+8参与eligibility，未套未经核对的政策名。

eligible时取旧cache、尝试新source0x10a9f6544（0x10a9f60e0/0x10a9f60f4）；
返回对象.+0x10缺失时退entry provider0x10a9f7110，provider仍nil退entry snapshot
.+0x10（0x10a9f71ec/0x10a9f71f8–0x10a9f7210）。old.equals(new)为true便跳过
写入和事件（0x10a9f6120/0x10a9f6124）；变化才按name Map.put
（0x10a9f6190→0x10a9c0b5c，具体HashMap0x1052462e8）。删除/变化两路才launch
lambda TypeInfo0x11bb27560（0x10a9f6294/0x10a9f62ec）；invoke0x10a9f6e64
向center.+0x30 hash0x483 slot+8发property name（0x10a9f6edc）。此事件到决策依赖/结果cache失效见下段；不保证账户callback返回时Bool已变，不取消
现有HTTP task或迁移once client。未读实际name对应属性值。

V2 Bool查询也已接同一DDContainer，而非只闭property。getBoolForKey:defaultValue:
config:0x10004fd34取lazy dd（0x10004fd7c→0x10004d5e0，ivar0x120277c58），
交core0x10004fc6c（0x10004fd94）再Kotlin getBool adapter。KDeviceDecision.dd
以key0x11c544a38 resolve并存.+8（0x1053de9c8/0x1053dea20/0x1053dea28）；
Root registration0x10b92c958使用同key（0x10b92c9b8）及getter0x10b91f5cc的
Root.+0x88 cached provider id17。id17分支0x10b93cef4→0x10a9bdd28的lambda
TypeInfo0x11bb20560/invoke0x10a9bf3a8 resolve上述id18、直接返回同DDContainer
（0x10a9bf4b4/0x10a9bf4bc）。因此V2 dd与property来自相同安装的父container。
export row0x11cd0fb30→0x10bf1cf94→helper0x1053ddeec，经decision hash0x3b00
slot+8（0x1053ddfe0）接该TypeInfo0x11bb21500的0x10a9c68d8。每次查询先从
container.+0x38调用evaluator0x10a9dbd1c（0x10a9c69a4–0x10a9c69b4），其结果
cache/依赖失效及最终类型/状态转换见下段。外围Bool helper仅nonnull才取boxed Bool.+8
（0x1053ddfec），nil保留原default并返回（0x1053ddfe8/0x1053ddffc）；不能将
Ktor defaultfalse读成开关永远false，也不能由对象一致性推全部决策cache已重置。

DecisionCenter的属性flow消费者已接实。DDContainer constructor分配
TypeInfo0x11bb24920并存container.+0x38（0x10a9c4ecc/0x10a9c4ed0/0x10a9c5170），
把已证PropertyCenter存DecisionCenter.+0x10（0x10a9c4f28/0x10a9c4f68）；另建
.+0x28/.+0x30两个同步cache holder（0x10a9c4fe0/0x10a9c503c）。constructor无条件
launch observePropsUpdate lambda TypeInfo0x11bb24ce0（0x10a9c5100/0x10a9c5160），
不等待collector安装。invoke0x10a9dd5b0经PropertyCenter hash0x7081 slot0
（0x10a9dd670）→0x10a9f4dc0读取同一.+0x30 flow并包装read-only flow
（0x10a9f4ddc/0x10a9f4de4），构造collector TypeInfo0x11bb24d80并collect
（0x10a9dd688/0x10a9dd71c）。

collector0x10a9dd754枚举DecisionCenter.+0x28的keys（0x10a9dd7f4），逐项取当前
entry（0x10a9dd994），nil跳过；只在entry.+0x10 dependency collection.contains
通知name为true时收集该decision key（0x10a9dd9ec/0x10a9dda08），交0x10a9dce28
（0x10a9dda28）。后者逐key remove .+0x30（0x10a9dd020），取/删除.+0x28 entry
（0x10a9dd030/0x10a9dd048）；source helper0x10a9dcb4c缺失时以context=nil调用
0x10a9dc15c重求值（0x10a9dd058/0x10a9dd0dc/0x10a9dd0e0），old/new status与value
比较再决定后续通知（0x10a9dd060–0x10a9dd0b8）。正常query也在0x10a9dc15c按key
读.+0x28，命中返回cached item.+8（0x10a9dc288/0x10a9dc294/0x10a9dc29c）；因此
已证删除的是实际查询结果cache。.+0x30另作辅助Bool cache，result.+0x11==1时才
可写boxed Bool（0x10a9dc6d0/0x10a9dc6d4/0x10a9dc6ec–0x10a9dc70c），不把它直接
等同公共getBool最终返回值。

默认配置观察者的通知源是DecisionCenter.+0x20：constructor以0/0、nil、mask6
调用flow factory 0x1052dff68并保存（0x10a9c4f74..0x10a9c4f88）。它不同于
DataCenter的node flow。didKeysUpdated 0x10a9dce28在old cache缺失
（0x10a9dd034）或old/new结果比较需要通知时，构造lambda TypeInfo 0x11bb24e20
（0x10a9dd114/0x10a9dd120/0x10a9dd124），捕获center/key并在scope.+0x18 launch
（0x10a9dcf44/0x10a9dcf5c）。invoke 0x10a9ddb48读center.+0x20
（0x10a9ddb6c），hash0x483 slot+8 emit该key（0x10a9ddbc0）；相同结果跳过通知。
DDContainer默认observer 0x10a9c983c从container.+0x38取同一flow并read-only包装
（0x10a9c9af8..0x10a9c9b0c），安装仍受container.byte+0x50==1门禁。
observer从静态enum集合0x120c5b338取各enum.+0x18，保存为captured key collection
（0x10a9c9928/0x10a9c9a24/0x10a9c9af0/0x10a9c9b60）。transform
0x10a9ca158→0x10a9c9e44遍历captured集合（0x10a9c9f74/0x10a9c9fe0），
向下游emit各key（0x10a9ca058），但这是onStart预发：factory 0x1052ed940
实际TypeInfo 0x11b38bfd0为onStart$$inlined$unsafeFlow$1，collect 0x1052ee6e8。
订阅开始预发默认key全集；之后filter TypeInfo 0x11bb22060/collector 0x11bb22100
body 0x10a9ca3ac对incoming key做captured集合contains（0x10a9ca410/0x10a9ca414），
不命中返回Unit，命中才downstream emit。不能把onStart遍历称每次变化通知重发全集。
collector TypeInfo 0x11bb221a0/body 0x10a9ca4d4以0x1053df1dc查enum
（0x10a9ca5a4），normalize 0x10523c6b8后遍历0x120c5b330并比较enum.+0x18
（0x1053df25c/0x1053df290/0x1053df298）。nil lookup返回Unit（0x10a9ca700）；
命中则getString(key,nil,nil) 0x1053dddd8（0x10a9ca5c8），再将enum和String/nil
交container.+8的hash0x3d80 slot+8 setter（0x10a9ca624）。

该setter的具体依赖也已接实：container ctor保存x2到.+8（0x10a9c3a38），factory
从lambda.+0x10取x2（0x10a9c0774），依赖经0x10a9bed10/provider hash0x584/
producer hash0x587（0x10a9bee70/0x10a9beecc）存入lambda（0x10a9bef40）。
Root getter 0x10b91f45c读Root.+0x78（0x10b91f4b4），该字段由cached
SwitchingProvider ID20构造（0x10b930e38/0x10b930e44/0x10b930e48）；
table 0x118652e72 entry20→0x10b93cf9c→0x10a9be340（0x10b93cfd0），
getterlambda TypeInfo 0x11bb20880捕获config-module provider（0x10a9be3b0/
0x10a9be3f4）。实际get 0x10a9bf67c创建provideDDDefault$1 TypeInfo
0x11bb22240（0x10a9bf7c0/0x10a9bf7c8）及SharedPreferences 0x11b3b6230
（0x10a9bf874/0x10a9bf87c），调用constructor 0x1053e0058并保存wrapper.+8
（0x10a9bf8c0/0x10a9bf8c4）。固定suite公开literal 0x11cb2d540为
`dd-default-config`，此factory无账号参数，不推其他writer/clear不存在。
native peer通过NSUserDefaults.initWithSuiteName创建defaults
（0x1053e02f0），存peer.+0x10及Kotlin wrapper.+8
（0x1053e034c/0x1053e0374）。setter 0x10a9cab98总用原enum.key.+0x18
（0x10a9cabb8），nil替换公开sentinel `__DD_DEFAULT_NULL_VALUE__`
（literal 0x11cb2d4b0；0x10a9cabc4/0x10a9cabc8），tail 0x1053e2a2c
（0x10a9cabe4），先type validation 0x1053e20c0（0x1053e2aa8），再对peer
defaults setObject:forKey:（0x1053e2ab0/0x1053e2c10）。本地调用不是磁盘同步或网络ACK。

同一wrapper的getter 0x10a9caa3c还有快照分支：byte+0x10由config-module
hash0x28500/+0x50初始化（0x10a9bf864/0x10a9bf868）；==1
（0x10a9caab4..0x10a9caac4）读原key（0x10a9caad8），把原值或nil sentinel写到
原key+公开suffix `::to_sub_process`（literal 0x11cb2d500；
0x10a9caaec..0x10a9cab1c），返回原值（0x10a9cab20）。!=1只构造/读取suffixed key
（0x10a9cab44..0x10a9cab68）。read helper 0x10a9ca958→0x1053e25d4
（0x10a9ca9c0..0x10a9ca9d0）实际NSUserDefaults.stringForKey:
（0x1053e2748），nil传播，sentinel映射nil（0x10a9ca9ec..0x10a9caa00）。
因此setter写原key、条件getter才复制到快照key；不把两分支称同key无条件读取。
该Bool实际依赖也已闭：Root.+0x70由ID19构造（0x10b930db0/0x10b930dc0），
table entry19→0x10b93d32c→0x10a9bdb34（0x10b93d348）。后者把静态producer对象
0x11cb2cd38交module hash0x2b00/+8（0x10a9bdbd0）；此地址不是String DI key。
对象tagged TypeInfo为0x11bb20421，去tag后0x11bb20420，即providesRawProducer0$1，
hash0x584实现0x10a9be478；其associated static provider 0x11c32e6f8亦同实现。
该body实际分配DDNativeArgs TypeInfo 0x11bb28880（0x10a9be4e8），其hash0x28500
slot9/+0x48→0x10a9c0530、slot10/+0x50→0x10a9c0504均返回Bool true，不读取
运行配置字段。因此此native绑定上的observer start gate为true，default getter走
原key读取并写suffixed snapshot分支；保留getter自身false分支，不声称其他实现不存在。
默认enum集合六个公开key为`dd.default.app_disable_kntr_impl`、
`dd.default.enable_core_data_v2`、`dd.default.observable.props`、`dd.default.focus.props`、
`dd.default.update_host`、`dd.default.update_host_configs`；不含`dd.http_client_opt`。
默认持久化getter有具体消费者：factory 0x100058410取KDeviceDecision.shared.defaultDD
并调用isDDAppDisabled:（0x100058528）；export row 0x11cd0fb60→adapter 0x10bf1d3a8
选enum ordinal0/app-disable（0x10bf1d4e0）→0x1053df370（0x10bf1d4ec），后者调
receiver hash0x3d80 slot0（0x1053df448）。nil为false，exact String `true`或`__true__`
为true，其他String为false（0x1053df450/0x1053df470/0x1053df4a8）。该factory先创建V2，
app-disable=false选V2，true构造legacy并附上同V2；这是DD service选择，不直接选择
HttpClient类。HttpClient factory 0x10009be10仍单独query `dd.http_client_opt`，
default=false（0x10009bec8），选择HttpClientOpt/BFCHttpClient
（0x10009bee4..0x10009bef0）。defaultDD DI对象与消费getter的一致性继续追。
默认持久化getter与正常V2 DecisionCenter query仍是不同消费路径；已查observer setter不直接
调用client factory或清API once。已有HTTPClient是否采用后续更新需证明observer→client factory边（有界扫描未见）；下一步：find_callers 0x10009be10 穷举HttpClient factory调用方。未读取持久化值。

由此闭合账户callback→mid属性通知→异步属性变化/删除→name flow→依赖该name的
决策key→其结果cache失效/重求值。未登记name、属性值未变，或决策依赖不含mid，
均不会经此collector清该决策；未读取实际远程key/依赖配置。最终Bool类型/状态转换见下段；
legacy分支及业务enable/disable writer为精确残余（分散在业务DI图）：find_callers 0x1053df370 穷举app-disable adapter调用方核对writer集合；未证once client替换或现有task取消。

V2公共Bool的evaluator-result转换也已闭到实际返回值。DecisionCenter.Result为
TypeInfo0x11bb249c0，分配0x10a9dc48c/0x10a9dc494，.+8为boxed status、.+0x10为
payload、.+0x18为辅助byte；初始化清两reference和byte
（0x10a9dc4d0/0x10a9dc4d4）。它不同于formula reply的.+0x10/.+0x11及前述辅助
cache。getBool的0x10a9c68d8取得此result后按下表转换，不读取实际远程值。

| status | payload | 返回Bool及地址 |
| --- | --- | --- |
| nil | 任意 | supplied default，0x10a9c6a28/0x10a9c6aa4→0x10a9c6c54 |
| false | 任意 | false，0x10a9c6c18/0x10a9c6c1c |
| true | nil | true，0x10a9c6ad4→0x10a9c6c50 |
| true | equals `__true__` | true，0x10a9c6aec–0x10a9c6afc |
| true | 其他nonnull | equals `true`的比较结果，0x10a9c6c38/0x10a9c6c40/0x10a9c6c48 |

两个静态schema sentinel为KString0x11c544dc0/0x11c513bd0；该body调用payload
的equality，不trim/lowercase或通用parse数字1，不假定任意运行类型已经校验。
Bool box0x10a9c6c64→return0x10a9c6c7c→公共helper读.+8（0x1053ddfec）；外围
nil-object fallback与内部status=false、payload=nil三者不同。异常landing pad
0x10a9c6dec仅TypeInfo id落[0x3e4,0x49e]才日志并走fallback
（0x10a9c6e24–0x10a9c6e30/0x10a9c6f14–0x10a9c6f20），其他rethrow
（0x10a9c6f24/0x10a9c6f28）。尚未将范围内所有异常逐类命名，不能宣称全部失败
均吞掉或fallback代表远程接受。下一步 = disassemble.py 0x10a9c6e00 0x10a9c6f2c 逐类命名抛出的异常，并 query_index.py '*KntrException*' 10。

### DD 生产启动、配置 key 更新与响应版本触发

DDModule Runnable metadata0x11b0a4a38/witness0x11b0a4920.+0x28指向exec
0x100038680；解析BFCIDDContainer dependency typeref0x1202753e8
（0x100038690/0x1000386f8），保留actual container receiver并start
（0x1000386fc/0x10003870c），随后helper0x10003c5ac（0x100038714）。
V2.start0x10004dff0→0x10004d6e0（0x10004e004）取lazy dd0x10004d5e0，分别安装
versionsAsync:（0x10004d91c）与keysAsync:（0x10004dcc4），通过本实例
SerialDispatchQueueScheduler（ivar descriptor0x120277c50；0x10004d724/0x10004d728/
0x10004d794/0x10004d848）。version callback0x10004d9f4排队0x10004dc44，在
defaultCenter postNotification object=nil（0x10004dc64/0x10004dc8c）；keys callback
weak-load原V2（0x10004ddb4），存在才交0x10004ddec（0x10004ddcc），通过observerQueue
（descriptor0x120277c48；0x10004de94/0x10004de98）排队。这不是重建HTTP client。

DecisionCenter还在constructor安装与property observer独立的配置key coroutine
TypeInfo0x11bb24ba0（0x10a9c506c/0x10a9c50b0/0x10a9c50c8）。invoke0x10a9dd3dc
取IDataCenter hash28680 slot+8（0x10a9dd4a4），actual DataCenter TypeInfo0x11bb23640
的0x10a9d4910返回.+0x18 flow-container，读取其.+0x10（0x10a9dd4ac），构造collector
TypeInfo0x11bb24c40并collect（0x10a9dd520）；emit0x10a9dd554直接将notified key-list
与DecisionCenter交此前selective cache invalidation/re-evaluation0x10a9dce28
（0x10a9dd578）。这里输入本身是配置keys，不重做property dependency membership筛选。
Kotlin实际DI producer0x10a9c05a0在constructor之后（0x10a9c077c），仅container.byte
.+0x50==1才launch DDContainer$start$1 TypeInfo0x11bb217e0
（0x10a9c07ac/0x10a9c07b4/0x10a9c07c4/0x10a9c0818），同gate安装
observeDefaultConfigKey TypeInfo0x11bb21da0（0x10a9c0864/0x10a9c08b8）。该byte是
constructor从依赖hash0x28500 slot+0x48取得并保存（0x10a9c3ae0/0x10a9c3ae4），
未读取其实际配置值；不得与Swift V2.start Rx观察安装合为无条件刷新。

下载前半段是独立native NSURLSession：wrapper0x10a9fb934→0x10a9fb444构造
DDDownloader$download$2（0x11bb25a60），invoke0x10a9e59f4→0x10a9e5354
→downloadWithRetry coroutine body0x10a9e39b8（0x10a9e593c）。后者候选URL构造
NSURL/request（0x10a9e41f0/0x10a9e4318），使用ephemeralSessionConfiguration
（0x10a9e44c4），cachePolicy raw1（0x10a9e45d0）、URLCache nil（0x10a9e4680），
sessionWithConfiguration（0x10a9e4794）→dataTaskWithRequest:completionHandler:
（0x10a9e49dc）→resume（0x10a9e4ae0）；不套用公共Ktor签名或gateway。
completion block0x10bf6e42c连接callback TypeInfo0x11bb289c0实际方法0x10aa00020：
NSError非nil优先失败（0x10aa000b4），data缺失或HTTPResponse缺失/类型不符也失败
（0x10aa00148/0x10aa0014c/0x10aa002a0）；status只接受200..299
（0x10aa00318/0x10aa0035c..0x10aa00364）。随后NSData.writeToFile:atomically:true
（0x10aa00434..0x10aa00440），写false走失败（0x10aa00474/0x10aa006d0）；只有成功
写入才resumeWith Unit（0x10aa004dc），进入后述read/parse/version gate。
外层失败转UpdateException.DownloadFile（0x11bb280d0，0x10a9fb614/0x10a9fb618），
不是政策apply完成。取消handler TypeInfo0x11bb28a60捕获原task+8
（0x10a9e4b60），注册0x1052b6ab0（0x10a9e4b68）；实际0x10aa00950调用task.cancel
（0x10aa00a30），不等于撤销已写文件或回滚缓存。

重试body0x10a9e39b8读取配置max integer+0x18（0x10a9e3b28..0x10a9e3b38），
negative直接exhaust；index从0（0x10a9e3b40），collection+0x10按index取候选
（0x10a9e3bcc），nil或index>max结束（0x10a9e3bd0..0x10a9e3be0）。只对捕获的
Throwable TI id范围[0x3e4,0x49f)失败重试（0x10a9e51c4..0x10a9e51cc），
保存lastError（0x10a9e51d0），未到max则index+1回边（0x10a9e5308..0x10a9e5310），
exhaust重新throw lastError，无error则构造generic exception（0x10a9e5314..0x10a9e5348）。
成功返回Unit（0x10a9e3ad8..0x10a9e3ae4）绕过重试。故非负max=N时最多N+1个索引，
还受候选数限制；未读取实际N、URL、文件内容或策略值，候选/max构造来源继续核。
0x105cd7264仅File/path对象构造，不能当作字节写盘边界。

实际DateCenterFlow.didUpdatedNodes emitter0x10a9d77cc先检查incoming collection
isEmpty（0x10a9d786c），空则返回；非空launch TypeInfo0x11bb23fc0 coroutine
（0x10a9d78d0/0x10a9d7910/0x10a9d7928），body0x10a9d7eb0读同一个flow-container
.+0x10（0x10a9d80d8），hash0x483 slot+8 emit collection（0x10a9d8134）。已闭此flow的
emit→collector→缓存失效。DataCenter TypeInfo0x11bb23640/hash0x28680 slot+0x10实际
body0x10a9d4a70从.+0x28/0x38/0x30三CoreData取key collection
（0x10a9d4d6c/0x10a9d4dc0/0x10a9d4e24），合并（0x10a9d4dd4/0x10a9d4e38）并交
该emitter（0x10a9d4e44）。UpdateEngine apply→CoreData→nodeflow也已闭：coroutine0x10a9f91f0调用download wrapper
0x10a9fb934（0x10a9f9e44），resumed0x10a9f92c4恢复continuation，再读序列化配置
0x10a9e7230/parse0x10a9f1aa0（0x10a9f930c/0x10a9f9318）。数据nil分配ReadFile
exception TypeInfo0x11bb28180（0x10a9f93d4/0x10a9f93d8）；parsed nil或其version.+0x10
与目标不等（0x10a9f9320..0x10a9f932c）分配Serialize TypeInfo0x11bb28230
（0x10a9f9374/0x10a9f9378）。两分支清updating atomic Bool（0x10a9f9470）后绕过apply
（0x10a9f9478→0x10a9f98ac），不概括全部下载异常。

接受后取installed IDataCenter.+0x20，hash0x28680 slot+0x18
（0x10a9f9340/0x10a9f94ac）→actual DataCenter0x10a9d49ac，按environment enum==1
选.+0x38、否则.+0x40（0x10a9d4a04..0x10a9d4a2c），不是账号隔离。对actual CoreData
hash0x28600 slot+0x10传parsed config（0x10a9f94fc/0x10a9f9504），成功路径清updating
（0x10a9f9640）。DDContainer ctor实际factory0x10a9d5e40两次构造并存上述DataCenter
字段（0x10a9c4104/0x10a9c410c/0x10a9c4150/0x10a9c4154）。输入Bool非零alloc
CoreDataV2 TypeInfo0x11bb22a60（0x10a9d5ee0/0x10a9d5ee4/0x10a9d5ee8），零alloc
CoreData TypeInfo0x11bb222e0（0x10a9d6e88/0x10a9d6e8c），保留两分支，未读配置值。

CoreData slot+0x10=0x10a9cbd74→0x10a9cbdd0，wrapper/default mask使w26=1/w24=0
（0x10a9cbd80..0x10a9cbd90/0x10a9cbe0c..0x10a9cbe28），绕过另一incoming-version<=
stored拒绝（0x10a9cbed0..0x10a9cbee4）。mutex下写version atomic.+0x28
（0x10a9cc4c0..0x10a9cc4d8），安装collections到atomics.+0x30/+0x38/+0x40
（0x10a9cc524/0x10a9cc570/0x10a9cc67c），通知gate为true
（0x10a9cc788..0x10a9cc794），交node-key集合到同0x10a9d77cc（0x10a9cc90c），second
集合另交0x10a9d7950（0x10a9cc91c）；随后launch persistence0x10a9cc9dc
（0x10a9cc920..0x10a9cc930），不是磁盘完成ACK。
CoreDataV2 slot+0x10=0x10a9cf184→0x10a9d0490（0x10a9cf190/0x10a9cf194，w2=1），
同样绕过另一version拒绝（0x10a9d054c..0x10a9d055c），写version atomic.+0x38
（0x10a9d07f8/0x10a9d0810）与collections atomics.+0x40/+0x48
（0x10a9d0880/0x10a9d08d8），经0x10a9d1818（0x10a9d08f8）交node-key list到同emitter
（0x10a9d1a24..0x10a9d1a38），second集合另交0x10a9d7950（0x10a9d1a40..0x10a9d1a54）。
因此两实际backend的非空node通知都能进入DecisionCenter缓存失效；空集合仍不发node
事件。CoreDataV2完整body读至0x10a9d12b8后，程序次序已证RAM安装→
通知0x10a9d08f8→可跳过的异步持久task launch0x10a9d09ac。task TypeInfo
0x11bb230a0→body0x10a9d345c→JSON序列化→配置/版本两次setObject
0x10a9d3538/3560，接Settings0x1053e2a2c→NSUserDefaults API0x1053e2c10，
suite dd_core_data_v2（initWithSuiteName0x1053e02f0）。因此不是写盘完成后才通知。
下载输入文件的NSData.writeToFile:atomically:YES在独立callback0x10aa00440，
成功才resume到parse/apply；这不能与配置defaults异步持久写混为一件事。
物理IO成功和并发恢复交错仍运行期，已证程序顺序不归天然不可判。
证据root-static-remaining/findings.md。响应header
触发不能当apply完成，也不替换既有client/task。

更新结果归属与默认配置事件owner已闭合：versions callback 0x10004d9f4发出的
NSNotificationCenter通知名为`DDUpdateEngineDidUpdatedNotification`——名字由
Swift static accessor 0x1051306a8从字面量0x117aca650装入global 0x121073910
（0x1051306e4），post点0x10004dc74经0x1051306d4取该global。该accessor
（0x1051306d4）全量调用方仅3处：两处post（0x10004dc74与0x100049a9c）和
0x104950330——后者读配置`disable_memex_update`（0x104950290）后调
BFCMemexObserver.setDDUpdateNotiName:（stub经0x104950354），属Memex自有
BFCMemexUpdateEngine delegate链（setup 0x114553e28 setDelegate），不注册本通知。
即静态上该iOS通知无addObserver消费者（阳性对照：find_data_refs_root对
0x117aca650命中唯一writer 0x1051306a8；find_callers对0x1051306d4命中上述3点；
残余为动态NSNotificationName构造路径）。配置更新的实际消费主体是Kotlin
DataCenter node-flow→selective invalidation（0x10a9d4e44→0x10a9d77cc→
0x10a9dce28）。gateway interceptor触发的更新为火后不管：completion固定nil
（0x100135b98），V2 synchronous updateWith:返回值仅按
KntrIDeviceDecisionUpdaterResultSuccess dynamic-cast（0x100051160–
0x100051184），错误明细不透传调用方。

V2 synchronous updateWith:0x1000510ac取lazy updater（0x1000510e0），传provided String
与from=dd-v2到updateFrom:remoteData:（0x100051124），返回对
KntrIDeviceDecisionUpdaterResultSuccess dynamic-cast的Bool
（0x100051160/0x100051168/0x100051184），非调用即成功。
带force/test/from/completion版本0x100051780→0x10005119c（0x10005183c）按test选择
version env test/prod（0x1000511f8..0x100051204）；force bit true选
updateToLatestFrom:env:completionHandler:（0x100051254/0x1000512d4），false选
updateFrom:version:env:completionHandler:（0x10005138c）。两者是不同更新入口，回执另核。

真实native响应caller是DDApiGatewayInterceptor.canonicalGatewayResponse:
0x100135360→0x100135830（0x100135390）：取HTTPResponse.allHeaderFields
（0x100135894），必须response存在且cast为HTTP response
（0x100135868/0x100135884/0x100135888），本地request-header helper0x1001353c0所得dict
非空以及response allHeaders非空（0x1001358d4/0x1001358dc/0x1001358e0/0x1001358e4），
才lookup公开dd-v（0x100135980/0x1001359c4）。missing/nil结果
（0x1001359f0/0x1001359f4/0x100135a08）直接走释放/return（0x100135aa4），不会变成0。
存在非nil值时转换优先
String cast（0x100135a94），否则Int cast（0x100135ae0），失败置0
（0x100135ae8/0x100135aec）再description（0x100135b04）；result非空
（0x100135b20）resolve actual DD container（0x100135b28/0x100135b40），调用
updateWith:force:test:from:completion:（0x100135b9c），force=false（0x100135b90）、
from=http（0x100135b68..0x100135b74）、completion=nil（0x100135b98），test来自局部
ENV与test比较（0x1001358f8..0x10013594c）。本地helper读取cached SwiftString
0x121064b70，nil/empty则empty dict（0x100135404..0x100135418/0x100135568），非空分支
生成公开APP-KEY及ENV，ENV由服务isTestEnv（0x1001354f8）选prod/test；不要求response
含ENV，也未读取cached String实际值。存在非nil但String/Int都cast失败的dd-v会生成
String0，仍满足非空并触发update；原String为空则跳过。更新触发不代表成功或业务ACK。

该gateway有production注册：334 raw0 service zero-based index89/slot0x120272bd8
为BFCDDModule._$GripperDDUpdatePlugins。registration0x10003e144把API gateway
multibinding typeref0x120276370、provider metadata0x10003e53c（class0x120276460）、
callback0x10003e710、witness0x1202769c8交0x10513162c（0x10003e1cc，w5=1）。
witness.+0x10=0x10003dc20调用DDApiGatewayInterceptor metatype accessor
0x100135c2c（0x10003dc34），确为实际provider。同module另注册Moss gateway
（0x10003e214/0x10003e248；producer0x10003dc48→DDMossGatewayInterceptor metadata
0x100137f40及init0x1001376d4）。Moss response版本消费另核。native公共controller的
class实例化/canInit/response转发范围适用；不覆盖已知Ktor skip-gateway分支。
配置缓存失效也不自动替换once-cached HttpClient或迁移/取消已创建task。

### HD2 CardPool 的模型映射与实际 cell 注册

allModelClassDict（0x10df17d84）构造8项，缓存global0x120c98038。下表model类
均使用BBHD2PhonePegasus前缀；这不是任意card_type经NSClassFromString的回退。

| card_type | model类后缀 | class取值指令 |
| --- | --- | --- |
| large_cover_v1 | LargeCoverV1Model | 0x10df17dc0 |
| small_cover_v1 | SmallCoverV1Model | 0x10df17ddc |
| hot_topic | HotTopicModel | 0x10df17df8 |
| small_cover_v9 | SmallCoverV9Model | 0x10df17e14 |
| cm_v1 | AdSingleModel | 0x10df17e30 |
| three_item_all_v2 | ThreeItemAllV2Model | 0x10df17e4c |
| small_cover_v5 | SmallCoverV5Model | 0x10df17e68 |
| banner_ipad_v8 | BannerListModel | 0x10df17e84 |

allCardClassDict（0x10df17b1c）另构造17项，缓存global0x120c98030。下表cell类
除最后一项全名外，均使用BBHD2PhonePegasus前缀。

| reuseIdentifier | cell类后缀或全名 | class取值指令 |
| --- | --- | --- |
| local_refresh_v1 | MainRefreshCell | 0x10df17b58 |
| local_refresh_v2 | DoubleMainRefreshCell | 0x10df17b74 |
| local_dislike_v1 | SingleDislikeCell | 0x10df17b90 |
| local_dislike_v2 | DoubleDislikeCancelCell | 0x10df17bac |
| local_dislike_v3 | DoubleThreePicDislikeCancelCell | 0x10df17bc8 |
| local_dislike_v4 | DoubleDislikeV2CancelCell | 0x10df17be4 |
| local_dislike_v5 | SingleDislikeV2Cell | 0x10df17c00 |
| local_dislike_v6 | SingleDislikeV2ReasonsItemCell | 0x10df17c1c |
| local_dislike_v7 | DoubleBigCardDislikeCancelCell | 0x10df17c38 |
| local_dislike_v8 | DoubleThreePicDislikeV2CancelCell | 0x10df17c54 |
| large_cover_v1 | LargeCoverV1Cell | 0x10df17c70 |
| small_cover_v1 | SmallCoverV1Cell | 0x10df17c8c |
| small_cover_v9 | SmallCoverV9Cell | 0x10df17ca8 |
| cm_v1 | AdSingleCell | 0x10df17cc4 |
| local_dislike_cm_v1 | AdSingleDislikeCell | 0x10df17ce0 |
| small_cover_v5 | SmallCoverV5Cell | 0x10df17cfc |
| banner_ipad_v8 | BBHD2PegasusBannerV8Cell | 0x10df17d18 |

实际消费者是BaseCollectionVC.viewDidLoad（0x10dee53f0）：取CardPool映射
（0x10dee5688/0x10dee568c）并enumerate（0x10dee56e0）；callback0x10dee5ee0
弱读原VC的collectionView，以value注册class、key注册reuseIdentifier
（0x10dee5f28）。MainV2继承此base。cellForItem（0x10dee9488）对CURRENT VM.objects
做行边界检查，取当前model（0x10dee9540），要求BBHD2PegasusCardModelProtocol
conformance（0x10dee9564/0x10dee956c）；成立则直接用model.card_type dequeue
（0x10dee9578/0x10dee9594），设置delegate/context并installWithObject(model, argv:nil)
（0x10dee95f8）。越界或不符合protocol则走generic空cell（0x10dee9630）。
8项转换映射与17项cell注册分别承担不同职责；hot_topic/three_item_all_v2可转换不证明
普通cell已注册。动态注册、subclass覆盖与model自定义映射尚有边界，不由两表差异推断
运行时崩溃或不可达。

### HD2 设置响应字段到可见行及提交边界

FeedSettingVC.cellForRow读取当前dataArray[row]（0x10df07c40）后调用
FeedSettingCell.installWithObject（0x10df07c60）。install0x10df081dc先校验model类
（0x10df08214），title→myTitleLabel.text（0x10df08228/0x10df08250），
desc→myDescLabel.text（0x10df08268/0x10df08290），selected取反→checkImageView.hidden
（0x10df082a8/0x10df082d0）。这不是按value硬编码文案；错误model类型直接返回，
此body不清除复用cell原文案/check，实际复用呈现未运行验证。

新VC初始化仅对匹配项setSelected，不setSelectedModel；正常新实例未点选任何行时，
viewDidDisappear的selectedModel nil门禁（0x10df07a70）不提交followState。
已使用VC若复用，selectedModel未在已核viewDidLoad/viewWillAppear重置，不能把该
新实例结论外推到所有后续消失。MainVM.feedStateChangeWithDic（0x10df5b62c）只验证
input count、转换后的typed model及非nil，不要求option非空、title非空、唯一selected、
value在0/1内或已登录；客户端不能证明服务端发送此配置的生产原因/实验约束。

缺失/空follow_mode分支先置needFeedStateSetView=false（0x10df5b6d4），再把state1
转2（0x10df5b6fc）。KVO消费者重读needflag并以false跳过刷新；没有其他交错writer时，
这个响应驱动state写入自身不能满足刷新门禁。有效typed响应写feed_mode并置needflag=true
（0x10df5b6b0/0x10df5b6bc），不写followState；用户提交/其他选择事件另写state，
不能把这些producer合成无条件的‘响应模式变化立即重发’。
