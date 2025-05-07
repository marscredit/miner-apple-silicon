import SwiftUI
import CoreText
import Foundation

@main
struct MarsCreditApp: App {
    @StateObject private var logManager = LogManager.shared
    @StateObject private var miningService = MiningService()
    
    init() {
        LogManager.shared.clear() // Clear any old logs
        LogManager.shared.log("Starting Mars Credit Miner...", type: .info)
        MiningService.shared = miningService // Set the shared instance
        setupGethBinary()
        setupApp()
        
        // Run the app_helper.sh script to ensure proper environment setup
        runAppHelper()
    }
    
    // Helper method to run the app_helper.sh script
    private func runAppHelper() {
        // First try to find the script in the app bundle's Resources directory
        var appHelperPath: String?
        
        if let resourcesPath = Bundle.main.resourceURL?.path {
            let scriptPath = resourcesPath + "/app_helper.sh"
            if FileManager.default.fileExists(atPath: scriptPath) {
                appHelperPath = scriptPath
                LogManager.shared.log("Found app_helper.sh in resources: \(scriptPath)", type: .success)
            }
        }
        
        // If not found in the bundle, check the current directory
        if appHelperPath == nil {
            let currentPath = FileManager.default.currentDirectoryPath + "/Resources/app_helper.sh"
            if FileManager.default.fileExists(atPath: currentPath) {
                appHelperPath = currentPath
                LogManager.shared.log("Found app_helper.sh in current path: \(currentPath)", type: .success)
            }
        }
        
        // If we found a script, execute it
        if let scriptPath = appHelperPath {
            LogManager.shared.log("Running app_helper.sh to ensure proper environment setup...", type: .info)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                
                // Read output in background
                DispatchQueue.global(qos: .background).async {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        // Log in chunks to avoid overwhelming the log
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            if !line.isEmpty {
                                DispatchQueue.main.async {
                                    LogManager.shared.log("Helper: \(line)", type: .debug)
                                }
                            }
                        }
                    }
                }
                
