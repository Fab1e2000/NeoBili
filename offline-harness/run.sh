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
   "$APP/Core/Networking/BiliPassport.swift" \
   "$APP/Core/Networking/WBISigner.swift" \
   "$APP/Core/Networking/DeviceIdentity.swift" \
   "$APP/Core/Networking/KeychainStore.swift" \
   "$APP/Core/Networking/AppSigner.swift" \
   "$APP/Core/Networking/URL+Bili.swift" \
   "$APP/Core/UI/EnvironmentAction.swift" \
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
