# 推送注册、权限状态与设备上报

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 推送注册、权限状态与设备上报

PushModule 的三个调度事件应分开：ApplicationLaunch runnable（0x1001a7770）
调用setup（0x1001a7800），trigger为applicationLaunch、main线程、默认priority450；
ModuleInitialize runnable（0x1001a7960）经0x1001a7abc调用start（0x1001a7ae0），
trigger为moduleInitialize、main线程。homePageInitialized另执行内容放行和失败路由重试，
不能按函数地址推出框架的全局事件先后或priority比较方向。
setup的AppDelegate=nil分支跳过服务安装和Center配置，但仍注册五个生命周期通知。
Helper的WillEnterForeground（0x1001b1b64）把当前badge十进制记为
main.active.redpoint.0.click的num，没有正数门槛、没有清badge；它与下述Center
DidBecomeActive清badge并发callback/badge是两条链。

BFCPushService.initializeWithAppDelegate（0x115e02908）以self+8 bit0一次门控，
首次先写initialized，再associatedObject保存服务、用class_replaceMethod安装五个
AppDelegate通知方法，并设UNUserNotificationCenter.delegate=self；该局部未保存旧IMP。
静默收包（0x115e03b00）传原userInfo给Center，随即调用fetchCompletion raw0，
不等待路由/网络完成。Center（0x1149e97d4）构造type1/silent=true的content，
先forward再通知contentHandler，本体不发callbackClick；不能把type1静默收包当成点击。
旧本地通知（0x115e03be4）type0、identifier取userInfo.task_id；它会forward，
但不进入远程type1的点击API，identifier也不同于UNresponse的request.identifier。

APNs didRegister 回调（0x115e0395c）逐字节用 `%02lx` 转小写两位 hex，没有固定
NSData 长度校验，再交 BBCPushCenter。Center（0x1149e94fc）先更新 RAM token 和
BBCPushNotificationPreferences.deviceToken，再发 type=1 上报并通知 delegate，
不等待上报成功；init 会从 Preferences 恢复旧 token。APNs 失败仅转交 error，
Service 不清旧 token；接收错误的 Center（0x1149e9688）实际再发 type=4
（0x1149e9794），随后也调用 didRegister delegate。此 Center body 未清 RAM/
Preferences token 或 settings flags，所以 type4 可能带旧 token，delegate 名称
不能作为注册成功证据。

registerWithOptions（0x115e02ef0）以 options&0x47 申请通知权限；completion
不消费 granted/error，随后读取 settings。Center（0x1149e930c）保存 settings，
计算 notificationOpen，并置 notificationRegistered=true，再无条件调用 APNs
registerForRemoteNotifications。registered 因而不能等同于用户同意。open 的算法
0x1149e8030：authorizationStatus=3 为 true；=2 时要求 lockScreen/
notificationCenter/alert 之一为原始值 2；其他为 false。
PushHelper 正常启动传 options=7；提示 UI 确认路径在 status=0 时申请 options=7，
其他状态打开应用通知设置。GPPushNode.startIfAuthorized 实际条件为 status!=0，
不能凭名称缩成 status=2。启动注册的全局顺序由框架runable调度在运行期决定，静态不可排定；
静态侧trigger/priority已闭合（0x1001a7770 applicationLaunch/450、0x1001a7960
moduleInitialize），残余仅能以真机启动日志验证先后。

PushHelper.setup（0x1001a9c34）默认设 Center.appId=1；注入 service.productID
精确等于字符串 `14` 时改为 7（0x1001aa1a4），再连接 Service.delegate=Center、
Center.delegate=PushHelper。因此 app_id 也不能统一写为 1。启动 DD
`dd_push_new_install_use_custom_alert` 默认 false，与 isNewInstall 同为 true 才跳过
正常 start。使用 custom view 时查询 settings：status!=0 才注册 options7；status=0
也会递增 rn。rn setter 只写 RAM/Preferences，不发上报，启动 UI 完整顺序仍在追踪。

