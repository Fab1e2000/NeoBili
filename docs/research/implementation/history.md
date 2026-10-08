# 关联业务边界：LatestHistory 与本机续播

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 关联业务边界：LatestHistory 与本机续播

8.89 HD2 helper在enableResumePlaying关闭时直接handler(nil,nil)，不发LatestHistory
RPC；开启才发business=archive及playerPreload。无error且reply.items非nil才回调
model；items=nil本body跳过handler，不是显式空回执。descriptor确认items是单
CursorItem message，不是数组；GPB缺值getter的运行可达性及后续uri消费已由尾部证据闭合
（唯二调用点与 uri→processUrl），本文已判为不作为实施前置
（见[已闭合与残余](maintenance.md#已闭合)）。
因此不能把这个RPC当首页刷新、观看上传或历史列表分页，也不能按名称将items建数组。

Neo无此RPC；[PlaybackProgressStore](../../../NeoBili/Application/Player/PlaybackProgressStore.swift)
以bvid/cid保存本机进度，不依赖登录/云历史，忽略无效位置与近片尾；PlayerViewModel
开流及拿到时长后读取，PlaybackResumeState在到达目标前拒绝旧位置/短暂0。
本机续播是当前明确语义，不因缺云端RPC就判错或要求账号隔离本地进度；网页历史
列表和App观看同步分别有独立通道。

若产品需要跨设备续播，再设计typed单项、账号/请求代际和每条结果路径的明确完成，
对缺项、禁用、取消及迟到回执给出可测试行为，不照搬跳过callback造成等待不结束的
风险。新版契约、云/本机进度优先级及关闭设置需先确认；无该功能影响推荐的因果证据。
**改判（源码）**：`LatestHistory`、`resumePlaying` 在源码中均无标识，本机续播是本机既定
语义，因此不作为本文实施前置；官方侧的可达性与 uri 消费已由 G3 闭合（0x1002397a8/
0x100242ea4 唯二调用、uri→processUrl 0x1002390c4），见
[已闭合与残余](maintenance.md#已闭合)。
