# 网络与账号

[架构总览](../ARCHITECTURE.md)


主要接口经过 `APIClient` 校验调用时的账号会话、处理业务信封及选择重试策略；网页请求的
UA、Referer 与显式 Cookie 仍由它组装。App GET、表单、只读 gRPC 和已实现的点击日志请求，
由可注入的 `AppRequestEncoding` 编码，默认实现为 `AppRequestEncoder`。编码器只接收
`AppRequest` 和已校验的 `AppRequestContext`，不读取凭据存储或发起网络请求。
`APIClient` 在编码前统一合并设备公共头，并在异步准备后复核登录代际；不感兴趣等无自定义头的 App 接口也使用同一身份。
`HTTPTransport` 发送已编码请求并记录脱敏诊断、处理已发送 ticket 的失效响应；重试复用同一份请求，写操作使用零重试。
登录、直播和图片各有独立入口，默认 HTTP 传输使用 `AppNetwork.session`。WBI 与 App 签名各自维护。
非零业务码先于成功数据解码，列表用宽松解码避免单条异常拖垮整页。
推荐、直播与「不感兴趣」及撤销共用实测 iPhone 9.13.0 协议身份：
`build=91300100`、`mobi_app=iphone`、`platform=ios`，客户端参数集中在 `AppClientIdentity`。
硬件名与系统版本读取当前设备，未知机型使用真实硬件标识，不冒充抓包设备。
登录唯一入口为 SMSLoginSheet，SMSLoginModel 管理短信、倒计时和验证状态，SMSPassport 使用与业务相同的 iOS appkey。
同次登录从 DeviceIdentity 取得自己的 buvid 与共享 App 会话。
发短信、提交验证码及安全验证后的授权兑换共用这份身份：local_id=buvid，login_session_id 为本次尝试的 32 位随机编号；请求追踪号每次更新。
地区列表的 id 仅用于界面选择，App 短信发送与验证码提交的 cid 使用 country_id 电话区号（中国大陆为 86），不能发送列表编号 1。
短信写请求不自动重试，重发限制 60 秒，验证码本地按五分钟过期，最终有效性以服务器为准。修改手机号/地区或取消后不接收旧尝试结果。
App 响应必须同时包含账号一致的 token 和 Cookie；status 非零不视为登录成功。已观察到的官方安全页面使用隔离 WebKit，接收真实验证接口的授权 code，再调用 `/x/passport-login/oauth2/access_token`。
安全页面的指定安全中心查询/验证请求通过受限桥接补同次登录的 App 身份和签名，避免无签名网页验证结果直接用于 App 兑换；仅允许 api.bilibili.com 上的 user/info、answer/questions、answer/submit 和 pwd/verify，不开放通用签名接口。真实安全验证后的授权兑换仍需手机验收。
安全页面桥接仅接收 passport HTTPS 主框架消息，不把手机号、验证码或完整验证 URL 写入诊断日志。
`AppLoginRenewal` 实现原生 passport 的 info → timestamp → refresh → 保存 → confirm。
启动恢复与前台激活时异步检查，合并并发；成功检查节流 30 分钟，失败退避 60 秒，
无周期定时器，不重放续期/确认写请求。61000 保留本地凭据并标记需重登，同时请求快照不再提供已拒绝的 access key；保留账号标识以进入重新授权路径，不降为访客。普通网络故障不退出账号。
SMS/兑换获得的 Cookie、access token、refresh token、expires_in 成组保存在单个 Keychain 记录，
保存回读确认后才切换内存并确认旧凭据；重启优先整组恢复。续期不改变登录代际，换号/退出则取消旧任务。
旧版没有保存 refresh token 的会话继续可用，但需短信重登或同账号补授权才能获得自动续期能力。
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
