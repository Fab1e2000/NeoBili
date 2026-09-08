# NeoBili

使用 SwiftUI 和 Swift 6 开发的第三方哔哩哔哩 iOS 客户端，支持 iOS 26 及以上版本，播放内核使用 MPVKit。

## 功能

- 推荐视频、搜索、关注动态与 UP 主空间
- 视频播放、播放控制与清晰度选择
- 评论、收藏、稍后再看与历史记录
- 账号登录与个性化设置

## 构建

1. 使用支持 iOS 26 SDK 的 Xcode 打开 `NeoBili.xcodeproj`。
2. 等待 Swift Package Manager 解析 MPVKit 依赖。
3. 在 Signing & Capabilities 中选择自己的开发团队，按需修改 Bundle Identifier。
4. 选择 `NeoBili` scheme 和目标设备进行构建。

项目已配置 AppIcon，构建时会自动使用资源目录中的粉色播放图标。

仅编译真机目标、不签名：

```sh
xcodebuild -project NeoBili.xcodeproj -scheme NeoBili \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

工程生成配置保存在 `project.yml`，需要重新生成工程时可使用 XcodeGen。

## 文档与测试

- [架构说明](docs/ARCHITECTURE.md)
- [第三方依赖说明](THIRD_PARTY_NOTICES.md)
- `NeoBiliTests/`：应用单元测试
- `offline-harness/`：可在 macOS 上运行的离线逻辑测试，执行 `zsh offline-harness/run.sh`

NeoBili 是独立的第三方项目，与哔哩哔哩无官方关联。
