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
        } catch {
            LogManager.shared.log("Error creating directory: \(error.localizedDescription)", type: .error)
        }
        
        // Get the path to the bundled geth binary
        guard let bundledGethPath = Bundle.main.resourceURL?
            .appendingPathComponent("deps")
            .appendingPathComponent("go-marscredit")
            .appendingPathComponent("build")
            .appendingPathComponent("bin")
            .appendingPathComponent("geth") else {
            LogManager.shared.log("Error: Could not locate bundled geth binary", type: .error)
            return
        }
        
        // Copy the binary to the user's directory if it doesn't exist or needs updating
        if !fileManager.fileExists(atPath: gethBinaryPath.path) {
            do {
                if fileManager.fileExists(atPath: gethBinaryPath.path) {
                    try fileManager.removeItem(at: gethBinaryPath)
                    LogManager.shared.log("Removed existing geth binary", type: .info)
                }
                try fileManager.copyItem(at: bundledGethPath, to: gethBinaryPath)
                LogManager.shared.log("Copied geth binary to \(gethBinaryPath.path)", type: .success)
                
                // Make the binary executable
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/chmod")
                process.arguments = ["+x", gethBinaryPath.path]
                try process.run()
                process.waitUntilExit()
                
                LogManager.shared.log("Successfully installed geth binary", type: .success)
            } catch {
                LogManager.shared.log("Error setting up geth binary: \(error.localizedDescription)", type: .error)
            }
        } else {
            LogManager.shared.log("Using existing geth binary", type: .info)
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