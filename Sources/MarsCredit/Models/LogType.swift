import SwiftUI

enum LogType {
    case error
    case warning
    case success
    case info
    case debug
    case mining
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
        }
    }
} 