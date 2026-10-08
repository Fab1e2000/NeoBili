# iOS 客户端网络协议研究

本文维护客户端请求及上报的覆盖范围、静态调用证据和缺口。**想直接改代码的读者请先看
[实现契约](CLIENT_API_IMPLEMENTATION_CONTRACT.md)**：它把本文的地址级证据按端点/RPC 逐条重排，
每条九字段（端点/触发/请求头/参数来源/签名编码/响应结构/与 NeoBili 差异/证据版本/残余）。
推荐样本与当前 NeoBili 行为见 [推荐观察](RECOMMENDATION_OBSERVATIONS.md)，身份字段详解见
[参数策略与待验证问题](research/recommendation-parameters.md)，与官方行为的差异清单见
[推荐实现核查](RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。
本文是研究参考，不是官方接口规范，也不表示 NeoBili 已实现这些机制。

本文按主题拆分。先选择下面的章节；函数地址、字段编号和未决结论保留在对应章节中。术语说明见[研究阅读指南](research/README.md)。

## 样本与证据边界

<a id="本地联网对照的当前边界"></a>
<a id="社区镜像辅助索引"></a>

[阅读本章](research/protocols/evidence.md)

## 覆盖清单

[阅读本章](research/protocols/coverage.md)

## 传统 HTTP 参数与请求构造

[阅读本章](research/protocols/http-requests.md)

## options 默认值、缓存与响应入口

<a id="http-候选域名回退"></a>
<a id="公共服务端时间辅助请求"></a>

[阅读本章](research/protocols/http-options.md)

## Ktor 桥接与公共参数

<a id="ktor-实际请求桥接与普通拦截器门控"></a>
<a id="ktor-公共参数签名与编码"></a>

[阅读本章](research/protocols/ktor.md)

## Moss 服务选择、原生 metadata 与流重连

[阅读本章](research/protocols/moss.md)

## 公共 HTTP 网关流控

[阅读本章](research/protocols/gateway.md)

## ticket 拦截与更新入口

[阅读本章](research/protocols/tickets.md)

## 设备登记与访客生命周期

<a id="短信-ui-的-login_session_id"></a>
<a id="账号校验刷新注册与退出"></a>

[阅读本章](research/protocols/device-registration.md)

## 会话来源与旧活动上报

<a id="启动性能诊断的节点采样与本地接收边界"></a>

[阅读本章](research/protocols/sessions.md)

## 旧 V2 文本日志通道

[阅读本章](research/protocols/legacy-logs.md)

## 首页请求的业务组装

<a id="首页-vm-的首次请求重试与响应状态"></a>
<a id="推荐点击展示与可见时长的业务触发"></a>
<a id="不感兴趣的本地操作与请求"></a>

[阅读本章](research/protocols/home-feed.md)

## 功能、设置与首页请求参数

<a id="seriesloader-参数与响应证据"></a>
<a id="story-清晰度选择与偏好写入的独立执行链"></a>

[阅读本章](research/protocols/settings-parameters.md)

## 设置配置同步、上传与缓存

<a id="distribution-通用偏好"></a>
<a id="实验devicedecision值来源与-upload-账号边界task-14-补"></a>
<a id="playurl-旧操作配置"></a>
<a id="章节偏好的直接-distribution-请求"></a>

[阅读本章](research/protocols/settings-sync.md)

## Neuron Protobuf 日志通道

<a id="编码与缓存时点"></a>
<a id="消息描述符"></a>
<a id="请求分帧与回执"></a>
<a id="调度后台与流控"></a>
<a id="公共信息与采样配置"></a>

[阅读本章](research/protocols/neuron.md)

## 预加载播放能力参数

[阅读本章](research/protocols/preloading.md)

## UGC 播放地址请求入口

<a id="弹幕请求族与传输分支task-29-补"></a>

[阅读本章](research/protocols/playback.md)

## 直播播放信息与房间信息入口

<a id="直播入房权限消费者与配置存储task-29-补"></a>
<a id="直播观看时长的独立通道"></a>

[阅读本章](research/protocols/live.md)

## 搜索请求与查询会话

[阅读本章](research/protocols/search.md)

## 动态综合页请求

<a id="选中-up-的独立请求"></a>
<a id="排序选择账号缓存与刷新触发"></a>
<a id="综合页刷新与专用-sessionid"></a>
<a id="条目不足时的自动补页"></a>
<a id="视频-tab-的独立-dynvideo-请求"></a>
<a id="综合页响应状态与两种缓存"></a>
<a id="动态响应描述符辅助请求族与缓存过期回执task-14-补"></a>
<a id="动态发布-endpoint-与字段表task-26-闭合"></a>

[阅读本章](research/protocols/dynamics.md)

## 评论列表 RPC、发布与互动

<a id="主列表字段与分页来源"></a>
<a id="子回复详情的不同请求"></a>
<a id="排序操作到重新请求"></a>
<a id="广播插入与单条评论补取"></a>
<a id="评论广播房间与双向流"></a>
<a id="发布字段与验证码续提交流程"></a>
<a id="普通评论键盘的另一条模型路径"></a>
<a id="评论赞踩与取消的请求和局部-ui"></a>
<a id="评论删除确认与参数覆盖"></a>
<a id="评论置顶与取消"></a>
<a id="评论举报页面与原生回调"></a>
<a id="评论失败恢复与分享链task-29-补"></a>

[阅读本章](research/protocols/comments.md)

## 搜索自动播放的 Universal 偏好消费

[阅读本章](research/protocols/search-autoplay.md)

## 收藏业务参数的入口

<a id="首页-inline-三连的请求"></a>
<a id="首页卡片长按三连的另一入口"></a>
<a id="独立播放器的-ugc-三连-provider"></a>
<a id="独立播放器普通登录点赞"></a>
<a id="独立播放器点踩"></a>
<a id="独立播放器投币-provider-与-service"></a>

[阅读本章](research/protocols/video-actions.md)

## 推送注册、权限状态与设备上报

<a id="activitykit-两种-token-的独立上报"></a>
<a id="通知点击延后导航与-badge-回执"></a>
<a id="im-未读与消息同步链的入口与消费bblink-桥task-11-补齐"></a>
<a id="im-未读同步的字段级链task-18-补"></a>
<a id="本地通知与-category"></a>

[阅读本章](research/protocols/push.md)

## 崩溃插件的实际提交与本地缓存完成

<a id="logservice注册日志后端与远程配置采用时序"></a>
<a id="crash实验门禁与issue模型"></a>
<a id="crashkscrash-提交路径与-laser-回执端点task-18-补"></a>
<a id="laser-附件任务的日期窗过期与外部清理task-13-补"></a>
<a id="upos-取消后-laser-completion-的回执链task-14-补"></a>

[阅读本章](research/protocols/crash-reporting.md)

## 稍后再看的旧 Phone 请求族

<a id="bblistwatchlatermanager-原生单条与批量添加"></a>
<a id="新版-watchlater-v2-列表清空与删除-builders"></a>

[阅读本章](research/protocols/watch-later.md)

## 播放历史同步与播放器心跳

<a id="历史请求的校验和字段"></a>
<a id="历史服务的计时与触发"></a>
<a id="播放器心跳的边界"></a>
<a id="心跳上下文会话与发送队列"></a>

[阅读本章](research/protocols/watch-history.md)

## 广告加载与归因的静态入口

<a id="dmad-响应模型字段与响应侧消费"></a>
<a id="广告去重容器的锁与生命周期边界"></a>
<a id="story选集面板与卡片翻译的实际入口"></a>
<a id="hdmainv2普通曝光项检查触发与页面复用"></a>
<a id="日志附件laser实际按钮归档上传与结果反馈"></a>
<a id="blog缓冲区压缩最终文件写入与flush限度"></a>
<a id="hd2外层账号事件重建与新曝光池边界"></a>
<a id="laser启动任务服务器任务与预先去重"></a>
<a id="hd2-notice-的门禁参数和回执时间归属"></a>
<a id="hd2-设置页路由与-vmtype-映射task-13-补"></a>
<a id="设置上传缓存与重试边界"></a>
<a id="设置上传入口的账号门禁task-13-补"></a>
<a id="字幕选择ai翻译目标偏好与公共-locale-元数据"></a>
<a id="upos-各阶段配置分片状态适配与取消通知"></a>
<a id="hd2-mainvm-迟到回执的原vm与共享状态边界"></a>
<a id="upos-自身数据库过期与停机后的回调门禁"></a>
<a id="story-ai语言偏好到-unite-播放解析及响应回显"></a>
<a id="hd2-loadmore-的原vm当前数组与入口门禁"></a>
<a id="watchlater-管理菜单到确认与工具栏动作"></a>
<a id="hd2-刷新旧卡保留与布局裁剪"></a>
<a id="hd2-notice-第二按钮的安全页面路由"></a>
<a id="hd2-follow_mode-响应持久化与-logout-清理"></a>
<a id="locale-元数据的具体-httpmoss-采用范围"></a>
<a id="watchlater-列表实际行点击与-uri-来源"></a>
<a id="hd2-卡报告时间精度与请求局部序号"></a>
<a id="kotlin-翻译设置与-alwaystranslate-派生状态"></a>
<a id="watchlater-页面返回检查与列表重拉的边界"></a>
<a id="独立-kotlin-locale-hook-的-ktor-采用与覆盖门禁"></a>
<a id="hd2-follow配置来源与设置页提交触发"></a>
<a id="fallbackcache-native-export-与-nil-expiry-的静态实现边界"></a>
<a id="fallbackcache-的-root-注册文件后端与取消边界"></a>
<a id="kotlin-locale-的编码与独立缓存更新"></a>
<a id="hd2-idx-的动态-int64-gettersetter-与重新启动读取"></a>
<a id="languagesettingspage-的-compose-生命周期提交"></a>
<a id="phone-推荐设置页的点选写入与-recsys_mode-三层值"></a>
<a id="phone-播放模式引导入口曝光与当前实例移除"></a>
<a id="hd2-与-phone-feedsetting-路由的解析和同名-bus-门禁"></a>
<a id="vip-hd-素材请求响应模型入口点击与首页回执"></a>
<a id="pgc-番剧详情播放入口与-follow付费请求族"></a>
<a id="会员状态读取与权益提示"></a>
<a id="漫画商城支付游戏创作请求族入口"></a>
<a id="ktor-开关的重复读取client-once-与已创建-task"></a>
<a id="dd-生产启动配置-key-更新与响应版本触发"></a>
<a id="hd2-cardpool-的模型映射与实际-cell-注册"></a>
<a id="hd2-设置响应字段到可见行及提交边界"></a>

[阅读本章](research/protocols/advertising.md)

## 第三方 SDK、CDN 与网页容器的静态入口

<a id="依赖清单与来源边界"></a>
<a id="cdn"></a>
<a id="网页容器"></a>
<a id="第三方发送侧与-cdn-管线分支task-30-补"></a>
<a id="普通首页-v2-曝光池静态补证"></a>
<a id="ticket-maxtries-的有限消费边界"></a>
<a id="评论分享消息结构补证"></a>
<a id="swift-neuroncore-的独立过期清理"></a>
<a id="首页自定义-raw-policy-与明确-owner-覆盖"></a>
<a id="swift-neuron-配置-resolver-与通用任务门"></a>
<a id="ktor-attrs-的真实-map复制与-key-等价"></a>
<a id="补证请求构造与回执的静态范围"></a>
<a id="辅助模块的确定映射与分支"></a>
<a id="两枚投币与诊断服务注销"></a>
<a id="启动事务心跳缓存与日志结构补证"></a>
<a id="所选播放器入口与预加载边界"></a>
<a id="发布成功消息的真实注册"></a>
<a id="dd-服务实际构造与-legacy-缓存的局部补证"></a>
<a id="gripper-gripper-安装与覆盖规则"></a>

[阅读本章](research/protocols/external-services.md)
