import Foundation
import Web3
import Web3ContractABI
import BigInt
import PromiseKit

class EthereumClient {
    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private let web3: Web3
    private var isConnected = false
    private var lastKnownBlockNumber: BigInt?
    private var lastKnownPeerCount: BigInt?
    private var lastKnownHashRate: BigInt?
    private var lastKnownBalance: BigInt?
    private var lastKnownBlock: Int = 0
    private var highestKnownBlock: Int = 0
    private var isMining = false
    
    init(rpcURL: String) {
        web3 = Web3(provider: Web3HttpProvider(rpcURL: rpcURL))
    }
    
    private var dataDirectory: URL {
        return homeDirectory.appendingPathComponent(".marscredit")
    }
    
    func testConnection() -> Promise<Bool> {
        return Promise { seal in
            web3.net.version { response in
                switch response.status {
                case .success:
                    self.isConnected = true
                    seal.fulfill(true)
                case .failure(let error):
                    print("Connection test failed: \(error)")
                    self.isConnected = false
                    seal.fulfill(false)
                }
            }
        }
    }
    
    func startMining(address: String) throws {
        guard !isMining else { return }
        isMining = true
        
        print("Starting mining process...")
        print("Mining to address: \(address)")
        
        // Verify the address is valid
        do {
            let _ = try EthereumAddress(hex: address, eip55: true)
            print("Address validation successful")
        } catch {
            print("Invalid mining address: \(error)")
            throw error
        }
    }
    
    func stopMining() {
        isMining = false
        print("Mining stopped")
    }
    
    func getHashRate() -> Promise<BigInt> {
        return Promise { seal in
            web3.eth.hashrate { response in
                switch response.status {
                case .success(let hashRate):
                    if let value = BigInt(hashRate.ethereumValue().string ?? "0", radix: 16) {
                        seal.fulfill(value)
                    } else {
                        seal.reject(NSError(domain: "EthereumClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid hash rate value"]))
                    }
                case .failure(let error):
                    seal.reject(error)
                }
            }
        }
    }
    
    func getSyncStatus() -> Promise<(currentBlock: BigInt, progress: Double)> {
        return Promise { seal in
            web3.eth.syncing { response in
                switch response.status {
                case .success(let result):
                    if let syncStatus = result as? EthereumSyncStatusObject {
                        if let currentBlock = syncStatus.currentBlock?.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                            let progress = 0.0 // We'll calculate this based on highest block
                            seal.fulfill((currentBlock: currentBlock, progress: progress))
                        }
                    } else {
                        // Not syncing, we're up to date
                        self.getBlockNumber().done { blockNumber in
                            seal.fulfill((currentBlock: blockNumber, progress: 1.0))
                        }.catch { error in
                            seal.reject(error)
                        }
                    }
                case .failure(let error):
                    seal.reject(error)
                }
            }
        }
    }
    
    func getBlockNumber() -> Promise<BigInt> {
        return Promise { seal in
            web3.eth.blockNumber { response in
                switch response.status {
                case .success(let block):
                    if let blockNumber = BigInt(block.ethereumValue().string ?? "0", radix: 16) {
                        seal.fulfill(blockNumber)
                    } else {
                        seal.reject(NSError(domain: "EthereumClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid block number"]))
                    }
                case .failure(let error):
                    seal.reject(error)
                }
            }
        }
    }
    
    func getLatestBlock() -> Promise<BigInt> {
        return getBlockNumber()
    }
    
    func getPeerCount() -> Promise<BigInt> {
        return Promise { seal in
            web3.net.peerCount { response in
                switch response.status {
                case .success(let peerCount):
                    if let value = peerCount.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                        self.lastKnownPeerCount = value
                        seal.fulfill(value)
                    } else {
                        seal.reject(NSError(domain: "EthereumClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse peer count"]))
                    }
                case .failure(let error):
                    print("Failed to get peer count: \(error)")
                    seal.reject(error)
                }
            }
        }
    }
    
    func getBalance(address: String) -> Promise<BigInt> {
        return Promise { seal in
            do {
                let ethereumAddress = try EthereumAddress(hex: address, eip55: true)
                web3.eth.getBalance(address: ethereumAddress, block: .latest) { response in
                    switch response.status {
                    case .success(let balance):
                        if let balanceValue = BigInt(balance.ethereumValue().string ?? "0", radix: 16) {
                            self.lastKnownBalance = balanceValue
                            seal.fulfill(balanceValue)
                        } else {
                            seal.reject(NSError(domain: "EthereumClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid balance value"]))
                        }
                    case .failure(let error):
                        seal.reject(error)
                    }
                }
            } catch {
                seal.reject(error)
            }
        }
    }
} 