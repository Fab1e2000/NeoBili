#!/bin/zsh
# Host-only regression/benchmark. Does not create a Simulator or access a phone.
set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-performance.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$ROOT/NeoBili"
source "$HARNESS/modules.sh"
harness_build_modules -O
harness_compile -O \
    "$APP/Core/UI/ImageDownsampling.swift" \
    "$HARNESS/src/ImagePerformanceRegression.swift" \
    -o "$BUILD_DIR/image-performance"
"$BUILD_DIR/image-performance"
harness_compile -O \
    "$HARNESS/src/ImagePipelineRegression.swift" \
    -o "$BUILD_DIR/image-pipeline"
"$BUILD_DIR/image-pipeline"
harness_compile -O \
    "$APP/Application/Player/PlaybackProgressStore.swift" \
    "$HARNESS/src/PlaybackPersistencePerformance.swift" \
    -o "$BUILD_DIR/persistence-performance"
"$BUILD_DIR/persistence-performance"
harness_compile -O \
    "$APP/Application/Player/VideoPreparationCache.swift" \
    "$HARNESS/src/HostServiceDefaults.swift" \
    "$HARNESS/src/VideoPreparationRegression.swift" \
    -o "$BUILD_DIR/video-preparation"
"$BUILD_DIR/video-preparation"

# Metadata classification commits a page once, off the main thread, while
# retaining restart/cancellation durability and the existing cache format.
harness_compile -O \
    "$APP/Application/Content/VideoFiltering.swift" \
    "$APP/Application/Settings/VideoDurationFilterSettings.swift" \
    "$APP/Application/Content/PortraitVideoStore.swift" \
    "$HARNESS/src/MetadataPersistenceRegression.swift" \
    -o "$BUILD_DIR/metadata-persistence"
"$BUILD_DIR/metadata-persistence"

harness_compile -O \
    "$HARNESS/src/DateFormattingPerformance.swift" \
    -o "$BUILD_DIR/date-formatting"
"$BUILD_DIR/date-formatting"
