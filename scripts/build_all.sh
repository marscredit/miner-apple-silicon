#!/bin/bash

# Exit on error
set -e

echo "🚀 Building Mars Credit Miner - Build 29"
echo "========================================"

# Build the Swift project
echo "📦 Step 1: Building Swift project..."
swift build -c release || {
    echo "❌ Error: Failed to build Swift project"
    exit 1
}

echo "✅ Swift project built successfully"

# Create the app bundle
echo ""
echo "📱 Step 2: Creating app bundle..."
./create_app.sh || {
    echo "❌ Error: Failed to create app bundle"
    exit 1
}

echo "✅ App bundle created successfully"

# Ask if user wants to create DMG
echo ""
read -p "🔧 Create DMG file? (y/n): " create_dmg

if [[ $create_dmg =~ ^[Yy]$ ]]; then
    echo ""
    echo "💿 Step 3: Creating DMG..."
    ./scripts/build_app_dmg.sh || {
        echo "❌ Error: Failed to create DMG"
        exit 1
    }
    echo "✅ DMG created successfully"
else
    echo "📁 Skipping DMG creation"
fi

echo ""
echo "🎉 Build 29 Complete!"
echo "📂 App bundle: builds/build29/Mars Credit Miner.app"

if [[ $create_dmg =~ ^[Yy]$ ]]; then
    echo "💿 DMG file: builds/build29/Mars-Credit-Miner-Build29.dmg"
fi

echo ""
echo "🔧 New Features in Build 29:"
echo "   ✓ Fixed sleep/wake crash issue"
echo "   ✓ Moved heavy operations off main thread"
echo "   ✓ Better geth process management"
echo "   ✓ Enhanced error recovery and cleanup"
echo "   ✓ Organized project structure"
echo "" 