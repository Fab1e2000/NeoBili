# 推荐实现核查与改进建议

本文保留官方协议的逐项证据和版本边界，供当前实现核查使用。NeoBili 已接入设备/访客登记、票据、点击/曝光、真实观看与登录续期；接口存在或回归通过不证明服务端推荐效果。下述建议是核查清单，不表示每项仍缺实现；旧源码行号需按符号定位当前实现。

本文按主题拆分。先选择下面的章节；函数地址、字段编号和未决结论保留在对应章节中。术语说明见[研究阅读指南](research/README.md)。

## 本机校验范围与入口

[阅读本章](research/implementation/validation.md)

## 证据与判定边界

[阅读本章](research/implementation/evidence.md)

## 当前差异清单

<a id="r01-首页参数必须分版本配置能力设置和操作状态p1"></a>
<a id="r02-播放能力和画质不能由一个首页常量代表p1"></a>
<a id="r03-屏幕附加内容有已证实结构差异p2"></a>
<a id="r04-登录事件启动消费和横幅失效不是同一生命周期p1"></a>
<a id="r05-自身-buvid-生成与官方跟踪编号不同p0"></a>
<a id="r06-指纹访客登录资料需要保存各自真实结果p0"></a>
<a id="r07-ticket-是独立服务且有启用边界p1依赖r06"></a>
<a id="r08-卡片追踪到观看关联已接通但曝光上下文不完整p0p1"></a>
<a id="r09-点击字段不能直接套某套通用模板p1"></a>
<a id="r10-展示及每段可见时长的采集和发送p1依赖r08r11"></a>
<a id="r11-position-必须保存来源不能一律按ui行号生成p0阻挡曝光定稿"></a>
<a id="r12-日志公共字段与事件缓存策略有明确差异p1"></a>
<a id="r13-观看事实与历史位置已分开触发补全仍须逐项对照p1"></a>
<a id="r14-过滤去重和预加载会改变展示不能被误算成服务端推荐p1"></a>
<a id="r15-不感兴趣上下文最小化且旧卡缺来源代际校验p1"></a>
<a id="r16-公共登录播放和启动会话要分别命名p1"></a>
<a id="r17-观看结束报告没有官方旧包的持久补发层p1"></a>
<a id="r18-公共身份头locale和网络资料需按通道补齐p2身份部分依赖r06"></a>
<a id="r19-app签名的保留字符与旧包存在差异p1当前版本待验证"></a>
<a id="r20-首页磁盘兜底不同于保留内存旧卡p2账号来源隔离为实施前置"></a>
<a id="r21-app启动与活动段缺实现旧包再次提交不应直接复制p2需-913-样本"></a>
<a id="r22-心跳时间回执缺实现公共时间辅助与观看计时须分开p1辅助来源-p2-需-913-样本"></a>
<a id="r23-应用定时心跳未实现不能用历史checkpoint替代p2"></a>
<a id="r24-兴趣引导为独立可选功能安装标记与迟到回执须另建所有权p2条件性"></a>
<a id="r25-播放器操作日志已接入子集单位与观看报告分开p2"></a>
<a id="源码锚点索引本轮逐条核查"></a>

[阅读本章](research/implementation/differences.md)

## 关联业务边界：稍后再看

[阅读本章](research/implementation/watch-later.md)

## 关联业务边界：LatestHistory 与本机续播

[阅读本章](research/implementation/history.md)

## 关联业务边界：分享菜单

[阅读本章](research/implementation/sharing.md)

## 社区资料的辅助核查

<a id="来源范围与判定"></a>
<a id="逐项对照"></a>
<a id="需要保留的冲突与实现差异"></a>

[阅读本章](research/implementation/community.md)

## 接入顺序与验收

[阅读本章](research/implementation/acceptance.md)

## 已授权本地对照的执行边界与当前结果

[阅读本章](research/implementation/device-comparison.md)

## 未决证据与维护范围

<a id="已闭合"></a>
<a id="明确残余"></a>
<a id="不成立"></a>

[阅读本章](research/implementation/maintenance.md)
