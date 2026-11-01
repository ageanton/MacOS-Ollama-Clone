import SwiftUI

public struct ModelPickerMenu: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette
    @State private var isPresented: Bool = false

    public var body: some View {
        let activeModel = coordinator.activeConversation?.selectedModel ?? ""
        let isLoaded = coordinator.runningModels.contains(where: { $0.name == activeModel })

        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isLoaded ? palette.statusHealthy : (activeModel.isEmpty ? palette.mutedText : palette.accent))
                    .frame(width: 7, height: 7)

                Text(activeModel.isEmpty ? "Select Model" : activeModel.replacingOccurrences(of: ":latest", with: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: AetherMetrics.controlCornerRadius).fill(palette.subtleSurface))
            .overlay(RoundedRectangle(cornerRadius: AetherMetrics.controlCornerRadius).stroke(palette.hairlineBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Select Model")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    Button("Storage & External Drive...") {
                        isPresented = false
                        coordinator.selectedSettingsTab = .externalDrive
                        coordinator.isSettingsOpen = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.accent)
                }

                Divider().overlay(palette.hairlineBorder)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Section 1: Installed in Ollama
                        if !coordinator.installedModels.isEmpty {
                            Text("Installed Models (\(coordinator.installedModels.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondaryText)

                            ForEach(coordinator.installedModels) { model in
                                let isSelected = coordinator.activeConversation?.selectedModel == model.name
                                let running = coordinator.runningModels.first(where: { $0.name == model.name })

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.cleanDisplayName)
                                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(palette.primaryText)
                                        HStack(spacing: 6) {
                                            Text(model.formattedSize)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(palette.mutedText)
                                            Text(model.quantizationText)
                                                .font(.system(size: 10.5, design: .monospaced))
                                                .foregroundStyle(palette.mutedText)
                                            if let r = running {
                                                Text(r.formattedVRAM)
                                                    .font(.system(size: 10.5, weight: .medium))
                                                    .foregroundStyle(palette.statusHealthy)
                                            }
                                        }
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(palette.accent)
                                    }
                                }
                                .padding(7)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? palette.accentSoft : palette.cardSurface)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.selectModelForActiveConversation(model.name)
                                    isPresented = false
                                }
                            }
                        }

                        // Section 2: Discovered on External Drive
                        if !coordinator.driveManager.discoveredGGUFModels.isEmpty {
                            Divider().padding(.vertical, 2)

                            HStack {
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(palette.accent)
                                Text("Models on External Drive (\(coordinator.driveManager.discoveredGGUFModels.count))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }

                            ForEach(coordinator.driveManager.discoveredGGUFModels) { gguf in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(gguf.fileName)
                                            .font(.system(size: 12))
                                            .foregroundStyle(palette.primaryText)
                                            .lineLimit(1)
                                        Text("\(gguf.formattedSize) · \(gguf.volumeName)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(palette.mutedText)
                                    }
                                    Spacer()
                                    Button("Load into Chat") {
                                        coordinator.importRawGGUF(gguf)
                                        isPresented = false
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(palette.accent))
                                }
                                .padding(7)
                                .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                            }
                        }

                        if coordinator.installedModels.isEmpty && coordinator.driveManager.discoveredGGUFModels.isEmpty {
                            VStack(spacing: 8) {
                                Text("No models found.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.secondaryText)
                                Button("Select External Drive Models...") {
                                    isPresented = false
                                    coordinator.selectedSettingsTab = .externalDrive
                                    coordinator.isSettingsOpen = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(palette.accent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            .padding(14)
            .frame(width: 380)
            .background(palette.elevatedSurface)
        }
    }
}
