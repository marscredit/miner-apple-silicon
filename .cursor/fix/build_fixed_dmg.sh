#!/bin/bash

# This script builds a new DMG with the fixed Mars Credit Miner application

echo "===== Building Fixed Mars Credit Miner DMG ====="

# Make sure we have the geth binary in the Resources directory
if [ ! -f "Resources/geth/geth" ]; then
    echo "Error: geth binary not found in Resources/geth/"
    
    if [ -f "$HOME/.marscredit/geth-binary" ]; then
        echo "Copying geth binary from ~/.marscredit/geth-binary"
        mkdir -p Resources/geth
        cp "$HOME/.marscredit/geth-binary" Resources/geth/geth
        chmod +x Resources/geth/geth
    else
        echo "No geth binary found. Please run app_helper.sh first."
        exit 1
    fi
fi

# Make sure app_helper.sh is in the Resources directory
if [ ! -f "Resources/app_helper.sh" ]; then
    echo "Copying app_helper.sh to Resources/"
    cp app_helper.sh Resources/
    chmod +x Resources/app_helper.sh
fi

# Create a launch script in Resources that will be run when the app starts
echo "Creating launcher script in Resources/"
cat > Resources/launch.sh << EOF
#!/bin/bash

# This script runs when the app starts
# It ensures the geth binary and environment are properly set up

APP_DIR="\$(dirname "\$(dirname "\$(dirname "\$0")")")"
RESOURCES_DIR="\$APP_DIR/Contents/Resources"

# Run the app helper script if it exists
if [ -f "\$RESOURCES_DIR/app_helper.sh" ]; then
    cd "\$RESOURCES_DIR/.."
    "\$RESOURCES_DIR/app_helper.sh" &
fi
EOF

chmod +x Resources/launch.sh

# Create a new DMG
echo "Building DMG..."
DMG_NAME="Mars Credit Miner - Fixed.dmg"

# Remove old DMG if it exists
if [ -f "$DMG_NAME" ]; then
    rm "$DMG_NAME"
fi

# Create DMG
hdiutil create -volname "Mars Credit Miner" -srcfolder "Mars Credit Miner.app" -ov -format UDZO "$DMG_NAME"

echo "===== DMG Build Complete ====="
echo "New DMG created: $DMG_NAME"
echo ""
echo "Instructions for users:"
echo "1. Open the new DMG and drag 'Mars Credit Miner' to your Applications folder"
echo "2. Right-click on the app and select 'Open' (may need to do this twice on first run)"
echo "3. The app will now correctly find and use the geth binary"
echo "4. When clicking 'Start Mining', you should see the Mars planet with spinning moon" 