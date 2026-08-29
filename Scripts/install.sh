#!/bin/bash
#
# Installs Tidewell.app into /Applications and launches it.
#
#   ./Scripts/install.sh
#
# Run the app from /Applications, not from build/. `Scripts/build.sh` deletes and
# recreates the bundle on every build, which pulls the executable out from under a
# running copy and leaves macOS unable to validate its identity — which shows up as
# folder access and the login item mysteriously resetting.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Tidewell"
SRC="build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

[ -d "$SRC" ] || { echo "error: $SRC not found — run ./Scripts/build.sh first" >&2; exit 1; }

echo "==> Quitting any running copy"
# Ask first so applicationWillTerminate runs and settings are flushed, then force
# it. A scripted quit reports success even when the app is wedged mid-terminate, so
# without the fallback kill the old process survives every reinstall.
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
for _ in 1 2 3 4 5; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.4; done
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "==> Verifying signature"
codesign --verify --strict "$DEST" && echo "    signature valid"
codesign -d -r- "$DEST" 2>&1 | tail -1 | sed 's/^/    /'

echo "==> Launching"
open "$DEST"

echo
echo "==> Installed."
