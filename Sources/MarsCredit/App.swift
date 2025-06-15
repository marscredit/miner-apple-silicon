import SwiftUI
import CoreText
import Foundation
import AppKit

@main
struct MarsCreditApp: App {
    @StateObject private var logManager = LogManager.shared
    @StateObject private var miningService = MiningService()
    
    // Sleep/Wake detection
    private let sleepWakeNotificationCenter = NSWorkspace.shared.notificationCenter
    
    init() {
        LogManager.shared.clear() // Clear any old logs
        LogManager.shared.log("Starting Mars Credit Miner Build 29...", type: .info)
        MiningService.shared = miningService // Set the shared instance
        
        // Setup sleep/wake notifications
        setupSleepWakeNotifications()
        
        // Move heavy operations to background thread
        setupAppAsync()
    }
    
    private func setupSleepWakeNotifications() {
        LogManager.shared.log("Setting up sleep/wake notifications...", type: .info)
        
        // Listen for sleep notifications
        sleepWakeNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            LogManager.shared.log("System going to sleep - stopping mining...", type: .warning)
            self.miningService.stopMining()
        }
        
        // Listen for wake notifications
        sleepWakeNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            LogManager.shared.log("System woke up - mining can be restarted manually", type: .info)
            // Don't automatically restart mining - let user decide
        }
        
        // Listen for app termination to clean up geth processes
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            LogManager.shared.log("App terminating - cleaning up geth processes...", type: .warning)
            self.miningService.stopMining()
            self.cleanupGethProcesses()
        }
    }
    
    private func cleanupGethProcesses() {
        // Kill any remaining geth processes
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProcess.arguments = ["-9", "geth"]
        
        do {
            try killProcess.run()
            LogManager.shared.log("Cleaned up geth processes", type: .success)
        } catch {
            LogManager.shared.log("Could not cleanup geth processes: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func setupAppAsync() {
        // Move heavy initialization to background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Setup geth binary in background
            self.setupGethBinaryAsync()
            
            // Setup app components in background
            DispatchQueue.main.async {
                self.setupApp()
            }
            
            // Run app helper in background
            self.runAppHelper()
        }
    }
    
    // Helper method to run the app_helper.sh script
    private func runAppHelper() {
        // Look for app_helper.sh in scripts directory (new location)
        var appHelperPath: String?
        
        // First try the new scripts directory
        let scriptsPath = FileManager.default.currentDirectoryPath + "/scripts/app_helper.sh"
        if FileManager.default.fileExists(atPath: scriptsPath) {
            appHelperPath = scriptsPath
            DispatchQueue.main.async {
                LogManager.shared.log("Found app_helper.sh in scripts: \(scriptsPath)", type: .success)
            }
        }
        
        // Then try the app bundle's Resources directory
        if appHelperPath == nil, let resourcesPath = Bundle.main.resourceURL?.path {
            let scriptPath = resourcesPath + "/app_helper.sh"
            if FileManager.default.fileExists(atPath: scriptPath) {
                appHelperPath = scriptPath
                DispatchQueue.main.async {
                    LogManager.shared.log("Found app_helper.sh in resources: \(scriptPath)", type: .success)
                }
            }
        }
        
        // If we found a script, execute it
        if let scriptPath = appHelperPath {
            DispatchQueue.main.async {
                LogManager.shared.log("Running app_helper.sh to ensure proper environment setup...", type: .info)
            }
            
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
                
                DispatchQueue.main.async {
                    LogManager.shared.log("App helper script is running in the background", type: .success)
                }
            } catch {
                DispatchQueue.main.async {
                    LogManager.shared.log("Failed to run app_helper.sh: \(error.localizedDescription)", type: .error)
                }
            }
        } else {
            DispatchQueue.main.async {
                LogManager.shared.log("app_helper.sh not found, skipping environment setup", type: .warning)
            }
        }
    }
    
    private func setupGethBinaryAsync() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let marscreditDir = homeDir.appendingPathComponent(".marscredit")
        let gethBinaryPath = marscreditDir.appendingPathComponent("geth-binary")
        
        DispatchQueue.main.async {
            LogManager.shared.log("Setting up geth environment (background thread)...", type: .info)
        }
        
        // Create marscredit directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: marscreditDir, withIntermediateDirectories: true)
            DispatchQueue.main.async {
                LogManager.shared.log("Created marscredit directory at \(marscreditDir.path)", type: .success)
            }
            
            // First, try to use the bundled geth binary
            if let bundledGethPath = findBundledGethBinary() {
                if !fileManager.fileExists(atPath: gethBinaryPath.path) {
                    do {
                        try fileManager.copyItem(at: bundledGethPath, to: gethBinaryPath)
                        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethBinaryPath.path)
                        DispatchQueue.main.async {
                            LogManager.shared.log("Successfully installed bundled geth binary", type: .success)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            LogManager.shared.log("Failed to copy bundled geth binary: \(error.localizedDescription)", type: .error)
                        }
                    }
                }
            }
            
            // Verify the binary works
            if fileManager.fileExists(atPath: gethBinaryPath.path) {
                verifyGethBinary(at: gethBinaryPath)
            } else {
                DispatchQueue.main.async {
                    LogManager.shared.log("No geth binary available. Will use remote RPC endpoint.", type: .warning)
                }
            }
            
        } catch {
            DispatchQueue.main.async {
                LogManager.shared.log("Error setting up geth environment: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    private func findBundledGethBinary() -> URL? {
        // Check app bundle Resources/geth/geth
        if let bundleURL = Bundle.main.resourceURL {
            let gethPath = bundleURL.appendingPathComponent("geth").appendingPathComponent("geth")
            if FileManager.default.fileExists(atPath: gethPath.path) {
                DispatchQueue.main.async {
                    LogManager.shared.log("Found bundled geth binary in app bundle", type: .success)
                }
                return gethPath
            }
        }
        
        // Check Resources/geth/geth in working directory
        let workingDirectory = FileManager.default.currentDirectoryPath
        let resourcesGethPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("Resources")
            .appendingPathComponent("geth")
            .appendingPathComponent("geth")
        
        if FileManager.default.fileExists(atPath: resourcesGethPath.path) {
            DispatchQueue.main.async {
                LogManager.shared.log("Found bundled geth binary in Resources directory", type: .success)
            }
            return resourcesGethPath
        }
        
        DispatchQueue.main.async {
            LogManager.shared.log("No bundled geth binary found", type: .warning)
        }
        return nil
    }
    
    private func verifyGethBinary(at path: URL) {
        let testProcess = Process()
        testProcess.executableURL = path
        testProcess.arguments = ["version"]
        
        let testPipe = Pipe()
        testProcess.standardOutput = testPipe
        testProcess.standardError = testPipe
        
        do {
            try testProcess.run()
            testProcess.waitUntilExit()
            
            if testProcess.terminationStatus == 0 {
                let output = String(data: testPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    LogManager.shared.log("Geth binary verified: \(output.prefix(50))...", type: .success)
                }
            } else {
                let output = String(data: testPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    LogManager.shared.log("Geth binary failed verification: \(output)", type: .error)
                }
                
                // Remove corrupted binary
                do {
                    try FileManager.default.removeItem(at: path)
                    DispatchQueue.main.async {
                        LogManager.shared.log("Removed corrupted geth binary", type: .info)
                    }
                } catch {
                    DispatchQueue.main.async {
                        LogManager.shared.log("Could not remove corrupted binary: \(error.localizedDescription)", type: .error)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                LogManager.shared.log("Error verifying geth binary: \(error.localizedDescription)", type: .error)
            }
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
                window.title = "Mars Credit Miner - Build 29"
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
        
        LogManager.shared.log("Loaded font: GunshipBoldItalic", type: .success)
    }
}