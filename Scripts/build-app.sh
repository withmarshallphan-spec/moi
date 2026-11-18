#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
# MOI_FLAVOR: development (default; separate data, dev switches on), release (Moi.app), or
# firstrun (a brand-new identity with empty data, to try the app as if just downloaded).
FLAVOR="${MOI_FLAVOR:-development}"
case "$FLAVOR" in
  release)  NAME="Moi";             BUNDLE_ID="local.marshall.moi" ;;
  firstrun) NAME="Moi First Run";   BUNDLE_ID="local.marshall.moi.firstrun" ;;
  *)        NAME="Moi Development"; BUNDLE_ID="local.moi.development" ;;
esac
APP_DIR="$ROOT_DIR/Build/$NAME.app"
SDK_PATH="${MOI_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
CONFIG="${MOI_BUILD_CONFIGURATION:-debug}"
SDKROOT="$SDK_PATH" swift build --package-path "$ROOT_DIR" -c "$CONFIG"
BIN_DIR=$(SDKROOT="$SDK_PATH" swift build --package-path "$ROOT_DIR" -c "$CONFIG" --show-bin-path)
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Moi" "$APP_DIR/Contents/MacOS/Moi"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
python3 - "$APP_DIR/Contents/Info.plist" "$BUNDLE_ID" "$NAME" "$FLAVOR" <<'PY'
import sys,plistlib
from pathlib import Path
p=Path(sys.argv[1]);d=plistlib.loads(p.read_bytes())
d.update(CFBundleIdentifier=sys.argv[2],CFBundleName=sys.argv[3],CFBundleDisplayName=sys.argv[3])
if sys.argv[4]=="development": d["CFBundleURLTypes"]=[{"CFBundleURLName":"moi development navigation","CFBundleURLSchemes":["moi-development"],"CFBundleTypeRole":"Viewer"}]
p.write_bytes(plistlib.dumps(d))
PY
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
for sound in "$ROOT_DIR"/Sources/MoiApp/Resources/Sounds/*.wav; do cp "$sound" "$APP_DIR/Contents/Resources/"; done
if [[ -d "$BIN_DIR/Moi_MoiApp.bundle" ]]; then
    ditto "$BIN_DIR/Moi_MoiApp.bundle" "$APP_DIR/Contents/Resources/Moi_MoiApp.bundle"
fi
codesign --force --deep --sign - --entitlements "$ROOT_DIR/Resources/Moi.entitlements" "$APP_DIR"
echo "Built $APP_DIR"
