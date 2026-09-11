# 直播分区请求契约修正

2026-09-10 核对结果：PiliPlus 使用 App 分区接口，但它的固定 Android 字段组在当前匿名连接中也返回 `-352`。不能把更新版本参数当作风控问题已解决。

当前官方 [分区页](https://live.bilibili.com/p/eden/area-tags?parentAreaId=2&areaId=86) 的页面源码 build time 为 2026-08-18。

- [分区逻辑](https://s1.hdslb.com/bfs/static/blive/live-region/static/js/81.d56e5df2.js) 使用 `xlive/web-interface/v1/second/getList`，传入 `platform=web`、`parent_area_id`、`area_id`、`sort_type`、`page`、`vajra_business_key`。
- [请求中间件](https://s1.hdslb.com/bfs/static/blive/live-region/static/js/221.391a2d3a.js) 对请求应用 WBI 签名，并保留普通网页会话。

NeoBili 分区入口现预先使用以上网页协议、项目现有 WBISigner 与 APIClient Cookie；Referer 匹配所选分区。删除原 App 分区 builder，推荐页继续保留先前已经可用的 App 推荐协议。没有添加风控后的自动身份切换、假指纹或验证码重放。

验证边界：匿名网页签名请求仍返回 `-352`，不能据此宣称服务端拦截已消失。生产 LiveAPI、LiveModels、AppSigner 经 Swift 6 宿主类型检查通过；网络依赖仅在此次类型检查中使用桩。API 回归测试新增一级分区、二级分区、分页及空签名字段覆盖。真机目录 smoke 会在恢复正常会话后验证一级分区、二级分区与第二页；这些联网结果由本轮总验收记录补充。

本轮 `/tmp/NeoBiliMiniLiveSmoke-20260910.xcresult` 的正常真机会话目录验证：推荐和关注正常，一级分区 `2/0` 仍返回 `-352`，随后停止分区分页请求。签名与 Cookie 修正尚未解除服务端限制。

官方 SDK 还会在页面存在 `_render_data_.access_id` 时将其作为 `w_webid` 加入签名，且内建 `CaptchaLoader` 交互式处理 `-352/-401`。匿名补齐普通页面的 `w_webid` 也未成功，因此不推断它是唯一缺失条件。PiliPlus 选分区时明确改调 `liveSecondList`，没有推荐接口支持同等分区筛选的可靠依据。可操作方案是风控时打开同会话的官方分区页面，由官网处理完整初始化和用户验证；点击房间后交回 NeoBili 原生播放器。
