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
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(alignment: .top) {
                // Left side - Title and Balance
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mars Credit Miner")
                        .font(.gunship(size: 32))
                        .foregroundColor(.white)
                    
                    Text("Balance: \(String(format: "%.2f", miningService.currentBalance)) MARS")
                        .font(.system(.body, design: .default))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Right side - Network Status
                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(miningService.networkStatus.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(miningService.isMining ? 
                             (miningService.networkStatus.isConnected ? "Connected" : "Starting node...") : 
                             (miningService.networkStatus.isConnected ? "Connected" : "Node not running"))
                            .font(.system(.body, design: .default))
                            .foregroundColor(miningService.networkStatus.isConnected ? .green : 
                                           (miningService.isMining ? .yellow : .red))
                    }
                    
                    if miningService.networkStatus.isConnected {
                        Text("Block: \(miningService.networkStatus.currentBlock)")
                            .font(.gunship(size: 14))
                            .foregroundColor(.white)
                        
                        if miningService.networkStatus.syncProgress < 1.0 {
                            HStack(spacing: 4) {
                                Text("Syncing:")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.yellow)
                                ProgressView(value: miningService.networkStatus.syncProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .yellow))
                                    .frame(width: 100)
                                Text("\(Int(miningService.networkStatus.syncProgress * 100))%")
                                    .font(.gunship(size: 14))
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 32)
            
            // Center Content - Logs
            if showLogs {
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
                .frame(maxHeight: 200)
            }
            
            Spacer()
            
            // Bottom Content
            VStack(alignment: .leading, spacing: 16) {
                // Planet and Moon Animation
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
                    .padding(.bottom)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mining Address:")
                        .font(.gunship(size: 14))
                        .foregroundColor(.gray)
                    Text(miningAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                Text("\(String(format: "%.2f", miningService.currentHashRate)) MH/s")
                    .font(.system(.body, design: .default))
                    .foregroundColor(.white)
                
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
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .frame(width: 800, height: 600)
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
        .onAppear {
            generateAccountIfNeeded()
        }
        .onChange(of: miningService.isMining) { isMining in
            if isMining {
                // Start animation immediately when mining begins
                isAnimating = true
                moonAngle = 0 // Reset angle first
                withAnimation(Animation.linear(duration: 30).repeatForever(autoreverses: false)) {
                    moonAngle = 360
                }
            } else {
                isAnimating = false
                withAnimation(.default) {
                    moonAngle = 0
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // Add a method to generate an account
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
} 