# 一、首页与推荐链

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 一、首页与推荐链

### FEED-01 feed/index（App 首页推荐）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `BBHD2PhonePegasusMainApi.baseUrl`（0x10df57790）返回 `app.bilibili.com/x/v2/feed/index`；无 host 回退链的静态证据。业务层为 `BFCApiRequest`（HTTP GET），Ktor 桥接或旧 task 由 `dd.http_client_opt` / `dd_http_client_use_ktor` 决定。 |
| 2) 触发时机 | HD2：`BBHD2PhonePegasusMainVM.init`（0x10df58690）后的首次 `loadData`（0x10df58a10）；下拉/刷新与 `loadMore`（0x10df5a4c0）另建 MainApi 并设 `pullType=0`/`flush=8`。Swift 侧：`BiliAPI.appRecommendFeed` 每次首页请求新建参数。账号 observer 只对 action 1/2 更新同一 `login_event` 映射。 |
| 3) 请求头 | 传统 HTTP 公共头由 `-[BFCApiRequest _buildRequestOperation:afterRequest:]`（0x11609537c）写：User-Agent、非空 Session_ID、非空 x-bili-trace-id、`options.extraHTTPHeader`、`authenticationHeaderParams`（当前仅返回非 nil 的 `+[BFCBuvid buvid]` 作 Buvid，0x11609d4b4–0x11609d4b8）。`extraHTTPHeader`（0x10df56d34）只在 `BFCAppPreferences.isNewInstall` 且 `PegasusConfig.isFeedReqSuccessOnce` 为假时追加 DeviceInfo，明文是单键 idfa JSON，AES-128-ECB + PKCS#7 后 Base64（0x10df06d08，key 来自调用处包内常量，本文不记录）。Ktor 路径另受 `Enable common params` / `Enable GInterceptor`（键槽 0x120c5e410，缺省 false）门控。 |
| 4) 参数及来源 | 见下方“FEED-01 参数来源”表；对象属性来自 VM，播放能力来自 `BBPlayerPreloadUrlParamsHelper.preloadUrlParams`，`firstRequestInfo` 来自启动读取的 `Documents/chooseInterest.plist`（helper init 0x10df579ec，读完即删）。 |
| 5) 签名与编码规则 | 传统路径由 `BFCApiSignHelper`：`signType` 0 用 `authenticationParams`（baseParams + ts + 有值时的 access_key）并生成 sign，2 用 `authenticationParamsWithoutTs` 并生成 sign，1/3 不生成；生成前合并 `options.params`，业务参数可覆盖公共参数。`createSign:`（0x11609ce34）按键 `compare:` 排序，各值 `description` 经 `_encodeUrl:`（0x11609d68c，CFURL percent escape、UTF-8、显式转义 `!*'();:@&=+$,/?%#[]`）拼成 `key=value` 并用 `&` 连接、去掉末尾 `&`，追加按 appkey 选择的 secret，取 MD5 小写。Ktor 路径由 `CommonParamsPlugin`：按 `Map.Entry.key` 排序（comparator 0x10a9b38b8），多 value 先逗号合并，key 与 value 均经 0x105d0b070(false) 编码（仅保留 ASCII 字母数字与 `-._~`，空格 `%20`、`+` `%2B`、`*` `%2A`），拼 `key=value` 以 `&` 连接后追加后缀，MD5 小写；仅缺失 ts 才补，`dd.sign_ts_use_milliseconds` 默认 false 用秒。 |
| 6) 响应结构 | `modelDescriptions`（0x10df575e4）：`/data/items`（数组、必需）、`/data/config`（非数组、可选）、`/data/config/auto_refresh_time`（非数组、可选）。成功回调（0x10df59104）应用服务器 config 的 `follow_mode`、`auto_refresh_time`、列布局、自动播放等，置 `isFeedReqSuccessOnce`，清空 `helper.firstRequestInfo`，并把 `login_event` 置 0；取 converted array 第一张卡（0x10df5969c）且在 `isKindOf CardBaseModel` 时才读 idx（0x10df596fc）并存 `DataManager.savePegasusFeedIndex`（0x10df59714）。顶层 code 非零在非 `ignoreCodeNonZero` 时走 `BFCApiNonZeroErrorDomain`（公共层 0x116093fe4 上游）。分页：`loadMore` 取末卡 idx，首次刷新取首卡或本地保存的 Pegasus feed index。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 的 `AppRecommendationProtocol.parameters`（[AppRecommendationProtocol.swift](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationProtocol.swift)）把 `auto_refresh_state=4`、`inline_sound_cold_state=4`、`inline_sound=1`、`autoplay_card=10`、`video_mode=1`、`recsys_mode=0`、`client_attr=0`、`qn_policy=1`、`disable_rcmd=0`、`teenagers_age=16`、`guidance=1`、`https_url_req=0`、`column=4`、`fnval=84948`、`qn=32`、`fourk=1`、`force_host=0`、`soft_fnval=2` 写成固定值；8.89 侧这些字段各有真实来源（主文档“功能、设置与首页请求参数”表逐项列出）。`flush`/`pull` 按 `pageIndex`/`isRefresh`/`isLayoutChange` 生成 0/2/6/8 与 1/0，与 8.89 的 `pullType`/`flush` 取值集合相容但不是同一条读取链；`idx` 分刷新首游标与分页尾游标；network/player_net 使用真实网络状态。请求由 `BiliAPI.appRecommendFeed`（[BiliAPI+Recommendation.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Recommendation.swift)）调用 `getApp`。差异判定见 [RECOMMENDATION_IMPLEMENTATION_REVIEW.md](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md) 的 R01/R02。 |
| 8) 证据等级与版本 | 8.89 静态（entry 参数 0x10df56ed4、`baseUrl` 0x10df57790、`loadData` 0x10df58a10、success 0x10df59104、`loadMore` 0x10df5a4c0、`extraHTTPHeader` 0x10df56d34、`modelDescriptions` 0x10df575e4）；本地实测（三次 GET，见主文档“本地联网对照的当前边界”，结构与业务码，不构成验签/个性化证据）；当前源码（上列锚点）。 |
| 9) 残余不确定项 | `idx` 首卡保存门禁已证数组非空且卡0为CardBaseModel→savePegasusFeedIndex→BFCPreferences动态setter→NSUserDefaults suite BBHD2PhonePegasusConfig（root-static-remaining）；真实磁盘完成不由setter返回证明；`DeviceInfo` 头所用 AES key 属包内常量、现版是否仍相同未证；跨启动的首次成功状态与落盘时序需真机读取。 |

