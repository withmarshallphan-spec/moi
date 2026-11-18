#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the MOI character renderer (the same code the app draws with).
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
WORK_DIR="$ROOT_DIR/.build/icon"
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR/AppIcon.iconset"
"$ROOT_DIR/Scripts/build-app.sh" >/dev/null
MOI_EXPORT_CHARACTER="$WORK_DIR" "$ROOT_DIR/Build/Moi Development.app/Contents/MacOS/Moi"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK_DIR/moi-icon-1024.png" --out "$WORK_DIR/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK_DIR/moi-icon-1024.png" --out "$WORK_DIR/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK_DIR/AppIcon.iconset" -o "$ROOT_DIR/Resources/AppIcon.icns"
echo "Wrote $ROOT_DIR/Resources/AppIcon.icns"
