// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OAuthKit",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(name: "OAuthKit", targets: ["OAuthKit"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OAuthKit",
            dependencies: []
        ),
        .testTarget(
            name: "OAuthKitTests",
            dependencies: ["OAuthKit"]
        ),
    ]
)
