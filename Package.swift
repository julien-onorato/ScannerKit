// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScannerKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(
            name: "ScannerKit",
            targets: ["ScannerKit"]),
    ],
    targets: [
        .target(
            name: "ScannerKit"),
        .testTarget(
            name: "ScannerKitTests",
            dependencies: ["ScannerKit"]
        ),
    ]
)
