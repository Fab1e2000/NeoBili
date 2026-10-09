# 五、Laser / UPOS 上传

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 五、Laser / UPOS 上传

### UP-01 UPOS Pre 阶段 `member.bilibili.com/preupload`

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `Pre.apiRequest`（0x114aac48c）优先取非空 `request.preUploadUrl`，否则装内置 CFString 0x11d2c42d0 = `https://member.bilibili.com/preupload`（0x114aac698/0x114aac6a8），并按 `setRequestMethod:#0` 置 GET。Laser 自身的四个上报/上传端点来自 Kotlin 常量 wrapper：`+[BFCLaserConstWrapper laserURL]`（0x104e31070）= `app.bilibili.com/x/resource/laser`、`laser2URL`（0x104e31174）= `…/laser2`、`reportCommandURL`（0x104e31278）= `…/laser/cmd/report`、`uploadURL`（0x104e3137c）= `api.bilibili.com/x/feedback/uploadFile`（源文件 `srcs/base/BFC/Fawkes/BFCLaser/LaserConstWrapper.swift`）；Swift 侧调用点 `+[BFCLaserConst laser2Url]` 0x114a8dc20。`silenceURL`（0x104e30f70）= `https://app.bilibili.com/x/resource/laser/silence`（本轮补齐该字面量；同族 `laserURL`= `…/laser`、`laser2URL`= `…/laser2`、`reportCommandURL`= `…/laser/cmd/report`）。 |
| 2) 触发时机 | `TaskOperation.uploadAfterPackup`（0x114a91348）取 date/dateList 对应附件（空列表报 error1），非空先 `createZip`，失败退 `createTar`，计算归档 size/MD5 后进入上传；`uploadServiceForOperation:`（0x114a8c790）缺 getter 时默认 raw2。实验 getter 0x100074a94 查询 `laser.upload_to_upos` preset1，true→2 / false→0，因此**默认 UPOS**，而非备用 Uploader 固定 URL。 |
| 3) 请求头 | Pre 阶段无独立 auth 头记录；后续 Initial/Merge 阶段有 `X-Upos-Auth`（见 UP-02）。 |
| 4) 参数及来源 | mutable-copy `options.queryDictRepresentation`，加入 `r=upos`、`name=filePath.lastPathComponent`、`profile`。日志附件来源：LogModule multibinding 0x12028f0c0 注册 `BFCLaserAttachmentProvider`，两个 witness 指向 `BLogAttachment`（0x1049514a0）与 `BFCLogAttachment`（0x1049514d8）；`BLogAttachment.localPaths`（0x104953c98→0x104955284）先 flush BLogger，再枚举 `Documents/BLog` 按 `yyyy-MM-dd` 筛日期；operation 附件收集 0x114a8bd04 调注册 provider 的 `localPaths`/`data` 并保留 name 关联。 |
| 5) 签名与编码规则 | 未在主文档记录自有签名；GET query 由 options 生成。 |
| 6) 响应结构 | `success`（0x114aac970）解析 configuration，**仅 endpoints 非空**才记 `ctimeOfPreupload`/`taskConfiguration`、推进 phase 并通知更新（0x114aaca38/0x114aaca7c/0x114aacb94）。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无 Laser/UPOS/日志上传（本轮 grep `upos`/`preupload`/`laser`/`BLog` 在 `NeoBili/` 下只有 [PlaybackSource.swift](../../../NeoBili/Features/Player/PlaybackSource.swift) 的 CDN host 判断与 [BiliAPI+Danmaku.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Danmaku.swift) 的路径同名片段，均与上传无关）。不新增实现。 |
| 8) 证据等级与版本 | 8.89 静态（0x114aac48c、0x114aac698/0x114aac6a8、0x114a91348、0x114a8c790、0x100074a94、0x12028f0c0、0x104953c98→0x104955284、0x114a8bd04）；G1 findings 7；当前源码（grep 结论）。 |
| 9) 残余不确定项 | Pre与queryDict完整字段/门禁已展开：必写trace_id/device/os_version/build/version；size仅非0写，mid/appkey/access_key/net_state及path按getter非nil；Pre从networkForTask取networkType、GET、copy后加r=upos/name/profile。附件实际flush/打包、后续取消调度及远端持久性不能由builder证明；BLog job结构另见CRASH-01，不混作本阶段参数（root-static-remaining/findings.md）。 |