**FEED-01 参数来源**

| 参数 | 8.89 来源/条件 |
| --- | --- |
| pull | `pullType=0`→`0`，`=1`→`1`，其他不加 |
| idx / column | 对象整数属性转字符串 |
| network | `BFCReachability.currentStatus` 映射 wifi/mobile/空 |
| login_event | 对象属性非零才加（`init` 按 hasLogin 设 2/1） |
| open_event / banner_hash | helper getter；nil 兜底空字符串。`open_event`（0x10df57b60）读取即消费：`isFirstRefresh` 为真时按 `isColdLaunch` 返回 cold/hot，然后无条件置 `isFirstRefresh` 假。1800 秒清 banner_hash 的三方法（0x10df57b34/0x10df57bdc/0x10df57c20）已静态证死：无注册点（三个 selref 全部加载点枚举无 Pegasus 区间）且无 BL 调用者（阳性对照 BBLiveHighFansRoomViewController.viewDidLoad 0x101df93cc） |
| ad_extra / splash_id | `BBAdReport.requestAdExtra` / 对象属性，nil 兜底空 |
| firstRequestInfo | 将 helper.firstRequestInfo 键值逐项合入 |
| flush / recsys_mode / autoplay_card | 对象整数属性转字符串（VM.flush=-555 是内部已派发标志，下次 loadData 先改 0） |
| fnval/fnver/qn/fourk/force_host/player_extra_content | `getPlayerParams` 合并，底层 `BBPlayerPreloadUrlParamsHelper.preloadUrlParams` |
| interest / interest_v2 | 已有合并值优先；未出现时用对象属性或空字符串；interest_v2 非 nil 才加 |
| device_type | `isFirstCall` 为真才加 `1` |
| https_url_req / guidance | `httpsPlayurlEnabled` / `needShowGuidance` 映射 1/0 |
| screen_window_type | `BBHD2ScreenSwitchHelper.windowType` 转字符串 |
| caid（Swift 侧） | Marker 0x101a3515c 在 `hasUploadedCaidSinceInstallation=false` 时 global queue 调 `BBDeviceInfo.mergeCAIDParams`（0x101a35e0c），main queue 转 JSON 存 Marker+48/+50；MainApi 0x101a33a34 非 nil 才写 caid 并覆盖同键；merge实际为12项本地设备材料而非CAID标识getter，材料覆盖输入同键，JSON失败非nil空串仍可发送。字段与来源见root-static-session/home-caid.md |

**FEED-01 现版（9.13 抓包线级，team-c12；官方 App build 91300100，268 条 feed/index）**

同一 App 在同一批抓包里存在**两套参数模板**（`feed-template.jsonl`）：

