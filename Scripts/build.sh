#!/bin/bash
#
# Builds Tidewell.app.
#
#   ./Scripts/build.sh              Release build
#   ./Scripts/build.sh --debug      Debug build
#   SIGN_IDENTITY="Developer ID Application: …" ./Scripts/build.sh
#
# SwiftPM produces a bare executable, so this assembles the .app around it:
# Info.plist, icon and signature. Output: build/Tidewell.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Tidewell"
BUNDLE_ID="space.iam-deepak.tidewell"
VERSION="1.0"
BUILD_NUMBER="1"
MIN_MACOS="26.0"

CONFIG="release"
[ "${1:-}" = "--debug" ] && CONFIG="debug"

# Prefer the self-signed certificate: an ad-hoc signature changes identity on every
# build, so macOS silently revokes any privacy grant each time — and the stale entry
# still reads as enabled in System Settings, which looks like a broken app rather
# than an unauthorised one.
SELF_SIGNED="Tidewell Self-Signed"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SELF_SIGNED"; then
        SIGN_IDENTITY="$SELF_SIGNED"
    else
        SIGN_IDENTITY="-"
        echo "note: no signing certificate found — falling back to ad-hoc."
        echo "      Full Disk Access and login-item state will reset on every rebuild."
        echo "      Run ./Scripts/make-signing-cert.sh once to fix that permanently."
    fi
fi

APP="build/$APP_NAME.app"
CONTENTS="$APP/Contents"

# arm64 is the default and the primary release artifact. `ARCHS=universal` additionally
# builds x86_64 and lipos them together, for Intel Macs on macOS 14–26 — a transitional
# audience with a known end date, since macOS 26 is the last release supporting Intel.
ARCHS="${ARCHS:-arm64}"

if [ "$ARCHS" = "universal" ]; then
    echo "==> Building ($CONFIG, arm64 + x86_64)"
    swift build -c "$CONFIG" --arch arm64
    swift build -c "$CONFIG" --arch x86_64
    ARM_BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
    X86_BIN="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)"
    BIN_PATH="build/universal"
    mkdir -p "$BIN_PATH"
    lipo -create "$ARM_BIN/$APP_NAME" "$X86_BIN/$APP_NAME" -output "$BIN_PATH/$APP_NAME"
else
    echo "==> Building ($CONFIG, arm64)"
    swift build -c "$CONFIG" --arch arm64
    BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
fi

if [ ! -f "build/icon/$APP_NAME.icns" ]; then
    echo "==> Icon missing, generating"
    ./Icon/make-icon.sh
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "build/icon/$APP_NAME.icns" "$CONTENTS/Resources/$APP_NAME.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Privacy manifest. Nothing is collected, but declaring that explicitly — and naming the
# required-reason APIs actually used — is what makes the claim checkable.
cp Resources/PrivacyInfo.xcprivacy "$CONTENTS/Resources/PrivacyInfo.xcprivacy"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>            <string>en</string>
    <key>CFBundleExecutable</key>                   <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>                   <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>        <string>6.0</string>
    <key>CFBundleName</key>                         <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>                  <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>                  <string>APPL</string>
    <key>CFBundleShortVersionString</key>           <string>$VERSION</string>
    <key>CFBundleVersion</key>                      <string>$BUILD_NUMBER</string>
    <key>CFBundleIconFile</key>                     <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>               <string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key>            <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>             <string>Personal build. Not for redistribution.</string>

    <!-- Sudden termination would let macOS kill the process without running
         applicationWillTerminate, which is where settings are flushed. -->
    <key>NSSupportsAutomaticTermination</key>       <false/>
    <key>NSSupportsSuddenTermination</key>          <false/>

    <!-- Menu bar only: no Dock tile. The main window is still a real, focusable
         window — see WindowPresenter for how it is brought forward. -->
    <key>LSUIElement</key>                          <true/>

    <!-- Folder access is granted by the user picking a folder in NSOpenPanel, and by
         the standard Downloads/Desktop/Documents prompts. There is no usage-description
         key for those; macOS asks on first access. -->
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" > /dev/null

# ── App Intents metadata ────────────────────────────────────────────────────
# Xcode produces this in a build phase SwiftPM does not have. The compiler is asked for
# const values via swiftSettings in Package.swift; this runs the extractor over them.
# If the bundle is missing, the Shortcuts verbs silently do not exist, so a failure here
# is reported rather than swallowed.
TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
PROCESSOR="$TOOLCHAIN/usr/bin/appintentsmetadataprocessor"

if [ -x "$PROCESSOR" ]; then
    echo "==> Extracting App Intents metadata"
    WORK="build/appintents"
    rm -rf "$WORK"; mkdir -p "$WORK"
    find Sources/Tidewell -name "*.swift" > "$WORK/sources.txt"
    find .build -name "*.swiftconstvalues" > "$WORK/const.txt" 2>/dev/null || true

    if [ -s "$WORK/const.txt" ]; then
        "$PROCESSOR" \
            --output "$WORK" \
            --toolchain-dir "$TOOLCHAIN" \
            --module-name "$APP_NAME" \
            --sdk-root "$(xcrun --show-sdk-path)" \
            --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $3}')" \
            --platform-family macOS \
            --deployment-target "$MIN_MACOS" \
            --target-triple "arm64-apple-macos$MIN_MACOS" \
            --source-file-list "$WORK/sources.txt" \
            --swift-const-vals-list "$WORK/const.txt" 2>&1 | sed 's/^/    /'

        if [ -d "$WORK/Metadata.appintents" ]; then
            cp -R "$WORK/Metadata.appintents" "$CONTENTS/Resources/"
            echo "    installed Metadata.appintents"
        else
            echo "    warning: no metadata produced — Shortcuts will not see Tidewell's actions"
        fi
    else
        echo "    warning: no const values — build with the flags in Package.swift"
    fi
fi

echo "==> Signing (identity: $SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - --timestamp=none "$APP"
elif [ "$SIGN_IDENTITY" = "$SELF_SIGNED" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi

codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

echo "==> Done: $APP"
du -sh "$APP" | sed 's/^/    /'
lipo -archs "$CONTENTS/MacOS/$APP_NAME" | sed 's/^/    architectures: /'
