# 本机校验范围与入口

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 本机校验范围与入口

验收标准是现有研究的已确认规则以及用户确定的产品策略，不要求与官方新版逐项一致。
测试必须使用当前生产实现；注入时钟、设备事实与传输响应可以验证协议和生命周期，但不能把模拟成功响应写成服务器接受。

| 链路 | 生产实现与本地检查 | 判定边界 |
| --- | --- | --- |
| 首页请求、首尾游标、启动/横幅状态 | AppRecommendationProtocol / Session / Page；AppRecommendationTests、RecommendationPolicyTests、RecommendationAlignmentTests | 固定关闭自动刷新、静音等属于产品策略；请求生成与服务器推荐效果分开判定 |
| 账号/设备代际与公共编码 | DeviceIdentity、AppRequestEncoder；AppProtocolIntegrationTests、AccountSessionTests、OfficialBehaviorAdoptionTests | golden 字节、换号取消和字段传播可离线验证；不等于真实 token 被接受 |
| 设备指纹 | IOSFingerprintProtocol、AppDeviceRegistration；DeviceRegistrationTests | 加密、结果保存、失败冷却已有覆盖；资料只实现明确子集，不是54字段全覆盖。另有如下生命周期差异 |
| 访客与票据 | AppGuestRegistration、AppTicketService；GuestRegistrationTests、AppTicketTests、AppDeviceMetadataTests | 公钥、guest_id、ticket 的持久化/过期/迟到响应可注入测试；实际获取与续期须另有联网结果 |
| 点击、曝光与观看 | RecommendationClick、AppBehaviorReporter、AppWatchProtocol、播放器状态机；RecommendationExposurePolicyTests、RecommendationBehaviorTests、OfficialBehaviorAdoptionTests、BehaviorQueueTests | 核对原始卡片追踪、比例门限、逐段时长、暂停/seek/倍速、终止边界；本地记录事件不证明服务端更新兴趣 |
| 登录续期 | AppLoginRenewal、DeviceIdentity；LoginRenewalTests | info→时间→refresh→保存→旧凭据confirm、换号及存储失败可离线验证；无真实完整续期材料时不强制刷新账号 |

设备指纹 DEV-02 的当前具体差异：研究规定成功后 expiry 取请求发起时刻+86400，且 expiry 仅在内存；当前 `register` 取响应完成时刻+86400，并把 expiry 和设备ID一起持久化。研究 getter 异步更新并立即返回旧ID，当前公共头路径会等待 `register` 完成（请求超时10秒）。当前还增加了非零业务码拒绝门禁。上述差异应独立评估，不能因为加密回环测试通过而标成完全契合。

Neuron LOG-01 的当前发送策略也不是逐项复制：HTTP成功判定为200–299并检查可解析JSON的code，研究所选层仅判HTTP200；持久删除在发送前完成，歧义超时不重放，用于避免重复上报。它是显式可靠性取舍，不能称为官方重试/缓存规则完全一致。

`zsh offline-harness/protocol-check.sh` 复用当前源码验证签名字节及首批/刷新/分页参数。
加 `--network` 最多发送4个无自动重试的GET：公钥、服务器时间，以及在提供独立私有上下文文件后两批推荐。
输出只含HTTP/业务码、字段存在性与卡片数量，不输出凭据、标题或完整URL；禁止跨站重定向。
`NEOBILI_PROBE_CONTEXT` 指向私有JSON文件（accessKey、mid、headers），其中 headers 使用 NeoBili 自身上下文。
未提供时明确跳过个性化推荐，不用访客结果替代。该入口不自动收集凭据，不合成设备指纹，不发送观看/点赞/收藏，不执行凭据轮换；注入头仅验证该快照，不验证头部生成生命周期。
运行结果保存于忽略的 `DerivedData/Validation/`，不把某次运行状态当作长期协议事实。
