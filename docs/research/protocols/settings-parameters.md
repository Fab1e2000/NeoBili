# 功能、设置与首页请求参数

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 功能、设置与首页请求参数

此专项核对 NOTSURE 中的当前策略，保留9.13抓包结论与8.89静态分支的版本边界。
下表“相容”仅表示所选场景可生成该值，不证明官方值恒定，也不直接要求改变生产策略。
Swift MainApi.params（0x101a32340）先读实例 self+0x18，非 nil 直接返回；首次才
调用 builder 0x101a3239c 并缓存。MainVM refresh/loadmore 新建 API，故下面状态
读取发生在新实例首次构造参数，不能概括为同实例每次 getter/重试都会重新读取。
getApiOptions（0x101a3204c）取缓存 params、桥接 NSDictionary 后 setParams，
传统公共构造层随后按前述规则合并。builder 已读尾部可选键没有任意 extra 字典
覆盖这些设置字段；但中段 preloadUrlParams 已证会覆盖此前生成的同名业务值：
0x101a32f10 桥接 incoming 字典，0x101a32f18–0x101a32f48 交给 merge
0x101a34414，碰撞分支 0x101a34528–0x101a34544 释放旧 value、存 incoming value。
该 specialized body 的碰撞段没有调用传入 closure，不能仅按 closure 推定旧值优先。
完整公共/Ktor 后置覆盖仍需逐项核对。

| 参数 | 功能与来源 | 操作、保存 | 生成、读取及复用 | 8.89最终字段证据 | 当前策略对照 | 仍缺证据 |
| --- | --- | --- | --- | --- | --- | --- |
| auto_refresh_state | 自动刷新，用户设置/设备配置 | 设置页数组开3关4；didSelect 0x10f2f5fd8→updateAutoRefreshState 0x113ceea74，写 cachedConfig.autoRefreshState.value，再 uploadConfig | getter 0x113cee9d8 缺省/unsigned值<=1退1，否则保留；isOpen仅1/3；新API首建读 | 0x101a33808→UInt.description，赋同名键 | 固定4与明确关闭相容，默认1/重新开3不是4 | uploadConfig磁盘/账号边界、公共覆盖 |
| inline_sound_cold_state | 持久声音偏好与用户是否处理设置 | 音量设置开3关4，0x10f2f5e2c→0x113cee934；1/3写inlineVolumeOn=true，3/4写hasHandledVolumeSetting=true | getter 0x113cee8ac：未处理开1/关2，已处理开3/关4；动态Bool setter更新RAM与NSUserDefaults，新API首建读 | 0x101a33680→UInt.description | 固定4与用户处理后关闭相容，不等同默认2 | 默认配置、与实时mute同步、公共覆盖 |
| inline_sound | 实时静音/系统输出音量，播放状态与设备状态 | BBPegasusInlinePreferences.mutePlay setter 0x11419f388 更新RAM/KVO/通知，未写上述偏好；init仅首次读inlineVolumeOn反转 | 进程singleton，mutePlay=true→1；false且AVAudioSession.outputVolume>0→2，否则3；新API首建读 | 0x101a33574–0x101a33650 | 固定1仅与mutePlay=true相容，不能将cold_state=4直接当实时状态证明 | mute UI/通知同步链、账号复用、公共覆盖 |
| inline_danmu | 首页弹幕，用户偏好及服务器同步 | BBPlayerDanmakuPreference的动态Bool，经BFCPreferences写RAM/NSUserDefaults；active Service.updateDanmakuSwitch再发paramType15同步；服务器也可覆盖 | 内建默认true；true→2/false→1，对象nil省略；新API首建读 | 0x101a33764–0x101a337d8；默认0x1147e5398，写0x114203fe8，同步0x1147e7ad8 | 固定2与默认/开关true相容 | 首页具体UI绑定、账号边界、公共覆盖 |
| voice_balance | 音量均衡，用户偏好/PlayConfig | setter写BoolValue.value、setVolumeBalance，再uploadConfig；设置页switch selected经type37调用setEnableLoudNorm | getter优先cachedConfig.volumeBalance.value，缺失取defaultConfig；内建默认true；true→1/false→0，对象nil省略；新API首建读 | 0x101a338f8–0x101a3396c；getter0x1147f062c，默认0x1147eecd8，setter0x1147f0704，UI0x10f31bb48 | 固定0仅与显式关闭相容，内建默认产生1 | upload持久化/账号/服务器更新、公共覆盖 |
| autoplay_card | 首页自动播放，用户/设备/服务器影响 | UI模型all10/WIFI3/off4；设置页0x10f2f58ec→updateInlineSetting 0x113ced8f4，写DeviceConfig.autoPlay.double_p及server标志，再upload/通知，无重启门槛 | 底层off1/WIFI2/all3，在server=false时生成4/3/10，true时2/1/11，缺省0；合法0/1/2/3/4/10/11最终保留，非法兜底11；新API首建读 | 0x101a32e38→0x1035ab340→0x101a482b8，表0x1182c91e0→Int.description | 固定4与用户明确关闭相容，不是官方全场景常量 | UI数组装入、upload持久化/服务器更新、公共覆盖 |
| column | 布局，用户/账号/设备/服务器影响 | manualUpdate仅3/4，登录写Mid配置；Device把1/3归底层1、2/4归2，另写server标志并通知 | 登录取Mid，未登录取Device；Device底层1生成server1/用户3，底层2生成server2/用户4；最终unsigned<5保留否则0，新API首建读 | 0x101a32700→0x1035ac8ac→currentColumnSetting，再Int.description | 固定4与显式双列采集及关闭server标志相容，码不是实际列数 | 布局UI/flush通知链、磁盘与账号切换、服务器写入、公共覆盖 |
| video_mode | 视频播放样式，用户/账号偏好 | 设置页item.type赋UI.value，didSelect加10；manual仅11/12，登录写MidConfig.playMode并upload，所有状态写list_setting_userDefaults的kBBListPlayTypeKey并通知 | 登录读Mid，缺省0；退出读NSUserDefaults非零值，否则-1；新API首建直接Int.description，不减10 | UI0x10f2f3b04/0x10f2f5c98；manual0x113ced0b4，保存0x113ced234/0x113ced2d4；字段0x101a339a0–0x101a339c8 | 固定1不能等同用户明确选择11；选择码与请求码要保留 | model标题/服务器默认、账号切换通知消费、公共覆盖 |
| recsys_mode | 推荐/关注feed模式，用户及DeviceConfig | 设置页value1传1，value0且当前关注时传2；setter输入1写底层mode2，其余写1，同值跳过，变化upload并通知 | getter底层==2生成1，其他0；Swift isFollowFeedMode→字符串1/0，新API首建读 | UI0x10f2f5aec–0x10f2f5ba8；setter0x113cee678，getter0x113cee5c0；字段0x101a32d8c–0x101a32e04 | 固定0相容推荐模式，关注模式为1 | model标题/默认、账号持久边界、通知刷新与公共覆盖 |
| disable_rcmd（公共参数） | 个性化推荐开关，用户偏好 | 设置selected取disable的反值；tap要求permission_url.rcmd_info存在，当前disabled时直接开启，当前开启时确认后才禁用；默认false，BFCPreferences动态Bool写RAM/UserDefaults | KNetParamModule缓存service，OtherNetParam每次仍读getDisableRcmd；Bool false/nil→0、true→1 | 数据模型0x10f321ad8；action0x10f2f1fb8/confirm0x10f2f2384；native getter0x1000b3e08，Kotlin0x10aac5910 | 不能把默认0与用户确认后的1等同；公共项不是首页builder中的常量 | 最终公共合并覆盖、账号/服务器变更 |
| client_attr（preload） | Dolby/HDR优先，用户、实验与VIP共同影响 | 设置QualitySettingDatas把priorityUseDolbyHDR作switch selected/type50；通用action→setPriorityUseDolbyHDR。player.priority_hdr_842 preset0未命中时setter不写；命中且变化才写CloudPlayConfig/upload；默认false | getter同实验门控，preload再检查有效VIP；仍受preload字典合并时点影响 | UI0x10f312df8/0x10f31bb88；setter0x1147f0adc；preload0x114398220–0x114398270 | 固定1不能等同默认，也不能只凭设置开就保证该bit | upload/账号边界、其他bit与设备能力 |
| qn_policy（preload） | 自动画质，用户播放选择/持久偏好 | BFCPlayerSettingsPreferences.autoQnEnabled默认true；updateUserQn:isAuto接受后写原isAuto，manual不满足shouldMemoryQn则早退 | preload→QualityHelper.autoQualityEnabled→共享偏好，Bool→字符串1/0 | 0x1143980b8–0x1143980e0；getter0x114820fc4；默认0x114faf598；写0x11453b1ec | 只与实际偏好值对照，不能推为设备/网络恒定能力 | isAuto具体UI来源、manual保存门槛、其他覆盖 |
| https_url_req | HTTPS播放地址，用户本地偏好 | OtherSettingDatas用httpsPlayurlEnabled填selected/type10；通用switch Bool→DataManager.setHttpsPlayurlEnabled；默认false，BFCPreferences动态Bool保存 | 新API首建读共享偏好，非nil生成0/1，nil省键；在preload合并后赋值，覆盖同名项 | UI0x10f314778–0x10f314820；写0x10f31bb80，默认0x114faf4fc，字段0x101a33398–0x101a33424 | 固定0相容默认/关闭；打开可为1，无重启要求 | 服务器/账号其他写入、呈现条件 |
| guidance | 卡片/加载更多引导，本地展示标记 | LocalPreferences动态Bool，BBPhonePegasusConfig suite；defaultConfig两个标记均false；UI写true待追 | 新API首建读hasShownGuideTapCard，true才再读hasShownGuideLodeMore；公式!(tapShown&&loadMoreShown) | 默认0x101b8a9e8/0x101b8aa78；字段0x101a33464–0x101a33548 | 固定1相容任一未展示/缺存默认；两项都true才0 | UI写入、清理、账号边界 |
| teenagers_age（公共参数） | 青少年年龄，账号偏好/服务器状态 | PasswordVC status11设置流程仅成功回调才Manager.setAge；同步状态也可覆盖。Prefs动态Int64，常规suite含account.userID；defaultConfig无age | SignHelper.baseParams每次Const→wrapper/manager→Prefs.age→NSNumber.stringValue写公共键；未见16常量 | 公共0x11609c68c/0x11609cac4–0x11609cb00；保存0x115961ebc；成功0x1159777d0 | 固定16缺来源证明；选择器defaultIndex16对应年龄17 | delegate/确认绑定、shared账号重建、缺值动态getter与公共优先级 |
| player_net（preload） | 网络可达状态，系统状态/进程缓存 | BFCReachability监控www.bilibili.com，初status0，异步更新；变化写status并通知，无这条链用户存储 | preloadDevice首次缓存能力项，但每次重写player_net；WiFi1/WWAN2/其他reachable0/不可达3，新API首建merge，同APIparams仍缓存 | 0x114a0c368–0x114a0c430；status0/1/2判断0x1161baf4c/0x1161baf94/0x1161bafdc；merge0x101a32f48 | 固定1只相容当次WiFi；初始异步尚未完成可能3 | 底层仅0/1/2，0分支可受独立读取间状态变化影响；其他public覆盖 |

