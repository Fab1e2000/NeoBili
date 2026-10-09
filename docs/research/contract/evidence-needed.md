# 后续验证需要的证据

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

<a id="需要其他席位补的证据请求"></a>

## 后续验证需要的证据

以下问题需要进一步定位实现或核对已有证据。新增结果应同步到对应协议章节和契约条目。

1. **访客取公钥接口的 path/字段**：`+[BFCAccountGolangApi requestPublicKeyWithCompletionBlock:]` 的实现体（下一步 `$PY disassemble.py 0x116047568 0x116047640`）。
2. ~~**`feedback` 实际取哪一个 Laser wrapper 值**~~：**已有证据**（team-c13 A1：`+[BFCLaserApi
   reportFeedback:…]` 0x114a89448 的 baseUrl 装载点 0x114a89548 = `+[BFCLaserConst laser2Url]`
   0x114a8dc20 → `+[BFCLaserConstWrapper laser2URL]` 0x104e31174 = `…/laser2`；另三条
   `reportFawkes*` 分别用 reportCmdUrl/laserUrl/silenceUrl。剩余只是 raw0 备用
   `uploadURL` 与 UP-01 `preupload` 的分支对应，已在 UP-03 第 9 项登记）。
3. **覆盖清单行的官方侧等级复核**：表 ② 中“未覆盖或只到局部”的模块，是否要把某行从“局部”提升，必须给出相应级别的证据后才能调整覆盖状态。

已有证据、不再需要外部补证的请求（保留记录）：设备登记 URL/host 与 signType（team-c3 S2 → DEV-02）；
访客登记 URL/body（team-c3 S3.3 → DEV-03）；`setIp:`/`setUserAgent:` 接收者类型（team-c3 S1 → DEV-08 所选流程证据）；
Laser 四个 wrapper 端点（Lead → UP-01/UP-02/UP-03）；**Neuron realtime URL**（样本证据：硬编码 CFString
0x11d3dac90/0x11d3dacb0，无服务端下发 → LOG-01）；**PlayURL gRPC 全名**（样本证据：包 `bilibili.app.playurl.v1`、
服务 `PlayURL` → PLAY-01）。
