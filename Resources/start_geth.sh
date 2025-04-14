#!/bin/bash

# Exit on error
set -e

# Get the app's Resources directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
GETH_PATH="$SCRIPT_DIR/geth/geth"
CONFIG_PATH="$SCRIPT_DIR/config"

# Create data directory if it doesn't exist
DATA_DIR="$HOME/.marscredit"
mkdir -p "$DATA_DIR/keystore"
mkdir -p "$DATA_DIR/ethash"

# Initialize blockchain if not already initialized
if [ ! -d "$DATA_DIR/geth/chaindata" ] || [ -z "$(ls -A "$DATA_DIR/geth/chaindata")" ]; then
    echo "Initializing blockchain with genesis block..."
    "$GETH_PATH" --datadir "$DATA_DIR" init "$CONFIG_PATH/genesis.json"
fi

# Start Geth with PoW mining
echo "Starting Geth 1.10.18 with PoW mining..."
"$GETH_PATH" --datadir "$DATA_DIR" \
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
    --maxpeers "50" \
    --cache "256" \
    --ethash.dagdir "$DATA_DIR/ethash" \
    --nousb 