- **完整模板**（48 键基准，236 条）：含 18 个 HD2/Pegasus 扩展键 `open_event / banner_hash /
  login_event / client_attr / qn_policy / player_net / soft_fnval / autoplay_card /
  auto_refresh_state / inline_danmu / inline_sound / inline_sound_cold_state / video_mode /
  teenagers_age / splash_ids / splash_creative_id / ad_extra / network`；其中 `ad_extra` 与
  `network` **同现同缺**（186 条同现），`widgets` 独立缺省，`access_key` 与登录态同现同缺。
- **精简模板**（29/28 键，32 条）：上列 18 键**全部不出现**（另缺 widgets/caid/cny_info/device_type）。
- `caid`/`cny_info`/`device_type` 在 feed/index 上仅各 2 条（海外组）。

观测取值域（**本次样本取值，非协议常量**）：`open_event` ∈ {空, `cold`, `hot`}；
`flush` ∈ {0,1,2,5,6,8,14}；`pull` ∈ {0,1}；`login_event` ∈ {0,2}（海外组另见 `1`）；
`column` ∈ {2,3,4}；**`fnval` ∈ {84948, 2448}（同一端点两种取值）**；`force_host` ∈ {0,2}；
`https_url_req` ∈ {0,1}；`inline_sound` ∈ {1,2,3}；`autoplay_card` ∈ {4,10}（海外 11）；
`auto_refresh_state` ∈ {1,3,4}；`client_attr`=1（海外 0）；`qn`=32、`qn_policy`=1、`fourk`=1、
`player_net`=1、`recsys_mode`=0、`disable_rcmd`=0、`video_mode`=1、`guidance`=1、`soft_fnval`=2、
`teenagers_age`=16、`voice_balance`=0、`network`=`wifi`。证据 `DerivedData/Validation/team-c12/feed-template.jsonl`、
`wire-feed.jsonl`、`endpoint-params.jsonl`。

### FEED-02 feed/index/interest（启动/引导兴趣选择）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `https://app.bilibili.com/x/v2/feed/index/interest`，`requestMethod` raw0（公共 builder 默认 GET），统一 interest builder 0x103c6e0d0（URL 0x103c6e13c/0x103c6e17c）。 |
| 2) 触发时机 | 两条入口：launch item（scene raw2，`process` 0x103c766fc→0x103c763bc 置 `source=0`）；guide（`processWithGuide` 0x103c7489c，物理入口 `actionButtonDidTap` 0x103c7226c 先调 actionClosure 再做 track/dismiss）。launch 还受 `MainVM setup` 0x101a49e68 的 `isRequestEnabled`（0x103c73c7c）本地门禁：`!hasShown` 且（`isNewInstall` 或 `disableActionOpenHomepage=true` 且 `!hasSubmitedInterest`）。 |
| 3) 请求头 | 走公共 HTTP 层，与 FEED-01 同（User-Agent / Session_ID / x-bili-trace-id / extraHTTPHeader / Buvid）。builder 未设置自有 auth/cache/responseQueue，也未把 request 存 manager ivar。 |
| 4) 参数及来源 | 键顺序：非空 manager CAID→`caid`；`cny_info`（JSON String）；合并调用方字典；最后条件性 `dp_status`。`cny_info` 恒由两键对象生成：`cny_active`=`TabDisplayManager.isCnyTabDefaultSelected` 的 Bool 转 Int，`ab_test_vars`=`cnyAbTestVars`（nil→空），`NSJSONSerialization` options0、UTF-8、失败返回空 String、不请求 sortedKeys（0x103c6f200）。`dp_status`：builder 每次先递增进程 counter 0x120442df8，再取 `BFCLauncherContext.hasAction`；true 且 count1→`"1"`、count2→`"2"`、其他省略（0x103c6e4d4–0x103c6e528）。调用方字典同键可覆盖 caid/cny_info，生成的 dp_status 后写覆盖同键；launch caller 传空字典。guide action 带静态 `{"action":"1"}`、source raw1。 |
| 5) 签名与编码规则 | 同 FEED-01 的公共签名层；本 builder 未额外设置签名或编码。 |
| 6) 响应结构 | 三条 optional/nonarray 描述路径：`/data/interest_choose`、`/data/config/close_small_window`、`/data/config/interest_popup_logic_exp`。回执 0x103c6d610 先消费 config：`close_small_window` 1→自动小窗（0x104b1ae2c）、2→自动 PiP（0x104b1ae04）、3→两者，对应 helper 先检查手动操作标记、已手动则 return；`interest_popup_logic_exp` 先写共享 manager。随后 `dp_status=="1"` 直接 `success(nil)` 并丢弃兴趣内容（0x103c6d7bc–0x103c6d838）；其他 dp_status 才解析 InterestModel，成功先写固定 suite 的 `disableActionOpenHomepage`，再用 model 的 `interest_popup_logic_exp` 覆盖 config 实验值。解析缺失/失败也是 `success(nil)`，不走 errorHandler。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 首页只解码卡片、游标与 refreshConfig，无 `interest_choose` 模型、无本端点与 `/second/interest`、无引导/二次选择与安装成功标记（[AppRecommendationPage.swift](../../../NeoBili/Data/Networking/Recommendation/AppRecommendationPage.swift)）；现有“不感兴趣”走 FEED-05 的 dislike 反馈。差异判定见 review 文档 R24（条件性 P2，不构成推荐必要项）。 |
| 8) 证据等级与版本 | 8.89 静态（builder 0x103c6e0d0、回执 0x103c6d610、`isRequestEnabled` 0x103c73c7c、guide 0x103c7489c）；当前源码。 |
| 9) 残余不确定项 | ObjC methodtable已绑定Token.done113c3c018与Transaction.finishItem113c3c2d8；registerWithItem真实创建business item/token，token strong item+8/weak operator+10，done→同operator.finishItem→removeItem→start。所选7 done selref/5 token descriptor/直接stub候选已逐原始body归属，accepted interest真实success capture已核：accepted→prepare跳过所捕获failurefinisher，T17 dismiss经实际witness结束serial token而非launch token；实际MainVM delegate.scene与登录弹窗MakeDismiss producer已读，14个view factory/witness及5个shared-sheet nil completion已核，仍未找到accepted launch完成source；不能说zero直接引用证明不存在或静态不可能。未知间接桥超出该寻址覆盖，实际到达需运行观测（root-static-exposure/final-feed-heartbeat-tail.md）。 |

