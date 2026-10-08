# 公共 HTTP 网关流控

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 公共 HTTP 网关流控

公共 JSON 响应的 hook 与错误顺序另已闭合：_serializationFromRawData:error:
（0x116093474）解析 JSON/SKVObject 后，若有 customResponseAfterRequest，先同步
调用它（0x116093744），返回值替换解析对象（0x116093764），随后才读
ignoreCodeNonZero/code；未忽略且 code 非0，生成 BFCApiNonZeroErrorDomain NSError
并返回 nil。network completion（0x116092c3c）调用该 serialization 后才到
_queryRemoteEnd（0x116093a00），正常对象再 ORM，错误交 errorHandler：immediately
分支同步调用，其他分支 dispatch 到 responseQueue。transport error、nil raw 和
JSON 解析失败跳过此 custom hook。因此评论 code12015 hook 保存 needCaptcha/URL
先于 VM.parseErr 发信号，有公共层顺序支持，不能把两者当独立竞速。

`BFCFlowControlGateway.canInitWithRequest`（0x1145508a4）返回真。请求拦截
（0x1145508ac）询问 isControlWithURL；命中时生成 status=429 的 HTTP 响应和
domain=`com.bilibili.bfc.flowcontrol`、code=429 的 NSError，将其包装进 gateway 响应。
这条分支是本地阻断，不足以证明服务器刚刚返回了 429；实际 gateway 注册/执行顺序
仍需核对。

响应拦截（0x114550a88）的 isFlowControl（0x114550eb0）只识别 429 和 503。
提取 x-bili-retry-after 的辅助函数（0x114550488）遍历 allHeaderFields 的 key，用
isEqualToString 与该小写字面值比较，值取 intValue；没在此看到大小写归一化或标准
Retry-After 日期解析。缺值路径回 0，后续仍交给配置约束。响应 body 若可解析为 JSON，
取 message 作为错误文案，否则有资源文案兜底；保存 error.userInfo 供后续本地阻断复用。
非流控 HTTP 状态会调用 disableControl。网络错误/非 HTTP 响应的分支和 HTTP/Moss
差异仍需完整核对。

URL 规范化辅助函数（0x11454fe9c）通过 NSURLComponents 取 host 和 path，path 非空
时拼成 host+path；查询参数不在该键内，并检查 disableList。enableControl
（0x114550004）记当前 Unix 秒为 lastVisitTime，controlTime 为
`min(max(retryAfter, minRetryAfter), maxRetryAfter)`。isControlWithURL
（0x11454fb60）在当前时间不晚于 lastVisitTime+controlTime 时认为受控；另有
localPeriods 的 begin/end 和 localList 分支。缓存清理、列表匹配与时间边界还需进一步
验证，不应由这一局部链推断限制跨进程持久化。

FlowControlConst.config（0x1145506dc）由 BFCNetworkFlowControlConstWrapper 的
isNetFlowControlEabled、minRetryAfter/maxRetryAfter、localPeriods/localList 构造；
disableList 是 wrapper 返回字符串按 `|` 分隔。这些 getter 的配置来源、默认值、更新
时机未全部解码。wrapper（0x10495c480–0x10495cb10）已确认如下入口：实验键
net_flow_control_enabled 的 presetHitValue=1；远程整数
net.flow_control_min_retry_after 默认 3、net.flow_control_max_retry_after 默认 15；
flowcontrol.block.api.time 与 flowcontrol.block.api 分别取数组用于 localPeriods/localList。
这些 wrapper 有 Swift once/缓存入口，不能假设每次请求都会重新读取远程配置。
重试等待使用 Unix 秒差，因此上述 3/15 的单位是秒；最终运行值仍可能被覆盖。

Moss 网关请求（0x114550ec4）复用 isControlWithURL，命中时生成 code=1346 的错误和
BFCMossGatewayResponse；响应（0x114551030）依据 error.moss_maybeFlowControl 和
moss_isFlowControl 分支，读取相同 x-bili-retry-after 并更新/取消限制。两个 NSError
扩展方法进一步确认：moss_maybeFlowControl（0x115e0fe74）等于
moss_isResourceExhausted 或 moss_isUnavailable；moss_isFlowControl（0x115e0feac）
检查 domain=`io.grpc` 且 code=1346。这一自定义错误码不能原样当作 gRPC status；
ResourceExhausted（0x115e0fdb4）检查 io.grpc/code=8，Unavailable（0x115e0fe14）
检查 io.grpc/code=14；该入口只用 domain/code 分类。
这套网关与 Neuron.handleFlowControl 是独立机制，状态码、作用域和调度不可互换。
