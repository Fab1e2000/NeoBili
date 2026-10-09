# 四、推送

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 四、推送

### PUSH-01 APNs token 与状态上报 `x/push/report`（Center，12 字段）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `BBCPushApi.pushReport`（0x1149e6df4）向 `x/push/report` 发 `method=1`、`ignoreCache=true`；host 由 `BBCPushApi.init`（0x1149e6d98）默认存 `api.bilibili.com`（self+8），report 以该属性组装 `https://%@/x/push/report`。`Center.setApiHost`（0x1149e7dcc）只是 tail call `_objc_msgSend$setHost:`，本镜像符号表不存在 `_objc_msgSend$setApiHost:` 调用桩（`query_index` 仅命中方法表 selector 字符串 0x11a2d1b4b），即无任何调用点为该 selector 编译出 msgSend。 |
| 2) 触发时机 | `sendPushReport`（0x1149e80f0）没有以 token 非空/open=true 拒绝请求。事件类型：1=APNs token 到达、2=账号登录/切换、3=退出、4=APNs 注册失败、5=notifyChangeToken、7=前台重新读取 settings。APNs `didRegister` 回调（0x115e0395c）逐字节用 `%02lx` 转小写两位 hex（无固定 NSData 长度校验），交 `BBCPushCenter`；Center（0x1149e94fc）先更新 RAM token 与 `BBCPushNotificationPreferences.deviceToken`，再发 type=1 并通知 delegate，**不等待上报成功**；init 会从 Preferences 恢复旧 token。接收错误的 Center（0x1149e9688）实际再发 type=4（0x1149e9794），随后也调用 didRegister delegate——此 body 未清 RAM/Preferences token 或 settings flags，所以 type4 可能带旧 token，delegate 名称不能作为注册成功证据。type5 的两个明确消费者为 `PushModuleRestrictedModeObserver`（0x1001a8f7c）与 `GPPushHelper`（0x10f6d3688）的 `enableChangedOfMode:`，均查询传入 mode 的 `BFCRestrictedModeManager.enableOfMode`，true 才发 type5；mode 枚举：0→青少年模式 controller、1→课堂模式 controller、其他值原样透传。 |
| 3) 请求头 | 未在主文档逐项列出；由公共网络层添加。 |
| 4) 参数及来源 | 12 字段：`app_id` 十进制（`PushHelper.setup` 0x1001a9c34 默认设 Center.appId=1；注入 service.productID 精确等于字符串 `14` 时改为 7）、`buvid`（Const 0x104e2dab0→`BFCBuvid.buvid`，跟踪 36 字符）、`device_token`（nil 空）、`push_sdk=\`1\``、`time_zone`（Date 当前时区秒数÷3600 向零截断）、`notify_switch` 布尔十进制、`type` 十进制、`mobile_brand=\`Apple\``、`mobile_model=UIDevice.bfc_platformString`、`mobile_version=systemVersion`、`extra` 的 `yy_modelToJSONString`、`push_to_start_token`（standardUserDefaults/ActivityPushToStartToken，nil 空）。type5 的 extra 记录六个数字枚举：authorization_status/sound_setting/badge_setting/alert_setting/notification_center_setting/lock_screen_setting。 |
| 5) 签名与编码规则 | 未在主文档记录自有签名；`extra` 用 `yy_modelToJSONString`（键顺序不保证）。 |
| 6) 响应结构 | 该 body 的 `requestAsync` **没有业务 completion/响应校验**，也没有失败回滚 token 或递归重试；公共网络层行为独立。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 源码没有推送注册与 token 上报（本轮 grep `x/push`、`deviceToken`、`registerForRemoteNotifications`、`UNUserNotification` 在 `NeoBili/` 下零命中）。不新增实现；差异不产生实施建议。 |
| 8) 证据等级与版本 | 8.89 静态（0x1149e6df4、0x1149e6d98、0x1149e7dcc、0x1149e80f0、0x115e0395c、0x1149e94fc、0x1001a9c34、0x1001a8f7c、0x10f6d3688）；G1 findings 3/4；当前源码（grep 结论）。 |
| 9) 残余不确定项 | 启动注册与 moduleInitialize 的全局先后由框架 runnable 调度在运行期决定，静态不可排定（静态侧 trigger/priority 已闭合：0x1001a7770 applicationLaunch/450、0x1001a7960 moduleInitialize；残余仅能以真机启动日志验证先后）；token 新鲜度属运行期状态，静态不可定，不能将 type5 等同于 APNs 新 token 或某个固定限制模式。 |

