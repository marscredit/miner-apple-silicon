import SwiftUI

enum LogType: CaseIterable, Comparable, Hashable {
    case error
    case warning
    case success
    case info
    case debug
    case mining
    case network
    case stats
    case system
    
    // Compare types in the order they're defined
    static func < (lhs: LogType, rhs: LogType) -> Bool {
        let order: [LogType] = [.error, .warning, .success, .info, .debug, .mining, .network, .stats, .system]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

extension LogType {
    var color: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .yellow
        case .success:
            return .green
        case .info:
            return .white
        case .debug:
            return .gray
        case .mining:
            return Color(red: 1.0, green: 0.5, blue: 0.0) // Orange color for mining
        case .network:
            return Color(red: 0.0, green: 0.8, blue: 1.0) // Cyan color for network
        case .stats:
            return Color(red: 0.8, green: 0.3, blue: 1.0) // Purple color for statistics
        case .system:
            return Color(red: 0.7, green: 0.7, blue: 0.7) // Light gray for system
        }
    }
    
    var prefix: String {
        switch self {
        case .error:
            return "❌ ERROR"
        case .warning:
            return "⚠️ WARNING"
        case .success:
            return "✅ SUCCESS"
        case .info:
            return "ℹ️ INFO"
        case .debug:
            return "🔍 DEBUG"
        case .mining:
            return "⛏️ MINING"
        case .network:
            return "🌐 NETWORK"
        case .stats:
            return "📊 STATS"
        case .system:
            return "🖥️ SYSTEM"
        }
    }
} 