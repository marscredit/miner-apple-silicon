#!/bin/bash

# Kill any existing geth processes
killall geth 2>/dev/null || true
sleep 2

# Set up minimal test directory
TEST_DIR="$HOME/.marscredit-minimal-test"
mkdir -p "$TEST_DIR"
mkdir -p "$TEST_DIR/logs"

echo "Testing Geth binary version..."
if ! ./Resources/geth/geth version; then
    echo "Error: Geth binary test failed"
    exit 1
fi

echo "Starting minimal Geth test with --dev mode..."

# Run with absolute minimal settings in dev mode
nohup ./Resources/geth/geth \
    --dev \
    --datadir "$TEST_DIR" \
    --nodiscover \
    --maxpeers 0 \
    --cache 32 \
    --verbosity 5 \
    --nousb \
    --port 30305 \
    --ipcdisable \
    --networkid 110110 \
    --rpc.gascap 0 \
    --dev.period 0 > "$TEST_DIR/logs/geth.log" 2>&1 &

# Save the PID
echo $! > "$TEST_DIR/geth.pid"

echo "Geth started in background. Waiting 5 seconds to check status..."
sleep 5

# Check if process is still running
if ps -p $(cat "$TEST_DIR/geth.pid") > /dev/null; then
    echo "Geth is running. Last few lines of log:"
    tail -n 10 "$TEST_DIR/logs/geth.log"
    echo "To check full logs: cat $TEST_DIR/logs/geth.log"
else
    echo "Geth process died. Last few lines of log:"
    tail -n 20 "$TEST_DIR/logs/geth.log"
fi 