#!/bin/bash

# Exit on error
set -e

APP_NAME="Mars Credit Miner.app"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Create directories
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy executable
cp .build/release/MarsCredit "$MACOS_DIR/"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MarsCredit</string>
    <key>CFBundleIdentifier</key>
    <string>com.marscredit.miner</string>
    <key>CFBundleName</key>
    <string>Mars Credit Miner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Create DMG
create-dmg \
    --volname "Mars Credit Miner" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "$APP_NAME" 200 190 \
    --hide-extension "$APP_NAME" \
    --app-drop-link 600 185 \
    "Mars Credit Miner.dmg" \
    "$APP_NAME" 