# Mars Credit Miner - Fixed for Apple Silicon

This repository contains fixed versions of the Mars Credit Miner application optimized for Apple Silicon Macs. The original application was freezing during mining operations due to several resource utilization issues.

## Issues Fixed

1. **DAG Generation Freezing**: The app would freeze when generating the DAG (Directed Acyclic Graph) due to excessive resource usage.
2. **Connection Issues**: The UI would fail to connect to the mining node running on localhost:8546.
3. **Resource Consumption**: Optimized cache usage and peer connections for better performance on Apple Silicon.
4. **Initialization Problems**: Fixed issues with genesis block and blockchain initialization.

## Optimizations Applied

- **Reduced Cache**: Lowered from 2048MB to 512MB
- **Limited Peer Connections**: Reduced from 50 to 25
- **Improved Network Connectivity**: Removed node discovery flags causing network issues
- **RPC Mining**: Using RPC API for mining rather than startup flags
- **Proper Genesis Block**: Ensured correct initialization of the blockchain
- **Binary Placement**: Proper placement of the geth binary where the app expects it
- **Automatic Setup**: Added helper scripts to set up the environment automatically

## Usage Instructions

### Option 1: Install from DMG

1. Download the "Mars Credit Miner - Fixed.dmg" file
2. Open the DMG file and drag the app to your Applications folder
3. Right-click on the app and select "Open" (you may need to do this twice on first launch due to macOS security)
4. The app will automatically set up the environment and start the mining node
5. Click "Start Mining" in the app - when working correctly, you should see the Mars planet with a spinning moon animation

### Option 2: Run the Helper Script Manually

If you already have the app installed and just want to fix it:

1. Run the `app_helper.sh` script from a terminal:
   ```
   ./app_helper.sh
   ```
2. This will set up the environment, place the geth binary in the correct location, and create necessary configuration files
3. Open the app and click "Start Mining"

## Troubleshooting

If you encounter issues:

1. **App Not Finding Geth Binary**:
   - Run the app_helper.sh script again
   - Check the log files in ~/.marscredit/logs/

2. **Connection Issues**:
   - Ensure nothing else is using port 8546
   - Check if the geth process is running with: `ps aux | grep geth`
   - Look for error messages in the log: `cat ~/.marscredit/logs/geth.log`

3. **Performance Issues**:
   - The optimizations are designed for Apple Silicon M1/M2 machines
   - Further reduce cache (`--cache` flag) if your machine has limited memory

## Rebuilding the App

To rebuild the app with all fixes:

1. Ensure you have Xcode and developer tools installed
2. Run the build script:
   ```
   ./build.sh
   ```
3. This will create a new app bundle and DMG file

## Technical Details

The fixes focus on optimizing resource usage during mining:

1. The DAG generation is particularly resource-intensive. By lowering cache values and limiting other resource usage, we ensure the system doesn't freeze.
2. Proper placement of binaries and configuration files ensures the UI can communicate with the mining node.
3. The helper script provides automatic setup and error recovery.

---

For issues or questions, please open an issue on the repository. 