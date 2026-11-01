// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AetherStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AetherStudio",
            targets: ["AetherStudio"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AetherStudio",
            path: "Sources/AetherStudio",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("DiskArbitration"),
                .linkedFramework("Security"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("CoreText")
            ]
        )
    ]
)
