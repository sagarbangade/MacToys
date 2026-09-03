#!/bin/bash
set -e

echo "Building MacToys..."
swift build -c release

APP_DIR=".build/release/MacToys.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "Creating App Bundle Structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying binary..."
cp .build/release/MacToys "$MACOS_DIR/"

echo "Creating Info.plist..."
cat << PLIST > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacToys</string>
    <key>CFBundleIdentifier</key>
    <string>com.mactoys.app</string>
    <key>CFBundleName</key>
    <string>MacToys</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Code signing with ad-hoc..."
codesign --force --deep --sign - "$APP_DIR"

echo "Done! The app is at $APP_DIR"