### UP-02 UPOS Initial / Merge / SinglePart 阶段

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 三阶段共用 URL format `https:%@/%@%@`，由 `activeEndpoint` 与 `NSURL(uposUri).host`/`path`（Initial，0x114aa97b8）或 `storageInfo.bucket`/`key`（Merge，0x114aa9f34）填入，不自行补 slash 或固定动态域名。SinglePart（0x114aadd4c）同 URL 规则。**本条的 host 属服务端配置/运行期值**，不同于 Laser 的固定 wrapper 常量（`uploadURL` 0x104e3137c = `api.bilibili.com/x/feedback/uploadFile` 是 raw0 备用 Uploader 的端点，见 UP-01/UP-03）。 |
| 2) 触发时机 | `BaseRequestManager.sendRequest`（0x114aa89ac）调用实际 `apiRequest` 构造 `BFCApiRequest`，设 callback queue/timeout/handlers 后 `requestAsync`（0x114aa8c38）。普通 `start`（0x114a9a9dc）按 phase/`enableSimple`/size 阈值选 simple，否则走 Pre/Initial/Part/Merge managers；`enableRealTimeTranscoding` 另分支。UPOS task：`taskWithRequest`（0x114a996a8）→`TaskManager`（0x114a9c510）创建 UploadTask 并设 performer=self，resume 0x114aa56d0→0x114a9cd84 创建 `BFCOperation` 包装 `OperationManager` 并入队。 |
| 3) 请求头 | Initial：method raw2，`X-Upos-Auth` 来自 `configuration.auth`（BFCApiRequest init 0x114aa9ba4）。Merge：method raw2，auth 非 nil 才加同名头。SinglePart：同 URL 规则与 auth 头，`ignoreCache=1`、`signType=1`；`requestInjection`（0x114aae5ac）mutable-copy 最终 request 并明确设置 PUT（0x114aae5cc）。 |
| 4) 参数及来源 | Initial：`uploads=""`、`output=json`，`customInitialParas` 后合并可覆盖。Merge：`output=json`、`uploadId`、`biz_id`，`needTranscode` 才添 `profile`，`customMergeParas` 后合并可覆盖（0x114aaa308）。SinglePart：`partNumber` 十进制与 `uploadId`；非 background 路径 seek `partInfo.offset`、读 `partInfo.size` 字节，`taskType=4`/`localData`；background 为 `taskType=3`/`localPath`。配置解析 parser 0x114aa82a8 解析 `chunk_size`/`threads`/`timeout`/`chunk_retry`/`chunk_retry_delay`/`endpoint`/`endpoints`/`upos_uri`/`put_query`：zero `chunk_size`→8388608、threads unsigned≤1→1、zero timeout→900、zero chunk_retry→200、zero retry_delay→3（0x114aa83cc/0x114aa8404/0x114aa8444/0x114aa8500/0x114aa853c）。 |
| 5) 签名与编码规则 | SinglePart 的 `signType=1`；其余阶段未在主文档记录签名步骤。 |
| 6) 响应结构 | SinglePart 的 `preProcessRawData`（0x114aae5e0）**仅 HTTP status 200 合成 JSON code0**（0x114aae630/0x114aae6a0），其他 nil——这是传输状态适配，不是服务端返回 JSON code0 或所有分片已持久化的证明。重试：`error callback`（0x114aa8d48）递增 `currentTimesOfRetry`，交替 continuousFailure 时按 optionalEndpoints count 轮换 endpoint；`current<timesOfRetry` 才 main `dispatch_after` interval 后重启。Base 默认 timeout=120、timesOfRetry=10、interval=3（0x114aa9030/0x114aa9038/0x114aa9040），子类可覆盖；Initial/Merge/Pre 的 method lists 均无 Base 覆盖，SinglePart 明确覆盖为读 `taskConfiguration.timeout`/`timesOfChunkRetry`/`delayIntervalOfChunkRetry`（0x114aaef40/0x114aaefb4/0x114aaf028）。Simple timeout（0x114aadc18）另按 `options.size` 作移位/高位乘法后 +5。取消：`Task.cancel`（0x114aa5740）→`TaskManager.cancelTask`（0x114a9d1c8），running operation 存在才 `cancelOperation`、删 UPOS task cache、state 0，再 `notifyTaskDidCanceled`；无 operation 也通知但跳过删 cache。`OperationManager.stop`（0x114a9b4c8）取消 uploadQueue，`Base.stop`（0x114aa88a0）设 `isStop=1` 并 main common modes 排 `BFCApiRequest.cancel`、`waitUntilDone=false`。取消通知 0x114a9be9c→block 0x114a9bfbc 只向 delegate 发 `uposUploadTaskDidCanceled`（0x114a9bfe4），**不调用 task.completionHandler**。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无 UPOS 上传（同 UP-01）。 |
| 8) 证据等级与版本 | 8.89 静态（上列全部地址）；当前源码。 |
| 9) 残余不确定项 | Pre/SinglePart/Merge options完整已读：Pre GET+query r=upos/name/profile；Part X-Upos-Auth、partNumber/uploadId、file/data分别taskType3/4，injector114aae5ac显式PUT；Merge output=json/uploadId/biz_id、needTranscode才profile、method raw2。queryDict必写trace/device/os/build/version；size仅非0写，mid/appkey/access/net/path各按getter非nil。真实持久性/取消调度与服务端结果不由这些builder证明（root-static-remaining/findings.md）。 |

