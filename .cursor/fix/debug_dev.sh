#!/bin/bash

# Kill any existing geth processes
killall geth 2>/dev/null || true
sleep 2

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_DIR="$DATA_DIR/logs"

mkdir -p "$DATA_DIR" "$KEYSTORE_DIR" "$LOG_DIR"

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

echo "Running Geth in development mode..." >> "$LOG_DIR/geth.log"

# Start geth in development mode
nohup ./Resources/geth/geth \
    --dev \
    --datadir "$DATA_DIR" \
    --keystore "$KEYSTORE_DIR" \
    --http \
    --http.addr "localhost" \
    --http.port "8546" \
    --http.api "personal,eth,net,web3,miner,debug,admin" \
    --http.vhosts "*" \
    --http.corsdomain "*" \
    --networkid "110110" \
    --dev.period 1 \
    --miner.etherbase "$MINING_ADDRESS" \
    --nodiscover \
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
    
    # Check mining status
    MINING_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
        http://localhost:8546)
    
    echo "Mining status: $MINING_STATUS"
    
    # Check balance
    BALANCE=$(curl -s -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$MINING_ADDRESS\", \"latest\"],\"id\":1}" \
        http://localhost:8546)
    
    echo "Current balance: $BALANCE"
    
    echo "Check logs with: tail -f $LOG_DIR/geth.log"
    echo "Monitor system load with: top -pid $(cat "$DATA_DIR/geth.pid")"
    echo "Kill process with: kill -9 $(cat "$DATA_DIR/geth.pid")"
else
    echo "Failed to start Geth process"
    tail -n 30 "$LOG_DIR/geth.log"
fi 