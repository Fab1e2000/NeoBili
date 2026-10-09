# 崩溃插件的实际提交与本地缓存完成

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 崩溃插件的实际提交与本地缓存完成

BFCAnalytics.installAnalytics0x10513a864 setupAppUUID后main dispatch_after两秒
（0x10513a8c8）→0x10513a8dc→setupTrackerHandlerIfNeeded0x10513abac。
config.isExperimentalGroupHitForKey(app_tracker_kscrash_enable_v4)
（0x10513abdc）为false仅log，为true才把appUUID交shared handler并装callback。
app_tracker_power_consume_enable命中结果XOR1（0x10513ac88–0x10513ac8c）作为
installTracker参数，不能从key字面反推开关方向/线上值。
BFCTrackerHandler.installTracker0x105142d10创建WCCrashBlockMonitorPlugin，
enableCrash/enableBlockMonitor固定true，listener=self，reportStrategy=1；输入
Bool只决定是否装bGetPowerConsumeStack=true的默认block config，随后plugin.start。
真实listener桥0x10514f160→super0x105144688弱取listener
（0x1051446ac–0x1051446c0）→onReportIssue（0x1051446cc），nil则不提交。
Analytics callback0x10513ad00把同一report dictionary分别交
trackLog(app_reboot_track)（0x10513ad44）及
trackTech(public.crash.crash-report-scene.track,rate100)（0x10513ad74）。
AnalyticsModule装入的Tech closure0x100029b04解析optional
BFCMikotoService.Type（typeref0x120274960→0x1196beac2），调用实际service
trackTech:extendedFields:policy:rate:（0x100029bdc），policy raw2/rate原传，
复用已闭合Mikoto→Neuron transport；nil service返回false。Log closure
0x100029dcc另取optional BFCLogService instance（0x120274940→0x1196beb58）
调用logEvent:type:file:function:line:（0x100029ee4）。具体provider inventory
false index180/slot0x120273188为LogModule._$GripperLogProviderModule；
注册0x1049522b0用BFCLogService key0x120276350→LogProviderDependencyProvider，
getter0x104952234→0x10495217c经once0x104952580创建LogSystem
（0x104952600–0x104952618），不是直接把provider当service实例。
两者均为同步提交回调，没有HTTP响应参数。
### LogService注册、日志后端与远程配置采用时序

LogSystem构造读standard defaults bfclog.blog_enable到instance byte+0x10
（0x1049525e4/0x104952610），后续getter不刷新。logEvent实现
0x104953a00→0x1049536b4用type/event_details包装原dictionary，
NSJSONSerialization options8（0x104953868）后UTF8，失败不写；
成功经0x1049534b4/0x104953028按该snapshot选择以下出口。
false分支0x104953314→C logger0x11539bba4→global0x120db2368 BFCLogEngine。
engine init0x11539bfb8注册DDFileLogger到DDLog（0x11539c1fc）；
DDFileLogger.logMessage0x1153bda34转UTF8 NSData（0x1153bdb34）→
lt_logData0x1153bdf40→current handle.seekToEndOfFile→writeData:ddError:
（0x1153bdfa0），证明的是本地文件出口。可选BFCLogFileHandle封装mmap/zip，
其内部写入另追，不把文件logger当已上传。
true分支实际0x1049533a0→BLogger virtual+80=0x1050a1bf8，mLogger nil
直接返回；0x104953140是String.Encoding value-witness destroy，不是sender。
ProviderModule exec0x1049524a8→0x1049529e4先构造DDLogger，再按同持久Bool
false传DDLogger、true传nil给BLogger init slot+78=0x1050a1ab0
（0x104952c08）。此处nil会构造BLogServiceDefaultImpl；已有非nil mLogger
不替换。DefaultImpl log0x1050a26b0 level4选BLog.error
0x1164801c8→0x116480204→C0x116486584，coreglobal0x1210df460 nil跳过，
非nil到0x1164802d0；core内部持久化/上传还在追踪，无Crash服务器ACK证据。
配置更新入口LogModule0x104951890→0x10495262c先resolve LogService并excute
（0x1049526bc/0x104952720），之后才取optional DeviceDecisionService交
0x104955c48：log.blog_enable defaultfalse→写bfclog.blog_enable
（0x104955ccc/0x104955d0c），log.use_oslog→bfclog.is_use_oslog。
该updater没有写已构造LogSystem.byte+0x10，故不能声称同进程即时采用新开关；
文件大小等已有缓存配置及其他task顺序仍须分别核对，不输出实际配置值。
### Crash实验门禁与issue模型

