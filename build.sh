#!/bin/bash
# Builds Lingo.app from the Swift sources. Requires only the Xcode Command
# Line Tools (xcode-select --install), not the full Xcode.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Lingo"
BUNDLE_ID="com.federicospinoso.lingo"
VERSION="1.0"
MIN_MACOS="13.0"

# The ".noindex" suffix keeps Spotlight from indexing the staged copy, so the
# app appears only once in Launchpad and Spotlight after it is installed.
BUILD_DIR="build.noindex"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "Building ${APP_NAME}..."
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

ARCH="$(uname -m)"

xcrun --sdk macosx swiftc \
    -O \
    -swift-version 5 \
    -target "${ARCH}-apple-macos${MIN_MACOS}" \
    -framework AppKit \
    -framework SwiftUI \
    -framework NaturalLanguage \
    -framework ServiceManagement \
    -framework Carbon \
    Sources/*.swift \
    -o "$MACOS_DIR/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# App icon. Only shows up in Login Items and Finder, so a failure here is not
# worth failing the build over.
if ./Tools/make-icon.sh "$RES_DIR/AppIcon.icns" >/dev/null 2>&1; then
    echo "  icon ok"
else
    echo "  icon skipped"
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Ad-hoc signature: enough for macOS to run it and to give the app a stable
# identity for the login item and the keychain-free network access.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || {
    echo "  warning: ad-hoc signing failed; the app should still run"
}

echo "Built $APP"
