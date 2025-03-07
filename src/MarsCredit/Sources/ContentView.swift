import SwiftUI
import CryptoSwift
import Crypto

struct MarsOrbitView: View {
    @Binding var isAnimating: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Mars (red circle)
                Circle()
                    .fill(Color(red: 193/255, green: 68/255, blue: 14/255))
                    .frame(width: 40, height: 40)
                    .shadow(color: .red.opacity(0.3), radius: 10)
                
                // Moon orbit path
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                
                // Orbiting moon
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(x: geometry.size.width * 0.4)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 3)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 100)
    }
}

struct NetworkStatusView: View {
    let syncProgress: Double
    let currentBlock: Int
    let highestBlock: Int
    
    var body: some View {
        VStack(spacing: 8) {
            ProgressView("Syncing Blockchain", value: syncProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(Color(red: 234/255, green: 51/255, blue: 35/255))
                .foregroundColor(.white)
            
            Text("Block: \(currentBlock) / \(highestBlock)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(8)
    }
}

struct ContentView: View {
    @State private var isGeneratingAccount = false
    @State private var isMining = false
    @State private var password = ""
    @State private var mnemonic = ""
    @State private var address = ""
    @State private var errorMessage = ""
    @State private var hashRate = "0 H/s"
    @State private var marsBalance = "0.00"
    @State private var syncProgress = 0.0
    @State private var currentBlock = 0
    @State private var highestBlock = 0
    @State private var isNodeConnected = false
    
    private let miningService: MiningService?
    private let logoURL = URL(string: "https://github.com/marscredit/brandassets/blob/main/marscredit_square_solid.png?raw=true")!
    private let marsRed = Color(red: 234/255, green: 51/255, blue: 35/255)
    
    init(miningService: MiningService? = nil) {
        self.miningService = miningService
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: logoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                    } placeholder: {
                        ProgressView()
                    }
                    .padding(.top)
                    
                    Text("Mars Credit Miner")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding(.bottom)
                    
                    if !address.isEmpty {
                        VStack(spacing: 10) {
                            Text("Mining Address:")
                                .foregroundColor(.gray)
                            Text(address)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            
                            Text("Balance: \(marsBalance) MARS")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.top)
                        }
                    }
                    
                    if syncProgress < 1.0 && !address.isEmpty {
                        NetworkStatusView(
                            syncProgress: syncProgress,
                            currentBlock: currentBlock,
                            highestBlock: highestBlock
                        )
                    }
                    
                    if !mnemonic.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mnemonic Seed (Save this for wallet import):")
                                .foregroundColor(.gray)
                            Text(mnemonic)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    
                    if address.isEmpty {
                        TextField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 300)
                            .padding()
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                    }
                    
                    HStack(spacing: 20) {
                        if address.isEmpty {
                            Button(action: generateAccount) {
                                if isGeneratingAccount {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(width: 150)
                                } else {
                                    Text("Generate Account")
                                        .frame(width: 150)
                                }
                            }
                            .disabled(isGeneratingAccount || password.isEmpty)
                            .buttonStyle(.borderedProminent)
                            .tint(marsRed)
                        }
                        
                        if !address.isEmpty {
                            Button(action: toggleMining) {
                                Text(isMining ? "Stop Mining" : "Start Mining")
                                    .frame(width: 150)
                            }
                            .disabled(password.isEmpty || syncProgress < 1.0)
                            .buttonStyle(.borderedProminent)
                            .tint(isMining ? marsRed : .green)
                        }
                    }
                    
                    if isMining {
                        VStack(spacing: 16) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                                    .opacity(0.8)
                                Text("Mining Active")
                                    .foregroundColor(.green)
                                Text(hashRate)
                                    .foregroundColor(.white)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                            
                            MarsOrbitView(isAnimating: $isMining)
                                .frame(height: 120)
                        }
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .onAppear {
            startNetworkStatusUpdates()
            startBalanceUpdates()
        }
    }
    
    private func generateAccount() {
        isGeneratingAccount = true
        errorMessage = ""
        
        Task {
            do {
                if let service = miningService {
                    let result = try service.generateAccount(password: password)
                    DispatchQueue.main.async {
                        self.address = result.address
                        self.mnemonic = result.mnemonic
                        self.isGeneratingAccount = false
                        self.startNetworkStatusUpdates()
                    }
                } else {
                    // Preview mode - simulate account generation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.address = "0x" + String(repeating: "0", count: 40)
                        self.mnemonic = "test word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12"
                        self.isGeneratingAccount = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to generate account: \(error.localizedDescription)"
                    self.isGeneratingAccount = false
                }
            }
        }
    }
    
    private func toggleMining() {
        if isMining {
            miningService?.stopMining()
            isMining = false
            hashRate = "0 H/s"
        } else {
            do {
                if let service = miningService {
                    try service.startMining(address: address, password: password)
                }
                isMining = true
                errorMessage = ""
                startHashRateUpdates()
            } catch {
                errorMessage = "Failed to start mining: \(error.localizedDescription)"
            }
        }
    }
    
    private func startHashRateUpdates() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard isMining else {
                timer.invalidate()
                return
            }
            
            if let service = miningService {
                let rate = service.getCurrentHashRate()
                hashRate = String(format: "%.2f MH/s", rate)
            } else {
                let randomHashRate = Double.random(in: 50...100)
                hashRate = String(format: "%.2f MH/s", randomHashRate)
            }
        }
    }
    
    private func startNetworkStatusUpdates() {
        guard !address.isEmpty else { return }
        
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            if let service = miningService {
                let status = service.getNetworkStatus()
                DispatchQueue.main.async {
                    self.syncProgress = status.syncProgress
                    self.currentBlock = status.currentBlock
                    self.highestBlock = status.highestBlock
                    self.isNodeConnected = status.isConnected
                }
            } else {
                // Preview mode - simulate sync progress
                DispatchQueue.main.async {
                    self.syncProgress = min(1.0, self.syncProgress + 0.1)
                    self.currentBlock = Int(Double(1_000_000) * self.syncProgress)
                    self.highestBlock = 1_000_000
                    self.isNodeConnected = true
                }
            }
        }
    }
    
    private func startBalanceUpdates() {
        guard !address.isEmpty else { return }
        
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { timer in
            if let service = miningService {
                let balance = service.getBalance(address: address)
                DispatchQueue.main.async {
                    self.marsBalance = String(format: "%.2f", balance)
                }
            } else {
                // Preview mode - simulate balance
                DispatchQueue.main.async {
                    let randomIncrease = Double.random(in: 0...0.1)
                    if let currentBalance = Double(self.marsBalance) {
                        self.marsBalance = String(format: "%.2f", currentBalance + randomIncrease)
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(miningService: nil)
    }
} 