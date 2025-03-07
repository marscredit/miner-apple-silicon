// swift-tools-version:5.9
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
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0")
    ],
    targets: [
        .executableTarget(
            name: "MarsCredit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                "CryptoSwift"
            ],
            path: "src/MarsCredit/Sources"
        )
    ]
) 