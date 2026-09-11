#!/bin/zsh
# Host-only regression/benchmark. Does not create a Simulator or access a phone.
set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-performance.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Core/UI/ImageDownsampling.swift" \
    "$HARNESS/src/ImagePerformanceRegression.swift" \
    -o "$BUILD_DIR/image-performance"
"$BUILD_DIR/image-performance"
swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Features/Player/PlaybackProgressStore.swift" \
    "$HARNESS/src/PlaybackPersistencePerformance.swift" \
    -o "$BUILD_DIR/persistence-performance"
"$BUILD_DIR/persistence-performance"
swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Features/Player/VideoPreparationCache.swift" \
    "$HARNESS/src/VideoPreparationRegression.swift" \
    -o "$BUILD_DIR/video-preparation"
"$BUILD_DIR/video-preparation"