系统Reachability0x1161e4ea8读取flags失败为0，成功交0x1161e4d84：reachable bit1
未设为0；已设且connectionRequired bit2未设为1，或自动连接bit3/5且无需干预bit4为1；
WWAN bit18设则覆盖2。因此底层正常输出仅0/1/2，player_net的“其他reachable→0”
不能当稳定第四网络类型；三次Bool独立读状态，更新交错可走到该分支。
首页另有network：0x101a32640单次同源status读取，1→wifi、2→mobile、其他空字符串；
早于preload player_net，异步变化可能使同批两个字段不同，同API缓存限制仍适用。

red_point由启动保存状态决定：GPPushNode.setup0x10f6d36f8保存launchOptions远程通知
是否非nil和当时系统角标到BBCPush的bootByNotification/bootBadgeNumber（RAM）。
MainApi0x101a3251c仅非通知启动、bootBadge>=1且MainApiMarker.+10计数为0才写角标
十进制，非请求时实时角标。Marker初始化0x101a35678计数0；订阅dispatcher key22，
首payload可cast OptionalError且nil才0x101a35058清状态并计数+1，错误不消费首次。
VM 响应入口 0x101a5b04c 在 swift_once 完成后，先读全局 byte 0x12106a634
（0x101a5b080）并与入参 w0 bit0 比较（0x101a5b084–08c），不等则直接返回；
相等后才以 w4 bit0 分 error/nil 两支 key22，分别在 0x101a5b0ac 与 0x101a5b1a4。
因此撤回 task-37 的“唯一门禁为w4”及据此对全族 reset/账号调用方的否定。
全局 byte writer、w0 的业务含义及任务复用须继续追；原始证据
`DerivedData/Validation/root-static-audit/recovery/0x101a5b04c.asm`。

widgets来自系统WidgetCenter配置。Marker初始OptionalString=nil；后台通知接
0x101a35724，iOS>=14调用getCurrentConfigurations。成功0x101a358e4按返回顺序取
WidgetInfo.kind，逗号join保存Marker+58/+60，不读family/intent、不去重；零组件写空串，
失败保留旧值。MainApi0x101a33aac有值才加入widgets，nil移除键，因此未加载省略与
成功空串不同。旧API缓存不更新，新API读当时状态；不是首页player_widget，冷启动请求前一定读取未证、该串 NSUserDefaults 持久化未見（下一步 `disassemble 0x101a33aac 0x101a33b60`）。

禁个性化推荐还有设置页以外的明确writer：PersonalizeGuidance setup
0x101b59418把onOpen ivar0x120358518绑定weak-self closure0x101b5f560→
0x101b59ca0。实际openButton ivar0x1203585a0经Rx事件raw64
（0x101b5b364）订阅0x101b5fe88→0x101b5b85c，onOpen非nil才BLR
0x101b5b8c0；callback发送open_button动作/toast后调用
setDisablePersonalizedRcmd=false（0x101b59dcc）。这是用户推荐引导动作，不是
账号或服务端自动重置。
外层creator0x101b57d70在force bit=false时检查0x101b59164：已有guideView
isShowing则拒绝；latestConfig.enable_rcmd_guide必须存在且Bool true、用户
disablePersonalizedRcmd必须true、guideConfig非nil、today count<max_show_count，
并通过关闭冷却0x101b58a44。force=true只绕开该helper，仍需guideConfig及
guideType.lowbyte!=0。raw1冷启动show0x101b594bc另外检查RAM hasShownForCold，
因此force也不绕过它；安排BBSerial priority1/event0x101b5f528→0x101b5a21c，
成功展示后0x101b5a59c才设true，init0x101b57be0设false，不把它称磁盘标记。
非cold show0x101b59628仍需要application window，未保证每次请求展示都完成。
展示计数0x101b58548按当前Date的yyyy-MM-dd key把今日count+1，保留close字符串；
shared helper0x101b57938经yy_modelToJSONObject/字典cast→LocalPreferences
singleton0x120359f78→setPersonalizeGuideInfo（0x101b57a2c），不是HTTP成功。
close callback0x101b5f568→0x101b5a0ac报告close_button，再0x101b58854仅在
close_show_interval>=1时保存今日字符串PegasusPersonalizeStartDayAfterClose，
保留计数字典并用相同持久调用；zero/negative不写marker，没有禁个性化setter。
jump callback0x101b5f570→0x101b5a14c报告panel事件并processUrl
personalized_rcmd_page，也不在该body写偏好。
冷却helper0x101b58a44在config nil、interval<1、close字符串空时允许；正常
eligibility此前仍要求config非nil。非空关闭字符串用yyyy-MM-dd解析
（0x101b58bb8），解析失败退当前Date（0x101b58dac），随后加systemTimeZone
对应secondsFromGMT（0x101b58e14/0x101b58e38）。正interval经UInt→Double
原值交Date.addingTimeInterval（0x101b58ed4/0x101b58edc），**未乘86400**；
再格式化/解析为日期，比较targetDate>today（0x101b59130），返回取反允许
targetDate<=today（0x101b58b88）。不能据字段名把interval写成天数或精确墙钟
冷却时间；malformed日期走当前日期fallback，不直接无条件允许。
Story STLoadBloc.addReloadNotifications0x1041149e4→0x10411431c注册账号
action type1（0x1041143dc）及update type2/triggerImmediately0
（0x104114460），并观察BFCAppPreferences.shared的disablePersonalizedRcmd
keypath0x1183cc3d8。publisher0x105011644/raw options5后经过Bool处理链
0x1050fc84c/0x1050d0154，再sink0x104114c30→0x10411498c；这些框架operator
**Combine operator 已命名（team-c39 取证）**：0x1050fc84c = `drop(_:)`（Publishers.Drop，SkipCount/SkipCountSink 元数据 0x1050fc894→0x1050fc8e0）、0x1050d0154 = `removeDuplicates()/distinctUntilChanged`（DistinctUntilChanged nominal，链 0x1050d01f8→sub_1050D02B0）；setter 真实入口 0x1167d34cc（0x1167d3520 只是其中段），**其 ObjC selector 名静态不可命名**（无符号，find_pointer_refs/find_callers 均空）。preference callback忽略incoming Bool，weakself存在才调用
reloadIfNeed0x104114738/raw4；account update0x104114934走raw2。两者没有写
该偏好。layout helper0x1040be894比较weak mainVC与router.navigationController
topVC（NSObject equality0x1040be970），相等才立即0x104114a80 reload，不相等
只存reloadType byte（0x104114914）；不是foreground通知。reload在landscape
先转portrait，再0x1041152cc/raw2/tab0，currentTab==1追加tab1
（0x104114b80）。延后reason由onViewDidAppearWithPushed
0x104114df4→0x104114dac消费：mode byte==1、pushed false、reloadType!=0才
reload后清0（0x104114e30/0x104114e34）；stored raw4/raw2可通过，raw0 login
与清除sentinel同值而不通过此非零门禁。实际load mode仍raw2，不把reason当wire
mode。loader若正在requesting可拒发，实际网络路径见后续独立核对。这是设置/
账号通知的请求消费路径，不证明偏好按账号分区或清理。


Story实际请求入口0x1041152cc按tab分流：tab0取feedLoader；mode byte==1且tab1
取SeriesLoader。tab0 factory0x104114e5c按router.scene==tab3创建CircleLoader，
否则RecommendLoader（class0x12045c590）。Recommend虚表+c8
0x12045c658→0x104111b9c，仅mode0且sharedResourceId非空可走快速路径；
上述重载mode2直接common0x1041186b0。common先检查requesting byte，已有请求
则返回；否则置1（0x1041187e8），options/params→setParams（0x10411893c），
BFCApiRequest.initWithOptions（0x104118960），completion/error handler，
再requestAsync（0x104118ad4）。这证明可用loader的异步请求调用，仍不等于实际
HTTP已经发送或成功。成功0x10411a4bc→0x1041192d0在处理payload前清requesting
（0x10411938c）；错误0x10411a4ec→0x1041194b0清该byte（0x1041194f0）后
error fanout。weak loader失效不执行这些更新，此范围未证自动重试。
Recommend URL getter0x104111fb0固定https://app.bilibili.com/x/v2/feed/index/story；
options0x104118538设GET，/data映射optional非array StoryModel。
params0x104111fcc先取BBPlayerPreloadUrlParamsHelper.preloadUrlParams；mode2
有focusItem时用playerArgs aid/cid/epid（缺playerArgs数值0）、pgc_info.ogv_style
（缺0）、trackid/goto、contain="1"及optional highlight_id；无focus则取router
的aid/cid/bvid/trackid/material_no/goto。display_id==1才补router from/from_spmid、
commonData.spmid和auto_play="0"，不是按mode2恒定补。全局cold byte0x12045c548
在构造参数时从1消费成0并加open_event=cold（0x104113858–0x1041138ec），
不等待send/ACK；pull仅mode4为"0"，其他包括mode2为"1"（0x1041138f4）。
network按reachability raw1/2/其他→wifi/mobile/空（0x104113980），video_mode
实时取shared setting（0x104113a64），display_id取loader+0x28。request_from、
story_param（query percent decode）、VBFreeBandwidth字段均来自各自helper。
非mode0取广告extra，随后originalRouterParams仍可覆盖ad_extra。此函数未证直接加disable_rcmd（覆盖次序需 `disassemble 0x10df56ed4 0x10df575e4` 复核）；共享preload/public参数不能在此当作空或固定值。

### SeriesLoader 参数与响应证据

