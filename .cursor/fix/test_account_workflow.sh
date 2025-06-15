#!/bin/bash

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_DIR="$DATA_DIR/logs"

echo "=== Mars Credit Account Workflow Test ==="
echo "Testing on: $(date)"

# Step 1: Clean start
echo -e "\n1. Cleaning previous state..."
killall geth 2>/dev/null || true
rm -rf "$KEYSTORE_DIR"/*
mkdir -p "$KEYSTORE_DIR" "$LOG_DIR"

# Step 2: Start the app and wait for initialization
echo -e "\n2. Starting Mars Credit Miner..."
open "Mars Credit Miner.app"
sleep 5

# Step 3: Check if keystore directory is populated
echo -e "\n3. Checking keystore directory..."
ls -la "$KEYSTORE_DIR"
KEYSTORE_FILES=$(ls "$KEYSTORE_DIR" | grep -c "UTC--")
echo "Found $KEYSTORE_FILES keystore files"

if [ $KEYSTORE_FILES -eq 0 ]; then
    echo "❌ No keystore files found - account generation may have failed"
    exit 1
fi

# Step 4: Verify account format
echo -e "\n4. Verifying account format..."
ACCOUNT_FILE=$(ls "$KEYSTORE_DIR"/UTC--* | head -n 1)
if [[ -f "$ACCOUNT_FILE" ]]; then
    echo "✅ Found valid account file: $(basename "$ACCOUNT_FILE")"
    
    # Check if file contains valid JSON
    if jq . "$ACCOUNT_FILE" >/dev/null 2>&1; then
        echo "✅ Account file contains valid JSON"
    else
        echo "❌ Account file is not valid JSON"
        exit 1
    fi
else
    echo "❌ No valid account file found"
    exit 1
fi

# Step 5: Check logs for successful account creation
echo -e "\n5. Checking logs for account creation..."
if [ -f "$LOG_DIR/geth.log" ]; then
    if grep -q "Created new wallet with address" "$LOG_DIR/geth.log"; then
        echo "✅ Found account creation confirmation in logs"
    else
        echo "⚠️ No account creation confirmation found in logs"
    fi
else
    echo "⚠️ No log file found"
fi

# Step 6: Restart app to test account detection
echo -e "\n6. Testing account detection on restart..."
killall "Mars Credit Miner" 2>/dev/null || true
sleep 2
open "Mars Credit Miner.app"
sleep 5

# Check logs for successful account detection
if grep -q "Using existing account" "$LOG_DIR/geth.log"; then
    echo "✅ Account successfully detected on restart"
else
    echo "⚠️ Account detection on restart not confirmed"
fi

echo -e "\n=== Test Complete ==="
echo "Check the app's UI to verify account is loaded correctly"
echo "Next step: Run mining tests" 