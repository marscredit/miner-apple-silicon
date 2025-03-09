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
    
    // Directory structure
    var keystoreDirectory: URL {
        dataDirectory.appendingPathComponent("keystore")
    }
    
    var dataDirectory: URL {
        homeDirectory.appendingPathComponent(".marscredit")
    }
    
    var chaindataDirectory: URL {
        dataDirectory.appendingPathComponent("geth/chaindata")
    }
    
    var ethashDirectory: URL {
        dataDirectory.appendingPathComponent(".ethash")
    }
    
    var nodekeyPath: URL {
        dataDirectory.appendingPathComponent("geth/nodekey")
    }
    
    private var bundledMarscreditPath: URL? {
        dataDirectory.appendingPathComponent("geth-binary")
    }
    
    init() {
        setupDirectoryStructure()
        setupEthereumClient()
        startLatestBlockPolling()
        
        // Set up signal handling for graceful shutdown
        signal(SIGTERM) { _ in
            MiningService.shared?.stopMining()
            exit(0)
        }
        
        signal(SIGINT) { _ in
            MiningService.shared?.stopMining()
            exit(0)
        }
    }
    
    // Singleton instance for signal handling
    private static var shared: MiningService?
    
    private func setupDirectoryStructure() {
        do {
            // Create all required directories
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: keystoreDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: chaindataDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: ethashDirectory, withIntermediateDirectories: true)
            
            // Set proper permissions
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dataDirectory.path)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: keystoreDirectory.path)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: chaindataDirectory.path)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ethashDirectory.path)
            
            LogManager.shared.log("Created and configured data directories", type: .success)
            
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
            
            // Generate nodekey if it doesn't exist
            if !fileManager.fileExists(atPath: nodekeyPath.path) {
                let nodekey = try generateSecureEntropy(byteCount: 32)
                    .map { String(format: "%02x", $0) }
                    .joined()
                try nodekey.write(to: nodekeyPath, atomically: true, encoding: .utf8)
                LogManager.shared.log("Generated new node key", type: .success)
            }
        } catch {
            LogManager.shared.log("Error setting up directory structure: \(error.localizedDescription)", type: .error)
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
        
        // Only initialize if chaindata is empty
        if let contents = try? fileManager.contentsOfDirectory(atPath: chaindataDirectory.path),
           !contents.isEmpty {
            LogManager.shared.log("Using existing blockchain data", type: .info)
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
        
        LogManager.shared.log("Starting mining process...", type: .info)
        
        // Initialize blockchain if needed
        initializeBlockchain()
        
        guard let marscreditPath = bundledMarscreditPath?.path,
              fileManager.fileExists(atPath: marscreditPath) else {
            LogManager.shared.log("Error: go-marscredit binary not found at \(bundledMarscreditPath?.path ?? "unknown path")", type: .error)
            return
        }
        
        LogManager.shared.log("Starting mining process with binary: \(marscreditPath)", type: .info)
        LogManager.shared.log("Data directory: \(dataDirectory.path)", type: .debug)
        LogManager.shared.log("Keystore directory: \(keystoreDirectory.path)", type: .debug)
        LogManager.shared.log("Mining address: \(address)", type: .debug)
        
        marscreditProcess = Process()
        marscreditOutput = Pipe()
        
        marscreditProcess?.executableURL = URL(fileURLWithPath: marscreditPath)
        
        let args = [
            "--datadir", dataDirectory.path,
            "--keystore", keystoreDirectory.path,
            "--syncmode", "full",
            "--http",
            "--http.addr", "0.0.0.0",
            "--http.port", "8545",
            "--http.api", "personal,eth,net,web3,miner,admin",
            "--http.vhosts", "*",
            "--http.corsdomain", "*",
            "--networkid", "110110",
            "--ws",
            "--ws.addr", "0.0.0.0",
            "--ws.port", "8546",
            "--ws.api", "personal,eth,net,web3,miner,admin",
            "--ws.origins", "*",
            "--port", "30304",
            "--nat", "any",
            "--mine",
            "--miner.threads", "1",
            "--miner.etherbase", address,
            "--bootnodes", "enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138",
            "--maxpeers", "50",
            "--cache", "2048",
            "--verbosity", "5",
            "--metrics",
            "--pprof",
            "--pprof.addr", "0.0.0.0",
            "--pprof.port", "6060",
            "--nodekey", nodekeyPath.path,
            "--ethash.dagdir", ethashDirectory.path
        ]
        
        marscreditProcess?.arguments = args
        
        LogManager.shared.log("Starting geth with command:", type: .debug)
        LogManager.shared.log("\(marscreditPath) \(args.joined(separator: " "))", type: .debug)
        
        marscreditProcess?.standardOutput = marscreditOutput
        marscreditProcess?.standardError = marscreditOutput
        
        // Set up a dispatch queue for processing logs
        let logQueue = DispatchQueue(label: "com.marscredit.gethLogs")
        
        // Monitor the output pipe
        marscreditOutput?.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                LogManager.shared.log("Geth process terminated unexpectedly", type: .error)
                return
            }
            
            if let output = String(data: data, encoding: .utf8) {
                logQueue.async {
                    // Split the output into lines and process each one
                    output.components(separatedBy: .newlines).forEach { line in
                        guard !line.isEmpty else { return }
                        
                        // Determine log type based on content but keep full message
                        let logType: LogType
                        if line.contains("ERROR") || line.contains("error") {
                            logType = .error
                        } else if line.contains("WARN") || line.contains("warn") {
                            logType = .warning
                        } else if line.contains("Successfully sealed new block") || 
                                line.contains("🔨 mined potential block") ||
                                line.contains("Commit new mining work") ||
                                line.contains("Mining") ||
                                line.contains("miner") {
                            logType = .mining
                        } else if line.contains("INFO") || line.contains("info") {
                            logType = .info
                        } else {
                            logType = .debug
                        }
                        
                        // Add a prefix to easily identify different types of messages
                        let prefix: String
                        switch logType {
                        case .error:   prefix = "❌ [ERROR] "
                        case .warning: prefix = "⚠️ [WARN] "
                        case .mining:  prefix = "⛏️ [MINE] "
                        case .info:    prefix = "ℹ️ [INFO] "
                        case .debug:   prefix = "🔍 [DEBUG] "
                        case .success: prefix = "✅ [SUCCESS] "
                        }
                        
                        // Post to main thread for UI update
                        DispatchQueue.main.async {
                            LogManager.shared.log(prefix + line, type: logType)
                        }
                    }
                }
            }
        }
        
        // Set up termination handler
        marscreditProcess?.terminationHandler = { process in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isMining = false
                LogManager.shared.log("Geth process terminated with status: \(process.terminationStatus)", type: .info)
                if process.terminationStatus != 0 {
                    LogManager.shared.log("Node stopped with error code \(process.terminationStatus). Check logs for details.", type: .error)
                }
                
                // Clean up
                self.marscreditOutput?.fileHandleForReading.readabilityHandler = nil
                self.marscreditOutput = nil
                self.marscreditProcess = nil
            }
        }
        
        do {
            LogManager.shared.log("Attempting to start geth process...", type: .info)
            try marscreditProcess?.run()
            isMining = true
            LogManager.shared.log("✨ Mining process started successfully", type: .success)
            updateNetworkStatus()
        } catch {
            LogManager.shared.log("❌ Error starting mining process: \(error.localizedDescription)", type: .error)
            // Clean up on error
            marscreditOutput?.fileHandleForReading.readabilityHandler = nil
            marscreditOutput = nil
            marscreditProcess = nil
        }
    }
    
    func stopMining() {
        LogManager.shared.log("🛑 Stopping mining process...", type: .info)
        
        // Gracefully terminate the process
        marscreditProcess?.terminate()
        
        // Wait for the process to finish
        marscreditProcess?.waitUntilExit()
        
        marscreditProcess = nil
        marscreditOutput?.fileHandleForReading.readabilityHandler = nil
        marscreditOutput = nil
        isMining = false
        currentHashRate = 0
        LogManager.shared.log("✅ Mining stopped successfully", type: .success)
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
        MiningService.shared = nil
    }
}

enum MiningError: Error {
    case entropyGenerationFailed
    case mnemonicGenerationFailed
    case keystoreCreationFailed
} 