Series factory0x104115130读STCommonData.tag ivar0x12045aff0
（0x1041151f0）→loader kind+0x28（0x104115260）。mode2同样直接common；
仅mode0/kind4可能cache fast path。URL0x10411a640按kind4取
https://app.bilibili.com/x/v2/feed/index/relate/story，其余取
https://app.bilibili.com/x/v2/feed/index/space/story/cursor；kind4 options额外
cacheValidLife=600.0、ignoreCache=false（0x10411a69c `cmp #0x4`、0x10411a6a0 `b.ne` 跳过；
0x10411a6ac 载 selref `setCacheValidLife:` 并组装双精度立即数 mov #0xc00000000000 +
movk #0x4082,lsl#48（=600.0），0x10411a6bc 调用；0x10411a6c0–0x10411a6d0 载 selref
`setIgnoreCache:` 且 w2=0）。URL 同一 kind 门禁：0x10411a668 `cmp #0x4`、0x10411a66c/0x10411a670
两次 csel 在 relate/story 与 space/story/cursor 之间选择，0x10411a674 `orr #0x8000000000000000`
把 C 字符串指针转成 Swift 大字符串。三个 IMP 登记在 __data 的配置表 0x12045ca78
（+0x00→0x10411a640、+0x10→0x10411af6c、+0x18→0x104119580、+0x30→0x10411af68，其中
0x10411af68 是 `b 0x104118064` 尾跳）。**producer 边界**：ASCII 串 `requestWith:config:`
在本镜像共 5 处，其中唯一落在选择子区段的是 __objc_methname 的 0x11a294923，
另外 4 处（0x2702ff8e、0x27030ae1、0x27030e3b、0x2c4323d0，非任何 section 覆盖的
__LINKEDIT 区域）分别是 `-[RecommendLoader requestWith:config:]`、`-[STLoader …]`、
`-[STSeriesLoader …]` 符号名与 `sel_requestWith:config:` 符号名，不构成调用点。
全 section 8 字节对齐扫描 0x11a294923 的指针只命中 __objc_data 的四个方法表项
（0x11fe2c820 等 = name/types/IMP 三元组，types 0x1178a46e0，对应 RecommendLoader/
STLoadBloc/STLoader/STSeriesLoader），__objc_selrefs 中没有该选择子的槽位，即本镜像内
没有 `requestWith:config:` 的 objc_msgSend 调用点；该配置表 0x12045ca78 也没有代码
ADRP+LDR/ADD 引用。**随包二进制已排查**：从 `bili-universal_8.89.0.app.zip` 解出的
`Frameworks/BilibiliVideoTools.dylib`（12,486,320 B）与 `Frameworks/BGM.framework/BGM`
（2,779,328 B）内既无 `requestWith:config:` 字节串也无 `STSeriesLoader`/`STLoader`/
`RecommendLoader`/`STLoadBloc` 类名（仅静态字节扫描，未运行任何解出文件；BilibiliVideoTools
为随包第三方 dylib，按样本边界声明不能用于提升证据等级），因此该调用方不在这两个随包
二进制里，只能在主镜像内经间接派发（Swift witness/vtable 或运行时构造 selector）或来自
系统框架，属精确残余（下一步命令见 findings 的 S-2）。

**该 producer 已闭合（本轮，S-2 撤销）**：`requestWith:config:` 之所以没有 selref/stub，
是因为**唯一的生产者直接 BL 同一 Swift 方法体**、不经 ObjC 分派：
`-[BBPhoneMPStoryFeedVC loadStoryCards]` 0x1132e13b8 / `-[… loadMorePage]` 0x1132e20a4 /
`-[… refreshStoryCards:anchorItem:]` 0x1132e27bc → `_objc_msgSend$loadBlocRequest:`（0x1173f9de0）
→ `-[BBPhoneMPStoryFeedVC loadBlocRequest:]` 0x1132e6728 → `_objc_msgSend$requestWith:tab:`
（共享 stub 0x1174f2ec0）→ `-[STLoadBloc requestWith:tab:]` 0x104115284 →
`sub_1041152CC`（0x1041152cc）。该函数在 0x104115358 `bl sub_104E4231C` 取一个 lazy 全局
Bool（初始化器 sub_104E422C0：立即数装配 15 字符小字符串
`0x6666/0x755f/0x696e/0x6574` + `0x5f64/0x7473/0x726f/0xef79`（末字节 0xEF=0xE0|15）
= **`ff_united_story`**，再 `[BFCMemexABTest hitExperimentalGroupForKey:presetHitValue:]`
（sub_11649C3D0，preset=0）写全局字节 0x121072f53），随后 0x10411535c `ldrb w8,[x0]`、
0x104115360 `cmp w8,#1`、0x104115364 `ccmp x22,#1,#0,eq`：**仅当该 Memex 开关==1 且 tab==1**
才走 0x104115380。命中后 0x104115380 `bl sub_1041150BC` 取 lazy `seriesLoader`
（ivar `_OBJC_IVAR_$__TtC5Story10STLoadBloc.$__lazy_storage_$_seriesLoader` 0x12045c6c8，
factory `sub_104115130` 即前述读 STCommonData.tag→kind 的 Series factory），
0x104115390 `bl sub_10411AF6C`——这个 0x10411af6c **就是 `-[STSeriesLoader requestWith:config:]`
（0x10411b2c4）在 0x10411b300 所 BL 的同一个 Swift 方法体**（self 在 x20；入口 0x10411af8c
`cbnz x0` 要求首参为 nil、0x10411af94 `ldr x8,[x20,#0x28]`+`cmp #0x4` 要求 kind==4）。
因此 kind4 relate/story 请求的真实触发条件与归属是
「Phone 故事流 VC 的三个加载动作 → STLoadBloc+Memex`ff_united_story`+tab==1 → 共享方法体」，
selector 无调用点是**直接调用方法体**造成的，不再列为残余。
Series params0x10411a6e4先补preload/质量/network/翻译状态/免流字段，再按kind
0/1/2/3/4/5调用空dict/0x10411b36c/0x10411bef0/0x10411c87c/0x10411dee0/
0x10411d4fc。kind4 helper要求current item/playerArgs；缺失返回空dict，存在加
aid=avid decimal、trackid（nil空）、当前commonData spmid/from_spmid（nil空）、
view_attribute="0"及arc_attribute="0"，合入共同字段（0x10411aec8）。
Series其他kind字段也已独立映射：tag1 helper0x10411b36c八String
 aid/vmid/position/index/contain/before_size/after_size/cid。vmid优先config.mid>0，
再config.anchorItem.owner.mid>0，再series.item.owner.mid（nil0）；mode3取first
storyItems的cursorIndex/playerArgs，position=left/sizes20/0；mode4取last，
position原始count bit0偶right/奇left（0x10411b7a8–0x10411b7cc），sizes0/20；
其他取current series.item，position空/sizes10/10。contain仅mode3/4为"0"，
其他"1"；空edge仍保留方向/sizes而数值0，不在helper取消请求。
tag2 helper0x10411bef0八String aid/vmid/contain/before_size/after_size/cid/
season_id/goto；config.avid>0 OR config.cid>=1时同时替换aid/cid，未分别验证
每个替换值（0x10411c1c0–0x10411c250）。mode3/4仍改取first/last playerArgs，
vmid/season保持原item/config来源。season_id优先item.seasonId，否则config，
最终nil空；goto按tag2/3/5→ugc-season/ogv-season/pages，其他空。
tag3 helper0x10411c87c增加epid/ogv_style/material_no，总11String；config覆盖
门禁改为avid>0 OR epid>=1（0x10411caf0–0x10411cbbc），同时替换aid/cid/epid。
season仅原series.item，nil空；ogv_style始终原item.pgc_info（nil0），material_no
始终原item.highlight_id decimal（0x10411d3d4–0x10411d42c），不是config或edge。
tag5 helper0x10411d4fc同tag2八字段/override/sizes，但season只原series.item；
vmid特意从store.dataBloc.feed.item.owner.mid（getter0x1040a5f88，
0x10411db28–0x10411dc44）取，不套用series.item。各helper只构造合入的新dict，
未在此写游标/存储，raw loadmode和tag不是同一枚举。
Series response虚表+e8 0x12045caa8→0x10411af68→0x104118064，先调用
optional config.filter(model)，false返回不通知observer（0x104118144–0x104118168）。
其+b0 0x10411a67c固定1，所以跳过mode0 onlineConfig覆盖及该branch的reportStates。
公共handleResponse0x104118064仅filter准入、weakstore有效、type==0、loader.+b0==0、
model.config非nil时写dataBloc.onlineConfig并调用配置helper、trackBloc.reportStates
（0x104118198/0x1041181ac/0x1041181d8/0x104118210/0x104118244/0x10411826c）；
此入口是公共Loader条件分支，不应算Series每次响应的固定事件。
reportStates0x1041f07cc→0x1041f0578（0x1041f07e0）构造三个设置字段：
play_set_state用gestureMode0x10419eb88结果==1转String2、否则1
（0x1041f05dc–0x1041f05f0）；该getter每次优先登录且StoryConfig.gestureType.
lastModified>=1时使用remote.value==2的0/1，否则读本地BBPhoneMPStoryPreferences.
gestureMode（0x10419ebf4/0x10419ec10/0x10419ec54/0x10419eca8），不把remote PB2
直接作为日志2。play_set_start取当前STPlayModeBloc.currentPlayMode的十进制String
（0x1041f0624/0x1041f064c）；qn取CURRENT BBPhoneMPStoryPreferences.playQn，shared
nil为0（0x1041f0698/0x1041f06a8/0x1041f06bc/0x1041f06d8）。随后BFCNeuronExposureEvent.
trackEventWithId:extendedFields:，eventId为main.ugc-video-detail-vertical.set-state.0.show
（0x1041f072c/0x1041f079c），这是普通policy0链，区别于前述卡片trackInstantly。
play_set_start的currentPlayMode getter0x104172a74→0x104172abc重新读本地autoPlayNext/
looping（0x104172b54/0x104172b88），autoPlayNext=true返回raw3，否则looping=true
返回2、false返回1（0x104172bc0/0x104172bc8/0x104172bf0/0x104172bf8）；任一shared
缺失走fallback3（0x104172b44/0x104172b78/0x104172d64）。这里不直接返回配置PB。
另公开updatePlayMode0x1041728b4→0x1041725bc（0x1041728d0）把incoming==1写
local.autoPlayNext=true、local.looping=false；其他incoming写false/true
（0x1041725dc/0x104172628/0x10417264c/0x104172660），再重新问currentLoop并调用
playerBloc.updateWithPlaybackLoop（0x104172694/0x1041726a8）。currentLoop是当前模式
!=1（0x104172a8c/0x104172a90）。因此writer input1与下一次日志raw3不同，不能把
setter input当play_set_start；其他input经此writer归一到raw2。该body仅本地偏好/
player更新及诊断日志，未发Universal/RPC或reportStates；其他writer仍另核。

