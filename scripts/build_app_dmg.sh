#!/bin/bash

# Exit on error
set -e

# Configuration
APP_NAME="Mars Credit Miner.app"
BUILD_DIR="builds/build29"
VERSION_FILE="build_version.txt"

# Get build number
BUILD_NUMBER=29
if [ -f "$VERSION_FILE" ]; then
    BUILD_NUMBER=$(cat "$VERSION_FILE")
fi

DMG_NAME="Mars-Credit-Miner-Build${BUILD_NUMBER}.dmg"
DMG_OUTPUT_PATH="builds/build29/$DMG_NAME"

echo "Creating DMG for Build $BUILD_NUMBER..."

# Check if app bundle exists
if [ ! -d "$BUILD_DIR/$APP_NAME" ]; then
    echo "Error: App bundle not found at $BUILD_DIR/$APP_NAME"
    echo "Run './create_app.sh' first to build the app bundle"
    exit 1
fi

# Remove existing DMG if it exists
if [ -f "$DMG_OUTPUT_PATH" ]; then
    echo "Removing existing DMG: $DMG_OUTPUT_PATH"
    rm "$DMG_OUTPUT_PATH"
fi

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg via Homebrew..."
    brew install create-dmg
fi

echo "Creating DMG with create-dmg..."

# Create DMG with create-dmg
create-dmg \
    --volname "Mars Credit Miner Build $BUILD_NUMBER" \
    --volicon "$BUILD_DIR/$APP_NAME/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "$APP_NAME" 200 190 \
    --hide-extension "$APP_NAME" \
    --app-drop-link 600 185 \
    "$DMG_OUTPUT_PATH" \
    "$BUILD_DIR/"

# Check if DMG was created successfully
if [ -f "$DMG_OUTPUT_PATH" ]; then
    echo ""
    echo "✅ DMG created successfully!"
    echo "📁 Location: $DMG_OUTPUT_PATH"
    echo "📊 Size: $(du -h "$DMG_OUTPUT_PATH" | cut -f1)"
    echo ""
    echo "🔧 Build $BUILD_NUMBER Features:"
    echo "   - Fixed sleep/wake crash issue"
    echo "   - Improved startup performance (background thread initialization)"
    echo "   - Better geth process management"
    echo "   - Enhanced error recovery and cleanup"
    echo ""
    echo "The DMG is ready for distribution!"
else
    echo "❌ Error: Failed to create DMG"
    exit 1
fi 