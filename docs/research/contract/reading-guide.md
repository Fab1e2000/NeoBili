# 如何使用本文档

[研究导航](../README.md) · [本主题目录](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)

本章保留对应样本的字段、调用链和证据限制。应用应实现的规则见[实现契约](../../CLIENT_API_IMPLEMENTATION_CONTRACT.md)，当前接入情况见[实现核查](../../RECOMMENDATION_IMPLEMENTATION_REVIEW.md)。静态分析结果不能单独证明当前服务器行为。

## 如何使用本文档

- **先读哪一条**：按业务链找条目标题。索引表给出条目 ID、端点/方法与主文档章节。
- **每条记录的九项**：1) 端点/服务方法 2) 触发时机 3) 请求头 4) 参数及来源
  5) 签名与编码规则 6) 响应结构 7) 与 NeoBili 当前实现的差异 8) 证据等级与版本
  9) 残余不确定项。第9项须说明已覆盖范围、未闭合具体链与下一步动作。暂未找到命令或工具失败不等于静态不可判；只有明确缺失的运行值/外部实现等边界才归运行期。
- **证据等级**沿用主文档：**8.89 静态**（第三方处理的 iOS 8.89.0/build 88900100 主程序反汇编）、
  **9.13 抓包**（既有官方 9.13/build 91300300 样本；其离线解析产物在 `DerivedData/Validation/capture-resume/`，仍按 9.13 抓包计级）、
  **9.13 抓包（线级）**（本机 `work/bili-capture/` 的 32 组 `.flows`：官方 App **9.13.0/build 91300100**（`bili-universal`，主体）与 **9.13.0/build 91300300**（`bili-overseas` 与 `bilibili/91300300` 旧日志客户端）；共 9,496 个请求 / 288 个端点，HTTP/2 为主。证据 `DerivedData/Validation/team-c12/findings.md` 及同目录 `capture-index.jsonl`、`endpoint-inventory.json`、`endpoint-params.jsonl`、`wire-feed.jsonl`、`metadata-bin.jsonl`、`neuron-events.jsonl`、`wire-sign.jsonl`；文中凡标“9.13 抓包（线级）”者为**该批样本观测值**，不是协议常量。**build 91300100 与 91300300 分别标注、不可互相顶替**）、**本地实测**（已授权的三次 feed/index GET，另含 NeoBili Debug 客户端对照实验 `DerivedData/Validation/local-behavior-experiment/`；材料索引见 `DerivedData/Validation/team-c10/findings.md`）、
  **当前源码**（NeoBili 工作区）。跨版本一致性逐条标注，不默认成立。
- **候选与已证分开**：主文档里的“候选”“下一步”措辞在本文一律保留，不改写成结论。
- **不写凭据**：本文不记录 appkey/secret、账号、设备编号、token、ticket 或指纹常量；
  需要值时只给“在哪一层读取”和文件锚点。
- **静态不可判**：一律写成“静态不可判 + 原因 + 需要什么运行期证据 + 建议取证方式”，
  并汇总进文末表 ①。本文不使用“完整”一类措辞描述覆盖范围。
- **验收口径**：56个契约ID、17行U表和未决词频是索引/文本统计，不代表正确性或完成度。每项关闭须能对应原始证据与版本边界；有界零引用不能证明全局不存在。
- **共享 stub 判据**：`selref` 零引用不等于无调用；ObjC 方法入口直接 `find_callers` 常得 0。
  需要分派证据时先找 `_objc_msgSend$<selector>` stub，再查该 stub 的调用方。
