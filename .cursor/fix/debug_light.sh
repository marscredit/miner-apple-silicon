#!/bin/bash

# Kill any existing geth processes
killall geth 2>/dev/null || true
sleep 2

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_DIR="$DATA_DIR/logs"
ETHASH_DIR="$DATA_DIR/ethash"

mkdir -p "$DATA_DIR" "$KEYSTORE_DIR" "$LOG_DIR" "$ETHASH_DIR"

# Clear the log file
echo "Starting Geth node at $(date)" > "$LOG_DIR/geth.log"

# Get existing account or create new one
if [ -z "$(ls -A "$KEYSTORE_DIR")" ]; then
    echo "Creating new account..."
    ACCOUNT=$(./Resources/geth/geth --datadir "$DATA_DIR" account new --password <(echo "password123"))
    if [ $? -ne 0 ]; then
        echo "Account creation failed"
        exit 1
    fi
    MINING_ADDRESS=$(echo $ACCOUNT | grep -o '{[[:xdigit:]]\{40\}}' | tr -d '{}')
else
    MINING_ADDRESS=$(./Resources/geth/geth --datadir "$DATA_DIR" account list | head -n 1 | grep -o '{[[:xdigit:]]\{40\}}' | tr -d '{}')
fi

# Add 0x prefix to the address
MINING_ADDRESS="0x${MINING_ADDRESS}"
echo "Using mining address: $MINING_ADDRESS"

echo "Starting Geth with minimal settings..." >> "$LOG_DIR/geth.log"

# Start geth with minimal settings
nohup ./Resources/geth/geth \
    --datadir "$DATA_DIR" \
    --keystore "$KEYSTORE_DIR" \
    --syncmode "light" \
    --http \
    --http.addr "localhost" \
    --http.port "8546" \
    --http.api "personal,eth,net,web3,miner" \
    --http.vhosts "*" \
    --http.corsdomain "*" \
    --networkid "110110" \
    --port "30304" \
    --miner.etherbase "$MINING_ADDRESS" \
    --maxpeers "10" \
    --cache "1024" \
    --nousb \
    --verbosity 3 >> "$LOG_DIR/geth.log" 2>&1 &

# Save the PID
echo $! > "$DATA_DIR/geth.pid"

echo "Waiting for RPC endpoint..."
for i in {1..30}; do
    if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
            http://localhost:8546 > /dev/null 2>&1; then
        echo "RPC endpoint is available"
        break
    fi
    echo "Waiting for RPC endpoint (attempt $i/30)..."
    sleep 2
done

# Verify process is running
if ps -p $(cat "$DATA_DIR/geth.pid") > /dev/null; then
    echo "Geth started successfully with PID $(cat "$DATA_DIR/geth.pid")"
    
    # Check sync status
    SYNC_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        http://localhost:8546)
    
    echo "Sync status: $SYNC_STATUS"
    
    # Try to start mining
    echo "Attempting to start mining..."
    START_MINING=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
        http://localhost:8546)
    
    echo "Mining start response: $START_MINING"
    
    echo "Check logs with: tail -f $LOG_DIR/geth.log"
    echo "Monitor system load with: top -pid $(cat "$DATA_DIR/geth.pid")"
    echo "Kill process with: kill -9 $(cat "$DATA_DIR/geth.pid")"
else
    echo "Failed to start Geth process"
    tail -n 30 "$LOG_DIR/geth.log"
fi 