### FEED-03 feed/second/interest（二次兴趣选择）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `https://app.bilibili.com/x/v2/feed/second/interest`，`requestMethod` raw0，独立 builder 0x103c6e96c。 |
| 2) 触发时机 | 物理确认入口按 style 分流：T37 首屏 `_confirmButtonDidTap` 0x103d87d9c、T37 最终确认 0x103d97798→0x103d8a940、T35 `confirm` 0x103d6c1c4→0x103d6b5b4、T18 0x103cff000、T19 0x103d24370、T33 0x103d45a84、T34 0x103d58390。T37/T33/T34 在 `_isRequesting`/`busy` 门禁后发；T18/T19/T35 的 admission body 只检查 model 非 nil。 |
| 3) 请求头 | 公共 HTTP 层同 FEED-01；builder 未设置自有 timeout/cache/auth/responseQueue，也未持有 cancel。 |
| 4) 参数及来源 | 可选非空 `manager.caid`；`interest_id`=`model.unique_id` 的 Int64 十进制；`interest_result`=传入 String；`interest_type`=传入 Bool `true→half`/`false→full`；`device_type`=固定 suite `BBPhonePegasusConfig` 中 `stringForKey:isFeedReqSuccessOnceSinceInstallation` 的原 String，缺值→`"0"`（0x103c6ecd8–0x103c6ed9c）。该 builder 不递增 index counter，无 `cny_info`/`dp_status`/调用方字典合并。SID 编码按 style 不同：T37 用 `selectedItems` 顺序 + weak SubItem 匹配生成 `parentId.SubItemId`（0x103d858a8），T33/T34 直接按 `selectedSubItems` 顺序（0x103d443f4/0x103d56d00），T18/T19 只追加 gender.id/age.id（0x103d22568/0x103cfd1f8 传 Bool=true）。 |
| 5) 签名与编码规则 | 同 FEED-01 公共签名层。`device_type` 的 Bool→String 是系统 `stringForKey` 读法，IPA 内未见显式编码。 |
| 6) 响应结构 | `optional/nonarray` 路径为 `/data/interest_choose` 与 `/data/config/close_small_window`；回执 0x103c6dbdc 只解析 `interest_choose`，经 YYModel 与 nested-model 归一化 0x103c77974 后 `success(model)`，缺失/失败 `success(nil)`。**不消费** `close_small_window`，也不写 `disableActionOpenHomepage`/popupLogicExp，无 dp_status discard。空 items 构造 `interest.second.api.items.empty`/code -1234 并回退 captured 原 model + reload/report。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无该端点与兴趣选择模型（同 FEED-02 锚点）。差异判定见 review 文档 R24。 |
| 8) 证据等级与版本 | 8.89 静态（builder 0x103c6e96c、回执 0x103c6dbdc、各 style 入口地址见上）；当前源码。 |
| 9) 残余不确定项 | 完整回调0x103d87134–875f4已展开：非空结果先weak检查原UI并可写absoluteModel；alive/nil两路都汇入87508共享manager.model写入，之后87538/56c才weak检查helper/reload。共享写不依赖原UI存活，但不能说在所有weak门之前。0x120442e28是swift_once令牌，不是请求epoch。所选body未见账号/请求代际比较；实际跨账号交错仍需运行期（root-static-exposure/feed-residual-closure.md）。 |

