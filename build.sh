#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="WorkMonitor.app"
BUNDLE_DIR="$APP_NAME/Contents"
BINARY="WorkMonitor"
INFO_PLIST="Info.plist"

DEFAULT_DEPLOYMENT_TARGET=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || echo "14.0")
BUILD_ARCH="${BUILD_ARCH:-$(uname -m)}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-$DEFAULT_DEPLOYMENT_TARGET}"
TARGET_TRIPLE="${BUILD_ARCH}-apple-macosx${MACOS_DEPLOYMENT_TARGET}"

echo "Building Work Monitor..."

# Clean previous build
rm -rf "$APP_NAME" "$BINARY"

# Generate app icon
echo "Generating app icon..."
swift scripts/generate-icon.swift icon_1024.png

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     icon_1024.png --out "$ICONSET/icon_16x16.png"      > /dev/null
sips -z 32 32     icon_1024.png --out "$ICONSET/icon_16x16@2x.png"   > /dev/null
sips -z 32 32     icon_1024.png --out "$ICONSET/icon_32x32.png"      > /dev/null
sips -z 64 64     icon_1024.png --out "$ICONSET/icon_32x32@2x.png"   > /dev/null
sips -z 128 128   icon_1024.png --out "$ICONSET/icon_128x128.png"    > /dev/null
sips -z 256 256   icon_1024.png --out "$ICONSET/icon_128x128@2x.png" > /dev/null
sips -z 256 256   icon_1024.png --out "$ICONSET/icon_256x256.png"    > /dev/null
sips -z 512 512   icon_1024.png --out "$ICONSET/icon_256x256@2x.png" > /dev/null
sips -z 512 512   icon_1024.png --out "$ICONSET/icon_512x512.png"    > /dev/null
sips -z 1024 1024 icon_1024.png --out "$ICONSET/icon_512x512@2x.png" > /dev/null
iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET" icon_1024.png

# Compile
echo "Compiling for $TARGET_TRIPLE..."
swiftc \
    -parse-as-library \
    -target "$TARGET_TRIPLE" \
    -O \
    -o "$BINARY" \
    Sources/*.swift

# Create app bundle
mkdir -p "$BUNDLE_DIR/MacOS"
mkdir -p "$BUNDLE_DIR/Resources"
mv "$BINARY" "$BUNDLE_DIR/MacOS/"
cp "$INFO_PLIST" "$BUNDLE_DIR/"
mv AppIcon.icns "$BUNDLE_DIR/Resources/"

# Ad-hoc code sign
codesign --force --sign - "$APP_NAME"

echo ""
echo "Built $APP_NAME successfully!"
echo ""
echo "To run:     open $SCRIPT_DIR/$APP_NAME"
echo "To install: cp -r $APP_NAME /Applications/"
echo ""
echo "To launch at login: right-click the menu bar icon > Launch at Login"
echo "To override target: BUILD_ARCH=x86_64 MACOS_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET ./build.sh"
