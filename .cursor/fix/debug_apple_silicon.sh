#!/bin/bash

echo "===== Mars Credit Miner - Apple Silicon Debug ====="
echo "Cleaning up any previous instances..."

# Kill any existing geth processes
killall geth 2>/dev/null || true
sleep 2

# Set up directories
DATA_DIR="$HOME/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
LOG_DIR="$DATA_DIR/logs"
ETHASH_DIR="$DATA_DIR/ethash"

mkdir -p "$DATA_DIR" "$KEYSTORE_DIR" "$LOG_DIR" "$ETHASH_DIR"

# Remove any existing DAG files
echo "Removing any existing DAG files..."
rm -rf "$ETHASH_DIR"/*
mkdir -p "$ETHASH_DIR"

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

# Create a minimal genesis file if it doesn't exist
GENESIS_DIR="$DATA_DIR/genesis"
GENESIS_FILE="$GENESIS_DIR/genesis.json"
mkdir -p "$GENESIS_DIR"

if [ ! -f "$GENESIS_FILE" ]; then
    echo "Creating minimal genesis file..."
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
  "alloc": {
    "${MINING_ADDRESS#0x}": { "balance": "0x1000000000000000000" }
  }
}
EOF
fi

# Initialize the blockchain if needed
if [ ! -d "$DATA_DIR/geth/chaindata" ] || [ -z "$(ls -A "$DATA_DIR/geth/chaindata")" ]; then
    echo "Initializing blockchain with genesis block..."
    ./Resources/geth/geth --datadir "$DATA_DIR" init "$GENESIS_FILE"
    if [ $? -ne 0 ]; then
        echo "Genesis initialization failed"
        exit 1
    fi
fi

echo "Starting geth with settings optimized for Apple Silicon..."

# Set up bootnode list for better connectivity
BOOTNODES="enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138"

# Start geth with network-enabled settings
nohup ./Resources/geth/geth \
    --datadir "$DATA_DIR" \
    --keystore "$KEYSTORE_DIR" \
    --syncmode "full" \
    --http \
    --http.addr "localhost" \
    --http.port "8546" \
    --http.api "personal,eth,net,web3,miner,admin" \
    --http.corsdomain "*" \
    --http.vhosts "*" \
    --networkid "110110" \
    --port "30304" \
    --miner.etherbase "$MINING_ADDRESS" \
    --cache "512" \
    --maxpeers 25 \
    --bootnodes "$BOOTNODES" \
    --nat "any" \
    --nousb \
    --rpc.allow-unprotected-txs \
    --ws \
    --ws.addr "localhost" \
    --ws.port "8546" \
    --ws.origins "*" \
    --ws.api "personal,eth,net,web3,miner,admin" \
    --verbosity 3 > "$LOG_DIR/geth.log" 2>&1 &

# Save the PID
GETH_PID=$!
echo $GETH_PID > "$DATA_DIR/geth.pid"

echo "Geth started with PID: $GETH_PID"
echo "Waiting for RPC endpoint..."

# Wait for RPC endpoint to become available
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

# Check if the process is still running
if ps -p $GETH_PID > /dev/null; then
    echo "Geth is running. Starting mining..."
    
    # Try to start mining
    curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
        http://localhost:8546
    
    echo "Mining command sent. Checking status..."
    sleep 3
    
    # Check mining status
    MINING_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
        http://localhost:8546)
    
    echo "Mining status: $MINING_STATUS"
    
    # Check peer count
    PEER_COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        http://localhost:8546)
    
    echo "Connected peers: $PEER_COUNT"
    
    # Show helpful information
    echo ""
    echo "==== Debugging Information ===="
    echo "Log file: $LOG_DIR/geth.log"
    echo "Mining address: $MINING_ADDRESS"
    echo "Process ID: $GETH_PID"
    echo ""
    echo "To check logs, run: tail -f $LOG_DIR/geth.log"
    echo "To check mining status, run: curl -s -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_mining\",\"params\":[],\"id\":1}' http://localhost:8546"
    echo "To check peer count, run: curl -s -X POST -H \"Content-Type: application/json\" --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' http://localhost:8546"
    echo "To stop geth, run: kill $GETH_PID"
else
    echo "Geth process failed to start or terminated prematurely."
    echo "Check logs: $LOG_DIR/geth.log"
    tail -n 20 "$LOG_DIR/geth.log"
fi 