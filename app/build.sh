#!/bin/bash
# Builds Gootd.app from the SwiftPM product. Needs Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Gootd.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "· compiling"
swift build -c release

echo "· drawing icon"
ICONSET="build/Gootd.iconset"
rm -rf "$ICONSET" build/icons && mkdir -p "$ICONSET" build/icons
swiftc -O Tools/makeicon.swift -o build/makeicon
./build/makeicon build/icons
cp build/icons/icon_16.png   "$ICONSET/icon_16x16.png"
cp build/icons/icon_32.png   "$ICONSET/icon_16x16@2x.png"
cp build/icons/icon_32.png   "$ICONSET/icon_32x32.png"
cp build/icons/icon_64.png   "$ICONSET/icon_32x32@2x.png"
cp build/icons/icon_128.png  "$ICONSET/icon_128x128.png"
cp build/icons/icon_256.png  "$ICONSET/icon_128x128@2x.png"
cp build/icons/icon_256.png  "$ICONSET/icon_256x256.png"
cp build/icons/icon_512.png  "$ICONSET/icon_256x256@2x.png"
cp build/icons/icon_512.png  "$ICONSET/icon_512x512.png"
cp build/icons/icon_1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Gootd.icns"

echo "· assembling bundle"
cp .build/release/Gootd "$APP/Contents/MacOS/Gootd"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "· signing"
# A Developer ID signature, the hardened runtime and a secure timestamp are all
# three preconditions for notarisation - a submission missing any one of them is
# rejected outright. Without notarisation macOS shows the "Apple could not
# verify this app" dialog on first launch, whatever else the bundle does right.
SIGN_ID="${GOOTD_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)}"
# Downloaded and copied files carry xattrs that codesign refuses to seal over.
xattr -cr "$APP"
if [ -n "$SIGN_ID" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    echo "    $SIGN_ID"
else
    codesign --force --sign - --timestamp=none "$APP"
    echo "    ad hoc - no Developer ID Application certificate in the keychain."
    echo "    This build cannot be notarised, so it will warn on first launch."
fi

echo
echo "  built  $(pwd)/$APP"
