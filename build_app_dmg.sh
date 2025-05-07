#!/bin/bash

echo "===== Building Mars Credit Miner DMG for Apple Silicon ====="

# Make sure dependencies are installed
if ! command -v create-dmg &> /dev/null; then
    echo "Installing create-dmg tool..."
    brew install create-dmg || {
        echo "Error: Failed to install create-dmg. Please install manually with 'brew install create-dmg'"
        exit 1
    }
fi

# Build the Swift app
echo "Building Mars Credit Miner app..."
swift build -c release || {
    echo "Error: Failed to build the Swift app"
    exit 1
}

# Create app bundle
echo "Creating app bundle..."
if [ -d "Mars Credit Miner.app" ]; then
    echo "Removing existing app bundle..."
    rm -rf "Mars Credit Miner.app"
fi

# Run the app creation script
if [ -f "create_app.sh" ]; then
    echo "Running create_app.sh..."
    chmod +x create_app.sh
    ./create_app.sh || {
        echo "Error: Failed to create app bundle"
        exit 1
    }
else
    echo "Error: create_app.sh not found"
    exit 1
fi

# Run the icon creation script
if [ -f "create_icons.sh" ]; then
    echo "Running create_icons.sh..."
    chmod +x create_icons.sh
    ./create_icons.sh || {
        echo "Error: Failed to create app icons"
        # Continue anyway
    }
fi

# Update the app with optimized mining configuration
echo "Updating app with optimized mining configuration..."
swift update_mining_config.swift || {
    echo "Error: Failed to update mining configuration"
    # Continue anyway
}

# Create DMG file
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

# Create DMG
create-dmg \
    --volname "$APP_NAME" \
    --volicon "Resources/AppIcon.icns" \
    --background "Resources/dmg-background.png" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 200 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 600 185 \
    "$DMG_PATH" \
    "$APP_NAME.app" || {
    echo "Error: Failed to create DMG file"
    exit 1
}

echo "===== Build Complete ====="
echo "DMG file created at: $DMG_PATH"
echo "App optimized for Apple Silicon with improved mining performance" 