动态preferences后端已接通：BBPhoneMPStoryPreferences class 0x1201cf678继承
BFCPreferences 0x1202710f0，shared 0x1142bf5c0使用once token0x120da0af8及
instance0x120da0af0，initializer 0x1142bf5f0 alloc/init后存slot
（0x1142bf600/0x1142bf60c）。configName 0x1142bf61c固定返回
`BBPhoneMPStoryPreferences`（0x1142bf620），init 0x1142bf628先super.init
（0x1142bf650）。属性表0x11f0fb5e8明确autoPlayNext/looping是TB,D,N；通用
processAllProperties 0x1167d3798对rawB选择Bool getter0x1167d4adc/setter0x1167d4b5c
（0x1167d3ab0/0x1167d3bc0/0x1167d3bc4/0x1167d3bcc），映射原始property name。
初始化userDefaults同key非nil优先，否则defaultConfig（0x1167d3d30/0x1167d3d8c），
后续getter读RAM cache，setter先改cache再NSUserDefaults.setObject
（0x1167d355c/0x1167d357c），suite由当前configName懒建
（0x1167d4cfc/0x1167d4d14），本链无MID命名参数或Universal响应门禁。
Story defaultConfig 0x1142bf67c静态默认autoPlayNext=false
（0x1142bf7a0/0x1142bf7b8/0x1142bf7c4）、looping=true
（0x1142bf7d4/0x1142bf7ec/0x1142bf7f8），两者均采用默认时currentPlayMode为2；
不能把shared nil时fallback3当成正常默认。没有读取实际存值/磁盘提交结果或账号清理。

qn需区分静态default字典与手写getter：defaultConfig有playQn=0
（0x1142bf904/0x1142bf91c/0x1142bf928），但Story.playQn 0x1142bf960实际取得
BBPlayerSettingsPreferences.shared（0x1142bf970/0x1142bf974），读其playQn
（0x1142bf984）；setter 0x1142bf9a4同样委托该shared并setPlayQn
（0x1142bf9b8/0x1142bf9bc/0x1142bf9d0）。因此reportStates.qn并非直接取Story suite的
playQn=0默认；最终Player偏好/远程同步规则需沿其receiver另核。Story.autoQnEnabled
0x1142bf9e4也委托BFCPlayerSettingsPreferences，二者属性无D，且
handleNonDynamicProperty 0x1142bfa68返回false，不能当作上述动态Bool链。

Player qn接收端BBPlayerSettingsPreferences也继承BFCPreferences，property table
0x11f24ba80的playQn是Tq,D,N；固定configName `BBPlayerSettingsPreferences`
（0x1147ee2cc/0x1147ee2d0），defaultConfig 0x1147ee72c的playQn=NSNumber int0
（0x1147ee75c/0x1147ee774/0x1147ee780）。通用rawq动态getter0x1167d429c经RAM
及longLongValue（0x1167d42d4/0x1167d42f0），setter0x1167d431c封装NSNumber再同suite
保存（0x1167d435c/0x1167d4378）；存值优先于默认。Player.init末调用
resetDropSettingToDefault、syncLocalToRemote（0x1147ee4fc/0x1147ee504），后者
0x1147ee5f0从同suite读syncRemote gate（0x1147ee644/0x1147ee64c/0x1147ee66c），
未置true时只迁移enabledCubicPanorama/dolbyEnable到对应setter
（0x1147ee674/0x1147ee698/0x1147ee6a8/0x1147ee6cc），再写syncRemote=true并synchronize
（0x1147ee6f8/0x1147ee704/0x1147ee714）。该名字不证明playQn被上传；其body无playQn
写入或直接HTTP。其他实际Player qn writer/质量请求使用另沿各调用者核对。

选择模型的didClick链已闭合：playModeList 0x104171748把builder 0x104170c58交给
公共list wrapper 0x104172564。builder使用静态两项值0/1
（0x120459a28/0x120459a30），每项TitleModel.didClick安装closure 0x104172ea0及
捕获的weak bloc/value（0x104171194/0x1041711b4/0x1041711bc）。实际metadata
0x11ff09c68的+0x1a8槽0x11ff09e10→0x104b56610→0x104b56e8c，写didClick的
function/context pair（0x104b56ec8），不是仅凭字段名推安装。closure读取捕获值
（0x104172ea0）→0x104171488，weak bloc非nil才调用updatePlayMode:原始选择值
（0x1041714c4/0x1041714c8/0x1041714d0/0x1041714dc）；随后toast，重新load weak
bloc非nil才取得trackBloc并发BFCNeuronClickEvent.trackEventWithId:extendedFields:
（0x104171548/0x10417154c/0x104171554/0x104171680/0x10417168c）。事件id为
`main.ugc-video-detail-vertical.play-type-select.0.click`（0x104171578），局部字段
`play_type`=输入EXACT1时字符串2，否则字符串1（0x1041715c8..0x1041715f0），
不等于重新读出的currentPlayMode 3/2。weak bloc第一次缺失仍走toast，日志和dismiss
还有各自的后续weak检查；无该body的Universal上传或等待日志ack。

loopSettingList 0x104172558使用builder 0x104171754，将Bool选择捕获到closure
0x104172e30（0x104171cf0/0x104171d10/0x104171d18）→0x104171f38，weak bloc有效
才调用0x104172258（0x104171f74/0x104171f78/0x104171f84）。该helper取输入低位，
写looping=!input（0x104172288/0x10417228c/0x1041722cc/0x1041722d4），再写
独立autoPlayNext=false（0x1041723a0/0x1041723a8/0x1041723ac），更新播放器loop
（0x104172514/0x104172528）；不是调用前述updatePlayMode整数writer。
之后同callback的weak bloc有效才上报
`main.ugc-video-detail-vertical.player-type-select.0.click`（0x10417208c），
`play_type`=Bool低位+1的十进制String（0x1041720dc/0x1041720e0/0x1041720fc），
走BFCNeuronClickEvent（0x104172190/0x10417219c）。输入false对应looping=true、
当前模式2、日志字符串1；true对应looping=false、autoPlayNext=false、当前模式1、
日志字符串2。通用TitleContent触摸→didClick也有实际注册：TitleComponent metadata
0x12049f610的+0x70→0x104b5a294创建TitleContent（0x104b5a2a4/0x104b5a2b8），
+0x78→0x104b5a2cc把component模型.+0x10交install helper 0x104b59094
（0x104b5a2e0/0x104b5a2e8），helper写TitleContent.model（0x104b590c4/0x104b590cc）。
TitleContent class 0x11ff0a140继承BaseContent 0x11ff0c608，其initWithFrame
0x104b59fc0→0x104b59f08调用super（0x104b59fa8）；BaseContent initializer
0x104b6c5c0通过当前metadata.+0xa0调用setup（0x104b6c648/0x104b6c654），
具体TitleContent槽0x11ff0a1e0→0x104b57a54。setup把tapContent:作为action、
self为target的gesture安装到self（0x104b58770/0x104b58788/0x104b58790/0x104b587a8）。
tapContent 0x104b59e24→0x104b59e3c取CURRENT model及其didClick pair，任一nil返回
（0x104b59e58/0x104b59e60/0x104b59e88/0x104b59e8c），否则以捕获context调用closure
（0x104b59ec4/0x104b59ec8）；无该body独立gesture.state门禁。模型、渲染组件与物理
回调已接通；外层more按钮入口、实际运行时renderer选择/展示成功仍另核。

外层已知安装是BBStoryInteractRigthModule.makeShareService 0x1132c2580创建
BBPhoneMPStoryShareService（0x1132c25ac/0x1132c25e0），将weak-module block
0x1132c2b10安装为selectPlayModeBlock（0x1132c2754/0x1132c2768/0x1132c2784）。
该block load weak（0x1132c2b20）→_showPlayModePanels（0x1132c2b28→0x1132c3304），
从CURRENT storyContext.store resolve明确STPlayModeBloc class
（0x1132c3314/0x1132c3324/0x1132c3338/0x1132c3348），对返回receiver调用
showPlayMode（0x1132c336c）。showPlayMode 0x1041709d0→0x104170780→0x1041707b0
（0x1041709e4），layoutBloc.mainVC weak有效（0x104170820/0x104170830）才取
playModeList（0x104170834/0x10417083c），创建VKSettingVC
（0x104170870/0x10417087c）并经poperBloc呈现
（0x104170958/0x104170970），返回controller weak保存到swipeVC
（0x104170984/0x104170990）。这连接已安装share callback到设置列表构造；当前
shareChannel模型是否包含调用selectPlayModeBlock的具体菜单项仍未闭，不能把setter
存在当作该菜单运行可达。loopSetting外层调用另核。

两条选择日志均把局部字典交给trackBloc helper 0x1041efa34
（0x104171618/0x104172128）。该helper重新读CURRENT item，nil返回nil
（0x1041efa68/0x1041efaa4/0x1041efabc/0x1041efdb8），否则生成十个公共字段：
position=index+1、spmid、simple_id、from_spmid、avid/cid（playerArgs缺失取0）、
goto、r_id、track_id、is_full_screen（当前status.isLandscape为1/0），均为String。
其输入字典随后合并到公共字典（0x1041f0034/0x1041f0050/0x1041f0080），重复key
释放旧value并写incoming（0x1041f0364..0x1041f0378），所以调用者可覆盖公共字段。
当前两个调用者只有play_type，不能推所有调用者最终字段都等于公共默认。

本branch没有等待上报结果再完成响应。requesting此前已清0；
缺/data/cast失败不发成功observer。通过filter且weakstore有效才global(default)
处理model.items，再main queue通知snapshot observers
 didLoadCompleteWithResponse:type（0x10411a17c–0x10411a18c），type原loadmode。
