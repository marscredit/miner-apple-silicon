// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarsCredit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MarsCredit", targets: ["MarsCredit"])
    ],
    dependencies: [
        .package(url: "https://github.com/Boilertalk/Web3.swift.git", from: "0.8.8"),
        .package(url: "https://github.com/mxcl/PromiseKit.git", from: "6.22.1"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.4"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.5.1")
    ],
    targets: [
        .executableTarget(
            name: "MarsCredit",
            dependencies: [
                .product(name: "Web3", package: "Web3.swift"),
                .product(name: "Web3ContractABI", package: "Web3.swift"),
                .product(name: "PromiseKit", package: "PromiseKit"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "BigInt", package: "BigInt")
            ],
            resources: [
                .copy("Resources/gunshipboldital.otf")
            ]
        )
    ]
) 