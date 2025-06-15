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

# Initialize blockchain with our genesis if needed
if [ ! -d "$DATA_DIR/geth/chaindata" ] || [ -z "$(ls -A "$DATA_DIR/geth/chaindata")" ]; then
    echo "Initializing blockchain with genesis block..."
    ./Resources/geth/geth --datadir "$DATA_DIR" init ./Resources/config/genesis.json
    if [ $? -ne 0 ]; then
        echo "Genesis initialization failed"
        exit 1
    fi
fi

# Create a new account if none exists
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

# Start geth in the background with our network configuration
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
    --miner.etherbase "$MINING_ADDRESS" \
    --bootnodes "enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138" \
    --verbosity 5 \
    --maxpeers "50" \
    --cache "4096" \
    --rpc.allow-unprotected-txs \
    --nousb \
    --gcmode "archive" >> "$LOG_DIR/geth.log" 2>&1 &

# Save the PID
echo $! > "$DATA_DIR/geth.pid"

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

# Check if process is still running and verify mining status
if ps -p $(cat "$DATA_DIR/geth.pid") > /dev/null; then
    echo "Geth process started successfully"
    
    # Check mining status
    sleep 5
    MINING_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
        http://localhost:8546)
    
    if echo "$MINING_STATUS" | grep -q "true"; then
        echo "Mining started successfully"
        echo "Mining address: $MINING_ADDRESS"
        
        # Get initial hashrate
        HASHRATE=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_hashrate","params":[],"id":1}' \
            http://localhost:8546)
        
        echo "Current hashrate: $HASHRATE"
        echo "Check logs at: $LOG_DIR/geth.log"
    else
        echo "Mining not active, starting mining..."
        
        # Explicitly start mining using RPC
        START_MINING=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
            http://localhost:8546)
        
        echo "Mining start command response: $START_MINING"
        
        # Set coinbase address
        SET_ETHERBASE=$(curl -s -X POST -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"miner_setEtherbase\",\"params\":[\"$MINING_ADDRESS\"],\"id\":1}" \
            http://localhost:8546)
        
        echo "Set etherbase response: $SET_ETHERBASE"
        
        # Check mining status again
        sleep 5
        MINING_STATUS=$(curl -s -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
            http://localhost:8546)
        
        if echo "$MINING_STATUS" | grep -q "true"; then
            echo "Mining started successfully"
            echo "Mining address: $MINING_ADDRESS"
            
            # Get initial hashrate
            HASHRATE=$(curl -s -X POST -H "Content-Type: application/json" \
                --data '{"jsonrpc":"2.0","method":"eth_hashrate","params":[],"id":1}' \
                http://localhost:8546)
            
            echo "Current hashrate: $HASHRATE"
            echo "Check logs at: $LOG_DIR/geth.log"
        else
            echo "Mining failed to start after explicit command"
            tail -n 20 "$LOG_DIR/geth.log"
        fi
    fi
else
    echo "Failed to start Geth process"
    tail -n 30 "$LOG_DIR/geth.log"
fi 