#!/bin/bash

# Exit on error
set -e

APP_NAME="Mars Credit Miner.app"
BUILD_DIR="builds/build29"
CONTENTS_DIR="$BUILD_DIR/$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
VERSION_FILE="build_version.txt"
BUNDLE_VERSION_FILE="$RESOURCES_DIR/VERSION.txt"

# Create build directory
mkdir -p "$BUILD_DIR"

# Get build number from version file
BUILD_NUMBER=29
if [ -f "$VERSION_FILE" ]; then
    BUILD_NUMBER=$(cat "$VERSION_FILE")
fi

echo "Creating Build $BUILD_NUMBER..."

# Create directories
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Write version to bundle
echo "Build: $BUILD_NUMBER" > "$BUNDLE_VERSION_FILE"
echo "Date: $(date)" >> "$BUNDLE_VERSION_FILE"
echo "App version $BUILD_NUMBER written to $BUNDLE_VERSION_FILE"

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
fi

# Copy the app helper script from the new scripts directory
if [ -f "./scripts/app_helper.sh" ]; then
    cp "./scripts/app_helper.sh" "$RESOURCES_DIR/"
    echo "App helper script copied to app bundle: $RESOURCES_DIR/app_helper.sh"
    chmod +x "$RESOURCES_DIR/app_helper.sh"
else
    # Fallback to old location
    if [ -f "./Resources/app_helper.sh" ]; then
        cp "./Resources/app_helper.sh" "$RESOURCES_DIR/"
        echo "App helper script copied from Resources: $RESOURCES_DIR/app_helper.sh"
        chmod +x "$RESOURCES_DIR/app_helper.sh"
    else
        echo "Warning: app_helper.sh not found in scripts/ or Resources/. App may not start correctly."
    fi
fi

# Copy the Mars Credit genesis file
if [ -f "./Resources/mars_credit_genesis.json" ]; then
    cp "./Resources/mars_credit_genesis.json" "$RESOURCES_DIR/"
    echo "Mars Credit genesis file copied to app bundle: $RESOURCES_DIR/mars_credit_genesis.json"
else
    echo "Warning: ./Resources/mars_credit_genesis.json not found. Geth may not initialize with correct genesis."
fi

# Copy executable
if [ -f ".build/release/MarsCredit" ]; then
    cp .build/release/MarsCredit "$MACOS_DIR/"
    echo "Executable copied to app bundle: $MACOS_DIR/MarsCredit"
else
    echo "Error: .build/release/MarsCredit not found. Build the project first with 'swift build -c release'"
    exit 1
fi

# Copy app icon if it exists
if [ -f "./Sources/MarsCredit/Resources/AppIcon.icns" ]; then
    cp "./Sources/MarsCredit/Resources/AppIcon.icns" "$RESOURCES_DIR/"
    echo "App icon copied to app bundle: $RESOURCES_DIR/AppIcon.icns"
    ICON_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    echo "Warning: AppIcon.icns not found. App will use default icon."
    ICON_ENTRY=""
fi

# Copy font file if it exists
if [ -f "./Sources/MarsCredit/Resources/gunshipboldital.otf" ]; then
    cp "./Sources/MarsCredit/Resources/gunshipboldital.otf" "$RESOURCES_DIR/"
    echo "Font file copied to app bundle: $RESOURCES_DIR/gunshipboldital.otf"
else
    echo "Warning: gunshipboldital.otf not found. App may not display fonts correctly."
fi

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
    <string>1.0.$BUILD_NUMBER</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
$ICON_ENTRY
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
</dict>
</plist>
EOF

echo "Re-signing the app bundle with an ad-hoc signature..."
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME" || echo "Warning: Ad-hoc codesign failed. This might be an issue on some systems."
echo "App bundle re-signed." 

echo ""
echo "✅ Build $BUILD_NUMBER created successfully!"
echo "📁 Location: $BUILD_DIR/$APP_NAME"
echo "🔧 Build improvements:"
echo "   - Moved heavy operations off main thread"
echo "   - Added sleep/wake detection to prevent geth crashes"
echo "   - Improved error recovery with bundled geth binary"
echo "   - Better resource management and cleanup"
echo ""
echo "To create a DMG, run: ./scripts/build_app_dmg.sh" 