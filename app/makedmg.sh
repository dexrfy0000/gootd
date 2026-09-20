#!/bin/bash
# Builds Gootd.dmg: the app, the folder it belongs in, and a line between them.
#
# The layout is written by scripting Finder on a read/write image and then
# flattening it to a compressed read-only one, which is the only way the icon
# positions and the backdrop survive into the file people download.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Gootd.app"
[ -d "$APP" ] || { echo "no $APP - run ./build.sh first" >&2; exit 1; }

VOL="Gootd"
DMG="build/Gootd.dmg"
STAGE="build/dmg-stage"
RW="build/Gootd-rw.dmg"

rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Gootd.app"
ln -s /Applications "$STAGE/Applications"
# Redrawn if missing, so a wiped build/ does not silently cost the backdrop.
if [ ! -f build/dmgbg.tiff ]; then
    echo "· drawing backdrop"
    swiftc -O Tools/makedmgbg.swift -o build/makedmgbg
    ./build/makedmgbg build/dmgbg.tiff
fi
cp build/dmgbg.tiff "$STAGE/.background/backdrop.tiff"
# The volume wears the app's own icon rather than the generic white disk.
cp "$APP/Contents/Resources/Gootd.icns" "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true

echo "· creating image"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
    -format UDRW -ov "$RW" >/dev/null

echo "· laying it out"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | \
        grep -E '/Volumes/' | sed 's/.*\(\/Volumes\/.*\)/\1/')
osascript <<APPLESCRIPT || echo "  (Finder would not script this - the image is still valid, just unstyled)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 820, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 12
    set background picture of opts to file ".background:backdrop.tiff"
    set position of item "Gootd.app" of container window to {160, 180}
    set position of item "Applications" of container window to {460, 180}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" >/dev/null

echo "· compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$RW" "$STAGE"

# The image is signed too, not just the app inside it. Gatekeeper checks the
# container the user actually double-clicks, and notarytool will not accept an
# unsigned one.
SIGN_ID="${GOOTD_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)}"
if [ -n "$SIGN_ID" ]; then
    echo "· signing image"
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
fi

echo
echo "  built  $(pwd)/$DMG  ($(du -h "$DMG" | cut -f1))"
