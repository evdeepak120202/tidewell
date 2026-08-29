#!/bin/bash
#
# Packages build/Tidewell.app into a distributable disk image.
#
#   ./Scripts/build.sh && ./Scripts/make-dmg.sh
#
# Produces build/Tidewell-<version>.dmg with a drag-to-Applications layout, the
# rendered backdrop behind it and a custom volume icon.
#
# The window layout step drives Finder through AppleScript, so the first run asks for
# Automation permission. If you decline, or run this over SSH, the image is still
# produced and still works — it just opens with Finder's default list view instead of
# the arranged icon view.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Tidewell"
VOL_NAME="Tidewell"
APP="build/$APP_NAME.app"

[ -d "$APP" ] || { echo "error: $APP not found — run ./Scripts/build.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/$APP_NAME-$VERSION.dmg"
STAGING="build/dmg-staging"
RW_DMG="build/.$APP_NAME-rw.dmg"

# Window geometry. The icon wells sit on the same baseline as the arrow drawn into
# the backdrop, so these numbers and Icon/GenerateIcon.swift must agree — see
# DMGBackground.baseline there.
WIN_X=360;  WIN_Y=140
WIN_W=600;  WIN_H=400
ICON_SIZE=112
APP_ICON_X=168; APP_ICON_Y=214
APPLICATIONS_X=432; APPLICATIONS_Y=214

echo "==> Staging"
rm -rf "$STAGING" "$RW_DMG" "$DMG"
mkdir -p "$STAGING/.background"

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Finder picks the right representation out of a multi-resolution TIFF.
tiffutil -cathidpicheck \
    build/icon/dmg-background.png \
    build/icon/dmg-background@2x.png \
    -out "$STAGING/.background/background.tiff" > /dev/null

# Auto-sizing is tight; leave room for the .DS_Store the layout step writes.
SIZE_KB=$(( $(du -sk "$STAGING" | cut -f1) + 20000 ))

echo "==> Creating read/write image"
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOL_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${SIZE_KB}k" \
    "$RW_DMG" > /dev/null

echo "==> Mounting"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | grep -E '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOL_NAME"

cleanup() {
    hdiutil detach "$DEVICE" -quiet 2>/dev/null || \
    hdiutil detach "$DEVICE" -force -quiet 2>/dev/null || true
}
trap cleanup EXIT

# Wait for Finder to see the volume before scripting it.
for _ in $(seq 1 30); do [ -d "$MOUNT" ] && break; sleep 0.2; done

echo "==> Arranging window"
if osascript > /dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {$APP_ICON_X, $APP_ICON_Y}
        set position of item "Applications" of container window to {$APPLICATIONS_X, $APPLICATIONS_Y}
        close
        open
        update without registering applications
        delay 1.5
        close
    end tell
end tell
APPLESCRIPT
then
    echo "    layout applied"
else
    echo "    note: Finder scripting unavailable — image will open in default view"
fi

echo "==> Applying custom volume icon"
# Two ordering constraints here, both learned the hard way:
#   1. The icon must be installed on the mounted volume, not staged into the source
#      folder — hdiutil's -srcfolder copy does not carry it through.
#   2. It must happen *after* the Finder layout step, which rewrites the volume
#      root's Finder info and clears the custom-icon bit if it ran first.
cp "build/icon/$APP_NAME.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a V "$MOUNT/.VolumeIcon.icns"   # invisible
SetFile -a C "$MOUNT"                    # volume uses a custom icon

if GetFileInfo "$MOUNT" | grep -q 'attributes:.*C'; then
    echo "    custom icon bit set"
else
    echo "    warning: custom icon bit did not take" >&2
fi

# Make the .DS_Store world-readable so the layout survives for other accounts.
chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync

echo "==> Compressing"
cleanup
trap - EXIT

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" > /dev/null
rm -f "$RW_DMG"
rm -rf "$STAGING"

# Sign the image itself so its contents cannot be swapped after the fact.
SELF_SIGNED="Tidewell Self-Signed"
if [ -z "${SIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$SELF_SIGNED"; then
    SIGN_IDENTITY="$SELF_SIGNED"
fi
codesign --force --sign "${SIGN_IDENTITY:--}" "$DMG"

echo "==> Done: $DMG"
ls -lh "$DMG" | awk '{print "    " $5, $9}'
hdiutil verify "$DMG" > /dev/null && echo "    checksum verified"
