// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mactrax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mactrax", targets: ["Mactrax"])
    ],
    targets: [
        .executableTarget(
            name: "Mactrax",
            path: "Sources/Mactrax",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MactraxTests",
            dependencies: ["Mactrax"],
            path: "Tests/MactraxTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
