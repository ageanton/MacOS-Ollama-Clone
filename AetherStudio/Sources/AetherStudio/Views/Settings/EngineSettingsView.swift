import SwiftUI

public struct EngineSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ollama Engine & Daemon Supervisor")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("Control background process lifecycle and network bindings.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                // Status & Controls
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Engine Status")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            Text(coordinator.isEngineOnline ? "Ollama v\(coordinator.engineVersion) listening on \(coordinator.storageConfig.baseURLString)" : "Offline")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                        PillBadge(
                            coordinator.isEngineOnline ? "Online" : "Offline",
                            palette: palette,
                            isAccent: coordinator.isEngineOnline,
                            dotColor: coordinator.isEngineOnline ? palette.statusHealthy : palette.statusDanger
                        )
                    }

                    HStack(spacing: 10) {
                        Button("Restart Engine") {
                            Task {
                                await coordinator.supervisor.restartEngine(config: coordinator.storageConfig)
                                await coordinator.refreshEngine()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)

                        Button("Stop Engine") {
                            coordinator.supervisor.stopEngine()
                            Task { await coordinator.refreshEngine() }
                        }
                        .buttonStyle(.bordered)
                        .tint(palette.statusDanger)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                // Network & Optimizations
                VStack(alignment: .leading, spacing: 12) {
                    Text("Optimizations & Binary")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    Toggle("Enable Flash Attention (OLLAMA_FLASH_ATTENTION=1)", isOn: $coordinator.storageConfig.flashAttention)
                        .font(.system(size: 12.5))
                        .onChange(of: coordinator.storageConfig.flashAttention) { _ in
                            coordinator.storageConfig.save()
                        }

                    if let bin = coordinator.supervisor.detectedBinaryPath {
                        HStack {
                            Text("Ollama Binary:")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                            Text(bin)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.mutedText)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                // Supervisor Live Logs
                VStack(alignment: .leading, spacing: 8) {
                    Text("Supervisor Logs")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(coordinator.supervisor.logs.indices, id: \.self) { i in
                                Text(coordinator.supervisor.logs[i])
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 180)
                    .background(palette.codeSurface)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairlineBorder, lineWidth: 1))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))
            }
            .padding(20)
        }
    }
}
