#!/bin/bash

# Exit on error
set -e

APP_NAME="Mars Credit Miner.app"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Create directories
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Create geth subdirectory in Resources
mkdir -p "$RESOURCES_DIR/geth"

# Copy geth binary
if [ -f "./Resources/geth/geth" ]; then
    cp "./Resources/geth/geth" "$RESOURCES_DIR/geth/"
    echo "Geth binary copied to app bundle: $RESOURCES_DIR/geth/geth"
    # Ensure the copied geth binary is executable
    chmod +x "$RESOURCES_DIR/geth/geth"
else
    echo "Error: ./Resources/geth/geth not found. Geth binary will be missing from app bundle."
    # You might want to exit 1 here if Geth is critical for the app to function
    # exit 1 
fi

# Copy the geth wrapper script
if [ -f "./Resources/run_geth_in_app.sh" ]; then
    cp "./Resources/run_geth_in_app.sh" "$RESOURCES_DIR/"
    echo "Geth wrapper script copied to app bundle: $RESOURCES_DIR/run_geth_in_app.sh"
    chmod +x "$RESOURCES_DIR/run_geth_in_app.sh"
else
    echo "Warning: ./Resources/run_geth_in_app.sh not found. Geth may not start correctly from the app."
fi

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

# (Section to be removed)
# Create DMG
# create-dmg \
#     --volname "Mars Credit Miner" \
#     --window-pos 200 120 \
#     --window-size 800 400 \
#     --icon-size 100 \
#     --icon "$APP_NAME" 200 190 \
#     --hide-extension "$APP_NAME" \
#     --app-drop-link 600 185 \
#     "Mars Credit Miner.dmg" \
#     "$APP_NAME" 