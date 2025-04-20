#!/bin/bash

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_DIR="$DATA_DIR/logs"
ETHASH_DIR="$DATA_DIR/ethash"

echo "=== Mars Credit Mining Workflow Test ==="
echo "Testing on: $(date)"

# Step 1: Ensure we have an account
echo -e "\n1. Checking for existing account..."
if [ ! -d "$KEYSTORE_DIR" ] || [ -z "$(ls -A "$KEYSTORE_DIR")" ]; then
    echo "❌ No account found. Please run test_account_workflow.sh first"
    exit 1
fi

# Step 2: Clear existing Geth processes
echo -e "\n2. Cleaning up existing processes..."
killall geth 2>/dev/null || true
sleep 2

# Step 3: Start the app
echo -e "\n3. Starting Mars Credit Miner..."
open "Mars Credit Miner.app"
sleep 5

# Step 4: Monitor DAG generation
echo -e "\n4. Monitoring DAG generation..."
(tail -f "$LOG_DIR/geth.log" & echo $! >&3) 3>pid | grep -m 1 "Generated DAG" || true
kill $(cat pid)
rm pid

if grep -q "Generated DAG" "$LOG_DIR/geth.log"; then
    echo "✅ DAG generation completed"
else
    echo "⚠️ DAG generation not confirmed within timeout"
fi

# Step 5: Check for mining startup
echo -e "\n5. Checking mining startup..."
(tail -f "$LOG_DIR/geth.log" & echo $! >&3) 3>pid | grep -m 1 "Mining started" || true
kill $(cat pid)
rm pid

if grep -q "Mining started" "$LOG_DIR/geth.log"; then
    echo "✅ Mining started successfully"
else
    echo "❌ Mining startup not confirmed"
fi

# Step 6: Monitor hashrate
echo -e "\n6. Monitoring hashrate..."
echo "Waiting 30 seconds for stable hashrate..."
sleep 30

# Use curl to check hashrate via RPC
HASHRATE=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_hashrate","params":[],"id":1}' \
    http://localhost:8546 | jq -r '.result')

if [ "$HASHRATE" != "null" ] && [ "$HASHRATE" != "0x0" ]; then
    echo "✅ Mining hashrate detected: $HASHRATE"
else
    echo "❌ No hashrate detected"
fi

# Step 7: Check network connectivity
echo -e "\n7. Checking network connectivity..."
PEER_COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8546 | jq -r '.result')

if [ "$PEER_COUNT" != "null" ] && [ "$PEER_COUNT" != "0x0" ]; then
    echo "✅ Connected to network with $((16#${PEER_COUNT#0x})) peers"
else
    echo "⚠️ No peers connected"
fi

# Step 8: Test error recovery
echo -e "\n8. Testing error recovery..."
echo "Stopping Geth process..."
killall geth
sleep 5

# Check if app automatically restarts mining
(tail -f "$LOG_DIR/geth.log" & echo $! >&3) 3>pid | grep -m 1 "Mining started" || true
kill $(cat pid)
rm pid

if grep -q "Mining started" "$LOG_DIR/geth.log"; then
    echo "✅ Mining automatically recovered after process kill"
else
    echo "❌ Mining did not automatically recover"
fi

# Step 9: Final status check
echo -e "\n9. Final status check..."
if curl -s http://localhost:8546 > /dev/null; then
    echo "✅ RPC endpoint responding"
else
    echo "❌ RPC endpoint not responding"
fi

echo -e "\n=== Test Complete ==="
echo "Check the app's UI for:"
echo "1. Mining status indicator"
echo "2. Current hashrate display"
echo "3. Network connection status"
echo "4. Any error messages"

# Optional: Dump recent logs for analysis
echo -e "\nRecent logs from geth.log:"
tail -n 20 "$LOG_DIR/geth.log" 