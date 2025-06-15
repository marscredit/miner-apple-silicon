#!/usr/bin/swift

import Foundation

// Path to our optimized script
let sourceScriptPath = "run_geth_in_app.sh"
let debugAppleSiliconPath = "debug_apple_silicon.sh"

// Function to check if a file exists
func fileExists(at path: String) -> Bool {
    return FileManager.default.fileExists(atPath: path)
}

// Function to read file contents
func readFile(at path: String) -> String? {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        print("Error reading file at \(path): \(error)")
        return nil
    }
}

// Function to write file contents
func writeFile(contents: String, to path: String) -> Bool {
    do {
        try contents.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        return true
    } catch {
        print("Error writing to file at \(path): \(error)")
        return false
    }
}

// Function to make a file executable
func makeExecutable(path: String) -> Bool {
    do {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return true
    } catch {
        print("Error making file executable at \(path): \(error)")
        return false
    }
}

// Check if sources exist
guard fileExists(at: sourceScriptPath) else {
    print("Error: Source script not found at \(sourceScriptPath)")
    exit(1)
}

guard fileExists(at: debugAppleSiliconPath) else {
    print("Error: Debug Apple Silicon script not found at \(debugAppleSiliconPath)")
    exit(1)
}

// Copy the optimized script to app bundle Resources directory
let appBundlePath = "Mars Credit Miner.app"

// Check if the app bundle exists
if fileExists(at: appBundlePath) {
    let appResourcesPath = "\(appBundlePath)/Contents/Resources"
    
    // Create Resources directory if it doesn't exist
    if !fileExists(at: appResourcesPath) {
        do {
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: appResourcesPath), withIntermediateDirectories: true)
        } catch {
            print("Error creating Resources directory: \(error)")
            exit(1)
        }
    }
    
    // Copy the optimized run_geth_in_app.sh to the app's Resources directory
    if let scriptContents = readFile(at: sourceScriptPath) {
        let targetPath = "\(appResourcesPath)/run_geth_in_app.sh"
        if writeFile(contents: scriptContents, to: targetPath) {
            if makeExecutable(path: targetPath) {
                print("✅ Successfully installed optimized mining script to app bundle")
            }
        }
    }
    
    // Copy debug_apple_silicon.sh to the app's Resources directory
    if let debugScriptContents = readFile(at: debugAppleSiliconPath) {
        let debugTargetPath = "\(appResourcesPath)/debug_apple_silicon.sh"
        if writeFile(contents: debugScriptContents, to: debugTargetPath) {
            if makeExecutable(path: debugTargetPath) {
                print("✅ Successfully installed debug Apple Silicon script to app bundle")
            }
        }
    }
    
    print("✨ App has been updated with optimized mining scripts for Apple Silicon")
} else {
    print("⚠️ App bundle not found at \(appBundlePath)")
    print("Installing scripts to current directory only...")
    
    // Make sure the scripts in the current directory are executable
    if makeExecutable(path: sourceScriptPath) && makeExecutable(path: debugAppleSiliconPath) {
        print("✅ Scripts are now executable")
        print("📋 Run './debug_apple_silicon.sh' to test mining with optimized settings")
    }
}

// Create a README for these changes
let readmeContent = """
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
"""

// Write the README
if writeFile(contents: readmeContent, to: "README.apple_silicon_optimization.md") {
    print("📝 Created documentation for Apple Silicon optimizations")
} 