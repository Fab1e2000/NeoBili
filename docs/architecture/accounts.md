# 网络与账号

[架构总览](../ARCHITECTURE.md)


主要接口经过 `APIClient` 校验调用时的账号会话、处理业务信封及选择重试策略；网页请求的
UA、Referer 与显式 Cookie 仍由它组装。App GET、表单、只读 gRPC 和已实现的点击日志请求，
由可注入的 `AppRequestEncoding` 编码，默认实现为 `AppRequestEncoder`。编码器只接收
`AppRequest` 和已校验的 `AppRequestContext`，不读取凭据存储或发起网络请求。
`APIClient` 在编码前统一合并设备公共头，并在异步准备后复核登录代际；不感兴趣等无自定义头的 App 接口也使用同一身份。
`HTTPTransport` 发送已编码请求并记录脱敏诊断、处理已发送 ticket 的失效响应；重试复用同一份请求，写操作使用零重试。
登录、直播和图片各有独立入口，默认 HTTP 传输使用 `AppNetwork.session`。Regression 禁止安全验证 WebKit 的远端初始加载及导航。WBI 与 App 签名各自维护。
非零业务码先于成功数据解码，列表用宽松解码避免单条异常拖垮整页。
推荐、直播与「不感兴趣」及撤销共用实测 iPhone 9.13.0 协议身份：
`build=91300100`、`mobi_app=iphone`、`platform=ios`，客户端参数集中在 `AppClientIdentity`。
硬件名与系统版本读取当前设备，未知机型使用真实硬件标识，不冒充抓包设备。
登录唯一入口为 SMSLoginSheet，SMSLoginModel 管理短信、倒计时和验证状态，SMSPassport 使用与业务相同的 iOS appkey。
同次登录从 DeviceIdentity 取得自己的 buvid 与共享 App 会话。
发短信、提交验证码及安全验证后的授权兑换共用这份身份：local_id=buvid，login_session_id 为本次尝试的 32 位随机编号；请求追踪号每次更新。
地区列表的 id 仅用于界面选择，App 短信发送与验证码提交的 cid 使用 country_id 电话区号（中国大陆为 86），不能发送列表编号 1。
短信写请求不自动重试，重发限制 60 秒，验证码本地按五分钟过期，最终有效性以服务器为准。修改手机号/地区或取消后不接收旧尝试结果。
验证成功后的本地凭据提交失败可重试完成，不重新发送短信；也可重新验证手机号，重发
倒计时仍保留。补授权账号不匹配释放表单但不写入其他账号凭据；会话变化取消原验证，
需关闭后重新开始。账号资料失败不移除通用设置入口，所有退出入口共用会话受保护的确认。
空间关注使用未知/已知关系及读写代次，初读失败可重试；未知关系不推测写入方向，旧名片
不能覆盖已完成写入，旧账号回调不能回填新账号关系，自身账号不提供关注操作。
App 响应必须同时包含账号一致的 token 和 Cookie；status 非零不视为登录成功。已观察到的官方安全页面使用隔离 WebKit，接收真实验证接口的授权 code，再调用 `/x/passport-login/oauth2/access_token`。
安全页面的指定安全中心查询/验证请求通过受限桥接补同次登录的 App 身份和签名，避免无签名网页验证结果直接用于 App 兑换；仅允许 api.bilibili.com 上的 user/info、answer/questions、answer/submit 和 pwd/verify，不开放通用签名接口。真实安全验证后的授权兑换仍需手机验收。
安全页面桥接仅接收 passport HTTPS 主框架消息，不把手机号、验证码或完整验证 URL 写入诊断日志。
`AppLoginRenewal` 实现原生 passport 的 info → timestamp → refresh → 保存 → confirm。
启动恢复与前台激活时异步检查，合并并发；普通检查成功节流 30 分钟、失败退避 60 秒，显式前台激活绕过检查缓存，
无周期定时器，不重放续期/确认写请求。61000 保留本地凭据并标记需重登，同时请求快照不再提供已拒绝的 access key；保留账号标识以进入重新授权路径，不降为访客。普通网络故障不退出账号；资料接口确认网页登录失效时清理本地会话，并在根界面显示“登录已失效”和重新登录入口。
SMS/兑换获得的 Cookie、access token、refresh token、expires_in 成组保存在单个 Keychain 记录，
保存回读确认后才切换内存并确认旧凭据；重启优先整组恢复。续期不改变登录代际，换号/退出则取消旧任务。
旧版没有保存 refresh token 的会话也校验 access token，但不虚构自动续期能力。启动与每次回前台触发有效性检查，回前台检查绕过普通30分钟缓存；并发检查合并，无周期轮询。服务器确认61000后，根界面明确提示App授权失效并提供当前账号的短信重新授权入口；有效网页登录状态保留，网络故障不判为撤销。