具体初始请求0x10410a048：config nil或anchorItem非nil用mode0/tab1/nil requestConfig；
config存在且anchorItem nil才复制avid/cid/seasonId（不复制epid），安装weak self
closure0x10410c7b4→0x10410b688。这个具体filter所有正常返回均true
（0x10410b88c），包括weak self消失/config nil/items nil/未匹配；它匹配响应
playerArgs.avid/cid与**当时的live config**（0x10410b804/0x10410b840），
autoPlayNext且有下一项就取下一项，否则匹配项，存willLocateItem
（0x10410b958–0x10410b964）。因此不能把通用false分支当作此调用链的过期响应门禁。
tag/listener更新0x10410a2c4→0x104115f64复用lazy loader，写tag+28，
containsObject后才addListener（0x10411a290–0x10411a2c8）；本函数不取消在途请求、
清requesting、清其他listener或递增generation —— **三者均已否证（team-c39 取证）**：0x10411a290 只是 sub_10411A278 内的 selref 载入指令（非函数），其装配点是该 helper 的 4 个调用方（0x104115fd0 `updateSeriesLoaderWithTag:listener:`、0x1041160c0/0x1041160f4 BBStoryRouterParams、0x1041195c4 `STLoader addListener:`）；`updateSeriesLoaderWithTag` 全函数内无清 requesting、无对其他 listener 的 removeObject:/removeAllObjects（remove 只在配对移除方法 0x1041195e4–0x104119638）、无递增 generation 指令；阳性对照：find_callers 对 0x10411a278 与 stub 0x1175a8cc0 各回 4 点。
实际consumer STSeriesBloc.didLoadCompleteWithResponse:type
0x104108340→0x1041078e8：items nil立即返回，非nil空数组仍走adapter及
didLoadedData=true；merge helper0x104107ae0只接受count>0。mode1/2先清
lastReportedItem及preload.cachePool；mode0/1/2替换storyItems，mode3前插并把
series.index加incoming count（0x104108130/0x1041081a8），mode4追加
（0x10410827c）。替换后优先willLocateItem，否则旧item，用isSameArcTo查找，
未找到取index0，再更新focus/UI（0x104107134）。外层mode<=2清willLocateItem，
调用可选adapter witness+50及helper0x1041085b0，最后setDidLoadedData:YES
（0x104107aac–0x104107ab8）。error consumer0x104108398只置didLoadedData=true，
没有替换列表/重试/持久存储写入；这些状态不能解释为网络成功或展示成功。
另有不同的anchor切换producer0x10410b328：已有isEqualTo匹配且index不同时
只经0x104109488/0x1040d096c本地定位；无匹配或已经当前index才复制
avid/cid/epid到requestConfig，raw2/tab1加载。其filter
0x10410bda8→0x10410b9ac确会拒绝：响应items无匹配→可选anchor.failded(model)
然后false；匹配→willLocateItem再true，weak self消失仍true。匹配helper
0x10410bc20→0x10410bae4先比较正epid，否则比较正cid，没有比较avid。
这条回调不能套用初始0x10410a048恒true filter的结论。
Series卡片曝光的producer另已接到实际上报入口，不能用SeriesLoader请求锚点替代。
公开listViewWillFocus0x10410aa94将index/focusType交helper0x10410befc
（0x10410aae8）；helper先取旧common.index，按旧index>新index写preloadMode
（0x10410bf74/0x10410bf80/0x10410bf90），检查storyItems.count>新index
（0x10410c038/0x10410c060/0x10410c064）。准入后先本地定位0x104107134
（0x10410c07c），再调用trackBloc.reportCardExposureWithPrevious:index:type:isFirst:
（0x10410c170–0x10410c1b4）：previous=旧index、index=新index、type=原focusType，
isFirst为当前lastReportedItem==nil（0x10410c194/0x10410c19c）。该body未写
lastReportedItem或等待上报回执；构造时该字段置nil（0x1041099a0/0x1041099a4），
mode1/2响应清零见前文。本轮已展开 0x104106008–0x10410c308 本类可见函数、
闭包、modify/lazy accessor，扫描真实 ivar 槽及硬编码 +0x30 store，并核实际
共享 Neuron selector/sender。唯一硬编码 store 属于新字典 avid 值；未找到非空
业务 writer。此覆盖不能否定全程序间接/动态写入，不能把字段名当可靠一次曝光
去重（root-static-exposure/series-parser-findings.md）。
实际曝光 body 0x1041ee0a0 在 0x1041eed44 取得 BFCNeuronExposureEvent，
以 eventWithId:extendedFields: 建事件后在 0x1041eed88 向实例发 trackInstantly。
“更多”按钮另有独立点击链：STSeriesTopView.moreBtnClick 0x10410e0d8→
STSeriesBloc 0x104108ef4，事件 main.ugc-video-detail-vertical.header.more.click，
通过 BFCNeuronClickEvent 的 trackEventWithId:extendedFields: 上报；与普通
首页卡片曝光不是同一入口，也没有证据据此推断推荐权重。

STBloc.trackBloc getter0x1043272dc携带STTrackBloc metadata accessor
0x1041f0558进入通用getter0x104327354，调用接收者metadata.+0x78
（0x104327388/0x1043273a4）；STBlocStore.trackBloc0x104327150也按同type resolve。
已定位唯一同selector实现STTrackBloc0x1041eede8→0x1041edf7c
（0x1041eee28）；实际STSeriesBloc class0x11fe2bd60继承STBloc0x11fe5dd18，.+0x78
静态槽正指0x105120c08；该函数weak-load Bloc.store（0x105120c48），存活才
0x105121b60→0x1051238f4（0x105120c60）。后者先按type查cached bloc
（0x10512391c），miss才调用目标metadata.+0x70创建（0x1051239dc/0x1051239f4），
此处STTrackBloc槽为0x1041f01b8，alloc/initWithStore后缓存
（0x1041f01cc/0x1041f01d8/0x105123a08）。已闭实际Series静态槽到指定TrackBloc
构造，store安装顺序/动态override仍另核。其type1按newIndex<previous
产生gesture2，否则gesture1（0x1041edfa0/0x1041edfa8）；type2→gesture3
（0x1041edfb0）；type0只有isFirst=true且newIndex==0才gesture0
（0x1041edfbc/0x1041edfc0/0x1041edfc4），其余type0仅诊断日志并返回，未知rawtype
走enum诊断/trap（0x1041ee098/0x1041ee09c）。不能将所有焦点回调算一次曝光。

实际事件builder0x1041ee0a0重新读取CURRENT dataBloc.current.item
（0x1041ee0ec/0x1041ee110），nil直接返回false（0x1041ee128/0x1041ee408），
不用调用入口的card对象。公开字段包括faid（status helper0x1040a975c，0x1041ee1b0），
该helper初次取BFCIDFA.idfaString（0x1040a97a0）、nil为空，缓存到status的
idfaString lazy槽（0x1040a97cc/0x1040a97d8），以后重用（0x1040a9778/0x1040a9788）；
已存在 setter 0x1040a980c/0x1040a9854 可改该槽。**调用方已核查（team-c39 取证）**：stub 0x1175a8cc0 的真实调用点只有 **2 处**（0x1132e09fc ∈ BBPhoneMPStoryFeedVC `_transformParamsFromItem:…`、0x113318cf8 ∈ BBPhoneMPStorySeriesVC 同名方法），receiver 均为 `[meta tracker]`（上报 tracker 元对象）**而非 STStatus**；STStatus 只作读源（getter 0x1132e09c4 取 `context.status`）。STStatus getter 的原始入口为 0x1040a975c，0x1040a97a0 直接读取 BFCIDFA.idfaString，
首次读取后在 0x1040a97d8 缓存 Swift String。0x1040a97cc 是 nil→空 String 的内部
分支，不是 reset；零调用方不构成 reset 缺失证据。ObjC setter 0x1040a980c 与
Swift setter 0x1040a9854 可改该 lazy 槽，间接写者仍需核对。原 team-c39 的
“读源只能运行期确定/reset 0x1040a97cc”已由原始 asm 否证（独立 synchronization.md）。其余
r_id=item.rid十进制（0x1041ee1e0/0x1041ee1fc）、is_full_screen=status.isLandscape
String1/0（0x1041ee26c/0x1041ee284）、position=CURRENT common.index+1十进制
（0x1041ee2fc/0x1041ee308/0x1041ee328）、story_gesture=上述gesture单字符
（0x1041ee354–0x1041ee360）、is_live=item.isLiving String1/0
（0x1041ee388/0x1041ee394）。avid取playerArgs.avid、缺playerArgs为0
（0x1041ee3dc/0x1041ee400/0x1041ee410）；simple_id/spmid/from_spmid重新取CURRENT
common对应字段（0x1041ee4c8/0x1041ee558/0x1041ee5ec），不是旧index对象快照。
另goto/track_id/unique_id分别来自item.cardGoto/trackid/pos_rec_unique_id
（0x1041ee644/0x1041ee69c/0x1041ee6fc）；view_permission为item.isPlayable的1/0
（0x1041ee770/0x1041ee77c）；highlight_cut_id正值才十进制、否则空
（0x1041ee7ac/0x1041ee7d8/0x1041ee7e0）；player_session_id沿当前player.context.tracker
（0x1041ee814–0x1041ee8a0），action_id沿BFCVCPVManager.pvUniqueID
（0x1041ee924）。本节只描述来源，不读取任何真实session/identity。

CURRENT currentTab==1才加Series专属collection_id（item.season.seasonId，缺失则
移除该key，0x1041ee9bc/0x1041eea04/0x1041eea30/0x1041eeae0）及space_type
（Series.adapter witness.+0x30，缺adapter则移除，0x1041eeb7c/0x1041eeb90/
0x1041eeba0/0x1041eec68）；其他tab跳过两字段（0x1041ee9c0）。最后将item.show_report
字典merge到已组字段（0x1041eecbc/0x1041eecf4→0x1041eee44）。该专门化merge
遇到已有key会release旧value、写incoming value（0x1041eef60–0x1041eef74），后续
迭代同样替换（0x1041eeffc–0x1041ef018），因此show_report覆盖同名默认字段；
缺失的key才插入，不能把上述默认来源当最终字段不可覆盖。构造BFCNeuronExposureEvent，eventId为
main.ugc-video-detail-vertical.0.0.show（0x1041eed00/0x1041eed5c），调用trackInstantly
（0x1041eed88），接前述Neuron policy1→采样/入队/编码/缓存/调度链。
这个业务调用返回值不能当服务器回执。space_type实际witness已接：conformance
0x1183cbf58将STSeriesAdapter nominal0x11962ecc8绑定STSeriesAdapterProtocol
0x11962ec38，witness0x11b2b3ed0的.+0x30→0x1040e6d9c；它取实际对象metadata.+0x70
（0x1040e6dc0/0x1040e6dc4），各adapter静态槽如下，返回Swift String，不是数字enum。

