#!/bin/bash

echo "===== Mars Credit Miner - Quick Test Mode ====="
echo "This script lets you test the miner without full installation or DMG creation."

# Check if debug script exists
if [ ! -f "debug_apple_silicon.sh" ]; then
    echo "Error: debug_apple_silicon.sh not found!"
    exit 1
fi

# Make the debug script executable
chmod +x debug_apple_silicon.sh

# Check if the app is running in "dev mode" or "installed mode"
if [ -d ".build" ]; then
    echo "Detected development environment."
    
    # For dev mode, make sure our script is up to date
    echo "Running the app's debug script..."
    ./debug_apple_silicon.sh
else
    # For installed mode, use the script from resources directory
    APP_PATH="Mars Credit Miner.app"
    if [ -d "$APP_PATH" ]; then
        SCRIPT_PATH="$APP_PATH/Contents/Resources/debug_apple_silicon.sh"
        if [ -f "$SCRIPT_PATH" ]; then
            echo "Using the script from app bundle..."
            chmod +x "$SCRIPT_PATH"
            "$SCRIPT_PATH"
        else
            echo "Script not found in app bundle, using local script..."
            ./debug_apple_silicon.sh
        fi
    else
        echo "App not found, using local script..."
        ./debug_apple_silicon.sh
    fi
fi

echo ""
echo "===== Miner Started ====="
echo "To check status and logs:"
echo "- Mining status: curl -s -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_mining\",\"params\":[],\"id\":1}' http://localhost:8546"
echo "- Hashrate: curl -s -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_hashrate\",\"params\":[],\"id\":1}' http://localhost:8546"
echo "- Logs: tail -f ~/.marscredit/logs/geth.log" 