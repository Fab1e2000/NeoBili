# 社区资料的使用边界

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 社区资料的使用边界

[API-collect 逐项对照与诊断](../implementation/community.md#社区资料的辅助核查)
记录固定来源提交、已有知识、平台冲突及未找到的行为细节。签名、基础端点、Ticket 和移动心跳
消息结构已有社区资料；iOS 字段生产者、触发时机和缓存状态不能由 proto 定义直接补全。
尤其不要混用 Web 与 App 的 played_time、Android 与 iOS 的 BUVID、GenWebTicket 与 GetTicket；
App 点赞按 ACT-01 的运行反馈修正为0点赞/1取消。新增社区依据保留其来源等级，不把它写成8.89反汇编
或9.13运行证据；全文的“已闭合”仅适用于对应条目标明的覆盖范围。
