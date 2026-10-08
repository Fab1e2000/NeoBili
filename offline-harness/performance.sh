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
    "$ROOT/NeoBili/Core/UI/ImageRequestPool.swift" \
    "$ROOT/NeoBili/Core/UI/ImageMemoryCache.swift" \
    "$HARNESS/src/ImagePipelineRegression.swift" \
    -o "$BUILD_DIR/image-pipeline"
"$BUILD_DIR/image-pipeline"
swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Application/Player/PlaybackProgressStore.swift" \
    "$HARNESS/src/PlaybackPersistencePerformance.swift" \
    -o "$BUILD_DIR/persistence-performance"
"$BUILD_DIR/persistence-performance"
swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Application/Player/VideoPreparationCache.swift" \
    "$HARNESS/src/VideoPreparationRegression.swift" \
    -o "$BUILD_DIR/video-preparation"
"$BUILD_DIR/video-preparation"

# Metadata classification commits a page once, off the main thread, while
# retaining restart/cancellation durability and the existing cache format.
swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Domain/Models/VideoDimension.swift" \
    "$ROOT/NeoBili/Application/Content/VideoFiltering.swift" \
    "$ROOT/NeoBili/Domain/Models/VideoDurationFilterSettings.swift" \
    "$ROOT/NeoBili/Application/Content/PortraitVideoStore.swift" \
    "$HARNESS/src/MetadataPersistenceRegression.swift" \
    -o "$BUILD_DIR/metadata-persistence"
"$BUILD_DIR/metadata-persistence"

swiftc -swift-version 6 -O -parse-as-library \
    "$ROOT/NeoBili/Core/Extensions/BiliDateFormatting.swift" \
    "$HARNESS/src/DateFormattingPerformance.swift" \
    -o "$BUILD_DIR/date-formatting"
"$BUILD_DIR/date-formatting"
