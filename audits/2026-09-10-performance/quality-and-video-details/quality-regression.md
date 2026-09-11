# 视频清晰度回归记录

日期：2026-09-10。此记录对应本次 4K 档位识别、按所选 `qn` 补取播放地址，以及换源状态保护的修改。

## 已执行的离线检查

在 macOS 主机上使用 Swift 6 编译并运行了一次临时逻辑 harness，随后在加入解码尺寸隔离断言后再次运行；两次均为 **11 个测试方法全部通过**。

临时 harness 使用当时工作区中的 `PlayerViewModel`、`PlaybackSourceBuilder`、播放响应模型、`PlaybackProgressStore` 等生产逻辑源码。执行器调用 `NeoBiliTests/PlayerQualityTests.swift` 中的测试方法，将 XCTest 断言映射为失败即停止的主机断言；mpv、网络请求、音频会话及系统媒体中心使用本地替身。它没有初始化真实播放内核、读取账号凭据、执行远程写操作或使用 Simulator。

这是离线逻辑检查，不是真机 XCTest 或解码验证。临时执行器没有作为长期维护的测试入口保留，因此此处不提供依赖易失临时文件的复现命令。可维护、可重现的正式测试源是 [`NeoBiliTests/PlayerQualityTests.swift`](../../../NeoBiliTests/PlayerQualityTests.swift)。

| 检查 | 结果 |
| --- | --- |
| 服务端声明 4K 时能识别该档位，但不将声明当作已取得的轨道，也不凭空增加 8K | 通过 |
| 登录请求不带匿名 `try_look`；取流上下文不生成随机 `dm_` 指纹 | 通过 |
| 缺失 4K 地址时请求 `qn=120`，打开对应真实返回轨道，保留暂停、播放位置及小窗渲染归属 | 通过 |
| 区分选中轨道元数据尺寸与实际解码尺寸；换源清空解码尺寸，拒收旧内核的尺寸事件 | 通过 |
| 服务端降档或返回会员要求时，保留原会话、实际选中画质、进度和播放状态 | 通过 |
| 取流期间旧视频继续更新位置；暂停意图保留；重复点击不重复取流 | 通过 |
| 关闭后拒收迟到的质量响应及开流完成/失败 | 通过 |
| 取流失败保留原播放；旧主 CDN 开流失败不能覆盖已恢复的备用内核 | 通过 |
| 音质切换复用已有音轨，不触发视频质量请求 | 通过 |
| 实际选中画质来自打开的轨道，不能把较高的配置偏好显示成已取得的画质 | 通过 |

另外，以下独立的、已保留在仓库内的主机检查也完整通过：

```sh
./offline-harness/run.sh
```

该脚本验证既有业务逻辑、续播、画幅、动画等回归，并编译实际 `BiliAPI` 与视频模型。它目前不包含上述临时质量执行器，不能将脚本通过等同于重新执行了 11 项质量测试。运行输出包含已有的可选值插值和无必要 `await` 编译警告，没有检查失败。

## 正式复现方式

在项目的 Xcode 测试导航器中选择 `NeoBiliTests/PlayerQualityTests`，使用已配对并解锁的 **iPhone 17 真机**作为测试目标，运行该测试类的全部 11 个测试方法。正式测试使用注入的取流/开流替身、空进度上报器和独立的临时 `UserDefaults` suite；不会更改用户观看记录。不要选择 Simulator。

质量协议依据包括 [PiliPlus 播放模型的声明档位与缺失轨道检查](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/models/video/play/url.dart)及本地参考源码 `references/PiliPlus/lib/pages/video/controller.dart` 的 `_supplementVideoQualities`。服务端声明的档位只用于识别可请求的格式；仍需正常取流，并核对返回轨道，不能据声明推断会员权限。

## 公开 4K 验证素材

视频：[《【4K HDR 60fps】向云端 视觉盛宴 魅力自然》](https://www.bilibili.com/video/BV1po4y177z8/)。通过公开搜索找到该条视频后，仅对其[官方视频详情接口](https://api.bilibili.com/x/web-interface/view?bvid=BV1po4y177z8)进行了一次只读查询，返回 `code=0`，得到以下元数据：

```json
{
  "bvid": "BV1po4y177z8",
  "cid": 1163679532,
  "title": "【4K HDR 60fps】向云端 视觉盛宴 魅力自然",
  "dimension": { "width": 3840, "height": 2160, "rotate": 0 },
  "duration": 250
}
```

**截至本记录写入时，仍待真机解码验证。** 官方详情中的 3840×2160 是稿件元数据，不证明当前账号已经获准取得 4K 地址，也不证明播放器已完成 4K 解码。后续真机检查需要分别确认正常账号请求取得 `qn=120` 的对应轨道、实际选中轨道尺寸，以及首帧后的 `decodedVideoWidth/decodedVideoHeight`；如服务器未授权，应记录限制并验证旧画质继续播放。本记录不包含账号凭据或签名播放 URL。
