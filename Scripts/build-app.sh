#!/bin/zsh
# Builds a release HyperVideo Converter.app into ./build (no Xcode required).
set -euo pipefail
cd "${0:A:h}/.."

APP="build/HyperVideo Converter.app"
CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/HyperVideoConverter"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HyperVideoConverter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns || Resources/AppIcon.png -nt build/AppIcon.icns ]]; then
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  swift Scripts/make-icon.swift build/icon-1024.png $( [[ -f Resources/AppIcon.png ]] && echo Resources/AppIcon.png )
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