### PUSH-02 ActivityKit 推送 token 上报（7 字段）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 固定 `https://api.bilibili.com/x/push/report`，`method=1`、`ignoreCache=true`（报告入口 0x102bc61a4）。启动模块 0x102bc2fac，`start` 0x102bc2890，`startTokenMonitor` 0x102bc6e8c，链 0x102bc72cc→0x102bc93ac→0x102bc94b8→`reportWithRetry` 0x102bc5bf8。 |
| 2) 触发时机 | `ActivityTokenMonitor`（0x102bc72cc）创建 `TokenState` actor 时把 token/startToken 两个 Optional 清零，不从 NSUserDefaults 恢复。`pushToStartTokenUpdates`（0x102bca134）逐字节 `%02x` 后空分隔连接，先与 `actor.startToken` 比较，相等跳过，不同则更新 RAM、写 `standardUserDefaults/ActivityPushToStartToken`（0x102bca9f4），再启动报告；它读取 persisted old token 给状态/telemetry helper，去重判断仍用 actor。`Activity.activityUpdates`→每个 `Activity.pushTokenUpdates`（0x102bc7e88）独立产生 `push_token`，同样小写 hex；ActivityState ended/dismissed 跳过此次处理，其他状态与 `actor.token` 比较，变化才更新 RAM 和报告；该分支未见持久化，也不是 APNs token。启动要求 `dd.liveactivity_enable`（默认 true）与 runtime availability 17.2.0 均通过；`tokenmonitor_delay` 默认 false、`monitor_delaytime` 默认 10 秒。 |
| 3) 请求头 | 未在主文档逐项列出；由公共网络层添加。 |
| 4) 参数及来源 | 仅 7 字段：`app_id=\`1\``、跟踪 buvid、`type=\`1\``、`push_to_start_token=actor.startToken`、`push_token=actor.token`、`push_sdk=\`1\``、当前时区小时向零截断；两个 Optional 字符串 nil 退空。 |
| 5) 签名与编码规则 | 未在主文档记录自有签名。 |
| 6) 响应结构 | `retry` 仅在两个 Optional 都 nil 时本地拒绝，**空但非 nil 的字符串通过此检查**；调用方 limit=3，失败最多 3 次尝试、间隔 1 秒，最后抛错；sleep 取消直接走错误，不增加第 4 次。completion 0x102bc58ac 直接 `resume(returning:)`，error 0x102bc5a4c `resume(throwing:)`，**此 body 没有独立业务 status 检查**。报告失败不回滚缓存，相同 token 的后续 update 仍可能被 actor 去重。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无 ActivityKit 与 `x/push/report`（同 PUSH-01 的 grep 结论）。 |
| 8) 证据等级与版本 | 8.89 静态（上列地址）；当前源码。 |
| 9) 残余不确定项 | 框架是否交付 token 不能由 caller body 代替证明（属运行期）；`startTokenMonitor` 读取 `areActivitiesEnabled` 只做日志与 cold_start telemetry，此读取不是权限 gate，实际权限属运行期（需真机取证：在启用 Live Activity 的设备上抓 `x/push/report` 的 7 字段）。 |

