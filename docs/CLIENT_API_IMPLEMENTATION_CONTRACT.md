# 客户端 API 实现契约（端点/RPC 逐条）

本文把 [iOS 客户端网络协议研究](CLIENT_NETWORK_PROTOCOLS.md) 中已经落盘的地址级证据，
按“照着就能改代码”的契约视角逐条重排：一个端点/RPC 一条记录，字段固定为九项。
本文不替代主文档；主文档与独占验证产物保存原始指令、selector、调用链及独立复核，
本文归并已核证据与缺口。补证后须同步第9项和U表，不能保留已撤回的关闭理由。

本文按主题拆分。先选择下面的章节；函数地址、字段编号和未决结论保留在对应章节中。术语说明见[研究阅读指南](research/README.md)。

## 如何使用本文档

[阅读本章](research/contract/reading-guide.md)

## 社区资料的使用边界

[阅读本章](research/contract/community.md)

## 索引

[阅读本章](research/contract/index.md)

## 一、首页与推荐链

<a id="feed-01-feedindexapp-首页推荐"></a>
<a id="feed-02-feedindexinterest启动引导兴趣选择"></a>
<a id="feed-03-feedsecondinterest二次兴趣选择"></a>
<a id="feed-04-feedindexstorystory-tab"></a>
<a id="feed-05-不感兴趣与撤销xfeeddislike"></a>
<a id="feed-06-推荐点击事件neuron--旧链-001365"></a>
<a id="feed-07-曝光与逐段可见时长事件"></a>
<a id="feed-08-兴趣选择曝光点击与提交事件"></a>

[阅读本章](research/contract/home-feed.md)

## 二、身份、设备登记与票据

<a id="dev-01-buvid-本地生成与存储链非-http但决定多端点身份"></a>
<a id="dev-02-设备资料登记54-项指纹-payload"></a>
<a id="dev-03-访客登记-bfcaccountguest-loadguestidwithcompletionblock"></a>
<a id="dev-04-账号刷新与-confirm"></a>
<a id="dev-05-新用户注册与换-token"></a>
<a id="dev-06-退出与撤销"></a>
<a id="dev-07-短信-ui-的-login_session_id本地派生"></a>
<a id="dev-08-三字段在所选-generateinfo-未赋值及实际-presence-规则"></a>
<a id="dev-09-访客取-rsa-公钥接口"></a>
<a id="ticket-01-getticketmossgrpc"></a>
<a id="ticket-02-x-bili-ticket--x-ticket-status-拦截器http-与-moss"></a>
<a id="hb-01-播放器移动心跳-xreportheartbeatmobile"></a>
<a id="hb-02-观看历史-xv2historyreport含-report_scene"></a>
<a id="hb-03-atomic-应用心跳与-nettrackerneuron-事件非独立端点"></a>
<a id="hb-04-公共服务端时间辅助-xreportclicknow"></a>

[阅读本章](research/contract/identity.md)

## 三、日志与上报通道

<a id="log-01-neuron-protobuf-日志通道"></a>
<a id="log-02-旧-v2-文本日志通道-databilibilicomlogmobileios"></a>

[阅读本章](research/contract/reporting.md)

## 四、推送

<a id="push-01-apns-token-与状态上报-xpushreportcenter12-字段"></a>
<a id="push-02-activitykit-推送-token-上报7-字段"></a>
<a id="push-03-通知点击回执-xpushcallbackclick"></a>
<a id="push-04-badge-回执-xpushcallbackbadge"></a>

[阅读本章](research/contract/push.md)

## 五、Laser / UPOS 上传

<a id="up-01-upos-pre-阶段-memberbilibilicompreupload"></a>
<a id="up-02-upos-initial--merge--singlepart-阶段"></a>
<a id="up-03-laser-反馈回执"></a>

[阅读本章](research/contract/uploads.md)

## 六、播放地址与预加载

<a id="play-01-playurl-grpcplayurlreq--playviewreq"></a>
<a id="play-02-预加载播放能力参数本地生成"></a>

[阅读本章](research/contract/playback.md)

## 七、稍后再看

<a id="wl-01-旧-phone-请求族add--del--list"></a>
<a id="wl-02-新版-watchlater-v2-请求族"></a>

[阅读本章](research/contract/watch-later.md)

## 八、搜索、评论与互动

<a id="search-01-搜索综合"></a>
<a id="cmt-01-评论主列表moss-grpc"></a>
<a id="cmt-02-评论发布与互动"></a>
<a id="act-01-三连点赞与投币"></a>
<a id="fav-01-收藏与合集"></a>
<a id="im-sync-01-消息未读同步bblink--moss-im-rpc-族"></a>
<a id="crash-01-崩溃与日志提交链kscrash--analyticsneuron--laser-回执"></a>
<a id="settings-up-01-设置上传同步bbcdeviceconfig-syncdifftoremote"></a>

[阅读本章](research/contract/search-comments-actions.md)

## 九、动态、直播、广告上报与 VIP 素材

<a id="dyn-01-动态综合页--选中-up--视频-tabmoss-rpc"></a>
<a id="live-info-01-直播播放房间信息与观看上报"></a>
<a id="ad-report-01-广告请求与上报"></a>
<a id="vip-mat-01-vip-hd-素材与权益入口"></a>
<a id="comic-01-漫画请求族manga-twirp--bfcapioptions"></a>
<a id="game-01-游戏中心h5-spm-注册表--bbtrack-埋点"></a>
<a id="creative-01-创作中心季列表memberbilibilicom"></a>
<a id="sdk-01-第三方-sdk--cdn--网页容器"></a>
<a id="pgc-01-番剧详情--vip--商城--支付请求族"></a>
<a id="danmaku-01-弹幕段请求与弹幕互动grpcapi-双传输"></a>
<a id="dyn-02-动态发布-createdynmoss-grpc"></a>
<a id="cmt-03-评论分享sharereplymaterial"></a>

[阅读本章](research/contract/dynamics-live-advertising.md)

## 表 ① 未决项与静态/运行期边界

[阅读本章](research/contract/open-questions.md)

## 表 ② 覆盖矩阵

[阅读本章](research/contract/coverage.md)

## 表 ③ 当前实现与证据边界

<a id="需要其他席位补的证据请求"></a>

[阅读本章](research/contract/implementation.md)

## 后续验证需要的证据

<a id="未改动声明"></a>

[阅读本章](research/contract/evidence-needed.md)

## 证据来源与适用范围

[阅读本章](research/contract/scope.md)
