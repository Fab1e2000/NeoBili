# 关闭小窗后的退出转场修复

关闭小窗时，退出先暂停并取消未完成加载，保留播放器和页面至原生转场的 onDismiss；之后才同步销毁内核和清空数据。转场期间固定收缩阶段，避免暂停触发第二段尺寸动画。退出中重新打开同一视频会重新加载，旧完成回调不能关闭新页面。

- iPhone 17 真机回归：27 项通过，0 失败、0 跳过（MiniPlayerTests 和 MiniPlayerSurfaceTests）。
- Debug build-for-testing、Release build 与 diff 检查通过。
- Release 已安装；安装和启动回执见同目录 JSON。
- 未使用 Simulator。生命周期测试通过不等同于逐帧帧率测量。
- 测试运行记录仍有音频会话主线程调用的系统警告，详见 device-tests.json。

完整测试结果：`/tmp/NeoBiliExitLifecycle-20260912.xcresult`。
