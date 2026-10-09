#!/bin/zsh
# Host-only behavior identity benchmark; isolated defaults and memory credentials.
# Usage: zsh offline-harness/behavior-performance.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap "rm -rf $BUILD_DIR" EXIT

APP="$ROOT/NeoBili"
source "$HARNESS/sources.sh"
cp "$HARNESS/src/BehaviorIdentityPerformance.swift" "$BUILD_DIR/"

swiftc -O -D NEOBILI_REGRESSION -parse-as-library -o "$BUILD_DIR/behavior-performance" "$BUILD_DIR"/*.swift
"$BUILD_DIR/behavior-performance"
