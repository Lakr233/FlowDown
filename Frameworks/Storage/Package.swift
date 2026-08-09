// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "Storage",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
        .macCatalyst(.v16),
    ],
    products: [
        .library(name: "Storage", type: .dynamic, targets: ["Storage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/MarkdownView", exact: "4.2.3"),
        .package(url: "https://github.com/Lakr233/wcdb-spm-prebuilt", from: "2.1.15"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.4.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(path: "../Logger"),
    ],
    targets: [
        .target(name: "Storage", dependencies: [
            .product(name: "MarkdownParser", package: "MarkdownView"),
            .product(name: "WCDBSwift", package: "wcdb-spm-prebuilt"),
            .product(name: "OrderedCollections", package: "swift-collections"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "Logger", package: "Logger"),
        ]),
        .testTarget(
            name: "StorageTests",
            dependencies: [
                "Storage",
                .product(name: "WCDBSwift", package: "wcdb-spm-prebuilt"),
            ],
        ),
    ],
)
