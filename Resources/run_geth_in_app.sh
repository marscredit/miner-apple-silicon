#!/bin/bash
set -ex # Exit on error, print commands

# Log script start immediately to a temporary file to confirm execution
# This temporary log is just to be absolutely sure the script starts
INIT_LOG="$HOME/.marscredit/logs/wrapper_init.log"
echo "run_geth_in_app.sh started at $(date) (v3 - double_fork, no_pidfile_arg)" > "$INIT_LOG"
HOME_DIR_FOR_GETH="$HOME" # Capture HOME early, in case it changes in subshells
echo "HOME_DIR_FOR_GETH: $HOME_DIR_FOR_GETH" >> "$INIT_LOG"
echo "User: $(whoami)" >> "$INIT_LOG"
SCRIPT_PATH_DEBUG="${BASH_SOURCE[0]}"
echo "Script path: $SCRIPT_PATH_DEBUG" >> "$INIT_LOG"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
echo "SCRIPT_DIR: $SCRIPT_DIR" >> "$INIT_LOG"
echo "Attempting to write to main log next..." >> "$INIT_LOG"

# Main log file
LOG_FILE="$HOME_DIR_FOR_GETH/.marscredit/logs/geth.log"
echo "run_geth_in_app.sh: Attempting to clear/write main log file: $LOG_FILE at $(date)" > "$LOG_FILE"

# Kill any existing geth processes
echo "run_geth_in_app.sh: Killing existing geth processes..." >> "$LOG_FILE"
killall geth 2>/dev/null || true
echo "run_geth_in_app.sh: Sleep after killall" >> "$LOG_FILE"
sleep 1 # Reduced sleep after killall

# Set up directories
DATA_DIR="$HOME_DIR_FOR_GETH/.marscredit"
KEYSTORE_DIR="$DATA_DIR/keystore"
echo "run_geth_in_app.sh: DATA_DIR=$DATA_DIR, KEYSTORE_DIR=$KEYSTORE_DIR" >> "$LOG_FILE"

echo "run_geth_in_app.sh: Creating directories..." >> "$LOG_FILE"
mkdir -p "$DATA_DIR/logs" "$KEYSTORE_DIR" # Ensure logs dir exists for sure
echo "run_geth_in_app.sh: Directories created." >> "$LOG_FILE"

echo "run_geth_in_app.sh: (This line should be the Geth startup message in geth.log) Starting Geth node..." >> "$LOG_FILE"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
GETH_BINARY_PATH="$SCRIPT_DIR/geth/geth"
echo "run_geth_in_app.sh: SCRIPT_DIR=$SCRIPT_DIR" >> "$LOG_FILE"
echo "run_geth_in_app.sh: GETH_BINARY_PATH=$GETH_BINARY_PATH" >> "$LOG_FILE"

if [ ! -f "$GETH_BINARY_PATH" ]; then
    echo "run_geth_in_app.sh: FATAL ERROR - Geth binary not found at $GETH_BINARY_PATH" >> "$LOG_FILE"
    exit 1
fi
if [ ! -x "$GETH_BINARY_PATH" ]; then
    echo "run_geth_in_app.sh: FATAL ERROR - Geth binary not executable at $GETH_BINARY_PATH" >> "$LOG_FILE"
    exit 1
fi
echo "run_geth_in_app.sh: Geth binary found and is executable. Launching via double-fork..." >> "$LOG_FILE"

# Define Bootnodes
BOOTNODES="enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138"
echo "run_geth_in_app.sh: Using BOOTNODES: $BOOTNODES" >> "$LOG_FILE"

# Double fork to detach Geth completely
( ( nohup "$GETH_BINARY_PATH" \
    --datadir "$DATA_DIR" \
    --keystore "$KEYSTORE_DIR" \
    --syncmode "full" \
    --http --http.addr "localhost" --http.port 8546 \
    --http.api "personal,eth,net,web3,miner,admin,debug" \
    --http.vhosts "*" --http.corsdomain "*" \
    --networkid 110110 \
    --bootnodes "$BOOTNODES" \
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
    < /dev/null >> "$LOG_FILE" 2>&1 & ) & ) &

echo "run_geth_in_app.sh: Geth launch (double-fork) initiated." >> "$LOG_FILE"
echo "run_geth_in_app.sh: Sleeping 8 seconds for Geth to fully start before RPC check..." >> "$LOG_FILE"
sleep 8 # Give Geth ample time to start before the script starts its own checks

echo "run_geth_in_app.sh: Starting RPC check loop." >> "$LOG_FILE"
RPC_AVAILABLE=false
for i in {1..15}; do
    echo "run_geth_in_app.sh: RPC check attempt $i/15..." >> "$LOG_FILE"
    if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' http://localhost:8546 > /dev/null 2>&1; then
        echo "run_geth_in_app.sh: SUCCESS - RPC endpoint is available on attempt $i" >> "$LOG_FILE"
        RPC_AVAILABLE=true
        break
    fi
    echo "run_geth_in_app.sh: RPC endpoint not available on attempt $i, sleeping 2s..." >> "$LOG_FILE"
    sleep 2
done

if [ "$RPC_AVAILABLE" = true ]; then
    echo "run_geth_in_app.sh: RPC check loop finished successfully." >> "$LOG_FILE"
    echo "run_geth_in_app.sh: Exiting with status 0." >> "$LOG_FILE"
    exit 0
else
    echo "run_geth_in_app.sh: ERROR - RPC endpoint NOT available after all attempts." >> "$LOG_FILE"
    echo "run_geth_in_app.sh: Exiting with status 1 (RPC unavailable)." >> "$LOG_FILE"
    exit 1
fi 