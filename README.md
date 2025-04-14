# Mars Credit Miner for Apple Silicon

A native macOS application for mining Mars Credit (MARS) on Apple Silicon Macs. This application provides a user-friendly interface for generating accounts and mining MARS coins.

## Features

- Native Apple Silicon support
- Account generation with mnemonic seed backup
- Secure password storage in macOS keychain
- One-click mining start/stop
- Clean, modern user interface

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
- Direct Process execution fallback if wrapper is unavailable

### Network Configuration
- HTTP RPC on port 8546
- WebSocket interface on port 8547
- P2P port 30304
- Configured bootnodes for peer discovery
- Full node synchronization mode
- Maximum 50 peers

### Mining Settings
- Single mining thread to prevent resource overuse
- Reduced cache (512MB) for better stability
- Mining rewards sent to configurable address
- DAG generation progress tracking in UI

### Data Storage
- User data stored in ~/.marscredit
- Separate directories for keystore, chaindata, and logs
- Comprehensive logging for debugging

### Error Handling
- Process monitoring for crashes
- Automatic chaindata reinitialization if needed
- Log file monitoring with error detection

## Requirements

- macOS 12.0 or later
- Apple Silicon Mac (M1/M2/M3)
- Xcode 14.0 or later (for building from source)

## Installation

1. Download the latest release from the Releases page
2. Mount the DMG file
3. Drag Mars Credit Miner to your Applications folder
4. Launch the application

## Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/miner-apple-silicon.git
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

## Importing Your Wallet

The generated mnemonic seed can be used to import your wallet into MetaMask or other compatible wallets:

1. Open MetaMask
2. Click "Import Account"
3. Select "Import using seed phrase"
4. Enter the 12-word mnemonic seed
5. Add the Mars Credit network details:
   - Network Name: Mars Credit
   - RPC URL: [Your RPC URL]
   - Chain ID: [Your Chain ID]
   - Symbol: MARS

## Security Notes

- Store your mnemonic seed phrase securely - it's the only way to recover your funds
- Never share your mnemonic seed or password with anyone
- The application stores your password securely in the macOS keychain
- All mining rewards are sent to your generated address automatically

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.