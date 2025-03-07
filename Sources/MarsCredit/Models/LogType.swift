import SwiftUI

enum LogType {
    case error
    case warning
    case success
    case info
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
        }
    }
} 