### FEED-04 feed/index/story（Story tab）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | `Recommend` URL getter 0x104111fb0 固定 `https://app.bilibili.com/x/v2/feed/index/story`；options 0x104118538 设 GET，`/data` 映射 optional 非 array 的 StoryModel。`SeriesLoader` 另取 `x/v2/feed/index/relate/story` 或 `x/v2/feed/index/space/story/cursor`（kind 分流，主文档“SeriesLoader 参数与响应证据”）。 |
| 2) 触发时机 | Story 请求入口 0x1041152cc 按 tab 分流：tab0 取 feedLoader，`mode byte==1` 且 tab1 取 SeriesLoader。tab0 factory 0x104114e5c 按 `router.scene==tab3` 创建 CircleLoader，否则 RecommendLoader。重载 mode2 直接走 common 0x1041186b0（先检查 `requesting` byte，已有请求则返回，否则置 1）。设置/账号通知的 reload 消费路径见主文档（STLoadBloc.addReloadNotifications 0x1041149e4）。 |
| 3) 请求头 | 公共 HTTP 层同 FEED-01；common 路径设 options/params 后 `BFCApiRequest.initWithOptions`。 |
| 4) 参数及来源 | `params`（0x104111fcc）先取 `BBPlayerPreloadUrlParamsHelper.preloadUrlParams`；mode2 有 focusItem 时用 playerArgs 的 aid/cid/epid、`pgc_info.ogv_style`、trackid/goto、`contain="1"` 及可选 highlight_id；无 focus 时取 router 的 aid/cid/bvid/trackid/material_no/goto。`display_id==1` 才补 router 的 from/from_spmid、commonData.spmid 与 `auto_play="0"`。全局 cold byte 0x12045c548 在构造参数时从 1 消费成 0 并加 `open_event=cold`（不等待 send/ACK）；`pull` 仅 mode4 为 `"0"`，其他含 mode2 为 `"1"`。`network` 按 reachability raw1/2/其他→wifi/mobile/空；`video_mode` 实时取 shared setting；`display_id` 取 loader+0x28；request_from / story_param（query percent decode）/ VBFreeBandwidth 来自各自 helper；非 mode0 取广告 extra，`originalRouterParams` 仍可覆盖 ad_extra。 |
| 5) 签名与编码规则 | 同 FEED-01 公共签名层。 |
| 6) 响应结构 | `/data` → StoryModel（optional、非 array）。成功 0x10411a4bc→0x1041192d0 在处理 payload 前清 `requesting`；错误 0x10411a4ec→0x1041194b0 清该 byte 后 error fanout；weak loader 失效不执行这些更新，此范围未证自动重试。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 无 Story tab 入口（[BiliAPI+Recommendation.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Recommendation.swift) 只有 App 与网页两条推荐路径）。不新增实现；差异不构成本轮实施项。 |
| 8) 证据等级与版本 | 8.89 静态（URL getter 0x104111fb0、params 0x104111fcc、common 0x1041186b0）；当前源码。 |
| 9) 残余不确定项 | 旧待查0x10df56ed4属于HD2而非Story；真实Story params0x104111fcc所选body未见直接disable_rcmd literal，不代表最终请求缺席。原生baseParams11609c68c由BFCApiConst.disableRcmd写该键；完整次序为公共字段→custom覆盖→_authenInreviewParams按in_review覆盖appver/filtered→auth包装补ts/access_key→business options.params覆盖→sign；审核hook所选body不写disable_rcmd。Ktor启用分支从空字典走独立common interceptor，实际attrs/动态字典及9.13最终wire仍需单独证据。originalRouterParams这里只解析后改一个ad_extra值，并非整字典bulk merge。 |

