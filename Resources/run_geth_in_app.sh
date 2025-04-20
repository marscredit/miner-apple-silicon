#!/bin/bash

# Kill any existing geth processes
killall geth 2>/dev/null || true
sleep 2  # Increased sleep to ensure proper cleanup

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_FILE="$DATA_DIR/geth.log"

mkdir -p "$DATA_DIR" "$KEYSTORE_DIR"

# Clear the log file
echo "Starting Geth node..." > "$LOG_FILE"

# Start geth in the background with more conservative settings
nohup Resources/geth/geth \
    --datadir "$DATA_DIR" \
    --keystore "$KEYSTORE_DIR" \
    --syncmode "full" \
    --http --http.addr "localhost" --http.port 8546 \
    --http.api "personal,eth,net,web3,miner,admin,debug" \
    --http.vhosts "*" --http.corsdomain "*" \
    --networkid 110110 \
    --ws --ws.addr "localhost" --ws.port 8547 \
    --ws.api "personal,eth,net,web3,miner,admin,debug" \
    --port 30304 \
    --nat "any" \
    --mine --miner.threads 1 \
    --nodiscover \
    --verbosity 3 \
    --maxpeers 50 \
    --cache 2048 \
    --nousb \
    --metrics \
    --allow-insecure-unlock \
    >> "$LOG_FILE" 2>&1 &

# Save the PID
echo $! > "$DATA_DIR/geth.pid"

# Wait for geth to start and check its status
sleep 5
if ! pgrep -F "$DATA_DIR/geth.pid" > /dev/null; then
    echo "Failed to start geth process" >&2
    exit 1
fi

# Wait for RPC endpoint to become available
for i in {1..30}; do
    if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' http://localhost:8546 > /dev/null 2>&1; then
        echo "RPC endpoint is available"
        break
    fi
    echo "Waiting for RPC endpoint to become available (attempt $i/30)..."
    sleep 2
done

# Exit success
exit 0 