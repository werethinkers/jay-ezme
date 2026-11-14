#!/bin/bash
# Builds KeyDo (the app bundle file is still named EzMe.app so installed copies update in place) and a distributable zip. Runs on macOS with Xcode command line tools.
#   BUILD_NUMBER   CFBundleVersion (default: 169)
#   OUT_DIR        output folder (default: app/build)
#   SWIFT_OPT      optimiser flag (default -O; pull request builds pass -Onone, which compiles much faster)
#   SIGN_IDENTITY  codesign identity (name or SHA-1). Empty = ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${BUILD_NUMBER:-169}"
OUT="${OUT_DIR:-build}"
APP="$OUT/EzMe.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling KeyDo $VERSION ($BUILD)..."
xcrun swiftc "${SWIFT_OPT:--O}" -wmo -num-threads "$(sysctl -n hw.ncpu)" -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Sources/EzMe/*.swift \
  -o "$APP/Contents/MacOS/EzMe"

cp Sources/EzMe/Resources/*.png Sources/EzMe/Resources/AppIcon.icns "$APP/Contents/Resources/"
# The installed file stays EzMe.app so existing installs update in place; Finder and the menu bar show KeyDo.
mkdir -p "$APP/Contents/Resources/en.lproj"
printf '"CFBundleDisplayName" = "KeyDo";\n"CFBundleName" = "KeyDo";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "Signing with $SIGN_IDENTITY"
  codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
else
  echo "Signing ad-hoc (set SIGN_IDENTITY for a stable identity)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

ZIP="$OUT/EzMe-$VERSION-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
