# 社区资料的辅助核查

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 社区资料的辅助核查

### 来源、范围与判定

参考 SocialSisterYi 发起、社区贡献的 bilibili-API-collect；这里核对的是
[bilibili-plugins 保留分支](https://github.com/bilibili-plugins/bilibili-api-collect)的固定快照
`cfc5fddcc8a94b74d91970bb5b4eaeb349addc47`，不是原仓库完整历史或所有后续分支。
来源以 CC BY-NC 4.0 发布，见该快照的 [LICENSE](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/LICENSE)。下表是针对 NeoBili 的摘要和诊断，
不复制密钥、凭据示例或整段实现；链接固定到提交，避免分支更新改变对照对象。

核对包括下表文件正文与 `docs/`、`grpc_api/` 的端点、字段和事件名检索。
“已公开”表示该快照存在对应知识，不断言发现先后或 Neo 的代码来源；“未找到”不涵盖旧 Issue、
Discussion、其他镜像及未公开研究。结构定义、业务调用规则、当前源码、真实服务器行为分别判定。
社区材料不能单独关闭契约 U 表里的 iOS 运行期缺口，也不产生新增业务或高频任务的要求。

### 逐项对照

| 范围 | 社区来源 | 已公开内容 | 对现有文档与实现的诊断 |
| --- | --- | --- | --- |
| App 签名（R19） | [APP.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/misc/sign/APP.md) | 已有按键排序、查询串加盐后 MD5 的规则，也明确区分平台、功能与版本；Swift 示例使用 `.urlQueryAllowed`。 | 基础算法属社区已公开知识。该示例不是字节级校验基准；Neo 的默认 JS 保留集与 8.89 native 严格保留集仍须分开，空值、空格、加号及特殊字符用独立向量检查。 |
| 首页（FEED-01 / R01） | [recommend.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/video/recommend.md) | 已有 feed/index 与 Story 地址；feed/index 参数表偏 Android，fnver=1、pull 为布尔，login_event 注释为登录状态，且承认参数含义不明。 | 不能覆盖 iOS 9.13 样本的 fnver=0、数字 pull、flush=0/6/8、冷启动 login_event=2；这些是版本/来源冲突，不是应直接修正 Neo 常量的依据。刷新首游标与分页尾游标的生命周期未在该页找到同等说明。 |
| 播放能力（PLAY-01/02 / R02） | [videostream_url.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/video/videostream_url.md) | 已有 qn 档位与 fnval 位组合，该页 fnver=0 与推荐页 fnver=1 不一致。 | Neo 普通视频 Web 请求采用4048→16→1回退，不能把社区“所有可用流”理解成必然拿到所有格式；请求能力、账号权益、实际响应和硬件解码分别验收。 |
| BUVID（DEV-01） | [device_identity.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/misc/device_identity.md) | 设备标识页给出以 Android 设备特征为主的 MD5、双字符前缀及 37 字符结构，并列 fp_local/fp_remote 算法。 | 不能套到 iOS 8.89 的 36 字符 Y/Z、IDFA/IDFV、偏好→Keychain 取值链；也不能把 Web buvid3/buvid4、App BUVID 和服务器 fingerprint 合并。Neo 当前新生成走自身 IDFV，保留旧值。 |
| 设备/网络头（R18） | [Device proto](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/grpc_api/bilibili/metadata/device/device.proto)、[Network proto](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/grpc_api/bilibili/metadata/network/network.proto) | 已有 Device 字段1–15、Network 字段1–3与网络枚举；该 Device 定义未列我们 iOS 证据中的 guestId 字段16。 | 消息结构有重叠，字段实际生成与缺省需独立核对。Network.type 与 feed player_net 属不同枚举，不能因都出现数字3就互换。Neo 已接入 Device 和 Network 的明确子集，不等于全部元数据覆盖。 |
| 票据（TICKET-01/02） | [Ticket proto](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/grpc_api/bilibili/api/ticket/v1/ticket.proto)、[Web ticket](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/misc/sign/bili_ticket.md) | GetTicket 的 context/key_id/sign/token 和 ticket/created_at/ttl 已公开；Web 页面另讲 GenWebTicket。 | GetTicket 结构不是新发现；Web 票据的生成方法与三天有效期不能用于替代 iOS GetTicket 的签名和响应 ttl。x-ticket-status 消费及 iOS 缓存生命周期在所检文件中未找到同等说明。 |
| 移动心跳（HB-01） | [Heartbeat proto](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/grpc_api/bilibili/api/player/v1/player.proto) | 已公开 Mobile RPC、ts 回执和 played_time、actual_played_time、paused_time 等字段，多数字段未解释计算方法。 | 字段存在不等于计时语义已明确。该 gRPC 消息不能直接当 iOS HTTP mobile 的字段表；墙钟/倍率累计、起止触发、回执写回、文件缓存及重试仍引用我们的8.89调用链。 |
| 历史与 Web 心跳（HB-02 / R13） | [report.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/video/report.md) | 已有 history/report 与 Web heartbeat；Web 的 played_time 表示位置，页面明示部分时长算法是推测。 | 接口已公开。不能将 Web 的字段语义和15秒说明套给移动心跳；Neo 的5/15秒 checkpoint 只同步历史，起止边界才发 mobile，实际观看与倍率加权时长独立累计。 |
| 登录续期（DEV-04） | [cookie_refresh.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/login/cookie_refresh.md) | 已有 Web Cookie 的检查、刷新及使用旧 refresh_token 确认的流程。 | 流程思想重叠，不等于 iOS oauth2/refresh_token 的请求和加密规则相同；不得用 Web refresh_csrf/CorrespondPath 替换 App 链。存储失败与换号保护另查当前实现。 |
| 点赞/点踩/投币/三连（ACT-01） | [action.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/video/action.md) | App 操作端点已有；其中 App like 表及示例写0点赞/1取消，点踩写0点踩/1取消。 | 用户点击点赞收到“取消赞失败”，支持社区操作码。Neo 已修正为0点赞/1取消，撤回8.89数值翻转等于网络目标状态的解释；点踩保持原映射。修复后的双向运行验收另列。 |
| 收藏（FAV-01） | [video/action.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/video/action.md)、[fav/action.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/fav/action.md) | 已有收藏资源增删与文件夹操作。 | 基础端点属已有知识；Web CSRF 和 App tracker 的角色不同，不能为追求全 App 化搬错鉴权，也不能据已收录端点推出 Neo 所有收藏入口已对齐。 |
| 稍后再看（WL-01/02） | [toview.md](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/historytoview/toview.md) | 已有旧列表、add/del/clear。 | 不能把整个稍后再看归为新发现；该页未找到 v2/list、v2/dels 的规则，Neo 的 v2 分页仍以对应契约为依据。 |
| 搜索/评论/动态（SEARCH-01 / CMT-01 / DYN-01） | [搜索](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/docs/search/search_request.md)、[评论 RPC](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/grpc_api/bilibili/main/community/reply/v1/reply.proto)、[动态 RPC](https://github.com/bilibili-plugins/bilibili-api-collect/blob/cfc5fddcc8a94b74d91970bb5b4eaeb349addc47/grpc_api/bilibili/app/dynamic/v2/dynamic.proto) | 已有 Web 搜索说明与评论、动态的 RPC 定义。 | 它们可定位字段和接口，不能证明 iOS 的入口选择、分页状态、账号归属或回调生命周期。未作这些业务全部方法逐字段等价认证。 |
| 设备登记/访客/曝光日志（DEV-02/03、FEED-06/07、LOG-01） | 所检快照的 `docs/` 与 `grpc_api/` | 未检出 x/resource/fingerprint、guest/reg、Neuron、feed-card.duration 等对应名称；Ticket 文件存在 x-fingerprint 及 AndroidDeviceInfo 线索。 | 只判“所检范围未找到同等说明”；Android 指纹结构不能补成 iOS 54项 payload。不能据关键词零命中认定原作者未研究、全社区未知或本项目首创。 |

### 需要保留的冲突与实现差异

- **App 点赞语义修正**：用户报告原实现点击点赞提示“取消赞失败”；按钮传递的是希望达到的
  liked 状态，旧网络层将 true 编码1。结合社区0点赞/1取消的说明，当前改为 true→0、false→1。
  8.89 `_updateLikeState` 的 xor1 只证明数值翻转，原先进一步断言 wire 是目标状态缺乏依据，撤回。
  回归检查 App 点赞和取消的最终表单，Web 的1/2与点踩的0/1保持各自规则。
  修复后真实服务器的双向前后状态尚需实际使用确认；用户报错不等于修复后验收，
  `has/like` 社区页提示“近期”限制，不能只用单一回读接口或成功 toast 作为完整证据。
- **签名字节差异**：R19 的 native/JS 转义差异仍在；社区示例不能作为当前编码器的独立 oracle。
  含争议字符的离线向量与真实 wire 字节需分别核对；既有错误 sign 也被接受的推荐样本不证明验签正确。
- **指纹生命周期差异**：DEV-02 当前登记使用响应完成时间计算并持久化 expiry，公共头路径等待登记；
  8.89 研究是请求开始时间、内存 expiry 与异步 getter。社区 Android 设备页不能消除这些差异。
- **文档中的“缺实现”必须跟随源码**：DeviceIdentity 已接入 guestid、Device、Network 子集与票据；
  PlaybackWatchProgress 已分开真实观看和倍率加权累计。不能继续把这些写成待实现项。
  网络质量、地区头、完整指纹及全部生命周期的一致性仍未因此得到证明。

基础接口与结构优先复用社区索引；iOS 特有行为保留原始调用链、样本版本与残余。
这里的对照不证明推荐画像更新，也不是对全部56个契约的首次发现或完整正确性认证。
