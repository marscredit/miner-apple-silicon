import Foundation
import CryptoSwift
import PromiseKit
import BigInt

struct NetworkStatus {
    let syncProgress: Double
    let currentBlock: BigInt
    let highestBlock: BigInt
    let isConnected: Bool
}

class MiningService: ObservableObject {
    @Published private(set) var isMining = false
    @Published private(set) var currentHashRate: Double = 0.0
    @Published private(set) var networkStatus = NetworkStatus(syncProgress: 0, currentBlock: 0, highestBlock: 0, isConnected: false)
    @Published private(set) var currentBalance: Double = 0.0
    
    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var ethClient: EthereumClient?
    private var updateTimer: Timer?
    private var latestBlockTimer: Timer?
    private var latestBlockNumber: BigInt = 0
    private var marscreditProcess: Process?
    private var marscreditOutput: Pipe?
    
    var keystoreDirectory: URL {
        homeDirectory.appendingPathComponent(".marscredit/keystore")
    }
    
    var dataDirectory: URL {
        homeDirectory.appendingPathComponent(".marscredit")
    }
    
    private var bundledMarscreditPath: URL? {
        dataDirectory.appendingPathComponent("geth-binary")
    }
    
    init() {
        setupDataDirectory()
        setupEthereumClient()
        startLatestBlockPolling()
    }
    
    private func setupDataDirectory() {
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: keystoreDirectory, withIntermediateDirectories: true)
            LogManager.shared.log("Created data directories", type: .success)
            
