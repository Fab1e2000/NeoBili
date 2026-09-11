# 2026-09-10 真机验证

设备为已配对的 iPhone 17；使用 `platform=iOS` 真机目标，未启动或使用 Simulator。

Debug XCTest：**87 项通过，0 失败**，执行测试耗时约 24.8 秒。

| 范围 | 测试数 |
| --- | ---: |
| 自定义动画开关 | 3 |
| 动态展开物理与几何 | 6 |
| 动态选择器原有行为 | 5 |
| 首页布局 | 4 |
| 播放区收缩 | 8 |
| 动态视频画幅 | 7 |
| 小窗状态、会话复用、加载退出、拖动边界 | 10 |
| 图片下采样、缓存与预加载取消 | 5 |
| 续播状态与存储 | 8 |
| 播放源、事件与播放器布局 | 15 |
| 渲染画幅 | 2 |
| 竖屏过滤 | 4 |
| 下拉刷新 | 7 |
| 系统正在播放信息 | 1 |
| 竖屏全屏方向 | 2 |

测试使用应用实际类型，网络依赖采用注入的固定数据；小窗测试验证同一 `PlayerViewModel` 与 mpv session 的身份、播放时间、播放状态及页面状态保留。物理回归验证手指位移与展开进度线性对应，60/120 Hz 与跨帧计算结果一致。这里未把单元测试视为实际触屏观感或视频帧率测量。

完整结果保存在本次构建的 `/tmp/NeoBiliMotionMiniPlayerTests-20260910.xcresult`，日志为 `/tmp/neobili-motion-mini-tests.log`。

另外，`offline-harness/run.sh` 和 `offline-harness/performance.sh` 均通过。性能测量的固定图片和持久化测试范围见同目录 README。

最终 `Release` 真机构建通过，已使用 `devicectl` 安装到这台 iPhone 17 并成功启动 `com.elsterlee.NeoBili`。安装与启动记录分别为 `/tmp/neobili-motion-mini-install.json`、`/tmp/neobili-motion-mini-launch.json`，构建日志为 `/tmp/neobili-motion-mini-release.log`。
