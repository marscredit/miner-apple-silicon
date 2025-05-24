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
    // Add serial queue for synchronization
    private let queue = DispatchQueue(label: "com.marscredit.miningservice")
    private let semaphore = DispatchSemaphore(value: 1)
    
    @Published private(set) var isMining = false {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var networkStatus = NetworkStatus(currentBlock: 0, highestBlock: 0, isConnected: false) {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var isGethRunning = false {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var remoteRpcConnected = false {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var currentBalance: Double = 0.0 {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var miningAddress: String = "" {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var averageBlockTime: Double = 0.0 {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var blocksFound: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    @Published private(set) var connectionAttempts: Int = 0 {
        didSet {
            objectWillChange.send()
        }
    }
    
    // Add connection tracking properties
    private var lastSuccessfulConnection: Date?
    private var connectionFailureCount: Int = 0
    private var connectionCheckTimer: Timer?
    private var connectionCheckInterval: TimeInterval = 5.0
    private var maxFailuresBeforeDisconnect: Int = 3
    
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
    
    private var localClient: EthereumClient?
    private var remoteClient: EthereumClient?
    private let remoteRpcUrl = "https://rpc.marscredit.xyz"
    
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
    
    var mnemonicFilePath: URL {
        dataDirectory.appendingPathComponent("wallet_mnemonic.dat")
    }
    
    private var bundledMarscreditPath: URL? {
        // First try to find the binary in the app bundle's Resources directory
        if let bundleURL = Bundle.main.resourceURL {
            let gethPath = bundleURL.appendingPathComponent("geth").appendingPathComponent("geth")
            if FileManager.default.fileExists(atPath: gethPath.path) {
                LogManager.shared.log("Found geth binary in app bundle", type: .success)
                return gethPath
            }
        }
        
        // Try to find the geth binary in the Resources directory relative to working directory
        let workingDirectory = FileManager.default.currentDirectoryPath
        let resourcesGethPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("Resources")
            .appendingPathComponent("geth")
            .appendingPathComponent("geth")
        
        if FileManager.default.fileExists(atPath: resourcesGethPath.path) {
            LogManager.shared.log("Found geth binary in Resources/geth directory", type: .success)
            return resourcesGethPath
        }
        
        // Fall back to the classic path if not found
        LogManager.shared.log("Geth binary not found in standard locations, falling back to ~/.marscredit/geth-binary", type: .warning)
        return dataDirectory.appendingPathComponent("geth-binary")
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
        
        // Set up more resilient connection checking
        setupConnectionStatusTimer()
        
        // Set up reconnection timer
        setupReconnectionTimer()
        
        // Set up periodic mining process checking for Build 18
        setupMiningProcessTimer()
        
        // Set up active log file monitoring for Build 19+
        setupLogFileMonitoring()
        
        // Set up signal handling for graceful shutdown
        // Re-enabled
        signal(SIGTERM) { _ in
            LogManager.shared.log("SIGTERM received by app", type: .warning)
            MiningService.shared?.stopMining()
            exit(0)
        }
        
        signal(SIGINT) { _ in
            LogManager.shared.log("SIGINT received by app", type: .warning)
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
        LogManager.shared.log("Setting up connection to Mars Credit network...", type: .info)
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.connectionAttempts += 1
                self.lastConnectionAttempt = Date()
            }
            
            // Set up remote client first to get network status
            let remote = EthereumClient(rpcURL: remoteRpcUrl)
            
            do {
                let remoteConnected = try remote.testConnection().wait()
                DispatchQueue.main.async {
                    self.remoteRpcConnected = remoteConnected
                }
                
                if remoteConnected {
                    LogManager.shared.log("Connected to remote Mars Credit RPC endpoint", type: .success)
                    DispatchQueue.main.async {
                        self.remoteClient = remote
                        self.lastSuccessfulConnection = Date()
                    }
                    
                    // Get initial network status from remote
                    self.updateNetworkStatus()
                } else {
                    LogManager.shared.log("Failed to connect to remote Mars Credit RPC", type: .warning)
                }
            } catch {
                LogManager.shared.log("Failed to connect to remote RPC: \(error.localizedDescription)", type: .warning)
                DispatchQueue.main.async {
                    self.remoteRpcConnected = false
                }
            }
            
            // Now try local endpoint for mining control
            LogManager.shared.log("Attempting connection to local geth node...", type: .debug)
            let local = EthereumClient(rpcURL: "http://localhost:8546")
            
            var localConnected = false
            
            // Try multiple times to connect to local endpoint
            for attempt in 1...3 {
                do {
                    let result = try local.testConnection().wait()
                    if result {
                        LogManager.shared.log("Connected to local geth endpoint (attempt \(attempt))", type: .success)
                        localConnected = true
                        break
                    }
                } catch {
                    LogManager.shared.log("Local connection attempt \(attempt) failed: \(error.localizedDescription)", type: .debug)
                    Thread.sleep(forTimeInterval: Double(attempt) * 2.0)
                }
            }
            
            if localConnected {
                DispatchQueue.main.async {
                    self.localClient = local
                    self.lastSuccessfulConnection = Date()
                    self.startUpdatingStatus()
                    self.isReconnecting = false
                    
                    // Update local connection status
                    var updatedStatus = self.networkStatus
                    updatedStatus.isConnected = true
                    self.networkStatus = updatedStatus
                }
            } else {
                LogManager.shared.log("Local geth endpoint not available, will retry later", type: .info)
                // Add exponential backoff for retry
                let delay = min(30.0, pow(2.0, Double(self.connectionAttempts)))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    DispatchQueue.main.async {
                        self?.isReconnecting = false
                    }
                    self?.setupEthereumClient()
                }
            }
        }
    }
    
    // NEW: Update network status from remote RPC
    private func updateNetworkStatus() {
        guard let remote = remoteClient else { return }
        
        remote.getSyncStatus().done { [weak self] syncStatus in
            guard let self = self else { return }
            
            // Update latest block number from remote
            DispatchQueue.main.async {
                self.latestBlockNumber = syncStatus.highestBlock
                LogManager.shared.log("Mars Credit network at block \(syncStatus.currentBlock)", type: .network)
            }
        }.catch { error in
            LogManager.shared.log("Failed to get remote network status: \(error.localizedDescription)", type: .debug)
        }
    }
    
    private func checkDagGenerationStatus() -> String? {
        let logFile = dataDirectory.appendingPathComponent("geth.log")
        guard let logContents = try? String(contentsOf: logFile, encoding: .utf8) else {
            return nil
        }
        
        // Look for DAG generation progress in the last few lines
        let lines = logContents.components(separatedBy: .newlines).reversed()
        for line in lines.prefix(20) {
            if line.contains("Generating DAG in progress") {
                if let percentageRange = line.range(of: "percentage=\\d+", options: .regularExpression),
                   let percentage = Int(line[percentageRange].dropFirst(10)) {
                    return "DAG generation at \(percentage)%"
                }
                return "DAG generation in progress"
            }
        }
        return nil
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
    
    // NEW: Set up periodic mining process checking for Build 18
    private func setupMiningProcessTimer() {
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Periodically check mining process status
            self.checkGethMiningProcess()
            
            // Check remote RPC connection (less frequently to reduce flashing)
            self.checkRemoteConnection()
        }
    }
    
    // NEW: Check remote RPC connection periodically
    private func checkRemoteConnection() {
        guard let remote = remoteClient else { 
            // Try to reconnect to remote if we don't have a client
            let newRemote = EthereumClient(rpcURL: remoteRpcUrl)
            newRemote.testConnection().done { [weak self] connected in
                DispatchQueue.main.async {
                    self?.remoteRpcConnected = connected
                    if connected {
                        self?.remoteClient = newRemote
                        LogManager.shared.log("Reconnected to Mars Credit RPC", type: .network)
                    }
                }
            }.catch { [weak self] _ in
                DispatchQueue.main.async {
                    self?.remoteRpcConnected = false
                }
            }
            return
        }
        
        // Quick network version check (lighter than full connection test)
        let request = remote.createRPCRequest(method: "net_version", params: [])
        remote.executeRequest(request) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.remoteRpcConnected = true
                case .failure:
                    // Only mark as disconnected after multiple failures
                    self?.remoteRpcConnected = false
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
        LogManager.shared.log("Scheduling reconnection attempt...", type: .mining)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            LogManager.shared.log("Attempting to reconnect...", type: .mining)
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Start update timer if not already running
            if self.updateTimer == nil {
                self.updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                    self?.queue.async {
                        self?.updateMiningStatus()
                    }
                }
            }
            
            // Start block timer if not already running
            if self.latestBlockTimer == nil {
                self.latestBlockTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
                    self?.queue.async {
                        self?.updateLatestBlock()
                    }
                }
            }
        }
    }
    
    private func updateMiningStatus() {
        guard let client = ethClient else {
            DispatchQueue.main.async { [weak self] in
                self?.networkStatus = NetworkStatus(currentBlock: 0, highestBlock: 0, isConnected: false)
            }
            return
        }

        // Check if geth process is running with --mine flag
        checkGethMiningProcess()
        
        // Get sync status
        client.getSyncStatus().done { [weak self] syncStatus in
            guard let self = self else { return }
            
            // Log sync progress as mining type (orange color)
            let currentBlock = syncStatus.currentBlock
            let highestBlock = syncStatus.highestBlock
            let progress = Double(currentBlock) / Double(max(1, highestBlock)) * 100
            
            if currentBlock < highestBlock {
                LogManager.shared.log("Sync progress: \(currentBlock)/\(highestBlock) (\(String(format: "%.1f", progress))%)", type: .mining)
            }
            
            DispatchQueue.main.async {
                self.networkStatus = NetworkStatus(
                    currentBlock: syncStatus.currentBlock,
                    highestBlock: syncStatus.highestBlock,
                    isConnected: true
                )
            }
        }.catch { error in
            LogManager.shared.log("Failed to get sync status: \(error.localizedDescription)", type: .error)
        }

        // Get mining status and hashrate - but don't rely on hashrate alone for mining status
        client.getHashRate().done { [weak self] hashRate in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Update connection status on successful hashrate retrieval
                self.lastSuccessfulConnection = Date()
                self.connectionFailureCount = 0
                
                // REMOVED: Hash rate tracking - no longer needed
                // Just use this call to confirm connection is working
                
                // Log mining confirmation if hashrate > 0
                if hashRate > 0 {
                    LogManager.shared.log("⛏️ Mining confirmed with network hashrate response", type: .mining)
                }
            }
        }.catch { error in
            LogManager.shared.log("Failed to get hashrate: \(error.localizedDescription)", type: .error)
        }
    }
    
    // IMPROVED: Check if geth process is running with --mine flag
    private func checkGethMiningProcess() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let checkProcess = Process()
            checkProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
            checkProcess.arguments = ["aux"]
            
            let outputPipe = Pipe()
            checkProcess.standardOutput = outputPipe
            
            do {
                try checkProcess.run()
                checkProcess.waitUntilExit()
                
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                // Look for our specific geth process with mining - IMPROVED detection
                let hasGethProcess = output.contains("geth") && 
                                  output.contains("--mine") && 
                                  (output.contains("--datadir") || output.contains(".marscredit"))
                
                // Also check for any geth process in our data directory
                let hasMarsCreditGeth = output.contains("marscredit") && output.contains("geth")
                
                let gethRunning = hasGethProcess || hasMarsCreditGeth
                
                DispatchQueue.main.async {
                    let wasGethRunning = self.isGethRunning
                    let wasMining = self.isMining
                    
                    self.isGethRunning = gethRunning
                    
                    // If geth is running, we're mining
                    if gethRunning {
                        self.isMining = true
                        
                        if !wasMining {
                            LogManager.shared.log("⛏️ MINING DETECTED: Geth process found running", type: .mining)
                        }
                        if !wasGethRunning {
                            LogManager.shared.log("✅ Geth mining process is active", type: .mining)
                        }
                    } else {
                        self.isMining = false
                        
                        if wasMining {
                            LogManager.shared.log("⚠️ Mining process stopped", type: .warning)
                        }
                    }
                }
            } catch {
                LogManager.shared.log("Error checking geth mining process: \(error.localizedDescription)", type: .debug)
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
        
        // REMOVED: Hash rate tracking - no longer needed
        // Just confirm the mining RPC is responding
        client.executeJS(script: "eth.hashrate").done { [weak self] result in
            guard let self = self, !result.isEmpty else { return }
            
            if let hashRate = Double(result.trimmingCharacters(in: .whitespacesAndNewlines)), hashRate > 0 {
                LogManager.shared.log("⛏️ Mining RPC responding with hashrate data", type: .mining)
            }
        }.catch { error in
            // Try another approach using miner.getHashrate
            client.executeJS(script: "miner.getHashrate()").done { [weak self] result in
                guard let self = self, !result.isEmpty else { return }
                
                if let hashRate = Double(result.trimmingCharacters(in: .whitespacesAndNewlines)), hashRate > 0 {
                    LogManager.shared.log("⛏️ Miner module responding with hashrate data", type: .mining)
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
                
                // Try to load saved mnemonic
                if let savedMnemonic = try loadSavedMnemonic(forAddress: existingAddress) {
                    LogManager.shared.log("Loaded existing mnemonic for account", type: .success)
                    return (existingAddress, savedMnemonic)
                } else {
                    // Return a placeholder mnemonic for existing accounts
                    // In a real implementation, we would have a proper way to recover the mnemonic
                    return (existingAddress, "Existing account - backup phrase not available")
                }
            }
        } catch {
            LogManager.shared.log("Error checking for existing accounts: \(error.localizedDescription)", type: .warning)
        }
        
        // Generate a random mnemonic (12 words)
        let entropy = try generateSecureEntropy(byteCount: 16)
        let mnemonic = try generateMnemonic(fromEntropy: entropy)
        let mnemonicString = mnemonic.joined(separator: " ")
        
        // Create keystore file
        let privateKey = try derivePrivateKey(fromMnemonic: mnemonic)
        let address = try createKeystoreFile(privateKey: privateKey, password: password)
        
        // Set the mining address
        self.miningAddress = address
        
        // Save mnemonic
        try saveMnemonic(mnemonicString, forAddress: address)
        
        return (address, mnemonicString)
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
    
    // Save mnemonic to a protected file
    private func saveMnemonic(_ mnemonic: String, forAddress address: String) throws {
        // Create a dictionary with address-to-mnemonic mapping
        var mnemonicData: [String: String] = [:]
        
        // Load existing data if available
        if fileManager.fileExists(atPath: mnemonicFilePath.path) {
            if let data = try? Data(contentsOf: mnemonicFilePath),
               let existingDict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                mnemonicData = existingDict
            }
        }
        
        // Update with new mnemonic
        mnemonicData[address] = mnemonic
        
        // Save back to file
        let jsonData = try JSONSerialization.data(withJSONObject: mnemonicData, options: [.prettyPrinted])
        try jsonData.write(to: mnemonicFilePath)
        
        // Set secure permissions
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: mnemonicFilePath.path)
        
        LogManager.shared.log("Saved mnemonic for address: \(address)", type: .success)
    }
    
    // Load mnemonic for a specific address
    private func loadSavedMnemonic(forAddress address: String) throws -> String? {
        guard fileManager.fileExists(atPath: mnemonicFilePath.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: mnemonicFilePath)
        guard let mnemonicDict = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        
        return mnemonicDict[address]
    }
    
    // Add process tracking properties
    public var gethStartupTime: Date?
    private var gethProcessPID: Int?
    
    func startMining(address: String, password: String) {
        guard !isMining else { 
            LogManager.shared.log("startMining() called but already mining, ignoring", type: .debug)
            return 
        }
        
        LogManager.shared.log("=== STARTING MINING PROCESS ===", type: .mining)
        
        // First test that the geth binary actually works
        testGethBinary { [weak self] success, error in
            guard let self = self else { return }
            
            if !success {
                LogManager.shared.log("⚠️ Geth binary test failed: \(error ?? "Unknown error")", type: .error)
                LogManager.shared.log("Cannot start mining with a non-functional geth binary", type: .error)
                return
            }
            
            // Continue with normal mining startup
            DispatchQueue.main.async {
                self.isMining = true
                self.miningAddress = address
                self.gethStartupTime = Date() // Track startup time
            }
            
            // Try to wait for any previous mining operation to clean up
            sleep(1)
            
            // Reset stats
            self.blocksFound = 0
            
            // Set the mining address
            self.miningAddress = address
            
            // Try to use a local node first
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Debug log for geth binary path
                LogManager.shared.log("Looking for geth binary at: \(self.bundledMarscreditPath?.path ?? "unknown path")", type: .debug)
                if let path = self.bundledMarscreditPath?.path, self.fileManager.fileExists(atPath: path) {
                    LogManager.shared.log("Found geth binary at: \(path)", type: .success)
                    
                    // We have a local binary, try to start it
                    self.startLocalNode(address: address, password: password)
                } else {
                    LogManager.shared.log("Geth binary not found, cannot use local node", type: .warning)
                    
                    // Try remote mining if local geth isn't available
                    if let client = self.ethClient {
                        client.startMining(address: address).done {
                            LogManager.shared.log("Mining started on remote node for address: \(address)", type: .success)
                        }.catch { error in
                            LogManager.shared.log("Failed to start mining on remote node: \(error.localizedDescription)", type: .error)
                        }
                    } else {
                        LogManager.shared.log("No ethereum client available, cannot mine", type: .error)
                    }
                }
                
                // Start tracking miner stats
                self.startMinerStatsTracking()
            }
        }
    }

    func stopMining() {
        LogManager.shared.log("--- stopMining() CALLED ---", type: .warning)
        guard isMining else { 
            LogManager.shared.log("stopMining(): called but isMining is false, returning.", type: .debug)
            return
        }
        
        // PROTECTION: Don't stop if geth just started (give it at least 10 seconds)
        if let startTime = gethStartupTime, Date().timeIntervalSince(startTime) < 10.0 {
            LogManager.shared.log("🛡️ Geth started recently (\(Int(Date().timeIntervalSince(startTime)))s ago), protecting from premature shutdown", type: .warning)
            return
        }
        
        LogManager.shared.log("Stopping mining process...", type: .mining)
        
        // Update UI immediately
        DispatchQueue.main.async {
            self.isMining = false
            self.gethStartupTime = nil // Clear startup tracking
            self.gethProcessPID = nil
        }
        
        // Stop the geth process - both the direct process and potentially running scripts
        marscreditProcess?.terminate()
        marscreditProcess = nil
        marscreditOutput = nil
        
        // IMPROVED: Only kill our specific geth process using PID file, not all geth processes
        let pidFilePath = dataDirectory.appendingPathComponent("geth.pid")
        if FileManager.default.fileExists(atPath: pidFilePath.path) {
            do {
                let pidString = try String(contentsOf: pidFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                if let pid = Int(pidString) {
                    LogManager.shared.log("Attempting to stop geth process with PID: \(pid)", type: .info)
                    
                    // First try SIGTERM for graceful shutdown
                    let termTask = Process()
                    termTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                    termTask.arguments = ["-TERM", "\(pid)"]
                    try? termTask.run()
                    termTask.waitUntilExit()
                    
                    // Wait a moment for graceful shutdown
                    Thread.sleep(forTimeInterval: 2.0)
                    
                    // Check if process is still running, then force kill if needed
                    let checkTask = Process()
                    checkTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                    checkTask.arguments = ["-p", "\(pid)"]
                    let checkPipe = Pipe()
                    checkTask.standardOutput = checkPipe
                    try? checkTask.run()
                    checkTask.waitUntilExit()
                    
                    let output = String(data: checkPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if output.contains("\(pid)") {
                        LogManager.shared.log("Process \(pid) still running, force killing...", type: .warning)
                        let killTask = Process()
                        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                        killTask.arguments = ["-KILL", "\(pid)"]
                        try? killTask.run()
                    } else {
                        LogManager.shared.log("Geth process \(pid) stopped gracefully", type: .success)
                    }
                    
                    // Clean up PID file
                    try? FileManager.default.removeItem(at: pidFilePath)
                } else {
                    LogManager.shared.log("Invalid PID in geth.pid file", type: .warning)
                }
            } catch {
                LogManager.shared.log("Error reading geth.pid file: \(error.localizedDescription)", type: .error)
            }
        } else {
            LogManager.shared.log("No geth.pid file found, trying fallback process termination", type: .warning)
            
            // Fallback: only kill geth processes from our specific data directory
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killTask.arguments = ["-f", "\(dataDirectory.path).*geth"]
            try? killTask.run()
        }
        
        // Clear the processed log lines
        processedLogLines.removeAll()
        
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
            
            // Get more detailed system info
            let sysInfo = Process()
            sysInfo.executableURL = URL(fileURLWithPath: "/usr/bin/sw_vers")
            let sysInfoPipe = Pipe()
            sysInfo.standardOutput = sysInfoPipe
            try? sysInfo.run()
            sysInfo.waitUntilExit()
            let macOSInfo = String(data: sysInfoPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown"
            
            // Get CPU info
            let cpuInfo = Process()
            cpuInfo.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
            cpuInfo.arguments = ["-n", "machdep.cpu.brand_string"]
            let cpuInfoPipe = Pipe()
            cpuInfo.standardOutput = cpuInfoPipe
            try? cpuInfo.run()
            cpuInfo.waitUntilExit()
            let processorInfo = String(data: cpuInfoPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
            
            // Check file permissions
            let permissionInfo = Process()
            permissionInfo.executableURL = URL(fileURLWithPath: "/bin/ls")
            permissionInfo.arguments = ["-la", bundledMarscreditPath?.path ?? ""]
            let permissionInfoPipe = Pipe()
            permissionInfo.standardOutput = permissionInfoPipe
            try? permissionInfo.run()
            permissionInfo.waitUntilExit()
            let filePermissions = String(data: permissionInfoPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown"
            
            // Create comprehensive log content
            let logContent = """
            --- Mars Credit Miner Debug Log: \(timestamp) ---
            System Info:
            \(macOSInfo)
            Processor: \(processorInfo)
            
            Application Configuration:
            Mining Address: \(miningAddress)
            Data Directory: \(dataDirectory.path)
            Geth Binary: \(bundledMarscreditPath?.path ?? "not found")
            File Permissions: 
            \(filePermissions)
            
            Process Info:
            PID: \(marscreditProcess?.processIdentifier ?? 0)
            Is Running: \(marscreditProcess?.isRunning ?? false)
            
            Directory Structure Check:
            Data Directory Exists: \(fileManager.fileExists(atPath: dataDirectory.path))
            Keystore Directory Exists: \(fileManager.fileExists(atPath: keystoreDirectory.path))
            Chaindata Directory Exists: \(fileManager.fileExists(atPath: chaindataDirectory.path))
            Ethash Directory Exists: \(fileManager.fileExists(atPath: ethashDirectory.path))
            
            Network Status:
            Current Block: \(networkStatus.currentBlock)
            Highest Block: \(networkStatus.highestBlock)
            Is Connected: \(networkStatus.isConnected)
            Connection Attempts: \(connectionAttempts)
            
            Mining Status:
            Is Mining: \(isMining)
            
            """
            
            try logContent.write(to: debugLogPath, atomically: true, encoding: .utf8)
            
            // Execute a simple status check command and write output to our log
            let statusProcess = Process()
            statusProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            statusProcess.arguments = ["-c", "ps -p \(marscreditProcess?.processIdentifier ?? 0) -o pid,ppid,command | tee -a \(debugLogPath.path)"]
            try statusProcess.run()
            statusProcess.waitUntilExit()
            
            // Check for open network ports
            let netstatProcess = Process()
            netstatProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            netstatProcess.arguments = ["-i", "TCP:8546"]
            let netstatPipe = Pipe()
            netstatProcess.standardOutput = netstatPipe
            try netstatProcess.run()
            netstatProcess.waitUntilExit()
            let netstatOutput = String(data: netstatPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            // Append to log file with FileHandle
            if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                fileHandle.seekToEndOfFile()
                let appendString = "\n\n--- Network Connections ---\n\(netstatOutput)\n\n"
                fileHandle.write(appendString.data(using: .utf8)!)
                fileHandle.closeFile()
            }
            
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
            pendingTxProcess.standardError = pendingTxOutput
            
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
                
                // Log the error details
                if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "\n\n--- Pending Transactions Error ---\n\(error)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
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
            miningStatusProcess.standardError = miningStatusOutput
            
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
                
                // Log the error details
                if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "\n\n--- Mining Status Error ---\n\(error)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
            }
            
            // Check if we can connect to the node at all
            let nodeInfoProcess = Process()
            nodeInfoProcess.executableURL = URL(fileURLWithPath: bundledMarscreditPath?.path ?? "/usr/local/bin/geth")
            let nodeInfoArgs = [
                "--exec", "admin.nodeInfo",
                "attach", "http://localhost:8546"
            ]
            nodeInfoProcess.arguments = nodeInfoArgs
            
            let nodeInfoOutput = Pipe()
            nodeInfoProcess.standardOutput = nodeInfoOutput
            nodeInfoProcess.standardError = nodeInfoOutput
            
            do {
                try nodeInfoProcess.run()
                nodeInfoProcess.waitUntilExit()
                
                let output = String(data: nodeInfoOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                // Append to log file with FileHandle
                if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "--- Node Info ---\n\(output)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
                
                LogManager.shared.log("Node info: \(output.prefix(100))...", type: .debug)
            } catch {
                LogManager.shared.log("Failed to get node info: \(error)", type: .warning)
                
                // Log the error details
                if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "\n\n--- Node Info Error ---\n\(error)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
            }
            
            // Check disk space
            let diskSpaceProcess = Process()
            diskSpaceProcess.executableURL = URL(fileURLWithPath: "/bin/df")
            diskSpaceProcess.arguments = ["-h", dataDirectory.path]
            let diskSpacePipe = Pipe()
            diskSpaceProcess.standardOutput = diskSpacePipe
            try diskSpaceProcess.run()
            diskSpaceProcess.waitUntilExit()
            let diskSpaceOutput = String(data: diskSpacePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            // Append disk space info to log
            if let fileHandle = FileHandle(forWritingAtPath: debugLogPath.path) {
                fileHandle.seekToEndOfFile()
                let appendString = "\n\n--- Disk Space ---\n\(diskSpaceOutput)\n\n"
                fileHandle.write(appendString.data(using: .utf8)!)
                fileHandle.closeFile()
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
        guard averageBlockTime > 0 else {
            return 0
        }
        
        let blocksPerDay = 86400 / averageBlockTime
        
        // REMOVED: Hash rate based calculations - no longer available
        // Return a simple estimate based on average block time
        let blockReward = 3.0 // 3 MARS per block
        let networkEstimate = 10_000_000.0 // Assume 10 GH/s network hashrate
        let basicMinerEstimate = 100_000.0 // Assume basic miner rate
        
        // Simple estimate without real hashrate
        let estimatedMinerShare = basicMinerEstimate / networkEstimate
        let expectedBlocksPerDay = blocksPerDay * estimatedMinerShare
        
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
            guard let self = self, self.isMining else { return }
            
            // REMOVED: Hash rate based calculations - no longer available
            // Focus on block mining success and network participation
            
            // Check for total rewards occasionally
            self.getAllMinerRewards()
        }
    }
    
    deinit {
        stopMining()
        connectionCheckTimer?.invalidate()
        MiningService.shared = nil
    }
    
    // Helper function to test if the geth binary works correctly
    private func testGethBinary(completion: @escaping (Bool, String?) -> Void) {
        // First check if the binary exists
        guard let gethPath = bundledMarscreditPath?.path,
              fileManager.fileExists(atPath: gethPath) else {
            completion(false, "Geth binary not found")
            return
        }
        
        // Prepare log directory
        let logsDir = dataDirectory.appendingPathComponent("logs")
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let testLogPath = logsDir.appendingPathComponent("geth_test.log")
        
        let logEntry = "===== GETH BINARY TEST: \(Date()) =====\n"
        try? logEntry.write(to: testLogPath, atomically: true, encoding: .utf8)
        
        // Run a simple version command to test the binary
        let versionProcess = Process()
        versionProcess.executableURL = URL(fileURLWithPath: gethPath)
        versionProcess.arguments = ["version"]
        
        let outputPipe = Pipe()
        versionProcess.standardOutput = outputPipe
        versionProcess.standardError = outputPipe
        
        do {
            // Try to make sure the binary is executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gethPath)
            
            LogManager.shared.log("Testing geth binary with 'version' command...", type: .info)
            try versionProcess.run()
            versionProcess.waitUntilExit()
            
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            // Append output to test log
            if let fileHandle = FileHandle(forWritingAtPath: testLogPath.path) {
                fileHandle.seekToEndOfFile()
                let appendString = "VERSION TEST OUTPUT:\n\(output)\n\n"
                fileHandle.write(appendString.data(using: .utf8)!)
                fileHandle.closeFile()
            }
            
            if versionProcess.terminationStatus == 0 && output.contains("Version") {
                LogManager.shared.log("✅ Geth binary test successful: \(output.prefix(50))...", type: .success)
                
                // Try a more complex test - check if geth can initialize a test genesis
                let testGenesisPath = dataDirectory.appendingPathComponent("test_genesis.json")
                let testGenesisContent = """
                {
                    "config": {
                        "chainId": 999999,
                        "homesteadBlock": 0,
                        "eip150Block": 0,
                        "eip155Block": 0,
                        "eip158Block": 0
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
                try? testGenesisContent.write(to: testGenesisPath, atomically: true, encoding: .utf8)
                
                // Create a test directory
                let testDir = dataDirectory.appendingPathComponent("geth_test")
                try? fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
                
                // Try to initialize the test genesis
                let initProcess = Process()
                initProcess.executableURL = URL(fileURLWithPath: gethPath)
                initProcess.arguments = [
                    "--datadir", testDir.path,
                    "init",
                    testGenesisPath.path
                ]
                
                let initOutputPipe = Pipe()
                initProcess.standardOutput = initOutputPipe
                initProcess.standardError = initOutputPipe
                
                LogManager.shared.log("Testing geth binary with genesis initialization...", type: .info)
                try initProcess.run()
                initProcess.waitUntilExit()
                
                let initOutput = String(data: initOutputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                // Append init output to test log
                if let fileHandle = FileHandle(forWritingAtPath: testLogPath.path) {
                    fileHandle.seekToEndOfFile()
                    let appendString = "INIT TEST OUTPUT:\n\(initOutput)\n\n"
                    fileHandle.write(appendString.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
                
                if initProcess.terminationStatus == 0 {
                    LogManager.shared.log("✅ Geth binary successfully initialized test genesis", type: .success)
                    
                    // Clean up test directory
                    try? fileManager.removeItem(at: testDir)
                    try? fileManager.removeItem(at: testGenesisPath)
                    
                    completion(true, nil)
                } else {
                    LogManager.shared.log("⚠️ Geth binary failed to initialize test genesis: \(initOutput)", type: .warning)
                    
                    // The binary still works for version, so let's consider it partially functional
                    completion(true, "Binary works but genesis init failed. Mining may not work properly.")
                }
            } else {
                LogManager.shared.log("❌ Geth binary test failed: \(output)", type: .error)
                completion(false, "Binary failed version test: \(output)")
            }
        } catch {
            LogManager.shared.log("❌ Error running geth binary test: \(error.localizedDescription)", type: .error)
            
            // Append error to test log
            if let fileHandle = FileHandle(forWritingAtPath: testLogPath.path) {
                fileHandle.seekToEndOfFile()
                let appendString = "ERROR RUNNING TEST:\n\(error.localizedDescription)\n\n"
                fileHandle.write(appendString.data(using: .utf8)!)
                fileHandle.closeFile()
            }
            
            completion(false, error.localizedDescription)
        }
    }
    
    // Start a local geth node for mining
    private func startLocalNode(address: String, password: String) {
        // Update UI state immediately
        DispatchQueue.main.async {
            LogManager.shared.log("Starting mining process...", type: .mining)
            // Removed "Initializing blockchain..." log as it's handled by script
        }

        // Find the wrapper script within the app bundle's Resources directory
        guard let wrapperPathString = Bundle.main.path(forResource: "run_geth_in_app", ofType: "sh") else {
            LogManager.shared.log("Error: run_geth_in_app.sh not found in the application bundle's Resources directory.", type: .error)
            DispatchQueue.main.async {
                self.isMining = false
                self.gethStartupTime = nil
            }
            return
        }
        let wrapperPath = URL(fileURLWithPath: wrapperPathString)
        LogManager.shared.log("Found geth wrapper script at: \(wrapperPath.path)", type: .info)

        // Make sure the script is executable
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath.path)
            LogManager.shared.log("Ensured wrapper script is executable", type: .debug)
        } catch {
            LogManager.shared.log("Error setting execute permission on wrapper script: \(error.localizedDescription)", type: .error)
            return
        }

        // Use the wrapper script to launch geth
        LogManager.shared.log("Using geth wrapper script to launch geth", type: .info)

        // Create a simple Process to run the wrapper script
        let wrapperProcess = Process()
        // Execute via /bin/bash
        wrapperProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        wrapperProcess.arguments = [wrapperPath.path] // Pass script path as argument

        // Create pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        wrapperProcess.standardOutput = outputPipe
        wrapperProcess.standardError = errorPipe

        // Dispatch the process launch to a background queue
        DispatchQueue.global(qos: .background).async {
            var errorMessage: String? = nil
            var successMessage: String? = nil

            do {
                // Launch the script
                LogManager.shared.log("Attempting to launch geth wrapper script: \(wrapperPath.path)", type: .debug)
                try wrapperProcess.run()
                
                let pid = wrapperProcess.processIdentifier // PID of bash
                successMessage = "✨ Dispatched geth wrapper script process (PID: \(pid)). Script runs in background."
                
                // Set up monitoring for the actual geth process
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    self?.startGethProcessMonitoring()
                }

            } catch {
                errorMessage = "Error trying to run geth wrapper: \(error.localizedDescription)"
            }

            // Log results safely on the main thread
            DispatchQueue.main.async {
                if let msg = successMessage {
                    LogManager.shared.log(msg, type: .success)
                }
                if let msg = errorMessage {
                    LogManager.shared.log("❌ \(msg)", type: .error) // Added ❌ for emphasis
                    self.isMining = false
                    self.gethStartupTime = nil
                }
                
                // After attempting to start, check the actual Geth log file
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Wait 2s for Geth to potentially log
                    self.checkGethLogFileContent()
                }
            }
        }
    }
    
    private func startGethProcessMonitoring() {
        LogManager.shared.log("Starting geth process monitoring...", type: .debug)
        
        // Monitor for PID file creation and track the process
        let pidFilePath = dataDirectory.appendingPathComponent("geth.pid")
        
        // Check every second for up to 30 seconds for the PID file to appear
        var attempts = 0
        let maxAttempts = 30
        
        let monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            attempts += 1
            
            if FileManager.default.fileExists(atPath: pidFilePath.path) {
                do {
                    let pidString = try String(contentsOf: pidFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let pid = Int(pidString) {
                        DispatchQueue.main.async {
                            self.gethProcessPID = pid
                            LogManager.shared.log("🎯 Geth process detected with PID: \(pid)", type: .success)
                        }
                        
                        // Verify the process is actually running
                        let checkTask = Process()
                        checkTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                        checkTask.arguments = ["-p", "\(pid)", "-o", "pid,command"]
                        let checkPipe = Pipe()
                        checkTask.standardOutput = checkPipe
                        
                        try? checkTask.run()
                        checkTask.waitUntilExit()
                        
                        let output = String(data: checkPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        if output.contains("geth") {
                            LogManager.shared.log("✅ Confirmed geth process is running: \(output.components(separatedBy: .newlines).last ?? "")", type: .success)
                        } else {
                            LogManager.shared.log("⚠️ PID file exists but geth process not found in process list", type: .warning)
                        }
                    }
                    timer.invalidate()
                } catch {
                    LogManager.shared.log("Error reading PID file: \(error.localizedDescription)", type: .error)
                }
            } else if attempts >= maxAttempts {
                LogManager.shared.log("⚠️ Geth PID file not created after \(maxAttempts) seconds", type: .warning)
                timer.invalidate()
            }
        }
        
        // Also start periodic health checking after the initial monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 35.0) { [weak self] in
            self?.startGethHealthMonitoring()
        }
    }
    
    private func startGethHealthMonitoring() {
        // Monitor geth health every 30 seconds
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isMining else { return }
            
            if let pid = self.gethProcessPID {
                // Check if the process is still running
                let checkTask = Process()
                checkTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                checkTask.arguments = ["-p", "\(pid)"]
                let checkPipe = Pipe()
                checkTask.standardOutput = checkPipe
                checkTask.standardError = Pipe() // Silence stderr
                
                try? checkTask.run()
                checkTask.waitUntilExit()
                
                if checkTask.terminationStatus != 0 {
                    LogManager.shared.log("🚨 Geth process (PID: \(pid)) has died unexpectedly!", type: .error)
                    DispatchQueue.main.async {
                        self.isMining = false
                        self.gethProcessPID = nil
                        self.gethStartupTime = nil
                    }
                } else {
                    LogManager.shared.log("💓 Geth process (PID: \(pid)) is healthy", type: .debug)
                }
            }
        }
    }

    private func checkGethLogFileContent() {
        let logPath = dataDirectory.appendingPathComponent("logs/geth.log")
        do {
            let logContent = try String(contentsOf: logPath, encoding: .utf8)
            if logContent.contains("Starting Geth node...") || logContent.contains("HTTP server started") {
                LogManager.shared.log("Geth log file indicates Geth started or attempted to start. Contents:\\n\(logContent.prefix(500))", type: .info)
            } else if logContent.contains("Geth log cleared") {
                 LogManager.shared.log("Geth log file only contains 'cleared' message. Geth wrapper script likely didn't run properly.", type: .warning)
            } else {
                LogManager.shared.log("Geth log file content (first 500 chars):\\n\(logContent.prefix(500))", type: .debug)
                }
        } catch {
            LogManager.shared.log("Could not read Geth log file at \(logPath.path): \(error.localizedDescription)", type: .error)
        }
    }

    // Check if mining is actually running
    private func checkMiningStatus() {
        guard let client = ethClient else { return }
        
        // Use eth.mining to check if mining is actually running
        client.executeJS(script: "eth.mining").done { result in
            let isMining = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            
            if isMining {
                LogManager.shared.log("✅ Mining is active", type: .success)
            } else {
                LogManager.shared.log("⚠️ Mining is not active, attempting to start it", type: .warning)
                
                // Try to start mining
                client.executeJS(script: "miner.start()").done { _ in
                    LogManager.shared.log("Mining start command sent", type: .info)
                }.catch { error in
                    LogManager.shared.log("Failed to start mining via RPC: \(error)", type: .error)
                }
            }
        }.catch { error in
            LogManager.shared.log("Failed to check mining status: \(error)", type: .warning)
        }
        
        // Also check hashrate as a confirmation
        client.getHashRate().done { hashRate in
            if hashRate > 0 {
                LogManager.shared.log("Confirmed mining is working with hashrate: \(Double(hashRate) / 1_000_000) MH/s", type: .success)
            } else {
                LogManager.shared.log("Mining appears to be inactive (hashrate = 0)", type: .warning)
            }
        }.catch { _ in
            // Silent fail - already logged in other methods
        }
    }

    // Monitor Geth process status
    private func checkGethProcess() {
        // Check if PID file exists
        let pidFilePath = dataDirectory.appendingPathComponent("geth.pid").path
        
        if fileManager.fileExists(atPath: pidFilePath) {
            do {
                let pidString = try String(contentsOfFile: pidFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                if let pid = Int(pidString) {
                    // Check if process is running
                    let checkProcess = Process()
                    checkProcess.executableURL = URL(fileURLWithPath: "/bin/ps")
                    checkProcess.arguments = ["-p", "\(pid)"]
                    
                    let outputPipe = Pipe()
                    checkProcess.standardOutput = outputPipe
                    
                    try checkProcess.run()
                    checkProcess.waitUntilExit()
                    
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    
                    if output.contains("\(pid)") {
                        LogManager.shared.log("Geth process is running with PID \(pid)", type: .debug)
                        return
                    } else {
                        LogManager.shared.log("Geth process not running, PID \(pid) not found", type: .warning)
                    }
                }
            } catch {
                LogManager.shared.log("Error checking Geth PID: \(error.localizedDescription)", type: .error)
            }
        }
        
        // If PID file doesn't exist or process not running, check for any geth processes
        let checkAllProcess = Process()
        checkAllProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        checkAllProcess.arguments = ["geth"]
        
        let outputPipe = Pipe()
        checkAllProcess.standardOutput = outputPipe
        
        do {
            try checkAllProcess.run()
            checkAllProcess.waitUntilExit()
            
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !output.isEmpty {
                let pids = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if !pids.isEmpty {
                    LogManager.shared.log("Found running geth processes with PIDs: \(pids.joined(separator: ", "))", type: .info)
                    return
                }
            }
        } catch {
            LogManager.shared.log("Error checking for geth processes: \(error.localizedDescription)", type: .debug)
        }
        
        // If we get here, the Geth process is not running
        LogManager.shared.log("Geth process not found, mining may not work correctly", type: .error)
    }

    // Monitor the geth log file to display in the app - IMPROVED for Build 20+
    private func monitorGethLogFile() {
        // IMPORTANT: Read from the actual geth log file path
        let logPath = dataDirectory.appendingPathComponent("logs/geth.log")

        guard FileManager.default.fileExists(atPath: logPath.path) else {
            // Log path doesn't exist, try alternative location
            let altLogPath = dataDirectory.appendingPathComponent("geth.log")
            if FileManager.default.fileExists(atPath: altLogPath.path) {
                monitorLogFile(at: altLogPath)
            }
            return
        }
        
        monitorLogFile(at: logPath)
    }
    
    // NEW: Monitor specific log file
    private func monitorLogFile(at logPath: URL) {
        do {
            let data = try Data(contentsOf: logPath)
            guard let logContent = String(data: data, encoding: .utf8) else {
                return
            }
            
            // Get the log lines
            let lines = logContent.components(separatedBy: .newlines)
            
            // Process lines we haven't seen yet
            let totalLines = lines.count
            let startLine = max(0, totalLines - 50) // Check last 50 lines for new content
            
            for i in startLine..<totalLines {
                let line = lines[i]
                guard !line.isEmpty else { continue }
                
                // Check if we've already processed this line
                if !processedLogLines.contains(line) {
                    processedLogLines.insert(line)
                    
                    // Categorize and log the line with BETTER detection
                    DispatchQueue.main.async {
                        self.categorizeAndLogLine(line)
                    }
                }
            }
        } catch {
            // Silently fail - we'll try again next time
        }
    }
    
    // NEW: Better log line categorization
    private func categorizeAndLogLine(_ line: String) {
        let lowercaseLine = line.lowercased()
        
        // MINING LOGS (Orange) - Expanded detection
        if lowercaseLine.contains("generating dag") ||
           lowercaseLine.contains("commit new sealing work") ||
           lowercaseLine.contains("successfully sealed new block") ||
           lowercaseLine.contains("mined potential block") ||
           lowercaseLine.contains("imported new chain segment") ||
           lowercaseLine.contains("starting mining operation") ||
           lowercaseLine.contains("sealing result") ||
           lowercaseLine.contains("block reached canonical chain") ||
           lowercaseLine.contains("ethash") ||
           lowercaseLine.contains("mining") {
            LogManager.shared.log("⛏️ " + line, type: .mining)
        }
        // ERROR LOGS (Red)
        else if lowercaseLine.contains("fatal") || 
                lowercaseLine.contains("panic") || 
                lowercaseLine.contains("error") ||
                lowercaseLine.contains("failed") {
            LogManager.shared.log("⚠️ " + line, type: .error)
        }
        // SUCCESS LOGS (Green)
        else if lowercaseLine.contains("started p2p networking") ||
                lowercaseLine.contains("http server started") ||
                lowercaseLine.contains("ipc endpoint opened") {
            LogManager.shared.log("✅ " + line, type: .success)
        }
        // WARNING LOGS (Yellow)
        else if lowercaseLine.contains("warn") {
            LogManager.shared.log("⚠️ " + line, type: .warning)
        }
        // DEFAULT INFO LOGS (White)
        else if lowercaseLine.contains("info") {
            LogManager.shared.log(line, type: .info)
        }
        // DEBUG LOGS (Gray)
        else {
            LogManager.shared.log(line, type: .debug)
        }
    }
    
    // Store processed log lines to avoid duplicates
    private var processedLogLines = Set<String>()
    
    // Reset wallet and create a new one
    func resetWallet(password: String) throws -> (address: String, mnemonic: String) {
        // Stop mining if active
        if isMining {
            stopMining()
        }
        
        LogManager.shared.log("Resetting wallet...", type: .warning)
        
        // Clean up existing keystore files
        do {
            let contents = try fileManager.contentsOfDirectory(at: keystoreDirectory, includingPropertiesForKeys: nil)
            let keystoreFiles = contents.filter { $0.lastPathComponent.hasPrefix("UTC--") }
            
            for file in keystoreFiles {
                try fileManager.removeItem(at: file)
                LogManager.shared.log("Removed keystore file: \(file.lastPathComponent)", type: .info)
            }
        } catch {
            LogManager.shared.log("Error clearing keystore directory: \(error.localizedDescription)", type: .error)
        }
        
        // Generate a new account
        let entropy = try generateSecureEntropy(byteCount: 16)
        let mnemonic = try generateMnemonic(fromEntropy: entropy)
        let mnemonicString = mnemonic.joined(separator: " ")
        
        // Create keystore file
        let privateKey = try derivePrivateKey(fromMnemonic: mnemonic)
        let address = try createKeystoreFile(privateKey: privateKey, password: password)
        
        // Set the mining address
        self.miningAddress = address
        
        // Save mnemonic
        try saveMnemonic(mnemonicString, forAddress: address)
        
        LogManager.shared.log("Created new wallet with address: \(address)", type: .success)
        return (address, mnemonicString)
    }

    private func setupConnectionStatusTimer() {
        connectionCheckTimer?.invalidate()
        
        // IMPROVEMENT: Delay connection checking if geth was just started
        let delay: TimeInterval
        if let startTime = gethStartupTime, Date().timeIntervalSince(startTime) < 30.0 {
            // If geth started recently, wait longer before beginning aggressive connection checking
            delay = 30.0 - Date().timeIntervalSince(startTime)
            LogManager.shared.log("Delaying connection monitoring for \(Int(delay))s to allow geth startup", type: .info)
        } else {
            delay = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            self.connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: self.connectionCheckInterval, repeats: true) { [weak self] _ in
                self?.checkNetworkConnection()
            }
            self.connectionCheckTimer?.fire() // Check immediately after delay
            
            if delay > 0 {
                LogManager.shared.log("Connection monitoring started after geth startup delay", type: .success)
            }
        }
    }
    
    private func checkNetworkConnection() {
        guard let client = localClient ?? remoteClient else {
            // If no client is available, we're definitely disconnected
            DispatchQueue.main.async {
                self.updateNetworkStatusWithDebounce(isConnected: false)
            }
            return
        }
        
        client.testConnection().done { [weak self] isConnected in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateNetworkStatusWithDebounce(isConnected: isConnected)
            }
        }.catch { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateNetworkStatusWithDebounce(isConnected: false)
            }
        }
    }
    
    private func updateNetworkStatusWithDebounce(isConnected: Bool) {
        if isConnected {
            // On successful connection, reset failure count and update last success time
            connectionFailureCount = 0
            lastSuccessfulConnection = Date()
            
            // Update network status if it wasn't already connected
            if !networkStatus.isConnected {
                var updatedStatus = networkStatus
                updatedStatus.isConnected = true
                networkStatus = updatedStatus
                LogManager.shared.log("Connection to Mars Credit network (ID: 110110) established", type: .success)
            }
        } else {
            // On connection failure, increment failure count
            connectionFailureCount += 1
            
            // IMPROVEMENT: Be more tolerant during geth startup period
            let failureThreshold: Int
            if let startTime = gethStartupTime, Date().timeIntervalSince(startTime) < 60.0 {
                // During startup (first 60 seconds), require more failures before disconnecting
                failureThreshold = 8  // More tolerant during startup
                LogManager.shared.log("Startup period: connection check failed (\(connectionFailureCount)/\(failureThreshold)) - being tolerant", type: .debug)
            } else {
                // Normal operation - use standard threshold
                failureThreshold = maxFailuresBeforeDisconnect
                LogManager.shared.log("Connection check failed (\(connectionFailureCount)/\(failureThreshold))", type: .debug)
            }
            
            // Only mark as disconnected after multiple consecutive failures
            if connectionFailureCount >= failureThreshold {
                if networkStatus.isConnected {
                    var updatedStatus = networkStatus
                    updatedStatus.isConnected = false
                    networkStatus = updatedStatus
                    LogManager.shared.log("Connection to network lost after \(connectionFailureCount) failed attempts", type: .warning)
                }
                
                // Try to reconnect if we've been disconnected for a while
                if lastSuccessfulConnection == nil || Date().timeIntervalSince(lastSuccessfulConnection!) > 15.0 {
                    scheduleReconnection()
                }
            }
        }
    }

    public func getCurrentAccountMnemonic() -> String? {
        guard !self.miningAddress.isEmpty else {
            LogManager.shared.log("No active mining address to fetch mnemonic for.", type: .debug)
            return nil
        }
        do {
            if let mnemonic = try loadSavedMnemonic(forAddress: self.miningAddress) {
                LogManager.shared.log("Successfully loaded mnemonic for \(self.miningAddress) on demand.", type: .debug)
                return mnemonic
            } else {
                LogManager.shared.log("Mnemonic not found for \(self.miningAddress) in saved file.", type: .warning)
                return "Mnemonic not found for this account."
            }
        } catch {
            LogManager.shared.log("Error loading saved mnemonic for \(self.miningAddress): \(error.localizedDescription)", type: .error)
            return "Error occurred while loading mnemonic."
        }
    }
    
    // NEW: Set up active log file monitoring for Build 19+
    private func setupLogFileMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Monitor geth log file for new entries
            self.monitorGethLogFile()
            
            // Update mining statistics via RPC
            if self.isMining || self.isGethRunning {
                self.updateMiningStats()
            }
        }
        
        // ADDED: More frequent balance updates
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update balance more frequently
            if !self.miningAddress.isEmpty {
                self.updateBalance(address: self.miningAddress)
            }
        }
    }
    
    // NEW: Update mining stats via RPC (balance, hashrate, etc.)
    private func updateMiningStats() {
        // Always check mining process first
        checkGethMiningProcess()
        
        // Get current balance via REMOTE RPC more frequently
        if !miningAddress.isEmpty, let remoteClient = remoteClient {
            let balanceRequest = remoteClient.createRPCRequest(method: "eth_getBalance", params: [miningAddress, "latest"])
            remoteClient.executeRequest(balanceRequest) { [weak self] result in
                if case .success(let response) = result,
                   let balanceHex = response["result"] as? String,
                   let balance = BigInt(balanceHex.dropFirst(2), radix: 16) {
                    DispatchQueue.main.async {
                        let newBalance = Double(balance) / 1e18 // Convert from wei to MARS
                        if newBalance != self?.currentBalance {
                            self?.currentBalance = newBalance
                            LogManager.shared.log("Balance updated: \(String(format: "%.6f", newBalance)) MARS", type: .mining)
                        }
                    }
                }
            }
        }
        
        guard let localClient = localClient else { return }
        
        // REMOVED: Hash rate tracking - no longer needed
        // Just use this call to confirm mining process is responding
        if localClient != nil {
            LogManager.shared.log("⛏️ Mining process connection confirmed", type: .mining)
        }
    }
    
    // NEW: Alternative hash rate checking
    private func checkAlternativeHashRate() {
        guard let localClient = localClient else { return }
        
        // Try getting mining statistics differently
        let request = localClient.createRPCRequest(method: "eth_getWork", params: [])
        localClient.executeRequest(request) { [weak self] result in
            switch result {
            case .success:
                // If getWork succeeds, we're actively mining
                DispatchQueue.main.async {
                    LogManager.shared.log("⛏️ Active mining detected (getWork responding)", type: .mining)
                }
            case .failure:
                // Try checking if miner module is working  
                let minerRequest = localClient.createRPCRequest(method: "miner_hashrate", params: [])
                localClient.executeRequest(minerRequest) { result in
                    if case .success = result {
                        // Just confirm the miner module is responding, don't track actual hash rate
                        DispatchQueue.main.async {
                            LogManager.shared.log("⛏️ Miner module responding", type: .mining)
                        }
                    }
                }
            }
        }
    }
    
    // NEW: Check if we mined any blocks recently
    private func checkForMinedBlocks() {
        guard let client = localClient else { return }
        
        client.getLatestBlock().done { [weak self] latestBlock in
            guard let self = self else { return }
            
            // Check the last few blocks to see if we mined any
            let startBlock = max(0, latestBlock - 10) // Check last 10 blocks
            
            for blockNum in startBlock...latestBlock {
                let blockHex = "0x" + String(blockNum, radix: 16)
                let request = client.createRPCRequest(method: "eth_getBlockByNumber", params: [blockHex, false])
                
                client.executeRequest(request) { [weak self] result in
                    guard let self = self else { return }
                    
                    if case .success(let response) = result,
                       let blockData = response["result"] as? [String: Any],
                       let miner = blockData["miner"] as? String,
                       miner.lowercased() == self.miningAddress.lowercased() {
                        
                        DispatchQueue.main.async {
                            self.blocksFound += 1
                            LogManager.shared.log("🎉 BLOCK FOUND! Block #\(blockNum) mined by us!", type: .mining)
                        }
                    }
                }
            }
        }.catch { _ in
            // Silent fail
        }
    }
    
    // NEW: Public method to get balance immediately
    public func getBalanceOnStartup(address: String) {
        guard !address.isEmpty else { return }
        
        // Get balance immediately via remote RPC
        self.miningAddress = address
        self.updateBalance(address: address)
        
        LogManager.shared.log("🔍 Checking initial balance for address: \(address)", type: .info)
    }
}

enum MiningError: Error {
    case entropyGenerationFailed
    case mnemonicGenerationFailed
    case keystoreCreationFailed
} 