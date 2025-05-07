#!/bin/bash

echo "===== Building Mars Credit Miner DMG for Apple Silicon (Simple Version) ====="

# Check if app exists
if [ ! -d "Mars Credit Miner.app" ]; then
    echo "Error: Mars Credit Miner.app not found"
    exit 1
fi

# Create DMG file using hdiutil directly
echo "Creating DMG file..."
APP_NAME="Mars Credit Miner"
DMG_NAME="${APP_NAME// /-}-apple-silicon"
DMG_PATH="build/${DMG_NAME}.dmg"

# Ensure build directory exists
mkdir -p build

# Remove existing DMG if it exists
if [ -f "$DMG_PATH" ]; then
    echo "Removing existing DMG..."
    rm -f "$DMG_PATH"
fi

# Create a temporary directory for DMG contents
TEMP_DIR="build/dmg_contents"
mkdir -p "$TEMP_DIR"

# Copy the app to the temporary directory
cp -R "$APP_NAME.app" "$TEMP_DIR/"

# Create a symlink to Applications folder
ln -s /Applications "$TEMP_DIR/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$TEMP_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up
rm -rf "$TEMP_DIR"

echo "===== Build Complete ====="
echo "DMG file created at: $DMG_PATH"
echo "App optimized for Apple Silicon with improved mining performance" 