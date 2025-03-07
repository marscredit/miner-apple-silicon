import SwiftUI

struct LogView: View {
    @EnvironmentObject private var logManager: LogManager
    
    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logManager.logs) { log in
                        HStack(spacing: 8) {
                            Text(log.formattedTimestamp)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(log.type.color)
                            
                            Text(log.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(log.type.color)
                        }
                        .textSelection(.enabled)
                        .id(log.id)
                    }
                }
                .padding()
                .onChange(of: logManager.logs.count) { _ in
                    if let lastLog = logManager.logs.last {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.3))
    }
} 