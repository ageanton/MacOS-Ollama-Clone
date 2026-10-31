// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OllamaStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OllamaStudio",
            targets: ["OllamaStudio"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OllamaStudio",
            path: "Sources/OllamaStudio",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("PDFKit")
            ]
        )
    ]
)