| factory tag | adapter / class | space_type getter / String |
| --- | --- | --- |
| 1 | STSeriesUpSpaceAdapter / 0x11fe2ba08 | 0x104103408 → `1` |
| 2 | STSeasonAdapter / 0x11fe2a770 | 0x1040e7a20 → `2` |
| 3 | STEpisodeAdapter / 0x11fe295c0 | 0x1040d7dfc → `2` |
| 4 | STRelateAdapter / 0x11fe2a1c8 | 0x1040e4a68 → `3` |
| 5 | STPageAdapter / 0x11fe29968 | 0x1040db054 → `4` |
| 其他 | STSeriesAdapter / 0x11fe2a508 | 0x1040e6c54 → 空String |

factory0x10410b000对应类型选择见前文，动态替换仍未运行；缺adapter时移除key与存在
base adapter写空String不同。全部Series日志producer已收敛到两类可定位调用：卡片曝光
`main.ugc-video-detail-vertical.0.0.show`（构造 0x1041eed00/0x1041eed5c、trackInstantly 0x1041eed88）
与 set-state 回执 reportStates 0x1041f0578→0x1041f072c（eventId
`main.ugc-video-detail-vertical.set-state.0.show`），两者都经 BFCNeuronExposureEvent →
policy0/1 公共链。精确残余：上述构造点所在函数之外的 Series 侧入口
（factory 0x104115130、`-[STLoadBloc requestWith:tab:config:]` 0x1041153ac、
`-[RecommendLoader requestWith:config:]` 0x104111f30、`-[STLoader requestWith:config:]` 0x104119524、
`-[STSeriesLoader requestWith:config:]` 0x10411b2c4）尚未逐个反汇编穷举第三类 trackEventWithId；
下一步命令：`$PY disassemble.py 0x104118064 0x10411b2c4` 后检索 Neuron 构造点，
并用 `$PY find_callers.py 0x1041eed00` 回溯曝光构造的生产者。

Series边缘加载的实际UI入口listViewDidFocus0x10410ab14→0x10410c308：
preloadMode0且adapter witness+40为true、count-index<=3→raw4/tab1；
preloadMode1且adapter+48为true、index<4→raw3/tab1。
listViewWillFocus0x10410befc在0x10410bf80–0x10410bf90根据旧index>新index
设置preloadMode1，否则0。adapter实际绑定0x104109b78经factory0x10410b000
创建tag1/2/3/4/5对应adapter，把selectedAction设weak self closure
0x10410c7bc（0x104109c50–0x104109c6c）→0x10410b2cc→上述anchor入口。
Page公开seriesPagesView:didSelectedItemAt:0x1040dd448→0x1040dcdd0
给anchor avid/cid及epid0；failed0x1040dd4c4→0x1040dd28c在weak adapter有效
且response.redirect.uri非空时BFCRouter.processUrl:animated:true
（0x1040dd39c），否则固定StoryRes字符串→center toast（0x1040dd428）。
Episode公开episodeListSheet:didSelectEpisode:route:avid:0x1040d8ed0→
0x1040d91b8先dismiss sheet，再给anchor avid/cid0、epid；failed
0x1040d9764→0x1040d8e18忽略响应model，weak adapter有效后直接使用捕获原始
route调用processUrl:animated:true（0x1040d8ea8），没有非空检查/response.redirect。
两种failed是响应目标缺失后的业务回调，不是transport error，也不在此重试请求。
引导计数另有比较差异：noclick入口0x101b581b4要求enable/disable、未点击、
config非nil及threshold>=1，RAM计数从<=999加1（封顶1000）；0x101b582fc
比较count与threshold，count>=threshold才raw3/forcefalse调用展示入口。
noInterest入口0x101b57fb4却在0x101b5816c比较threshold与count，b.lt返回，
因此threshold>=count才调用，不能按名称反写成达到阈值；传入guideType原传。
两者仍受上述eligibility，RAM计数不是持久daily count。真实closeButton
ivar0x1203585a8→Rx control event64（0x101b5b490）→0x101b5ff2c→onClose
ivar0x120358520→共同callback/hide helper0x101b5b85c，实际调用已证的
0x101b5f568→0x101b5a0ac关闭日期保存，随后hide；不在此写禁个性化偏好。

声音两项持久 Bool 的保存桥已闭合：BBListPegasusInlinePreferences 是 BFCPreferences
子类，属性编码 TB,D,N；动态 setter（0x1167d4b5c）查 selector→property key，
NSNumber Bool→_setObjectWithKey:value:（0x1167d34cc），更新RAM字典后
userDefaults.setObject:forKey:。suite 来自子类 configName 的类 description。
这证明设置值有即时内存更新与持久存储调用，不代表已经验证磁盘提交完成时机。
实时 mute singleton init（0x11419f300）只首次读取该存储；系统音量监听 callback
只发 old/new 通知，也不直接写 mute。首页 volumeDidClick:isMannual:
（0x113a99fdc）在 token.isValide 后把音量设为 mute?0:1，再调用共享对象
setMutePlay（0x113a9a058–0x113a9a074）；此入口没有写 cold 两项持久偏好。
新 API 因而可读取实时变化，同 API 缓存不刷新；不能宣称两字段每次切换同步。

autoplay setter 将2/4写底层1、1/3写2、10/11写3，其余0；server标志仅1/2/11为true。
因此用户明确选10/3/4会取消受服务器影响标志。请求最终编码经enum/table映射，不是
直接把底层 double_p=1/2/3发送。column 的另一字符串getter把0..4映射为2/3/2/3/2，
这是展示相关值，与请求column原始码不同；UI标题与实际排布仍需追调用方。

设置通知到刷新需要区分即时与延后：RefreshHelper订阅Column/VideoMode的ByUserAction
通知（0x101b65644/0x101b65718），只消费可cast Int64且分别3/4、11/12的userInfo.value。
0x101b647e0在pegasusIsShow=true时返回；false且latestConfig.mode_switch_refresh_exp
可castInt并等2时，operator+0x60先清理、+0x50派发原reason3/14，否则保存对应flag。
MainVM注册0x101a48f88明确将+0x50绑定捕获VM的0x101a5c404→0x101a4893c，
reason入MainApi+0x11；builder0x101a32cb0再读表0x1182c9138映射wire flush，
所以column reason3→flush2、video reason14→flush17。VM正在loading时拒绝派发。
不要将内部reason原值当成请求flush，也不把实验缺失等同2。

延后flag消费0x101b638a8对userHasChangeFormat走+0x50 reason3，对
playStyleManualChanged却走+0x30 reason14。+0x30绑定0x101a5c464→VM0x101a4fa88，
要求collectionView存在且!isLoading，保存reason、setContentOffset(0,-60,animated=true)，
延迟0.3秒callback0x101a5c758调用捕获collectionView.bfc_beginHeaderRefresh。
Header action0x101a3b7e8经0x101a37538取VC.viewModel、读取保存reason，
再调VM0x101a4893c，最终仍raw14→flush17，但存在loading/view/延迟与UI刷新条件。
这不是通知收到即无条件发RPC；operator绑定发生在VC lazy viewModel nil初始化分支。

延后消费的生命周期已闭合：VC.viewWillAppear wrapper 0x101a37608传key1，
viewDidAppear传key2；共用handler 0x101a37648向BBListPegasusEventDispatcher
（共享入口0x103d9fe54）发布该key与animated payload。RefreshHelper
0x101b654d4订阅同dispatcher的key1，closure 0x101b690ec→弱引用callback
0x101b6728c→0x101b638a8。因此这些flag在viewWillAppear消费，不能写成viewDidAppear。

声音偏好缺值还有条件性默认链：InlinePreferences未覆写defaultConfig，父类
0x1167d33cc返回nil；处理属性时缺省字典为空，NSUserDefaults缺值不会赋属性。
动态Bool getter仅查RAM字典，再对nil调boolValue得到false。因此无持久值且
没有其他先行setter时，inlineVolumeOn/hasHandledVolumeSetting都是false，生成
cold_state=2；实时singleton init反转inlineVolumeOn，得到mutePlay=true、inline_sound=1。
_didUpdateConfig（0x11419ed54）仅return，配置更新通知本身不改这两个Bool。
这不是所有账号、安装或首请求的恒定值证明。

自动画质的UI和保存还需区分：makeQualityData（0x114535648）给自动项
setIsAutoSwitch=true，加入quality list；didSelect（0x114536030）同auto/同qn时
早退，否则先走delegate，缺delegate再qualityProxy.changeQuality。正常播放container
把videoServiceClass配置成BBPlayerVideoQualityService，proxy按context配置取得服务。
changeQuality→_switchToExpectQn（0x11453d23c）仅needUpdate=true才调
updateUserQn:isAuto，再受manual.shouldMemoryQn门槛；
QualityHelper.shouldMemoryQn（0x11482146c）每次读在线String Memorable_qn→integerValue，
允许条件为threshold==0或signed threshold>qn，相等不存；nil/转0允许。自动选择绕过该门槛；needUpdate helper
（0x114539c18）由trial/VIP试用/familyBroadband状态决定。故临时切换、试用等
路径可以改变当前auto状态却不改持久autoQnEnabled。其他widget的context绑定和
代理内部转发仍未全部闭合，不宣称所有播放器入口统一。
青少年设置年龄不能从选择器缺省索引推请求常量：UserCenter.showAgePicker
（0x10f361268）构造1..17，age>0时defaultIndex=age-1，否则index16；completion
（0x10f36148c）把selectedIndex+1传Navigator（0x11596442c），构造PasswordVC
status11并setAge。nextStep该分支验证码/密码流程成功callback0x115977798
仅success=true才把捕获age写Manager；失败不写。同步模式状态0x1159613c4则
从teenagers模式模型.age取32位符号扩展后setAge，因此服务器也能覆盖。
这一同步callback不同于UI设置的successBool：SynchronizeApi0x11595cc70在RPC error
时向completion传(nil,nil)，无error则按模式名挑teenagers/lessons模型；Manager
callback0x1159613c4对teenagers模型没有nil门控，nil.age→0仍setAge。因此错误/响应
缺teenagers模式可能把本地年龄写0，不是自动保留旧值；该分支属运行期、本轮未复现（下一步 `disassemble 0x11595cc70 0x11595ce00`）。
BFCRestrictedModeTeenagersPreferences的动态age类型Tq,D,N，configName
（0x115965870）常规按account.userID形成BFCTeenagersModePreferences-%lld，另有
一次flag归-0分支；七项defaultConfig不含age。动态Int64 getter0x1167d429c从RAM字典取对象后longLongValue，故无持久值且没有
先行writer时退0；不代表所有首请求都0。shared（0x1159657dc）once缓存账号suite实例；
resetPreferences有重建能力但未找到账号切换调用。localShared另once并设置一次flag
以创建suite-0，getAge使用shared而非localShared；不能据configName动态账号格式
宣称每次账号切换都已切换读取实例。
播放能力/画质与flush/pull等继续逐项归因；当前固定采集策略不能替代来源证明。

