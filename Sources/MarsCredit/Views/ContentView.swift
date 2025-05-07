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
    
    // Connection status calculation
    private var connectionStatus: (color: Color, text: String) {
        if miningService.isMining {
            if miningService.networkStatus.isConnected {
                return (.green, "Connected")
            } else {
                return (.yellow, "Connecting...")
            }
        } else {
            if miningService.networkStatus.isConnected {
                return (.green, "Connected")
            } else {
                return (.red, "Node not running")
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Bar - Fixed height
                HStack(alignment: .top) {
                    // Left side - Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mars Credit Miner")
                            .font(.gunship(size: 32))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Right side - Network Status
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(connectionStatus.color)
                                .frame(width: 8, height: 8)
                            Text(connectionStatus.text)
                                .font(.system(.body, design: .default))
                                .foregroundColor(connectionStatus.color)
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
                    }
                }
                .padding(.horizontal)
                .padding(.top, 32)
                .frame(height: 80)
                
                // Center Content - Logs (Flexible height)
                if showLogs {
                    VStack(spacing: 0) {
                        // Log filter controls
                        HStack {
                            Text("Filter Logs:")
                                .font(.system(.caption))
                                .foregroundColor(.gray)
                            
                            // Quick filter buttons
                            ForEach(LogType.allCases.sorted(), id: \.self) { logType in
                                Button(action: {
                                    logManager.toggleLogType(logType)
                                }) {
                                    HStack(spacing: 2) {
                                        Circle()
                                            .fill(logType.color)
                                            .frame(width: 8, height: 8)
                                        Text(String(describing: logType).uppercased())
                                            .font(.system(.caption))
                                            .foregroundColor(logManager.selectedLogTypes.contains(logType) ? .white : .gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .opacity(logManager.selectedLogTypes.contains(logType) ? 1.0 : 0.5)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                logManager.togglePrefixes()
                            }) {
                                Text(logManager.showPrefixes ? "Hide Prefixes" : "Show Prefixes")
                                    .font(.system(.caption))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                logManager.clear()
                            }) {
                                Text("Clear")
                                    .font(.system(.caption))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        
                        ScrollView {
                            ScrollViewReader { proxy in
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(logManager.filteredLogs) { log in
                                        HStack(spacing: 8) {
                                            Text(log.formattedTimestamp)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(log.type.color)
                                            
                                            Text(logManager.showPrefixes ? log.formattedMessage : log.message)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(log.type.color)
                                                .lineLimit(nil)
                                        }
                                        .textSelection(.enabled)
                                        .id(log.id)
                                    }
                                }
                                .padding()
                                .onChange(of: logManager.logs.count) { _ in
                                    if let lastLog = logManager.filteredLogs.last {
                                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                                    }
                                }
                                .onChange(of: logManager.selectedLogTypes) { _ in
                                    if let lastLog = logManager.filteredLogs.last {
                                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .background(Color.black.opacity(0.3))
                    }
                }
                
                // Optional Performance Metrics Panel
                if showPerformanceMetrics && miningService.isMining {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mining Performance")
                            .font(.gunship(size: 18))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 32) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Avg Block Time:")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.gray)
                                    
                                    Text(miningService.formattedAverageBlockTime())
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.white)
                                }
                                
                                HStack {
                                    Text("Blocks Found:")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.gray)
                                    
                                    Text("\(miningService.blocksFound)")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Est. Earnings/Day:")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.gray)
                                    
                                    Text("\(String(format: "%.2f", miningService.estimatedEarningsPerDay())) MARS")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.white)
                                }
                                
                                HStack {
                                    Text("Connection Attempts:")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.gray)
                                    
                                    Text("\(miningService.connectionAttempts)")
                                        .font(.gunship(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(width: geometry.size.width)
                    .background(Color.black.opacity(0.5))
                }
                
                // Bottom Content - Fixed height
                HStack(alignment: .top, spacing: 20) {
                    // Left side - Mining info and animation
                    VStack(alignment: .leading, spacing: 16) {
                        // Mars and Moon Animation
                        if miningService.isMining {
                            ZStack {
                                Circle() // Mars
                                    .fill(Color(red: 1, green: 0, blue: 0))
                                    .frame(width: 40, height: 40)
                                
                                Circle() // Moon orbit path
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    .frame(width: 80, height: 80)
                                
                                Circle() // Moon
                                    .fill(Color.white)
                                    .frame(width: 12, height: 12)
                                    .offset(y: -40)
                                    .rotationEffect(.degrees(moonAngle))
                            }
                            .padding(.bottom, 8)
                        }
                        
                        // Mining Information
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Mining Address:")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.gray)
                                
                                Text(miningAddress)
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            HStack(spacing: 8) {
                                Text("Balance:")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.gray)
                                
                                Text("\(String(format: "%.2f", miningService.currentBalance)) MARS")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.white)
                            }
                            
                            HStack(spacing: 8) {
                                Text("Hash Rate:")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.gray)
                                
                                Text("\(String(format: "%.2f", miningService.currentHashRate)) MH/s")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Right side - Buttons
                    VStack(alignment: .trailing) {
                        HStack(spacing: 16) {
                            if miningService.isMining {
                                Button("Stop Mining") {
                                    withAnimation {
                                        miningService.stopMining()
                                        isAnimating = false
                                    }
                                }
                                .miningButtonStyle(isDestructive: true)
                                .font(.gunship(size: 14))
                                
                                // Performance Button
                                Button(showPerformanceMetrics ? "Hide Metrics" : "Show Metrics") {
                                    withAnimation {
                                        showPerformanceMetrics.toggle()
                                    }
                                }
                                .miningButtonStyle()
                                .font(.gunship(size: 14))
                            } else {
                                Button("Start Mining") {
                                    withAnimation {
                                        miningService.startMining(address: miningAddress, password: password)
                                        isAnimating = true
                                    }
                                }
                                .miningButtonStyle()
                                .font(.gunship(size: 14))
                            }
                            
                            Button("See Backup Phrase") {
                                showingMnemonicSheet = true
                            }
                            .miningButtonStyle()
                            .font(.gunship(size: 14))
                            
                            Button(showLogs ? "Hide Logs" : "Show Logs") {
                                withAnimation {
                                    showLogs.toggle()
                                }
                            }
                            .miningButtonStyle()
                            .font(.gunship(size: 14))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .padding(.top, 16)
                .frame(height: 120)
            }
            .background(Color.black)
            .sheet(isPresented: $showingMnemonicSheet) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        Text("Recovery Phrase")
                            .font(.gunship(size: 24))
                            .foregroundColor(.white)
                        
                        Text("These 12 words are the only way to recover your account if you lose access. Keep them safe and never share them with anyone.")
                            .font(.system(.body, design: .default))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Text(generatedMnemonic)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button("Close") {
                            showingMnemonicSheet = false
                        }
                        .miningButtonStyle()
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            generateAccountIfNeeded()
            startAnimationTimers()
            // We no longer automatically start mining - let the user click the button
            MiningService.shared = miningService
            LogManager.shared.log("App started. Click 'Start Mining' to begin mining.", type: .info)
        }
        .onDisappear {
            stopAnimationTimers()
        }
    }
    
    private func generateAccountIfNeeded() {
        if miningAddress.isEmpty || generatedMnemonic.isEmpty {
            // Use a default password for simplicity
            do {
                let (address, mnemonic) = try miningService.generateAccount(password: password)
                miningAddress = address
                generatedMnemonic = mnemonic
                LogManager.shared.log("New account generated: \(address)", type: .success)
                LogManager.shared.log("Backup phrase created (accessible via the 'See Backup Phrase' button)", type: .info)
            } catch {
                LogManager.shared.log("Error generating account: \(error.localizedDescription)", type: .error)
                // Fallback to a default address if generation fails
                miningAddress = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
            }
        }
    }
    
    private func startAnimationTimers() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if isAnimating {
                withAnimation {
                    moonAngle += 1
                    if moonAngle >= 360 {
                        moonAngle = 0
                    }
                }
            }
        }
        
        // Check for blocks found by this miner every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            if miningService.isMining {
                miningService.checkMinerBlocks()
            }
        }
    }
    
    private func stopAnimationTimers() {
        // If needed, we could store timer references and invalidate them here
    }
} 