### PUSH-03 通知点击回执 `/x/push/callback/click`

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 点击 API（0x1149e7314）向**可覆盖 current host** 的 `/x/push/callback/click` 发 `method=1`。 |
| 2) 触发时机 | `BFCPushService.didReceiveNotificationResponse`（0x115e03d70）按 `request.trigger` 是否为 `UNPushNotificationTrigger` 取 type=1/0，转 delegate 后立即调用系统 completion。Center（0x1149e99a8）先 `forwardContent`，再仅 type=1 调 `callbackClick`，最后通知 `didReceiveContent`；dismiss 也经过此 forward，不直接等同于“没有导航/回执”。自定义 action 按 `rich_1.0`/`rich_media.buttons` 的 identifier 匹配，button type 为 remove 才 click=4，其余 click=0；dismiss 本身也取 0。 |
| 3) 请求头 | 未在主文档逐项列出；由公共网络层添加。 |
| 4) 参数及来源 | `app=appId` 十进制、`task=userInfo.task_id` 的 `%@` 格式（task nil 没有门槛，会经格式化形成 `(null)`）、`push_sdk=\`1\``、`mid=Const 注入 service.mid` 十进制、`token=当前 APNs token`（nil 空）、`action`、`type` 十进制与 `extra`。extra 仅自定义 action 传 `{button: actionIdentifier}` 并 `yy_modelToJSONString`，其他 action 传 nil（字典下标省略该键），**不能把七条赋值语句描述为七个键必带**。 |
| 5) 签名与编码规则 | 未在主文档记录自有签名。 |
| 6) 响应结构 | 此 API **没有业务回执或重试 block**，不能由客户端发送证明服务端接受。`forwardContent`（0x1149e8978）在 `handleAllow` 恰为 1 时 main.async execute，否则同步追加 RAM 数组；`setHandleAllow` 非零即 flush，不比较此前值；flush（0x1149e8d90）把各条 main.async 给 contentHandler 后清数组，**没有再次发送 click 回执**。因此系统 completion/点击回执不等待延后导航完成。`homePageInitialized` 放行 runnable 读 `push.delay_handle_allow`：signed<1 立即，>=1 按 Double 秒 `main.asyncAfter`。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无推送点击回执（同 PUSH-01）。 |
| 8) 证据等级与版本 | 8.89 静态（0x1149e7314、0x115e03d70、0x1149e99a8、0x1149e8978、0x1149e8d90）；当前源码。 |
| 9) 残余不确定项 | 初次 payload URL 选择由服务端下发 payload 在运行期决定、框架全局事件顺序静态不可排定（冷启动加速门禁已闭合至 0x1001b4144，下一步以真机启动日志验证顺序）；静默收包无 HTTP 点击回执，但仍有 `public.apns.trigger.other` 收包埋点与 `public.apns.ground.other` 路由结果埋点，不能把无点击 API 概括为无上报。**payload 键级解析点已补（team-33）**：`callbackClickWithContent:` 0x1149e8410 读 `userInfo` 的 `id`/`type`/`task_id`/`rich_media`（`bfc_arrayForKey:`，元素取 `buttons`、type=='remove'）与 `categoryIdentifier`/`actionIdentifier`；静默收包解析点 `pushService:didReceiveSilentRemoteNotificationWithUserInfo:` 0x1149e97d4。 |

### PUSH-04 badge 回执 `/x/push/callback/badge`

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | badge API（0x1149e75c4）向 current host 的 `/x/push/callback/badge` 发 `method=1`。 |
| 2) 触发时机 | `Center.applicationDidBecomeActive`（0x1149e9274）只处理 signed badge>=1：先调 `setApplicationIconBadgeNumber(-1)`，再报告旧正数（**不要把 setter 参数归一化为 0**）。另有 Helper 的 `WillEnterForeground`（0x1001b1b64）把当前 badge 十进制记为 `main.active.redpoint.0.click` 的 num，没有正数门槛、不清 badge，与 Center 的 DidBecomeActive 清 badge 并发 callback/badge 是两条链。 |
| 3) 请求头 | 未在主文档逐项列出；由公共网络层添加。 |
| 4) 参数及来源 | 七字段：`app`/`mid`/`buvid`/`device_token`（nil 空）/`action=\`clear\``/`type=\`number\``/`number=` 旧值十进制；**该 body 没有 `push_sdk`**。 |
| 5) 签名与编码规则 | 未在主文档记录自有签名。 |
| 6) 响应结构 | 异步无业务 completion/重试，失败不还原本地 badge。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无 badge 回执（同 PUSH-01）。 |
| 8) 证据等级与版本 | 8.89 静态（0x1149e75c4、0x1149e9274、0x1001b1b64）；当前源码。 |
| 9) 残余不确定项 | 实际 badge 数值由系统与推送 payload 在运行期决定（需真机取证：触发带 badge 的推送后抓 `/x/push/callback/badge` 的 `number` 与实际本地 badge）；静态不可判。 |
