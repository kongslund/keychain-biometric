// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "keychain-biometric",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "keychain-biometric",
            targets: ["keychain-biometric"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        .target(
            name: "KeychainBiometricLib",
            path: "Sources/KeychainBiometricLib"
        ),
        .executableTarget(
            name: "keychain-biometric",
            dependencies: [
                "KeychainBiometricLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/keychain-biometric"
        ),
        .testTarget(
            name: "KeychainBiometricLibTests",
            dependencies: ["KeychainBiometricLib"],
            path: "Tests/KeychainBiometricLibTests"
        ),
    ]
)