显式启用 `NEOBILI_IDENTITY_RESET_DIAGNOSTIC` 的真机 Debug 诊断构建，在身份服务初始化前
一次性清除 App 保存的登录、设备登记、访客、票据和旧行为队列，并生成持久随机 BUVID。
主题、其他偏好和下载内容保留；Keychain 清除失败时停止进入业务界面，不沿用旧登录。
完成标记防止后续启动再次清理，新登录仍需用户完成。普通构建、Release 和 Simulator
不会自动执行该清理；不表示服务器一定接受新登记或新设备推荐一定改善。

普通 Debug 与 Release 共用已在设备对照中确认的国际版请求配置，不依赖诊断编译开关。
App 身份统一使用 `iphone_i/91300300`，statistics 使用 appId 14/version 6.6.0。
首页手动刷新使用 flush 14，播放/布局设置参数与该样本对齐；冷启动、布局切换、翻页
保留此前规则，不以单次刷新推定其他操作。推荐请求头采用该次 CN 网络和语言/商店
地区配置，移除样本中未发送的 device-bin、aurora-zone 和 Referer；其他 App 接口
保留自身设备元数据。账号、用户选择的 BUVID、票据、游标及时间戳仍来自自身状态，
年龄继续省略，不复制广告数据、近期地区记录或未知字段。模板来自该次国际版样本，
不表示所有地区或所有用户的官方参数均相同，也不承诺普遍改善推荐。

另行授权的 `NEOBILI_CAPTURED_DEVICE_DIAGNOSTIC` 在本机 Debug 产物中读取私有
`DeviceIdentityComparison.json`，临时采用本人官方客户端样本的 BUVID/guestid。
资源不进入源码、工程配置或普通构建；缺失/无效资源时停止进入业务界面。诊断设备的
登记和票据使用独立存储重新申请，不与自身设备缓存混用；自身登录、随机编号及原缓存
保留。普通构建和 Release 不读取该资源，回到自身身份。该对照不复制官方登录令牌或票据。
单独变更访客编号的本地对照可用 `registrationScopeGuestID` 保留前一组诊断登记/票据的
存储作用域；随机访客编号在私有资源中固定，不每次启动重新生成，也不覆盖自身访客回执。
私有资源可选 `generationSeedIDFV`，通过 `AppBuvid.generate` 的 Y 分支重新生成编号，
必须与样本 BUVID 完全一致，否则停止进入业务界面。种子可从样本后 32 位还原，但不证明
它是官方当前系统 IDFV；真实值不进入源码或分发构建。
续期 bili_local_id 使用独立的本地设备编号；device_id 优先服务器登记回执，缺失时用该本地编号。
原生请求手动携带 Cookie，不做没有消费者的系统 Cookie/WebKit SSO 同步。
旧扫码/密码协议代码保留用于原有回归，没有生产入口，也不再自动通过扫码链路换取 token。
凭据以 iOS scope 隔离，旧 Android/HD token 保存在原存储但不参与 iOS 请求；缺少 iOS token 时使用当前账号手机号补授权，失败保留原 Cookie。保存前核对账号与登录会话，防止迟到结果覆盖新会话。
官方 fingerprint 是带加密 key/content 的 POST；分析包中的标识及加密依据见
[待确认参数](../research/recommendation-parameters.md)。生产已接入版本受限的 fingerprint 适配器：基于 8.89 公钥和 AES-ECB/PKCS7＋RSA-PKCS1 包装，
提交自身的已实现资料字段，保存真实 bili_deviceId；默认不读取广告标识、运动、相机或未确认的派生字段。
目前材料是已确认字段的子集，不能称为完整官方指纹；9.13 服务端兼容及真机登记尚未验收。
访客登记已接入独立的 RSA 取钥与 AES-CBC/key=IV 加密流程，启动及激活时异步申请；成功的 guest_id 存 Keychain，跨账号保留，失败在下一次激活重试。请求头和 SMS 的 device_tourist_id 共用真实回执。
Ticket 使用自身 Device protobuf 签名申请，返回后存 Keychain，读取不阻塞请求，剩余不足 1800 秒时异步续期；失败保留旧值并退避，响应 x-ticket-status=1 仅更新匹配已发送票据。账号代际/BUVID 隔离及迟到响应保护是 NeoBili 的安全策略，不宣称官方跨账号行为已完全确定。
Device protobuf 使用已确认的字段映射，未知首次追踪时间不填；ticket 的可选安全实验材料、登录 device_meta/dt 尚未接入；bili_local_id 已在续期专用流程接入，短信请求暂不扩展。上述新登记/票据流程的当前服务端接受情况仍须运行验收。
登记失败保留旧的有效编号，冷却两分钟；成功缓存一天并存 Keychain。没有真实登记回执时不发送 device_id。
登录、日志 AppInfo.bilifp 和请求 Device protobuf 字段 14 共用登记结果，不另造随机值。
用户已报告当前短信测试版登录成功且设备管理出现“哔哩哔哩”条目；其他账号与风控分支尚未验收，设备登记和推荐变化分别记录。
已网页登录但缺少 iOS token 时，App 推荐在发请求前提示授权，不再静默发无 token 的请求；
明确未登录的访客仍可请求。`x-bili-mid` 不能替代 access_key，也不代表 App 认证成功。

