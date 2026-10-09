# 架构

NeoBili 是使用 SwiftUI 和 MPVKit 的 iOS 客户端，没有单独部署的服务器。“前后端解耦”在本项目中指：页面和业务状态依赖服务契约，网络、签名及存储实现通过适配器提供。当前仍使用一个 App target；目录边界由检查脚本维护，并非独立 Swift 模块。

构建、测试和设备使用统一见[开发与测试](DEVELOPMENT.md)。

## 目录与依赖方向

| 目录 | 负责什么 | 不应放入什么 |
| --- | --- | --- |
| `App` | 启动、根路由、生产依赖组装 `ApplicationServices+Live` | 接口字段和响应解析 |
| `Features` | SwiftUI 页面、交互和展示组件 | HTTP 请求、签名、凭据读取 |
| `Application` | 页面状态、加载任务、分页、缓存及播放协调 | URLSession、接口地址和传输协议 |
| `Domain/Services` | 按业务划分的可注入操作、账号快照、实时通道协议 | 生产客户端单例和网络实现 |
| `Domain/Models` | 共享值、解码模型、筛选规则和设置值 | 页面类型、播放器实例、网络访问 |
| `Data/Services` | 将服务契约连接到生产实现的适配器 | SwiftUI 页面状态 |
| `Data/Networking` | 端点、传输、身份、签名、响应解析及上报 | View / ViewModel 依赖 |
| `Data/Media` | 图片传输与缓存、弹幕下载 | 页面导航 |
| `Platform` | mpv、系统媒体控制等平台适配 | 业务页面 |
| `Core/UI`、`Core/Extensions` | 共享组件、主题、格式化和交互工具 | 业务接口调用 |
| `Core/Diagnostics` | 显式启用的诊断与回放工具 | 默认后台探测 |

通常的请求路径是：`View → Application model → Domain service → Data adapter → APIClient`。简单的一次性操作可以由 View 使用环境中的服务完成；分页、重试和长任务由状态模型持有。

## 服务如何注入

`ApplicationServices` 是按业务分组的值类型。`App/ApplicationServices+Live.swift` 组装生产实现；页面通过 `EnvironmentValues.applicationServices` 取得依赖。模型通过初始化参数接收服务或更小的 loader / writer 闭包。已有的默认初始化方式仍使用生产组装，方便普通页面创建。

测试为当前模型创建独立依赖，不替换全局单例。只实现该测试需要的操作；未配置操作抛出明确错误，不能假装成功。测试创建的服务应随模型传入其子模型，避免子模型意外使用生产默认值。`AccountSessionClient` 管理登录存储边界；`LiveDanmakuStreaming` 管理实时通道，展示模型接收连接状态、热度及消息事件。

服务契约与线上协议名有部分对应，便于核对研究证据；调用方不接触 `APIClient`、`DeviceIdentity` 或端点 URL。`Live*Service` 负责将领域操作映射到现有协议实现。测试若要验证传输行为，应直接注入端点的客户端；服务单元测试则替换操作闭包。

## 状态与任务所有权

`NowPlayingStore` 从打开到关闭持有当前媒体、详情模型和返回历史。`PlayerViewModel` 协调播放、画质、备用源与观看记录，平台会话负责内核。账号切换或媒体切换后，旧标识的回调不能修改新状态。

页面模型持有自己的加载任务。共享缓存持有共享下载任务，单张卡片退出只取消自己的等待。直播实时连接拥有认证、心跳和重连任务，`stop()` 统一终止；展示模型拥有列表合并和 SC 历史任务。

详细规则按问题阅读：

- [账号、身份与请求](architecture/accounts.md)
- [播放与观看记录](architecture/playback.md)
- [列表、图片与取消](architecture/lists-images.md)
- [设置分类与持久化](SETTINGS.md)

## 如何扩展

1. 在 `Domain` 定义调用方需要的数据和操作，避免引用页面嵌套类型。
2. 在 `Data` 实现接口适配，复用现有身份校验、错误处理和取消机制。
3. 在 `App` 组装生产依赖，在 `Application` 管理操作状态，在 `Features` 呈现结果。
4. 测试业务状态时注入受控服务；测试端点时使用受控传输。不要为了运行单元测试读写真实账号。
5. 移动源码后同步离线测试的输入路径，并运行 `python3 scripts/check-architecture.py` 和开发指南中的相关检查。

`project.yml` 是工程配置来源；源码采用 synchronized folder，单纯移动 Swift 文件不需要手工修改工程文件。只有配置发生变化时才修改配置并重新生成工程。
