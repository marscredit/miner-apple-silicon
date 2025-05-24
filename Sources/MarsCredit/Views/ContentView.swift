import SwiftUI

struct ContentView: View {
    @StateObject private var miningService = MiningService()
    @EnvironmentObject private var logManager: LogManager
    @State private var miningAddress = ""
    @State private var password = "marscredit" // Default password
    @State private var showingMnemonicSheet = false
    @State private var generatedMnemonic = ""
    @State private var isAnimating: Bool = false
    @State private var moonAngle: Double = 0
    @State private var showLogs = true
    @State private var showPerformanceMetrics = false
    @State private var appVersion = "Build: N/A"
    
    // Connection status calculation - UPDATED for Build 18
    private var connectionStatus: (color: Color, text: String) {
        // Prioritize remote RPC connection status for the main indicator
        if miningService.remoteRpcConnected {
            return (.green, "Connected")
        } else {
            return (.red, "Network Offline")
        }
    }
    
    // Local mining status for additional info
    private var miningStatus: (color: Color, text: String) {
        if miningService.isMining {
            return (.orange, "Mining Active")
        } else if miningService.isGethRunning {
            return (.yellow, "Syncing...")
        } else {
            return (.gray, "Not Mining")
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Bar - Modified
                HStack(alignment: .top) {
                    // Left side - Title and Buttons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mars Credit Miner")
                            .font(.gunship(size: 32))
                            .foregroundColor(.white)
                        
                        // MOVED: Compact buttons under title
                        HStack(spacing: 8) {
                            // UPDATED: Better mining state detection for Build 18
                            if miningService.isMining || miningService.isGethRunning {
                                Button("Stop Mining") {
                                    withAnimation { miningService.stopMining(); isAnimating = false }
                                }.compactButtonStyle(isDestructive: true)
                                
                                Button(showPerformanceMetrics ? "Hide Metrics" : "Show Metrics") {
                                    withAnimation { showPerformanceMetrics.toggle() }
                                }.compactButtonStyle()
                            } else {
                                Button("Start Mining") {
                                    withAnimation { miningService.startMining(address: miningAddress, password: password); isAnimating = true }
                                }.compactButtonStyle()
                            }
                            
                            Button("Backup Phrase") {
                                let newMnemonic = miningService.getCurrentAccountMnemonic()
                                if let mnemonicValue = newMnemonic, !mnemonicValue.starts(with: "Mnemonic not found"), !mnemonicValue.starts(with: "Error loading"), !mnemonicValue.isEmpty {
                                    generatedMnemonic = mnemonicValue
                                } else {
                                    generatedMnemonic = newMnemonic ?? "No active account to retrieve mnemonic."
                                }
                                showingMnemonicSheet = true
                            }.compactButtonStyle()
                            
                            Button("Reset Wallet") {
                                do {
                                    let (newAddress, newMnemonic) = try miningService.resetWallet(password: password)
                                    miningAddress = newAddress
                                    generatedMnemonic = newMnemonic
                                    LogManager.shared.log("Wallet reset. New address: \(newAddress).", type: .warning)
                                } catch {
                                    LogManager.shared.log("Error resetting wallet: \(error.localizedDescription)", type: .error)
                                }
                            }.compactButtonStyle(isDestructive: true)
                            
                            Button(showLogs ? "Hide Logs" : "Show Logs") {
                                withAnimation { showLogs.toggle() }
                            }.compactButtonStyle()
                        }
                    }
                        .padding(.leading)
                    
                    Spacer()
                    
                    // Right side - Status, Animation, Performance
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            // Spinning Mars/Moon animation (if mining)
                            if miningService.isMining {
                                ZStack {
                                    Circle() // Mars
                                        .fill(Color.red) // Explicitly red for Mars
                                        .frame(width: 20, height: 20)
                                    Circle() // Moon orbit path
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        .frame(width: 30, height: 30)
                                    Circle() // Moon
                                        .fill(Color.white)
                                        .frame(width: 6, height: 6)
                                        .offset(y: -15)
                                        .rotationEffect(.degrees(moonAngle))
                                }
                                .frame(width: 30, height: 30) // Constrain animation size
                                .padding(.trailing, 8)
                            }
                            
                            // Network Connection Status
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(connectionStatus.color)
                                        .frame(width: 8, height: 8)
                                    Text(connectionStatus.text)
                                        .font(.system(.body, design: .default))
                                        .foregroundColor(connectionStatus.color)
                                }
                                
                                // Local Mining Status (secondary)
                                HStack {
                                    Circle()
                                        .fill(miningStatus.color)
                                        .frame(width: 6, height: 6)
                                    Text(miningStatus.text)
                                        .font(.system(.caption, design: .default))
                                        .foregroundColor(miningStatus.color)
                                }
                            }
                        }
                        
                        if miningService.networkStatus.isConnected || miningService.isMining {
                            HStack {
                                Text("Block:")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.white)
                                Text("\(miningService.networkStatus.currentBlock)")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.green)
                                if miningService.networkStatus.currentBlock != miningService.networkStatus.highestBlock {
                                    Text("/ \(miningService.networkStatus.highestBlock)")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.yellow)
                                }
                            }
                            if miningService.networkStatus.currentBlock < miningService.networkStatus.highestBlock {
                                HStack(spacing: 4) {
                                    Text("Syncing:")
                                    Text("\(Int((Double(miningService.networkStatus.currentBlock) / Double(max(1, miningService.networkStatus.highestBlock))) * 100))%")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        // Optional Performance Metrics Panel (now at top)
                        if showPerformanceMetrics && miningService.isMining {
                            VStack(alignment: .trailing, spacing: 4) { // Changed to trailing
                                Text("Mining Performance")
                                    .font(.gunship(size: 16)) // Slightly smaller
                                    .foregroundColor(.white)
                                HStack {
                                    Text("Avg Block Time:")
                                        .font(.caption).foregroundColor(.gray)
                                    Text(miningService.formattedAverageBlockTime())
                                        .font(.caption).foregroundColor(.white)
                                }
                                HStack {
                                    Text("Blocks Found:")
                                        .font(.caption).foregroundColor(.gray)
                                    Text("\(miningService.blocksFound)")
                                        .font(.caption).foregroundColor(.white)
                                }
                                HStack {
                                    Text("Est. Earnings/Day:")
                                        .font(.caption).foregroundColor(.gray)
                                    Text("\(String(format: "%.2f", miningService.estimatedEarningsPerDay())) MARS")
                                        .font(.caption).foregroundColor(.white)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.trailing)
                }
                .padding(.horizontal)
                .padding(.top, 20) // Adjusted padding
                .frame(minHeight: 80) // Use minHeight
                
                // Center Content - Logs (Flexible height)
                if showLogs {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Filter Logs:")
                                .font(.system(.caption))
                                .foregroundColor(.gray)
                            ForEach(LogType.allCases.sorted(), id: \.self) { logType in
                                Button(action: { logManager.toggleLogType(logType) }) {
                                    HStack(spacing: 2) {
                                        Circle().fill(logType.color).frame(width: 8, height: 8)
                                        Text(String(describing: logType).uppercased())
                                            .font(.system(.caption))
                                            .foregroundColor(logManager.selectedLogTypes.contains(logType) ? .white : .gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle()).opacity(logManager.selectedLogTypes.contains(logType) ? 1.0 : 0.5)
                            }
                            Spacer()
                            Button(action: { logManager.togglePrefixes() }) {
                                Text(logManager.showPrefixes ? "Hide Prefixes" : "Show Prefixes")
                                    .font(.system(.caption)).foregroundColor(.gray)
                            }.buttonStyle(PlainButtonStyle())
                            Button(action: { logManager.clear() }) {
                                Text("Clear").font(.system(.caption)).foregroundColor(.red)
                            }.buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal).padding(.vertical, 4).background(Color.black.opacity(0.5))
                        ScrollView {
                            ScrollViewReader { proxy in
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(logManager.filteredLogs) { log in
                                        HStack(spacing: 8) {
                                            Text(log.formattedTimestamp).font(.system(.caption, design: .monospaced)).foregroundColor(log.type.color)
                                            Text(logManager.showPrefixes ? log.formattedMessage : log.message).font(.system(.caption, design: .monospaced)).foregroundColor(log.type.color).lineLimit(nil)
                                        }
                                        .textSelection(.enabled).id(log.id)
                                    }
                                }
                                .padding()
                                .onChange(of: logManager.logs.count) { _ in if let lastLog = logManager.filteredLogs.last { proxy.scrollTo(lastLog.id, anchor: .bottom) } }
                                .onChange(of: logManager.selectedLogTypes) { _ in if let lastLog = logManager.filteredLogs.last { proxy.scrollTo(lastLog.id, anchor: .bottom) } }
                            }
                        }
                        .background(Color.black.opacity(0.3))
                    }
                }
                
                // Bottom Bar - Mining Info and Status Indicators
                HStack(alignment: .center, spacing: 16) {
                    // Mining Information - LEFT SIDE
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Address:").font(.caption).foregroundColor(.gray)
                            Text(miningAddress).font(.caption).foregroundColor(.white).lineLimit(1).truncationMode(.middle)
                        }
                        HStack(spacing: 6) {
                            Text("Balance:").font(.caption).foregroundColor(.gray)
                            Text("\(String(format: "%.2f", miningService.currentBalance)) MARS").font(.caption).foregroundColor(.white)
                        }
                        // REMOVED: Hash Rate - replaced with better indicators below
                    }
                    .padding(.leading)
                    
                    Spacer()
                    
                    // IMPROVED: Better Mining Indicators - RIGHT SIDE
                    VStack(alignment: .trailing, spacing: 6) {
                        // Process Status Indicator
                        HStack(spacing: 6) {
                            Text("Process:").font(.caption).foregroundColor(.gray)
                            if miningService.isGethRunning {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                    Text("Geth Active").font(.caption).foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Circle().fill(.red).frame(width: 6, height: 6)
                                    Text("Offline").font(.caption).foregroundColor(.red)
                                }
                            }
                        }
                        
                        // Sync Progress Indicator
                        if miningService.networkStatus.isConnected {
                            HStack(spacing: 6) {
                                Text("Sync:").font(.caption).foregroundColor(.gray)
                                if miningService.networkStatus.currentBlock >= miningService.networkStatus.highestBlock {
                                    HStack(spacing: 4) {
                                        Circle().fill(.green).frame(width: 6, height: 6)
                                        Text("Synced").font(.caption).foregroundColor(.green)
                                    }
                                } else {
                                    let progress = Int((Double(miningService.networkStatus.currentBlock) / Double(max(1, miningService.networkStatus.highestBlock))) * 100)
                                    HStack(spacing: 4) {
                                        Circle().fill(.blue).frame(width: 6, height: 6)
                                        Text("\(progress)%").font(.caption).foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        
                        // Connection Quality Indicator  
                        HStack(spacing: 6) {
                            Text("Network:").font(.caption).foregroundColor(.gray)
                            if miningService.remoteRpcConnected {
                                HStack(spacing: 4) {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                    Text("Connected").font(.caption).foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Circle().fill(.red).frame(width: 6, height: 6)
                                    Text("Disconnected").font(.caption).foregroundColor(.red)
                                }
                            }
                        }
                        
                        // Display App Version
                        Text(appVersion)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.top, 2)
                    }
                    .padding(.trailing)
                }
                .padding()
                .frame(height: 100) // Adjusted height
            }
            .background(Color.black)
            .sheet(isPresented: $showingMnemonicSheet) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text("Recovery Phrase").font(.gunship(size: 24)).foregroundColor(.white)
                        Text("These 12 words are the only way to recover your account if you lose access. Keep them safe and never share them with anyone.")
                            .font(.system(.body, design: .default)).foregroundColor(.gray).multilineTextAlignment(.center)
                        Text(generatedMnemonic).font(.system(.body, design: .monospaced)).foregroundColor(.white).padding().background(Color.gray.opacity(0.2)).cornerRadius(8).fixedSize(horizontal: false, vertical: true)
                        Button("Close") { showingMnemonicSheet = false }.miningButtonStyle()
                    }.padding()
                }
            }
        }
        .onAppear {
            loadAppVersion()
            generateAccountIfNeeded()
            startAnimationTimers()
            MiningService.shared = miningService // Keep this for signal handling
            // LogManager.shared.log("App started. Click 'Start Mining' to begin mining.", type: .info) // Already logged by ContentView
        }
        .onDisappear {
            stopAnimationTimers()
        }
    }
    
    private func generateAccountIfNeeded() {
        if miningAddress.isEmpty || generatedMnemonic.isEmpty {
            do {
                let (address, mnemonic) = try miningService.generateAccount(password: password)
                miningAddress = address
                generatedMnemonic = mnemonic
                LogManager.shared.log("New account generated: \(address)", type: .success)
                LogManager.shared.log("Backup phrase created (accessible via the 'See Backup Phrase' button)", type: .info)
            } catch {
                LogManager.shared.log("Error generating account: \(error.localizedDescription)", type: .error)
                miningAddress = "0xDEADBEEF...ACCOUNT_ERROR"
            }
        }
    }
    
    private func startAnimationTimers() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if isAnimating {
                withAnimation(.linear(duration: 0.05)) {
                    moonAngle += 2 // Speed up animation slightly
                    if moonAngle >= 360 { moonAngle = 0 }
                }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            if miningService.isMining { miningService.checkMinerBlocks() }
        }
    }
    
    private func stopAnimationTimers() {}
    
    private func loadAppVersion() {
        if let versionPath = Bundle.main.path(forResource: "VERSION", ofType: "txt") {
            do {
                let versionString = try String(contentsOfFile: versionPath, encoding: .utf8)
                self.appVersion = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                self.appVersion = "Build: Error"
                LogManager.shared.log("Error loading version file: \(error.localizedDescription)", type: .error)
            }
        } else {
            self.appVersion = "Build: Not Found"
        }
    }
}

// Preview for development (optional)
// struct ContentView_Previews: PreviewProvider {
//     static var previews: some View {
//         ContentView()
//             .environmentObject(LogManager())
//             .frame(width: 700, height: 500)
//     }
// } 