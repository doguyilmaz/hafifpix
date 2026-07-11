#!/bin/bash
# Packages dist/HafifPix.app into a distributable DMG with the classic
# "drag to Applications" layout. Run scripts/build-app.sh first (make dmg does).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/HafifPix.app"
VOL="HafifPix"

[[ -d "$APP" ]] || { echo "ERROR: $APP missing — run 'make app' first" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="dist/HafifPix-$VERSION.dmg"
STAGING=".build/dmg-staging"
TMP_DMG=".build/hafifpix-rw.dmg"

echo "==> Staging"
rm -rf "$STAGING" "$DMG" "$TMP_DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/HafifPix.app"
ln -s /Applications "$STAGING/Applications"
cp Resources/AppIcon.icns "$STAGING/.VolumeIcon.icns"

echo "==> Creating writable image"
hdiutil create -volname "$VOL" -srcfolder "$STAGING" -fs HFS+ -format UDRW -o "$TMP_DMG" -quiet

MOUNT_DIR=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}')
trap 'hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true' EXIT

SetFile -a C "$MOUNT_DIR" 2>/dev/null || true

echo "==> Arranging Finder window"
# Needs Automation permission (Terminal → Finder); layout is cosmetic, so
# a denial only costs the pretty window, not the DMG.
osascript <<EOF || echo "    (Finder layout skipped — grant Automation permission for the pretty window)"
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 780, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 110
        set text size of viewOptions to 13
        set position of item "HafifPix.app" of container window to {150, 170}
        set position of item "Applications" of container window to {430, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_DIR" -quiet
trap - EXIT

echo "==> Compressing"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$TMP_DMG"

if [[ -n "${SIGN_IDENTITY:-}" && "${SIGN_IDENTITY:-}" != "-" ]]; then
    echo "==> Signing DMG"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
