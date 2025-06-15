# Mars Credit Miner - Troubleshooting Guide

This document contains known issues and their solutions for the Mars Credit Miner application.

## Main Issues Solved

### App Freezing (Spinning Rainbow Wheel)

**Issue**: The application freezes when starting mining, showing a spinning rainbow wheel, requiring a force quit.

**Cause**: Several factors contributed to this issue:
1. DAG file generation is resource-intensive on Apple Silicon
2. Default high cache values (2048MB) were too resource-intensive
3. Too many peers attempted to connect (maxpeers=50)
4. The blockchain was attempting full sync mode with many peers

**Solution**: 
1. Lower the cache size (512MB instead of 2048MB)
2. Reduce the maximum number of peers (10 instead of 50)
3. Ensure genesis block is properly initialized
4. Start mining via RPC after the node is running, not at startup
5. Use simple file redirection (`>`) instead of append (`>>`) for logs for better performance

The implementation can be found in the updated `run_geth_in_app.sh` script.

### Mining Not Starting

**Issue**: Geth process starts but mining doesn't begin.

**Cause**: When using the `--mine` flag with Geth, sometimes mining doesn't actually start properly, especially on Apple Silicon with Rosetta 2.

**Solution**: Start Geth without the `--mine` flag and instead use the JSON-RPC API to start mining after the node is ready:
```bash
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}' \
    http://localhost:8546
```

### Invalid Flag Error

**Issue**: Error message in logs: `flag provided but not defined: -ethash.dagdir`

**Cause**: The flag was being provided with one dash (`-`) instead of two dashes (`--`).

**Solution**: Ensure all flags are properly formatted with two dashes before the flag name: `--ethash.dagdir`.

### Light Sync Mode Doesn't Support Mining

**Issue**: Error when attempting to start mining: `the method miner_start does not exist/is not available`

**Cause**: The light sync mode in Geth doesn't support mining operations.

**Solution**: Always use `--syncmode "full"` when mining is required.

## Tips for Running the App

1. Use the `debug_apple_silicon.sh` script for testing on Apple Silicon Macs.

2. Check the logs in `~/.marscredit/logs/` if you encounter issues.

3. Monitor mining status via the JSON-RPC API:
   ```bash
   # Check if mining is active
   curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' \
       http://localhost:8546

   # Check current hashrate
   curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_hashrate","params":[],"id":1}' \
       http://localhost:8546
   ```

4. If the app freezes, try running with reduced resource settings:
   - Lower cache (512MB)
   - Fewer peers (10 max)
   - No discovery mode

## Configuration Improvements

The following configuration changes were made to improve stability:

1. Changed HTTP and WebSocket interfaces from binding to all interfaces (`0.0.0.0`) to localhost only (`localhost`) for improved security.

2. Added explicit wait for RPC endpoint availability before attempting to start mining.

3. Removed the `--mine` flag from Geth startup in favor of starting mining via RPC after node initialization.

4. Added proper genesis initialization to ensure the blockchain starts correctly.

5. Reduced resource usage (memory cache, peer connections) for better compatibility with Apple Silicon.

## Future Improvements

Potential improvements to consider:

1. Create a native arm64 build of Geth to avoid using Rosetta 2.

2. Implement more efficient mining methods specific to Apple Silicon.

3. Create a dedicated "low resource mode" option in the UI for older Macs.

4. Add better error reporting and recovery mechanisms in the UI.
