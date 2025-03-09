import SwiftUI
import CoreText
import Foundation

@main
struct MarsCreditApp: App {
    @StateObject private var logManager = LogManager.shared
    private var miningService = MiningService()
    
    init() {
        LogManager.shared.log("Starting Mars Credit Miner...", type: .info)
        setupGethBinary()
        setupCustomFont()
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
            
            // If binary doesn't exist, we need to build it
            if !fileManager.fileExists(atPath: gethBinaryPath.path) {
                LogManager.shared.log("Building geth binary for Apple Silicon...", type: .info)
                
                // Create a temporary build directory
                let buildDir = marscreditDir.appendingPathComponent("build")
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
                buildProcess.executableURL = URL(fileURLWithPath: "/usr/local/go/bin/go")
                buildProcess.environment = ProcessInfo.processInfo.environment
                buildProcess.environment?["GOARCH"] = "arm64"
                buildProcess.environment?["GOOS"] = "darwin"
                buildProcess.arguments = ["build", "-o", gethBinaryPath.path]
                
                let pipe = Pipe()
                buildProcess.standardOutput = pipe
                buildProcess.standardError = pipe
                
                do {
                    try buildProcess.run()
                    buildProcess.waitUntilExit()
                    
                    if buildProcess.terminationStatus == 0 {
                        LogManager.shared.log("Successfully built geth binary", type: .success)
                        
                        // Set executable permissions
                        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethBinaryPath.path)
                        
                        // Clean up build directory
                        try fileManager.removeItem(at: buildDir)
                    } else {
                        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        LogManager.shared.log("Failed to build geth binary: \(output)", type: .error)
                    }
                } catch {
                    LogManager.shared.log("Error building geth binary: \(error.localizedDescription)", type: .error)
                }
            } else {
                LogManager.shared.log("Using existing geth binary", type: .info)
            }
            
            // Verify the binary is executable
            if let attributes = try? fileManager.attributesOfItem(atPath: gethBinaryPath.path),
               let permissions = attributes[.posixPermissions] as? NSNumber {
                let isExecutable = (permissions.intValue & 0o111) != 0
                if !isExecutable {
                    LogManager.shared.log("Fixing geth binary permissions...", type: .info)
                    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethBinaryPath.path)
                }
            }
        } catch {
            LogManager.shared.log("Error setting up geth environment: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func setupCustomFont() {
        LogManager.shared.log("Setting up custom fonts...", type: .info)
        // Register custom font
        if let fontURL = Bundle.module.url(forResource: "gunshipboldital", withExtension: "otf") {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
                // Print available font names after registration
                let fontDescriptors = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
                LogManager.shared.log("Available fonts registered successfully", type: .success)
                
                // Create a test font to verify the name
                let testFont = CTFontCreateWithName("GunshipBoldItalic" as CFString, 12, nil)
                let fontName = CTFontCopyPostScriptName(testFont) as String
                LogManager.shared.log("Loaded font: \(fontName)", type: .success)
            } else {
                LogManager.shared.log("Failed to register font: \(error.debugDescription)", type: .error)
            }
        } else {
            LogManager.shared.log("Failed to find font file in bundle", type: .error)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 800, height: 600)
                .environmentObject(logManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
} 