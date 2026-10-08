#!/bin/zsh
# Local protocol probe using current production encoders. Network is opt-in.
# Usage: zsh offline-harness/protocol-check.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap "rm -rf $BUILD_DIR" EXIT

APP="$ROOT/NeoBili"
source "$HARNESS/sources.sh"
cp "$HARNESS/src/ProtocolCheck.swift" "$BUILD_DIR/"

swiftc -O -D NEOBILI_REGRESSION -parse-as-library -o "$BUILD_DIR/protocol-check" "$BUILD_DIR"/*.swift
"$BUILD_DIR/protocol-check" "$@"
