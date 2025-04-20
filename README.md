# Mars Credit Miner for Apple Silicon

A native macOS application for mining Mars Credit (MARS) on Apple Silicon (arm64) Macs. This application provides a user-friendly interface for generating accounts and mining MARS coins using a custom fork of Ethereum v1.10.18.

## Features

- Native Apple Silicon (arm64) support for the main application
- Geth v1.10.18 running via Rosetta 2 (required for Ethereum PoW fork compatibility)
- Account generation with mnemonic seed backup
- Secure password storage in macOS keychain
- One-click mining start/stop
- Clean, modern SwiftUI interface

## Requirements

- macOS 12.0 or later
- Apple Silicon Mac (M1/M2/M3)
- Rosetta 2 (automatically installed if needed)
- Internet access for RPC sync
- Ports 8546 (HTTP/WS) and 30304 (P2P) must be open
- Xcode 14.0 or later (for building from source)

## Technical Overview

The Mars Credit Miner implements an Ethereum mining node using Geth 1.10.18 with the following configuration:

### Blockchain Configuration
- Custom private blockchain with chainID 110110
- Proof-of-Work (PoW) with Ethash algorithm
- Genesis block with low initial difficulty (0x400)
- Block gas limit of 0x1c9c380

### Node Execution
- Wrapper script (`run_geth_in_app.sh`) manages Geth execution
- Geth binary (v1.10.18) is bundled with the application
- Native arm64 support for optimal performance on Apple Silicon

### Network Configuration
- HTTP/WS RPC on port 8546
- P2P port 30304
- RPC URL: https://rpc.marscredit.xyz:443
- Full node synchronization mode
- Maximum 50 peers
- Configured bootnodes:
  ```
  enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590
  enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254
  enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270
  enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138
  ```

### Mining Settings
- Single mining thread to prevent resource overuse
- 2GB cache for optimal performance
- Mining rewards sent to configurable address
- DAG directory: /data/.ethash
- DAG generation progress tracking in UI

### Data Storage
- User data stored in ~/.marscredit
- Separate directories for keystore, chaindata, and logs
- Comprehensive logging for debugging

### Error Handling
- Process monitoring for crashes
- Automatic chaindata reinitialization if needed
- Log file monitoring with error detection

## Installation

1. Download the latest release from the Releases page
2. Mount the DMG file
3. Drag Mars Credit Miner to your Applications folder
4. Launch the application

## Building from Source

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

## Usage

1. Launch the application
2. Enter a secure password
3. Click "Generate Account" to create a new mining account
4. Save the displayed mnemonic seed phrase securely - this is required to access your funds!
5. Click "Start Mining" to begin mining MARS coins

## Account Management

- New accounts are automatically generated with a 12-word mnemonic backup
- Private keys are securely stored in /app/keystore
- Mnemonic phrases can be viewed on-demand through the UI
- Password is securely stored in macOS Keychain

## Security Notes

- Store your mnemonic seed phrase securely - it's the only way to recover your funds
- Never share your mnemonic seed or password with anyone
- The application stores your password securely in the macOS keychain
- Private keys are encrypted at rest
- All mining rewards are sent to your generated address automatically

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.