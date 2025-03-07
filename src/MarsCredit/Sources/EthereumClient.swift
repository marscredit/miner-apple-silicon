import Foundation
import Web3
import Web3PromiseKit
import Web3ContractABI
import BigInt

class EthereumClient {
    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var web3: Web3?
    private var lastKnownBlock: Int = 0
    private var highestKnownBlock: Int = 0
    private var isMining = false
    
    init() {
        setupWeb3Client()
    }
    
    private var dataDirectory: URL {
        return homeDirectory.appendingPathComponent(".marscredit")
    }
    
    private func setupWeb3Client() {
        let clientUrl = "https://rpc.marscredit.xyz:443"
        print("Connecting to Mars Credit network at \(clientUrl)...")
        web3 = Web3(rpcURL: clientUrl)
        
        // Test connection
        if let blockNumber = try? web3?.eth.blockNumber().wait() {
            print("Connected to Mars Credit network. Current block: \(blockNumber)")
            if let value = blockNumber.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                print("Parsed block number: \(value)")
                self.lastKnownBlock = Int(value)
                self.highestKnownBlock = self.lastKnownBlock
            } else {
                print("Failed to parse block number value: \(blockNumber.ethereumValue().string ?? "nil")")
            }
        } else {
            print("Failed to connect to Mars Credit network")
        }
        
        // Test peer connection
        if let peerCount = try? web3?.net.peerCount().wait() {
            print("Connected peers: \(peerCount)")
        } else {
            print("Failed to get peer count")
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
    
    func getHashRate() -> UInt64 {
        guard let web3 = web3 else {
            print("Cannot get hash rate - web3 client not initialized")
            return 0
        }
        
        do {
            let hashRate = try web3.eth.hashrate().wait()
            print("Raw hash rate response: \(hashRate)")
            if let value = hashRate.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                print("Parsed hash rate: \(value) H/s")
                return UInt64(value)
            }
            print("Failed to parse hash rate value")
            return 0
        } catch {
            print("Failed to get hash rate: \(error)")
            return 0
        }
    }
    
    func getSyncStatus() -> (progress: Double, currentBlock: Int, targetBlock: Int) {
        guard let web3 = web3 else {
            print("Cannot get sync status - web3 client not initialized")
            return (1.0, 0, 0)
        }
        
        // Get current block
        if let blockNumber = try? web3.eth.blockNumber().wait() {
            print("Current block number response: \(blockNumber)")
            if let value = blockNumber.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                print("Parsed current block: \(value)")
                lastKnownBlock = Int(value)
            } else {
                print("Failed to parse current block number")
            }
        } else {
            print("Failed to get current block number")
        }
        
        // Get sync status
        if let syncStatus = try? web3.eth.syncing().wait() {
            print("Sync status response: \(syncStatus)")
            
            if let highestBlock = syncStatus.highestBlock?.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }),
               let currentBlock = syncStatus.currentBlock?.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }),
               let startingBlock = syncStatus.startingBlock?.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                
                let highestBlockInt = Int(highestBlock)
                let currentBlockInt = Int(currentBlock)
                let startingBlockInt = Int(startingBlock)
                
                print("Sync progress:")
                print("- Starting block: \(startingBlockInt)")
                print("- Current block: \(currentBlockInt)")
                print("- Highest block: \(highestBlockInt)")
                
                highestKnownBlock = highestBlockInt
                let progress = Double(currentBlockInt - startingBlockInt) / Double(highestBlockInt - startingBlockInt)
                print("- Calculated progress: \(progress * 100)%")
                
                return (
                    progress: progress,
                    currentBlock: currentBlockInt,
                    targetBlock: highestBlockInt
                )
            } else {
                print("Failed to parse sync status values")
            }
        } else {
            print("Failed to get sync status")
        }
        
        print("Using fallback sync values - assuming fully synced")
        return (1.0, lastKnownBlock, lastKnownBlock)
    }
    
    func getPeerCount() -> Int {
        guard let web3 = web3 else {
            print("Cannot get peer count - web3 client not initialized")
            return 0
        }
        
        do {
            let peerCount = try web3.net.peerCount().wait()
            print("Raw peer count response: \(peerCount)")
            if let value = peerCount.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                print("Parsed peer count: \(value)")
                return Int(value)
            }
            print("Failed to parse peer count value")
            return 0
        } catch {
            print("Failed to get peer count: \(error)")
            return 0
        }
    }
    
    func getBalance(address: String) throws -> UInt64 {
        guard let web3 = web3 else {
            print("Cannot get balance - web3 client not initialized")
            return 0
        }
        
        do {
            let ethAddress = try EthereumAddress(hex: address, eip55: true)
            print("Getting balance for address: \(ethAddress.hex())")
            
            let balance = try web3.eth.getBalance(address: ethAddress, block: .latest).wait()
            print("Raw balance response: \(balance)")
            
            if let value = balance.ethereumValue().string.flatMap({ BigInt($0, radix: 16) }) {
                print("Parsed balance: \(value) wei")
                return UInt64(value)
            }
            print("Failed to parse balance value")
            return 0
        } catch {
            print("Failed to get balance: \(error)")
            throw error
        }
    }
} 