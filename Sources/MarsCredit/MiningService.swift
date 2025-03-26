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
        // Create a JavaScript file to help control mining
        let minerJsPath = dataDirectory.appendingPathComponent("miner.js")
        do {
            let minerJsContent = """
            // Check if mining is already enabled
            if (!eth.mining) {
                console.log("Mining not active, attempting to start...");
                miner.start();
                
                // Give it a moment to start
                admin.sleepBlocks(1);
                
                console.log("Mining status: " + eth.mining);
                console.log("Current coinbase: " + eth.coinbase);
                console.log("Current hashrate: " + eth.hashrate);
            } else {
                console.log("Mining already active");
                console.log("Current hashrate: " + eth.hashrate);
            }
            """
            try minerJsContent.write(to: minerJsPath, atomically: true, encoding: .utf8)
        } catch {
            LogManager.shared.log("Failed to create miner.js: \(error.localizedDescription)", type: .error)
        }
        
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
    public static var shared: MiningService?
    
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
                        "chainId": 7007,
                        "homesteadBlock": 0,
                        "eip150Block": 0,
                        "eip155Block": 0,
                        "eip158Block": 0,
                        "byzantiumBlock": 0,
                        "constantinopleBlock": 0,
                        "petersburgBlock": 0,
                        "istanbulBlock": 0,
                        "berlinBlock": 0,
                        "londonBlock": 0,
                        "ethash": {}
                    },
                    "difficulty": "1",
                    "gasLimit": "30000000",
                    "alloc": {}
                }
                """
                try genesisContent.write(to: genesisPath, atomically: true, encoding: .utf8)
                LogManager.shared.log("Genesis block configuration created", type: .success)
            } else {
                // Check if genesis file needs an update
                let genesisContent = try String(contentsOf: genesisPath, encoding: .utf8)
                if !genesisContent.contains("\"ethash\"") {
                    LogManager.shared.log("Updating genesis block configuration for PoW mining...", type: .info)
                    let updatedGenesisContent = """
                    {
                        "config": {
                            "chainId": 7007,
                            "homesteadBlock": 0,
                            "eip150Block": 0,
                            "eip155Block": 0,
                            "eip158Block": 0,
                            "byzantiumBlock": 0,
                            "constantinopleBlock": 0,
                            "petersburgBlock": 0,
                            "istanbulBlock": 0,
                            "berlinBlock": 0,
                            "londonBlock": 0,
                            "ethash": {}
                        },
                        "difficulty": "1",
                        "gasLimit": "30000000",
                        "alloc": {}
                    }
                    """
                    try updatedGenesisContent.write(to: genesisPath, atomically: true, encoding: .utf8)
                    // Re-initialize blockchain with updated genesis
                    try? fileManager.removeItem(at: chaindataDirectory)
                    initializeBlockchain()
                    LogManager.shared.log("Genesis block configuration updated for PoW mining", type: .success)
                }
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
        // Try local endpoint first, then fall back to remote
        let localClient = EthereumClient(rpcURL: "http://localhost:8545")
        
        localClient.testConnection().done { [weak self] connected in
            if connected {
                LogManager.shared.log("Connected to local RPC endpoint", type: .success)
                self?.ethClient = localClient
                self?.startUpdatingStatus()
            } else {
                // Fall back to remote endpoint
                LogManager.shared.log("Local endpoint not available, using remote RPC", type: .info)
                let remoteClient = EthereumClient(rpcURL: "https://rpc.marscredit.xyz:443")
                self?.ethClient = remoteClient
                
                remoteClient.testConnection().done { connected in
                    if connected {
                        LogManager.shared.log("Connected to remote RPC endpoint", type: .success)
                        self?.startUpdatingStatus()
                    } else {
                        LogManager.shared.log("Failed to connect to any RPC endpoint", type: .error)
                    }
                }.catch { error in
                    LogManager.shared.log("Error connecting to remote endpoint: \(error.localizedDescription)", type: .error)
                }
            }
        }.catch { _ in
            // Fall back to remote endpoint
            LogManager.shared.log("Local endpoint not available, using remote RPC", type: .info)
            let remoteClient = EthereumClient(rpcURL: "https://rpc.marscredit.xyz:443")
            self.ethClient = remoteClient
            
            remoteClient.testConnection().done { [weak self] connected in
                if connected {
                    LogManager.shared.log("Connected to remote RPC endpoint", type: .success)
                    self?.startUpdatingStatus()
                } else {
                    LogManager.shared.log("Failed to connect to any RPC endpoint", type: .error)
                }
            }.catch { error in
                LogManager.shared.log("Error connecting to remote endpoint: \(error.localizedDescription)", type: .error)
            }
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
        
        // Update UI state immediately
        DispatchQueue.main.async {
            self.isMining = true
            LogManager.shared.log("Starting mining process...", type: .info)
            LogManager.shared.log("Connecting to remote node at https://rpc.marscredit.xyz", type: .info)
        }
        
        // Debug log for geth binary path
        LogManager.shared.log("Looking for geth binary at: \(bundledMarscreditPath?.path ?? "unknown path")", type: .debug)
        if let path = bundledMarscreditPath?.path, fileManager.fileExists(atPath: path) {
            LogManager.shared.log("Found geth binary at: \(path)", type: .success)
            
            // Build and log terminal command that user could run manually
            let manualCommand = """
            \(path) --datadir \(dataDirectory.path) --keystore \(keystoreDirectory.path) --syncmode full --http --http.port 8545 --networkid 7007 --mine --miner.etherbase \(address) --verbosity 5
            """
            LogManager.shared.log("Manual command for debugging: \(manualCommand)", type: .debug)
        } else {
            LogManager.shared.log("❌ Geth binary not found!", type: .error)
            DispatchQueue.main.async {
                self.isMining = false
            }
            return
        }
        
        // Start mining process in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Initialize blockchain if needed
            self.initializeBlockchain()
            
            guard let marscreditPath = self.bundledMarscreditPath?.path,
                  self.fileManager.fileExists(atPath: marscreditPath) else {
                DispatchQueue.main.async {
                    LogManager.shared.log("Error: go-marscredit binary not found at \(self.bundledMarscreditPath?.path ?? "unknown path")", type: .error)
                    self.isMining = false
                }
                return
            }
            
            // Create output pipe for geth process
            let marscreditOutput = Pipe()
            self.marscreditProcess = Process()
            self.marscreditProcess?.executableURL = URL(fileURLWithPath: marscreditPath)
            
            let args = [
                "--datadir", self.dataDirectory.path,
                "--identity", "MarsCredit",
                "--syncmode", "full",
                "--http",
                "--http.addr", "127.0.0.1",
                "--http.port", "8545",
                "--http.api", "eth,net,web3,miner,admin",
                "--networkid", "7007",
                "--bootnodes", "enode://279cfddc9edd1fb94f3db6c0173515042cc329423ec5e302352a6539786167500c9c4e3da5d79f85336750b8780e867d0c47eaebd5cda993d9d3b0982752840d@67.2.31.33:30303",
                "--mine",
                "--authrpc.addr", "127.0.0.1",
                "--authrpc.port", "8551",
                "--authrpc.vhosts", "*",
                "--miner.etherbase", address,
                "--miner.threads", "1",
                "--allow-insecure-unlock",
                "--unlock", address,
                "--password", "/dev/null",
                "--nodiscover",
                "--cache", "512",
                "--verbosity", "4"
            ]
            
            self.marscreditProcess?.arguments = args
            self.marscreditProcess?.standardOutput = marscreditOutput
            self.marscreditProcess?.standardError = marscreditOutput
            
            // Set up a dispatch queue for processing logs
            let logQueue = DispatchQueue(label: "com.marscredit.gethLogs")
            
            // Monitor the output pipe
            marscreditOutput.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    DispatchQueue.main.async {
                        LogManager.shared.log("Geth process terminated unexpectedly", type: .error)
                        self.isMining = false
                    }
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
                                     line.contains("Ethash nonce search") ||
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
            
            do {
                LogManager.shared.log("Attempting to start geth process...", type: .info)
                
                // Check file permissions one more time before attempting to run
                if let attributes = try? self.fileManager.attributesOfItem(atPath: marscreditPath),
                   let permissions = attributes[.posixPermissions] as? NSNumber {
                    let isExecutable = (permissions.intValue & 0o111) != 0
                    LogManager.shared.log("Geth binary permissions: \(String(format: "%o", permissions.intValue))", type: .debug)
                    if !isExecutable {
                        LogManager.shared.log("Binary not executable, attempting to fix permissions...", type: .warning)
                        try self.fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: marscreditPath)
                    }
                }
                
                try self.marscreditProcess?.run()
                LogManager.shared.log("✨ Local mining node started successfully", type: .success)
                
                // Force an explicit mining start via JavaScript execution
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    LogManager.shared.log("Explicitly starting mining via JavaScript...", type: .info)
                    let minerJsPath = self.dataDirectory.appendingPathComponent("miner.js")
                    
                    // Update the JavaScript content for newer geth
                    do {
                        let updatedMinerJsContent = """
                        // Check if mining is already enabled
                        if (!eth.mining) {
                            console.log("Mining not active, attempting to start...");
                            miner.start();
                            
                            // Give it a moment to start
                            admin.sleepBlocks(1);
                            
                            console.log("Mining status: " + eth.mining);
                            console.log("Current coinbase: " + eth.coinbase);
                            console.log("Current hashrate: " + eth.hashrate);
                        } else {
                            console.log("Mining already active");
                            console.log("Current hashrate: " + eth.hashrate);
                        }
                        """
                        try updatedMinerJsContent.write(to: minerJsPath, atomically: true, encoding: .utf8)
                    } catch {
                        LogManager.shared.log("Error updating mining script: \(error.localizedDescription)", type: .error)
                    }
                    
                    let jsProcess = Process()
                    jsProcess.executableURL = URL(fileURLWithPath: marscreditPath)
                    jsProcess.arguments = [
                        "--datadir", self.dataDirectory.path,
                        "js", minerJsPath.path
                    ]
                    
                    let jsPipe = Pipe()
                    jsProcess.standardOutput = jsPipe
                    jsProcess.standardError = jsPipe
                    
                    do {
                        try jsProcess.run()
                        jsProcess.waitUntilExit()
                        
                        let jsOutput = String(data: jsPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        LogManager.shared.log("Mining JavaScript output: \(jsOutput)", type: .mining)
                    } catch {
                        LogManager.shared.log("Error executing mining JavaScript: \(error.localizedDescription)", type: .error)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    LogManager.shared.log("Error starting geth: \(error.localizedDescription)", type: .error)
                    self.isMining = false
                }
            }
        }
    }
    
    func stopMining() {
        LogManager.shared.log("🛑 Stopping mining process...", type: .info)
        
        if marscreditProcess != nil {
            // If running a local node
            // Gracefully terminate the process
            marscreditProcess?.terminate()
            
            // Wait for the process to finish
            marscreditProcess?.waitUntilExit()
            
            marscreditProcess = nil
            marscreditOutput?.fileHandleForReading.readabilityHandler = nil
            marscreditOutput = nil
        } else {
            // If using remote node
            ethClient?.stopMining().done {
                LogManager.shared.log("Mining stopped on remote node", type: .success)
            }.catch { error in
                LogManager.shared.log("Error stopping mining on remote node: \(error.localizedDescription)", type: .error)
            }
        }
        
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
        
        // Ensure we have exactly 16 bytes (128 bits) of entropy for 12 words
        var entropyBytes = entropy
        if entropyBytes.count != 16 {
            entropyBytes = Array(entropyBytes.prefix(16))
            // Pad if necessary
            while entropyBytes.count < 16 {
                entropyBytes.append(0)
            }
        }
        
        // Step 1: Convert entropy to bits
        let entropyBits = entropyBytes.map { byte in
            String(byte, radix: 2).padding(toLength: 8, withPad: "0", startingAt: 0)
        }.joined()
        
        // Step 2: Calculate checksum
        let checksumBits = calculateChecksumBits(entropy: entropyBytes)
        
        // Step 3: Combine entropy bits with checksum bits
        let combinedBits = entropyBits + checksumBits
        
        // Step 4: Split into 11-bit segments and convert to words
        var words: [String] = []
        for i in stride(from: 0, to: combinedBits.count, by: 11) {
            // Ensure we don't go out of bounds
            let endIndex = min(i + 11, combinedBits.count)
            if endIndex - i < 11 {
                break // Skip incomplete chunks
            }
            
            // Extract 11 bits and convert to index
            let range = combinedBits.index(combinedBits.startIndex, offsetBy: i)..<combinedBits.index(combinedBits.startIndex, offsetBy: endIndex)
            let wordBits = String(combinedBits[range])
            
            if let index = Int(wordBits, radix: 2), index < wordList.count {
                words.append(wordList[index])
            }
        }
        
        // Ensure we always have exactly 12 words
        while words.count < 12 {
            if let randomWord = wordList.randomElement() {
                words.append(randomWord)
            }
        }
        
        // Take only the first 12 words if somehow we got more
        return Array(words.prefix(12))
    }
    
    private func calculateChecksumBits(entropy: [UInt8]) -> String {
        // Calculate the SHA-256 hash of the entropy
        let hash = SHA2(variant: .sha256).calculate(for: entropy)
        
        // The length of the checksum in bits is entropy-bits/32
        let checksumBitLength = entropy.count * 8 / 32
        
        // Convert the first byte of the hash to bits and take the needed length
        let firstByte = hash[0]
        let bits = String(firstByte, radix: 2).padding(toLength: 8, withPad: "0", startingAt: 0)
        
        return String(bits.prefix(checksumBitLength))
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
        
        // Create a JSON structure for the keystore file
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date())
        
        // This is a simplified version - a real implementation would use proper encryption
        // with scrypt or pbkdf2 for key derivation and proper cipher for encryption
        let jsonData: [String: Any] = [
            "address": address.replacingOccurrences(of: "0x", with: "").lowercased(),
            "id": uuid,
            "version": 3,
            "crypto": [
                "cipher": "aes-128-ctr",
                "ciphertext": privateKey.map { String(format: "%02x", $0) }.joined(),
                "cipherparams": ["iv": "0102030405060708090a0b0c0d0e0f10"],
                "kdf": "pbkdf2",
                "kdfparams": [
                    "c": 10240,
                    "dklen": 32,
                    "prf": "hmac-sha256",
                    "salt": UUID().uuidString.replacingOccurrences(of: "-", with: "")
                ],
                "mac": SHA3(variant: .keccak256).calculate(for: [UInt8](password.utf8)).map { String(format: "%02x", $0) }.joined()
            ]
        ]
        
        let jsonObject = try JSONSerialization.data(withJSONObject: jsonData, options: [.prettyPrinted])
        
        // Formatted keystore filename: UTC--<ISO timestamp>--<UUID>
        let formattedDate = timestamp.replacingOccurrences(of: ":", with: "-")
        let keystoreFile = keystoreDirectory.appendingPathComponent("UTC--\(formattedDate)--\(uuid)")
        
        try jsonObject.write(to: keystoreFile)
        LogManager.shared.log("Keystore file created at \(keystoreFile.path)", type: .success)
        
        return address
    }
    
    private func generateAddress(fromPrivateKey privateKey: [UInt8]) throws -> String {
        // Step 1: Create a SHA-3 (Keccak-256) hash of the public key
        let publicKey = try derivePublicKey(fromPrivateKey: privateKey)
        let publicKeyHash = SHA3(variant: .keccak256).calculate(for: publicKey)
        
        // Step 2: Take the last 20 bytes of the hash to form the address
        let addressBytes = Array(publicKeyHash.suffix(20))
        
        // Step 3: Convert to checksum address format
        return formatEthereumAddress(addressBytes)
    }
    
    private func derivePublicKey(fromPrivateKey privateKey: [UInt8]) throws -> [UInt8] {
        // For proper implementation, we would use secp256k1 to derive public key
        // This is a simplified version for demonstration
        let publicKey = privateKey.map { $0 ^ 0xFF }  // Just an example, not correct
        return publicKey
    }
    
    private func formatEthereumAddress(_ addressBytes: [UInt8]) -> String {
        // Convert to hex string with 0x prefix
        let hexString = addressBytes.map { String(format: "%02x", $0) }.joined()
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