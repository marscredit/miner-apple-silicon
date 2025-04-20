#!/bin/bash

# This is a simple wrapper that will run Geth in a predictable way
# The app will call this script instead of trying to manage Geth directly

# Log start time
echo "Starting Geth wrapper at $(date)" > ~/geth_wrapper.log

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

# Pre-generate DAG file to avoid freezing
echo "Pre-generating DAG file..." >> "$LOG_DIR/geth.log"
TEMP_DIR="$DATA_DIR/temp"
mkdir -p "$TEMP_DIR"

# Run a temporary instance just to trigger DAG generation
./Resources/geth/geth \
    --datadir "$TEMP_DIR" \
    --verbosity 5 \
    --maxpeers 0 \
    --nodiscover \
    --mine \
    --nousb > "$LOG_DIR/dag_generation.log" 2>&1 &

DAG_PID=$!

# Wait for 5 seconds to let DAG generation start
sleep 5
kill $DAG_PID 2>/dev/null || true
rm -rf "$TEMP_DIR"
sleep 2

echo "Starting main Geth process..." >> "$LOG_DIR/geth.log"

# Start geth in the background with production settings
nohup ./Resources/geth/geth \
    --datadir "$DATA_DIR" \
    --keystore "$KEYSTORE_DIR" \
    --syncmode "full" \
    --http \
    --http.addr "localhost" \
    --http.port "8546" \
    --http.api "personal,eth,net,web3,miner,admin" \
    --http.vhosts "*" \
    --http.corsdomain "*" \
    --networkid "110110" \
    --ws \
    --ws.addr "localhost" \
    --ws.port "8547" \
    --port "30304" \
    --nat "any" \
    --mine \
    --miner.threads "1" \
    --miner.etherbase "0xD21602919e81e32A456195e9cE34215Af504535A" \
    --bootnodes "enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138" \
    --verbosity 5 \
    --maxpeers "25" \
    --cache "128" \
    --nodiscover \
    --nousb >> "$LOG_DIR/geth.log" 2>&1 &

# Save the PID
echo $! > "$DATA_DIR/geth.pid"

# Wait for RPC endpoint to become available
for i in {1..30}; do
    if curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
            http://localhost:8546 > /dev/null 2>&1; then
        echo "RPC endpoint is available" >> "$LOG_DIR/geth.log"
        break
    fi
    echo "Waiting for RPC endpoint (attempt $i/30)..." >> "$LOG_DIR/geth.log"
    sleep 2
done

# Check if process is still running
if ps -p $(cat "$DATA_DIR/geth.pid") > /dev/null; then
    echo "Geth process started successfully" >> "$LOG_DIR/geth.log"
    exit 0
else
    echo "Failed to start Geth process" >> "$LOG_DIR/geth.log"
    exit 1
fi 