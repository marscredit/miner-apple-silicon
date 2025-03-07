import Foundation
import CryptoSwift
import Crypto

struct NetworkStatus {
    let syncProgress: Double
    let currentBlock: Int
    let highestBlock: Int
    let isConnected: Bool
}

class MiningService {
    private var isMining = false
    private var currentHashRate: Double = 0.0
    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var ethClient: EthereumClient?
    
    var keystoreDirectory: URL {
        homeDirectory.appendingPathComponent(".marscredit/keystore")
    }
    
    init() {
        try? fileManager.createDirectory(at: keystoreDirectory, withIntermediateDirectories: true)
        setupEthereumClient()
    }
    
    private func setupEthereumClient() {
        ethClient = EthereumClient()
    }
    
    func generateAccount(password: String) throws -> (address: String, mnemonic: String) {
        // Generate a random mnemonic (12 words)
        let entropy = try generateSecureEntropy(byteCount: 16)
        let mnemonic = try generateMnemonic(fromEntropy: entropy)
        
        // Create keystore file
        let privateKey = try derivePrivateKey(fromMnemonic: mnemonic)
        let address = try createKeystoreFile(privateKey: privateKey, password: password)
        
        return (address, mnemonic.joined(separator: " "))
    }
    
    func startMining(address: String, password: String) throws {
        guard !isMining else { return }
        isMining = true
        
        // Start mining with the provided address
        try ethClient?.startMining(address: address)
        
        // Start updating hash rate
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isMining else {
                timer.invalidate()
                return
            }
            
            // Update network stats
            if let hashRate = self.ethClient?.getHashRate() {
                self.currentHashRate = Double(hashRate) / 1_000_000 // Convert to MH/s
            }
        }
    }
    
    func stopMining() {
        isMining = false
        ethClient?.stopMining()
    }
    
    func getCurrentHashRate() -> Double {
        return currentHashRate
    }
    
    func getNetworkStatus() -> NetworkStatus {
        let client = ethClient ?? EthereumClient()
        
        let syncStatus = client.getSyncStatus()
        return NetworkStatus(
            syncProgress: syncStatus.progress,
            currentBlock: syncStatus.currentBlock,
            highestBlock: syncStatus.targetBlock,
            isConnected: client.getPeerCount() > 0
        )
    }
    
    func getBalance(address: String) -> Double {
        guard let client = ethClient else { return 0 }
        
        if let balance = try? client.getBalance(address: address) {
            return Double(balance) / 1e18 // Convert from wei to MARS
        }
        return 0
    }
    
    // MARK: - Private Helper Methods
    
    private func generateSecureEntropy(byteCount: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw MiningError.entropyGenerationFailed
        }
        return bytes
    }
    
    private func generateMnemonic(fromEntropy entropy: [UInt8]) throws -> [String] {
        let wordList = try loadBIP39WordList()
        let entropyBits = entropy.compactMap { byte in
            String(byte, radix: 2).padding(toLength: 8, withPad: "0", startingAt: 0)
        }.joined()
        
        var words: [String] = []
        for i in stride(from: 0, to: entropyBits.count, by: 11) {
            let endIndex = min(i + 11, entropyBits.count)
            let wordBits = String(entropyBits[entropyBits.index(entropyBits.startIndex, offsetBy: i)..<entropyBits.index(entropyBits.startIndex, offsetBy: endIndex)])
            if let index = Int(wordBits, radix: 2), index < wordList.count {
                words.append(wordList[index])
            }
        }
        
        return words
    }
    
    private func derivePrivateKey(fromMnemonic mnemonic: [String]) throws -> [UInt8] {
        let seed = try PKCS5.PBKDF2(
            password: mnemonic.joined(separator: " ").bytes,
            salt: "mnemonic".bytes,
            iterations: 2048,
            keyLength: 32,
            variant: .sha2(.sha512)
        ).calculate()
        
        return seed
    }
    
    private func createKeystoreFile(privateKey: [UInt8], password: String) throws -> String {
        let uuid = UUID().uuidString
        let address = try generateAddress(fromPrivateKey: privateKey)
        
        let keystoreFile = keystoreDirectory.appendingPathComponent("UTC--\(Date())--\(uuid)")
        try "placeholder".write(to: keystoreFile, atomically: true, encoding: .utf8)
        
        return address
    }
    
    private func generateAddress(fromPrivateKey privateKey: [UInt8]) throws -> String {
        let hexString = privateKey.prefix(20).map { String(format: "%02x", $0) }.joined()
        return "0x" + hexString
    }
    
    private func createTemporaryPasswordFile(password: String) throws -> URL {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try password.write(to: tempFile, atomically: true, encoding: .utf8)
        return tempFile
    }
    
    private func loadBIP39WordList() throws -> [String] {
        return ["abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd", "abuse",
                "access", "accident", "account", "accuse", "achieve", "acid", "acoustic", "acquire", "across", "act",
                // ... (adding more words)
                "wing", "wink", "winner", "winter", "wire", "wisdom", "wise", "wish", "witness", "wolf",
                "woman", "wonder", "wood", "wool", "word", "work", "world", "worry", "worth", "wrap",
                "wreck", "wrestle", "wrist", "write", "wrong", "yard", "year", "yellow", "you", "young",
                "youth", "zebra", "zero", "zone", "zoo"]
    }
}

enum MiningError: Error {
    case entropyGenerationFailed
    case mnemonicGenerationFailed
    case keystoreCreationFailed
} 