### FEED-05 不感兴趣与撤销（`x/feed/dislike`）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 主文档“不感兴趣的本地操作与请求”记录 HD2 参数 0x10df563d8；NeoBili 使用 `x/feed/dislike` 与 `x/feed/dislike/cancel`（GET 写操作）。 |
| 2) 触发时机 | HD2：卡片三点菜单的本地操作与 `params` 0x10df563d8 条件合入。NeoBili：`HomeViewModel.markUninterested`/`cancelUninterested` 在用户选择理由后调用（[HomeViewModel.swift](../../../NeoBili/Application/Home/HomeViewModel.swift)）。 |
| 3) 请求头 | 8.89 侧走公共 HTTP 层；`params` 内 `mid` 来自 `args.up_id`（UP 主），不是登录 mid。NeoBili 侧由 `AppRequestEncoder` 加 env/app-key、mid>0 时加 `x-bili-mid` 与 aurora eid（[BiliHeaders.swift](../../../NeoBili/Data/Networking/Transport/BiliHeaders.swift)）。 |
| 4) 参数及来源 | 8.89 `params` 0x10df563d8 条件合入 `track_id`、`from_spmid`、UP mid、`rid/tid`、`reason/feedback` 及广告字段；`extraParams` 最后覆盖。NeoBili：`feedbackParameters` 只带 `goto`/`id`（[BiliAPI+Recommendation.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Recommendation.swift)），按 `options.dislikeReasons` 选 `reason_id` 或 `feedback_id`。 |
| 5) 签名与编码规则 | 8.89 同 FEED-01。NeoBili 经 `AppSigner.signed`（排序、`percentEncoded` 保留集 `A-Za-z0-9-_.!~*'()`、空值保留等号、MD5 小写），见 [AppSigner.swift](../../../NeoBili/Data/Networking/Identity/AppSigner.swift)。 |
| 6) 响应结构 | NeoBili 只关心顶层 code，`IgnoredData` 不解析 data；`retries: 0`（[BiliAPI+Recommendation.swift](../../../NeoBili/Data/Networking/Endpoints/BiliAPI+Recommendation.swift)）。 |
| 7) 与 NeoBili 当前实现的差异 | 推荐卡在响应时绑定登录会话和来源参数；不感兴趣及撤销携带 track_id/from_spmid/UP mid/rid，拒绝旧登录代际。未确认 tag_id/广告字段不伪造。 |
| 8) 证据等级与版本 | 8.89 静态（params 0x10df563d8）；当前源码。 |
| 9) 残余不确定项 | 8.89完整builder0x10df563d8–56980已逐键核：id/goto始终写入（nil转空）；reason_id/feedback_id/mid/rid/tag_id/ad_cb/from/cm_reason_id/from_spmid/from_module/nature_ad/track_id各自length>0才写。extraParams.count>0时5691c最后bulk覆盖，可替换此前任意同键。9.13不同反馈类型是否必需各字段仍需线级样本（root-static-exposure/feed-residual-closure.md）。 |

### FEED-06 推荐点击事件（Neuron / 旧链 001365）

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | 事件 ID `[from_spmid_v2].main-card.0.click`（click wrapper 0x10df30338 生成，0x10df31728–0x10df31784），经 Neuron 通道发送（传输见 LOG-01）；同一次 track 后还发旧链 `001365`。NeoBili 侧事件常量 `tm.recommend.main-card.0.click`、logId `001538`（[RecommendationClick.swift](../../../NeoBili/Data/Networking/Reporting/RecommendationClick.swift)）。 |
| 2) 触发时机 | HD：`MainV2VC.didSelect`（0x10df3e318）先对 bangumi_rcmd 卡路由后调 `HomeData.reportCardClick`；其他卡走 superclass，`super` 在 cell 支持 jumpDetail 时调用；只有 cell 精确类名属于 LargeCoverV1Cell/SmallCoverV1Cell/SmallCoverV9Cell/SmallCoverV5Cell 白名单（0x10df18c40）才调 HomeData 点击报告。NeoBili：真实视频 Button 的 action 调 `RecommendationClickReporter.record`（[RecommendationClick.swift](../../../NeoBili/Data/Networking/Reporting/RecommendationClick.swift)），点击记录异步执行、路由不等待上传。 |
| 3) 请求头 | Neuron 通道的请求头见 LOG-01（`Content-Type: application/octet-stream`、可选 `Content-Encoding: gzip`、`Neuron-Events`）。NeoBili 点击上报用 `DeviceIdentity.appRequestHeaders`（buvid/session_id/x-bili-trace-id 等，[AppDeviceProtocol.swift](../../../NeoBili/Data/Networking/Identity/AppDeviceProtocol.swift)）。 |
| 4) 参数及来源 | HD 通用报告器（0x10df30fd8）22 个默认扩展键：event/style/param/title/goto/sub_goto/sub_param/page_from/page_id/from_type/state/up_id/rid/tid/type/track_id/converge_type/extra_info/card_type/card_rel_id/card_material_id/position；字符串 nil 退空，args 数值转十进制；`track_id` 优先非 nil 的 `report_args.track_id`（空串也保留），否则 `report_track_id`；`position` 取 `report_flush_idx`；`extraDic` 最后覆盖。`style` 仅在 `page_from` 严格字符串 1 时取 `FormatManager.getPegasusStyle`。旧链 001365 另组 14 字段并重新读 getter、不合 extraDic。NeoBili：`RecommendationClick.make` 合并 `track_id`/`event=card_click`/`event_policy=0`/`page_from=1`，限制 40 项、单值 ≤4096 bytes（[RecommendationClick.swift](../../../NeoBili/Data/Networking/Reporting/RecommendationClick.swift)）。 |
| 5) 签名与编码规则 | Neuron 分帧：`RDIO` + 4 字节大端长度/标志 + 校验字节 + body；元信息 `单字节 key 长度 + key + 4 字节大端 value 长度/标志 + value`；value 长度最高位表示还有下一项，外层长度最高位表示含元信息。NeoBili 在 [AppBehaviorEncoder.swift](../../../NeoBili/Data/Networking/Reporting/AppBehaviorEncoder.swift) 实现同一分帧，并按需 gzip（[AppBehaviorEncoder.swift](../../../NeoBili/Data/Networking/Reporting/AppBehaviorEncoder.swift)）。 |
| 6) 响应结构 | Neuron `didFinishTask`（0x1161ed618）仅在无 error、响应为 HTTP 且 status=200 时删缓存，不在该层解析 body；status=449 或 500–599 先 `handleFlowControl` 再更新缓存，其他失败直接更新缓存。NeoBili 的 `APIClient` 接受 HTTP 200–299 并检查可解析响应的 code（review 文档 R12）。 |
| 7) 与 NeoBili 当前实现的差异 | 事件 ID 与 logId 不同（HD 为 `[from_spmid_v2].main-card.0.click`，NeoBili 固定 `tm.recommend.main-card.0.click`）；NeoBili 只抽取部分根字段与 `args.tid/rid`，保留选定 `extra_rpt_fields`；只对普通视频卡发送（直播/图文不发）；缺 track 卡不发送；字段上限 40 项/4096 bytes。见 review 文档 R08/R09/R12。 |
| 8) 证据等级与版本 | 8.89 静态（0x10df30338、0x10df30fd8、0x10df315a4、0x10df316b8、0x10df18c40、0x10df317d8–0x10df31a2c）；当前源码。 |
| 9) 残余不确定项 | 已识别8.89 HD whitelist/HomeData generic、Swift UI→CardViewModel witness→SmallCoverV2专属click与实际ExposureV2 show/duration链已列，不等于全卡型同字段；14类型构造policy表不替代所有专属reporter schema。未识别卡型与当前9.13 golden不在有限已定位链覆盖内，需要后续同版本事件证据；NeoBili队列补发差异另见R12/R17（root-static-exposure/final-feed-heartbeat-tail.md）。 |