上报入口 sendPushReport（0x1149e80f0）没有以 token 非空/open=true 拒绝请求。
事件类型为 1:APNs token 到达、2:账号登录/切换、3:退出、5:notifyChangeToken、
4:APNs 注册失败、7:前台重新读取 settings；账号 update 回调是 RET。
type5 的两个明确消费者为 PushModuleRestrictedModeObserver（0x1001a8f7c）和
GPPushHelper（0x10f6d3688）的 enableChangedOfMode:，均查询传入 mode 的
BFCRestrictedModeManager.enableOfMode，true 才发 type5（该上报实际读取的 token 点已按0x1149e80f0/0x1149e8238闭合，见下行限定）。模块初始化
0x1001a944c 注册前者，无 mode 过滤参数，dealloc 移除。mode 枚举已闭合：
BFCRestrictedModeManager.modeControllerWithMode:0x115963bcc对入参NSUInteger
cmp #1：0→objc_msgSend$teenagersMode（青少年模式controller）、1→
objc_msgSend$lessonsMode（课堂模式controller）、其他值原样透传（0x115963bdc
cbnz直接返回入参，非controller）。enableOfMode:0x115961090即
modeControllerWithMode:.modeEnable（0x1159610b4/0x1159610d0）。事件源为
BFCRestrictedModeManager.modeEnableChanged:needRefreshApp:0x11596363c：在
pthread_mutex锁下copy观察者数组（self+0x58，0x115963680），逐个
objc_opt_respondsToSelector enableChangedOfMode:后以mode调用
（0x115963700–0x115963710）；needRefreshApp非零再
postRefreshApplicationNotification，并经NSNotificationCenter发带
mode=numberWithUnsignedInteger的BFCRestrictedModeDidChangedNotification
（0x115963754–0x11596379c）。故type5在青少年或课堂模式开启事件到达时触发；
该请求所用 token 读取点已闭合：sendPushReportWithType:0x1149e80f0 在0x1149e8238取
self+0x20，并于0x1149e8394–0x1149e8398作为deviceToken:实参（x3）传入
pushReportWithAppId:deviceToken:notifySwitch:type:extra:（stub0x1174afa60，全镜像唯一
调用点0x1149e8398）；Center.deviceToken getter0x1149e9c48即ldr x0,[x0,#0x20]，该ivar
唯一写入点是APNs didRegister 0x1149e95f4–0x1149e962c（find_callers.py 0x1175738e0 对照，
另三处setDeviceToken为BFCRestrictedModeSynchronize/AliyunIdentity/BFCMossConst无关类）。
故type5与其他type共用同一Center RAM token，即为最近一次didRegister写入的APNs token；
注册前的初值是init 0x1149e7940自BBCPushNotificationPreferences恢复的旧值，其新鲜度属
运行期状态，静态不可定，也不能将 type5 等同于 APNs 新 token 或某个固定限制模式。extra 记录六个数字枚举：
authorization_status/sound_setting/badge_setting/alert_setting/
notification_center_setting/lock_screen_setting。

BBCPushApi.pushReport（0x1149e6df4）向 x/push/report 发 method=1，ignoreCache=true，
12 字段为 app_id 十进制、buvid（Const 0x104e2dab0→BFCBuvid.buvid，跟踪36字符）、
device_token（nil 空）、push_sdk=`1`、time_zone（Date 当前时区秒数÷3600向零截断）、
notify_switch 布尔十进制、type 十进制、mobile_brand=`Apple`、mobile_model=
UIDevice.bfc_platformString、mobile_version=systemVersion、extra 的 yy_modelToJSONString、
push_to_start_token（standardUserDefaults/ActivityPushToStartToken，nil 空）。
此 body 的 requestAsync 没有业务 completion/响应校验，也没有失败回滚 token 或
递归重试；公共网络层行为独立。BBCPushApi.init（0x1149e6d98）明确把默认 host=`api.bilibili.com` 存 self+8，
report 以该属性组装 `https://%@/x/push/report`。Center.setApiHost（0x1149e7dcc）
只是tail call `_objc_msgSend$setHost:`写内部API的host属性；本镜像符号表不存在
`_objc_msgSend$setApiHost:`调用桩（query_index仅命中方法表selector字符串
0x11a2d1b4b），即无任何调用点为该selector编译出msgSend，默认 host 在静态
镜像内无覆盖入口（残余：NSSelectorFromString等动态调用静态不可排除）。
上报额外初始化计数继续追踪，未读取
实际 token 或 prefs 内容。

### ActivityKit 两种 token 的独立上报

ActivityTokenMonitor（0x102bc72cc）创建 TokenState actor 时将 token/startToken
两个 Optional 清零，不从 NSUserDefaults 恢复。pushToStartTokenUpdates
（0x102bca134）逐字节 `%02x` 后空分隔连接，先与 actor.startToken 比较；相等
跳过，不同则更新 RAM，再写 standardUserDefaults/ActivityPushToStartToken
（0x102bca9f4），然后才启动报告。它读取 persisted old token 给状态/telemetry helper，
去重判断仍用 actor，不能据磁盘 old==new 就说进程首次更新不报告。
Activity.activityUpdates→每个 Activity.pushTokenUpdates（0x102bc7e88）独立产生
push_token，同样小写 hex；ActivityState ended/dismissed 跳过此次处理，其他状态
与 actor.token 比较，变化才更新 RAM 和报告。该分支未见持久化，也不是 APNs token。

两种变化均走 0x102bc93ac→0x102bc94b8→reportWithRetry（0x102bc5bf8），不调用
Center.notifyChangeToken。报告（0x102bc61a4）向固定
`https://api.bilibili.com/x/push/report` 发 method=1、ignoreCache=true，仅7字段：
app_id=`1`、跟踪 buvid、type=`1`、push_to_start_token=actor.startToken、
push_token=actor.token、push_sdk=`1`、当前时区小时向零截断；两个 Optional 字符串
nil 退空。它与普通 Center 的12字段请求、device_token 和可覆盖 host 不同。
retry 仅在两个 Optional 都 nil 时本地拒绝，空但非 nil 的字符串通过此检查。
调用方 limit=3，失败最多3次尝试，间隔1秒，最后抛错；sleep 取消直接走错误，
不增加第4次。completion（0x102bc58ac）直接 resume(returning:)，error
（0x102bc5a4c）resume(throwing:)，此 body 没有独立业务 status 检查；公共网络层
的判错另论。报告失败不回滚缓存，相同 token 的后续 update 仍可能被 actor 去重。

启动模块（0x102bc2fac）要求 dd.liveactivity_enable（默认 true）与 runtime
availability 17.2.0 均通过。start（0x102bc2890）的 tokenmonitor_delay 默认 false、
monitor_delaytime 默认10秒；delay false 或 applicationState 原始2立即监控，其他
情况延时，睡眠后不重新检查状态。startTokenMonitor（0x102bc6e8c）先创建
activityUpdates/pushToStartTokenUpdates 两任务，再读取 areActivitiesEnabled 做
日志与 cold_start 设置 telemetry，该读取不是此入口的权限 gate。两个任务在已读
创建 iterator 之前也未再检查它；框架是否交付 token 不能由 caller body 代替证明。

### 通知点击、延后导航与 badge 回执

BFCPushService.didReceiveNotificationResponse（0x115e03d70）按 request.trigger 是否
为 UNPushNotificationTrigger 取 type=1/0，转 delegate 后立即调用系统 completion。
Center（0x1149e99a8）先 forwardContent，再仅 type=1 调 callbackClick，最后通知
didReceiveContent。dismiss 也经过此 forward，不直接等同于“没有导航/回执”。
自定义 action 按 rich_1.0/rich_media.buttons 的 identifier 匹配，button type 为
remove 才 click=4，其余 click=0；dismiss 本身也取0。

点击 API（0x1149e7314）向可覆盖 current host 的 `/x/push/callback/click` 发
method=1，设置 app=appId 十进制、task=userInfo.task_id 的 `%@` 格式、
push_sdk=`1`、mid=Const 注入 service.mid 十进制、token=当前 APNs token（nil空）、
click 十进制与 extra。task nil 没有门槛，会经格式化形成 `(null)`。extra 仅自定义
action 传 `{button: actionIdentifier}` 并 yy_modelToJSONString；其他 action 传 nil，
字典下标会省略该键，不能把七条赋值语句描述为七个键必带。此 API 没有业务回执
或重试 block，不能由客户端发送证明服务端接受。

forwardContent（0x1149e8978）在 handleAllow 恰为1时 main.async execute，否则
同步追加 RAM 数组；setHandleAllow 非零即 flush，不比较此前值。flush
（0x1149e8d90）把各条 main.async 给 contentHandler 后清数组，没有再次发送 click
回执。因此系统 completion/点击回执不等待延后导航完成。
homePageInitialized放行runnable读push.delay_handle_allow：signed<1立即，>=1
按Double秒main.asyncAfter；放行priority400、retryFailed priority200均为main，
调度器比较方向未证，不能按数值断言先后。
Helper构造（0x1001a9738）把普通/静默失败数组初始化空RAM；初次路由失败分别
append72-byte tuple或content对象。普通缓存还有主动延后条件，并非全是失败：
handle（0x1001b4144）只有launchOptions远程task_id为非空String且等于当前task时
才检查冷启动加速。dd_push_handle_url_try_speedup默认false，false直接缓存延后；
true时dd_push_url_can_speedup_pattern（默认空）必须正则匹配location=0且覆盖
完整UTF-16长度才尝试导航，否则也缓存。加速导航失败另append；无/不同冷启动task
直接route，该分支失败未见同样append。不能据数组名概括所有路由失败都重试。
retryFailed经main.async到0x1001ad04c，
静默数组仅scheme=bilibili且host=laser的有效URL才重路由；普通数组直接
processUrl:animated=true。已读循环结束没有清空/移除缓存。
该重试不再次调用HTTP callback/click，但action字符串非空时会记
push.push-message.action.0.click（0x1001aec0c），含action_id/task_id/当前Center token；
另有public.apns.ground.other路由结果埋点，不能概括为重试没有点击报告。
初次payload URL选择由服务端下发payload在运行期决定、框架全局事件顺序静态不可排定；
静态侧冷启动加速门禁已闭合至0x1001b4144，下一步 disassemble.py 0x1001b4144 0x1001b4260
复核后以真机启动日志验证顺序。

导航parser（0x1001b0820）rich按钮按id匹配非nil actionIdentifier，读取字段
`link`；type为空/default/remove保留link，其他非空type清空link。没有匹配按钮
才回退顶层userInfo.url String。remove虽记录tuple flag，已读主handle没有用它
跳过route；因此remove点击raw4或dismiss不能单凭名称推断不导航。
parser为导航URL补缺失的na.src=push、from_module=push-pop，保留已有同名query，
重新拼回fragment。这些是导航归因参数，不是callback API字段。
silent分流（0x1001af0f8）只接受原始url的scheme=bilibili/host=laser，合法后亦按
上述相同launch task/DD加速决定立即导航或缓存；普通不同task失败的局部仅报错与
ground埋点，不追加silent缓存。静默收包无HTTP点击回执，仍有
public.apns.trigger.other收包埋点与public.apns.ground.other路由结果埋点；
不能把无点击API概括为无上报。消息与payload实际内容未读取。

willPresent（0x115e03cd4）仅回系统 presentation options：applicationState 原始1
为27（iOS14+）/7，其他为8/0，不在该 body 转发或发点击回执。
收包 payload 键级解析点（team-33 补）：`-[BBCPushNotificationCenter callbackClickWithContent:]`
0x1149e8410 从 `notificationResponse.userInfo` 读 `id`/`type`/`task_id`/`rich_media`
（`bfc_arrayForKey:`，元素取 `buttons`、type=='remove'）并读取 `categoryIdentifier`/
`actionIdentifier`，再经 stub 0x117232020 转 `callbackClickWithAppId:task:type:deviceToken:extra:`
0x1149e7314；静默收包点 `pushService:didReceiveSilentRemoteNotificationWithUserInfo:`
0x1149e97d4。click 请求体键与来源（0x1149e7314 逐 setter）：`task`←入参、`app`←appId
intValue 格式化、`push_sdk`='1'、`mid`←`[BBCPushNotificationConst mid]` longLong 字符串化、
`token`←deviceToken、`click`←type 字符串化、`extra`←yy_modelToJSONString（nil 省键）；
badge 请求体（0x1149e75c4）：`mid`/`buvid`←Const buvid/`device_token`/`number`←入参字符串化/
`type`='number'/`action`='clear'/`app`。本地通知构造字段 `-[BFCPushService
scheduleRequest:identifier:]` 0x115e03400：title/body/badge/sound（非空 soundNamed 否则
defaultSound）+ userInfo 可变复制后 identifier 覆盖 `task_id`；旧本地通知入口
`application:didReceiveLocalNotification:` 0x115e03be4 以 `userInfo['task_id']` 为
identifier 包成 `BFCPushNotificationResponse initWithType:0` 走同一 delegate 通道。
Center.applicationDidBecomeActive（0x1149e9274）只处理 signed badge>=1，先调用
setApplicationIconBadgeNumber(-1)，再报告旧正数；不要把 setter 参数归一化为0。
badge API（0x1149e75c4）向 current host 的 `/x/push/callback/badge` 发 method=1，
七字段 app/mid/buvid/device_token（nil空）/action=`clear`/type=`number`/number=
旧值十进制，该 body 没有 push_sdk。异步无业务 completion/重试，失败不还原本地 badge。

收包和路由埋点的字段来源独立：trackTrigger（0x1001ac4f0）的
public.apns.trigger.other含payload=原始userInfo经JSON options0/UTF8，失败省略；
task_id/url取原始String，否则空；app_state取UIApplication状态十进制。
该入口未见type/silent/remove过滤。trackGround（0x1001adde0）的
public.apns.ground.other同样含payload/task_id/url/app_state，另加ground_url=
实际路由URL、result=bool bit0的0/1、error=NSError.localizedDescription或空。
重试也记录ground，不能当作APNs HTTP receipt。

didReceiveContent（0x1001b2f48）先trackTrigger，再构造app.active.growth.sys；
remove/silent/local三个parser flag任一为true时不发growth。九String字段为
open_app_from_type=push、open_app_uid/groupid/url为空、open_app_addition=parser task、
open_app_wake=非空且相同冷启动task时1否则2、session_id=BFCActiveReport.sessionId
或空、idfa=BFCIDFA.idfaString或空、deeplink_id=最终路由URL。这里session并非
Ktor lazy会话来源；过滤growth不代表禁止导航。未读取真实payload/IDFA/session。

### IM 未读与消息同步链的入口与消费（BBLink 桥，task-11 补齐）

消息链 ObjC 桥入口 `-[BBLinkConnectManager install]`（0x10e5f3368）：读
BFCMossStreamReachability.isReachable（0x10e5f3394）写 connected；新建
BBIMSynchronizeHandler 并把其加入该 handler queue 的 delegate（0x10e5f33b0–0x10e5f3404）；
self 另加入 BBLinkAuthority 的 delegate 机制（0x10e5f3418–0x10e5f3450）；注册
mossReachabilityDidChange: 通知（0x10e5f3464–0x10e5f34a0）；尾部按
BBLinkClientConfig.isDelayLoadConfigApiEnable（0x10e5f34a8）门禁后 tail 到
checkRefreshInfos。install 的 find_callers 为 0（共享 selector 无独立 stub），装配方属
运行期间接派发，静态不可定。checkRefreshInfos 0x10e5f3530 仅 BBLinkAuthority.login 非0
才经 synchronizeHandler 发 fetchRemoteRelations（0x10e5f355c–0x10e5f3584）；
`authority:login:` 0x10e5f3670 仅 login=true 才触发 checkRefreshInfos，登出不在此处理。
同步回执消费面为 BBIMSynchronizeHandler 协议组 0x10e5f3154–0x10e5f3360：
didSynchronizeMesssagesFailedWithError:（0x10e5f3358）是同步失败分支入口；
didSyncReceiveMessages:hintMessages:notifications:messageRange:continued:（0x10e5f31ec）
转 _respondReceivedMessages:messageRange: 0x10e5f367c / _respondReceivedNotifications:
0x10e5f3744；_respondUpdateSessionsWithSequenceNumber: 0x10e5f3874 经 delegates 转发
connectManager:didReceiveUpdateSessions:（selref 0x11f7cd950）。
已读回执 updateRemoteAck:completion: 0x10e5f3d48 读 item.maxSeqno/locSeqno
（0x10e5f3d88–0x10e5f3da4）交 synchronizeHandler.updateAckWithItem:completion:
（0x10e5f3dd8→BBIMSynchronizeHandler 0x10e4ccb98）：请求侧 ackSeqno 的取值优先级是
item.maxSeqno 非 nil 时直传，否则退 item.locSeqno.unsignedLongLongValue（0x10e43e42c），
不是把两个字段拼接，也不是推送 task_id；字段级见下节。
未读映射 `+[BBLinkGetUnreadModel unreadModelWithMossRsp:]` 0x10e62c304 tail 到
initWithTotalRsp: 0x10e62c154：totalUnreadNew.unreadCount→totalUnreadCount、
unreadType→totalUnreadStyle、msgFeedUnread→msgFeedWithMossRsp:、sessionUnread→
singleWithMossRsp:、sysMsgInterfaceLastMsg→sysLastMsgWithMossRsp:
（0x10e62c1a0–0x10e62c2d0）。推送到达后的 IM 消费：`_handleRemotePushNotification:`
0x10e644718 断言 BBLinkNotification 类型（CFString 0x11d1c5150）后 main 队列批量分派
约25个 _respond* 处理器（0x10e644814–0x10e644a98）；`_respondBadgeValueWithType:notification:`
0x10e645fc0 向 delegates 转发 didReceiveBadgeValueWithType:notifcation:（0x10e646048）、
didUpdateAnchorMessagesWithTitle:unreadCount:timestamp:（0x10e64619c，anchor 字段取
subtitle/unreadCount/timestamp）等；消费端 BBLinkBadgeValueManager 0x10e5e5184 先
_existBadgeValueWithType:（0x10e5e51a8）再 updateBadgeValue:type:timestamp:
（0x10e5e51c0），新条目以 NSUUID appendBadgeValueWithObjectID:parentID:type:value:timestamp:
（0x10e5e5218–0x10e5e5250）。这是 IM 内部角标值存储，不等于系统
setApplicationIconBadgeNumber（后者仅 BBCPushCenter 一条，见上文）。
静态边界：Blink 引擎本体（连接、心跳、sync RPC 传输）不在主二进制——
BBIMConnectionProtocol/Observer 仅存协议对象（0x11ea46bb8/0x11ea47020），无实现类符号；
引擎传输与重连参数静态不可判，需真机抓包 IM 长连接 host/port 与 sync/auth 帧取证。

<a id="im-未读同步的字段级链task-18-补"></a>

### IM 未读/同步的字段级链

同步请求（fetchRemoteRelations 实际是 RPC `SyncRelation`）：checkRefreshInfos 0x10e5f3530
在 authority.login 非 0 时 BL 到共享 stub 0x10f84cf4c（site 0x10e5f3584）=
`-[BBIMSynchronizeHandler fetchRemoteRelations]` 0x10e4c92e8；另一调用方是
refetchRemoteRelations 0x10e4c92c0（先把 relationSequenceNumber 置 0，0x10e4c92d0/0x10e4c92e4），
find_callers 0x10f84cf4c 的全部命中就这两处。链：inner_fetchRemoteRelationWithQueue:completion:
0x10e4c93ec 读 relationSequenceNumber（0x10e4c9434）→
inner_fetchRelationsWithSequenceNumber:queue:completion: 0x10e4c9578（日志 CFString
0x11d1bc3f0 `Prepare to synchronize relation with sequence number: %llu.`，category BBLink，
源文件 BBIMSynchronizeHandler+BBIMGroupPrivate.m 第 41 行）→ async block 0x10e4c9650 组
`BAPIImInterfaceV1ReqRelationSync` 并 setClientRelationOplogSeqno:（0x10e4c9684）→
`[BAPIImInterfaceV1ImInterface syncRelationWithRequest:handler:]`（stub 0x10f88b3bc）。
回执 block 0x10e4c9704 形参 (response,error)：error.bapi_status 非 nil 时用 domain/code/message
重造 NSError（0x10e4c9754–0x10e4c9820）否则原样；完成 block 0x10e4c9500 取
`[response serverRelationOplogSeqno]`（0x10e4c9534）写 setRelationSequenceNumber:（0x10e4c9540）。
包装 block 0x10e4c93a8 先对 self+0x20 发 _respondDelegatesDidSyncrhronizeGroupsReponses:
（透传整个 response）再回调 completion。RPC 全名（本轮闭合）：service 由
`-[BAPIImInterfaceV1ImInterface initWithHost:callOptions:]` 0x1162072c0 建
（createMossServiceWithHost: packageName `bilibili.im.interface.v1` serviceName `ImInterface`），
`+defaultService` 0x1162074b8 host=grpc.biliapi.net、isRest=0；instance 0x116207708 把 request、
RspRelationSync class、service、serviceName CFString `SyncRelation` 交
`+[BFCMossServiceWrapper handleRpcRequestWithRequest:responseClass:service:serviceName:handler:]`
⇒ `/bilibili.im.interface.v1.ImInterface/SyncRelation`。请求描述符
`+[BAPIImInterfaceV1ReqRelationSync descriptor]` 0x116209ce0：1 字段 clientRelationOplogSeqno
（fields 0x120852b50）；回执 `+[BAPIImInterfaceV1RspRelationSync descriptor]` 0x116209d4c：
5 字段 full(bool)/relationLogsArray/friendListArray/serverRelationOplogSeqno(uint64)/
groupListArray（fields 0x120852b70），所选transport callback只写serverRelationOplogSeqno，后续GroupManager实际消费full/groupList/relationLogs，不可称全部应用只读seqno。

未读五组（RPC `GetTotalUnread`）：`+[BBLinkNetCenter
fetchTotalUnreadWithUnreadType:dustbin:unfollow:handler:]` 0x10e655084 先被
`[BBIMHelper isSessionRefactorOn]` 门禁（真则不发，0x10e6550bc），再组
`BAPIImGatewayInterfaceV1GetTotalUnreadReq` 的 unreadType/showDustbin/showUnfollowList
（0x10e6550c8–0x10e6550f0）→ `[BAPIImGatewayInterfaceV1ImGatewayApi
getTotalUnreadWithRequest:handler:]`（stub 0x10f850dc4）；instance 0x10e66a23c responseClass=
`BAPIImGatewayInterfaceV1GetTotalUnreadRsp`、serviceName `GetTotalUnread`，service 0x10e669bec
package `bilibili.im.gateway.interface.v1`、service `ImGatewayApi`
⇒ `/bilibili.im.gateway.interface.v1.ImGatewayApi/GetTotalUnread`。完成 block 0x10e655174 调
`[BBLinkGetUnreadModel unreadModelWithMossRsp:]`，且 error 非 0 时把模型置 nil
（0x10e6551b4 csel）。Req 3 字段 unreadType/showUnfollowList/showDustbin（descriptor 0x10e66c9a4，
fields 0x12061eaa0）；Rsp 6 字段 sessionUnread/msgFeedUnread/sysMsgInterfaceLastMsg/
customUnread/totalUnread/totalUnreadNew（descriptor 0x10e66ca10，fields 0x12061eb00）。
映射 `-[BBLinkGetUnreadModel initWithTotalRsp:]` 0x10e62c154：totalUnreadNew.unreadCount→
setTotalUnreadCount:（sxtw，0x10e62c1b0–0x10e62c1bc）、totalUnreadNew.unreadType→
setTotalUnreadStyle:（0x10e62c1dc–0x10e62c1e8；totalUnreadNew 缺失时消息返回 0，无 nil 分支）、
msgFeedUnread→`+[BBLinkUnreadFeedModel msgFeedWithMossRsp:]` 0x10e62b958、
sessionUnread→`+[BBLinkUnreadSingleModel singleWithMossRsp:]` 0x10e62bb4c、
sysMsgInterfaceLastMsg→`+[BBLinkUnreadUpHelperModel sysLastMsgWithMossRsp:]` 0x10e62c058；
customUnread/totalUnread 在本模型无 ivar，不消费。msgFeedUnread 的 MsgFeedUnreadRsp 只有 1 个
bytes 字段 unread（descriptor 0x11620af80），`-initWithFeedRsp:` 0x10e62b71c 交
parseGPBDataToDictionary 后按字符串键 at/like/reply/sys_msg/sys_msg_style/recv_like/recv_reply/
new_follow 取 integerValue（8 个计数器，缺键为 0）。sessionUnread 的 SessionUnread descriptor
0x10e66ca7c 有 13 字段（多 customUnread/systemUnread/strangerUnread/strangerPushMsg/accountUnread），
而 `-initWithSingleRsp:` 0x10e62ba24 只取 10 项（含 strangerUnread/strangerPushMsg；只有
strangerPushMsg 按对象直传，其余 sxtw），customUnread/systemUnread/accountUnread 不消费。
sysMsgInterfaceLastMsg 的 Rsp descriptor 0x11620afec 4 字段 unread/title/time/id_p，
`-initWithSysLastMsgRsp:` 0x10e62bc38 组 {id,time,title,unread} 四键字典→setMsgDictionary:，
title.length 非 0 才 modelWithDictionary: 建 BBLinkUpHelperNewestMessage→setAnchorMsg:
（0x10e62bfc0 段）。未读请求的两个业务生产者（find_callers 0x10f84d078 全部命中）：
`-[BBIMSessionManager queryCombineSessionUnread:dustbin:unfollow:completion:]` 0x10e4c3cbc 与
`-[BBLinkBadgeValueNodeManager queryTotalMsgUnread:completion:]` 0x10e63f984（要求
BBLinkAuthority.login 非 0；unreadType 取 BBIMHelper.enablebadgeNodeAppendFilter ?
foldUnfollowedSessionConfig : sessionPreference.foldUnfollowedSession，dustbin=0，
unfollow=!enablebadgeNodeAppendFilter，0x10e63fa94/0x10e63faa4）。角标语义在该链 block
0x10e63fb00：totalUnreadStyle==0 不设置、==1 用 totalUnreadCount、==2 用常量槽 0x118e40740
（chained-fixup 未解码），setCount: 到 rootMessageNode ⇒ 只有 totalUnreadNew 组驱动 root
badge node。

已读回执：`-[BBIMSynchronizeHandler updateAckWithItem:completion:]` 0x10e4ccb98（日志 CFString
0x11d1bc4b0 `prepare to update message record`，BBIMSynchronizeHandler.m 第 67 行）以
objc_msgSend$async: 把 block 0x10e4ccc80 派发到 self；block 先 [item type]（getter stub
0x10f88ed54=`type`）==3 且 isKindOfClass:BBLinkServiceSession 时走 BBIMServiceNetCenter
customerUpdateAckWithAckSeqo:shopId:shopFatherId:completion:（取 kf_ackSeqno 与
kf_talkerInfo.shopId/shopFatherId），否则 BAPIImInterfaceV1ReqUpdateAck requestWithSession:item
后 updateAckWithRequest:handler:。`+requestWithSession:` 0x10e43e42c：sessionType=
[item type]==1?1:2、talkerId=[item contactID].unsignedLongLongValue、ackSeqno=maxSeqno 非 nil
时直传，否则 locSeqno.unsignedLongLongValue。ReqUpdateAck descriptor 0x11620a114 3 字段
talkerId/sessionType/ackSeqno（fields 0x120853130）；instance 0x116207d20 serviceName `UpdateAck`、
responseClass=`BAPIImInterfaceV1DummyRsp` ⇒ 回执无业务字段、客户端不消费。ReqSyncAck/RspSyncAck
（0x116209db8/0x116209e24）属另一条 syncAckWithRequest:handler: 0x116207898，业务调用方本轮未定位。

推送到达后的字段映射：`_respondBadgeValueWithType:notification:` 0x10e645fc0 不读 notification
字段，只 copy 后经 hasDelegateThatRespondsToSelector:
notificationManager:didReceiveBadgeValueWithType:notifcation: 门禁转发 (self,type,notification)；
真正做映射的是 `_respondUpHelperNewestMsgToNotificationCenter:` 0x10e6460fc：
notification.subtitle→title（0x10e646168）、notification.unreadCount→unreadCount（0x10e64617c）、
notification.timestamp→timestamp（0x10e646188），经
didUpdateAnchorMessagesWithTitle:unreadCount:timestamp:（selref 0x11f6ba998）转发给
BBLinkBadgeValueManager 0x10e5e5184。静态边界与上节一致：Blink 引擎本体（连接/心跳/sync 传输）
不在主二进制；isSessionRefactorOn 的实际设备决策返回和 style2 UI 表现属运行期；来源key/default与整数哨兵-10086已静态解出。证据
DerivedData/Validation/team-c13/findings.md。

### 本地通知与 category

Center.init（0x1149e79dc）只注册rich_1.0类别；Service转换
UNNotificationCategory（0x115e02e18）时actions/intentIdentifiers均为空数组，
options=0、placeholder=nil。这条注册链没有把rich_media.buttons转换为系统按钮；
通知扩展一路已按样本闭合为不存在：主程序镜像符号表无任何
NotificationService/NotificationContentExtension类（query_index三种通配均空），
且样本app包bili-universal_8.89.0.app.zip内PlugIns/extension条目数为0，即本
8.89.0包不含任何通知扩展bundle，不能据parser字段推导已经注册这些UNNotificationAction。

Service.scheduleRequest（0x115e03400）仅_initialized byte恰为1且request.type=0
继续。复制title/body/badge；sound非nil用soundNamed，否则defaultSound。可变复制
userInfo后用传入identifier覆盖task_id，并用同identifier建UNNotificationRequest。
fireDate非nil取NSDateInterval(now,fireDate).duration，建不重复timeInterval trigger；
本体没有正数/clamp校验，nil则trigger=nil。addNotificationRequest的completion
（0x115e03754）仅return，没有处理平台错误或业务重试，也未设categoryIdentifier。
旧didRegisterUserNotificationSettings（0x115e03848）忽略传入settings，先写
didAskForPermission=true再重读实际settings交Center；该标记不是授权成功证明。

已确认四个静态业务schedule调用点，动态selector调用仍可能遗漏：

| 来源 | 操作条件与通知内容 | 标识及后续边界 |
| --- | --- | --- |
| 下载notifyUi（0x115933ee4） | state1239且lastestState非1239/0、inReview=false生成发送flag；main block再要求appstate原始2且flag1。标题/正文取下载模型非空值或本地化；url=bilibili://user_center/download | identifier=kBFCDownloadMessage:+entityType+":"+task.bfc_uniqueString；无论schedule与否仍post BFCDownloadTaskNotifyUiNotification |
| 投稿失败（0x10cdb0c5c） | title/body来自参数及格式化，url=/uper/user_center/archive_list；本体无appstate/权限门槛 | 固定BBUPER_ARCHIVE_ADD_FAIL，无fireDate，最终仍受Service初始化门槛 |
| Phone前台召回（0x10f26a96c） | 读push_recall_time(float days)/push_recall(body，空时本地化)；先取消，再以正数days*86400或默认5184000秒建通知 | 同identifier=longTimeNoUse；title空/userInfo初始空，Service仅附task_id，无url |
| HD转Phone前台召回（0x10c8892d0） | 与Phone同配置/取消/重建规则，两个入口本体未请求线上config | 同longTimeNoUse；本地type0无HTTP click/growth，trigger仍可记录 |

下载时间比较不能直接描述成可靠1秒节流：0x115933f64–0x115933f70计算
t=tv_sec*1000+tv_usec，未见微秒除1000；已有task时间还先被重写0。
随后unsigned(t-old)>1000或state变化才继续并保存t。保留这段单位/保存异常，
不据比较常量推出实际限流效果。上述通知仅静态研究，未调度或触发真实通知。
