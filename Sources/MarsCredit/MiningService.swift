import Foundation
import CryptoSwift
import PromiseKit
import BigInt

struct NetworkStatus {
    var currentBlock: BigInt
    var highestBlock: BigInt
    var isConnected: Bool
}

class MiningService: ObservableObject {
    @Published private(set) var isMining = false
    @Published private(set) var currentHashRate: Double = 0.0
    @Published private(set) var networkStatus = NetworkStatus(currentBlock: 0, highestBlock: 0, isConnected: false)
    @Published private(set) var currentBalance: Double = 0.0
    @Published private(set) var miningAddress: String = ""
    @Published private(set) var averageBlockTime: Double = 0.0
    @Published private(set) var blocksFound: Int = 0
    @Published private(set) var connectionAttempts: Int = 0
    
    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var ethClient: EthereumClient?
    private var updateTimer: Timer?
    private var latestBlockTimer: Timer?
    private var reconnectTimer: Timer?
    private var latestBlockNumber: BigInt = 0
    private var marscreditProcess: Process?
    private var marscreditOutput: Pipe?
    private var lastBlockTimestamps: [TimeInterval] = []
    private var lastConnectionAttempt: Date?
    private var isReconnecting = false
    
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
        
        // Set up reconnection timer
        setupReconnectionTimer()
        
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
                        "londonBlock": 0,
                        "ethash": {}
                    },
                    "nonce": "0x0000000000000042",
                    "timestamp": "0x0",
                    "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
                    "extraData": "0x",
                    "gasLimit": "0x1c9c380",
                    "difficulty": "0x400",
                    "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
                    "coinbase": "0x0000000000000000000000000000000000000000",
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
                            "londonBlock": 0,
                            "ethash": {}
                        },
                        "nonce": "0x0000000000000042",
                        "timestamp": "0x0",
                        "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
                        "extraData": "0x",
                        "gasLimit": "0x1c9c380",
                        "difficulty": "0x400",
                        "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
                        "coinbase": "0x0000000000000000000000000000000000000000",
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
        connectionAttempts += 1
        lastConnectionAttempt = Date()
        
        // Try local endpoint first, then fall back to remote
        let localClient = EthereumClient(rpcURL: "http://localhost:8546")
        
        localClient.testConnection().done { [weak self] connected in
            guard let self = self else { return }
            
            if connected {
                LogManager.shared.log("Connected to local RPC endpoint", type: .success)
                self.ethClient = localClient
                self.startUpdatingStatus()
                self.isReconnecting = false
            } else {
                // Fall back to remote endpoint
                LogManager.shared.log("Local endpoint not available, using remote RPC", type: .info)
                let remoteClient = EthereumClient(rpcURL: "https://rpc.marscredit.xyz:443")
                self.ethClient = remoteClient
                
                remoteClient.testConnection().done { connected in
                    if connected {
                        LogManager.shared.log("Connected to remote RPC endpoint - Mars Credit network (ID: 110110)", type: .success)
                        self.startUpdatingStatus()
                        self.isReconnecting = false
                    } else {
                        LogManager.shared.log("Failed to connect to any RPC endpoint", type: .error)
                        self.scheduleReconnection()
                    }
                }.catch { error in
                    LogManager.shared.log("Error connecting to remote endpoint: \(error.localizedDescription)", type: .error)
                    self.scheduleReconnection()
                }
            }
        }.catch { [weak self] _ in
            guard let self = self else { return }
            
            // Fall back to remote endpoint
            LogManager.shared.log("Local endpoint not available, using remote RPC", type: .info)
            let remoteClient = EthereumClient(rpcURL: "https://rpc.marscredit.xyz:443")
            self.ethClient = remoteClient
            
            remoteClient.testConnection().done { connected in
                if connected {
                    LogManager.shared.log("Connected to remote RPC endpoint - Mars Credit network (ID: 110110)", type: .success)
                    self.startUpdatingStatus()
                    self.isReconnecting = false
                } else {
                    LogManager.shared.log("Failed to connect to any RPC endpoint", type: .error)
                    self.scheduleReconnection()
                }
            }.catch { error in
                LogManager.shared.log("Error connecting to remote endpoint: \(error.localizedDescription)", type: .error)
                self.scheduleReconnection()
            }
        }
    }
    
    private func setupReconnectionTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Check if we need to reconnect
            if self.ethClient == nil || !self.networkStatus.isConnected {
                if !self.isReconnecting {
                    self.scheduleReconnection()
                }
            }
        }
    }
    
    private func scheduleReconnection() {
        // Avoid multiple reconnection attempts in quick succession
        guard !isReconnecting, 
              lastConnectionAttempt == nil || Date().timeIntervalSince(lastConnectionAttempt!) > 10 else {
            return
        }
        
        isReconnecting = true
        LogManager.shared.log("Scheduling reconnection attempt...", type: .info)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            LogManager.shared.log("Attempting to reconnect...", type: .info)
            self.setupEthereumClient()
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
        
        LogManager.shared.log("Initializing blockchain with genesis.json...", type: .info)
        let initProcess = Process()
        initProcess.executableURL = URL(fileURLWithPath: marscreditPath)
        initProcess.arguments = [
            "--datadir", dataDirectory.path,
            "init",
            dataDirectory.appendingPathComponent("genesis.json").path
        ]
        
        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        initProcess.standardOutput = outputPipe
        initProcess.standardError = errorPipe
        
        do {
            try initProcess.run()
            
            // Log output in real-time
            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            
            let outputData = outputHandle.readDataToEndOfFile()
            let errorData = errorHandle.readDataToEndOfFile()
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                LogManager.shared.log("Init output: \(output)", type: .debug)
            }
            
            if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                LogManager.shared.log("Init error: \(error)", type: .error)
            }
            
            initProcess.waitUntilExit()
            
            if initProcess.terminationStatus == 0 {
                LogManager.shared.log("Blockchain initialized successfully", type: .success)
            } else {
                LogManager.shared.log("Blockchain initialization failed with exit code: \(initProcess.terminationStatus)", type: .error)
                
                // Check genesis.json for potential issues
                if let genesisPath = try? String(contentsOf: dataDirectory.appendingPathComponent("genesis.json")),
                   !genesisPath.isEmpty {
                    LogManager.shared.log("Checking genesis.json content...", type: .debug)
                    LogManager.shared.log(genesisPath, type: .debug)
                } else {
                    LogManager.shared.log("Genesis.json missing or empty", type: .error)
                }
                
                // Use JSONSerialization to validate the JSON format
                do {
                    let genesisData = try Data(contentsOf: dataDirectory.appendingPathComponent("genesis.json"))
                    _ = try JSONSerialization.jsonObject(with: genesisData, options: [])
                    LogManager.shared.log("Genesis.json is valid JSON", type: .debug)
                } catch {
                    LogManager.shared.log("Genesis.json is invalid: \(error.localizedDescription)", type: .error)
                }
                
                // Try one more time with a simplified genesis
                let simpleGenesisContent = """
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
                        "londonBlock": 0,
                        "ethash": {}
                    },
                    "nonce": "0x0000000000000042",
                    "timestamp": "0x0",
                    "extraData": "0x",
                    "gasLimit": "0x1c9c380",
                    "difficulty": "0x400",
                    "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
                    "coinbase": "0x0000000000000000000000000000000000000000",
                    "alloc": {}
                }
                """
                
                let genesisRetryPath = dataDirectory.appendingPathComponent("genesis_retry.json")
                try? simpleGenesisContent.write(to: genesisRetryPath, atomically: true, encoding: .utf8)
                
                // Try initialization with the retry version
                let retryProcess = Process()
                retryProcess.executableURL = URL(fileURLWithPath: marscreditPath)
                retryProcess.arguments = [
                    "--datadir", dataDirectory.path,
                    "init",
                    genesisRetryPath.path
                ]
                
                LogManager.shared.log("Retrying initialization with simplified genesis...", type: .info)
                
                let retryOutputPipe = Pipe()
                retryProcess.standardOutput = retryOutputPipe
                retryProcess.standardError = retryOutputPipe
                
                try? retryProcess.run()
                retryProcess.waitUntilExit()
                
                let retryOutput = String(data: retryOutputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                LogManager.shared.log("Retry output: \(retryOutput)", type: .debug)
                
                if retryProcess.terminationStatus == 0 {
                    LogManager.shared.log("Blockchain initialization succeeded on retry", type: .success)
                } else {
                    LogManager.shared.log("Blockchain initialization failed on retry with exit code: \(retryProcess.terminationStatus)", type: .error)
                }
            }
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
        guard let client = ethClient else { 
            // No client available, schedule reconnection
            if !isReconnecting {
                scheduleReconnection()
            }
            return 
        }
        
        // Check if we're running a local node or using a remote RPC
        let isLocalNode = marscreditProcess != nil && client.rpcURL.contains("localhost")
        
        // Update mining status directly from geth when possible
        if isMining && isLocalNode {
            updateGethStatus()
        }
        
        client.getSyncStatus().done { [weak self] result in
            guard let self = self else { return }
            
            // Store the values
            let currentBlock = result.currentBlock
            let highestBlock = result.highestBlock
            
            // Track block timestamps for average calculation
            if let lastKnownBlock = self.networkStatus.currentBlock as? BigInt, 
               currentBlock > lastKnownBlock {
                self.lastBlockTimestamps.append(Date().timeIntervalSince1970)
                
                // Limit the array to the last 10 blocks for the average
                if self.lastBlockTimestamps.count > 10 {
                    self.lastBlockTimestamps.removeFirst()
                }
                
                // Calculate average block time if we have at least 2 timestamps
                if self.lastBlockTimestamps.count >= 2 {
                    let times = self.lastBlockTimestamps
                    var totalTime: TimeInterval = 0
                    
                    for i in 1..<times.count {
                        totalTime += times[i] - times[i-1]
                    }
                    
                    let avgTime = totalTime / Double(times.count - 1)
                    self.averageBlockTime = avgTime
                }
            }
            
            // Calculate sync progress - ensure we have a valid value
            let progress: Double
            
            if isLocalNode {
                // When using local node, we need to track sync progress
                if highestBlock > 0 {
                    progress = Double(currentBlock) / Double(highestBlock)
                } else if self.latestBlockNumber > 0 {
                    progress = Double(currentBlock) / Double(self.latestBlockNumber)
                } else {
                    progress = 0
                }
                
                // For local nodes, we always show sync status until we reach the network height
                let isSyncing = currentBlock < self.latestBlockNumber
                
                DispatchQueue.main.async {
                    self.networkStatus = NetworkStatus(
                        currentBlock: currentBlock,
                        highestBlock: self.latestBlockNumber,
                        isConnected: true
                    )
                }
            } else {
                // When using remote node, we're already at network height
                DispatchQueue.main.async {
                    self.networkStatus = NetworkStatus(
                        currentBlock: currentBlock,
                        highestBlock: currentBlock, // Same as current block
                        isConnected: true
                    )
                }
            }
            
            // Update balance for the mining address if we have one
            if !self.miningAddress.isEmpty {
                self.updateBalance(address: self.miningAddress)
            } else {
                // Fallback to a default address if necessary
                self.updateBalance(address: "0x742d35Cc6634C0532925a3b844Bc454e4438f44e")
            }
        }.catch { [weak self] error in
            guard let self = self else { return }
            print("Failed to update network status: \(error)")
            
            // Mark as disconnected on error
            DispatchQueue.main.async {
                var currentStatus = self.networkStatus
                currentStatus.isConnected = false
                self.networkStatus = currentStatus
            }
            
            if !self.isReconnecting {
                self.scheduleReconnection()
            }
        }
        
        // Get latest block separately to ensure we always have the most current network height
        client.getLatestBlock().done { [weak self] blockNumber in
            guard let self = self else { return }
            self.latestBlockNumber = blockNumber
        }.catch { [weak self] error in
            print("Failed to get latest block: \(error)")
            // No need to take action here since the sync status call will handle reconnection
        }
        
        if isMining {
            client.getHashRate().done { [weak self] hashRate in
                self?.currentHashRate = Double(hashRate) / 1_000_000 // Convert to MH/s
                
                // Only log significant hashrate changes
                if let self = self, hashRate > 0 {
                    LogManager.shared.log("Mining hashrate: \(Double(hashRate) / 1_000_000) MH/s", type: .mining)
                }
            }.catch { [weak self] error in
                print("Failed to update hash rate: \(error)")
                
                // Fallback to direct mining hashrate retrieval using admin module
                self?.updateDirectHashrate()
            }
        }
    }
    
    private func updateGethStatus() {
        guard let client = ethClient else { return }
        
        // Use admin.nodeInfo to get detailed node status
        client.executeJS(script: "admin.nodeInfo").done { result in
            guard !result.isEmpty else { return }
            LogManager.shared.log("Node info received, parsing status", type: .debug)
            
            // Try to extract network ID to confirm we're on the right network
            if result.contains("\"network\":110110") {
                LogManager.shared.log("Confirmed on Mars Credit network (ID: 110110)", type: .success)
            }
        }.catch { error in
            LogManager.shared.log("Failed to get node info: \(error)", type: .debug)
        }
    }
    
    private func updateDirectHashrate() {
        guard let client = ethClient else { return }
        
        // Try to get hashrate directly using eth.hashrate
        client.executeJS(script: "eth.hashrate").done { [weak self] result in
            guard let self = self, !result.isEmpty else { return }
            
            if let hashRate = Double(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
                DispatchQueue.main.async {
                    self.currentHashRate = hashRate / 1_000_000 // Convert to MH/s
                }
                LogManager.shared.log("Direct hashrate: \(hashRate / 1_000_000) MH/s", type: .mining)
            }
        }.catch { error in
            // Try another approach using miner.getHashrate
            client.executeJS(script: "miner.getHashrate()").done { [weak self] result in
                guard let self = self, !result.isEmpty else { return }
                
                if let hashRate = Double(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    DispatchQueue.main.async {
                        self.currentHashRate = hashRate / 1_000_000 // Convert to MH/s
                    }
                    LogManager.shared.log("Miner hashrate: \(hashRate / 1_000_000) MH/s", type: .mining)
                }
            }.catch { _ in
                // If everything fails, we at least tried
            }
        }
    }
    
    func generateAccount(password: String) throws -> (address: String, mnemonic: String) {
        // Check if we already have an address in a keystore file
        do {
            if let existingAddress = try loadExistingAddress() {
                LogManager.shared.log("Using existing account: \(existingAddress)", type: .info)
                self.miningAddress = existingAddress
                
                // Return a placeholder mnemonic for existing accounts
                // In a real implementation, we would have a proper way to recover the mnemonic
                return (existingAddress, "Existing account - backup phrase not available")
            }
        } catch {
            LogManager.shared.log("Error checking for existing accounts: \(error.localizedDescription)", type: .warning)
        }
        
        // Generate a random mnemonic (12 words)
        let entropy = try generateSecureEntropy(byteCount: 16)
        let mnemonic = try generateMnemonic(fromEntropy: entropy)
        
        // Create keystore file
        let privateKey = try derivePrivateKey(fromMnemonic: mnemonic)
        let address = try createKeystoreFile(privateKey: privateKey, password: password)
        
        // Set the mining address
        self.miningAddress = address
        
        return (address, mnemonic.joined(separator: " "))
    }
    
    private func loadExistingAddress() throws -> String? {
        // Check if keystore directory exists and has any files
        guard fileManager.fileExists(atPath: keystoreDirectory.path) else {
            return nil
        }
        
        let contents = try fileManager.contentsOfDirectory(at: keystoreDirectory, includingPropertiesForKeys: nil)
        
        // Look for keystore files (UTC--date--UUID format)
        let keystoreFiles = contents.filter { $0.lastPathComponent.hasPrefix("UTC--") }
        guard !keystoreFiles.isEmpty else {
            return nil
        }
        
        // Load the first keystore file
        let keystoreFile = keystoreFiles[0]
        let data = try Data(contentsOf: keystoreFile)
        
        // Parse the JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let addressHex = json["address"] as? String else {
            return nil
        }
        
        return "0x" + addressHex
    }
    
    func startMining(address: String, password: String) {
        guard !isMining else { return }
        
        // Set the mining address
        self.miningAddress = address
        
        // Update UI state immediately
        DispatchQueue.main.async {
            self.isMining = true
            LogManager.shared.log("Starting mining process...", type: .info)
            LogManager.shared.log("Initializing blockchain...", type: .info)
        }
        
        // Debug log for geth binary path
        LogManager.shared.log("Looking for geth binary at: \(bundledMarscreditPath?.path ?? "unknown path")", type: .debug)
        if let path = bundledMarscreditPath?.path, fileManager.fileExists(atPath: path) {
            LogManager.shared.log("Found geth binary at: \(path)", type: .success)
            
            // Build and log terminal command that user could run manually
            let args = [
                "--datadir", self.dataDirectory.path,
                "--keystore", self.keystoreDirectory.path,
                "--syncmode", "full",
                "--http",
                "--http.addr", "localhost",
                "--http.port", "8546",
                "--http.api", "personal,eth,net,web3,miner,admin",
                "--http.vhosts", "*",
                "--http.corsdomain", "*",
                "--networkid", "110110",
                "--ws",
                "--ws.addr", "localhost",
                "--ws.port", "8547",
                "--port", "30304",
                "--nat", "any",
                "--mine",
                "--miner.threads", "1",
                "--miner.etherbase", address,
                "--bootnodes", "enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138",
                "--verbosity", "6",
                "--maxpeers", "50",
                "--cache", "2048",
                "--nodiscover",
                "--rpc.allow-unprotected-txs",
                "--authrpc.addr", "localhost",
                "--authrpc.port", "8551",
                "--authrpc.vhosts", "*",
                "--ethash.dagdir", self.ethashDirectory.path
            ]
            
            let manualCommand = args.joined(separator: " ")
            LogManager.shared.log("Manual command for debugging: \(self.bundledMarscreditPath?.path ?? "geth") \(manualCommand)", type: .debug)
        } else {
            LogManager.shared.log("❌ Geth binary not found!", type: .error)
            LogManager.shared.log("Will attempt to use remote RPC endpoint for mining...", type: .info)
            
            // Try remote mining if local geth isn't available
            if let client = ethClient {
                client.startMining(address: address).done {
                    LogManager.shared.log("Mining started on remote node for address: \(address)", type: .success)
                    // Start tracking miner stats
                    self.startMinerStatsTracking()
                }.catch { error in
                    LogManager.shared.log("Failed to start remote mining: \(error.localizedDescription)", type: .error)
                    DispatchQueue.main.async {
                        self.isMining = false
                    }
                }
            } else {
                LogManager.shared.log("No RPC endpoint available for mining", type: .error)
                DispatchQueue.main.async {
                    self.isMining = false
                }
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
            
            // When starting the miner, we'll explicitly set our state to "syncing from zero"
            // until we start getting accurate sync data from our local node
            DispatchQueue.main.async {
                self.networkStatus = NetworkStatus(
                    currentBlock: 0,
                    highestBlock: self.latestBlockNumber,
                    isConnected: true
                )
            }
            
            // Create output pipe for geth process
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            self.marscreditProcess = Process()
            self.marscreditProcess?.executableURL = URL(fileURLWithPath: marscreditPath)
            
            let args = [
                "--datadir", self.dataDirectory.path,
                "--keystore", self.keystoreDirectory.path,
                "--syncmode", "full",
                "--http",
                "--http.addr", "localhost",
                "--http.port", "8546",
                "--http.api", "personal,eth,net,web3,miner,admin",
                "--http.vhosts", "*",
                "--http.corsdomain", "*",
                "--networkid", "110110",
                "--ws",
                "--ws.addr", "localhost",
                "--ws.port", "8547",
                "--port", "30304",
                "--nat", "any",
                "--mine",
                "--miner.threads", "1",
                "--miner.etherbase", address,
                "--bootnodes", "enode://bf93a274569cd009e4172c1a41b8bde1fb8d8e7cff1e5130707a0cf5be4ce0fc673c8a138ecb7705025ea4069da8c1d4b7ffc66e8666f7936aa432ce57693353@roundhouse.proxy.rlwy.net:50590,enode://ca3639067a580a0f1db7412aeeef6d5d5e93606ed7f236a5343fe0d1115fb8c2bea2a22fa86e9794b544f886a4cb0de1afcbccf60960802bf00d81dab9553ec9@monorail.proxy.rlwy.net:26254,enode://7f2ee75a1c112735aaa43de1e5a6c4d7e07d03a5352b5782ed8e0c7cc046a8c8839ad093b09649e0b4a6ed8900211fb4438765c99d07bb00006ef080a1aa9ab6@viaduct.proxy.rlwy.net:30270,enode://98710174f4798dae1931e417944ac7a7fb3268d38ef8d3941c8fcc44fe178b118003d8b3d61d85af39c561235a1708f8dd61f8ba47df4c4a6b9156e272af2cfc@monorail.proxy.rlwy.net:29138",
                "--verbosity", "6",
                "--maxpeers", "50",
                "--cache", "2048",
                "--nodiscover",
                "--rpc.allow-unprotected-txs",
                "--authrpc.addr", "localhost",
                "--authrpc.port", "8551",
                "--authrpc.vhosts", "*",
                "--ethash.dagdir", self.ethashDirectory.path
            ]
            
            self.marscreditProcess?.arguments = args
            self.marscreditProcess?.standardOutput = outputPipe
            self.marscreditProcess?.standardError = errorPipe
            
            // Set up a dispatch queue for processing logs
            let logQueue = DispatchQueue(label: "com.marscredit.gethLogs")
            
            // Process output function
            let processOutput = { (pipe: Pipe, prefix: String, type: LogType) in
                pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    if data.isEmpty { return }
                    
                    if let output = String(data: data, encoding: .utf8) {
                        logQueue.async {
                            // Split the output into lines and process each one
                            output.components(separatedBy: .newlines).forEach { line in
                                guard !line.isEmpty else { return }
                                
                                // Check for specific patterns that might indicate blockchain issues
                                if line.contains("Failed to write genesis block") {
                                    DispatchQueue.main.async {
                                        LogManager.shared.log("⚠️ Genesis block write failed, retrying initialization...", type: .warning)
                                        // Try to reinitialize blockchain
                                        DispatchQueue.global().async {
                                            self.stopMining()
                                            
                                            // Delete chaindata and try again
                                            try? self.fileManager.removeItem(at: self.chaindataDirectory)
                                            self.initializeBlockchain()
                                            
                                            // Restart mining after a short delay
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                self.startMining(address: address, password: password)
                                            }
                                        }
                                    }
                                }
                                
                                if line.contains("Started P2P networking") {
                                    DispatchQueue.main.async {
                                        LogManager.shared.log("✅ P2P networking started successfully", type: .success)
                                    }
                                }
                                
                                if line.contains("Starting mining operation") || line.contains("mined potential block") {
                                    DispatchQueue.main.async {
                                        LogManager.shared.log("⛏️ " + line, type: .mining)
                                    }
                                }
                                
                                if line.contains("Successfully sealed new block") {
                                    DispatchQueue.main.async {
                                        LogManager.shared.log("🎉 Block mined! " + line, type: .success)
                                    }
                                }
                                
                                DispatchQueue.main.async {
                                    LogManager.shared.log("\(prefix): \(line)", type: type)
                                }
                            }
                        }
                    }
                }
            }
            
            // Monitor the output pipe
            processOutput(outputPipe, "STDOUT", .debug)
            
            // Monitor the error pipe separately
            processOutput(errorPipe, "STDERR", .error)
            
            do {
                LogManager.shared.log("Attempting to start geth process...", type: .info)
                LogManager.shared.log("Command: \(marscreditPath) \(args.joined(separator: " "))", type: .debug)
                
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
                
                // Set the current directory for the process
                self.marscreditProcess?.currentDirectoryURL = URL(fileURLWithPath: self.dataDirectory.path)
                
                // Make sure any stale IPC file is removed
                let ipcPath = self.dataDirectory.appendingPathComponent("geth.ipc").path
                if fileManager.fileExists(atPath: ipcPath) {
                    try? fileManager.removeItem(atPath: ipcPath)
                    LogManager.shared.log("Removed stale IPC file", type: .debug)
                }
                
                // Save references to the pipes
                self.marscreditOutput = outputPipe
                
                // Clean up any terminated processes
                LogManager.shared.log("Killing any existing geth processes...", type: .debug)
                let killTask = Process()
                killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                killTask.arguments = ["-f", "geth-binary"]
                try? killTask.run()
                
                // Start the process with a slight delay to ensure cleanup is complete
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self = self else { return }
                    do {
                        try self.marscreditProcess?.run()
                        
                        LogManager.shared.log("✨ Local mining node started with PID: \(self.marscreditProcess?.processIdentifier ?? 0)", type: .success)
                        
                        // Check if process is running after a short delay
                        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                            if let process = self.marscreditProcess, process.isRunning {
                                LogManager.shared.log("Confirmed geth process is running with PID: \(process.processIdentifier)", type: .success)
                                
                                // Try to check geth's log files directly
                                self.checkGethLogs()
                                
                                // Let's also try to run the lsof command to ensure the socket is open
                                let lsofProcess = Process()
                                lsofProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                                lsofProcess.arguments = ["-i", ":8546"]
                                
                                let outputPipe = Pipe()
                                lsofProcess.standardOutput = outputPipe
                                
                                do {
                                    try lsofProcess.run()
                                    lsofProcess.waitUntilExit()
                                    
                                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                                    LogManager.shared.log("Port check: \(output)", type: .debug)
                                    
                                    if output.contains("geth") {
                                        LogManager.shared.log("✅ Geth is listening on port 8546", type: .success)
                                    } else {
                                        LogManager.shared.log("⚠️ Geth may not be listening on port 8546 yet", type: .warning)
                                        
                                        // Check for geth processes
                                        let psProcess = Process()
                                        psProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
                                        psProcess.arguments = ["aux"]
                                        
                                        let psOutputPipe = Pipe()
                                        psProcess.standardOutput = psOutputPipe
                                        
                                        try psProcess.run()
                                        psProcess.waitUntilExit()
                                        
                                        let psOutput = String(data: psOutputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                                        let gethLines = psOutput.components(separatedBy: .newlines).filter { $0.contains("geth") && !$0.contains("grep") }
                                        
                                        LogManager.shared.log("Active geth processes:\n\(gethLines.joined(separator: "\n"))", type: .debug)
                                    }
                                } catch {
                                    LogManager.shared.log("Error checking port: \(error)", type: .error)
                                }
                            } else {
                                LogManager.shared.log("⚠️ Warning: Geth process is not running properly", type: .warning)
                                
                                // Try running geth directly to see what happens
                                let directGethProcess = Process()
                                directGethProcess.executableURL = URL(fileURLWithPath: marscreditPath)
                                directGethProcess.arguments = ["--help"]
                                
                                let directOutputPipe = Pipe()
                                directGethProcess.standardOutput = directOutputPipe
                                directGethProcess.standardError = directOutputPipe
                                
                                do {
                                    try directGethProcess.run()
                                    let output = String(data: directOutputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                                    LogManager.shared.log("Direct geth output:\n\(output)", type: .debug)
                                } catch {
                                    LogManager.shared.log("Failed to run geth directly: \(error)", type: .error)
                                }
                            }
                        }
                    } catch {
                        LogManager.shared.log("Failed to start geth process: \(error.localizedDescription)", type: .error)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    LogManager.shared.log("Error starting geth: \(error.localizedDescription)", type: .error)
                    self.isMining = false
                }
            }
            
            // Start tracking miner stats
            self.startMinerStatsTracking()
        }
    }
    
    func stopMining() {
        guard isMining else { return }
        
        LogManager.shared.log("Stopping mining process...", type: .info)
        
        // Update UI immediately
        DispatchQueue.main.async {
            self.isMining = false
            self.currentHashRate = 0
        }
        
        // Stop the geth process
        marscreditProcess?.terminate()
        marscreditProcess = nil
        marscreditOutput = nil
        
        // Try to signal the node to stop mining via RPC if it's still accessible
        ethClient?.stopMining().done {
            LogManager.shared.log("Mining stopped successfully", type: .success)
        }.catch { error in
            LogManager.shared.log("Error sending stop mining command: \(error)", type: .warning)
            LogManager.shared.log("Mining process terminated", type: .success)
        }
        
        // Reset the block tracking for hash rate calculation
        lastBlockTimestamps.removeAll()
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
    
    private func checkGethLogs() {
        // Check for any geth log files
        let logsDir = dataDirectory.appendingPathComponent("logs")
        do {
            // Create logs directory if it doesn't exist
            if !fileManager.fileExists(atPath: logsDir.path) {
                try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            }
            
            // Create a log file to help with debugging
            let debugLogPath = logsDir.appendingPathComponent("debug.log")
            let now = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = dateFormatter.string(from: now)
            
            let logContent = """
            --- Mars Credit Miner Debug Log: \(timestamp) ---
            Mining Address: \(miningAddress)
            Data Directory: \(dataDirectory.path)
            Geth Binary: \(bundledMarscreditPath?.path ?? "not found")
            PID: \(marscreditProcess?.processIdentifier ?? 0)
            Is Running: \(marscreditProcess?.isRunning ?? false)
            
            """
            
            try logContent.write(to: debugLogPath, atomically: true, encoding: .utf8)
            
            // Execute a simple status check command and write output to our log
            let statusProcess = Process()
            statusProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            statusProcess.arguments = ["-c", "ps -p \(marscreditProcess?.processIdentifier ?? 0) -o pid,ppid,command | tee -a \(debugLogPath.path)"]
            try statusProcess.run()
            statusProcess.waitUntilExit()
            
            // Check for pending transactions
            let pendingTxProcess = Process()
            pendingTxProcess.executableURL = URL(fileURLWithPath: bundledMarscreditPath?.path ?? "/usr/local/bin/geth")
            let pendingTxArgs = [
                "--exec", "eth.pendingTransactions",
                "attach", "http://localhost:8546"
            ]
            pendingTxProcess.arguments = pendingTxArgs
            
            let pendingTxOutput = Pipe()
            pendingTxProcess.standardOutput = pendingTxOutput
            
            do {
                try pendingTxProcess.run()
                pendingTxProcess.waitUntilExit()
                
                let output = String(data: pendingTxOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                LogManager.shared.log("Pending transactions: \(output)", type: .info)
                
                // Append to log file with FileHandle
                if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "\n\n--- Pending Transactions ---\n\(output)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
            } catch {
                LogManager.shared.log("Failed to get pending transactions: \(error)", type: .warning)
            }
            
            // Try to check if mining is active
            let miningStatusProcess = Process()
            miningStatusProcess.executableURL = URL(fileURLWithPath: bundledMarscreditPath?.path ?? "/usr/local/bin/geth")
            let miningStatusArgs = [
                "--exec", "eth.mining",
                "attach", "http://localhost:8546"
            ]
            miningStatusProcess.arguments = miningStatusArgs
            
            let miningStatusOutput = Pipe()
            miningStatusProcess.standardOutput = miningStatusOutput
            
            do {
                try miningStatusProcess.run()
                miningStatusProcess.waitUntilExit()
                
                let output = String(data: miningStatusOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                LogManager.shared.log("Mining status: \(output)", type: .info)
                
                if output.lowercased().contains("true") {
                    LogManager.shared.log("✅ Mining is active!", type: .success)
                }
                
                // Append to log file with FileHandle
                if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "--- Mining Status ---\n\(output)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
            } catch {
                LogManager.shared.log("Failed to get mining status: \(error)", type: .warning)
            }
            
            LogManager.shared.log("Debug log created at: \(debugLogPath.path)", type: .info)
        } catch {
            LogManager.shared.log("Failed to check geth logs: \(error)", type: .error)
        }
    }
    
    // Track blocks attributed to this miner
    func checkMinerBlocks() {
        guard let client = ethClient, !miningAddress.isEmpty else { return }
        
        // Get the latest blocks mined by our address
        client.executeJS(script: "eth.getBlocks(eth.blockNumber-100, eth.blockNumber).filter(function(b) { return b.miner.toLowerCase() === '\(miningAddress.lowercased())'; }).length").done { [weak self] result in
            if let blocksCount = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
                DispatchQueue.main.async {
                    self?.blocksFound = blocksCount
                }
                
                if blocksCount > 0 {
                    LogManager.shared.log("You have mined \(blocksCount) blocks in the last 100 blocks!", type: .success)
                }
            }
        }.catch { _ in
            // Silently fail - this is just a nice-to-have feature
        }
    }
    
    // Helper function to format time
    func formattedAverageBlockTime() -> String {
        if averageBlockTime <= 0 {
            return "Unknown"
        }
        
        let minutes = Int(averageBlockTime) / 60
        let seconds = Int(averageBlockTime) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    // Helper function to estimate earnings
    func estimatedEarningsPerDay() -> Double {
        guard averageBlockTime > 0, currentHashRate > 0 else {
            return 0
        }
        
        let blocksPerDay = 86400 / averageBlockTime
        
        // Get network hashrate from EthereumClient when available
        if let client = ethClient {
            client.getNetworkHashrate().done { [weak self] networkHashRate in
                guard let self = self else { return }
                
                // Calculate with the actual network hashrate
                let minerHashRate = self.currentHashRate * 1_000_000 // Convert to H/s
                let networkHashRateDouble = Double(networkHashRate)
                let minerShare = networkHashRateDouble > 0 ? (minerHashRate / networkHashRateDouble) : 0
                
                // Update logs with network information
                LogManager.shared.log("Network hashrate: \(networkHashRateDouble / 1_000_000) MH/s", type: .info)
                LogManager.shared.log("Your mining share: \(String(format: "%.6f", minerShare * 100))%", type: .info)
                
            }.catch { _ in
                // Silently fail, we'll use the default calculation
            }
        }
        
        // Default calculation if the client call fails
        let networkHashRate = 10_000_000.0 // Assume 10 GH/s network hashrate
        let blockReward = 3.0 // 3 MARS per block
        
        // Expected blocks per day based on hashrate share
        let minerShare = (currentHashRate * 1_000_000) / networkHashRate
        let expectedBlocksPerDay = blocksPerDay * minerShare
        
        return expectedBlocksPerDay * blockReward
    }
    
    // Get all miner rewards
    func getAllMinerRewards() {
        guard let client = ethClient, !miningAddress.isEmpty else { return }
        
        client.getMinerRewards(address: miningAddress).done { result in
            if result.totalBlocks > 0 {
                LogManager.shared.log("Total blocks mined: \(result.totalBlocks)", type: .success)
                LogManager.shared.log("Total rewards earned: \(result.totalRewards) MARS", type: .success)
            }
        }.catch { _ in
            // Silently fail as this is supplementary information
        }
    }
    
    // Check miner stats periodically
    func startMinerStatsTracking() {
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self, self.isMining, let client = self.ethClient else { return }
            
            // Check network hashrate to estimate earnings
            client.getNetworkHashrate().done { networkHashRate in
                if networkHashRate > 0 {
                    let minerShare = (self.currentHashRate * 1_000_000) / Double(networkHashRate)
                    
                    // Only log if there's a significant share
                    if minerShare > 0.0001 { // More than 0.01% of network
                        LogManager.shared.log("Your mining share: \(String(format: "%.4f", minerShare * 100))%", type: .info)
                    }
                }
            }.catch { _ in
                // Silently fail
            }
            
            // Check for total rewards occasionally
            self.getAllMinerRewards()
        }
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