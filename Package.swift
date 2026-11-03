// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chilltrax",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Chilltrax", targets: ["Chilltrax"])
    ],
    targets: [
        .executableTarget(
            name: "Chilltrax",
            path: "Sources/Chilltrax",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ChilltraxTests",
            dependencies: ["Chilltrax"],
            path: "Tests/ChilltraxTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