### FEED-07 曝光与逐段可见时长事件

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | HD real show（0x10df3083c）构造 `tm.recommend.feed-card.0.show` 并 `trackInstantly`；时长回调 0x101b6cf80 发 `tm.recommend.feed-card.duration.show`（policy=1）。普通 show 走通用报告器（与 FEED-06 同族）。 |
| 2) 触发时机 | 普通 show 由 `BBListExposureManager`（0x103eb3744）按可见比例检查：单项检查 0x103eb523c 要求非空 identifier、view 存在且未 hidden、alpha>0、有 superview、非空 bounds 与 intersection；比例 = 交集宽/自身宽 × 交集高/自身高，`>=` 阈值才 `exposedIn:item` 并加入 identifier pool。Swift `RealExposure`/`ExposureV2.Manager`：raw policy=3 时可见比例 `>= startRatio` 建 Context 并存 Date.now，已有 Context 在比例 `< endRatio` 时移出池并结算（等于阈值保留）。 |
| 3) 请求头 | 同 Neuron 通道（LOG-01）。 |
| 4) 参数及来源 | HD real show 九个默认键：card_type/card_goto/goto/param/track_id/position/card_rel_id/card_material_id/is_background，extraDic 仍覆盖默认值；`track_id` 要求 `args.track_id.length>0` 才用，否则 `report_track_id`；`getAppstate`（0x10df31b44）每次读 `UIApplication.applicationState`，raw0/1/2 分别映射 String 2/3/1，其他空。时长事件：`durationDelegate` 结算 0x103eb9998 要求 `elapsed>=minimum`，通过才回调；回调 0x101b6cf80 复制扩展字典，把两端 DateUnix×1000 有边界检查地向零截断为 Int64 十进制 `card_start_time`/`card_end_time`，再发 `duration.show`，未单独添加 duration 秒字段。 |
| 5) 签名与编码规则 | 同 Neuron 分帧（FEED-06）。 |
| 6) 响应结构 | `RealExposure` 从 MainConfig 读 `exposure_duration_start_ratio`/`end_ratio`，缺失或类型错误各默认 0.8；`exposure_duration_min_ms` 读 Int 后除以 1000，默认 0 秒；普通展示比例 `visible_area/100` 默认 0；`durationRematchEndWithNonActive` 默认 true。后台 observer 枚举值：raw36=willResignActive、raw33=didEnterBackground、raw37=willTerminate；raw33/raw37 都调用结算 0x101b60e7c→Manager 0x103eb9294，raw36 受 `durationRematchEndWithNonActive` 控制才结算。 |
| 7) 与 NeoBili 当前实现的差异 | 已实现展示去重和逐段时长、MainConfig 阈值解析与可见交集面积计算；后台/页面离开结算。去重池标识/容量仍是本地策略，未声称完整复刻官方清池生命周期。 |
| 8) 证据等级与版本 | 8.89 静态（0x10df3083c、0x10df31b44、0x103eb3744、0x103eb523c、0x103eb9998、0x101b6cf80、0x101b60644）；当前源码。 |
| 9) 残余不确定项 | 普通首页V2主链已补（root-static-exposure/home-exposure-findings.md）：SmallCoverV2 show raw5经delegate得到raw1，duration raw3；raw8仅check/settle duration，非全show reset。VC viewWillAppear raw1→dispatcher→RealExposure已注册弱callback→provider/root存在时新Manager替换，正证重建show池。显式Manager+90清字典实现存在，Search/Live真实owner亦已读未见该caller。所选14卡Items与witness已核：raw1/2入池，raw4直接比例callback不入池；Banner/Notify的额外策略接子卡/轮播timer而非duration（home-policy-owner-continuation.md）。其它间接caller继续有限覆盖；不能把它与T17兴趣marker或Neuron event_policy混用。9.13规则、多实例实际监听/交错仍另验。 |

