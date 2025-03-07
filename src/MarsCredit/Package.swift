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
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        .package(url: "https://github.com/Boilertalk/Web3.swift.git", from: "0.8.4")
    ],
    targets: [
        .executableTarget(
            name: "MarsCredit",
            dependencies: [
                "CryptoSwift",
                .product(name: "Web3", package: "Web3.swift"),
                .product(name: "Web3PromiseKit", package: "Web3.swift"),
                .product(name: "Web3ContractABI", package: "Web3.swift")
            ],
            resources: [
                .copy("Resources/gunshipboldital.otf")
            ]
        )
    ]
) 