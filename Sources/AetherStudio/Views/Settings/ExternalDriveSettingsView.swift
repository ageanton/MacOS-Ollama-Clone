import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ExternalDriveSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette
    @State private var inputPath: String = ""

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage & External Hard Drive")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("Store large model weights on external SSDs to save internal Mac storage. Aether Studio links Ollama to your external drive automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                // Volume Status Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: coordinator.externalStatus.isExternal ? "externaldrive.fill" : "internaldrive")
                            .font(.system(size: 18))
                            .foregroundStyle(coordinator.externalStatus.isMountedAndWritable ? palette.accent : palette.statusWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(coordinator.externalStatus.volumeName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            Text(coordinator.externalStatus.statusText)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }

                        Spacer()

                        PillBadge(
                            coordinator.externalStatus.isMountedAndWritable ? "Mounted & Ready" : "Disconnected",
                            palette: palette,
                            isAccent: coordinator.externalStatus.isMountedAndWritable,
                            dotColor: coordinator.externalStatus.isMountedAndWritable ? palette.statusHealthy : palette.statusWarning
                        )
                    }

                    if let free = coordinator.externalStatus.freeSpaceGB,
                       let total = coordinator.externalStatus.totalSpaceGB, total > 0 {
                        let usedRatio = max(0.0, min(1.0, (total - free) / total))
                        ProgressView(value: usedRatio)
                            .tint(palette.accent)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairlineBorder, lineWidth: 1))

                // Models Folder Picker Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Models Directory Path")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    HStack(spacing: 8) {
                        TextField("e.g. /Volumes/2TB Oracle Air/models", text: $inputPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onSubmit {
                                coordinator.applyCustomModelsPath(inputPath)
                            }

                        Button("Apply") {
                            coordinator.applyCustomModelsPath(inputPath)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)

                        // 1. Browse Folder button
                        Button("Browse Folder...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Use Models Folder"
                            if panel.runModal() == .OK, let url = panel.url {
                                inputPath = url.path
                                coordinator.applyCustomModelsPath(url.path)
                            }
                        }
                        .buttonStyle(.bordered)

                        // 2. Direct .GGUF File button
                        Button("Select .GGUF File...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Import Model File"
                            panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data, .data]
                            if panel.runModal() == .OK, let url = panel.url {
                                let folder = url.deletingLastPathComponent().path
                                inputPath = folder
                                coordinator.applyCustomModelsPath(folder)

                                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                                let gguf = DiscoveredGGUF(
                                    fileName: url.lastPathComponent,
                                    fullPath: url.path,
                                    fileSizeBytes: size,
                                    volumeName: coordinator.externalStatus.volumeName
                                )
                                coordinator.importRawGGUF(gguf)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        Button("Reset to Internal Default (~/.ollama/models)") {
                            let def = AetherConstants.defaultInternalModelsPath
                            inputPath = def
                            coordinator.applyCustomModelsPath(def)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)

                        Spacer()

                        if let toast = coordinator.statusToast {
                            Text(toast)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                // Discovered GGUF Models Table
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Model Files on Drive (\(coordinator.driveManager.discoveredGGUFModels.count))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            Text("Click 'Load into Chat' to register any raw .gguf model with Ollama instantly.")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                        Button {
                            Task {
                                await coordinator.driveManager.scanForGGUFFiles(in: coordinator.storageConfig.modelsDirectoryPath)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Rescan")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.accent)
                    }

                    if coordinator.driveManager.discoveredGGUFModels.isEmpty {
                        Text("No .gguf files found in this folder. Click 'Browse Folder...' or 'Select .GGUF File...' above to point to your external drive.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.mutedText)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(coordinator.driveManager.discoveredGGUFModels) { gguf in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(gguf.fileName)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.primaryText)
                                        Text("\(gguf.formattedSize) · \(gguf.fullPath)")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(palette.mutedText)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Load into Chat") {
                                        coordinator.importRawGGUF(gguf)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(palette.accent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairlineBorder, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))
            }
            .padding(20)
        }
        .onAppear {
            inputPath = coordinator.storageConfig.modelsDirectoryPath
        }
    }
}
