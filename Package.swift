// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CircuitBreaker",
    platforms: [.iOS(.v15), .macOS(.v13), .watchOS(.v9)],
    products: [
        .library(
            name: "CircuitBreaker",
            targets: ["CircuitBreaker"]),
    ],
    targets: [
        .target(
            name: "CircuitBreaker"),
        .testTarget(
            name: "CircuitBreakerTests",
            dependencies: ["CircuitBreaker"]),
    ]
)