实验Bool配置callback0x100029d18解析DeviceDecisionService
（typeref0x120274938），调用getBoolForKey:defaultValue:false
（0x100029d9c）；缺service/未命中默认false，因此不能据插件构造固定true
认定所有启动都安装Crash。具体分组仍是服务端/本地配置结果，未读取实际值。
onReportIssue0x105142ee0按plugin tag/reportType/dataType分支。Lag reportType2
的五字段app_launch_time/uuid/key/log/call_status中log是类型label；generic
NSData/UTF8分支五字段app_launch_time/diagnosis/uuid/key/log中log是UTF8文本，
diagnosis尝试解析crash.diagnosis，失败退固定说明（0x105143388–0x10514360c）。
其他dataType分支四字段app_launch_time/uuid/key/log。app_launch_time取
reboot analyzer，uuid取handler.app_uuid，key取issue.filePath；只记录来源，
不输出实际报告/身份/路径值。payload无效可跳过提交。
**正常返回的共同尾部无条件reportIssueComplete(issue,true)**
（0x105143684），不测试tech callback Bool、不等待网络结果；无callback/无效payload
路径也可到这里。插件0x10514f1a0排serial pluginReportQueue
（0x10514f224，init nil attributes0x10514ece8）。reportType1 success==1
调用deleteCrashDataWithReportID（0x10514f538），无论success都移除uploading ID；
成功且队列空继续delayReportCrash。Lag成功也删相应文件
（0x10514f844）。这只是本地交付后清理，不证明服务端ACK。
plugin.start0x10514ed84在安装后delayReportCrash（0x10514f004）；helper
0x1051505cc main再延两秒，strategy1→reportCrash0x105150978→serial queue。
缓存非空且未uploading时取一份报告、加入uploading、构造issue
（0x105150c08–0x105150c40），排main回plugin.reportIssue
（0x105150e2c–0x105150e34）。这是启动/后续本地完成触发的缓存重放，未证
活体崩溃发生时发送或HTTP失败重试。
loadPendingCrashReportID0x10514aaf8枚举KSCrash.allReportID，取首个按"-"拆分
component count<6的ID（0x10514b340），wrapper未排序/TTL检查；底层顺序未证。
getPendingCrashReportInfo0x10514a7a8读取报告JSON encode，nil/空编码直接删除
（0x10514a9f4），独立于网络。删除最终到NSFileManager.removeItemAtPath:error:
（0x1051759b4），未测试返回Bool/error，因此连磁盘删除成功也不能由local completion
反推。缓存捕获writer在KSCrash第三方库内部、完整配置取值由服务端DeviceDecision下发，均属
静态不可穷尽/不可定项；下一步 query_index.py '*KSCrash*' 30 圈定缓存链，find_callers.py
0x10514f538 核对删除链；Log独立出口已闭合至C 0x116486584，业务初始化可达性由实验门禁
0x10513abdc运行期决定。

<a id="crashkscrash-提交路径与-laser-回执端点task-18-补"></a>

### Crash/KSCrash 提交路径与 Laser 回执端点

KSCrash 类本体在主二进制内。自身发送器 `-[KSCrash sendAllReportsWithCompletion:]` 0x105174854 →
`-[KSCrash sendReports:onCompletion:]` 0x105174c7c 需要 `-[KSCrash sink]` 0x105175b50：sink 为 nil
时建 KSError（描述串 CFString 0x11d0e4b70 = `No sink set. Crash reports not sent.`，
0x105174d64–0x105174d98），非 nil 才 `[sink filterReports:onCompletion:]`（0x105174d30）。
本样本内该发送器没有调用方：`query_index '*objc_msgSend$sendAllReportsWithCompletion*'` 零命中；
阳性对照 `'*objc_msgSend$allReportID*'` 有 j_ stub 0x10f83ab90 与规范 stub 0x1171da660，且应用侧
唯一消费者是 `-[BFCTrackerHandler loadPendingCrashReportID]` 0x10514aaf8；setSink: 的 stub
0x11762d1c0 唯一调用点 0x1148dcaa0 属 ConnectionManagerGetProtocolInfo，与 KSCrash 无关。
即 8.89 样本里崩溃报告不由 KSCrash 自身 HTTP 发送器发出，实际提交仍是 onReportIssue:
0x105142ee0 组字段（Lag 5/generic 5/其他 4 字段）→ Analytics callback 0x10513ad00 →
trackLog(`app_reboot_track`)/trackTech(`public.crash.crash-report-scene.track`,rate100)
（0x10513ad44/0x10513ad74）→ Mikoto/Neuron（LOG-01 通道）或 LogService，两条都无 HTTP 回执。
本地缓存/删除维持既有：loadPendingCrashReportID 0x10514aaf8、getPendingCrashReportInfo
0x10514a7a8（空编码即删 0x10514a9f4）、reportType1 成功 deleteCrashDataWithReportID
0x10514f538、removeItemAtPath:error: 0x1051759b4（不检查返回）。措辞保留：chained-fixup/
运行期拼 selector 不能静态排除 sink 被设置。

