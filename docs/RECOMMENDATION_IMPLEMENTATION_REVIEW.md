# 推荐实现核查与改进建议

NeoBili 已把“点哪张卡、从哪里进入、实际看了多久”接到同一条播放链，但设备登记和
“看见了哪些卡、看见多久”仍缺一段。首页请求还有按既定策略固定的状态值。先补清这些
事实，再判断推荐变化；请求成功不是兴趣画像已经更新的证明。

本文对照当前工作区源码，记录实现差异和可实施建议，不修改生产实现。用户已授权用
本人既有账号与设备资料做少量本地联网对照，由S1主持串行实验，S2复核构造与结果；
未经协调不并发消耗同账号推荐状态。已有未提交实现也是核查对象，不视作已发布版本。
敏感输入和原始响应留在本地忽略的独占目录，不修改其他研究文档。

## 证据与判定边界

- **8.89 静态**：S1 对第三方处理的 iOS 8.89.0/build 88900100 包定向反汇编所得。
  未执行该 App，不代表 9.13 或当前服务器要求。函数地址见
  [客户端协议研究](CLIENT_NETWORK_PROTOCOLS.md) 与 [待确认参数](../NOTSURE.md)。
- **9.13 采集/既有对照**：以 [推荐观察](RECOMMENDATION_OBSERVATIONS.md) 和
  [待确认参数](../NOTSURE.md) 中明确标注的样本为准；中国版与国际版分别解释。
  手机采集保持关闭；新增本地请求结果须另标版本、参数与实验边界，不输出真实编号、
  票据、密钥或账号凭据。
- **社区辅助线索**：保留的 bilibili-API-collect fork/镜像只说明社区页面的描述与示例，
  不替代IPA、当前采集或服务端验收；本文不执行其中请求。逐项对照见后文，不能凭
  README致谢或相同常量认定NeoBili直接继承了某份实现。
- **源码核查**：沿解析、状态所有权、调用者、最终编码检查。下述“一致”只指列出的
  行为一致；“有差异”不等于推荐根因；“尚不能确认”不补成常量。
- **测试证据**：本文读取测试内容以确定现有覆盖，未运行App测试、编译、Simulator
  或部署。本地脚本实验单独记录，不能代替回归、真机或推荐因果验收；已有测试定义
  和历史验收不能代替当前执行。

优先级 P0 表示实施前必须闭合的身份/关联基础，P1 表示主要行为补齐，P2 表示后续协议
完善。优先级来自缺口与依赖，不表示已证明改善推荐。用户暂定全部查清后统一升级。

## 当前差异清单

### R01 首页参数必须分版本配置、能力、设置和操作状态（P1）

