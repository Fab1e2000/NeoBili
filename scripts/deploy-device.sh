#!/bin/zsh
# 用 signing/ 里的证书构建 NeoBili，并安装、启动到真机。
# 用法：scripts/deploy-device.sh [Release|Debug] [--no-launch]
# signing/ 不入库，需要自己放入：dev.p12（开发证书）、dev.mobileprovision（描述文件）、
# p12-password（证书密码，一行文本）。
# 设备：默认使用唯一一台已配对的 iPhone / iPad；有多台时用 NEOBILI_DEVICE=<UDID 或设备名> 指定。
set -euo pipefail

ROOT=${0:A:h:h}
SIGNING=$ROOT/signing
CONFIG=${1:-Release}
LAUNCH=1
[[ "${2:-}" == "--no-launch" || "${1:-}" == "--no-launch" ]] && LAUNCH=0
[[ "$CONFIG" == "--no-launch" ]] && CONFIG=Release
DEVICE=${NEOBILI_DEVICE:-}
if [[ -z "$DEVICE" ]]; then
  DEVICES_JSON=$(mktemp -t neobili-devices)
  xcrun devicectl list devices --json-output "$DEVICES_JSON" > /dev/null
  DEVICE=$(python3 - "$DEVICES_JSON" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
found = [d["hardwareProperties"]["udid"] for d in devices
         if d.get("hardwareProperties", {}).get("platform") == "iOS"
         and d["hardwareProperties"].get("reality") == "physical"
         and d.get("connectionProperties", {}).get("pairingState") == "paired"]
print(found[0] if len(found) == 1 else "")
PY
)
  rm -f "$DEVICES_JSON"
  if [[ -z "$DEVICE" ]]; then
    echo "找不到唯一一台已配对的 iPhone / iPad，请用 NEOBILI_DEVICE=<UDID 或设备名> 指定。" >&2
    exit 1
  fi
fi

P12=$SIGNING/dev.p12
PROFILE=$SIGNING/dev.mobileprovision
P12_PASSWORD=$(<"$SIGNING/p12-password")
KEYCHAIN=$SIGNING/neobili-signing.keychain-db
KEYCHAIN_PASSWORD=neobili

# 从描述文件里读出 bundle id、团队和证书指纹。
PLIST=$(mktemp -t neobili-profile)
security cms -D -i "$PROFILE" > "$PLIST"
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$PLIST")
TEAM=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PLIST")
BUNDLE_ID=${APP_ID#$TEAM.}
IDENTITY=$(/usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:0" "$PLIST" | openssl x509 -inform der -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')

# 证书放在单独的钥匙串里，不动登录钥匙串。
if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  # 原 p12 的加密格式 security 读不了，先用 openssl 转成它认得的旧格式。
  PEM=$(mktemp -t neobili-p12); LEGACY_P12=$PEM.p12
  openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nodes -legacy -out "$PEM" 2>/dev/null \
    || openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nodes -out "$PEM"
  openssl pkcs12 -export -in "$PEM" -out "$LEGACY_P12" -passout "pass:$P12_PASSWORD" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
  security import "$LEGACY_P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
  rm -f "$PEM" "$LEGACY_P12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

# 不签名构建，再用本地证书重签。
xcodebuild -project "$ROOT/NeoBili.xcodeproj" -scheme NeoBili -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' -derivedDataPath "$ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build -quiet

APP=$ROOT/DerivedData/Build/Products/$CONFIG-iphoneos/NeoBili.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"

ENTITLEMENTS=$(mktemp -t neobili-entitlements)
cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$APP_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>keychain-access-groups</key><array><string>$APP_ID</string></array>
  <key>get-task-allow</key><true/>
</dict></plist>
PLIST

SIGN=(codesign --force --timestamp=none --keychain "$KEYCHAIN" --sign "$IDENTITY")
if [[ -d "$APP/Frameworks" ]]; then
  for item in "$APP"/Frameworks/*(N); do "${SIGN[@]}" "$item"; done
fi
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$PLIST" "$ENTITLEMENTS"

xcrun devicectl device install app --device "$DEVICE" "$APP"
if (( LAUNCH )); then
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE_ID"
fi
echo "已推送 $BUNDLE_ID（$CONFIG）"
