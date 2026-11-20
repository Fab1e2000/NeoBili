# 历史首页请求对照

[研究导航](../README.md) · [本主题目录](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)

## 已授权本地对照的执行边界与当前结果

本节保留已授权的三次 `feed/index` GET 记录。样本使用国际版
`mobi_app=iphone_i/build=91300300`，statistics 为 appId 14/version 6.6.0。
当前应用采用的请求身份另见[网络与账号](../../architecture/accounts.md)。
原始材料保存在忽略的 `DerivedData/Validation/recommendation-network-s1/`；正文只列脱敏结果。

三组保留相同业务参数和时间戳，按该时间戳重新签名；实际起始间隔约 18.0/17.8 秒。
第三组恢复正确 sign，并相对第一组增加捕获 ticket。

| 相对基线变化 | HTTP | 业务 code | 响应与视频编号交集 |
| --- | --- | --- | --- |
| 正确 sign，无 ticket | 200 | 0 | 10 项，均为 goto=av |
| 仅修改 sign 首字符 | 200 | 0 | 10 项，均为 goto=av；与基线交集为 0 |
| 正确 sign，加入捕获 ticket | 200 | 0 | 10 项，均为 goto=av；与基线交集为 0 |

该次端点及参数组合接受了修改后的 sign，验签行为仍需其他输入和通道的独立证据。
捕获签名的两种离线编码复算都匹配，但样本没有 `!*'()`，该字符范围没有被此样本覆盖。
捕获 ticket 的实际签发时间、有效性和服务器使用情况未记录。

请求未携带 Cookie 或 authorization 头，未另行校验账号。三次连续读取可能推进推荐状态；
记录范围为响应结构、业务码与列表差异。曝光、观看、互动、长期补发及推荐效果需要各自的运行记录。
