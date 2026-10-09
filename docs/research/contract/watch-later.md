# 七、稍后再看

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 七、稍后再看

### WL-01 旧 Phone 请求族（add / del / list）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | Add 0x10f53eb00 → `https://api.bilibili.com/x/v2/history/toview/add`（参数 id 12346）；Delete 0x10f53edcc → `https://api.bilibili.com/x/v2/history/toview/del`（12346）；List 0x10f53f190 → `https://api.bilibili.com/x/v2/history/toview`（12345）。另有 `BBListWatchLaterManager` 用 POST `https://api.bilibili.com/x/v2/history/toview/add`（options 0x10434e60c）与批量 `https://api.bilibili.com/x/v3/fav/toview/adds`（0x10434ea0c–0x10434ea54）。 |
| 2) 触发时机 | 用户添加/删除/查看稍后再看列表；旧 manager 的单条与批量添加入口见主文档“BBListWatchLaterManager 原生单条与批量添加”。 |
| 3) 请求头 | 未在主文档逐项列出。 |
| 4) 参数及来源 | 未在主文档逐项列出（字段来源与主文档“稍后再看”章节的 builder 一致）。 |
| 5) 签名与编码规则 | 未在主文档记录。 |
| 6) 响应结构 | 未在主文档逐项列出。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 用旧网页 `x/v2/history/toview/add`、`x/v2/history/toview`、`x/v2/history/toview/del`（[BiliAPI+WatchLater.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+WatchLater.swift)），当前列表一次读取、无 v2 分页（review“关联业务边界：稍后再看”）。add/remove 先读 csrf，`APIClient` 随后另取 Cookie 快照，未传 `expectedSessionID`；删除在确认后检查账号一次，但成功移除/失败恢复及添加提示没有再次绑定账号代际。 |
| 8) 证据等级与版本 | 8.89 静态（0x10f53eb00/0x10f53edcc/0x10f53f190/0x10f53f190、0x10434e60c）；当前源码。 |
| 9) 残余不确定项 | 10434e60c/ea0c builder及104353ef0/f7c response已raw核：aid/resources caller Int64/字符串逗号，spmid、版本v2，可选from仅非nil才numberFromWithTrace且nil结果省略；Model isEnabled/iconStyle0与既有mapper一致。batch103710ad8→104353994只是转发，实际资源producer上游仍精准追；不从nearest析构标签归业务owner。UI snackbar/账号写入实际交错另验（root-static-remaining/findings.md）。 |

### WL-02 新版 WatchLater v2 请求族

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | List `https://api.bilibili.com/x/v2/history/toview/v2/list`（0x101109004），`/data` 映射；Clear `https://api.bilibili.com/x/v2/history/toview/clear`（0x1011092ec，`clean_type`）；Dels `https://api.bilibili.com/x/v2/history/toview/v2/dels`（0x10110952c，唯一业务参数）。List 地址另经官方国际版9.13成功抓包核实；clear/dels 保留静态证据边界。 |
| 2) 触发时机 | 新版 WatchLater 列表首次 appearance 经每次 binding 的 `TakeCount(1)` 派发 refetch；手动刷新与底部分页独立；Rx 包装须实际订阅才发送，当前包装 dispose 不直接 cancel。删除 effect 的业务 closure 发 fire-and-forget 请求后就完成 observer；Store 先发布 reducer 状态再订阅 effects，**不是服务器 ACK 后才改 UI**。 |
| 3) 请求头 | 9.13 List 抓包含 buvid/app-key/x-bili-ticket/session_id，不含 Cookie/Authorization；凭据原值不纳入文档。 |
| 4) 参数及来源 | List 首批 start_key/split_key 空串，后续消费响应 next_key/split_key；本批 asc=false/sort_field=1。Dels resources 的业务资源类型仍须分别核对。 |
| 5) 签名与编码规则 | List 当前样本为 App GET，query 含 access_key/appkey/sign/ts 与公共身份字段；NeoBili 复用自身 iPhone 签名和凭据，不复制抓包值。 |
| 6) 响应结构 | code=0；data.has_more Bool、next_key/split_key String、list 数组。普通视频元素含 aid/bvid/cid/title/pic/duration/add_at、owner、dimension；另含 page/card_type/arc_state 等字段，不推定全部卡片类型已兼容。 |
| 7) 与 NeoBili 当前实现的差异 | 已接 v2 默认分支分页和多选整理；按需加载、保序去重及重复游标终止。删除沿用已验收单条接口，统一撤销后顺序提交；部分失败恢复，账号/请求代际隔离。未接未经当前样本确认的 v2 批量删除回执或其他页签。 |
| 8) 证据等级与版本 | 8.89 静态（0x101109004/0x1011092ec/0x10110952c）；9.13官方 List 成功请求及响应形状；当前源码。 |
| 9) 残余不确定项 | MainVC.viewDidLoad/setup两helper/appearance指定body已读，未在这些body找到显式账号通知observer，外部notification发送源未定位不能全局否定。v2资源Int64→decimal→comma与cacheMID-at-response复用已证；现代batchwrapper103710ad8仅转入[String]，直接BL未定位上游element producer，不等于不存在，未知indirect源保留有界未证。缓存/取消实际交错与9.13另验（root-static-remaining/findings.md）。 |
