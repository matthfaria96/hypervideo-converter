#!/bin/zsh
# Builds an installable HyperVideo Converter.app and a .dmg into ./dist (no Xcode required).
#
#   Scripts/build-app.sh [release|debug]
#
# Environment:
#   SIGN_IDENTITY   codesign identity ("Developer ID Application: …"). Enables the
#                   hardened runtime. Default: ad-hoc signature (-).
#   NOTARY_PROFILE  notarytool keychain profile. Submits, waits and staples.
#   ARCHS           architectures to build (default "arm64 x86_64", a universal app).
#                   Requires SIGN_IDENTITY and Xcode's notarytool/stapler.
set -euo pipefail
cd "${0:A:h}/.."

CONFIG="${1:-release}"
NAME="HyperVideo Converter"
EXE="HyperVideoConverter"
DIST="dist"
APP="$DIST/$NAME.app"
WORK="build"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

fail() { print -u2 "error: $*"; exit 1; }

# Check notarization prerequisites before spending time on the build.
if [[ -n "$NOTARY_PROFILE" ]]; then
  [[ -n "$SIGN_IDENTITY" ]] || fail "NOTARY_PROFILE needs SIGN_IDENTITY (a Developer ID Application identity)."
  xcrun --find notarytool >/dev/null 2>&1 || fail "notarytool not found. Notarization needs Xcode (not only the Command Line Tools)."
  xcrun --find stapler >/dev/null 2>&1 || fail "stapler not found. Notarization needs Xcode (not only the Command Line Tools)."
fi

# Version: latest tag (v1.2.3 -> 1.2.3), build number: commit count.
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')" || true
[[ "$VERSION" =~ '^[0-9]+(\.[0-9]+){0,2}$' ]] || VERSION="0.1.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
MIN_OS="$(sed -nE 's/.*\.macOS\(\.v([0-9]+)\).*/\1.0/p' Package.swift | head -1)"
[[ -n "$MIN_OS" ]] || fail "could not read the macOS platform from Package.swift"

# Universal (Apple silicon and Intel) by default; ARCHS="arm64" builds one architecture.
ARCH_FLAGS=()
for arch in ${=ARCHS:-arm64 x86_64}; do ARCH_FLAGS+=(--arch "$arch"); done
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WORK"
cp "$BIN_DIR/$EXE" "$APP/Contents/MacOS/$EXE"
# SwiftPM stamps the deployment target as the SDK version (sdk 15.0), and newer macOS
# then runs the app in its old look, without Liquid Glass. Stamp the real SDK.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
MIN_FOR_STAMP="$(sed -nE 's/.*\.macOS\(\.v([0-9]+)\).*/\1.0/p' Package.swift | head -1)"
if [[ -n "$SDK_VERSION" && -n "$MIN_FOR_STAMP" ]]; then
  vtool -set-build-version macos "$MIN_FOR_STAMP" "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/$EXE" "$APP/Contents/MacOS/$EXE"
fi

PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
$PB -c "Set :CFBundleVersion $BUILD" "$PLIST"
$PB -c "Set :LSMinimumSystemVersion $MIN_OS" "$PLIST"

# The app's translations: SwiftPM puts them in a resource bundle; copy its .lproj
# folders into the app itself, where Bundle.main (and SwiftUI's Text) look them up.
for lproj in "$BIN_DIR"/HyperVideoConverter_HyperVideoConverter.bundle/**/*.lproj(N/); do
  cp -R "$lproj" "$APP/Contents/Resources/"
done
ls "$APP/Contents/Resources"/pt-BR.lproj/Localizable.strings >/dev/null 2>&1 \
  || ls "$APP/Contents/Resources"/pt-br.lproj/Localizable.strings >/dev/null 2>&1 \
  || fail "the Portuguese translations were not copied into the app"

# The compiled asset catalog (the app's accent color): NSAccentColorName looks it up
# in the main bundle, so it moves next to the executable's resources too.
CAR=("$BIN_DIR"/HyperVideoConverter_HyperVideoConverter.bundle/**/Assets.car(N))
CAR="${CAR[1]:-}"
[[ -n "$CAR" && -f "$CAR" ]] || fail "Assets.car was not built from Sources/HyperVideoConverter/Resources/Colors.xcassets"
cp "$CAR" "$APP/Contents/Resources/Assets.car"

if [[ ! -f "$WORK/AppIcon.icns" || Resources/AppIcon.png -nt "$WORK/AppIcon.icns" || Scripts/make-icon.swift -nt "$WORK/AppIcon.icns" ]]; then
  ICONSET="$WORK/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  swift Scripts/make-icon.swift "$WORK/icon-1024.png" $( [[ -f Resources/AppIcon.png ]] && echo Resources/AppIcon.png )
  for s in 16 32 128 256 512; do
    sips -z $s $s "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"
fi
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# AI Upscale backend (Upscayl, AGPL-3.0): a separate executable plus its models and licence.
[[ -x Vendor/Upscayl/upscayl-bin ]] || zsh Scripts/fetch-upscayl.sh
cp Vendor/Upscayl/upscayl-bin "$APP/Contents/MacOS/upscayl-bin"
mkdir -p "$APP/Contents/Resources/Upscayl" "$APP/Contents/Resources/Licenses"
cp -R Vendor/Upscayl/models "$APP/Contents/Resources/Upscayl/models"
cp Vendor/Upscayl/LICENSE-AGPL-3.0.txt "$APP/Contents/Resources/Licenses/upscayl-LICENSE-AGPL-3.0.txt"
cp Resources/THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/Licenses/THIRD-PARTY-NOTICES.txt"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/upscayl-bin"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict "$APP"

if [[ -n "$NOTARY_PROFILE" ]]; then
  ZIP="$WORK/$EXE-notarize.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi

DMG="$DIST/$EXE-$VERSION.dmg"
STAGE="$WORK/dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
[[ -n "$SIGN_IDENTITY" ]] && codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built $APP ($VERSION build $BUILD) and $DMG"
