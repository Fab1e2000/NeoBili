#!/bin/zsh
# 在 macOS 宿主机上离线运行业务逻辑测试（不需要 Simulator、不需要真机）。
#
# 按真实模块名编译生产源码；sources.sh 列出组合测试共用的 App 层源码。
# src/ 保存场景入口和必要的组装依赖。
#
# 用法：./run.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

python3 "$ROOT/scripts/check-architecture.py"
python3 "$ROOT/scripts/check-doc-links.py"

APP="$ROOT/NeoBili"
source "$HARNESS/modules.sh"
source "$HARNESS/sources.sh"
harness_build_modules

harness_compile "${harness_app_sources[@]}" "$HARNESS/src/Tests.swift" -o "$BUILD_DIR/harness"
"$BUILD_DIR/harness"

# 单独验证 SwiftUI Binding 捕获的所有权，不启动任何界面或设备。
harness_compile \
    "$APP/Core/UI/EnvironmentAction.swift" \
    "$HARNESS/src/EnvironmentActionLifetime.swift" \
    -o "$BUILD_DIR/action-lifetime"
"$BUILD_DIR/action-lifetime"

# 验证真实入场状态逻辑，不创建窗口或启动设备。
harness_compile \
    "$APP/Application/Content/VideoEntranceClock.swift" \
    "$HARNESS/src/VideoEntranceRegression.swift" \
    -o "$BUILD_DIR/video-entrance"
"$BUILD_DIR/video-entrance"

# 续播存储和 mpv 事件顺序、内联画幅与固定渲染表面的真实逻辑。
harness_compile \
    "$APP/Application/Player/PlaybackProgressStore.swift" \
    "$HARNESS/src/PlaybackResumeRegression.swift" \
    -o "$BUILD_DIR/playback-resume"
"$BUILD_DIR/playback-resume"

# 只有真实播放进度才能上传历史；seek、预载、缓冲、EOF 和慢网队列回归。
harness_compile \
    "$APP/Application/Player/PlaybackWatchProgress.swift" \
    "$HARNESS/src/PlaybackWatchProgressRegression.swift" \
    -o "$BUILD_DIR/playback-watch-progress"
"$BUILD_DIR/playback-watch-progress"

harness_compile \
    "$APP/Application/Settings/CardAnimationSettings+Preferences.swift" \
    "$HARNESS/src/CardAnimationRegression.swift" \
    -o "$BUILD_DIR/card-animation"
"$BUILD_DIR/card-animation"

# Already-mounted mini windows must receive new-session handoffs without layout.
harness_compile \
    "$APP/Platform/Playback/PlayerSurfaceOwnership.swift" \
    "$HARNESS/src/PlayerSurfaceOwnershipRegression.swift" \
    -o "$BUILD_DIR/player-surface-ownership"
"$BUILD_DIR/player-surface-ownership"

harness_compile \
    "$APP/Application/Following/FollowedLiveDirectory.swift" \
    "$HARNESS/src/HostServiceDefaults.swift" \
    "$HARNESS/src/FollowedLiveDirectoryRegression.swift" \
    -o "$BUILD_DIR/followed-live-directory"
"$BUILD_DIR/followed-live-directory"

# 直播弹幕 WebSocket 的二进制包编解码（真实生产代码，无依赖桩）。
harness_compile \
    "$HARNESS/src/LivePacketCodecRegression.swift" \
    -o "$BUILD_DIR/live-packet-codec"
"$BUILD_DIR/live-packet-codec"

# 直播关注直接编译生产状态模型；资料和写接口均为离线桩。
harness_compile \
    "$APP/Application/Live/LiveRoomFollowModel.swift" \
    "$APP/Core/Extensions/Error+Cancellation.swift" \
    "$HARNESS/src/HostServiceDefaults.swift" \
    "$HARNESS/src/LiveRoomFollowRegression.swift" \
    -o "$BUILD_DIR/live-room-follow"
"$BUILD_DIR/live-room-follow"

harness_compile \
    "$APP/Application/Live/LiveFeedModel.swift" \
    "$APP/Application/Content/LoadFailureDescription.swift" \
    "$APP/Core/Extensions/Error+Cancellation.swift" \
    "$HARNESS/src/HostServiceDefaults.swift" \
    "$HARNESS/src/LiveFeedRegression.swift" \
    -o "$BUILD_DIR/live-feed"
"$BUILD_DIR/live-feed"

# 主题图标请求循环（真实控制器 + 桩端点）：成功提交后不得因上报滞后
# 无限重提交。
harness_compile \
    "$APP/Core/UI/ThemeIconController.swift" \
    "$HARNESS/src/ThemeIconRegression.swift" \
    -o "$BUILD_DIR/theme-icon"
"$BUILD_DIR/theme-icon"

# 播放器控件位置设置对象：沿用旧键、只写入改动项、恢复默认。
harness_compile \
    "$APP/Application/Settings/PlayerChromePreferences.swift" \
    "$HARNESS/src/PlayerChromePreferencesRegression.swift" \
    -o "$BUILD_DIR/player-chrome-preferences"
"$BUILD_DIR/player-chrome-preferences"

# 缩略播放器退出期间的快速展开、关闭和切换媒体，不启动 UI 或网络。
harness_compile \
    "$APP/Application/NowPlaying/MediaPresentationState.swift" \
    "$HARNESS/src/MiniPlayerInteractionRegression.swift" \
    -o "$BUILD_DIR/mini-player-interaction"
"$BUILD_DIR/mini-player-interaction"

# HTTP 身份隔离、WBI 并发和首页过期加载：同一批生产源码，独立入口。
harness_compile "${harness_app_sources[@]}" \
    "$HARNESS/src/NetworkLoadingRegression.swift" \
    -o "$BUILD_DIR/network-loading"
"$BUILD_DIR/network-loading"
