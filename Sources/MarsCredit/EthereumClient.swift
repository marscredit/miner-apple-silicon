import Foundation
import Web3
import Web3ContractABI
import BigInt
import PromiseKit
import SwiftUI

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
    
    func startMining(address: String) -> Promise<Void> {
        return Promise { seal in
            print("Checking connection to remote node")
            
            // First, test the connection
            self.testConnection().done { connected in
                if connected {
                    print("Connection successful, attempting to start mining")
                    self.isMining = true
                    seal.fulfill(())
                } else {
                    print("Connection to remote node failed")
                    seal.reject(NSError(domain: "EthereumClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to remote node"]))
                }
            }.catch { error in
                print("Error connecting to remote node: \(error)")
                seal.reject(error)
            }
        }
    }
    
    func stopMining() -> Promise<Void> {
        return Promise { seal in
            print("Stopping mining")
            self.isMining = false
            seal.fulfill(())
        }
    }
    
    func getHashRate() -> Promise<BigInt> {
        return Promise { seal in
            web3.eth.hashrate { response in
                switch response.status {
                case .success(let hashRate):
                    print("Raw hashrate response: \(hashRate)")
                    // Try to handle both string and numeric formats
                    if let hexString = hashRate.ethereumValue().string {
                        print("Hashrate hex string: \(hexString)")
                        if let value = BigInt(hexString, radix: 16) {
                            seal.fulfill(value)
                        } else if let value = BigInt(hexString, radix: 10) {
                            seal.fulfill(value)
                        } else {
                            seal.fulfill(BigInt(0)) // Assume zero hashrate if parsing fails
                        }
                    } else if let numValue = hashRate as? Int {
                        seal.fulfill(BigInt(numValue))
                    } else {
                        print("Unable to parse hashrate, defaulting to 0")
                        seal.fulfill(BigInt(0))
                    }
                case .failure(let error):
                    print("Hashrate request failed: \(error)")
                    seal.fulfill(BigInt(0)) // Return 0 instead of failing
                }
            }
        }
    }
    
    func getSyncStatus() -> Promise<(currentBlock: BigInt, progress: Double)> {
        return Promise { seal in
            web3.eth.syncing { response in
                switch response.status {
                case .success(let result):
                    print("Raw sync status response: \(result)")
                    
                    if let syncStatus = result as? EthereumSyncStatusObject {
                        print("Sync status object: \(syncStatus)")
                        
                        var currentBlock = BigInt(0)
                        if let currentBlockStr = syncStatus.currentBlock?.ethereumValue().string {
                            print("Current block string: \(currentBlockStr)")
                            if let value = BigInt(currentBlockStr, radix: 16) {
                                currentBlock = value
                            } else if let value = BigInt(currentBlockStr, radix: 10) {
                                currentBlock = value
                            }
                        }
                        
                        var highestBlock = BigInt(1) // Prevent division by zero
                        if let highestBlockStr = syncStatus.highestBlock?.ethereumValue().string {
                            print("Highest block string: \(highestBlockStr)")
                            if let value = BigInt(highestBlockStr, radix: 16) {
                                highestBlock = value
                            } else if let value = BigInt(highestBlockStr, radix: 10) {
                                highestBlock = value
                            }
                        }
                        
                        let progress: Double = highestBlock > 0 ? Double(currentBlock) / Double(highestBlock) : 0.0
                        print("Calculated sync progress: \(progress)")
                        seal.fulfill((currentBlock: currentBlock, progress: progress))
                    } else if let boolValue = result as? Bool, boolValue == false {
                        // Not syncing, we're up to date
                        print("Node is synced (false returned)")
                        self.getBlockNumber().done { blockNumber in
                            seal.fulfill((currentBlock: blockNumber, progress: 1.0))
                        }.catch { _ in
                            // Even if getting block number fails, return sensible defaults
                            seal.fulfill((currentBlock: BigInt(0), progress: 1.0))
                        }
                    } else {
                        // Unknown response format, assume synced
                        print("Unknown sync status format: \(type(of: result)), assuming synced")
                        seal.fulfill((currentBlock: BigInt(0), progress: 1.0))
                    }
                    
                case .failure(let error):
                    print("Sync status request failed: \(error)")
                    // Even if request fails, return sensible defaults
                    seal.fulfill((currentBlock: BigInt(0), progress: 0.0))
                }
            }
        }
    }
    
    func getBlockNumber() -> Promise<BigInt> {
        return Promise { seal in
            web3.eth.blockNumber { response in
                switch response.status {
                case .success(let block):
                    print("Raw block number response: \(block)")
                    // Try to handle both string and numeric formats
                    if let hexString = block.ethereumValue().string {
                        print("Block number hex string: \(hexString)")
                        if let value = BigInt(hexString, radix: 16) {
                            seal.fulfill(value)
                        } else if let value = BigInt(hexString, radix: 10) {
                            seal.fulfill(value)
                        } else {
                            seal.fulfill(BigInt(0)) // Assume block 0 if parsing fails
                        }
                    } else if let numValue = block as? Int {
                        seal.fulfill(BigInt(numValue))
                    } else {
                        print("Unable to parse block number, defaulting to 0")
                        seal.fulfill(BigInt(0))
                    }
                case .failure(let error):
                    print("Block number request failed: \(error)")
                    seal.fulfill(BigInt(0)) // Return 0 instead of failing
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
                        print("Raw balance response: \(balance)")
                        
                        if let balanceStr = balance.ethereumValue().string {
                            print("Balance string: \(balanceStr)")
                            if let value = BigInt(balanceStr, radix: 16) {
                                self.lastKnownBalance = value
                                seal.fulfill(value)
                            } else if let value = BigInt(balanceStr, radix: 10) {
                                self.lastKnownBalance = value
                                seal.fulfill(value)
                            } else {
                                print("Unable to parse balance, defaulting to 0")
                                seal.fulfill(BigInt(0))
                            }
                        } else if let numValue = balance as? Int {
                            self.lastKnownBalance = BigInt(numValue)
                            seal.fulfill(BigInt(numValue))
                        } else {
                            print("Unknown balance format, defaulting to 0")
                            seal.fulfill(BigInt(0))
                        }
                    case .failure(let error):
                        print("Balance request failed: \(error)")
                        seal.fulfill(BigInt(0))
                    }
                }
            } catch {
                print("Invalid address format: \(error)")
                seal.fulfill(BigInt(0))
            }
        }
    }
} 