                LogManager.shared.log("App helper script is running in the background", type: .success)
            } catch {
                LogManager.shared.log("Failed to run app_helper.sh: \(error.localizedDescription)", type: .error)
            }
        } else {
            LogManager.shared.log("app_helper.sh not found, skipping environment setup", type: .warning)
        }
    }
    
    private func setupGethBinary() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let marscreditDir = homeDir.appendingPathComponent(".marscredit")
        let gethBinaryPath = marscreditDir.appendingPathComponent("geth-binary")
        
        LogManager.shared.log("Setting up geth environment...", type: .info)
        
        // Create marscredit directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: marscreditDir, withIntermediateDirectories: true)
            LogManager.shared.log("Created marscredit directory at \(marscreditDir.path)", type: .success)
            
            // Check if Go is installed
            let goVersionProcess = Process()
            goVersionProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            goVersionProcess.arguments = ["go"]
            
            let pipe = Pipe()
            goVersionProcess.standardOutput = pipe
            goVersionProcess.standardError = pipe
            
            var goInstalled = false
            var goPath = "/usr/local/go/bin/go" // Default path
            
            do {
                try goVersionProcess.run()
                goVersionProcess.waitUntilExit()
                
                if goVersionProcess.terminationStatus == 0 {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !output.isEmpty {
                        goPath = output
                        goInstalled = true
                        LogManager.shared.log("Go is installed at: \(goPath)", type: .success)
                    }
                }
            } catch {
                LogManager.shared.log("Could not determine Go installation: \(error.localizedDescription)", type: .warning)
            }
            
            // If binary doesn't exist, we need to build it or try pre-compiled binary
            if !fileManager.fileExists(atPath: gethBinaryPath.path) {
                // Check if we need to verify or download a precompiled binary first
                let precompiledPath = Bundle.module.url(forResource: "geth-darwin-arm64", withExtension: nil)
                
                if let precompiledPath = precompiledPath {
                    // We have a precompiled binary, try to use it
                    LogManager.shared.log("Found precompiled geth binary, installing...", type: .info)
                    do {
                        try fileManager.copyItem(at: precompiledPath, to: gethBinaryPath)
                        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethBinaryPath.path)
                        LogManager.shared.log("Successfully installed precompiled geth binary", type: .success)
                    } catch {
                        LogManager.shared.log("Failed to copy precompiled binary: \(error.localizedDescription)", type: .error)
                        // Fall back to building from source
                    }
                }
                
                // If we still don't have the binary and Go is installed, build it
                if !fileManager.fileExists(atPath: gethBinaryPath.path) && goInstalled {
                    LogManager.shared.log("Building geth binary for Apple Silicon...", type: .info)
                    
                    // Create a temporary build directory
                    let buildDir = marscreditDir.appendingPathComponent("build")
                    if fileManager.fileExists(atPath: buildDir.path) {
                        try fileManager.removeItem(at: buildDir)
                    }
                    try fileManager.createDirectory(at: buildDir, withIntermediateDirectories: true)
                    
                    // Write the go code for our minimal geth implementation
                    let gethSource = """
                    package main

                    import (
                        "github.com/ethereum/go-ethereum/cmd/geth"
                    )

                    func main() {
                        geth.Main()
                    }
                    """
                    
                    let goModSource = """
                    module marscredit

                    go 1.21

                    require github.com/ethereum/go-ethereum v1.13.14
                    """
                    
                    try gethSource.write(to: buildDir.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)
                    try goModSource.write(to: buildDir.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
                    
                    // Build the binary using go build
                    let buildProcess = Process()
                    buildProcess.currentDirectoryURL = buildDir
                    buildProcess.executableURL = URL(fileURLWithPath: goPath)
                    buildProcess.environment = ProcessInfo.processInfo.environment
                    buildProcess.environment?["GOARCH"] = "arm64"
                    buildProcess.environment?["GOOS"] = "darwin"
                    // Pass additional environment variables required for CGO
                    buildProcess.environment?["CGO_ENABLED"] = "1"
                    buildProcess.arguments = ["build", "-o", gethBinaryPath.path]
                    
                    let buildPipe = Pipe()
                    buildProcess.standardOutput = buildPipe
                    buildProcess.standardError = buildPipe
                    
                    do {
                        try buildProcess.run()
                        buildProcess.waitUntilExit()
                        
                        if buildProcess.terminationStatus == 0 {
                            LogManager.shared.log("Successfully built geth binary", type: .success)
                            
                            // Set executable permissions
                            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethBinaryPath.path)
                            
                            // Verify the binary works
                            let testProcess = Process()
                            testProcess.executableURL = URL(fileURLWithPath: gethBinaryPath.path)
                            testProcess.arguments = ["version"]
                            
                            let testPipe = Pipe()
                            testProcess.standardOutput = testPipe
                            testProcess.standardError = testPipe
                            
                            do {
                                try testProcess.run()
                                testProcess.waitUntilExit()
                                
                                if testProcess.terminationStatus == 0 {
                                    let output = String(data: testPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                                    LogManager.shared.log("Geth binary test successful: \(output.prefix(50))...", type: .success)
                                } else {
                                    let output = String(data: testPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                                    LogManager.shared.log("Geth binary test failed: \(output)", type: .error)
                                }
                            } catch {
                                LogManager.shared.log("Error testing geth binary: \(error.localizedDescription)", type: .error)
                            }
                            
                            // Clean up build directory
                            try fileManager.removeItem(at: buildDir)
                        } else {
                            let output = String(data: buildPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                            LogManager.shared.log("Failed to build geth binary: \(output)", type: .error)
                            LogManager.shared.log("Will use remote RPC endpoint instead", type: .info)
                        }
                    } catch {
                        LogManager.shared.log("Error building geth binary: \(error.localizedDescription)", type: .error)
                        LogManager.shared.log("Will use remote RPC endpoint instead", type: .info)
                    }
                } else if !goInstalled {
                    LogManager.shared.log("Go is not installed, cannot build geth binary. Will use remote RPC endpoint.", type: .warning)
                }
            } else {
                LogManager.shared.log("Using existing geth binary", type: .info)
                
                // Verify the existing binary works
                let testProcess = Process()
                testProcess.executableURL = URL(fileURLWithPath: gethBinaryPath.path)
                testProcess.arguments = ["version"]
                
                let testPipe = Pipe()
                testProcess.standardOutput = testPipe
                testProcess.standardError = testPipe
                
                do {
                    try testProcess.run()
                    testProcess.waitUntilExit()
                    
                    if testProcess.terminationStatus == 0 {
                        let output = String(data: testPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        LogManager.shared.log("Existing geth binary verified: \(output.prefix(50))...", type: .success)
                    } else {
                        let output = String(data: testPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        LogManager.shared.log("Existing geth binary failed verification: \(output)", type: .error)
                        LogManager.shared.log("Removing corrupted binary...", type: .info)
                        
                        // Remove corrupted binary
                        try fileManager.removeItem(at: gethBinaryPath)
                        LogManager.shared.log("Binary removed. Please restart the application to rebuild.", type: .info)
                    }
                } catch {
                    LogManager.shared.log("Error verifying geth binary: \(error.localizedDescription)", type: .error)
                }
            }
            
            // Verify the binary is executable
            if fileManager.fileExists(atPath: gethBinaryPath.path) {
                if let attributes = try? fileManager.attributesOfItem(atPath: gethBinaryPath.path),
                   let permissions = attributes[.posixPermissions] as? NSNumber {
                    let isExecutable = (permissions.intValue & 0o111) != 0
                    if !isExecutable {
                        LogManager.shared.log("Fixing geth binary permissions...", type: .info)
                        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethBinaryPath.path)
                    }
                }
            } else {
                LogManager.shared.log("No geth binary available. Will use remote RPC endpoint.", type: .warning)
            }
        } catch {
            LogManager.shared.log("Error setting up geth environment: \(error.localizedDescription)", type: .error)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(logManager)
                .onAppear {
                    setupWindow()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
    
    private func setupWindow() {
        // Get the current window
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                // Configure window to be resizable with minimum size
                window.styleMask.insert(.resizable)
                window.setContentSize(NSSize(width: 800, height: 600))
                window.minSize = NSSize(width: 800, height: 600)
                window.backgroundColor = .black
                window.title = "Mars Credit Miner"
                window.isMovableByWindowBackground = true
                window.setFrameAutosaveName("MarsCreditWindow")
                
                // Center the window on screen
                window.center()
                
                // Make the window key and bring it to the front
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    private func setupApp() {
        // Register custom font
        registerFont()
    }
    
    private func registerFont() {
        // Get the font bundle path
        guard let fontURL = Bundle.module.url(forResource: "gunshipbolditalic", withExtension: "otf") else {
            LogManager.shared.log("Failed to find font in bundle", type: .error)
            return
        }
        
        // Register font with CoreText
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
            if let error = error?.takeRetainedValue() {
                LogManager.shared.log("Error registering font: \(error)", type: .error)
            } else {
                LogManager.shared.log("Unknown error registering font", type: .error)
            }
            return
        }
        
        // Validate the font was registered
        if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
            // Print available font names after registration
            let _ = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
            LogManager.shared.log("Available fonts registered successfully", type: .success)
            
        } else {
            if let error = error?.takeRetainedValue() {
                LogManager.shared.log("Error registering font: \(error)", type: .error)
            } else {
                LogManager.shared.log("Unknown error registering font", type: .error)
            }
        }
        
        LogManager.shared.log("Loaded font: GunshipBoldItalic", type: .success)
    }
}