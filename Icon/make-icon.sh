#!/bin/bash
# Regenerates Tidewell.icns, the 1024 px master and the DMG backdrop from the
# SwiftUI source in Sources/TidewellCore/Design/TidewellMark.swift.
#
#   ./Icon/make-icon.sh
#
# Output lands in build/icon/. Scripts/build.sh runs this when the icns is missing,
# so you only need it by hand after changing the mark itself.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/icon"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Compiling icon generator"
# TidewellMark.swift is self-contained SwiftUI so it compiles here without pulling
# in the rest of TidewellCore.
swiftc -O -parse-as-library -swift-version 6 \
    Icon/GenerateIcon.swift \
    Sources/TidewellCore/Design/TidewellMark.swift \
    -o "$OUT/generate-icon"

echo "==> Rendering representations"
"$OUT/generate-icon" "$OUT"

echo "==> Packing Tidewell.icns"
iconutil --convert icns "$OUT/Tidewell.iconset" --output "$OUT/Tidewell.icns"

rm -f "$OUT/generate-icon"
echo "==> Done: $OUT/Tidewell.icns"
