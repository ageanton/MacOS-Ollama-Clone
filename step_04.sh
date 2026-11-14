set -eo pipefail
cat << 'EOF' > Motif/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Motif",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Motif", targets: ["Motif"])
    ],
    targets: [
        .executableTarget(
            name: "Motif",
            path: "Sources/Motif",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Combine"),
                .linkedFramework("CoreText"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
EOF
