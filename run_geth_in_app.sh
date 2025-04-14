#!/bin/bash

# This is a simple wrapper that will run Geth in a predictable way
# The app will call this script instead of trying to manage Geth directly

# Log start time
echo "Starting Geth wrapper at $(date)" > ~/geth_wrapper.log

# Define paths
GETH_PATH="$(pwd)/Resources/geth/geth"
CONFIG_PATH="$(pwd)/Resources/config"
DATA_DIR="$HOME/.marscredit"

# Create data directories 
mkdir -p "$DATA_DIR/keystore"
mkdir -p "$DATA_DIR/logs"
mkdir -p "$DATA_DIR/ethash"

# Initialize blockchain if not already initialized
if [ ! -d "$DATA_DIR/geth/chaindata" ] || [ -z "$(ls -A "$DATA_DIR/geth/chaindata")" ]; then
    echo "Initializing blockchain with genesis block..." >> ~/geth_wrapper.log
    "$GETH_PATH" --datadir "$DATA_DIR" init "$CONFIG_PATH/genesis.json"
fi

# Make sure we're not running multiple instances
killall geth 2>/dev/null || true
sleep 1

# Use minimal settings to reduce memory usage
echo "Running: $GETH_PATH with minimal settings for Apple Silicon" >> ~/geth_wrapper.log

# Pre-generate the DAG in a separate process with minimal settings
echo "Pre-generating DAG file to avoid freezing the app..." >> ~/geth_wrapper.log
"$GETH_PATH" --datadir "$DATA_DIR" --mine --miner.threads 1 --ethash.dagdir "$DATA_DIR/ethash" --nodiscover --maxpeers 0 --cache 128 --verbosity 3 >> "$DATA_DIR/logs/dag_generation.log" 2>&1 &
DAG_PID=$!

# Wait for 3 seconds to let DAG generation start
sleep 3

# Kill the DAG generation process - we only needed to start it
kill $DAG_PID 2>/dev/null || true
sleep 1

# Run the actual Geth process with minimal settings, completely detached
nohup "$GETH_PATH" --datadir "$DATA_DIR" \
    --keystore "$DATA_DIR/keystore" \
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
    --verbosity "3" \
    --maxpeers "25" \
    --cache "128" \
    --ethash.dagdir "$DATA_DIR/ethash" \
    --nodiscover \
    --nousb > "$DATA_DIR/logs/geth_output.log" 2>&1 </dev/null &

# Save the PID of the Geth process
GETH_PID=$!
echo $GETH_PID > "$DATA_DIR/geth.pid"

# Log the PID of the Geth process
echo "Geth process started with PID: $GETH_PID" >> ~/geth_wrapper.log
echo "Command complete. Geth is now running completely detached from the app." >> ~/geth_wrapper.log

# Exit the wrapper script - the app should continue running
exit 0 