### Story 清晰度选择与偏好写入的独立执行链

Story分享菜单已有具体画质入口：沿前述shareChannelForModel: type−1跳表
0x119058d80，原始type18项raw54转0x113351e88，构造BFCShareCustomChannel，
公开key却为`kShareActionItemMiniScreen`（0x113351ed4/0x113351ed8），weak action
0x113353f9c（0x113351eb0/0x113351ed0/0x113351ee4）；以执行体核行为，不按key字面猜。
action weak-load service后，CURRENT selectVideoQualityBlock非nil才BLR
（0x113353fb0/0x113353fb8/0x113353fcc/0x113353fe8），随后独立报告
`main.ugc-video-detail-vertical.share-pannel.definition.click`
（0x113354018/0x113354024），不以面板实际显示为条件；弱service缺失也未见此体跳过
整个日志路径。RigthModule.makeShareService将weak module callback0x1132c2b3c
保存到该block（0x1132c279c/0x1132c27b0/0x1132c27cc），callback调用
_showVideoqualityPanels（0x1132c2b4c/0x1132c2b54→0x1132c3404）。后者CURRENT
storyContext.store.resolve(STQualityBloc)（0x1132c3424/0x1132c3438/0x1132c3448）
所得receiver调用showList（0x1132c346c），接下述具体列表/选择/writer/解析链。
availability固定allow-list也明确包含18（0x11335effc/0x11335f000），与19同走
isFunctionModelAvliable contains检验；实际菜单是否包含type18仍取决服务端model。
Store实例安装和运行呈现不由此静态接线单独证明。

实际列表model来源已闭：STQualityBloc.showList0x104176340调用builder0x104174f80
（0x104176354），再present helper0x104176378（0x10417635c）。builder先读
videoQualityService（0x104174fd0/0x104174fe8），从currentAutoQn/currentQuality取得
snapshot（0x104175420/0x104175434/0x104175438/0x1041756e0），逐项alloc
VKSettingView.TitleModel（metadata0x104b57048→class0x11ff09c68；0x104175714/0x104175724）。
每项callback context强捕获quality、弱bloc及snapshot Bool/qn
（0x104175dd8/0x104175df4/0x104175dfc/0x104175e04），thunk0x10417bc4c交model
virtual+0x1a8（0x104175e2c/0x104175e34）；该class slot0x11ff09e10→0x104b56610，选择
TitleModel.didClick ivar0x12049f4d0并存function/context pair
（0x104b56614/0x104b56618→0x104b56e8c/0x104b56ec8）。

TitleContent.setupViews0x104b58828→0x104b57a54（0x104b5883c）真实安装self为target的
tapContent: gesture（0x104b58770/0x104b58788/0x104b58790/0x104b587a8）。tapContent:
0x104b59e24选择didClick并交0x104b59e3c；CURRENT content.model必须非nil
（0x104b59e5c/0x104b59e60），CURRENT didClick func非nil（0x104b59e88/0x104b59e8c）
才BLR（0x104b59ec8），不把tapMore:的另一ivar算选择。thunk转0x10417a80c
（0x10417bc4c..0x10417bc58），弱bloc nil跳过（0x10417a84c/0x10417a850）；
selected quality.isAutoSwitch与captured原Bool均true则直接跳过
（0x10417a864/0x10417a868/0x10417a86c），两者均false且selected qn等于captured原qn
也跳过（0x10417a878..0x10417a898）；其他才didSelectQuality:
（0x10417a8ac）。因此下述点击日志不覆盖每次物理tap，该比较使用建表snapshot，
不是选择时重新读service.current。调用之后若weak swipeVC存在则dismiss并清weak字段
（0x10417a8bc/0x10417a8c0/0x10417a8d8/0x10417a8e4），不以authSelect/播放成功返回为
关闭门禁。分享菜单外层入口已如上闭；model→content的具体类型连接进一步定位：
VKSettingVC构造helper0x104b6db28保存传入section list（0x104b6db78），reload
0x104b6e930读取该list并render（0x104b6e964/0x104b6e9b0→0x104b6e8d8
→0x104b6ddc0）。section.items转换循环读取每个model metadata virtual+0x158
（0x104b6e728/0x104b6e7b4/0x104b6e7bc）。实际TitleModel class0x11ff09c68
槽0x11ff09dc0→0x104b56f28构造TitleComponent，+0x10强保存原model
（0x104b56f50），连同metadata/witness0x12049f6d0返回
（0x104b56f5c）。factory0x104cd1368调用该component witness+8
（0x104cd1384），实际0x11b2ff210+8→0x104b5a3b0→通用CellsBuilder
0x104cd2184。TitleComponent内容witness0x12049f670+0x10→0x104b5a294创建
TitleContent（0x104b5a2a4/0x104b5a2b8），+0x18→0x104b5a2cc取component原model
（0x104b5a2e0）交TitleContent安装body0x104b59094（0x104b5a2e8），保存
TitleContent.model（0x104b590c4/0x104b590cc）。具体model、component、content
不是凭同名推断。通用类型擦除链也已定位：CellsBuilder 0x104cd35c0取该component的
内容witness（0x104cd36b0），经0x104cd36fc→0x104cce33c（0x104cd3820）；
非AnyComponent分支创建ComponentBox并保存metadata/witness pair
（0x104cce410/0x104cce41c），box witness 0x11b30ac28的+0x18→0x104ccf578
→0x104cce940，取保存内容witness.+0x10并调用make（0x104cce95c/0x104cce998）；
box.+0x20→0x104ccf57c→0x104cce9b0先cast incoming content，成功才调用保存
内容witness.+0x18 update（0x104ccea84/0x104ccea8c/0x104cceab8/0x104cceac8）。
具体cell渲染helper 0x104cd2238在缺旧content分支调用box.+0x18 make
（0x104cd235c..0x104cd2380），挂载content后递归本helper
（0x104cd23c4/0x104cd23e8/0x104cd23f8）；已有content并通过其更新准入时调用
box.+0x20（0x104cd2304..0x104cd2334）。UICollectionViewAdapter的实际
cellForItemAtIndexPath wrapper 0x104cca234→0x104cc9d7c（0x104cca2b8），取得
cell后要求ComponentRenderable conformance及isMemberOfClass匹配；符合才调用
上述helper（0x104cc9f84/0x104cc9fa0），否则走注册/重新dequeue分支。
VKSettingVC的lazy adapter helper 0x104b6d284创建VKSettingVCFlowLayoutAdapter
（0x104b6d2b0/0x104b6d2b4）；其class 0x11ff0c7c8.+8→0x11ff255b8
UICollectionViewFlowLayoutAdapter，再.+8→0x11ff254a0 UICollectionViewAdapter。
具体dataSource绑定也已闭：VKSettingVC ctor body 0x104b6d684取上述renderer和
collectionView（0x104b6d724/0x104b6d72c），调用renderer virtual+0x80
（0x104b6d734/0x104b6d73c）。renderer的symbolic typeref 0x1196d6870实际为
Carbon.Renderer<UICollectionViewUpdater,UICollectionViewAdapter>；descriptor
0x1196979b4 vtable起word15，第二槽+0x80实现0x104cd3fbc。
该setter弱保存target（0x104cd3ff8）→helper 0x104cd3f00，从自身.+0x10取同adapter
（0x104cd3f44），通过Updater witness+0x20调用bind（0x104cd3f4c/0x104cd3f58）。
具体UICollectionViewUpdater conformance 0x118404070/witness 0x1204a98d0.+0x20
→0x104cd9e38→virtual+0x120（0x104cd9e4c/0x104cd9e50）；descriptor 0x119697b1c
vtable起word17，slot19正是0x104cd673c。它对原target设置同adapter为delegate及
dataSource（0x104cd675c/0x104cd6770），reloadData（0x104cd6780）并invalidateLayout
（0x104cd67a8）。因此此列表构造确有具体adapter接线，后续cell更新准入及呈现完成仍另核，
不把reload调用等同实际UIKit回调已发生。
此外render body 0x104b6ddc0要求当前target view及其window非nil
（0x104b6de00/0x104b6de28），才更新list/adapter并调用renderer
（0x104b6de54/0x104b6de84/0x104b6deec）；未挂window时直接返回，非无条件render。

STQualityBloc.didSelectQuality:0x10417a45c通过wrapper0x10417a468调用实际body
0x104179dcc（0x10417a49c）。必须weak layout.mainVC存在（0x104179e34/0x104179e44），
且playerBloc.videoQualityService非nil（0x104179e6c/0x104179e84）。先报告
main.ugc-video-detail-vertical.play-set-select.0.click，qn为incoming quality.qn的
Int64.description（0x104179f04/0x104179f20/0x104179fbc），之后才authSelect:
（0x104179ffc）；false直接退出（0x10417a000）。因此点击不是授权或切换成功ACK。
authSelect:0x104179d70实际body0x1041795a4（0x104179da0）先要求hasLogined，false
showLogin并返回false（0x104179604/0x104179608/0x1041797b4/0x1041797b8），包括自动选择，
不因expect 64的适配代码推匿名可成功切换。needVip=false跳过VIP helper；true要求
0x104179a44通过（0x104179618/0x104179628/0x10417962c），否则showVip:后拒绝
（0x104179a28）。helper检查currentUser.vip.isValidVip（0x104179abc），或item.owner.mid
与currentUser.mid的optional相等（0x104179bf8..0x104179c08），不观察实际MID；都不满足
时，存在mainVC/service且supports canTrialVipQuality而返回false会拒绝trial通路
（0x104179cac/0x104179cb8/0x104179cc4/0x104179cdc）；可trial通路还需
trialService.isQualityTrialAble:selected（0x104179cf8/0x104179d10）。nil mainVC/service
有独立分支，不概括为一律拒绝。auth随后若目标可trial，则checkAndStartTrialWithQuality:
必须非零（0x10417964c/0x10417965c/0x10417967c/0x10417968c）；二次trialService已nil
会返回当前nil值（0x104179668/0x1041797bc）。通过后如tracker存在，无论此前是否实际启动
trial，都发player.player.vip-qn-trysee-start.0.player、empty extended dict
（0x104179718/0x104179720/0x104179744/0x104179784），然后返回true
（0x1041797a0）；不能由此日志名推已经trial或播放成功。
权限通过后，如actual player.context.tracker存在，还发
player.player.clarity-type.0.player（0x10417a07c..0x10417a0d0/0x10417a2b4）：
qn为自动时String0、否则selected qn（0x10417a128..0x10417a174）；is_auto取反编码，
selected自动为0、手动为1（0x10417a190..0x10417a1a8）；from_is_auto按原currentAutoQn
同样编码（0x10417a1d0..0x10417a1e4），from_qn原自动为0、否则currentQuality
（0x10417a200..0x10417a240）。缺tracker不阻后续切换。

