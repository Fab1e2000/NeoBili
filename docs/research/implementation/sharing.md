# 关联业务边界：分享菜单

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 关联业务边界：分享菜单

8.89 BFCShareOperation持有canonize callback，channelList/clickBlock则属于
operation.model。dispatch group的main notify先dismiss loading，terminated则退出；
有error经当前delegate判forbidden，true提示错误并回调失败，不呈现菜单，false允许
默认channel list回退。canonize后复制到model再present；delegate真实规则见下方补充，
不能把网络失败一概当禁止分享，也不能将present调用当发送/用户分享成功。

**补充（8.89 静态，T2 findings C-7）**：delegate 由 ShareBaseModule 初始化体 `sub_10018CDA8`
装配为 ShareCoreInject（与 `BFCShareInjector` classref 交叉扫描的唯一命中 0x10018cde4），
`isForbiddenAPIError:` 要求 nonZero domain 且 code==110000。原先的 delegate 规则问题至此闭合；
它仍是官方实现细节，不改变下面的 Neo 判定。

Neo视频页用链接打开系统UIActivityViewController，无上述网络分享operation、服务端
channel配置或forbidden判定。不相关逻辑不新增实施项；如果未来支持远程分享菜单，
再定义operation/model所有权、可回退错误、取消/迟到回执和用户完成语义。分享链没有
被证明是普通首页个性化推荐必要条件，不因旧包功能差异改系统分享或补假事件。
**判定（源码）**：[VideoActionBar](../../../NeoBili/Features/VideoDetail/VideoActionBar.swift)
只有系统活动列表，没有可迁移的 delegate 分支；官方规则闭合不产生实施项。
