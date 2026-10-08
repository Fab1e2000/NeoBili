# 预加载播放能力参数

[研究导航](../README.md) · [本主题目录](../../CLIENT_NETWORK_PROTOCOLS.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 预加载播放能力参数

BBResolverUtils.preloadUrlDeviceParams（0x114a0c21c）先生成 fnver=0、能力 fnval、
fourk、soft_fnval、player_net 与 force_host。fourk 是 IJKFFUtils.isUhdSupported
的布尔值，不是在该函数另做屏幕判断。player_net 按 Wi-Fi→1、WWAN→2、其他
reachable→0、unreachable→3 选字符串；force_host 先为 0，设置
httpsPlayurlEnabled 为真时覆盖为 2。

supportFnval（0x114a0be60）按位组合：

| 位值 | 添加条件 |
| --- | --- |
| 0x10 | 总是作为基础位 |
| 0x80 | isUhdSupported |
| 0x100 | isEac3Supported |
| 0x200 | enableDolbyVision |
| 0x40 | enableHDR |
| 0x4000 | enableHDR 且 enableHDRVivid |
| 0x800 | isAv1Supported，或 v865_player_support_av1_soft 实验命中且 isAv1SupportSoft |
| 0x4 | v886_player_preload_support_soft_fnval 命中且 isHevcSupported |
| 0x10000 | isH266SupportSoft |

soft_fnval（0x114a0bf6c）在 v886_player_preload_support_soft_fnval 未命中时为 0；
命中则 0x114a0bfb4 组合 H266 软件支持位 2，以及
v888_player_support_av1_soft_fnval 命中且 AV1 软件支持时的位 1。上述实验 preset
均为 1，但实际命中与 IJKFFUtils 的系统能力判定仍需分别核对。

BBPlayerPreloadUrlParamsHelper（0x114397ffc）复制上述参数，再加 qn、qn_policy、
voice_balance、client_attr 和 player_extra_content。qn_policy 是 autoQualityEnabled
的 1/0，voice_balance 是 enableLoudNorm 的 1/0。qn 的 preferredQnForResolver
（0x11482101c）在自动画质开启时选择 32，否则取 userSettingQuality，再过
maxQualityByUserLoginState（0x1148210a8）：已登录原值返回；未登录且远程
配置 enable_player_force_login_qn 的整数 >=1 时取 min(候选画质,配置值)，否则
保留候选。未从此处推断设置本身的持久化和默认画质。

client_attr（0x1143981fc）仅当 player.priority_hdr_842（preset=0）命中、
priorityUseDolbyHDR 开启且 currentUser.vip.isValidVip 为真时返回 1，否则为 0。
extraContent（0x1143982d8）以 screenHeight→long_edge、screenWidth→short_edge
十进制字符串及 VBPreferences.translateLanguage→cur_language 组成字典；该函数
没有自行按 min/max 排序两条边。toJsonString（0x11439843c）对字典用 Foundation
JSON options=0，再 UTF-8 转字符串，非法输入或序列化失败退空；未指定排序键。
因此 player_extra_content 的键顺序不是此函数保证的协议常量。

这些参数被搜索等调用者复制；首页 getPlayerParams 另有选键/合并层，不能将 helper
全部字段直接认定为每种业务请求都会发送。实际 playurl/PlayerArgs 的注入、解码能力
函数和响应选择**已更正（task-38）**：原下一步地址 0x103c6e0d0 **无任何 fnval 分支**（该处是 interest builder，参数 cny_active/ab_test_vars/caid）；真实 fnval 点=getter stub 0x117310720 的调用方（resolver helper 族 0x114a5c0a4/0x114a2a928/0x113941a18）与 init stub 0x117392f20 的唯一调用方 0x112118a38（BBPgcOfflineCacheDownloadTimerInternal startKmpDownload:）。同版本执行与服务端接受属运行期；假布尔能力的 2,048 个 fnval
组合及 196 个 qn/登录/配置边界已通过分支实现与位公式的离线等价检查；
撤回 team-c40 的“预加载无能力探测/取自持久 KV”强否定：
RecentPlayerArgs `getPlayerArgs` 0x101655b10 先调用
BBPlayerPreloadUrlParamsHelper.preloadUrlParams（0x101655b44–b58），才将返回字典
桥接解析。helper 0x114397ffc → BBResolverUtils.preloadUrlDeviceParams
0x114a0c21c → supportFnval 0x114a0be60，实际消费 UHD/EAC3/Dolby/HDR/AV1/
HEVC/H266 getter 与实验开关。解析层无硬件 API 不能排除上游能力来源，RTC
独立函数零引用也不能否定此已证链。preloadUrlDeviceParams 有 RAM 缓存初始化门禁，
不能声称每次调用都会实时探测。fourk 在 0x114a0c2dc–c2e4 调用
BBResolverPlatfomSupport.isSupported4K，需继续核桥接实现，不能直接写作 IJK getter。
原始补证 `DerivedData/Validation/independent-dsh-review/c40.md` 及对应 asm；
新增原始补证（root-static-fnval/report.md；root-static-audit 已独立重生成复核）：
`isSupported4K` 0x114a07e68 → IJKFFUtils.isUhdSupported 0x114b10a08 →
HEVC getter；HEVC internal 0x114b10614 与 AV1 internal 0x114b10884 分别以
hvc1/av01 调 VideoToolbox.VTIsHardwareDecodeSupported。HEVC 外层 0x114b10620
按当前 OS 版本读取 UserDefaults 能力缓存；未命中或 OS 不符才探测并回写。
EAC3 getter 0x114b10a1c 在此镜像恒 true，不把所有能力 getter 泛称硬件探测。
preloadUrlDeviceParams 的 fnver/fnval/fourk 只在 RAM 字典 0x120da5540 初建分支
写入；soft_fnval/player_net/force_host 每次调用更新。C++ 软件能力 producer 已证：BBPlayerCoreModule.onModuleInitialize→
IJKAbrParamsInterface.initOnlineParamHandler(BBPlayerIJKConfigAdaptor)→BFCMemexABTest
preset0→38键表→C setter。enable_vod_av1/enable_av1_sw_codec/enable_h266_sw_codec
分别写 byte+3/+6/+8；suppression word+0x18 由 setLowPowerMode 写入。
优化替代初始化路径也已证：Swift任务 PlayerCoreModuleOnModuleInitialized 的body
0x1001c4ce4通过generic objc_msgSend调用同一initOnlineParamHandler，witness
0x11b0bc930和provider数组入口0x1001c517c已对应。优化flag来自
infra.ue.opt.gripper.runnable（default0、once缓存）。这不证明框架实际执行时序；
低功耗setter完整动态/外部触发仍开放；
有界 RAM 引用扫描仅见原getter/初始化写，不能证明不存在间接失效。
实际 9.13 取值和服务端接受仍须分别验证。