selected自动时，以hasLogined选expect 80/64（0x10417a300..0x10417a310），用available
quality list与canPlayVipQuality=false求findAdaptQuality，再修改incoming quality.qn
（0x10417a3b4/0x10417a3d8）；手动跳过该适配。receiver须respondsToSelector，才调用
changeQualityWithExpectQuality:preQuality:（0x10417a3ec/0x10417a404），preQuality来自可选
findCurrentQualityInfo（0x10417a018/0x10417a028）。实际STPlayerVideoQualityService方法
0x1041caaf0读取selected qn/isAutoSwitch（0x1041cab38/0x1041cab4c），进入0x1041cdfb8
（0x1041cab6c）。该helper匹配available list中qn（0x1041ce070/0x1041ce078），若匹配且
trialService.isQualityTrialAble为true（0x1041ce10c/0x1041ce11c），以canTrial helper
0x1041cb964的反值决定needUpdate（0x1041ce120/0x1041ce130）；未匹配、trialService缺失
或不可trial则needUpdate=true（0x1041ce138/0x1041ce140）。canTrial helper0x1041cb964要求hasLogined（0x1041cb98c/0x1041cb990），已有效VIP则false
（0x1041cb9e0/0x1041cb9f0/0x1041cb9f4）；否则取已有或resolve trialService
（0x1041cba04..0x1041cba2c），存在才返回trialAble（0x1041cba58/0x1041cba68），
缺失为false。因此该匹配目标可试用且当前可trial时needUpdate=false，不写偏好。

最终_switch(to:isAuto:needUpdate:preferToast:) body0x1041ca0f8要求目标quality存在
（0x1041ca30c/0x1041ca310），否则日志后返回。先写currentAutoQn
（0x1041ca3e4..0x1041ca3f4），needUpdate bit为true才调用偏好helper0x1041cd89c
（0x1041ca3f8/0x1041ca404）：自动传qn=0（0x1041ca3fc/0x1041ca400），在
BBPhoneMPStoryPreferences.shared非nil时写playQn=0并autoQnEnabled=true
（0x1041cd8f4/0x1041cd8f8/0x1041cd928/0x1041cd9cc）；手动必须
BBPlayerQualityHelper.shouldMemoryQn:返回非零（0x1041cd94c/0x1041cd950），才写
playQn与autoQnEnabled=false（0x1041cd998/0x1041cd9c8/0x1041cd9cc）。这沿用前述
Memorable_qn门禁，但receiver为Story preferences；同步上传该 local 偏好未证（下一步 `find_callers.py 0x10482146c` 枚举调用方）。
之后才进入willSwitchQuality callback及实际切换分支（0x1041ca464/0x1041ca474..0x1041ca4d4），
故偏好更新不是播放成功回执。画质列表 UI 的实现类已定位为
`-[BBPlayerVideoQualityListWidget makeQualityData:]`（0x114535648）与
`tableView:didSelectRowAtIndexPath:`（0x114536030）；对照实现还有
`-[BBUGCPlayerVideoQualityListWidget makeQualityData:]`（0x114384df4）与
`-[BBHD2MPVideoQualityListWidget makeQualityData:]`（0x10ccfa27c），三者不可混为同一路径。
**present 安装方已闭合**：对 classref 槽 0x11f7bdaf0 做 ADRP+LDR 全 __text 扫描得三个引用点，
其中 0x104176854 在 Story 的 `_TtC5Story13STQualityBloc`（函数 sub_104176754）内：
0x104176814/0x104176818 weak-load `STQualityBloc.playerContainer`（ivar slot 0x12045d930），
非 nil 时 0x104176828/0x10417682c 调 sub_1041B2D48(0)；
0x104176838/0x10417683c 取 `context`，0x104176854/0x104176858/0x10417685c 载
`_OBJC_CLASS_$_BBPlayerVideoQualityListWidget` 后 `objc_allocWithZone`，
0x104176864/0x104176868/0x10417686c 用 `initWithContext:config:`（config 传 0）构造；
0x104176880–0x104176890 `setDelegate:`（x2=STQualityBloc）、0x104176894–0x1041768a4
`setIncludeSetting:` w2=0、0x1041768a8–0x1041768b8 `setIncludeLoginBadge:` w2=0；
随后 0x1041768bc/0x1041768c4 取业务 view、0x1041768d8/0x1041768dc `frame`，0x104176900
常量 0x406d000000000000（=232.0）参与尺寸，0x10417690c 取
`type_metadata_accessor_for_STPlayerWidgetContainer` 并由 0x104176948 sub_1041B07E8、
0x104176970 sub_1041B1DE0 装载。另两个引用点（0x103a04b08 所在 sub_103A04AEC、
0x103f94608 所在 sub_103F94398）未逐个展开。
精确残余：（b）trialService 内部开始/失败生命周期；（c）切换/失败后如何更新 CURRENT quality。

清晰度切换的重新解析分支0x1041cd9f4要求service.parseModel非nil
（0x1041cda38/0x1041cda3c），以weak service和chosen qn/isAuto构造completion context
（0x1041cda60/0x1041cda7c/0x1041cda84）。它先就地修改同parseModel：preloadUrl=nil、
qn=chosen、isCantUseLocalCache=true、offline=false
（0x1041cda9c/0x1041cdab0/0x1041cdac4/0x1041cdad8）。若符合BBResolverUniteParms且
class为BBResolverBaseParsModel派生（0x1041cdaf4/0x1041cdaf8/0x1041cdb2c/0x1041cdb30），
还设playCtrl=1、qnPolicy=0、clientAttr=2（0x1041cdb48/0x1041cdb4c/0x1041cdb60/0x1041cdb74），curLanguage与
curLanguageType取CURRENT context.director.currentScene.response，相应来源nil则写nil/0
（0x1041cdc20/0x1041cddd8/0x1041cde8c/0x1041cdeb4），调用BBResolverUniteHelper
resolverWith:completeBlock:updateBlock:（0x1041cdf60，updateBlock=nil），接此前已闭Unite
请求/回退路径。失败该protocol/class门禁则优先parseModel.resolverClass非nil
（0x1041cdc7c/0x1041cdc80）调用其resolverWith（0x1041cdd00）；缺resolverClass时须
cast BBResolverBaseParsModel成功（0x1041cdd34/0x1041cdd38），才BBResolverHelper.
resolverV2With（0x1041cddb4/0x1041cddc0→0x1041cdf60），否则退出。三路共同completion
0x1041ce320→0x1041cc9fc（0x1041ce328），不在此构造独立Story quality HTTP endpoint。

completion须weak原service仍在且CURRENT context.playback存在
（0x1041cca48/0x1041cca4c/0x1041cca64/0x1041cca68/0x1041cca80/0x1041cca90）；
result非nil且result.videoInfo非nil才进入采用分支（0x1041cca94/0x1041ccab0/0x1041ccab4），
该分支没有先以error==nil门禁。先将response.qualityList替换availableQualityList并保存
videoInfo（0x1041cccd0/0x1041ccd00/0x1041ccd28），把response.item.streams追加到CURRENT
playback.currentItem（0x1041ccd84..0x1041cce64）；然后以response.currentQn而非
captured expect qn选择实际切换（0x1041ccf28/0x1041ccf58/0x1041ccf74）。特殊本地切换
helper0x1041cc110通过则走0x1041cc834，否则updateItemParams、replaceWithIjkItem、
bindCallBackFor等（0x1041ccfa0/0x1041ccfd0/0x1041cd03c）；不能从解析非nil推渲染成功。

result/videoInfo缺失走解析失败日志（0x1041ccb00..0x1041ccb84），取CURRENT quality，
error可转换为NSError类时提code，否则code=0（0x1041ccb9c/0x1041ccbf0/0x1041ccc08/
0x1041ccc20/0x1041ccc28），交反馈helper0x1041cbd24（0x1041ccc38）。此completion没有
恢复已写的Story playQn/autoQnEnabled、currentAutoQn或已改parseModel字段；无generation/
原item identity比较，观察到的是CURRENT playback，不推运行时必有乱序。
本地切换helper0x1041cc834须context/playback非nil（0x1041cc87c/0x1041cc8a4），手动模式
先setCurrentQuality（0x1041cc8a8/0x1041cc8bc），自动跳过；随后调用playback.
changeQualityWith:playerItem:isDashVideo:isAutoSwitch:autoSwitchMaxQn:autoSwitchMinQn:userQn:
（0x1041cc970），userQn从Story preferences.playQn取、shared nil为0
（0x1041cc910/0x1041cc944）。这些方法调用返回不等播放回执。
本地可切换helper0x1041cc110的布尔组合已核：availableQualityList必须含incoming
qn（0x1041cc1c4/0x1041cc1c8/0x1041cc1cc），CURRENT quality必须能通过
0x1041cb538从同list匹配（0x1041cb560/0x1041cb5f8/0x1041cb600）；无list/匹配返回false。
它要求videoInfo.isDashVideo=true（0x1041cc228..0x1041cc250），目标与当前quality都
isLocal=false（0x1041cc260..0x1041cc27c）、noRexcode=false
（0x1041cc28c..0x1041cc2a8）、isHDR=false（0x1041cc2b8..0x1041cc2d4）。还要求
CURRENT context.playback.currentItem.ijkItem非nil，且其
isExistSpecialQualityStream:(incoming qn)=true（0x1041cc2f0..0x1041cc3a4）；
缺context/playback/currentItem/ijkItem令此gate失败。videoInfo.drmTechType==1另拒绝
（0x1041cc3cc..0x1041cc3f4）。最终将非DASH、任一local/noRexcode/HDR、缺special
stream的低bit OR（0x1041cc3f8..0x1041cc408），全为false再返回(drmTechType!=1)
（0x1041cc468）；videoInfo nil也返回false。这里保留公开属性拼写与原始DRM值，
不猜DRM协议名；player 后续失败通知未逐条核对（下一步 `disassemble 0x1041cd9f4 0x1041cda80` 回溯失败回调）。