### UP-03 Laser 反馈回执

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `LaserApi`（0x114a89448），报告入口 `feedback`（0x114a92708），`requestSync` 0x114a89820；主机取 `+[BFCLaserConst laser2Url]` 0x114a8dc20 → `+[BFCLaserConstWrapper laser2URL]`（0x104e31174）= `app.bilibili.com/x/resource/laser2`（本轮逐调用点闭合；同族 `laserURL` 0x104e31070 = `…/laser`、`silenceURL` 0x104e30f70 = `…/laser/silence`、`reportCommandURL` 0x104e31278 = `…/laser/cmd/report`、`uploadURL` 0x104e3137c = `api.bilibili.com/x/feedback/uploadFile`；源文件 `srcs/base/BFC/Fawkes/BFCLaser/LaserConstWrapper.swift`）。方法全名 `+[BFCLaserApi reportFeedback:uposUri:md5:status:taskId:taskType:fawkesKey:errorDescription:error:]`；三条 `reportFawkes*` 各自用 reportCmdUrl（0x114a888d8→0x114a88990）、laserUrl（0x114a88cb8→0x114a88d70）、silenceUrl（0x114a89080→0x114a89138）。 |
| 2) 触发时机 | `TaskOperation.main` 完成上传后按 URL 是否 nil 写 status 3/-2 等 `reportContext`，`report` 的 retryTimes=3、retryInterval=3（0x114a91020）。`uploadServiceForOperation:` 的 raw0 分支走 `BFCLaserUploader`（0x114a967d8→0x114a96834，options 含 localPath、requestMethod=2、taskType=1、ignoreCache=1、timeout=60、cacheLife=0，`/data` 模型，`/data.url` 非空才接受）；raw2 先复用 task identifier 匹配的 UPOS task，未找到才新建 `BFCUploadRequest`，设置 profile / `options.mid` / 归档 file location，再装 completion 0x114a92290 并 resume；回调 error nil 才从 `storageInfo.bucket`/`key` 构造 download URL/UPOS URI，任一结果均 signal semaphore（0x114a923e8）；等待后删除归档 0x114a92124（不等同删除原日志文件）。 |
| 3) 请求头 | 未在主文档逐项列出。 |
| 4) 参数及来源 | 8 键 + 条件 `task_type`：`app_key`←第 7 形参 fawkesKey（=`BFCLaserConstWrapper.fawkesKey`）、`buvid`←`+[BFCBuvid buvid]`、`status`←`@(status).stringValue`、`url`/`raw_upos_uri`/`md5`/`error_msg`/`task_id` 分别取第 1/2/3/8/5 形参（nil→空串），`task_type` 非 nil 才 `setObject:forKeyedSubscript:`（0x114a896f0）——`dictionaryWithObjects:forKeys:count:8` 0x114a89690，故 8 键是下限、9 键是常见形态；`setRequestMethod:#1`（0x114a89580）。 |
| 5) 签名与编码规则 | 未在主文档记录。 |
| 6) 响应结构 | 报告 error 时循环，最多 3 次总 attempt、间隔 3 秒，区别于 UPOS stage retry。如果上传 error 为 nil 但 report error 非 nil，合成 error 6（0x114a91094）；最终 delegate completion 0x114a911ec 携 URL/error。`BFCLaser`（0x114a8d160）删缓存 task、main 派发 UUID completion 并移除 callback——**本地清理不是远端 ACK**。上传成功与报告成功是两层判定，不能用 `Crash.reportIssueComplete(true)` 代替。`awaitLogUpload` 类入口（`uploadAllLogsWithTag:` 0x114a8a464）提交时即更新 `lastUploadTime`，未等网络回执；直接入口 `uploadLogsWithTask:completionBlock:`（0x114a8a78c）不套该时间节流。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无 Laser 反馈上报（同 UP-01）。 |
| 8) 证据等级与版本 | 8.89 静态（0x114a89448 与 baseUrl 装载 0x114a89548、`+[BFCLaserConst laser2Url]` 0x114a8dc20、`+[BFCLaserConstWrapper laser2URL]` 0x104e31174、0x114a92708、0x114a89820、0x114a91020、0x114a91094、0x114a911ec、0x114a8d160、0x114a8a464、0x114a8a78c；四条 Api 的 wrapper 交叉核对证据 `DerivedData/Validation/team-c13/findings.md` A1/A2）；当前源码。 |
| 9) 残余不确定项 | 端点已闭合（`reportFeedback:`→`…/laser2`，四条 Api 各自的 wrapper 已逐调用点核对，见第 1 项）；剩下的：(a) `api.bilibili.com/x/feedback/uploadFile`（0x104e3137c，raw0 `BFCLaserUploader` 备用链）与 `member.bilibili.com/preupload`（UP-01）在 raw0/raw2 分支的对应关系仍只到默认值层（raw2=UPOS 默认，raw0 需实验键 `laser.upload_to_upos` 取假）；(b) 原 0x114a9bc38 不是回调入口，team-c32 已补齐静态回执调用链（见主文档对应章节），撤回该过时命令；服务端持久性仍需回执与后续查询独立核验；(c) UPOS 取消后 Laser completion（0x114a92290）是否被调用属运行期交错，静态不可判（需真机取证：上传中取消并观察 completion/delegate 回调）。 |