### FEED-08 兴趣选择曝光、点击与提交事件

| 字段 | 内容 |
| --- | --- |
| 1) 端点/服务方法 | Neuron 事件族（非独立 HTTP）：`interest.0.show`、`interest.0.click`、`main.interest-select.submit.0.click`、`three-point.0.show`、`main.interest-select.client.0.show`。 |
| 2) 触发时机 | T37 首屏 willDisplay 0x103d8de8c→0x103d9d094 按 section 取 Gender/Age 或 `current model.items`，`Item._isExposed` 为 true 时省事件，false 才发并随后置 true；S1/S2 child 的 willDisplay 各有独立入口（0x103d9293c→0x103d9e350、0x103d970bc→0x103d9e988）。S2 菜单 show helper 0x103d97adc 要求 `model` 存在且 `show_skip_three_point` 字节恰 1 才发 `three-point.0.show`。T33 提交后发 `main.interest-select.submit.0.click`（0x103d48c0c）。 |
| 3) 请求头 | 同 Neuron 通道（LOG-01）。 |
| 4) 参数及来源 | T37 首屏 `interest.0.show` 六 String：interest_name/interest_id/pos/style/unique_id/strategy；`pos` 用 `current model.items` 的 NSObject equality 搜索 first match+1、missing 0，不是物理 index。S2 child show 九 String，`interest_pos` 取 display selected parents 数组的 first equal 位置+1，`sub_interest_pos` 取全 model 扁平 child 数组的 first equal 位置+1。S2 child click 十 String，parent pos 与 child pos 分别在不同数组里查找（show/click 子位置可不同）。T33 submit 的 base 八字段：interest_id_list、interest_list、interest_pos_list、content_cnt、extra_select、style、unique_id、strategy。 |
| 5) 签名与编码规则 | 同 Neuron 分帧；三列表均经 Set<String>→array→JSON（0x100066c38/0x103d9cae8/0x103d6f200），去重且不保证 tap/server 顺序。 |
| 6) 响应结构 | 事件入队返回 true 只表明 operation 已入队，不是磁盘或上传成功。 |
| 7) 与 NeoBili 当前实现的差异 | NeoBili 首页无 `interest_choose` 模型、无兴趣选择 UI 与对应事件（review 文档 R24）。 |
| 8) 证据等级与版本 | 8.89 静态（上列各入口地址）；当前源码。 |
| 9) 残余不确定项 | Item与SubItem标记必须分开：Item槽120443a70、setter103c797c0正确；初始化103c799bc写false，16个所选槽候选展开得到11个业务true store及2个读/分支候选（已知writer helper调用在另一items-array分支，false门本身进入inline special-interest，不能概括为false直接delegate），未在这些寻址形式找到已有Item false重置，不能推广动态setter/硬编码offset全局不存在。SubItem正确槽120443b68、setter103c79ea0；T17确认→103ce77f4遍历已有sub_items于7cb0/7cdc写false，15个业务true写者另已核。该正例不替代Item调查，也不推广首页/9.13；账号实际交错、其他对象替换和动态writer仍分开验证（root-static-exposure/feed-residual-closure.md）。 |
