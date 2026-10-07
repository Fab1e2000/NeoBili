# 文档导航

首次 fork 不必先读协议研究。先运行应用，再按要修改的功能定位代码。

| 目的 | 阅读入口 |
| --- | --- |
| 构建、测试、签名、提交与发布 | [开发与测试](DEVELOPMENT.md)，开发流程唯一维护入口 |
| 理解目录、状态所有权与请求链路 | [架构](ARCHITECTURE.md) |
| 添加设置与本地化 | [设置开发](SETTINGS.md) |
| 了解用户可见行为 | [使用手册](USAGE.md) |
| 贡献与 PR 约定 | [贡献指南](../CONTRIBUTING.md) |
| 查看已发布版本与待发布说明 | [版本说明](releases/) |

## 协议研究

这些材料按问题查阅；历史样本及推断不等于当前实现或服务端保证。

| 内容 | 入口 |
| --- | --- |
| 请求规则、证据版本及实现契约 | [客户端契约](CLIENT_API_IMPLEMENTATION_CONTRACT.md) |
| 实现核查、已接入规则与剩余差异 | [推荐实现核查](RECOMMENDATION_IMPLEMENTATION_REVIEW.md) |
| 静态分析的原始协议与调用链依据 | [网络协议研究](CLIENT_NETWORK_PROTOCOLS.md) |
| 已采集的操作与现象 | [推荐观察](RECOMMENDATION_OBSERVATIONS.md) |
| 采集操作与动态验证范围 | [动态分析](DYNAMIC_ANALYSIS.md) |
| 参数含义及已确定处理策略 | [参数记录](../NOTSURE.md) |

原始采集、个人账号与设备凭据留在仓库外。构建和验证结果保存在忽略的
`DerivedData/Validation/`，不能作为 fork 后必需的输入。
