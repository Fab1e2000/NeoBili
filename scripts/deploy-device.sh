#!/bin/bash
# Usage: scripts/deploy-device.sh [Debug|Release] [--no-launch]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG=${1:-Debug}
LAUNCH=1
if [[ "$CONFIG" == --no-launch ]]; then CONFIG=Debug; LAUNCH=0; fi
[[ "${2:-}" == --no-launch ]] && LAUNCH=0
case "$CONFIG" in Debug|Release) ;; *) echo 'Expected Debug or Release' >&2; exit 2;; esac
DEVICE=${NEOBILI_DEVICE:-}
if [[ -z "$DEVICE" ]]; then
  DEVICES_JSON=$(mktemp -t neobili-devices)
  trap 'rm -f "$DEVICES_JSON"' EXIT
  xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null
  DEVICE=$(python3 - "$DEVICES_JSON" <<'DEVICE_PY'
import json, sys
found = []
for device in json.load(open(sys.argv[1]))['result']['devices']:
    properties = device.get('properties', {})
    hardware = properties.get('hardware', device.get('hardwareProperties', {}))
    connection = properties.get('connection', device.get('connectionProperties', {}))
    if (hardware.get('platform') == 'iOS' and hardware.get('reality') == 'physical'
            and connection.get('pairingState') == 'paired'
            and connection.get('state') != 'unavailable'):
        found.append(hardware['udid'])
print(found[0] if len(found) == 1 else '')
DEVICE_PY
)
fi
if [[ -z "$DEVICE" ]]; then
  echo '请连接并解锁唯一一台已配对的 iPhone，或设置 NEOBILI_DEVICE。' >&2
  exit 1
fi
DERIVED_DATA=${NEOBILI_DERIVED_DATA:-$ROOT/DerivedData}
xcodebuild -project "$ROOT/NeoBili.xcodeproj" -scheme NeoBili -configuration "$CONFIG" \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED_DATA" -allowProvisioningUpdates build -quiet
APP="$DERIVED_DATA/Build/Products/$CONFIG-iphoneos/NeoBili.app"
codesign --verify --deep --strict "$APP"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
xcrun devicectl device install app --device "$DEVICE" "$APP"
if (( LAUNCH )); then
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
fi
