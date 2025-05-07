#!/bin/bash
set -x

# Get the directory the script resides in
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Construct path to Geth binary relative to the script's directory
GETH_BINARY_PATH="$SCRIPT_DIR/Resources/geth/geth"

# Log start time
echo "Starting Geth wrapper at $(date). Script dir: $SCRIPT_DIR. Geth path: $GETH_BINARY_PATH." > ~/geth_wrapper.log

# Check if Geth binary exists
if [ ! -f "$GETH_BINARY_PATH" ]; then
  echo "Error: Geth binary not found at $GETH_BINARY_PATH" >> ~/geth_wrapper.log
  # Append to main log too for visibility
  echo "Error: Geth binary not found at $GETH_BINARY_PATH" >> "/Users/jeremycrane/.marscredit/logs/geth.log"
  exit 1
fi

# Kill any existing geth processes
# Be careful not to kill the script itself if geth is somehow named bash
pgrep -f "$GETH_BINARY_PATH" | xargs kill -9 2>/dev/null || true
sleep 2

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_DIR="$DATA_DIR/logs"
ETHASH_DIR="$DATA_DIR/ethash"

mkdir -p "$DATA_DIR" "$KEYSTORE_DIR" "$LOG_DIR" "$ETHASH_DIR"

# Clear the log file
echo "Starting Geth node at $(date)" > "$LOG_DIR/geth.log"

# Remove any existing DAG files to ensure clean start
echo "Removing any existing DAG files..." >> "$LOG_DIR/geth.log"
rm -rf "$ETHASH_DIR"/*
mkdir -p "$ETHASH_DIR"

# Create a minimal genesis file if it doesn't exist
GENESIS_DIR="$DATA_DIR/genesis"
GENESIS_FILE="$GENESIS_DIR/genesis.json"
mkdir -p "$GENESIS_DIR"

if [ ! -f "$GENESIS_FILE" ]; then
    echo "Creating minimal genesis file..." >> "$LOG_DIR/geth.log"
    cat > "$GENESIS_FILE" << EOF
{
  "config": {
    "chainId": 110110,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "ethash": {}
  },
  "difficulty": "0x400",
  "gasLimit": "0x8000000",
  "alloc": {}
}
EOF
fi

# Initialize the blockchain if needed
if [ ! -d "$DATA_DIR/geth/chaindata" ] || [ -z "$(ls -A "$DATA_DIR/geth/chaindata")" ]; then
    echo "Initializing blockchain with genesis block..." >> "$LOG_DIR/geth.log"
    "$GETH_BINARY_PATH" --datadir "$DATA_DIR" init "$GENESIS_FILE"
    if [ $? -ne 0 ]; then
        echo "Genesis initialization failed" >> "$LOG_DIR/geth.log"
        exit 1
    fi
fi

echo "Starting main Geth process using $GETH_BINARY_PATH..." >> "$LOG_DIR/geth.log"

# Set up bootnode list for better connectivity
BOOTNODES="enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138"

# Start geth in the background using the absolute path with optimized settings
nohup "$GETH_BINARY_PATH" \
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
    --ws.port "8546" \
    --port "30304" \
    --nat "any" \
    --maxpeers "25" \
    --cache "512" \
    --miner.etherbase "0xD21602919e81e32A456195e9cE34215Af504535A" \
    --bootnodes "$BOOTNODES" \
    --nousb > "$LOG_DIR/geth.log" 2>&1 &

GETH_PID=$!
echo $GETH_PID > "$DATA_DIR/geth.pid"

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

# Explicitly start mining using RPC
START_MINING=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
    http://localhost:8546)

echo "Mining start command response: $START_MINING" >> "$LOG_DIR/geth.log"

# Check if mining started successfully
sleep 3
MINING_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
    http://localhost:8546)

echo "Mining status: $MINING_STATUS" >> "$LOG_DIR/geth.log"

# Check peer connections
PEER_COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8546)

echo "Peer count: $PEER_COUNT" >> "$LOG_DIR/geth.log"

exit 0 # Assume success if Geth command launched without immediate error 