import Foundation
import SwiftUI

class LogManager: ObservableObject {
    @Published private(set) var logs: [LogEntry] = []
    @Published var selectedLogTypes: Set<LogType> = Set(LogType.allCases)
    @Published var showPrefixes: Bool = true
    
    static let shared = LogManager()
    
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
    }
    
    func log(_ message: String, type: LogType = .info) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(timestamp: Date(), message: message, type: type))
            
            // Keep only the last 1000 logs
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
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
} 