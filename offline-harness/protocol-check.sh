#!/bin/zsh
# Local protocol probe using current production encoders. Network is opt-in.
# Usage: zsh offline-harness/protocol-check.sh

set -euo pipefail
HARNESS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HARNESS")"
BUILD_DIR="$(mktemp -d /tmp/neobili-harness.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT

APP="$ROOT/NeoBili"
source "$HARNESS/modules.sh"
harness_build_modules -O
harness_compile -O "$HARNESS/src/ProtocolCheck.swift" -o "$BUILD_DIR/protocol-check"
"$BUILD_DIR/protocol-check" "$@"
