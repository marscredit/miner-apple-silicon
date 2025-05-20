import Foundation
import SwiftUI

class LogManager: ObservableObject {
    @Published private(set) var logs: [LogEntry] = []
    @Published var selectedLogTypes: Set<LogType> = Set(LogType.allCases)
    @Published var showPrefixes: Bool = true
    
    static let shared = LogManager()
    
    private var logFileURL: URL?
    private var logFileHandle: FileHandle?
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType
        
        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: timestamp)
        }
        
        var formattedMessage: String {
            "\(type.prefix): \(message)"
        }
        
        var displayMessage: String {
            LogManager.shared.showPrefixes ? formattedMessage : message
        }
    }
    
    var filteredLogs: [LogEntry] {
        logs.filter { selectedLogTypes.contains($0.type) }
    }
    
    private init() {
        // By default, show all log types except debug (which can be too verbose)
        selectedLogTypes = Set(LogType.allCases)
        if let debugIndex = selectedLogTypes.firstIndex(of: .debug) {
            selectedLogTypes.remove(.debug)
        }
        setupLogFile()
    }
    
    private func setupLogFile() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("LogManager Error: Could not find application support directory.")
            return
        }

        let logDirectory = appSupportURL.appendingPathComponent("Logs") // Changed from "com.yourappname.logs"
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
            self.logFileURL = logDirectory.appendingPathComponent("app.log")

            if let url = self.logFileURL {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
                }
                self.logFileHandle = try FileHandle(forWritingTo: url)
                self.logFileHandle?.seekToEndOfFile() // Start writing at the end of the file
                print("LogManager: Logging to file: \(url.path)")
            }
        } catch {
            print("LogManager Error: Could not create log file: \(error.localizedDescription)")
            self.logFileURL = nil
            self.logFileHandle = nil
        }
    }
    
    func log(_ message: String, type: LogType = .info) {
        let entry = LogEntry(timestamp: Date(), message: message, type: type)
        let fileMessage = "\(entry.formattedTimestamp) \(entry.formattedMessage)\n"

        DispatchQueue.main.async {
            self.logs.append(entry)
            
            // Keep only the last 1000 logs in memory
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
        }

        // Write to file on a background thread to avoid blocking UI
        DispatchQueue.global(qos: .background).async {
            if let handle = self.logFileHandle, let data = fileMessage.data(using: .utf8) {
                handle.write(data)
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
    
    func toggleLogType(_ type: LogType) {
        DispatchQueue.main.async {
            if self.selectedLogTypes.contains(type) {
                self.selectedLogTypes.remove(type)
            } else {
                self.selectedLogTypes.insert(type)
            }
        }
    }
    
    func toggleAllLogTypes() {
        DispatchQueue.main.async {
            if self.selectedLogTypes.count == LogType.allCases.count {
                // If all are selected, deselect all
                self.selectedLogTypes.removeAll()
            } else {
                // Otherwise select all
                self.selectedLogTypes = Set(LogType.allCases)
            }
        }
    }
    
    func togglePrefixes() {
        DispatchQueue.main.async {
            self.showPrefixes.toggle()
        }
    }
    
    // Add a deinit to close the file handle
    deinit {
        logFileHandle?.closeFile()
    }
} 