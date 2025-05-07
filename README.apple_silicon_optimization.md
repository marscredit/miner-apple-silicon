# Mars Credit Miner - Apple Silicon Optimization

The following optimizations have been made to improve performance on Apple Silicon:

1. **Resource Usage Optimizations**
   - Reduced cache from 2048MB to 512MB
   - Limited peer connections to 25 (from 50)
   - Removed node discovery flag to enable proper network connectivity

2. **Mining Optimizations**
   - Pre-generates the DAG file to prevent UI freezing
   - Uses RPC API to start mining rather than startup flags
   - Properly initializes genesis block for quicker startup

3. **Network Optimizations**
   - Binds services to localhost for improved security
   - Uses proper bootnodes for network connectivity
   - Reduces verbosity for improved performance

## Testing
To test mining with the optimized settings, run:
```
./debug_apple_silicon.sh
```

## Usage
The optimized script has been installed in the app bundle and will be used automatically.