Laser 五个 wrapper 端点与四个 Api 入口一一对应（本轮闭合 UP-01/UP-03 残余）：
`+[BFCLaserConstWrapper silenceURL]` 0x104e30f70 = `https://app.bilibili.com/x/resource/laser/silence`、
laserURL 0x104e31070 = `…/laser`、laser2URL 0x104e31174 = `…/laser2`、reportCommandURL
0x104e31278 = `…/laser/cmd/report`、uploadURL 0x104e3137c =
`https://api.bilibili.com/x/feedback/uploadFile`（源文件
`srcs/base/BFC/Fawkes/BFCLaser/LaserConstWrapper.swift`）。调用侧：
reportFawkesCMDTaskByBroadcast: 0x114a888d8 用 reportCmdUrl（0x114a88990）、
reportFawkesTaskByBroadcast: 0x114a88cb8 用 laserUrl（0x114a88d70）、
reportFawkesTaskByPush: 0x114a89080 用 silenceUrl（0x114a89138）、reportFeedback: 0x114a89448
用 laser2Url（0x114a89548，经 `+[BFCLaserConst laser2Url]` 0x114a8dc20）。reportFeedback: 的请求体
8 键 + 条件 task_type（dictionaryWithObjects:forKeys:count:8，0x114a89690）：app_key←fawkesKey、
buvid←`+[BFCBuvid buvid]`、status←@(status).stringValue、url/raw_upos_uri/md5/error_msg/task_id
分别取形参（nil→空串），task_type 非 nil 才 setObject:forKeyedSubscript:（0x114a896f0）；
setRequestMethod:1（0x114a89580），回执经 apiModelDescription→modelWith:/data（0x114a89740）后
requestWithOptions:（0x114a897a4），重试参数 3/3 见既有条目。即 BLog/日志附件链的提交 =
UPOS（UP-01/02）上传 + 本段 laser2 回执，两层判定；BLog 队列产物（`Documents/BLog` 日文件，
BLogAttachment.localPaths 0x104953c98→0x104955284，先 flush BLogger）经 provider
（0x12028f0c0，witness 0x1049514a0/0x1049514d8）→ TaskOperation.uploadAfterPackup 0x114a91348
打包后进入该链。

LogService 双出口的字段级补充：logEvent 实现 0x104953a00→0x1049536b4 以 type/event_details
包装原 dictionary，NSJSONSerialization options=8（0x104953868）后 UTF-8，失败不写；false 出口到
C 0x11539bba4→BFCLogEngine 0x120db2368，engine init 0x11539bfb8 注册 DDFileLogger，写入点是
seekToEndOfFile + writeData:ddError: 0x1153bdfa0，**未读 ddError**；true 出口 BLogger
virtual+80=0x1050a1bf8 在 mLogger=nil 时直接返回，DefaultImpl log 0x1050a26b0 level4 选
BLog.error 0x1164801c8→core global 0x1210df460，无 HTTP ACK。远程配置 updater 只写
bfclog.blog_enable/bfclog.is_use_oslog，不写已构造 LogSystem.byte+0x10（该 byte 只在构造时从
standard defaults 读一次，0x1049525e4/0x104952610），同进程内新开关不即时生效。

不可判（明写）：KSCrash 报告 writer 的完整字段集属第三方运行期（需真机触发一次可控崩溃后读沙盒
报告 JSON，或断点 0x105142ee0 dump dictionary）；sink 是否可运行期设置需断点 0x105175b50 观察；
Neuron/LogService 是否被服务端收取需 9.13 抓包按事件名过滤；BLog daily/quota 旧 job 筛选仍分散在
多个 helper（下一步 `disassemble.py 0x116481bfc 0x116483000`）。证据
DerivedData/Validation/team-c13/findings.md。

<a id="laser-附件任务的日期窗过期与外部清理task-13-补"></a>

### Laser 附件任务的日期窗、过期与外部清理

