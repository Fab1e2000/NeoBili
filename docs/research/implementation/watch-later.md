# 关联业务边界：稍后再看

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 关联业务边界：稍后再看

8.89新版WatchLater列表使用start_key/split_key及分页，Rx包装须实际订阅才发送，
当前包装dispose不直接cancel。删除effect的业务closure发fire-and-forget请求后就
完成observer；Store先发布reducer状态，再订阅effects，不是服务器ACK后才改UI。
首次appearance经每次binding的TakeCount(1)派发refetch，手动刷新与底部分页独立；
不能概括为进程全局once，也不能由动作派发推定请求已通过reducer门禁。

当前 [BiliAPI+WatchLater](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+WatchLater.swift)
使用 App `x/v2/history/toview/v2/list` 的默认排序分支，携带 start_key/split_key。
[WatchLaterModel](../../../NeoBili/Application/Library/WatchLaterModel.swift) 持有分页、增量去重、
账号及请求代次，空或重复游标停止分页。刷新先暂存新页，在旧卡淡出后换入。
列表支持多选；删除在撤销窗口后顺序调用单条 `/del`，失败恢复对应条目，并校验账号会话。
没有使用尚未接入的 v2 批量删除回执或其他页签。

添加仍使用网页 `/add`，等待业务成功后提示；端点先读 CSRF，再由 APIClient 获取 Cookie，
未显式传入 expectedSessionID。该边界应与列表分页和删除的会话保护分别维护。
稍后再看中的实际播放使用自身入口来源，不生成首页卡片点击或曝光事件。
