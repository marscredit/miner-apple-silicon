# Mars Credit Miner for Apple Silicon

A native macOS application for mining Mars Credit (MARS) on Apple Silicon (arm64) Macs. This application provides a user-friendly interface for generating accounts and mining MARS coins using a custom fork of Ethereum v1.10.18.

## Features

- Native Apple Silicon (arm64) support for the main application
- Geth v1.10.18 running via Rosetta 2 (required for Ethereum PoW fork compatibility)
- Account generation with mnemonic seed backup
- Secure password storage in macOS keychain
- One-click mining start/stop
- Clean, modern SwiftUI interface
- Optimized performance settings for Apple Silicon

## Requirements

- macOS 12.0 or later
- Apple Silicon Mac (M1/M2/M3)
- Rosetta 2 (automatically installed if needed)
- Internet access for RPC sync
- Ports 8546 (HTTP/WS) and 30304 (P2P) must be open
- Xcode 14.0 or later (for building from source)

## Quick Test (Without Installation)

To quickly test the miner without full installation:

```bash
# Run the optimized Apple Silicon debug script
chmod +x debug_apple_silicon.sh
./debug_apple_silicon.sh
```

This script will:
- Start geth with optimized settings for Apple Silicon
- Initialize a new blockchain if needed
- Begin mining with appropriate parameters
- Display real-time status and debug information

## Installation

### Option 1: Use the pre-built DMG

1. Download the latest release DMG file
2. Mount the DMG file
3. Drag Mars Credit Miner to your Applications folder
4. Launch the application

The DMG file is located in the `build/` directory with the name `Mars-Credit-Miner-apple-silicon.dmg`.

### Option 2: Build from Source

1. Clone the repository:
```bash
git clone https://github.com/marscredit/miner-apple-silicon.git
cd miner-apple-silicon
```

2. Build the project:
```bash
swift build -c release
```

3. Run the application:
```bash
.build/release/MarsCredit
```

## Building the DMG Package

To create a distributable DMG package:

1. Build a simple DMG (recommended):
```bash
chmod +x build_simple_dmg.sh
./build_simple_dmg.sh
```

2. Build a more sophisticated DMG with background image (requires create-dmg):
```bash
chmod +x build_app_dmg.sh
./build_app_dmg.sh
```

Both scripts will:
- Build the Swift app
- Create the app bundle
- Update with optimized mining scripts
- Generate a DMG file in the `build/` directory

## Apple Silicon Optimization

This miner has been specially optimized for Apple Silicon:

- Reduced memory cache requirements (512MB)
- Limited peer connections to 25 (from 50)
- Custom Genesis block for faster syncing
- RPC-based mining initiation for better stability
- Resource usage tuning for optimal performance on M1/M2/M3 chips

## Troubleshooting

If you encounter any issues with the application, please check the [Troubleshooting Guide](./README.issues.md) for solutions to common problems.

### Common Issues

1. **Application freezes when starting mining**: This is usually caused by resource limitations. Try using the `debug_apple_silicon.sh` script which has optimized settings.

2. **Mining doesn't start**: Check the logs in `~/.marscredit/logs/` to see if there are any errors.

3. **Application crashes on startup**: Make sure you have Rosetta 2 installed on your system. This can be installed by running:
   ```bash
   softwareupdate --install-rosetta --agree-to-license
   ```

## Debugging Tools

The application comes with several debugging scripts:

- `debug_apple_silicon.sh`: Optimized for Apple Silicon with minimal resource usage
- `debug_app.sh`: Standard debugging script with more detailed logging
- `debug_minimal.sh`: Minimal debugging script for testing basic functionality
- `test_mining_workflow.sh`: Tests the complete mining workflow
- `test_account_workflow.sh`: Tests account creation and management

## Status Checking

You can check the status of your mining operation using the JSON-RPC API:

```bash
# Check if mining is active
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
    http://localhost:8546

# Check current hashrate
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_hashrate","params":[],"id":1}' \
    http://localhost:8546

# Check balance
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getBalance","params":["YOUR_ADDRESS", "latest"],"id":1}' \
    http://localhost:8546
```

## Technical Details

### Mining Configuration

- Single mining thread to prevent resource overuse
- 512MB cache optimized for Apple Silicon
- Mining rewards sent to configured address
- Genesis block with minimal difficulty for faster start

### Data Storage

- User data stored in ~/.marscredit
- Separate directories for keystore, chaindata, and logs
- Comprehensive logging for debugging

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
