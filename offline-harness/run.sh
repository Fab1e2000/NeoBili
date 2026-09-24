#!/bin/zsh
# 在 macOS 宿主机上离线运行业务逻辑测试（不需要 Simulator、不需要真机）。
#
# 每次运行都从仓库当前源码复制被测文件，副本永不漂移；harness 自带的只有
# 测试本身（src/Tests.swift）和最小依赖桩（src/Stubs.swift）。
#
# 用法：./run.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap "rm -rf $BUILD_DIR" EXIT

APP="$ROOT/NeoBili"
cp "$APP/Core/Models/VideoDimension.swift" \
   "$APP/Core/Models/VideoDurationFilterSettings.swift" \
   "$APP/Core/Models/PortraitVideoStore.swift" \
   "$APP/Core/Models/VideoDimensionProviders.swift" \
   "$APP/Core/Models/VideoModels.swift" \
   "$APP/Core/Models/FollowModels.swift" \
   "$APP/Core/Models/AccountModels.swift" \
   "$APP/Core/Models/DynamicVote.swift" \
   "$APP/Core/Models/CommentModels.swift" \
   "$APP/Core/Networking/APIClient.swift" \
   "$APP/Core/Networking/BiliAPI.swift" \
   "$APP/Core/Networking/AppRecommendationPage.swift" \
   "$APP/Core/Networking/BiliPassport.swift" \
   "$APP/Core/Networking/WBISigner.swift" \
   "$APP/Core/Networking/DeviceIdentity.swift" \
   "$APP/Core/Networking/KeychainStore.swift" \
   "$APP/Core/Networking/AppSigner.swift" \
   "$APP/Core/Networking/URL+Bili.swift" \
   "$APP/Core/UI/EnvironmentAction.swift" \
   "$APP/Features/Danmaku/DanmakuModels.swift" \
   "$APP/Features/Home/HomeViewModel.swift" \
   "$HARNESS/src/Tests.swift" \
   "$HARNESS/src/Stubs.swift" \
   "$BUILD_DIR/"

swiftc -parse-as-library -o "$BUILD_DIR/harness" "$BUILD_DIR"/*.swift
"$BUILD_DIR/harness"

# 单独验证 SwiftUI Binding 捕获的所有权，不启动任何界面或设备。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Core/UI/EnvironmentAction.swift" \
    "$HARNESS/src/EnvironmentActionLifetime.swift" \
    -o "$BUILD_DIR/action-lifetime"
"$BUILD_DIR/action-lifetime"

# 验证真实入场状态逻辑，不创建窗口或启动设备。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Core/Models/VideoEntranceClock.swift" \
    "$HARNESS/src/VideoEntranceRegression.swift" \
    -o "$BUILD_DIR/video-entrance"
"$BUILD_DIR/video-entrance"

# 续播存储和 mpv 事件顺序、内联画幅与固定渲染表面的真实逻辑。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/Player/PlaybackProgressStore.swift" \
    "$HARNESS/src/PlaybackResumeRegression.swift" \
    -o "$BUILD_DIR/playback-resume"
"$BUILD_DIR/playback-resume"

swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/VideoDetail/InlineVideoLayout.swift" \
    "$HARNESS/src/InlineVideoLayoutRegression.swift" \
    -o "$BUILD_DIR/inline-video-layout"
"$BUILD_DIR/inline-video-layout"

swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/Player/PlayerSurfaceGeometry.swift" \
    "$HARNESS/src/PlayerSurfaceAspectRegression.swift" \
    -o "$BUILD_DIR/player-surface-aspect"
"$BUILD_DIR/player-surface-aspect"

swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/VideoDetail/InlineVideoCollapseLayout.swift" \
    "$HARNESS/src/InlineVideoCollapseRegression.swift" \
    -o "$BUILD_DIR/inline-video-collapse"
"$BUILD_DIR/inline-video-collapse"

swiftc -swift-version 6 -parse-as-library \
    "$APP/Core/Models/CardAnimationSettings.swift" \
    "$HARNESS/src/CardAnimationRegression.swift" \
    -o "$BUILD_DIR/card-animation"
"$BUILD_DIR/card-animation"

# Already-mounted mini windows must receive new-session handoffs without layout.
swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/Player/PlayerSurfaceOwnership.swift" \
    "$HARNESS/src/PlayerSurfaceOwnershipRegression.swift" \
    -o "$BUILD_DIR/player-surface-ownership"
"$BUILD_DIR/player-surface-ownership"

swiftc -swift-version 6 -parse-as-library \
    "$APP/Core/Models/LiveModels.swift" \
    "$APP/Features/Following/FollowedLiveDirectory.swift" \
    "$HARNESS/src/FollowedLiveDirectoryRegression.swift" \
    -o "$BUILD_DIR/followed-live-directory"
"$BUILD_DIR/followed-live-directory"

# 直播弹幕 WebSocket 的二进制包编解码（真实生产代码，无依赖桩）。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/Live/LivePacketCodec.swift" \
    "$HARNESS/src/LivePacketCodecRegression.swift" \
    -o "$BUILD_DIR/live-packet-codec"
"$BUILD_DIR/live-packet-codec"

# 直播关注直接编译生产状态模型；资料和写接口均为离线桩。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/Live/LiveRoomFollowModel.swift" \
    "$HARNESS/src/LiveRoomFollowRegression.swift" \
    -o "$BUILD_DIR/live-room-follow"
"$BUILD_DIR/live-room-follow"

swiftc -swift-version 6 -parse-as-library \
    "$APP/Core/Models/LiveModels.swift" \
    "$APP/Features/Live/LiveFeedModel.swift" \
    "$HARNESS/src/LiveFeedRegression.swift" \
    -o "$BUILD_DIR/live-feed"
"$BUILD_DIR/live-feed"

# 主题图标请求循环（真实控制器 + 桩端点）：成功提交后不得因上报滞后
# 无限重提交——那是 v1.0.3 引入的发热根因。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Core/UI/ThemeIconController.swift" \
    "$HARNESS/src/ThemeIconRegression.swift" \
    -o "$BUILD_DIR/theme-icon"
"$BUILD_DIR/theme-icon"

# 缩略播放器退出期间的快速展开、关闭和切换媒体，不启动 UI 或网络。
swiftc -swift-version 6 -parse-as-library \
    "$APP/Features/NowPlaying/MediaPresentationState.swift" \
    "$HARNESS/src/MiniPlayerInteractionRegression.swift" \
    -o "$BUILD_DIR/mini-player-interaction"
"$BUILD_DIR/mini-player-interaction"
