# 旧 V2 文本日志通道

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 旧 V2 文本日志通道

这是包内明确存在的一套实现；还没有证明它在本样本启动时的实际注册，更没有证明它就是
9.13 抓包中的 Protobuf 业务埋点通道。BFCTracker 支持多个 trackPlatforms 和
separatePlatforms，存在并行上报机制的入口。

BFCReportHandlerV2.trackCustomEvent（0x1141c7f70）要求参数键能以 integerValue 转换并
往返成同样的字符串，随后按数值比较器排序，将对应值转为有序数组。isRealTime 选择
ReportRealV2 或 ReportDelayV2。ReportItemV2 初始化记录日期字符串和 Unix 毫秒。
encodedParas（0x1141c83c8）拒绝空 taskId/空 params，值 description 中的 `|` 替换为空格，
再 URL 编码；最终各列用 `|` 连接。公共部分分 staticPublicPars（进程 once）与
publicPars（每次计算），分别含设备/首次跟踪/渠道信息及账号、版本、网络状态等；
完整列顺序与 BUVID 拼接部分仍需逐列复现。

ReportBaseV2 的请求/保存队列并发数均为 1；对象自己还有串行 dispatch queue。
入队先计算并保存编码字符串，再异步分配到 sendingReports 或 cachedReports。
trySendReport 先 saveReport，再判断 isSending、网络可达及非空发送数组。
默认一批上限 30 条，单条分流门槛 1024 个 NSString 字符，保存有效期 604800 秒，
默认延迟值 600 秒。DelayV2 大于等于门槛的项改入 LargeV2；Large/Real 批量上限为 1，
Real 延迟值为 0。Delay 的 reportDelayTime 有 requestInjector 时也返回 0，因此默认
600 不能直接当作运行时发送间隔。Delay/Large 的发送判断包含 Wi-Fi 条件。

sendReport（0x1141c6a04）去掉每项前 14 字符的保存日期前缀，以控制字符格式串组合为
文本（每条后加字节 0x03）、UTF-8 编码并 gzip。POST 到 data.bilibili.com/log/mobile?ios，设置 Content-Encoding
为 gzip、Content-Length 为压缩后 NSData 字节数；bili_debug_mode 为真选 HTTP，否则 HTTPS。随后可经 requestInjector 修改请求，
用 sendAsynchronousRequest 在串行 requestQueue 完成。**已闭合（task-38）**：自带头只有 Content-Encoding/Content-Length，其余全部来自 BFCTracker requestInjector `trackerCanonicalRequestForRequest:`（0x1141c6cd4）的 mutableCopy ⇒ 复用封包需复刻 injector 输出。

完成回调（0x1141c6e2c）按 HTTP 状态处理，没有解析响应业务正文；状态 200 进入成功，
无响应或其他状态进入失败。成功异步清空 sendingReports，再从 cachedReports 补下一批、
安排下一次检查；失败把发送项追加回 cachedReports 后重新取一批，没有在此失败块中直接
安排重发定时器。再次触发的来源已闭合，且有两条独立路径：
（1）新事件入队路径 `-[BFCReportBaseV2 addReportWithItem:]` 的 block_1（0x1141c66f0）在
0x1141c6850 取发送数组 count、0x1141c6860 `cmp x21,#0x14`（20）、0x1141c6864 `b.lo`：
count>=20 时 0x1141c686c 立即 `trySendReport`（0x1176f58a0）；count<20 时
0x1141c6878/0x1141c687c 用 objc_opt_new 新建 `BFCReportSchedulerV2`、0x1141c6888
`addObject:` 存入 self+0x10 数组、0x1141c6890–0x1141c68a0 组 `dispatch_time(0, 0xb2d05e00)`
=3 秒，0x1141c68f0 `dispatch_after`（0x11711d744）投递栈 block。
（2）成功回执路径 `-[BFCReportBaseV2 reportSuccessWithCode:]` 的 block_1（0x1141c6fac）
在 0x1141c7158–0x1141c7180 做同一套「新建 SchedulerV2 + addObject + 3 秒 dispatch_time」安排。
延迟块本体是 `addReportWithItem:]_block_block`（0x1141c6940）：0x1141c6950 取捕获的
scheduler 发 `canceled`（0x117238ee0），0x1141c6958 canceled 非 0 就跳过，否则
0x1141c695c/0x1141c6960 对 self 调 `trySendReport`，最后 0x1141c6964–0x1141c6974 用
`removeObject:` 把该 scheduler 从数组移除。`-[BFCReportSchedulerV2 setCanceled:]`
（0x1141c6338）**会被镜像主动置位**：共享 stub `_objc_msgSend$setCanceled:`（0x11754e3c0，
其 selref 槽 0x11f6fe798 只被该 stub 引用）的两个调用点就在这两个 block 里——
0x1141c6808（`addReportWithItem:]_block_1`）与 0x1141c7124（`reportSuccessWithCode:]_block_1`），
均以 `mov w2,#1` + `bl _objc_msgSend$setCanceled:` 遍历 scheduler 数组置 1；
因此上文"3 秒 dispatch_after 块首的 canceled 门禁"是**有效门禁**：先被置 1 的 scheduler
在延迟块触发时会走 0x1141c6958 `tbnz` 跳过 `trySendReport`。
（订正说明：早前"selref 槽无 ADRP+LDR 引用即无调用点"的判据是错的——共享 stub 场景下
selref 只被 `__objc_stubs` 内的 `_objc_msgSend$…` 引用，必须再查该 stub 的 BL 调用方；
本段已按 stub 调用方重写。）入队入口是
`+[BFCTracker trackCustomEvent:params:isRealTime:type:name:]`（0x115fd2cb4，调用点
0x115fd2e30）→ `-[BFCReportApiHandler trackCustomEvent:params:isRealTime:]`（0x1141c632c；
另见 0x104c69c7c BFCPayConstWrapper 与三个 beauty slider touchesEnded）；注意该
BFCReportApiHandler 选择子在本镜像的实现体只是 `ret`，真正编码/入队链仍在 BFCReportHandlerV2。

保存时将 sendingReports 与 cachedReports 拼接为数组，串行原子写文件；加载时读取数组，
用前 14 字符 yyyyMMddHHmmss 解析日期并过滤过期项，再分配发送和缓存数组。路径位于
Documents/reportv2 下的 delayv2、largev2、realv2。它保存的是已编码事件字符串；
不能推断跨账号缓存会重新绑定身份，字段编码阶段与登录变更需要进一步核对。