`DeviceIdentity` actor 管设备标识、凭据快照及登录会话版本；生产凭据存 Keychain，
测试可注入内存存储、独立 defaults 并关闭设备标识联网补取。
`AppAccountSnapshot` 是独立账号值类型；`AppDeviceSnapshot` 保存事件发生时的设备、
账号代际与会话事实，不依赖具体点击模型，也不保存 token/Cookie/ticket。
`AppDeviceProtocol`、`AppDeviceMetadata` 和 `AppDeviceLocale` 编码公共设备/语言头，与推荐响应模型分开。
`AppNetworkMetadata` 读取真实 Wi-Fi/蜂窝状态，提供首页 network/player_net 及 Network protobuf 类型；首个回调前未知，不假报 Wi-Fi。网络质量数据及地区三个头的真实来源/更新链仍有缺口，暂不伪造。
`AccountStore` 区分本地有凭据与服务端已确认登录；暂时网络失败不等同于凭据失效。

写操作不自动重试，包括形式为 GET 的推荐反馈。观看上报、推荐反馈和播放准备绑定
调用时的登录会话；账号切换后的迟到响应不能使用新凭据、返回旧播放清单或回填新缓存。

服务适配器传入的客户端必须沿端点链路传递到底层传输；账号、搜索、视频详情、评论、关注和资料库的读取
使用该实例的凭据快照与 session。测试用独立客户端调用同一端点，验证账号与传输不会落回生产默认图。
写入与取流适配器同时传递客户端和身份对象；Cookie、CSRF、签名上下文和账号代际来自同一注入图。
`HTTPTransport` 接收诊断与响应观察操作，`APIClient` 接收 WBI 签名操作，避免自定义传输回查其他图的状态。

直播与推荐适配器向端点传递所属 client；直播签名复用该 client 的签名器，推荐会话、网络状态、点击队列与过滤配置均可注入，避免独立服务落回另一组全局状态。

认证适配器将同一 URLSession 传给网页和短信登录端点。设备身份的注册、SPI 与续期使用实例持有的原始传输，网络状态也由实例注入；短信响应观察绑定对应身份，不会修改其他服务图的账号状态。

`App/ApplicationServices+Live.swift` 的 `makeLive` 显式组装各个服务适配器；独立图传入自己的 identity、client、session、诊断和上报实例。生产 `live` 通过同一入口组装，普通页面的默认创建方式保持不变。

视频列表的 `VideoFilterDependencies` 绑定同一时长设置与元数据缓存，由 App 组装；列表通过环境传递，Home/Space 模型通过构造器传入。纯时长文本解析属于 Domain 的 `VideoDuration`，持久化设置属于 `Application/Settings`，独立测试使用自己的偏好域与缓存。

身份、WBI 签名、HTTP 客户端、网络状态、推荐会话、诊断和上报队列的生产默认实例在 `App/ApplicationServices+Live.swift` 创建；Data 类型保留显式构造接缝。离线 harness 使用独立的宿主组装与内存凭据，不加载 `ApplicationServices+Live.swift`；复用 `App/NetworkingDefaults.swift` 的便利初始化器，由宿主提供隔离依赖。

`AccountCredentialPersistence` 同步负责账号凭据的格式、兼容存储与写后读回验证。`DeviceIdentity` 保留内存镜像、账号代际和续期任务；只有原子凭据记录验证成功后才发布新登录态，持久化委托不引入新的 await。

身份、签名和传输实现由 `NeoBiliData` 编译。账号凭据快照、服务操作和状态通知名属于 `NeoBiliDomain`；Application 不导入 Data，App 负责将生产身份与客户端交给适配器工厂。

网络会话由 App 组装层持有，Data 通过 `AppNetwork.makeSession()` 保留编译期 Regression 隔离；端点、身份与缓存接收显式传输依赖。离线 harness 创建自己的阻断会话。

首页推荐的成功与失败回调都校验请求所属的账号会话；换号后的旧请求错误不能覆盖当前页面状态。
