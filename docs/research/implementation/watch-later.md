# 关联业务边界：稍后再看

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 关联业务边界：稍后再看

8.89新版WatchLater列表使用start_key/split_key及分页，Rx包装须实际订阅才发送，
当前包装dispose不直接cancel。删除effect的业务closure发fire-and-forget请求后就
完成observer；Store先发布reducer状态，再订阅effects，不是服务器ACK后才改UI。
首次appearance经每次binding的TakeCount(1)派发refetch，手动刷新与底部分页独立；
不能概括为进程全局once，也不能由动作派发推定请求已通过reducer门禁。

Neo的[BiliAPI+WatchLater](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+WatchLater.swift)用旧网页
list/add/del端点，当前列表一次读取，无v2分页。[WatchLaterView](../../../NeoBili/Features/Library/WatchLaterView.swift)
以空列表且非loading决定初次加载，refreshable另触发reload；删除先乐观移除，撤销
窗口确认后await HTTP，失败回滚。菜单添加await业务成功后提示，不采用旧包本地
observer完成语义。列表回写有loadID/removal revision/取消保护；RootView按账号
session重建库标签，MineView换号关闭服务弹窗，不能说页面完全没有账号保护。

仍有具体请求边界：add/remove先读csrf，APIClient随后另取Cookie快照，未传
expectedSessionID；删除在确认后检查账号一次，但成功移除/失败恢复及添加提示没有
再次绑定账号代际。页面重建/关闭不等于能撤回已发送请求；此处只记录调用边界风险，
不宣称已实测跨账号写入。若维护这项功能，应保留HTTP失败处理并将账号快照、
发送前检查和迟到回写关联起来；验证换号、迟到列表/回滚和重复binding。

这是库列表可用性及用户操作一致性问题。尚无证据证明新版分页、删除完成策略或
WatchLater广告日志是首页个性化推荐必要条件，不因协议差异升级全部接口，也不把
稍后再看入口的真实播放补成首页卡片点击/曝光；8.89外层账号归属与9.13契约没有新证据。