任务"过期"即上传日期窗：`+[BFCLaser shared]` 初始化（0x114a89a84）尾部明确
`setUploadLogsPassedDay:` 传 w2=2（0x114a89bfc），即默认仅收集最近 2 天附件；
LaserModule 启动 setup 里以 Swift 字面量键 `laser.passed_day`（cstring 0x11776fa70，
引用点 0x100077a24）经 `getIntegerForKey:defaultValue:`（selref 0x11f677918 处加载）
读取配置覆盖。getter stub 0x11772c100 的全部 6 个消费点集中在
`+[BFCLaser uploadAllLogsWithTag:completionHandler:]`（0x114a8a464，sites
0x114a8a580/0x114a8a5c4/0x114a8a6c4）与 `-[BFCLaser uploadAllLogs:]`
（0x114a8a8d4，sites 0x114a8a92c/0x114a8a950/0x114a8aa34），即 passedDay 只参与
uploadAllLogs 的日期过滤，不参与 Moss 下发任务（didReceivedTask）路径。setter stub
0x117655080 全镜像仅 2 个引用：shared 初始化与类方法包装 `+[BFCLaser
setUploadLogsPassedDay:]`（0x114a89fb0→0x114a89fd4），无其他业务写入方。
Moss 下发任务本身无 TTL 分支：didReceivedTask（0x114a8af24 已读 body）仅
laserType 1/2 → containsTaskId 去重，命中 trackTaskStatus resultCode 10、
task 为 nil 记 4、miss 才 addTaskId+addTask 入队；无时间/过期比较。
外部清理边界：BFCLaserPreferences（固定 suite，继承 getter 0x1167d33b8）样本内无
removeTask/clear 类方法（query_index '*removeTask*'/'*clearTask*' 无 Laser 命中），
tasks/topTaskIds 只有 addTask/setTopTaskIds 写入方（0x114a90858/0x114a90954），
样本内**没有任何逐 key 删除者**（已按上面两条命令枚举写入方，全为 add/set）；suite 级
removePersistentDomainForName: 0x1174d7ea0 已由既有证据排除（全镜像仅 UASDKStorage 一处调用）。
若要再收窄，下一步对 `refs-results.json` 的 Laser suite 名字面量做 `find_data_refs_root.py` 复查
是否有 registerDefaults 之外的整体覆盖写。
因此去重索引与任务列表在样本内只增不减，跨任务积累行为属运行期可观察项。

<a id="upos-取消后-laser-completion-的回执链task-14-补"></a>

### UPOS 取消后 Laser completion 的回执链

UPOS Base failure closure（`-[BFCUpOSBaseRequestManager sendRequest]_block_block`
0x114aa8d48）：请求 error（含取消经 Operation 门禁替换出的 NSURLErrorDomain -999）先
sessionEnd:error:（session 错误码 raw4），currentTimesOfRetry+1；continousFailure 时轮换
optionalEndpoints（index+1 对 count 取模，0x114aa8e48–0x114aa8e8c）；
`currentTimesOfRetry < timesOfRetry` 则 dispatch_after(intervalOfRetry×1e9, main) 重入
sendRequest；预算耗尽才构造错误码 raw6 的 NSError 走 `failureWithError:`
（0x114aa8f84→0x114aa8f8c）。sendRequest 入口有 checkError 与 `isStop` 双门禁
（0x114aa8a0c/0x114aa8a18 tbnz 直跳 epilogue 0x114aa8c5c）：Base.stop（取消）置
isStop=1 后，已排队的重试 dispatch_after 落到入口即**静默返回**——不再发请求、不产生
failure、不回 completion。`failureWithError:`（0x114aa93a8）经
context.taskCallbackManager `notifyTask:didCompletedWithError:`（0x114a9ba44），
后者在 delegateQueue 排 block 0x114a9bc38：读 `task.completionHandler` 非 nil 即以
(error, task.storageInfo) 调用（0x114a9bc90 blr）。因此 Laser completion（0x114a92290）
与其 semaphore signal（0x114a923e8）只在重试预算耗尽的 failure 路径发生；
取消通知 uposUploadTaskDidCanceled（0x114a9be9c→0x114a9bfbc）不经 completion（已闭合）。
补充结论：取消时若仍有剩余重试预算，Laser 等待侧既不完成也不失败，直至其他路径；
是否真实发生取决于 cancel 与重试调度的时序，属运行期交错，静态不可定
（建议真机断点 0x114aa8ed8/0x114a9bc38）。
