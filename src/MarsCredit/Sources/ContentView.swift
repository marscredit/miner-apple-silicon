import SwiftUI
import CryptoSwift
import Crypto

struct ContentView: View {
    @State private var isGeneratingAccount = false
    @State private var isMining = false
    @State private var password = ""
    @State private var mnemonic = ""
    @State private var address = ""
    @State private var errorMessage = ""
    
    private let miningService = MiningService()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Mars Credit Miner")
                .font(.largeTitle)
                .padding()
            
            if !address.isEmpty {
                Text("Mining Address: \(address)")
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            
            if !mnemonic.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mnemonic Seed (Save this for wallet import):")
                        .font(.headline)
                    Text(mnemonic)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 300)
            
            HStack(spacing: 20) {
                Button(action: generateAccount) {
                    if isGeneratingAccount {
                        ProgressView()
                            .frame(width: 150)
                    } else {
                        Text("Generate Account")
                            .frame(width: 150)
                    }
                }
                .disabled(isGeneratingAccount || password.isEmpty)
                
                Button(action: toggleMining) {
                    Text(isMining ? "Stop Mining" : "Start Mining")
                        .frame(width: 150)
                }
                .disabled(address.isEmpty || password.isEmpty)
            }
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .padding()
    }
    
    private func generateAccount() {
        isGeneratingAccount = true
        errorMessage = ""
        
        Task {
            do {
                let result = try miningService.generateAccount(password: password)
                DispatchQueue.main.async {
                    self.address = result.address
                    self.mnemonic = result.mnemonic
                    self.isGeneratingAccount = false
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
            miningService.stopMining()
            isMining = false
        } else {
            do {
                try miningService.startMining(address: address, password: password)
                isMining = true
                errorMessage = ""
            } catch {
                errorMessage = "Failed to start mining: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    ContentView()
} 