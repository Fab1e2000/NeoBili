#!/bin/bash
# Simulator-only entry point. See docs/DEVELOPMENT.md.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ACTION=${1:-help}
if [[ "$ACTION" == help || "$ACTION" == --help ]]; then
  echo 'Usage: bash scripts/simulator.sh list|run|test|network [TestClass[/testMethod] ...]'
  echo 'Select with NEOBILI_SIMULATOR_ID or NEOBILI_SIMULATOR_NAME (default: iPhone 18 Pro).'
  echo 'Optional: NEOBILI_SIMULATOR_RUNTIME (e.g. iOS-27-0), NEOBILI_DERIVED_DATA.'
  exit 0
fi
shift
case "$ACTION" in list) exec xcrun simctl list devices available;; run|test|network) ;; *) echo 'Unknown action' >&2; exit 2;; esac
if [[ "$ACTION" != test && $# -ne 0 ]]; then echo 'Test selectors are only supported by test.' >&2; exit 2; fi
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json, os, sys
requested = os.environ.get("NEOBILI_SIMULATOR_ID")
name = os.environ.get("NEOBILI_SIMULATOR_NAME", "iPhone 18 Pro")
runtime = os.environ.get("NEOBILI_SIMULATOR_RUNTIME", "")
found = [(r, d) for r, ds in json.load(sys.stdin)["devices"].items()
         if ".iOS-" in r and (not runtime or r.endswith(runtime)) for d in ds
         if d.get("isAvailable") and (d["udid"] == requested if requested else d["name"] == name)]
if len(found) != 1:
    sys.exit("Expected exactly one available iOS simulator; use list and set NEOBILI_SIMULATOR_ID or a name + runtime.")
print(found[0][1]["udid"])
')
# Serialize foreground work across checkouts using the same simulator. Never steal a lock.
LOCK="${TMPDIR:-/tmp}/neobili-simulator-$DEVICE.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Simulator is reserved: $LOCK. Check its owner PID before removing a stale lock." >&2
  exit 1
fi
echo "$$" > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
RESULT="$ROOT/DerivedData/Validation/$STAMP-$ACTION"
mkdir -p "$RESULT"
CACHE=${NEOBILI_DERIVED_DATA:-$ROOT/DerivedData/Simulator}
SCHEME=NeoBili
[[ "$ACTION" == network ]] && SCHEME=NeoBili-Network
ARGS=(-project "$ROOT/NeoBili.xcodeproj" -scheme "$SCHEME" -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$CACHE" CODE_SIGNING_ALLOWED=NO)
printf 'Simulator: %s\nResults: %s\n' "$DEVICE" "$RESULT"
xcodebuild -version > "$RESULT/environment.txt"
xcrun simctl list devices available >> "$RESULT/environment.txt"
if [[ "$ACTION" == run ]]; then
  xcodebuild "${ARGS[@]}" -configuration Debug build > "$RESULT/build.log" 2>&1 || { tail -80 "$RESULT/build.log"; exit 1; }
  STATE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["state"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["udid"]==sys.argv[1]))' "$DEVICE")
  [[ "$STATE" == Booted ]] || xcrun simctl boot "$DEVICE"
  xcrun simctl bootstatus "$DEVICE" -b
  APP="$CACHE/Build/Products/Debug-iphonesimulator/NeoBili.app"
  BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
  xcrun simctl install "$DEVICE" "$APP"
  xcrun simctl launch "$DEVICE" "$BUNDLE"
else
  for SELECTOR in "$@"; do
    [[ "$SELECTOR" != -* ]] || { echo 'Invalid test selector' >&2; exit 2; }
    ARGS+=("-only-testing:NeoBiliTests/$SELECTOR")
  done
  if xcodebuild "${ARGS[@]}" -parallel-testing-enabled NO -resultBundlePath "$RESULT/tests.xcresult" test > "$RESULT/test.log" 2>&1; then
    STATUS=0
  else
    STATUS=$?
  fi
  tail -30 "$RESULT/test.log"
  if [[ -d "$RESULT/tests.xcresult" ]]; then
    xcrun xcresulttool get test-results summary --path "$RESULT/tests.xcresult" --format json > "$RESULT/summary.json"
    python3 - "$RESULT/summary.json" <<'PYTHON'
import json, sys
with open(sys.argv[1]) as source:
    summary = json.load(source)
print("Tests:", summary.get("passedTests", 0), "passed,", summary.get("failedTests", 0),
      "failed,", summary.get("skippedTests", 0), "skipped")
if summary.get("passedTests", 0) == 0 or summary.get("failedTests", 0) > 0:
    raise SystemExit("No passing tests or test failures; inspect the result bundle.")
PYTHON
  elif [[ "$STATUS" == 0 ]]; then
    echo 'No result bundle was generated.' >&2
    exit 1
  fi
  exit "$STATUS"
fi
