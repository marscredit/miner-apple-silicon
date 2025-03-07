#!/bin/bash

# Exit on error
set -e

echo "Building Mars Credit Miner for Apple Silicon..."

# Check for Xcode
if ! xcode-select -p &> /dev/null; then
    echo "Xcode command line tools not found. Please install them."
    exit 1
fi

# Check for Go
if ! command -v go &> /dev/null; then
    echo "Go is not installed. Please install Go first."
    exit 1
fi

# Configuration
APP_NAME="Mars Credit Miner"
ICON_NAME="AppIcon"
BUILD_DIR=".build"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MACOS_DIR="$CONTENTS_DIR/MacOS"
DEPS_DIR="$RESOURCES_DIR/deps"
GO_MARSCREDIT_DIR="$DEPS_DIR/go-marscredit"

# Clean previous build
rm -rf "$APP_DIR"

# Build Swift app
echo "Building for production..."
swift build -c release

# Create app structure
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/fonts" "$DEPS_DIR"

# Set up go-marscredit
echo "Setting up go-marscredit..."
mkdir -p "$GO_MARSCREDIT_DIR/build/bin"

# Download pre-built geth binary for Apple Silicon
GETH_VERSION="1.15.4"
GETH_COMMIT="8ccca244"
GETH_URL="https://gethstore.blob.core.windows.net/builds/geth-darwin-arm64-${GETH_VERSION}-${GETH_COMMIT}.tar.gz"
echo "Downloading geth from $GETH_URL..."
curl -L $GETH_URL -o geth.tar.gz
tar -xzf geth.tar.gz
mv geth-darwin-arm64-${GETH_VERSION}-${GETH_COMMIT}/geth "$GO_MARSCREDIT_DIR/build/bin/"
rm -rf geth.tar.gz geth-darwin-arm64-${GETH_VERSION}-${GETH_COMMIT}

# Make geth executable
chmod +x "$GO_MARSCREDIT_DIR/build/bin/geth"

# Copy binary
cp "$BUILD_DIR/arm64-apple-macosx/release/MarsCredit" "$MACOS_DIR/$APP_NAME"

# Copy resources
cp Resources/gunshipboldital.otf "$RESOURCES_DIR/fonts/"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>xyz.marscredit.miner</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# Create icns if it doesn't exist
if [ ! -f "$RESOURCES_DIR/$ICON_NAME.icns" ]; then
    ./create_icons.sh
    cp "$ICON_NAME.icns" "$RESOURCES_DIR/"
fi

# Create DMG
echo "Creating DMG..."
create-dmg \
    --volname "$APP_NAME" \
    --volicon "$ICON_NAME.icns" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 200 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 600 185 \
    "$APP_NAME.dmg" \
    "$APP_NAME.app"

echo "Build complete!" 