**证据**：8.89 `BBHD2PhonePegasusMainApi.params` 0x10df56ed4 取对象状态、Reachability、
广告服务、播放器 helper 和窗口类型；不是固定字段模板。`loadData` 0x10df58a10、
`loadMore` 0x10df5a4c0 设置不同刷新状态。9.13 的首批/下拉/翻页及混合操作观察见
[观察文档](RECOMMENDATION_OBSERVATIONS.md#首页参数随操作的变化)。

**NeoBili 实际行为**：[AppRecommendationProtocol](../NeoBili/Core/Networking/AppRecommendationProtocol.swift)
按 pageIndex/isRefresh/isLayoutChange 生成 flush=0/6/8/2、pull=1/0 与自身游标。
column=4、auto_refresh_state=4、login_event=0、inline_sound=1、inline_sound_cold_state=4、
autoplay_card=4、video_mode=1、inline_danmu=2、client_attr=1、qn_policy=1、player_net=1、
soft_fnval=2、teenagers_age=16、disable_rcmd=0 等仍固定；函数没有读取对应功能/网络/账号状态。
[BiliAPI+Recommendation](../NeoBili/Core/Networking/BiliAPI+Recommendation.swift) 合入自身
启动状态与横幅后调用 getApp，最终由 AppRequestEncoder 添加凭据、时间戳与签名。

**补充来源**：S1的设置专项已沿UI写入、Preferences/设备配置、Swift MainApi builder及
getApiOptions核查。以下是8.89函数体规则，不是9.13运行验收；主体已整合到
[客户端协议研究](CLIENT_NETWORK_PROTOCOLS.md)，进一步默认值/覆盖证据仍由S1在忽略的
`DerivedData/Validation/official-ios-package/analysis/recommendation_events/settings_parameter_provenance.md`工作表
维护，本文只读两者，不编辑研究来源。

| 字段 | 8.89实际生成链 | Neo固定值的边界 |
| --- | --- | --- |
| auto_refresh_state | UI0x10f2f7df8开3/关4；update0x113ceea74写缓存并uploadConfig；getter0x113cee9d8值<=1退1；builder0x101a33808读取 | 4与明确关闭相容，不是未知意义的任意值；不能把初始1和再开3合一 |
| inline_sound_cold_state | setter0x113cee934保存inlineVolumeOn/hasHandledVolumeSetting两个Bool；getter0x113cee8ac按未处理+开/关→1/2、已处理+开/关→3/4；builder0x101a33680读取 | 4与已处理设置后关闭相容，不等于初始关闭2 |
| inline_sound | builder0x101a33574读singleton.mutePlay：true→1；false且AVAudioSession.outputVolume>0→2，否则3 | 1与运行静音相容；不能把cold_state直接复制过来。singleton仅初始化从持久偏好反转；首页volumeDidClick0x113a99fdc在token有效时写音量并setMutePlay，不写cold两项，因此两者不是逐次同步 |
| autoplay_card | UI0x113ced494选择all10/WiFi3/off4；currentInlineSetting0x113ced790读autoPlay.double_p及doubleAffectedByServerSide，可生成0/1/2/3/4/10/11；Swift getter0x1035ab340、映射0x101a482b8、builder0x101a32e38最终保留合法码，非法兜底11 | 4与显式关闭、解除服务端影响相容；采集见2不代表普遍关闭或固定值；不能仅以Bool编码4/10 |
| inline_danmu | builder0x101a33764读inlinePlayerDanmakuSwitch，true→2、false→1；defaultConfig0x1147e5398内建true；active内联服务0x114203fe8可持久写入并同步，服务器配置0x1147e7ad8也可覆盖；对象nil省略 | 2对应旧包开启/缺存值默认，Neo没有首页内联播放/弹幕功能，适用状态及新版仍需核对 |
| voice_balance | UI switchType37→0x10f31b8bc→setEnableLoudNorm0x1147f0704写PlayConfig.volumeBalance并uploadConfig；getter0x1147f062c缺值用内建默认true（0x1147eecd8）；builder0x101a338f8读true→1/false→0，nil不加 | 0只相容显式关闭，旧包默认为1；通用持久化见下文，上层账号同步仍待闭合 |
| column | getter0x113ceddec按登录读Mid、否则Device；设备底层单/双列+serverflag映射1/3或2/4；UI只接受3/4；Swift0x101a326f0保留合法0..4 | 4对应显式双列且无server影响，不等于直接填写显示列数2 |
| video_mode | UI0x10f2f3b04将item.type写value，选择0x10f2f5c98加10；manual0x113ced0b4仅11/12，登录写MidConfig.playMode并upload，所有状态写本地kBBListPlayTypeKey；getter按登录读Mid缺省0，否则读设备非零值/缺省-1；builder0x101a339a0直接Int.description | 固定1不能称“用户明确选择11”；fetchVideoModeSettings0x113cecbf4允许1/11同UI样式、2/12同样式，但字段保留来源码，不能据此推断服务器1/11语义完全等价 |
| recsys_mode | 设置0x10f2f5614→updateFeedMode0x113cee678将关注input1写DeviceConfig.mode=2、其他推荐写1，再upload/通知；getter0x113cee5c0仅底层2为关注，builder0x101a32d8c编码关注1/推荐0 | 固定0与选择推荐模式相容；选中态来自CURRENT本地getter，配置缺失/失败可input0重置；标题/上层账号边界仍待闭合，通用配置落盘见下文 |
| disable_rcmd（公共项） | UI personalizedRcmdSwitchAction0x10f2f1fb8要求permission_url.rcmd_info存在；disabled时直接写false，开启时仅确认handler0x10f2f2384写true（主文档已统一为与工作表一致的地址）；默认false，本地BFCPreferences持久。公共producer0x10aac566c每次读native0x1000b3e08，false/nil→0、true→1 | Neo首页固定0与保持个性化推荐开启相容，未实现用户开关；旧包是进程共享持久项，不证明无其他账号同步/覆盖 |
| client_attr（preload） | UI switchType50→0x10f31bb90；setter0x1147f0adc仅player.priority_hdr_842实验命中且值变化才写CloudPlayConfig/upload，缺字段默认false。preload0x1143981fc要求实验、偏好开启、有效VIP全部成立才1 | 固定1不是通用HDR设备能力；设置打开也不保证1，账号权益/实验/首建缓存均影响 |
| qn_policy（preload） | QualityHelper0x114820fc4读持久autoQnEnabled，默认true；updateUserQn:isAuto0x11453b144先经_switch.needUpdate门控，再只有isAuto或手动shouldMemoryQn通过才保存原isAuto。preload0x1143980b8映射1/0；UI自动项明确赋isAutoSwitch=true，delegate/默认proxy及保存门控分流 | 固定1相容默认自动偏好，不能直接等同当前实际清晰度；手动选择经needUpdate与shouldMemoryQn两道保存门控后为0，未保存的选择不必改变偏好。不同业务proxy与账号配置覆盖仍待闭合 |
| player_net（preload） | helper0x114a0c368–0x114a0c430每次重写网络项，WiFi1/WWAN2/不可达3；底层status异步初始化为0，新API首建读取、同APIparams缓存 | 固定1仅与WiFi相容；“其他reachable→0”可能来自独立读取交错，不能称稳定第四网络类型。另有network按单次status生成wifi/mobile/空串，Neo未消费此来源 |
| https_url_req | UI type10→0x10f31bb80保存本地httpsPlayurlEnabled，默认false；builder0x101a33398–0x101a33424在preload合并后读0/1，nil省键 | 固定0相容默认/关闭，用户打开可为1；服务器/账号其他写入仍待核对 |
| guidance | BBPhonePegasusConfig本地两Bool默认false；builder0x101a33464–0x101a33548生成!(hasShownGuideTapCard && hasShownGuideLodeMore) | 固定1相容任一未展示或缺存值；两项都true才0，UI写入/清理与账号边界尚未闭合 |
| teenagers_age（公共项） | 设置成功0x1159777d0及状态同步写Manager/账号Prefs.age；SignHelper0x11609cac4–0x11609cb00每次读age转字符串，无16常量；无存值且无先行写入时getter退0 | 固定16缺生成依据；选择器defaultIndex16对应年龄17，不能当年龄16。同步失败也可能写0；账号suite once重建/覆盖及9.13语义待验，不猜用户年龄 |
| widgets / red_point（当前省略） | WidgetCenter成功按kind原顺序逗号拼接，nil省略/成功零组件空串/失败保留旧值；red_point读启动通知来源、bootBadge与首次成功消费标记 | widgets不等于player_widget；red_point不是实时角标。Neo未实现对应启动业务，不为了补字段虚构组件/推送状态；时机和重置仍待核对 |



设置操作到刷新也有独立编码层：RefreshHelper订阅Column/VideoMode的ByUserAction
（0x101b65644/0x101b65718），只消费3/4或11/12。0x101b647e0在pegasusIsShow=true
时返回；false且mode_switch_refresh_exp==2才即时派发，否则保存flag，不能按名称猜其
可见性语义。VM0x101a4893c接内部reason，builder0x101a32cb0经表0x1182c9138生成wire
flush：布局reason3→2、播放样式reason14→17。延后video flag另经VM0x101a4fa88、
collectionView offset(0,-60)、0.3秒beginHeaderRefresh和注册action回到同VM，受
view/loading/UI条件限制。通知不是无条件请求；Neo没有对应样式/布局设置入口，当前
isLayoutChange仅支持已知flush2，不应为“补齐所有flush”额外制造刷新。
推荐模式另有三层值及独立consumer：选中态按CURRENT isFollowFeedMode与option.value
计算，服务端option保持原序，不直接写selected。raw26配置缺失/转换失败在本地关注
状态时updateFeedMode(0)并隐藏选项；它与物理取消input2不同。通知带原setter input，
不等偏好upload成功；raw27刷新consumer只接受EXACT input1，取消2或fallback0
不走这条刷新。显示/实验/延后flag及VM loading门禁仍可阻止发送；准入后reason5
映射flush4，recsys_mode另读当前状态。Neo固定推荐0且无对应模式设置/配置消费，
不存在该监听；不能把所有模式变化概括为立即刷新或为补齐码值制造操作。
播放模式引导是独立条件性UI：8.89 attach后记录show，再排showTimeSec（无正值
默认5秒）延迟dismiss；block强捕获manager，执行时移除CURRENT view，未比原
view/model/token/generation。实际旧timer是否关闭新引导未运行验证。Neo无该引导
及对应timer/show，固定guidance字段也不是此show回执；不建议为日志相似新增引导。
未来如需实现应按引导实例取消/代际校验，不能照搬迟到timer的所有权缺口。

Swift MainApi.params0x101a32340首次构造后缓存字典，self+0x18非nil直接返回；
getApiOptions0x101a3204c用该缓存。MainVM新refresh/loadmore会建新Api；同实例复读不重新
读取音量/设置。builder0x101a32f10→merge0x101a34414用preloadUrlParams覆盖此前
生成的同名业务值；335xx–339xx声音、自动刷新、弹幕、均衡、video_mode显式赋值发生在
该merge之后，可再次覆盖同名键。必须同时记录来源和最终覆盖顺序，不能把预加载覆盖
推广成所有字段的最后赢家；完整公共层覆盖仍待闭合。


设置上传的公共下层也已部分闭合：8.89 Pegasus/CloudPlay等wrapper.uploadConfig尾调
BBCDeviceConfig.setUniversalConfig:typeUrl0x114fab274，先写内存/待上传diff并标记
blocked类型；merge0x114faac50在远端拉取时保留这些本地修改类型。
cleanUniversalConfigCache0x114fa93a0只清blocked标记，不清配置/diff/磁盘，不能把它
解释为登录切换清空偏好。0x114fa9eb8按generation和1秒debounce同步，helper
0x114faa7e4等待20秒却不处理wait结果；仅非nil响应且nil error清diff，非nil error
安排重试，单纯等待超时不自行重试。持久化0x114fa95b4的DeviceConfig路径此层
没有MID，写入通知不证明磁盘成功；上层账号迁移、迟到响应/排队身份仍待闭合。
Neo目前没有这些设置模型/同步业务；若统一升级R01，应先设计自己的偏好所有权、
覆盖与失败状态，不能因官方wrapper名带Mid就宣称天然账号隔离，也不要复制其超时
处理缺口。该偏好上传不是R06设备指纹登记，不能用于补齐登记状态。
Neo每次业务请求组装一次参数，HTTPTransport重试复用URLRequest，与
“同次重试不重新取设置”方向相容，但目前没有实际动态设置快照。

**判定**：刷新标记有9.13样本依据；4/4/1/4等与已选择的关闭/静音场景相容，不能将
它们全部判为错误。可生成更多状态与“固定值即官方常量”的说法有差异；Neo有意不实现
对应首页功能时，也不必为复刻所有编码而新增功能。video_mode=1与旧包显式选择请求11
有来源码差异，但不能因同UI样式的1/11关系而直接判定当前9.13策略错误或完全等价。
9.13每项最终规则仍未验收，现值是
已决定的对照策略，不能以本项为由立即升级。

**建议/接入**：在 AppRecommendationProtocol 输入显式功能/设置/能力快照；状态由
AppRecommendationSession 或对应设置 store 拥有。当前也不生成network、interest/interest_v2、
device_type、screen_window_type等旧包条件字段；仅在自身存在相应功能/真实状态且新版适用
依据明确时接入，缺少兴趣选择/广告/开屏功能不构造虚假状态。先建立“操作→getter→调用者→最终
请求”证据表，再替换对应固定值；没有首页内联播放功能时不能报告虚构预览状态。
**验证/依赖**：等待 S1 设置专项，分别验证初始、刷新、分页、布局、登录切换和网络变化；
验证内部trigger/reason与wire flush的独立映射和通知/延后条件，再做经授权的同账号
单变量采集。**可能影响**：改变候选/能力/实验上下文，
未证明这些常量造成个性化不足。

### R02 播放能力和画质不能由一个首页常量代表（P1）

**证据**：8.89 `supportFnval` 0x114a0be60 按 UHD/EAC3/HDR/DV/AV1/HEVC/H266 能力
及实验组合；`preloadUrlDeviceParams` 0x114a0c21c 将 player_net、fourk、force_host
关联网络/能力/HTTPS 设置。`preferredQnForResolver` 0x11482101c 在自动画质下取32，
否则取设置并经过登录态限制；client_attr 还依赖 HDR 实验、偏好及 VIP。

**NeoBili 实际行为**：AppRecommendationProtocol 固定 fnval=84948、qn=32、fourk=1、
force_host=0、soft_fnval=2、client_attr=1。
[AppRecommendationPlaybackCapabilities](../NeoBili/Core/Networking/AppRecommendationDisplay.swift)
虽命名为播放能力，当前2448实际仅被LiveAPI直播推荐请求消费。普通视频实际取流
[BiliAPI.playURL](../NeoBili/Core/Networking/BiliAPI+Playback.swift)走网页WBI，默认qn127、
fnval4048→16→1兼容路径；不能按ARCHITECTURE的“播放器2448”描述推断真实请求。
首页84948、相关页PlayerArgs84948、直播推荐2448、普通视频网页取流分别核查；
这些请求声明都不证明HDR渲染正确。
8.89 VKSettingVC renderer→adapter→delegate/dataSource绑定及reload/layout调用已闭合，
render仍要求view.window非nil，不等实际UIKit回调或呈现完成。STQuality点击在mainVC/
service门禁后先报incoming qn，再authSelect登录/VIP/trial，日志不是切换成功ACK。
Neo PlayerGlassChrome的qualityMenu调用PlayerControlsOverlay→selectQuality，先检查
停止/加载/取源/切换状态，再选实际已有stream或重新取流；选择后的quality及真实播放
报告与卡片点击分别拥有。静态UI接线不验收HDR、权限或解码，也不能据旧包日志新增
伪画质操作。

**判定**：与8.89能力/设置生成链有差异；首页 getPlayerParams 的选键层与9.13兼容性
仍待确认。**建议/接入**：由能力服务生成声明，再通过 AppRecommendationProtocol
选择已确认字段，播放器声明独立验收；未知位保留待研究，不能按名称推断可播放。
**验证/依赖**：复用能力组合离线证据，加自身能力/设置边界测试；HDR、权限及硬解需要
明确授权的专项。**可能影响**：影响返回媒体形式与预览准备，尚不能推断兴趣排序变化。

### R03 屏幕附加内容有已证实结构差异（P2）

**证据**：8.89 `extraContent` 0x1143982d8 以 screenHeight/screenWidth 分别写
long_edge/short_edge，另写 translateLanguage→cur_language；函数本身不排序边长。
**NeoBili 实际行为**：[AppRecommendationDisplay](../NeoBili/Core/Networking/AppRecommendationDisplay.swift)
读取当前 scene 的 screen.nativeBounds，按 min/max 排序、向下取整，JSON 只含两个边长。
**判定**：与该函数有差异；上游屏幕 getter 单位/方向及9.13行为尚不能确认，不能仅凭
旧函数把 nativeBounds 改成 points。**建议/接入**：先核对实际屏幕 getter 与翻译设置，
再让 AppRecommendationDisplay 编码已确认信息。**验证/依赖**：横竖屏、外接屏、语言
与屏幕 scale 的离线快照及官方单变量样本。**可能影响**：布局/语言上下文，推荐因果未证。

### R04 登录事件、启动消费和横幅失效不是同一生命周期（P1）

**证据**：8.89 MainVM.init 0x10df58690 按登录/访客设 login_event=2/1，登录/退出
观察者重设，成功回调0x10df59104清零。helper.open_event 0x10df57b60 的 getter 消费
cold/hot；后台间隔严格超过1800秒时清 banner_hash（0x10df579ec 后续方法链，完整
注册时机未闭合）。重试复用 loadDataOptions，不再次消费 getter。

**NeoBili 实际行为**：[AppRecommendationSession](../NeoBili/Core/Networking/AppRecommendationSession.swift)
从cold开始，scene background→active设置hot，takeRequest立即清 openEvent；缺已登录
账号的App凭据时 BiliAPI 在 takeRequest 前拒绝。横幅在解析过滤前取首个 banner_item
hash；recordBanner只接受当前store epoch且缓存为空。登录/退出不直接通知此store，
仅下次takeRequest察觉accountSession变化时清缓存/更新epoch；recordBanner不额外核
DeviceIdentity当前代际，因此新请求尚未开始时旧响应仍可暂写旧epoch，随后新请求会清。
普通长后台不清。
login_event始终0；getApp重试复用编码请求，耗掉open_event后整体失败仍不会恢复它。

**判定**：消费型启动标记与重试复用原则一致；登录映射和长后台横幅失效与8.89有差异。
**建议/接入**：在 AppRecommendationSession 独立保存登录事件与横幅有效期，等9.13及
通知链闭合再应用；明确失败是消费还是恢复，避免诊断读取提前消费。**验证/依赖**：
假时钟、同账号重登、换号但新推荐尚未请求时的旧响应、缺凭据、短/长后台与传输失败；现有 RecommendationPolicyTests
覆盖当前策略，不证明官方策略。**可能影响**：新登录/热启动上下文与候选刷新，效果未证。

### R05 自身 BUVID 生成与官方跟踪编号不同（P0）

**证据**：8.89 `BFCBuvid.buvid` 0x1167cbe68 先读Preferences/Keychain，失败后用
IDFA或IDFV去连字符，生成 Z/Y +主体第2/12/22字符+32字符主体。既有样本的36字符
Y/Z值符合这个结构；不是带连字符UUID，也不能由重复条目数量推算独立设备数。

**NeoBili 实际行为**：[DeviceIdentity.appBuvid](../NeoBili/Core/Networking/DeviceIdentity.swift)
从defaults复用，缺失时MD5随机UUID生成小写32字符主体，加 `XY`+三字符，结果37字符；
没有App BUVID的Keychain回退。Debug允许既有独立实验覆盖，Regression不取覆盖。
换登录不重新生成BUVID；请求、短信local_id及日志共用该值。

**判定**：共用/持久复用方向一致，生成输入、前缀、长度、存储边界与8.89有差异。
既有buvid单字段对照是线索，不能区分设备画像、实验和登记/风控。
**建议/接入**：由 DeviceIdentity 管自身跟踪编号与迁移，先决定如何保留已有用户设备
连续性；不要升级时每次新建、复制官方编号或用本地64字符指纹替代它。
**验证/依赖**：伪IDFA/IDFV、缺值、存储损坏、重装/重登与升级复用；新生成规则的服务端
兼容按已授权的本地对照另行验证，不能由读取成功推断登记或生命周期完整。**可能影响**：身份连续性和分组，当前最强线索但不是唯一根因证明。

### R06 指纹、访客、登录资料需要保存各自真实结果（P0）

**证据**：8.89 BFCDeviceToken.localBUVID 0x115fd6c80生成64字符本地指纹；
requestUpdateBuvidWithData 0x115fd7ed0 的Protobuf经AES-128-ECB/PKCS#7，再以包内
RSA包装随机key的hex UTF-8，返回data.bili_deviceId。currentBUVID优先服务器值。
Guest.load 0x11605a5a0只在0/-2登记，setup及DidBecomeActive调用；失败可在后续active再试，
不是每次前台无条件登记。serverBUVID getter有120秒节流，非空成功延至请求发起时+86400秒，
失败保留旧值；expiry为内存状态。GuestInfo 0x11605a924 是独立JSON→CBC/key=IV；登录DeviceToken 0x116058af4又是另一份
JSON。SMS 0x116048e54将跟踪BUVID→buvid/local_id、本地指纹→bili_local_id、当前指纹→
device_id、guest响应→device_tourist_id。既有日志2.14/gRPC Device14与响应指纹相等。

**NeoBili 实际行为**：DeviceIdentity没有上述登记状态；
[SMSPassport.prepare/baseParameters](../NeoBili/Core/Networking/SMSPassport.swift)
将deviceID设空，只共用自身buvid/local_id，不发bili_local_id/device_meta/dt或游客登记结果。
AppDeviceSnapshot不带登记指纹；AppBehaviorEncoder不写bilifp。

**判定**：已证实缺实现，短信成功/设备管理出现条目不证明完整登记或推荐关联。
**建议/接入**：DeviceIdentity分别保存本地指纹、服务端指纹、访客资料及响应和首次运行
时间；AppDeviceProtocol编码快照，领域登记API显式声明认证与写请求重试；SMSPassport、
日志及gRPC复用同一真实结果。取得8.89生成依据后仍要核清54项资料的实际赋值/缺省值、
RSA路径与9.13兼容；不能以格式合法值冒充服务端登记成功，也不能复制Android资料。
**验证/依赖**：假资料加密向量/边界、无IDFA时省略行为、首次时间持久化、并发getter、
失败保留旧值及账号隔离；自身登记的服务器验收与兴趣验收分开。**可能影响**：设备与
账号/行为关联，是后续日志完整化依赖，尚未证明缺失即导致个性化失败。

### R07 ticket 是独立服务且有启用边界（P1，依赖R06）

**证据**：8.89 BFCTicket.onTicketReq 0x100096170返回旧值并异步刷新，默认提前量
1800秒；x-ticket-status=1触发更新。GetTicket签名0x100096d40组合Device metadata与
排序context，HMAC输出32bytes。回调按回调时间+ttl保存，失败保留旧值。Ktor安装ticker
并不证明Enable GInterceptor的全部上游开启，不能推导所有HTTP必带ticket。
**NeoBili 实际行为**：AppDeviceProtocol不加ticket，AppRequest没有Ticket RPC，
DeviceIdentity无票据缓存/续期；当前只读gRPC入口会重试，不能直接复用为登记/票据写通道。
新增三次feed/index实测中无ticket组也返回200/code0，带捕获ticket组同样成功；
这只限定本次国际版参数组合的返回能力，不证明票据有效或被校验，见实验边界。
**判定**：获取和续期缺实现；当前适用请求范围与实验仍待确认。
**建议/接入**：独立票据状态和异步单任务刷新接 DeviceIdentity/领域服务，再通过
AppRequestContext/AppRequestEncoding只给证实的通道注入，HTTPTransport保留状态响应。
**验证/依赖**：假时钟/并发/旧值返回/失败保留/ttl边界、响应状态与scope；先完成metadata
来源，不把GenWebTicket或捕获票据代替App票据。**可能影响**：身份/路由/风控，已有单字段
实验未见稳定推荐改善，不据此认定无作用。

### R08 卡片追踪到观看关联已接通，但曝光上下文不完整（P0/P1）

**证据**：9.13已有样本按原始param/track_id关联首页卡片、点击与观看；8.89专用点击
直接取model.track_id，不能套HD args fallback。
**NeoBili 实际行为**：AppRecommendationCard把根track_id/report_flow_data写PlaybackEntry，
BiliAPI给返回卡绑定登录session；HomeFeedCellView实际Button先record再传route；
NowPlayingStore创建PlayerViewModel时保留entry；makeWatchReport按绑定登录session生成
sourceFields；AppWatchProtocol合入后 BiliAPI添加aid/cid/mid/session/sessionID。
PlaybackEntry.parameters会在账号变更后丢旧追踪值，但仍保留入口from/from_spmid。
makeWatchReport另填实际已选quality；surface为page时写详情spmid，mini时不写该spmid。
点击record异步执行，路由不等待上传成功。NowPlaying打开route后仍须详情/cid及
自动/手动播放准入才能建播放器；物理卡点击不能当首帧、有效观看或播放成功。
独立Story按钮也有相同证据边界：8.89先track story-button，再检查route及播放/共享/
队列准入；valid图片URL会先取消hidden，不等图片加载回执。Neo无该Story入口，不能
把按钮可见/点击替代导航成功，也不将Story日志当首页卡片点击协议或推荐必要条件。
**判定**：真实入口和同代际传播一致；解析没有保存原始批次位置、extra_rpt_fields、
rcmd_reason_style等曝光上下文。**建议/接入**：AppRecommendationPage解码后单独保存
不可变卡片报告上下文，经VideoSummary/路由传递；曝光身份不能只用bvid。
**验证/依赖**：同视频不同批次、旧账号卡片、刷新合并、相关入口及预取不触发；
RecommendationAlignmentTests已有追踪隔离断言，本次未执行。
**可能影响**：建立推荐→选择→观看关联；传播成功不证明服务端按其更新兴趣。

### R09 点击字段不能直接套某套通用模板（P1）

**证据**：8.89 SmallCoverV2专用reporter 0x101a974c0初始22字段**没有position**，
直接取model.track_id，OptionalString关系/素材编号；extra_rpt_fields/additionalDic可覆盖。
HD HomeData 0x10df30fd8另有position和track_id fallback。两条链不可混用。
**NeoBili 实际行为**：AppRecommendationCard只抽取部分根字段及args.tid/rid，不解析
extra_rpt_fields；RecommendationClick.make要求track非空、来源/账号一致，将event=card_click、
event_policy=0、page_from=1合入，字段限制40项/单值4096bytes。缺track卡不发送；仅普通视频
卡发送，直播/图文不发；没有虚构内联播放状态。
**判定**：actual Button与policy=0一致；字段来源、缺省和附加字典合并不完整。
**建议/接入**：确认Neo展示的具体card_type对应官方reporter，再由AppRecommendationPage
保留原字段、AppBehaviorEncoder按类型编码。不要为所有click补position或把HD规则
当Swift规则。**验证/依赖**：脱敏不同卡型golden、空/缺track、字符串编号、嵌套覆盖与
超限处理。**可能影响**：点击归因/特征完整性，字段补齐的推荐效果未证。

### R10 展示及每段可见时长仍缺采集和发送（P1，依赖R08/R11）

**证据**：9.13已有show/duration事件走realtime、policy=1；8.89 RealExposure/ExposureV2
0x103eb9998、0x101b6cf80以可见比例阈值和minimum结算，写card_start_time/card_end_time
Unix毫秒。后台/终止会结算；默认start/end各0.8、minimum默认0秒，但可远程覆盖，普通show
阈值与duration不同。VC0x101a37618/0x101a37628的出现/离开经VM.isShowing与
splashStyle==0生成真实出现/离开；raw8回调0x101b60644移除duration contexts并
结算，返回重新建段。raw36/inactive受配置控制，raw33/background与raw37/terminate
直接结算且仍受minimum门槛；普通show去重池是否重置未闭合。
**NeoBili 实际行为**：[HomeFeedCollection](../NeoBili/Features/Home/HomeFeedCollection.swift)
willDisplay/didEndDisplaying只管理预取/动画/分页；没有可见时段上下文和上报。
AppRequest只有unrealtimeLog，AppBehaviorEncoder只有click。HomeView接收isSelected
但没有消费/传给列表；onAppear只恢复方向锁，didMoveToWindow只登记滚动视图。
标签渐入及首页刷新会改变真实透明度，cell存在和willDisplay不能证明当时可见。
**判定**：已证实缺实现，不能用点击或取流请求替代展示。
**建议/接入**：列表采集器先综合选中标签、scene状态、详情/全屏遮盖、挂载与实际
透明度形成真实显示门禁，再维护可见卡片逐段起止；真实离开/遮挡/刷新/后台结算。
点击只有造成实际离开/覆盖才结束时段，被拦截或未成功导航的点击不制造结束；
show去重与duration多段分开，独立事件/队列接AppBehaviorEncoder和realtime通道。采用自身
可见规则时明确属于客户端选择，不能把8.89默认阈值声称为9.13实测。
**验证/依赖**：假时钟与面积、边界相等、滑回、首页→详情→返回、标签切换、透明刷新、
遮盖首页、换账号及预取；同次离开/inactive/background只结算一次，duration重建不
等于show必然重发；兴趣子对象去重另见R24，不作为普通首页show去重证据；
再验封装、服务器接受和观看后推荐，三者分开。**可能影响**：缺少未点击/停留信号，
可能改变反馈覆盖，但没有曝光缺失造成推荐不足的因果实验。

### R11 position 必须保存来源，不能一律按UI行号生成（P0，阻挡曝光定稿）

**证据**：8.89 HD回调0x10df59978按原始单批输入下标+1，过滤项占位；Swift
DataFactory 0x101a3e1dc→0x101a4340c先compactMap为CardData，再0x101a3e5a4从1编号，
无report model的成功项仍占号。未识别card_type返回41是哨兵，不是有效枚举case；合法unknown
为0。SmallCoverV2 duration builder0x101a7b6a0直接模型Optional值（含0），fallback才
flushIndex+1。Optional值来自associated object BBListPegasusSettings_flushIndex，不是已证明直接
解码的服务器位置。普通show、专用click分别有自己的规则。网络普通refresh和loadmore
都按成功CardData从1编号；兴趣选择render是独立分支。缓存恢复也经普通render、
compactMap再从1编号；replumeFlushIndex目前只证实BannerV8替换调用，不能泛化。
9.13可匹配样本的show=原下标+1、
duration=原下标+2是观测关系，不证明完整跨卡型算法。
HD2 getCurrentTimestamp0x10df9166c为NSDate epoch秒向零转Int64的String，刷新/分页
解析各卡分别取值，banner复制父值；同秒卡可同timestamp。report_flush_idx仍是单次
输入ordinal+1，保留旧卡保留其旧字段。timestamp不是唯一请求代际；完整标识还依赖
track/ordinal/App状态，静态精度不等于已观察到运行时碰撞。

**NeoBili 实际行为**：AppRecommendationPage循环原items时只保留有效cursor/banner，
随后try解码并丢失败卡；卡片不保存批次/原下标/官方模型编号。本地过滤与bvid去重后
无法恢复这些信息，也不能重建官方Swift支持卡片集合。HomeViewModel使用独立UUID
loadID、取消状态与账号session保护响应/游标回写，不拿网络ts或卡时间作请求代次；
AppRequestEncoder签名ts为请求时间，与卡报告timestamp分开。
**判定**：信息丢失已证实，9.13编号选择机制尚不能确认。
**建议/接入**：在解析时保留原始batch/下标与卡型证据，报告上下文区分原下标、转换后
编号、服务器显式值和事件fallback；卡报告时间另存来源/单位，不能替代本地请求
及账号代际。未闭合路径不填伪值。勿直接照旧NOTSURE建议统一+1/+2。
**验证/依赖**：前置坏卡、广告、无report但有效CardData、分页重置、重编号/替换、Optional0；
增加缓存恢复、有效JSON但空datas与兴趣选择分支；需S1闭合9.13映射、
支持卡型集合与重编号适用范围。**可能影响**：曝光/点击归因位置，因果未证。

**兴趣分支边界补充**：8.89确认可恢复tmp卡片后重新compactMap编号，或清空后尝试
刷新；T10不带disable_refresh_after_submit，缺省走后者。T10 skip缺sids，不更新
选择marker，T37 more有sids，不能概括为统一skip/恢复流程；接口和回执另见R24。

### R12 日志公共字段与事件缓存策略有明确差异（P1）

**证据**：8.89 Neuron0x1161ea030在trackQueue编码时读取公共信息、递增sn；描述符
有osver/fts/bilifp、network/logver、eventCategory/pageType/sn等。fts来自首次Neuron初始化
的持久毫秒值，不是设备firstRunTime。失败0x1161ec850更新retrySendCount，保留原事件；
发送刷新uploadTime，加Neuron-Events。HTTP200即删缓存，此层不解析body。9.13重启补发样本
显示原事件会话与当前上传会话可不同，不能按上传时间给动作重标。

**NeoBili 实际行为**：AppBehaviorEncoder写固定appId/platform、buvid/deviceId、model/
version/build/session和空Click子消息；未知osver/fts/bilifp及分类/序号/pageType等缺省。
RecommendationClickReporter在异步record取得设备快照，保留调用时session/time，持久队列
100条/24小时，按mid/accountEpoch隔离；只连接未建立的指定错误保留，超时/HTTP拒绝丢弃。
重启保留原事件快照，上传使用当前头；编码不写retrySendCount，请求不加Neuron-Events。
flush只由新点击和App首页请求触发；网络恢复/前台/重启本身没有独立补发调度，
非保留型失败删除当前事件并退出，其余事件等下一次触发。点击允许访客，登录/退出
轮换持久accountEpoch，单纯更新accessKey不轮换；不是允许同账号重登后补旧事件。
APIClient接受HTTP200–299并检查可解析响应的code，区别于旧Neuron仅HTTP200删除。
AppBehaviorEncoder的日志version/build使用AppClientIdentity的9.13协议身份；8.89初始化实际
取mainBundle版本，字段名字不能证明二者同义，Neo自身发布版本与兼容身份需分开设计。

**判定**：包装和旧事件/新上传会话方向一致；公共字段、采样/批量/配额、回执与失败策略
有差异。Neo的快照/保守去重是自身选择，不是官方完整复刻。R21旧包foreground
可能用同一eid再次生成活动duration，是业务入口再提交，不能归为Neuron失败重传，
也不证明下游已去重；Neo点击补发与活动段缺口分别处理。
**建议/接入**：AppDeviceSnapshot扩充已证实的真实字段；AppBehaviorEncoder显式事件分类，
队列/调度另管sn、补发、配额及回执，持久化不存凭据。不要为求一致无条件复制旧包7天、
重试所有超时或采样实验默认值。**验证/依赖**：RecordIO/Protobuf字段golden、重启/同账号
重登、失败回执、上传时间与事件时间、伪网络配额；RecommendationBehaviorTests已有部分
封装和队列断言但未涵盖官方全策略。**可能影响**：日志可用性和重复/漏报，效果未证。

### R13 观看事实与历史位置已分开，触发/补全仍须逐项对照（P1）

**证据**：9.13已采集开始/结束、暂停/后台/历史入口；8.89Context0x114885bcc输出
累计计时和位置，MetaInfo0x114886d4c另含播放模式、网络、自动播放等属性；多数赋值方未闭合。
历史helper0x104a80fcc可将距结尾<=4秒的progress改-1，历史服务使用媒体位置而非观看累计。
8.89普通HeartBeatServiceV2后台入口0x11488b0b8还要求!isSuspend、已准备、有效且
未completed；reportPolicy bit2=0仅stash结束保护快照，bit2=1才playEnd。前台入口
0x11488af54在有效且未completed时清stash；无效且bit2=1才恢复tracker资料并尝试
开始。Inline可覆盖service默认policy，状态raw值尚未全部映射业务名称，不能断言
所有暂停都结束或所有后台都发finish/前台都发start；这些是8.89方法证据。

**NeoBili 实际行为**：[PlaybackWatchProgress](../NeoBili/Features/Player/PlaybackWatchProgress.swift)
及PlayerViewModel只认可真实推进；确认观看且aid>0才排全零start，
退出/完成且已排start才有finish。aid始终缺失则只有网页历史checkpoint，迟到aid可补排
start；普通App首页视频卡保证有效aid，该限制主要影响其他资料补全路径。历史
checkpoint不发mobile；AppWatchProtocol区分watched/paused/position/max，当前played_time与
actual_played_time同取watched。8.89 updatePlayedTime 0x114885674则将墙钟整数增量写
played_time，以单精度倍率加权增量写actual_played_time；Neo在非1倍速时仍相等，有明确差异，
但不能将8.89分段截断/负墙钟差照搬为真实观看定义。BiliAPI有App凭据且aid/cid有效时独立发mobile和history，
mobile失败仍尝试history；仅Cookie时非start退网页历史。未登录不发这些移动观看报告。
play_type=1、auto_play=0等固定，不应根据字段名当完整状态表达。
首次累计5秒、随后每15秒生成历史checkpoint；暂停/退出可提前结算短段，但位置整数秒
须>0且不同于上次，EOF还须末段真实推进并靠近片尾才标-1。
RootView/VideoPage进入非active只savePlaybackProgress到本地续播store，不显式排
checkpoint/finish；是否继续计时由后续播放事件决定，不能把本地保存称为后台报告，
也不能据此把后台实际音频观看一律停止计时。MPVMetalViewController的前后台入口
只切视频输出，没有观看保护快照、恢复或reportPolicy。账号session变化时RootView
关闭播放器，报告捕获原session；这与真实后台持续音频播放是两个不同条件。

独立Neuron PlayerEvent的毫秒进度与画质允许值另见R25，不能混入本项历史/mobile单位。

**判定**：核心真实累计/位置区分与已有样本方向一致；8.89更多字段、历史尾部规则、校时
和完整触发频率有差异/待确认。不能为模仿历史尾部规则把跳到结尾当真实播完。
**建议/接入**：计时继续由播放器拥有，分别保存墙钟观看和倍率加权播放事实，
待新版语义核对后由AppWatchProtocol编码；已证明的模式/网络/自动播放/会话差异也消费
事实快照；历史语义与推荐观看反馈分别处理，访客行为待证后另设计。先确认9.13与
具体入口policy，再定义后台保护快照、前台撤销/恢复，不能只因系统通知制造结束/开始；
mini展示状态不等于后台状态。
**验证/依赖**：暂停、缓冲、seek、续播、换源、后台、倍速、迷你播放器、分P、重新进入/
重播及迟到aid；增加后台持续音频/已暂停、后台EOF或被系统终止、短后台返回、
重复通知与页内→mini。现有Behavior/Alignment tests覆盖部分，本次未执行。
**可能影响**：观看归因与时间强度，真实API成功不能证明短期兴趣已更新。

### R14 过滤、去重和预加载会改变展示，不能被误算成服务端推荐（P1）

**证据**：8.89 buildObjects0x10df5a28c有本地合并、刷新卡和数量/偶数处理；Swift转卡
先过滤失败项。尚未证明客户端另做个性化重排。
**NeoBili 实际行为**：AppRecommendationCard拒广告/无args/坏卡/不支持goto等，视频需
can_play=1；AppRecommendationPage先取原items最后有效idx，再做owner/zone/时长/标题等
本地过滤；HomeViewModel按bvid去重，分页旧项优先，刷新新批优先并可保留旧数据；失败只设置错误并保留内存卡，
没有datas/config磁盘兜底或is_cache_local_data标记（见R20）。
空过滤批也推进cursor，重复/缺cursor停翻页。Portrait过滤另用显示列表；卡片预取走
VideoPreparationCache，预取默认关闭，开启后停留300ms才执行；已有cid时直接预取播放
清单/URL，缺cid时先查详情，不下载媒体，不发送RecommendationClick。

**判定**：自身游标/过滤解耦已实现；本地选择与旧官方合并不是同一算法。列表看到少量
兴趣内容，可能同时受本地过滤和保留旧批影响。Neo loading时拒绝重复手动刷新，
替换刷新取消旧任务，并用loadID、取消状态与登录session限制成功结果写回；这是自身
防串扰设计，不能因旧包回调缺比较而删除。
**建议/接入**：诊断分原响应、可解析卡、本地筛选、最终显示；新报告上下文不随UI
位置变化而覆盖，重复bvid保留正确批次追踪；不要为“像官方”无条件恢复广告或未知卡。
**验证/依赖**：广告末项游标、坏卡、全过滤、跨批重复、刷新失败、账号/来源切换、
预取取消，使用脱敏离线fixture。**可能影响**：改变用户实际能看/点的候选与归因，
不是服务器兴趣算法证据。

**广告边界补充**：8.89 UGC广告GET x/v2/dm/ad是独立路径，type/oid/aid之外的
ad_extra仅在共享广告配置avid匹配当前aid时加入非空track_id/ocpx_target_type；
下层受开关、允许键及class门禁，再JSON→AES-128-CBC/PKCS7→大写hex，
不是明文JSON透传；模式已由静态helper闭合，不记录包内密钥/IV常量。
旧callback弱取manager但未见request/aid/cid/account比较，cancel不证明迟到回执
安全。Neo首页过滤ad_及ad_info且无该UGC广告请求，不能据此制造广告归因或补假
曝光；广告加载、展示/点击与推荐因果尚未闭合，本项不建议新增广告实现。
Monitor另由reportType bit16路由独立Uploads POST conversion/mobile/v2，使用自身
queue/cache及HTTP2xx+业务code="0"判据；公共retryFailedEvents仅调UI/fee.ad/fee.mma，
未调Monitor，但Monitor继承Uploads单次成功后重试自身缓存、失败保存的机制。
不能将“未接公共重试”写成“没有重试”，也不由事件名字monitor推定该路由。
Monitor getter未装普通UI/fee.ad/MMA的completion/abandon反馈；这些队列不应接到
Neo推荐点击补发层。源码未见对应Monitor或广告发送器，不构成推荐必要项。
广告KntrAdTrack每次发送调用随机[0,100)，signed随机值<event阈值才放行普通技术
事件，再交原生policy2/rate100；native rate100不取消前置采样。阈值producer已进一步
闭合为enum一次初始化的data/action/report配置快照，String解析失败走fallback，
该body未clamp到0..100；配置真实值/默认值与动态更新范围仍未知。不是用户稳定
分桶，也不是一次随机后永久命中；这些门禁不能套到普通推荐点击或曝光。
广告Operation层每次fresh对象、无creative-ID去重，不代表端到端无去重：下游Own
hash无分隔拼request_id/src_id/creative_id/EVENT/filter_salt，MMA第四项改为URL，
不含EVENT；所以Own event0/15不同，MMA相同URL及其他输入可能跨event命中。
各自集合在API排队前记入，已读失败callback不撤销；contains与add仅各自加锁，
caller未跨两步锁，外层串行与清理范围仍待证。不能将该层标记当HTTP成功、并发
恰好一次或推荐曝光去重规则；延迟Operation取消也不能撤回先前立即event0。

### R15 不感兴趣上下文最小化且旧卡缺来源代际校验（P1）

**证据**：8.89 params0x10df563d8条件合入track_id、from_spmid、UP mid、rid/tid、
reason/feedback及广告字段；extraParams最后覆盖。此处mid来自args.up_id，不是登录mid。
**NeoBili 实际行为**：AppRecommendationCard只保留goto/param及three_point_v2理由；
BiliAPI.feedDislike按理由集合选择reason_id/feedback_id，用GET写操作、retries=0并校验登录
会话，不传上述卡片关联字段。但HomeViewModel.markUninterested/cancelUninterested取
操作时currentSessionID，FeedbackOptions不保存卡片来源代际，也不对比PlaybackEntry的
loginSessionID；换号刷新尚未完成/失败仍保留旧卡时，可用新账号发送旧卡反馈。
**判定**：理由/无重试写操作已实现；请求绑定的是操作时账号，不能称旧卡已完全隔离。
来源代际缺校验是实际缺口，额外协议字段与8.89有差异且9.13必需性未确认。
**建议/接入**：RecommendationFeedbackOptions保留已返回且语义证实的非广告上下文，
BiliAPI+Recommendation/AppRecommendationProtocol编码；优先把卡片来源代际带入反馈操作
并拒绝旧代际，不能只检查新请求的账号。不要把账号mid误填UP mid，
或给普通卡添加广告身份。**验证/依赖**：不同reasonType、撤销、旧卡/新账号、请求超时
及缺附加字段。**可能影响**：显式负反馈归因，当前最小请求成功不证明完整特征等价。

### R16 公共、登录、播放和启动会话要分别命名（P1）

**证据**：8.89公共session经BFCDevice.getSessionId 0x115fd3960/Kntr lazy复用，
以16随机字节的FNV-1a低32位转小写hex、不补零。Ktor GAppRequest consumer
0x10aac466c→0x10a9b285c实际写克隆请求HeadersBuilder.session_id，不是query；
该写入与公共设备头取同一进程lazy来源，最终hook启用/覆盖范围仍未闭合。短信UI
helper0x104cf8968对BUVID+
FRINTA毫秒取大写MD5，发送/重发/提交复用入口值；播放Context.setupSession0x1148859c8
setup阶段优先metaInfo.sessionID，否则createSessionID0x11487f6b8取BUVID+NSNumber
毫秒文本的MD5。但trackMetaInfo0x1148891e8先取tracker.playerSessionId，非空显式
session会写入原metaInfo再copy/setup，因此该入口优先tracker缓存，不能只归为业务字段。
tracker manager0x11487f53c为实例缓存，reset0x11487f5c8只清旧值、日志参数不作新值；
inherit0x11487f630非空时保存。普通非shared场景完成及playerDestroyed假→真可reset，
rebindSessionID与graft attach另有继承路径，重建对象不必意味着新session。
Neuron启动会话与这些编号分别解释；BFCActiveReport.sessionId0x115fcfe7c为进程
once值，活动段id/eid在foreground另调用bfc_uniqueString0x1167a5928生成，两个
角色不互换（见R21）。9.13短后台保留、进程重启更新的样本不证明生成算法。

**NeoBili 实际行为**：DeviceIdentity公共session是补零8位随机hex，AppDeviceProtocol同样把session_id写请求头，进程创建、保存登录
和退出时更新；startSession另建8位随机hex且后台保留。SMSPassport.Context将登录尝试设
小写UUID32，在同次尝试复用；PlayerViewModel默认独立小写UUID32且可注入playbackSession，
BiliAPI+History最终同时写session/sessionID；重播/重新进入重建、暂停续播保留。视频页另有AppRelatedPage页面session，不能互换。AppRecommendationSession只管
cold/hot、banner与账号epoch，没有App活动进程session或活动段eid；不能拿openEvent
或账号epoch补成这些活动身份。当前无旧包式tracker reset/inherit/graft所有权链；
初始化可注入值不等于已实现跨容器继承协议。
**判定**：编号生命周期的部分采集关系一致，生成算法与8.89有差异；Neo换登录时刷新公共
session是隔离策略，未证明官方全生命周期相同。
**建议/接入**：DeviceIdentity、SMSPassport与PlayerViewModel各自拥有会话事实，
AppDeviceProtocol/AppWatchProtocol只编码。若采用官方算法先确认上游实际复用/舍入规则；
无需复刻旧非安全随机种子，不能为格式一致偷用官方现成会话。
**验证/依赖**：假时钟/随机源、同毫秒、登录重发、重启、同账号重登与长后台；单独核对
session和sessionID的meta赋值是否始终相等；补reset参数不作新session、
inherit空值/不同context、graft迁移、销毁及shared场景条件。**可能影响**：事件分段与关联，格式差异是否
影响兴趣未证，优先保证自身语义连续。

### R17 观看结束报告没有官方旧包的持久补发层（P1）

**证据**：8.89 ReportManager.reportWith0x114887940有内存/文件缓存分支，stash保留
结束快照，loadFileCache可合入重发；reportTrigger0x114888230串行发送，失败再等5/10秒
最多重试两次。postApiWith0x1148888b0发送前去hash/isStart、补当前idfv/idfa等；回执含
HTTP200 error分支。恢复caller已闭合：BBPlayerCoreModule.onModuleInitializedConfig
0x1147ddd4c取sharedManager并loadFileCache，位于后续hasLogined检查之前；不证明
未登录旧报告必能发出。模块初始化实际送达、reachability、缓存异常恢复/过期、跨账号
策略与9.13同链仍未确认。回执ts另见R22。
**NeoBili 实际行为**：PlaybackWatchReportSender只在内存排队，按账号/视频/分P串行，
相邻同播放session的checkpoint合并，start/finish不合并；PlayerViewModel默认sender调用
reportAppWatch使用try?，发送前移出pending，失败不恢复队列，APIClient.postApp为零重试；
没有文件加载或后台stash。未生成finish即被终止也可能失去末段事实，不只是发送失败。
播放器捕获登录session，每次发送检查expectedSessionID，RootView换session会关闭播放器；
旧队列不会取得新账号凭据，但已发请求无法撤回，发送前检查也不是迟到回执保护。
**判定**：串行/边界保留方向一致；进程退出或网络失败的结束报告可能丢失，与8.89存在
持久性差异。不能把旧包重试次数或HTTP200错误接受条件直接当安全生产要求。
**建议/接入**：在播放报告发送层设计不含凭据的持久快照、账号代际/过期、进程恢复和
可判定失败补发；分开保存当前播放保护快照、已排队报告与恢复资格，前台继续同一
播放时撤销保护快照，避免stash被当成已结束再发送。与点击队列共享基础设施但不混用
事件语义。进程内session UUID不能原样作为重启恢复资格，需持久账号代际/过期政策；
mobile与history分别记回执，重放整个组合可能重复已成功通道。模糊超时幂等性先确认。
**验证/依赖**：未连接、超时、请求已接收但响应丢失、强制终止、跨账号/同账号重登、
重播及快速退出、未生成finish的系统终止、前台撤销stash、凭据晚到、mobile成功/
history失败及反向部分成功；start/finish先后与历史独立通道保持。
**可能影响**：弱网下真实观看信号覆盖，暂无持久补发带来推荐改善的实验证据。

### R18 公共身份头、locale和网络资料需按通道补齐（P2，身份部分依赖R06）

**证据**：8.89 BFCApiSignHelper.baseParams0x11609c68c分公共platform/device/build/
locale/statistics，NetParamImp有GuestId/SessionId和个性化设置getter；原生callOptions helper0x115e070e4→0x115e06c20
复制缓存Metadata并刷新accessToken，构建fresh Device/Network，将三个PB.data写入
metadata-bin/device-bin/network-bin；extraHeader先合入，再由非空buvid/token/trace
覆盖对应头。Metadata缓存初始化0x115e0d0d4取客户端配置，不能混同fresh设备/网络。
Service初始化保存options，defaultAutoRPC仅复制，不能把helper每次取值说成每次RPC
都重读；KMoss/GrpcEngine的typed binary与flattened Base64路径、注册覆盖分别核对。
完整字段取值、引擎选择与transport覆盖仍未闭合。9.13已采集App/系统locale可能不同，locale附加5/8与network-bin
嵌套字段语义、地区头来源仍待确认。已有gRPC Device14与登记指纹关联不证明所有请求
应携带同一完整metadata包。
独立Ktor Locale RequestHook 0x10aae9400克隆请求，从KLocale序列化值写
x-bili-locale-bin，采用受Enable GInterceptor门禁；header setter仅write once显式
true且同名头已存在时保留，否则替换，空String无额外门禁。它不是已证Swift
MetadataStore adapter，也未证明普通首页采用同链，序列化byte变体仍待证。
KntrTranslation的userEnabled与alwaysTranslate分开：false开关或SYSTEM locale使
派生值false，否则按dd_localization_language_config的localeIdentifier exact匹配，
first wins，无配置/匹配为false；locale与开关变化均重算派生flow。user-enabled经
序列化property写NSUserDefaults的translation suite，此链不拼MID，不证明外部换号
清理或setter返回时已落盘；配置JSON字段、顶层导航可达性及精确提交时序仍待证。
实际候选行与switch的onClick先写remember编辑holder，再记录incoming编辑值；
DisposableEffect离开composition时cleanup才读holder当前值交全局setter。因此点击
日志可暂时不同于请求生效偏好，always_translate_switch也不是派生effective值，
不能将recomposition当点击、所有导航/消失名称当已证提交入口。
设备决策PropertyCenter也须分开：账号通知调用propertyChangedFor("mid")后异步
按name查entry，eligible时重求值，仅值变化写该name缓存，缺资格/provider时删该
name，再发property name事件；不是清全部决策cache。账号callback返回不等Bool
决策已更新，不取消HTTP或迁移once client；事件到依赖结果缓存失效仍未闭合。
DD原生响应gateway0x100135830需HTTP response、本地request-header字典及响应头
非空，dd-v缺失/nil不更新；存在值优先String，其次Int，均cast失败生成"0"，非空
才以force=false/from=http触发update。空String跳过，"0"触发不等于业务ACK或更新
成功；本native分支及注册不证明所有引擎同样采用，缺header也不是清配置指令。
**NeoBili 实际行为**：[AppDeviceProtocol](../NeoBili/Core/Networking/AppDeviceProtocol.swift)
编码自身buvid/session/trace和固定App、系统均zh/Hans/CN、Asia/Shanghai的locale1/2/4。
[AppRequestEncoder](../NeoBili/Core/Networking/AppRequestEncoding.swift)通过
[BiliHeaders.appAccountHeaders](../NeoBili/Core/Networking/BiliHeaders.swift)统一添加env/app-key、
固定aurora-zone，mid>0时加mid和自身计算的eid；gRPC有App凭据时加authorization，
metadata仅实现1–7字段，并按可选值缺省（访客无accessKey时不编码字段1）。
当前相关页BiliAPI+Video传入的仍是上述设备头，不生成guestid、x-bili-device-bin、
x-bili-network-bin或三种region头。编码器不读取实际网络/系统locale服务；它消费已校验
快照，外部context.headers还可覆盖默认头，apply使用URLRequest.setValue，无Ktor
write-once开关。Neo的[AppLanguage](../NeoBili/Core/UI/AppLanguage.swift)与
[语言设置](../NeoBili/Features/Settings/LanguageSettingsView.swift)仅选择界面语言并写
AppleLanguages，下次启动生效，内容保持原文；不驱动上述固定locale头或实现内容
翻译/alwaysTranslate，也未编码其派生字段。Neo APIClient使用已注入的HTTPTransport
和AppRequestEncoder，无对应PropertyCenter/按实验切Ktor客户端链；账号保护依调用方
expectedSessionID及响应代际，不能用旧包"mid"属性通知代替这些检查。Neo语言Picker
选择时直接AppLanguage.apply写所选项及AppleLanguages，无离开页面才提交的编辑
事务或上述点击日志；下一启动才改变UI，网络locale仍固定。APIClient/HTTPTransport
不消费dd-v，没有对应决策版本更新，不由缺失/坏header改变推荐配置。
**判定**：客户端版本/账号/自身设备和格式已有分层；locale固定中国配置是既定策略。
完整访客/设备/网络metadata缺实现或缺依据，不能从缺头直接推出请求未认证或兴趣失效。
原生旧包三块PB写入路径已证，当前Neo未实现其中Device/Network；不因此把其未知字段
整块复制，也不能将原生metadata生命周期套给所有Moss引擎。界面语言、系统locale、
请求locale和内容翻译是不同事实；缺内容翻译属条件性功能差异，不等于推荐身份失效。
**建议/接入**：设备与访客服务产出真实快照，由AppDeviceProtocol/AppRequestContext按
证实通道编码；AppClientIdentity只管客户端配置，AppRequestEncoding只组装，APIClient
继续先校验账号。公网IP地区必须等来源/更新证据，aurora-zone不能当真实地区，未知network
嵌套块不得复制样本或整段写死。若产品需要动态语言/内容翻译，先定义真实来源和
通道覆盖，再独立编码用户开关与派生状态，不把English界面直接当alwaysTranslate；
保留端点header优先级，不能为模仿Ktor而改普通首页。若加入编辑事务，分开编辑、
已提交、请求快照与日志事实；若加入DD更新，缺失/空/坏类型分别处理并校验请求
归属，不照搬坏类型隐式0策略。不要根据BiliHeaders旧注释
推断App只允许Android UA。
**验证/依赖**：账号/访客头、locale与系统语言区分、网络切换、headers覆盖、gRPCmetadata
脱敏golden；补write-once真/假与已有/空头的已证Ktor场景、SYSTEM/显式locale与
翻译开关组合、配置缺失/首个匹配、账号切换及重启存储；补编辑未退出/cleanup、
日志与请求值不同，以及dd-v缺失/空/错型/迟到更新，分别标通道和条件性功能。
AppProtocolIntegrationTests可复用注入边界，当前只定义了已实现字段。
**可能影响**：身份/实验/网络上下文，必需性和推荐效果仍待逐通道验收。

### R19 App签名的保留字符与旧包存在差异（P1，当前版本待验证）

**证据**：8.89 BFCApiSignHelper.createSign0x11609ce34排序键、对值description编码后
计算摘要；_encodeUrl0x11609d68c明确转义`!*'();:@&=+$,/?%#[]`。
S1新增Ktor CommonParams消费链0x10a9aca6c经排序器0x10a9b38b8及编码器
0x105d0b070(false)，键和值仅保留ASCII字母/数字/-._~，空格%20、加号%2B、星号%2A，
MD5为小写hex；多value逗号合并。Enable sign缺省true，ts缺失才补且有秒/毫秒配置，
不等于native HttpSign adapter覆盖范围已闭合。
[社区App签名页](https://janson20.github.io/bilibili-api-collect-mirror/docs/misc/sign/APP.html)
提供排序与摘要线索，但不同语言示例采用不同编码器，Swift示例使用.urlQueryAllowed，
不能视作当前iPhone逐字节规范；其跨平台appkey示例也不能直接移入当前身份配置。
**NeoBili 实际行为**：[AppSigner](../NeoBili/Core/Networking/AppSigner.swift)按原始字符串参数键
排序，再分别编码键和值，保留空值等号，签名与传输共用query字节；自定义字符集保留`!*'()`，并非
上述社区Swift示例。既有AppProtocolIntegrationTests的独立golden覆盖空值、空格、加号、
与号及中文，没有覆盖这五个字符；测试定义不等于本次已执行。
**当前样本离线复算**：S1独占实验目录的preflight记录官方9.13/build91300300捕获签名，
按严格`-._~`和当前JS保留集两种规则均匹配，App身份键与当前本地配置一致；S2只读
复核脚本与匹配结果，不输出实际常量。这份样本的值不含上述五个字符，所以支持已有
输入的签名兼容，不支持两种编码器在所有输入上等价，也不是服务器当次验签结果。三次读取的错误sign负控制也被接受，见下文实测边界；
不能以成功响应反证所有字符签名正确。
**判定**：避免Foundation宽松编码和签名/传输不同步已有实现；五个字符相对8.89旧包
有差异，Ktor局部编码规则也不保留这五个字符。NeoBili字符串字典不支持该多value分支；
其覆盖ts的策略与Ktor仅缺失才补也不同，需结合实际调用输入判断。9.13签名编码、
服务端接受性、数组/非字符串输入未闭合，不能据此判定所有
当前请求签名错误，也不能以已成功的普通数字字段请求证明完整一致。无法证明代码
源自该社区示例。
**建议/接入**：在AppSigner与AppRequestEncoder边界先补脱敏离线向量，再决定是否采用
按客户端版本限定的编码规则；不要修改独立Web WBI签名器来套用旧App规则。
**验证/依赖**：`!*'()`、保留分隔符、空键/值、Unicode、排序、已有sign覆盖与GET/表单
实际发送字节；若接入数组，需先确认createSign与buildQueryString不同分支。依赖S1
当前版本或足够独立的已知正确向量，不运行社区互动样例。
**可能影响**：包含这些字符的字段签名可靠性；是否影响推荐候选或兴趣更新没有证据。

### R20 首页磁盘兜底不同于保留内存旧卡（P2，账号/来源隔离为实施前置）

**证据**：8.89普通refresh失败0x101a5b3b0仅在缓存开关开启、flush属于mask0x1f7dff、
VM.cards空且open_event不为cold_back时调用0x101a54d44读兜底，不是发起网络重试。
正常响应同样受缓存开关与上述flush范围门控，在转卡之前经0x101a5a13c工作副本给extra_rpt_fields加is_cache_local_data="1"，
config剔除scene_uri/interest_guide后写datas/config。scene为tm.recommend.0.0，key
0x101a5a02c取发起查询时账号mid和style，version为VM.diskCacheVersion；expirationTime=0
实际后端语义未证。读回0x101a54878仅weak-load VM，未见MID/request-generation比较。
有效JSON即使datas/config缺失或类型不符也退空数组/字典并返回非nil；缓存恢复再走普通
编号/render，不等于一定显示了卡。Producer.subscribe0x1050e78d0两路分别返回ScheduledItem或SinkDisposer，析构只释放
成员，Optional替换/释放均不自动dispose；只有显式调用才取消，dealloc确有此调用。
普通refresh0x101a4893c在isLoading=true时拒绝新刷新，不dispose旧cacheRead。最终
FeedUpdater apply在默认分支受semaphore串行约束，实验true可绕过wait；commit点
0x101a44560/0x101a447f0只weak-load捕获updater后写datas，未见账号/代次或
before==current检查。串行和weak引用不能使旧响应自动失效；活VM切账号/替换、
外部diff引擎与额外取消防串扰仍待追踪，不能宣称已实测跨账号污染。
**NeoBili 实际行为**：[HomeViewModel](../NeoBili/Features/Home/HomeViewModel.swift)请求失败
保留已有内存卡；成功空过滤批推进游标后返回，没有官方式磁盘兜底、账号+style缓存或
缓存来源标记。自身loadID/session/取消检查保护正常网络回写，与旧包磁盘查询不同。
**判定**：缓存产品能力有差异，不是服务端重新推荐，也不证明缺缓存降低个性化。
旧包非nil缓存不保证非空卡；工作副本标记不代表当前网络卡已变为缓存卡。
**建议/接入**：只有产品需要离线首页时才在独立缓存层设计自身datas/config、格式版本、
有效期和来源上下文。账号/样式隔离、查询代际与迟到回调保护为P0前置，缓存卡点击/
曝光保持来源身份；不照搬未闭合的过期/取消语义，不绕过Neo已有响应防串扰。
**验证/依赖**：空/坏缓存、有效JSON无datas、账号/样式切换、迟到读取、新刷新替换、
写失败、版本/过期、缓存卡点击与曝光来源；依赖R08/R11/R15及后端0过期语义核查。
**可能影响**：离线可用性、用户实际可见候选与报告归属；未证推荐排序或兴趣效果。

### R21 App启动与活动段缺实现，旧包再次提交不应直接复制（P2，当前版本待核对）

**证据**：8.89 BFCActiveReport.applicationDidBecomeActive0x115fcfefc记录旧事件与
Neuron启动事件，first_open本地flag在事件生成后立即写true，不等网络回执。
foreground0x115fd04dc读取有end的旧app_active，可能再次生成同一eid的duration，
随后新建/覆盖活动段；background0x115fd0e40以字符串"0"结束并保存end，terminate
0x115fd0e4c以"1"生成结束但不保存新end。0x115fd0e58没有已有end/已上传复核，
无end记录在foreground被替换，不能称完整崩溃恢复；下游去重与9.13同链未验证。
首页模块回调0x11597d438以once同步枚举，亦可由默认3000ms延后入口触发，不要求
推荐成功；homeTasksStart/Finish量的是同步枚举，不是所有异步任务或网络回执。
Swift feedDataChanged/raw24消费者0x101a4a164只检查VM.dataFactory.datas与本地
layout flag，非空调用homeFinish:YES并置flag，空调用NO而不置flag；不是业务code
消费者。相邻ops.misaka.app-launcher是独立技术诊断，不作为推荐兴趣事件。
**NeoBili 实际行为**：[NeoBiliApp](../NeoBili/App/NeoBiliApp.swift)后台/active只通知
AppRecommendationSession启动状态；RootView/VideoPage有播放进度本地保存。
AppBehaviorEncoder只有点击，没有活动事件、首次标记/回执分层或活动段持久状态。
**判定**：旧包确有活动业务链，Neo缺实现；不是R12点击队列少补发，也不能凭缺项
推断当前推荐画像无效。真实活动计时与视频观看计时分别解释。
**建议/接入**：在App生命周期服务定义自身真实活动段与身份，事件生成、首次标记与
发送回执分别保存，再经行为编码/队列发送。不要为旧包一致主动重复生成同一活动段，
也不从旧字段名猜广告归因/指纹来源或合成不存在的资料。
**验证/依赖**：冷启动、连续active/foreground、首次发送失败、短后台、正常结束、
无end崩溃、重复回调与账号切换；依赖真实设备字段、R12编码和9.13活动样本。
**可能影响**：活动上下文覆盖；没有活动日志缺失导致推荐不足的因果证据。

### R22 心跳时间回执缺实现，公共时间辅助与观看计时须分开（P1，辅助来源P2待核对）

**证据**：8.89 reportTrigger0x114888230对同步发送快照仅index0成功且apiCallback非nil
时把serverTs排main，0x114888560调用捕获callback；Context回调0x114886910弱取原
context后写start_ts（0x11488692c），没有session/hash/当前start匹配或ts>0门禁。
发送前out ts初始化0，HTTP200错误分支也可判成功，因此callback不保证取得正时间。
setupDefaultConfig0x114885aa4分别取NSDate、BFCServerTimeChecker.realTimeInterval，
wire start_ts仅实验命中才用后者，否则0，后续可由该回执覆盖，不能统称全局校时。
独立时间辅助0x115dab238先用BFCServerTime，次选boottime/slinterval缓存；冷缓存
可异步请求x/report/click/now（timeout2秒）却立即返回0。completion只在now>0时保存
差值，无往返时延补偿；completion清flag，但error路径是否到达它与持久生命周期仍待核对。原生模块已注册
三个API类provider；BFCTimestampGateway0x10518ce44遍历响应头、忽略大小写匹配
x-bili-app-ts，doubleValue>0直接当Unix秒写BFCServerTime，未检查HTTP状态/error。
NetworkTimestamp多绑定注册及ApiClient moduleInitialize解析/登记类数组已闭合；
原生controller逐request按canInit实例化gateway，响应canonical先于rawDataHandler。
请求/响应各自重读ktorEnable，true跳过相应原生链，不能外推Ktor/Moss或假定flag
全程不变。它与heartbeat的data.ts回执不是同一个通道。
**NeoBili 实际行为**：[PlayerViewModel](../NeoBili/Features/Player/PlayerViewModel.swift)
watchStartTimestamp在已出画面、加载/续播门禁通过、playing且非buffering的首次
时间更新取本地Date秒，reset时清空；
生成的PlaybackWatchReport.startTimestamp不可变，由AppWatchProtocol原样编码。
[APIClient.postApp](../NeoBili/Core/Networking/APIClient.swift)只解码BiliEmptyData并返回Void，
BiliAPI.reportAppWatch及sender也不保留data.ts，没有服务器回执写回或独立时间辅助。
真实累计观看另用systemUptime推进，不能为补wire时间而替换这一计时来源。
**判定**：已证实缺回执时间消费；旧包首项弱回写不等于安全的按播放session校正。
9.13需不需要、何时使用这些时间仍未验收，本地时间不因此被证明错误。
**建议/接入**：心跳层独立typed回执，明确只在何种成功/有效时间条件下消费；检查账号
代际、播放session与context代际，再定义仅影响后续快照还是已有待发送快照。
不照搬首项弱回写，不让迟到结果改写新播放。公共时间服务另按已证实来源/缓存政策
设计，不能把异步辅助调用本身当校时成功，也不直接新增全局校时依赖。
**验证/依赖**：旧session/账号回执迟到、重播后回写、0/负/缺ts、首项失败后项成功、
待发送快照一致性、冷缓存与辅助失败；依赖当前版本响应样本、上游writer及R16/R17。
**可能影响**：报告时间关联和可解释性；没有时间差异导致推荐不足的因果证据。

### R23 应用定时心跳未实现，不能用历史checkpoint替代（P2）

**证据**：8.89普通HeartbeatService在trackMetaInfo/appendSliceContext把自身绑定为
AtomicHeartbeat proxy数据源。Atomic字典入口0x11487eac8要求播放器取得focus、数据源
存在且响应trackMetaInfo；读取当前位置、倍率、画质、缓冲、sceneMap及同一个tracker
session，没有另建Atomic session。BFCAtomicHeartbeat._fireDelegates0x1149f2f10
合入各非空delegate字典，后枚举项可覆盖字段，本段未排序或按session过滤；经注入
helper0x100129684调用BFCNeuronService customEvent/setExtendedFields/trackEvent，
policy raw0，最终服务注册与上传覆盖仍待确认，不是直接调用播放历史HTTP。
startBeating排随机0–29秒的always启动工作，同时启动point timer；两者mainRunLoop
common/repeats且fireDate=distantPast，always间隔30秒，point在state3/10/20发事件。
该state不是播放器状态；end会invalidate现有timer，先前排队启动block未见代际复查。
**NeoBili 实际行为**：源码无new_heartbeat事件、Atomic数据源或对应应用timer。
PlaybackWatchProgress的首次5秒/后续15秒checkpoint依真实观看推进，发送移动历史；
它不聚合应用delegate、focus/scene和画质资料，也不编码应用定时心跳（见R13/R21）。
**判定**：应用事件路径存在独立缺口；不能把旧包应用timer频率改成Neo观看报告频率，
也不能从注入接口调用推定当前服务器需要该事件或已接收兴趣信号。
**建议/接入**：新版和上传通道闭合后，在应用行为层独立管理调度，由当前播放器提供
不可变状态快照；保留账号/播放会话关联与focus资格。启动/结束包含代际取消，字段
聚合需确定冲突优先级，不能照搬无序覆盖或销毁后迟到启动。
**验证/依赖**：无focus、多播放器、快速start/end、重复start、排队启动迟到、账号切换、
后台/主线程暂停及字段冲突；依赖9.13同链、Neuron注册和最终编码/上传证据。
**可能影响**：应用与播放状态可解释性；无该事件导致推荐不足的因果证据。

### R24 兴趣引导为独立可选功能，安装标记与迟到回执须另建所有权（P2，条件性）

**证据**：8.89 guide物理action先调用网络closure，再track/dismiss；发送index/interest
的action="1"，close走独立cancelClosure。guide失败/success finisher为bare ret，与
launch的Unavailable/token.done策略不同。second/interest独立builder编码unique_id、
选中结果及source映射half/full，device_type读安装以来首次feed成功标记的String，
缺值"0"；该标记默认Bool false，feed nil-error链置true，IPA未显式完成Bool→String
编码。它不是机型，也不是当前登录状态或请求已成功的证明。
T37首屏确认成功回调先排0.5秒清loading，再处理response；原view释放仍可更新共享
manager model，随后才弱gate UI。本段未见account/request/current-model检查；
空items及网络失败回退捕获原model，不能据此断言实测跨账号交付。
T34 S1 willDisplay对display child._isExposed去重，false才track兴趣show，track返回
即将同child置true，不等待网络成功，也不因发送失败恢复资格。SubItem新建false，
YYModel黑名单排除该marker；S1 configure直接保留输入model/items，没有deep copy
或reset，因此同model重建及失败fallback保留它。全局reset、新响应对象复用及账号
边界未闭合；这是子对象曝光标记，不是MID/ID/IndexPath持久去重池。
**NeoBili 实际行为**：首页仅解码卡片、游标与refreshConfig，无interest_choose模型、
上述两兴趣endpoint、引导/二次选择或安装成功标记。现有“不感兴趣”菜单走dislike
反馈，与此选择功能不同；LiveAPI的device_type="0"属直播通道，不能挪作该字段来源。
**判定**：存在可选功能差异，其选择/恢复/刷新分支可改变实际展示卡片；没有证据说明
Neo必须实现它才能获得个性化推荐，不能把此device_type补到普通feed或当设备身份。
**建议/接入**：账号/请求隔离作为P0前置。仅在产品需要兴趣选择且新版契约闭合后
实施；分别建launch/guide/second
状态与失败策略。安装标记由本地安装生命周期拥有，显式编码；请求捕获账号代际、
选择model标识和请求代次，关闭/替换后定义是否允许业务回执更新，不能只用弱view
作保护。兴趣show业务去重与发送队列重试分别定义：真实展示形成事实后重传同一
事件，不因传输失败制造新曝光；不能机械照搬跨账号未证的对象marker生命周期。
UI点击/关闭与网络成功独立，不用伪操作或静默请求补齐状态。
**验证/依赖**：首次安装/重启、已有feed成功、guide action与close、缺/空response、
连续选择、关闭后迟到、旧请求清新loading、账号切换和恢复旧卡片；补同child反复
展示/传输失败、同model重建、新model与原对象复用，区分事件去重和补发；依赖9.13对应
模型/endpoint与安装标记契约，以及R11/R14/R20的选择后render范围。
**可能影响**：用户显式兴趣选择及展示分支；推荐质量改善与旧包跨账号结果均未验证。

### R25 播放器操作日志未实现，不能按其单位修改观看报告（P2）

**证据**：8.89 Tracker0x114880e90构造BFCNeuronPlayerEvent，category raw9，默认
track policy0、instantly才policy1。currentTime秒×1000再向零转Int32，先写
CommonFieldsModel，再填event；queue仅cid匹配才取itemCurrentTime，否则0。
quality映射0x11488242c只保留15/16/32/64/74/80/100/112/116/120/129，其余0。
model自身session先填入，后由当前tracker session覆盖；seq为实例报告顺序，缺该
扩展键时才补旧值并递增。operation入队返回true不是磁盘或上传成功。
**NeoBili 实际行为**：[AppBehaviorEncoder](../NeoBili/Core/Networking/AppBehaviorEncoder.swift)
仅构造推荐点击，无PlayerEvent。AppWatchProtocol的history progress及mobile播放
位置采用整数秒，累计观看另有字段；PlayerViewModel报告使用实际选中quality。
当前无上述公共model/日志序号/画质映射，不能归入R23应用timer或称为该日志已实现。
**判定**：日志覆盖有差异，单位/白名单属不同通道；没有证据将Neo AppWatch的秒值
或quality取值判错，日志缺失与推荐不足的因果也未验证。
**建议/接入**：仅在新版事件/上传契约及真实触发闭合后，行为层另建typed PlayerEvent，
由播放器提供不可变位置/画质/会话事实，明确定义序号与model替换。未知画质和非有限/
Int32越界值需显式处理，不能照搬转换指令的异常结果；不为格式完整制造操作事件。
**验证/依赖**：seek/续播、cid不匹配、未知画质、Int32边界、倍率格式、公共model
替换、跨容器继承和事件次序；依赖9.13对应事件、observer完整边界与最终上传链。
**可能影响**：播放器操作关联与可解释性；事件构造/入队不证明兴趣画像已更新。

## 关联业务边界：稍后再看

8.89新版WatchLater列表使用start_key/split_key及分页，Rx包装须实际订阅才发送，
当前包装dispose不直接cancel。删除effect的业务closure发fire-and-forget请求后就
完成observer；Store先发布reducer状态，再订阅effects，不是服务器ACK后才改UI。
首次appearance经每次binding的TakeCount(1)派发refetch，手动刷新与底部分页独立；
不能概括为进程全局once，也不能由动作派发推定请求已通过reducer门禁。

Neo的[BiliAPI+WatchLater](../NeoBili/Core/Networking/BiliAPI+WatchLater.swift)用旧网页
list/add/del端点，当前列表一次读取，无v2分页。[WatchLaterView](../NeoBili/Features/Library/WatchLaterView.swift)
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
稍后再看入口的真实播放补成首页卡片点击/曝光；8.89外层账号归属与9.13契约仍待证。

## 关联业务边界：LatestHistory 与本机续播

8.89 HD2 helper在enableResumePlaying关闭时直接handler(nil,nil)，不发LatestHistory
RPC；开启才发business=archive及playerPreload。无error且reply.items非nil才回调
model；items=nil本body跳过handler，不是显式空回执。descriptor确认items是单
CursorItem message，不是数组；GPB缺值getter的运行可达性及后续uri消费仍待证。
因此不能把这个RPC当首页刷新、观看上传或历史列表分页，也不能按名称将items建数组。

Neo无此RPC；[PlaybackProgressStore](../NeoBili/Features/Player/PlaybackProgressStore.swift)
以bvid/cid保存本机进度，不依赖登录/云历史，忽略无效位置与近片尾；PlayerViewModel
开流及拿到时长后读取，PlaybackResumeState在到达目标前拒绝旧位置/短暂0。
本机续播是当前明确语义，不因缺云端RPC就判错或要求账号隔离本地进度；网页历史
列表和App观看同步分别有独立通道。

若产品需要跨设备续播，再设计typed单项、账号/请求代际和每条结果路径的明确完成，
对缺项、禁用、取消及迟到回执给出可测试行为，不照搬跳过callback造成等待不结束的
风险。新版契约、云/本机进度优先级及关闭设置需先确认；无该功能影响推荐的因果证据。

## 关联业务边界：分享菜单

8.89 BFCShareOperation持有canonize callback，channelList/clickBlock则属于
operation.model。dispatch group的main notify先dismiss loading，terminated则退出；
有error经当前delegate判forbidden，true提示错误并回调失败，不呈现菜单，false允许
默认channel list回退。canonize后复制到model再present；delegate真实规则仍待证，
不能把网络失败一概当禁止分享，也不能将present调用当发送/用户分享成功。

Neo视频页用链接打开系统UIActivityViewController，无上述网络分享operation、服务端
channel配置或forbidden判定。不相关逻辑不新增实施项；如果未来支持远程分享菜单，
再定义operation/model所有权、可回退错误、取消/迟到回执和用户完成语义。分享链没有
被证明是普通首页个性化推荐必要条件，不因旧包功能差异改系统分享或补假事件。

## 社区资料的辅助核查

| 页面与范围 | 对照当前代码与强证据 | 判定与后续 |
| --- | --- | --- |
| [fork推荐页](https://github.com/melon-444/bilibili-API-collect-fork/blob/master/docs/video/recommend.md)：短视频列表示例含Android平台、fnval=272、fnver=1、布尔pull | R01当前iPhone参数为独立配置；8.89 fnver=0，9.13样本pull为数值。社区登录事件默认值不能替代S1的状态链 | 平台/版本与部分值冲突；不拿示例静态值填补未知刷新或登录状态 |
| [fork视频流页](https://github.com/melon-444/bilibili-API-collect-fork/blob/master/docs/video/videostream_url.md)：fnval位组合、qn与流格式线索 | R02实际普通视频Web WBI路径默认qn=127、fnval=4048→16→1；2448属于LiveAPI消费。请求qn不等于返回或实际选中清晰度 | 用于理解参数与响应需分层，不能仅凭位声明证明HDR能力、权益或官方当前能力值 |
| [镜像观看页](https://janson20.github.io/bilibili-api-collect-mirror/docs/video/report.html)：区分App历史与Web心跳，时长计算明确带猜测 | BiliAPI+History在Web心跳用played_time表达位置；AppWatchProtocol在移动报告用它表达累计观看，R13中两种App时长目前相等。当前15秒节奏可在源码确认 | 未发现Web位置语义直接混入App字段；相同周期或相等时长不证明继承关系。按旧包真实时间/倍速证据继续验收 |
| [镜像App签名页](https://janson20.github.io/bilibili-api-collect-mirror/docs/misc/sign/APP.html)：多平台密钥选择与多语言编码示例 | 当前AppSigner自定义编码、空值保留及App/passport用途分层，社区Swift示例不能给出现有golden的独立正确性证明 | R19单列具体字符差异；不复制示例密钥，不把Web WBI与App签名合并 |

以上只核查这几页对应的实际调用。源码中明确引用其他项目的注释属于该处作者说明，
不能扩展成整个项目来自这些fork的结论。社区页面内部也存在fnver等差异，优先保留
冲突与待验证项；请求被接受仍不能证明兴趣画像按官方方式更新。

## 接入顺序与验收

1. 闭合 R01/R06/R11 的功能赋值、资料缺省和卡片位置来源，整理脱敏golden。
2. 先建立自身身份/登记状态与报告上下文；迁移方案保留原设备连续性。登记、ticket等
   领域写通道必须独立声明认证/响应/重试，不能借用通用只读gRPC重试。
3. 按卡型补点击公共字段及展示/逐段时长，再逐项完善观看事实和负反馈；每个事件以
实际动作触发，不因预载/解析/接口成功制造行为。
4. 实施后按 [开发指南](DEVELOPMENT.md) 运行受影响离线/回归和阶段完整验证。
   本地参数/认证对照已获授权；App联网方案及真机专项与脚本实验分别验收，
   本轮不运行Simulator、部署或手机采集。
5. 先验协议自身资料可用、字段/会话/回执正确，再验真实观看后的推荐变化。
   推荐效果至少控制账号、设备连续性、入口、网络、设置和请求状态，观察多轮候选与
   内容分类；标题关键词计数与两批完全一致都不能单独代表个性化等价。

## 已授权本地对照的执行边界与当前结果

用户授权后，S1已串行完成既定三次feed/index GET；S2未额外发请求。本轮沿用官方
采集的国际版配置：mobi_app=iphone_i、build=91300300，statistics为appId14/version6.6.0。
不能把它当成Neo既定中国版配置、所有请求通道或生产实现已完成验收。材料保存在
忽略目录`DerivedData/Validation/recommendation-network-s1/`，输入和原始响应/头权限
0600。S2只读复核安全摘要、脚本，并在内存重解析三份响应正文，输出仅为业务码、
结构/数量及编号交集数量，不输出编号本身。独立复核结果留在自身忽略验证目录。
手机采集、处理版App执行、曝光/观看/互动上报和生产修改均未进行。

既有官方9.13/build91300300捕获签名的两种编码复算均匹配，但值不含R19五个争议
字符；离线匹配不能验证完整字符范围。请求更新ts后签名，业务参数/flush/pull/idx
仍沿用样本，固定同一个ts；每组完成后等15秒，实际起始间隔约18.0/17.8秒。
第三组相对第二组还恢复sign，表中变化均以第一组为基线。

| 顺序/相对基线变化 | HTTP | 业务code | 响应结构与独立复核 |
| --- | --- | --- | --- |
| 1：正确sign，不带ticket | 200 | 0 | 对象数组10项，均goto=av |
| 2：仅sign首字符改成不同值 | 200 | 0 | 对象数组10项，均goto=av；与基线唯一视频编号交集0 |
| 3：正确sign，加入既有捕获ticket | 200 | 0 | 对象数组10项，均goto=av；与基线唯一视频编号交集0 |

**实测判定**：这次端点、身份及参数组合没有拒绝错误sign，因此不能用成功响应证明
签名被校验；不推广成其他端点、认证通道或所有输入均无需签名。无ticket组成功仅表明
此组可返回列表，不证明票据服务、启用门控或生命周期无需实现。加捕获ticket成功也
不证明其有效、被验证或参与排序；票据实际签发时间/有效性尚未确认。

构造复核确认本轮未带Cookie或authorization头；没有另调用账号校验接口，仍不能由
列表成功证明服务端采用access_key对应的个性化身份。
三次不是同一状态的重放；读取可能消耗游标/推进推荐状态，旧操作参数也不是一次真实
官方刷新动作的复现。列表差异不构成签名、ticket、设备画像或兴趣变化的因果证据。
该实验不是8.89生命周期在9.13完整复现，也未验收曝光/观看报告或长期补发。

此前默认环境URLError及联网自动审批拒绝属于独立执行记录；S1在访问权限恢复并获
继续指令后完成三次请求，旧阻碍已解除，不再列为当前待确认事项。预算未扩大。
脚本记录逻辑已修正为先保留HTTP状态/正文长度，再分别判断HTTP、业务码和卡片结构；
异常仅输出脱敏类别。独立离线重解析支持上述数量与交集，不能扩大服务器结论范围。

## 未决证据与维护范围

S1已补部分功能/设置→参数的UI写入和Swift最终读取，仍在追剩余同步/覆盖、
Swift兴趣选择/重编号范围、缓存后端过期与活VM取消/账号边界、设备资料注入/更新
与ticket启用范围、公共时间辅助错误路径/缓存持久化，以及Atomic心跳注册/上传与
调度生命周期；兴趣回执账号/请求所有权、PlayerEvent触发/编码、Series/HD2日志配置的最终入口和UGC广告归因的
加载/展示边界、Monitor外部重试入口和广告采样配置值/更新范围；Ktor Locale byte
序列化/引擎覆盖及翻译设置外部清理、设备属性事件到结果缓存失效、LatestHistory
缺项运行可达性/uri消费、语言cleanup导航时序及DD更新结果归属；分享forbidden
真实delegate规则和画质UI实际呈现。普通网络刷新及缓存恢复的compactMap编号链已补入R11/R20，播放
stash、tracker继承和时间回执的差异见R13/R16/R17/R22，应用定时心跳见R23。
Series已定位URL/参数/响应入口0x10411a640/0x10411a6e4/0x10411af68，HD2 MainVM
发送入口0x10df58dfc；这些是请求与响应配置锚点，不代表Series专属日志producer闭合。
本文不重做整份逆向；收到新证据后核对实际调用与最终赋值，再更新相关R项判定。
9.13新版函数体、登记兼容、访客完整生命周期、日志跨账号官方策略以及推荐因果仍未
验收。国际版可用于字段关系线索，不能替换中国版身份配置。

当前覆盖首页请求、身份登记、卡片点击/观看关联、曝光与缓存补发、过滤去重；搜索、
动态、推送、评论等业务只有在S1证明与这条推荐链有关时才转为实施建议，不建议照搬
所有网络请求。普通会话跟进不等于后台永久监控或无人值守唤醒。
