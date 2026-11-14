#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="AntigravityQuotaBar.app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> Compiling Swift code..."
mkdir -p /tmp/module-cache
swiftc \
    -O \
    -module-cache-path /tmp/module-cache \
    -target arm64-apple-macosx13.0 \
    -framework Cocoa \
    -framework Network \
    -framework Security \
    -framework UserNotifications \
    "$PROJECT_DIR/Sources/AccountManager.swift" \
    "$PROJECT_DIR/Sources/QuotaFetcher.swift" \
    "$PROJECT_DIR/Sources/ModelTracker.swift" \
    "$PROJECT_DIR/Sources/QuotaAlertManager.swift" \
    "$PROJECT_DIR/Sources/LocalSavingsManager.swift" \
    "$PROJECT_DIR/Sources/AppDelegate.swift" \
    "$PROJECT_DIR/Sources/main.swift" \
    -o "$MACOS_DIR/AntigravityQuotaBar"

echo "==> Creating Info.plist..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AntigravityQuotaBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.antigravityquotabar</string>
    <key>CFBundleName</key>
    <string>AntigravityQuotaBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Copying brand icons and app icon..."
cp "$PROJECT_DIR"/Resources/Icons/*.svg "$RESOURCES_DIR/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/"

echo "==> Signing the app with an ad-hoc signature..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Build completed successfully at: $APP_BUNDLE"
