#!/bin/zsh
# Host-only behavior identity benchmark; isolated defaults and memory credentials.
# Usage: zsh offline-harness/behavior-performance.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

APP="$ROOT/NeoBili"
source "$HARNESS/modules.sh"
source "$HARNESS/sources.sh"
harness_build_modules -O
harness_compile -O "${harness_app_sources[@]}" "$HARNESS/src/BehaviorIdentityPerformance.swift" -o "$BUILD_DIR/behavior-performance"
"$BUILD_DIR/behavior-performance"
