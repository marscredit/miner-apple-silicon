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
                    // Check if it's directly an EthereumQuantity
                    if let quantity = hashRate as? EthereumQuantity {
                        print("Hashrate is an EthereumQuantity")
                        let bigUIntValue = quantity.quantity
                        print("Hashrate quantity: \(bigUIntValue)")
                        let value = BigInt(bigUIntValue)
                        print("Parsed hashrate: \(value)")
                        seal.fulfill(value)
                    } 
                    // Fallback to string parsing
                    else if let hexString = hashRate.ethereumValue().string {
                        print("Hashrate hex string: \(hexString)")
                        let cleanHex = hexString.stripHexPrefix()
                        if let value = BigInt(cleanHex, radix: 16) {
                            print("Parsed hashrate from hex: \(value)")
                            seal.fulfill(value)
                        } else if let value = BigInt(hexString, radix: 10) {
                            print("Parsed hashrate from decimal: \(value)")
                            seal.fulfill(value)
                        } else {
                            print("Could not parse hashrate string")
                            seal.fulfill(BigInt(0))
                        }
                    } else {
                        print("Unknown hashrate format: \(type(of: hashRate))")
                        seal.fulfill(BigInt(0))
                    }
                case .failure(let error):
                    print("Hashrate request failed: \(error)")
                    seal.fulfill(BigInt(0))
                }
            }
        }
    }
    
    func getSyncStatus() -> Promise<(currentBlock: BigInt, progress: Double)> {
        return Promise { seal in
            web3.eth.syncing { response in
                switch response.status {
                case .success(let result):
                    print("Raw sync status response: \(result), type: \(type(of: result))")
                    
                    // Specific handling for EthereumSyncStatusObject 
                    if let syncStatus = result as? EthereumSyncStatusObject {
                        print("Sync status is an EthereumSyncStatusObject")
                        
                        var currentBlock = BigInt(0)
                        var highestBlock = BigInt(1) // Prevent division by zero
                        
                        // Handle current block
                        if let currentBlockQuantity = syncStatus.currentBlock {
                            let bigUIntValue = currentBlockQuantity.quantity
                            print("Current block from quantity: \(bigUIntValue)")
                            currentBlock = BigInt(bigUIntValue)
                        } else if let currentBlockStr = syncStatus.currentBlock?.ethereumValue().string {
                            print("Current block string: \(currentBlockStr)")
                            let cleanHex = currentBlockStr.stripHexPrefix()
                            if let value = BigInt(cleanHex, radix: 16) {
                                currentBlock = value
                            }
                        }
                        
                        // Handle highest block
                        if let highestBlockQuantity = syncStatus.highestBlock {
                            let bigUIntValue = highestBlockQuantity.quantity
                            print("Highest block from quantity: \(bigUIntValue)")
                            highestBlock = BigInt(bigUIntValue)
                        } else if let highestBlockStr = syncStatus.highestBlock?.ethereumValue().string {
                            print("Highest block string: \(highestBlockStr)")
                            let cleanHex = highestBlockStr.stripHexPrefix()
                            if let value = BigInt(cleanHex, radix: 16) {
                                highestBlock = value
                            }
                        }
                        
                        // Calculate progress
                        let progress: Double
                        if highestBlock > 0 {
                            progress = Double(currentBlock) / Double(highestBlock)
                        } else {
                            progress = 0.0
                        }
                        
                        print("Calculated sync progress: \(progress) (\(currentBlock)/\(highestBlock))")
                        seal.fulfill((currentBlock: currentBlock, progress: progress))
                    } 
                    // If we got here, assume we're actually in sync, so try to get block number
                    else {
                        print("Got non-object sync status: \(result) - assuming synced")
                        self.getBlockNumber().done { blockNumber in
                            print("Current block number: \(blockNumber)")
                            seal.fulfill((currentBlock: blockNumber, progress: 1.0))
                        }.catch { error in
                            print("Failed to get block number after sync check: \(error)")
                            seal.fulfill((currentBlock: BigInt(0), progress: 1.0))
                        }
                    }
                    
                case .failure(let error):
                    print("Sync status request failed: \(error)")
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
                    print("Raw block number response: \(block), type: \(type(of: block))")
                    
                    // Handle EthereumQuantity directly
                    if let quantity = block as? EthereumQuantity {
                        print("Block number is an EthereumQuantity")
                        let bigUIntValue = quantity.quantity
                        print("Block number quantity: \(bigUIntValue)")
                        let value = BigInt(bigUIntValue)
                        print("Parsed block number: \(value)")
                        seal.fulfill(value)
                    } 
                    // Fallback to string parsing
                    else if let hexString = block.ethereumValue().string {
                        print("Block number hex string: \(hexString)")
                        let cleanHex = hexString.stripHexPrefix()
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
        return getBlockNumber()
    }
    
    func getPeerCount() -> Promise<BigInt> {
        return Promise { seal in
            web3.net.peerCount { response in
                switch response.status {
                case .success(let peerCount):
                    print("Raw peer count response: \(peerCount), type: \(type(of: peerCount))")
                    
                    // Handle when peerCount is directly an EthereumQuantity
                    if let quantity = peerCount as? EthereumQuantity {
                        print("Peer count is an EthereumQuantity")
                        let bigUIntValue = quantity.quantity
                        print("Peer count quantity: \(bigUIntValue)")
                        let value = BigInt(bigUIntValue)
                        print("Parsed peer count: \(value)")
                        self.lastKnownPeerCount = value
                        seal.fulfill(value)
                    }
                    
                    // Fallback to string parsing
                    else if let peerCountStr = peerCount.ethereumValue().string {
                        print("Peer count string: \(peerCountStr)")
                        let cleanHex = peerCountStr.stripHexPrefix()
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
        return Promise { seal in
            do {
                let ethereumAddress = try EthereumAddress(hex: address, eip55: true)
                web3.eth.getBalance(address: ethereumAddress, block: .latest) { response in
                    switch response.status {
                    case .success(let balance):
                        print("Raw balance response: \(balance), type: \(type(of: balance))")
                        
                        // Handle when balance is directly an EthereumQuantity
                        if let quantity = balance as? EthereumQuantity {
                            print("Balance is an EthereumQuantity")
                            let bigUIntValue = quantity.quantity
                            print("Balance quantity: \(bigUIntValue)")
                            let value = BigInt(bigUIntValue)
                            print("Parsed balance: \(value) wei")
                            self.lastKnownBalance = value
                            seal.fulfill(value)
                            return
                        }
                        
                        // Fallback to ethereumValue() string
                        if let balanceStr = balance.ethereumValue().string {
                            print("Balance string: \(balanceStr)")
                            let cleanHex = balanceStr.stripHexPrefix()
                            if let value = BigInt(cleanHex, radix: 16) {
                                print("Parsed balance from hex: \(value) wei")
                                self.lastKnownBalance = value
                                seal.fulfill(value)
                            } else if let value = BigInt(balanceStr, radix: 10) {
                                print("Parsed balance from decimal: \(value) wei")
                                self.lastKnownBalance = value
                                seal.fulfill(value)
                            } else {
                                print("Could not parse balance string")
                                seal.fulfill(BigInt(0))
                            }
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
