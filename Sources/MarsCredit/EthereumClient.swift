import Foundation
import Web3
import Web3ContractABI
import BigInt
import PromiseKit
import SwiftUI

// Add extension for String to handle hex prefixes
extension String {
    func stripHexPrefix() -> String {
        if hasPrefix("0x") {
            return String(dropFirst(2))
        }
        return self
    }
}

class EthereumClient {
    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private let web3: Web3
    private let session: URLSession
    private var isConnected = false
    private var lastKnownBlockNumber: BigInt?
    private var lastKnownPeerCount: BigInt?
    private var lastKnownHashRate: BigInt?
    private var lastKnownBalance: BigInt?
    private var lastKnownBlock: Int = 0
    private var highestKnownBlock: Int = 0
    private var isMining = false
    private var networkChainId: Int = 110110 // Default Mars Credit chain ID
    private var networkDifficulty: BigInt = 0
    private var rpcErrorCount = 0
    let rpcURL: String
    
    init(rpcURL: String) {
        self.rpcURL = rpcURL
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: configuration)
        self.web3 = Web3(provider: Web3HttpProvider(rpcURL: rpcURL))
    }
    
    private var dataDirectory: URL {
        return homeDirectory.appendingPathComponent(".marscredit")
    }
    
    func testConnection() -> Promise<Bool> {
        Promise<Bool> { resolver in
            let request = createRPCRequest(method: "net_version", params: [])
            executeRequest(request) { result in
                switch result {
                case .success(let response):
                    self.isConnected = true
                    
                    // Check if we're on the correct Mars Credit network
                    if let chainIdString = response["result"] as? String,
                       let chainId = Int(chainIdString) {
                        self.networkChainId = chainId
                        let isMarsCreditNetwork = chainId == 110110
                        
                        if isMarsCreditNetwork {
                            LogManager.shared.log("Confirmed connection to Mars Credit network (ID: \(chainId))", type: .success)
                        } else {
                            LogManager.shared.log("Connected to Ethereum network with ID: \(chainId). Expected Mars Credit network (110110)", type: .warning)
                        }
                    }
                    
                    self.rpcErrorCount = 0 // Reset error count on successful connection
                    resolver.fulfill(true)
                    
                    // After connection, fetch network difficulty
                    self.getNetworkDifficulty()
                case .failure(let error):
                    self.isConnected = false
                    self.rpcErrorCount += 1
                    LogManager.shared.log("RPC connection error: \(error.localizedDescription)", type: .error)
                    resolver.fulfill(false)
                }
            }
        }
    }
    
    func getNetworkDifficulty() {
        let request = createRPCRequest(method: "eth_getBlockByNumber", params: ["latest", false])
        executeRequest(request) { result in
            switch result {
            case .success(let response):
                if let blockInfo = response["result"] as? [String: Any],
                   let difficultyHex = blockInfo["difficulty"] as? String,
                   let difficulty = BigInt(difficultyHex.dropFirst(2), radix: 16) {
                    self.networkDifficulty = difficulty
                    LogManager.shared.log("Network difficulty: \(difficulty)", type: .debug)
                }
            case .failure:
                // Silently fail, this is just supplementary info
                break
            }
        }
    }
    
    func getNetworkHashrate() -> Promise<BigInt> {
        Promise<BigInt> { resolver in
            // Calculate network hashrate based on difficulty
            if self.networkDifficulty > 0 {
                // A very approximate formula for Ethereum-like PoW
                let networkHashrate = self.networkDifficulty / BigInt(12) // Avg block time in seconds
                resolver.fulfill(networkHashrate)
            } else {
                // If we don't have difficulty, try to get it now
                let request = createRPCRequest(method: "eth_getBlockByNumber", params: ["latest", false])
                executeRequest(request) { result in
                    switch result {
                    case .success(let response):
                        if let blockInfo = response["result"] as? [String: Any],
                           let difficultyHex = blockInfo["difficulty"] as? String,
                           let difficulty = BigInt(difficultyHex.dropFirst(2), radix: 16) {
                            self.networkDifficulty = difficulty
                            let networkHashrate = difficulty / BigInt(12) // Avg block time in seconds
                            resolver.fulfill(networkHashrate)
                        } else {
                            // Fallback to a reasonable estimate for Mars Credit network
                            resolver.fulfill(BigInt(10_000_000_000)) // 10 GH/s
                        }
                    case .failure:
                        // Fallback to a reasonable estimate for Mars Credit network
                        resolver.fulfill(BigInt(10_000_000_000)) // 10 GH/s
                    }
                }
            }
        }
    }
    
    func startMining(address: String) -> Promise<Void> {
        Promise<Void> { resolver in
            LogManager.shared.log("Checking connection to mine on Mars Credit network", type: .info)
            
            // First, test the connection
            self.testConnection().done { connected in
                if connected {
                    LogManager.shared.log("Connection successful, attempting to start mining for address \(address)", type: .info)
                    
                    // Set the miner's address (etherbase)
                    let miningRequest = self.createRPCRequest(method: "miner_setEtherbase", params: [address])
                    self.executeRequest(miningRequest) { result in
                        switch result {
                        case .success:
                            // Now start mining with specified number of threads (1 is a safe default)
                            let startRequest = self.createRPCRequest(method: "miner_start", params: [1])
                            self.executeRequest(startRequest) { startResult in
                                switch startResult {
                                case .success:
                                    self.isMining = true
                                    LogManager.shared.log("Mining started successfully for \(address)", type: .success)
                                    resolver.fulfill(())
                                case .failure(let error):
                                    LogManager.shared.log("Failed to start mining: \(error.localizedDescription)", type: .error)
                                    resolver.reject(error)
                                }
                            }
                        case .failure(let error):
                            LogManager.shared.log("Failed to set mining address: \(error.localizedDescription)", type: .error)
                            resolver.reject(error)
                        }
                    }
                } else {
                    LogManager.shared.log("Connection to Mars Credit network failed", type: .error)
                    resolver.reject(EthereumClientError.connectionFailed)
                }
            }.catch { error in
                LogManager.shared.log("Error connecting to Mars Credit network: \(error.localizedDescription)", type: .error)
                resolver.reject(error)
            }
        }
    }
    
    func stopMining() -> Promise<Void> {
        Promise<Void> { resolver in
            LogManager.shared.log("Stopping mining", type: .info)
            
            let request = createRPCRequest(method: "miner_stop", params: [])
            executeRequest(request) { result in
                switch result {
                case .success:
                    self.isMining = false
                    LogManager.shared.log("Mining stopped successfully", type: .success)
                    resolver.fulfill(())
                case .failure(let error):
                    LogManager.shared.log("Error stopping mining: \(error.localizedDescription)", type: .warning)
                    // We'll still consider mining stopped even if the API call failed
                    self.isMining = false
                    resolver.fulfill(())
                }
            }
        }
    }
    
    func getHashRate() -> Promise<BigInt> {
        Promise<BigInt> { resolver in
            let request = createRPCRequest(method: "eth_hashrate", params: [])
            executeRequest(request) { result in
                switch result {
                case .success(let response):
                    if let hashRateHex = response["result"] as? String {
                        if let hashRate = BigInt(hashRateHex.dropFirst(2), radix: 16) {
                            self.lastKnownHashRate = hashRate
                            resolver.fulfill(hashRate)
                        } else {
                            resolver.reject(EthereumClientError.resultParsingFailed)
                        }
                    } else {
                        // If result is missing, try a fallback method
                        self.executeJS(script: "eth.hashrate").done { resultString in
                            if let hashRate = BigInt(resultString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                resolver.fulfill(hashRate)
                            } else {
                                resolver.fulfill(self.lastKnownHashRate ?? BigInt(0))
                            }
                        }.catch { _ in
                            resolver.fulfill(self.lastKnownHashRate ?? BigInt(0))
                        }
                    }
                case .failure:
                    // Return last known value or fallback to script
                    self.executeJS(script: "eth.hashrate").done { resultString in
                        if let hashRate = BigInt(resultString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            resolver.fulfill(hashRate)
                        } else {
                            resolver.fulfill(self.lastKnownHashRate ?? BigInt(0))
                        }
                    }.catch { _ in
                        resolver.fulfill(self.lastKnownHashRate ?? BigInt(0))
                    }
                }
            }
        }
    }
    
    func getSyncStatus() -> Promise<(currentBlock: BigInt, highestBlock: BigInt, progress: Double)> {
        Promise<(currentBlock: BigInt, highestBlock: BigInt, progress: Double)> { resolver in
            let request = createRPCRequest(method: "eth_syncing", params: [])
            executeRequest(request) { result in
                switch result {
                case .success(let response):
                    if let syncingDict = response["result"] as? [String: Any] {
                        // We're syncing, extract the values
                        if let currentBlockHex = syncingDict["currentBlock"] as? String,
                           let highestBlockHex = syncingDict["highestBlock"] as? String,
                           let currentBlock = BigInt(currentBlockHex.dropFirst(2), radix: 16),
                           let highestBlock = BigInt(highestBlockHex.dropFirst(2), radix: 16) {
                            
                            let progress = highestBlock > 0 ? Double(currentBlock) / Double(highestBlock) : 0
                            LogManager.shared.log("Sync in progress: \(currentBlock)/\(highestBlock) (\(Int(progress * 100))%)", type: .mining)
                            resolver.fulfill((currentBlock: currentBlock, highestBlock: highestBlock, progress: progress))
                        } else {
                            resolver.reject(EthereumClientError.resultParsingFailed)
                        }
                    } else if response["result"] is Bool || response["result"] == nil {
                        // Not syncing, get current block
                        self.getLatestBlock().done { block in
                            // We're not logging "Node fully synced" here anymore
                            resolver.fulfill((currentBlock: block, highestBlock: block, progress: 1.0))
                        }.catch { error in
                            LogManager.shared.log("Error getting block during sync check: \(error)", type: .warning)
                            resolver.fulfill((currentBlock: BigInt(0), highestBlock: BigInt(0), progress: 0.0))
                        }
                    } else {
                        resolver.reject(EthereumClientError.resultParsingFailed)
                    }
                case .failure(let error):
                    LogManager.shared.log("Sync status request failed: \(error)", type: .error)
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getBlockNumber() -> Promise<BigInt> {
        Promise<BigInt> { seal in
            self.web3.eth.blockNumber { response in
                switch response.status {
                case .success(let block):
                    // Handle EthereumQuantity directly
                    if let quantity = block as? EthereumQuantity {
                        let bigUIntValue = quantity.quantity
                        let value = BigInt(bigUIntValue)
                        print("Parsed block number: \(value)")
                        seal.fulfill(value)
                    } else if let hexString = block as? String {
                        // Clean up hex string
                        let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                        
                        if let value = BigInt(cleanHex, radix: 16) {
                            print("Parsed block number from hex: \(value)")
                            seal.fulfill(value)
                        } else if let value = BigInt(hexString, radix: 10) {
                            print("Parsed block number from decimal: \(value)")
                            seal.fulfill(value)
                        } else {
                            print("Could not parse block number string")
                            seal.fulfill(BigInt(0))
                        }
                    } else {
                        print("Unknown block number format: \(type(of: block))")
                        seal.fulfill(BigInt(0))
                    }
                    
                case .failure(let error):
                    print("Block number request failed: \(error)")
                    seal.fulfill(BigInt(0))
                }
            }
        }
    }
    
    func getLatestBlock() -> Promise<BigInt> {
        Promise<BigInt> { resolver in
            let request = createRPCRequest(method: "eth_blockNumber", params: [])
            executeRequest(request) { result in
                switch result {
                case .success(let response):
                    if let blockNumber = response["result"] as? String {
                        if let number = BigInt(blockNumber.dropFirst(2), radix: 16) {
                            resolver.fulfill(number)
                        } else {
                            resolver.reject(EthereumClientError.resultParsingFailed)
                        }
                    } else {
                        resolver.reject(EthereumClientError.missingResult)
                    }
                case .failure(let error):
                    resolver.reject(error)
                }
            }
        }
    }
    
    func getPeerCount() -> Promise<BigInt> {
        Promise<BigInt> { seal in
            self.web3.net.peerCount { response in
                switch response.status {
                case .success(let peerCount):
                    // Handle EthereumQuantity directly
                    if let quantity = peerCount as? EthereumQuantity {
                        let bigUIntValue = quantity.quantity
                        let value = BigInt(bigUIntValue)
                        print("Parsed peer count: \(value)")
                        self.lastKnownPeerCount = value
                        seal.fulfill(value)
                    } else if let peerCountStr = peerCount as? String {
                        // Clean up hex string
                        let cleanHex = peerCountStr.hasPrefix("0x") ? String(peerCountStr.dropFirst(2)) : peerCountStr
                        
                        if let value = BigInt(cleanHex, radix: 16) {
                            print("Parsed peer count from hex: \(value)")
                            self.lastKnownPeerCount = value
                            seal.fulfill(value)
                        } else if let value = BigInt(peerCountStr, radix: 10) {
                            print("Parsed peer count from decimal: \(value)")
                            self.lastKnownPeerCount = value
                            seal.fulfill(value)
                        } else {
                            print("Could not parse peer count string")
                            seal.fulfill(BigInt(0))
                        }
                    } else {
                        print("Unknown peer count format, defaulting to 0")
                        seal.fulfill(BigInt(0))
                    }
                    
                case .failure(let error):
                    print("Peer count request failed: \(error)")
                    seal.fulfill(BigInt(0))
                }
            }
        }
    }
    
    func getBalance(address: String) -> Promise<BigInt> {
        Promise<BigInt> { resolver in
            let formattedAddress = address.hasPrefix("0x") ? address : "0x" + address
            let request = createRPCRequest(method: "eth_getBalance", params: [formattedAddress, "latest"])
            
            executeRequest(request) { result in
                switch result {
                case .success(let response):
                    if let balanceHex = response["result"] as? String {
                        if let balance = BigInt(balanceHex.dropFirst(2), radix: 16) {
                            self.lastKnownBalance = balance
                            resolver.fulfill(balance)
                        } else {
                            LogManager.shared.log("Failed to parse balance result: \(balanceHex)", type: .error)
                            resolver.fulfill(self.lastKnownBalance ?? BigInt(0))
                        }
                    } else {
                        LogManager.shared.log("Missing balance result", type: .error)
                        resolver.fulfill(self.lastKnownBalance ?? BigInt(0))
                    }
                case .failure(let error):
                    LogManager.shared.log("Balance request failed: \(error.localizedDescription)", type: .error)
                    resolver.fulfill(self.lastKnownBalance ?? BigInt(0))
                }
            }
        }
    }
    
    // Get rewards info for a miner
    func getMinerRewards(address: String) -> Promise<(totalBlocks: Int, totalRewards: Double)> {
        return Promise { seal in
            // This would be more involved in a real app, using a proper API or scanning blocks
            // For now, we'll simulate this with a simple query
            
            let script = """
            var blocks = eth.blockNumber;
            var count = 0;
            var rewards = 0;
            for (var i = Math.max(0, blocks - 1000); i <= blocks; i++) {
                var block = eth.getBlock(i);
                if (block && block.miner && block.miner.toLowerCase() === '\(address.lowercased())') {
                    count++;
                    rewards += 3; // Assuming 3 MARS per block
                }
            }
            JSON.stringify({count: count, rewards: rewards});
            """
            
            self.executeJS(script: script).done { result in
                do {
                    if let data = result.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int,
                       let rewards = json["rewards"] as? Double {
                        seal.fulfill((totalBlocks: count, totalRewards: rewards))
                    } else {
                        seal.fulfill((totalBlocks: 0, totalRewards: 0))
                    }
                } catch {
                    seal.fulfill((totalBlocks: 0, totalRewards: 0))
                }
            }.catch { _ in
                seal.fulfill((totalBlocks: 0, totalRewards: 0))
            }
        }
    }
    
    // New method to execute arbitrary JavaScript code
    func executeJS(script: String) -> Promise<String> {
        Promise<String> { resolver in
            let request = createRPCRequest(method: "eth_executeJS", params: [script])
            
            // Add a fallback for regular JavaScript console execution
            let fallbackRequest = createRPCRequest(method: "admin_runConsoleCommand", params: [script])
            
            executeRequest(request) { result in
                switch result {
                case .success(let response):
                    if let result = response["result"] as? String {
                        resolver.fulfill(result)
                    } else if let error = response["error"] as? [String: Any] {
                        // Try fallback if the first method fails
                        self.executeRequest(fallbackRequest) { fallbackResult in
                            switch fallbackResult {
                            case .success(let fallbackResponse):
                                if let result = fallbackResponse["result"] as? String {
                                    resolver.fulfill(result)
                                } else {
                                    resolver.fulfill("")
                                }
                            case .failure:
                                resolver.fulfill("")
                            }
                        }
                    } else {
                        resolver.fulfill("")
                    }
                case .failure:
                    // Try fallback if the first method fails
                    self.executeRequest(fallbackRequest) { fallbackResult in
                        switch fallbackResult {
                        case .success(let fallbackResponse):
                            if let result = fallbackResponse["result"] as? String {
                                resolver.fulfill(result)
                            } else {
                                resolver.fulfill("")
                            }
                        case .failure:
                            resolver.fulfill("")
                        }
                    }
                }
            }
        }
    }
    
    func createRPCRequest(method: String, params: [Any]) -> URLRequest {
        var request = URLRequest(url: URL(string: rpcURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            LogManager.shared.log("Error creating RPC request: \(error.localizedDescription)", type: .error)
        }
        
        return request
    }
    
    func executeRequest(_ request: URLRequest, completion: @escaping (Swift.Result<[String: Any], Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(EthereumClientError.emptyResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(EthereumClientError.invalidJSONFormat))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

enum EthereumClientError: Error {
    case connectionFailed
    case resultParsingFailed
    case missingResult
    case emptyResponse
    case invalidJSONFormat
    case unsupportedOperation
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Mars Credit network"
        case .resultParsingFailed:
            return "Failed to parse result from Mars Credit network"
        case .missingResult:
            return "Mars Credit network response missing expected result"
        case .emptyResponse:
            return "Empty response received from Mars Credit network"
        case .invalidJSONFormat:
            return "Invalid JSON format in Mars Credit network response"
        case .unsupportedOperation:
            return "Unsupported operation on Mars Credit network"
        }
    }
} 