            // Copy genesis block if it doesn't exist
            let genesisPath = dataDirectory.appendingPathComponent("genesis.json")
            if !fileManager.fileExists(atPath: genesisPath.path) {
                LogManager.shared.log("Creating genesis block configuration...", type: .info)
                let genesisContent = """
                {
                    "config": {
                        "chainId": 110110,
                        "homesteadBlock": 0,
                        "eip150Block": 0,
                        "eip155Block": 0,
                        "eip158Block": 0,
                        "byzantiumBlock": 0,
                        "constantinopleBlock": 0,
                        "petersburgBlock": 0,
                        "istanbulBlock": 0,
                        "berlinBlock": 0,
                        "londonBlock": 0
                    },
                    "difficulty": "1",
                    "gasLimit": "8000000",
                    "alloc": {}
                }
                """
                try genesisContent.write(to: genesisPath, atomically: true, encoding: .utf8)
                LogManager.shared.log("Genesis block configuration created", type: .success)
            }
        } catch {
            LogManager.shared.log("Error setting up data directory: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func setupEthereumClient() {
        ethClient = EthereumClient(rpcURL: "http://localhost:8545")
        
        // Test connection and start updating status
        ethClient?.testConnection().done { [weak self] connected in
            self?.startUpdatingStatus()
        }.catch { error in
            print("Failed to connect to local node: \(error)")
        }
    }
    
    private func initializeBlockchain() {
        guard let marscreditPath = bundledMarscreditPath?.path,
              fileManager.fileExists(atPath: marscreditPath) else {
            LogManager.shared.log("Error: go-marscredit binary not found", type: .error)
            return
        }
        
        LogManager.shared.log("Initializing blockchain...", type: .info)
        let initProcess = Process()
        initProcess.executableURL = URL(fileURLWithPath: marscreditPath)
        initProcess.arguments = [
            "--datadir", dataDirectory.path,
            "init",
            dataDirectory.appendingPathComponent("genesis.json").path
        ]
        
        do {
            try initProcess.run()
            initProcess.waitUntilExit()
            LogManager.shared.log("Blockchain initialized successfully", type: .success)
        } catch {
            LogManager.shared.log("Error initializing blockchain: \(error.localizedDescription)", type: .error)
        }
    }
    
    private func startLatestBlockPolling() {
        latestBlockTimer?.invalidate()
        latestBlockTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateLatestBlock()
        }
        latestBlockTimer?.fire()
    }
    
    private func updateLatestBlock() {
        guard let client = ethClient else { return }
        
        firstly {
            client.getLatestBlock()
        }.done { [weak self] blockNumber in
            self?.latestBlockNumber = blockNumber
        }.catch { error in
            print("Failed to get latest block: \(error)")
        }
    }
    
    private func startUpdatingStatus() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateNetworkStatus()
        }
        updateTimer?.fire()
    }
    
    private func updateNetworkStatus() {
        guard let client = ethClient else { return }
        
        firstly {
            client.getSyncStatus()
        }.done { [weak self] result in
            guard let self = self else { return }
            
            let progress: Double
            if self.latestBlockNumber > 0 {
                progress = Double(result.currentBlock) / Double(self.latestBlockNumber)
            } else {
                progress = result.progress
            }
            
            self.networkStatus = NetworkStatus(
                syncProgress: progress,
                currentBlock: result.currentBlock,
                highestBlock: self.latestBlockNumber,
                isConnected: true
            )
            
            // Update balance for the fixed address
            self.updateBalance(address: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e")
        }.catch { error in
            print("Failed to update network status: \(error)")
        }
        
        if isMining {
            firstly {
                client.getHashRate()
            }.done { [weak self] hashRate in
                self?.currentHashRate = Double(hashRate) / 1_000_000 // Convert to MH/s
            }.catch { error in
                print("Failed to update hash rate: \(error)")
            }
        }
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
    
    func startMining(address: String, password: String) {
        guard !isMining else { return }
        
        // Initialize blockchain if needed
        if !fileManager.fileExists(atPath: dataDirectory.appendingPathComponent("geth/chaindata").path) {
            initializeBlockchain()
        }
        
        guard let marscreditPath = bundledMarscreditPath?.path,
              fileManager.fileExists(atPath: marscreditPath) else {
            LogManager.shared.log("Error: go-marscredit binary not found", type: .error)
            return
        }
        
        LogManager.shared.log("Starting mining process...", type: .info)
        marscreditProcess = Process()
        marscreditOutput = Pipe()
        
        marscreditProcess?.executableURL = URL(fileURLWithPath: marscreditPath)
        marscreditProcess?.arguments = [
            "--datadir", dataDirectory.path,
            "--keystore", keystoreDirectory.path,
            "--syncmode", "full",
            "--http",
            "--http.addr", "127.0.0.1",
            "--http.port", "8545",
            "--http.api", "personal,eth,net,web3,miner,admin",
            "--http.vhosts", "*",
            "--http.corsdomain", "*",
            "--networkid", "110110",
            "--ws",
            "--ws.addr", "127.0.0.1",
            "--ws.port", "8546",
            "--port", "30304",
            "--nat", "any",
            "--mine",
            "--miner.threads", "1",
            "--miner.etherbase", address,
            "--bootnodes", "enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138",
            "--maxpeers", "50",
            "--cache", "2048",
            "--verbosity", "6"
        ]
        
        marscreditProcess?.standardOutput = marscreditOutput
        marscreditProcess?.standardError = marscreditOutput
        
        // Monitor the output pipe
        marscreditOutput?.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                LogManager.shared.log(output, type: .mining)
            }
        }
        
        do {
            try marscreditProcess?.run()
            isMining = true
            LogManager.shared.log("Mining started successfully", type: .success)
            updateNetworkStatus()
        } catch {
            LogManager.shared.log("Error starting mining process: \(error.localizedDescription)", type: .error)
        }
    }
    
    func stopMining() {
        LogManager.shared.log("Stopping mining process...", type: .info)
        marscreditProcess?.terminate()
        marscreditProcess = nil
        marscreditOutput?.fileHandleForReading.readabilityHandler = nil
        marscreditOutput = nil
        isMining = false
        currentHashRate = 0
        LogManager.shared.log("Mining stopped", type: .success)
    }
    
    func updateBalance(address: String) {
        guard let client = ethClient else { return }
        
        firstly {
            client.getBalance(address: address)
        }.done { [weak self] balance in
            self?.currentBalance = Double(balance) / 1e18 // Convert from wei to MARS
        }.catch { error in
            print("Failed to update balance: \(error)")
        }
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
    
    private func loadBIP39WordList() throws -> [String] {
        return [
            "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd", "abuse",
            "access", "accident", "account", "accuse", "achieve", "acid", "acoustic", "acquire", "across", "act",
            "action", "actor", "actress", "actual", "adapt", "add", "addict", "address", "adjust", "admit",
            "adult", "advance", "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
            "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album", "alcohol", "alert",
            "alien", "all", "alley", "allow", "almost", "alone", "alpha", "already", "also", "alter",
            "always", "amateur", "amazing", "among", "amount", "amused", "analyst", "anchor", "ancient", "anger",
            "angle", "angry", "animal", "ankle", "announce", "annual", "another", "answer", "antenna", "antique",
            "anxiety", "any", "apart", "apology", "appear", "apple", "approve", "april", "arch", "arctic",
            "area", "arena", "argue", "arm", "armed", "armor", "army", "around", "arrange", "arrest",
            "arrive", "arrow", "art", "artefact", "artist", "artwork", "ask", "aspect", "assault", "asset",
            "assist", "assume", "asthma", "athlete", "atom", "attack", "attend", "attitude", "attract", "auction",
            "audit", "august", "aunt", "author", "auto", "autumn", "average", "avocado", "avoid", "awake",
            "aware", "away", "awesome", "awful", "awkward", "axis", "baby", "bachelor", "bacon", "badge",
            "bag", "balance", "balcony", "ball", "bamboo", "banana", "banner", "bar", "barely", "bargain",
            "barrel", "base", "basic", "basket", "battle", "beach", "bean", "beauty", "because", "become",
            "beef", "before", "begin", "behave", "behind", "believe", "below", "belt", "bench", "benefit"
            // ... Add more words as needed to complete the 2048 BIP39 word list
        ]
    }
    
    deinit {
        stopMining()
    }
}

enum MiningError: Error {
    case entropyGenerationFailed
    case mnemonicGenerationFailed
    case keystoreCreationFailed
} 