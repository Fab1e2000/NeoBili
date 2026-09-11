# 画质、播放器显隐与简介布局验证

日期：2026-09-10。设备为已配对的 iPhone 17；构建目标为 `iphoneos`，全程未启动 Simulator。

## 本次修改

- 画质列表合并服务端声明与实际轨道。首次响应缺少所选画质地址时，按对应 qn 重新请求；只有实际返回该档位才切换。登录请求不再带访客试看标志。权限降档、请求失败保留原播放源；换源保留进度、播放意图和小窗归属，并隔离旧内核的迟到事件。
- 视频页用同一份显隐状态衔接初始封面和播放器；加载期间默认隐藏控件，点击可显示或收起。首播开始也不会重启正在使用菜单的自动隐藏计时。
- 画质、音质胶囊按显示文字测量宽度，在窄屏压缩可用空间，同时保留至少 48 pt 的点击区域。
- 暂停后的收缩以同一滚动距离驱动画面高度与一个连续的色层。安全区、画面和 10 pt 间隔不再独立跳变。只有完整收起时粉色栏接管点击；播放、加载仍保持原有限位。
- UP 主整行胶囊和可展开简介卡片采用原生 Liquid Glass，保留独立的个人空间、关注和展开操作。

## 回归与截图

首轮真机结果：`/tmp/NeoBiliQualityDetails-20260910.xcresult`，95 项中 94 项通过，简介截图测试的复用坐标探针未返回 canvas 坐标。修复测试的主动采集与等待后需单独复查；没有因此删除几何断言或修改产品布局。

本轮已通过的重点：11 项画质逻辑、16 项播放、9 项续播、16 项小窗、16 项收缩几何、15 项直播模型、10 项播放器样式以及 1 项包含 7 个状态的收缩快照。临时主机测试的边界见 [quality-regression.md](quality-regression.md)。

`screenshots/` 下播放器与收缩截图来自真机 UIWindow 中的生产组件，背景为明确标注的本地静态测试画面；它们证明布局、颜色和命中关系，不作为网络播放或真实手指操作证据。

已人工检查：完整屏幕的上下工具栏、动态画质宽度、加载默认隐藏与显隐切换、暂停收缩 50% 的连续色层。Debug 测试构建与 Release 构建均通过。

## 安装与未完成的真机复查

- 最后增量测试构建通过：`/tmp/NeoBiliQualityDetails-final-build.log`。包含修复后的简介探针、新增公开 4K 解码测试，以及加载过程中打开菜单的自动隐藏竞态修复。
- 最后复查尝试：`/tmp/NeoBiliQualityDetailsFinal-20260910.xcresult`。iOS 明确返回 `Xcode cannot launch NeoBiliTests on iPhone because the device is locked`，等待解锁后仍未能启动，因此中止等待，不能把这一轮计为通过。
- Release 已成功安装到 iPhone 17。`devicectl` 结果：`/tmp/neobili-quality-details-install.json`，bundle ID `com.elsterlee.NeoBili`，安装数据库序号 `5244`。
- Release 可执行文件 SHA-256：`0b5790c032ac35988c93069b5f83fcec2a79d29f4a67ff5fda81f6a87f3765c3`。
- 安装后的启动尝试遇到设备隧道连接超时，结果位于 `/tmp/neobili-quality-details-launch.json`；没有声称已成功启动新版。

**尚未完成**：修复测试探针后的简介五态快照、最终菜单竞态修改的真机复查、正常账号下公开 4K 视频的真实解码首帧验证。4K 档位逻辑已通过真机单元测试，但不能据此声称已在当前账号播放出 3840×2160。解锁并恢复设备连接后，使用正式的 `VideoQualityDeviceSmokeTests`，环境变量 `NEOBILI_VIDEO_QUALITY_SMOKE=1` 继续验收，并在测试后重新安装 Release。


## 15:46 后续验收

此前因锁屏中断的简介五态与实际4K解码测试均已在iPhone17通过；真实解码尺寸3840×2160，所选qn120。见[后续验证记录](../related-glass/validation.md)。先前锁屏、安装与启动失败记录保留为当时状态。
