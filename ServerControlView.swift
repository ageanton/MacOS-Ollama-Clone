import SwiftUI

// MARK: - Visual Model Builder (100% Modelfile Parity Without Writing Syntax)

public struct ModelBuilderView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    @State private var showRawModelfilePreview: Bool = true

    public init(palette: StudioPalette) {
        self.palette = palette
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Visual Model Builder")
                        .font(theme.titleFont())
                        .foregroundStyle(palette.primaryText)
                    Text("Create a custom, reusable Ollama model with baked-in personality, sampling parameters, example dialogue, or local GGUF / LoRA weights.")
                        .font(theme.bodyFont())
                        .foregroundStyle(palette.secondaryText)

                    // 1. Name & Base Model
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Model Identity & Base Weights")
                            .font(theme.bodyFont(weight: .semibold))
                            .foregroundStyle(palette.primaryText)

                        TextField("New Model Name (e.g. writer-pro:latest)", text: $appState.builderDraft.newModelName)
                            .textFieldStyle(.roundedBorder)
                            .font(theme.monoFont(size: 12.5))

                        Toggle("Import from Local .gguf File on Mac", isOn: $appState.builderDraft.isLocalGGUFFile)
                            .font(theme.captionFont())

                        if appState.builderDraft.isLocalGGUFFile {
                            HStack {
                                TextField("/Users/you/Downloads/model.gguf", text: $appState.builderDraft.baseModelOrGGUFPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(theme.monoFont(size: 12))
                                Button("Choose .gguf...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    if panel.runModal() == .OK, let url = panel.url {
                                        appState.builderDraft.baseModelOrGGUFPath = url.path
                                    }
                                }
                            }
                        } else {
                            Picker("Base Installed Model (FROM)", selection: $appState.builderDraft.baseModelOrGGUFPath) {
                                ForEach(appState.installedModels) { m in
                                    Text(m.name).tag(m.name)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                    // 2. Persona Preset Library + System Instructions
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("2. System Persona & Instructions (SYSTEM)")
                                .font(theme.bodyFont(weight: .semibold))
                            Spacer()
                            Menu("Fill from Persona Library") {
                                ForEach(PersonaPreset.library) { preset in
                                    Button("\(preset.title) (\(preset.category))") {
                                        appState.builderDraft.systemPrompt = preset.systemPrompt
                                        appState.builderDraft.dials.temperature = preset.recommendedTemperature
                                        appState.builderDraft.dials.numCtx = preset.recommendedCtx
                                        appState.builderDraft.exampleDialogue = preset.sampleTurns
                                    }
                                }
                            }
                            .font(theme.captionFont())
                            .frame(width: 180)
                        }

                        TextEditor(text: $appState.builderDraft.systemPrompt)
                            .font(theme.bodyFont())
                            .frame(height: 100)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.hairlineBorder, lineWidth: 1))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                    // 3. Baked Default Parameters
                    VStack(alignment: .leading, spacing: 12) {
                        Text("3. Baked Default Parameters (PARAMETER)")
                            .font(theme.bodyFont(weight: .semibold))
                        DialSliderRow(
                            title: "Default Temperature",
                            key: "temperature",
                            value: $appState.builderDraft.dials.temperature,
                            range: 0.0...2.0,
                            step: 0.05,
                            format: "%.2f",
                            palette: palette
                        )
                        DialIntSliderRow(
                            title: "Default Context Window (num_ctx)",
                            key: "num_ctx",
                            value: $appState.builderDraft.dials.numCtx,
                            range: 2048...65536,
                            palette: palette
                        )
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                    // 4. Few-Shot Example Dialogue Turns (`MESSAGE`)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("4. Few-Shot Example Dialogue (MESSAGE)")
                                .font(theme.bodyFont(weight: .semibold))
                            Spacer()
                            Button("+ Add Example Turn") {
                                appState.builderDraft.exampleDialogue.append(ExampleDialogueTurn(role: .user, content: ""))
                                appState.builderDraft.exampleDialogue.append(ExampleDialogueTurn(role: .assistant, content: ""))
                            }
                            .buttonStyle(.plain)
                            .font(theme.captionFont(weight: .semibold))
                            .foregroundStyle(palette.accent)
                        }

                        ForEach($appState.builderDraft.exampleDialogue) { $turn in
                            HStack {
                                Picker("", selection: $turn.role) {
                                    Text("User").tag(MessageRole.user)
                                    Text("Assistant").tag(MessageRole.assistant)
                                }
                                .frame(width: 100)
                                TextField("Example message...", text: $turn.content)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                    // Build Action
                    HStack(spacing: 14) {
                        Button {
                            appState.buildCustomModelFromDraft()
                        } label: {
                            HStack(spacing: 6) {
                                StudioIcon(.spark, size: 13, color: Color.white)
                                Text(appState.isBuildingModel ? "Building Model..." : "Compile & Save Reusable Model")
                                    .font(theme.bodyFont(weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 6).fill(palette.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isBuildingModel || appState.builderDraft.newModelName.isEmpty)

                        if !appState.builderStatusLog.isEmpty {
                            Text(appState.builderStatusLog)
                                .font(theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
                .padding(28)
            }

            Divider().overlay(palette.hairlineBorder)

            // Live Modelfile Syntax Preview Pane
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Live Modelfile Preview")
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button("Copy Modelfile") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.builderDraft.renderedModelfilePreview(), forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(theme.captionFont(weight: .semibold))
                    .foregroundStyle(palette.accent)
                }
                ScrollView {
                    Text(appState.builderDraft.renderedModelfilePreview())
                        .font(theme.monoFont(size: 11.5))
                        .foregroundStyle(palette.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(18)
            .frame(width: 320)
            .background(palette.subtleSurface)
        }
    }
}

// MARK: - Server Control Center (Every Environment Variable as a Visual Control)

public struct ServerControlView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    public init(palette: StudioPalette) {
        self.palette = palette
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header + Lifecycle Controls
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Control Center")
                            .font(theme.titleFont())
                            .foregroundStyle(palette.primaryText)
                        Text("Configure every Ollama environment variable visually, connect external apps, move model storage, and inspect live engine logs.")
                            .font(theme.bodyFont())
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()

                    HStack(spacing: 8) {
                        Button("Start") {
                            appState.processManager.startManagedServer(config: appState.serverConfig)
                        }
                        .buttonStyle(.plain)
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(palette.statusHealthy)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))

                        Button("Apply & Restart Engine") {
                            appState.serverConfig.enforceSafetyInvariants()
                            appState.persistVault()
                            Task {
                                await appState.processManager.restartServer(with: appState.serverConfig)
                                await appState.refreshEngineStatus()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.accent))

                        Button("Stop") {
                            appState.processManager.stopServer()
                        }
                        .buttonStyle(.plain)
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(palette.statusDanger)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
                    }
                }

                // 1. Apple Silicon Memory & KV Cache Quantization (`OLLAMA_KV_CACHE_TYPE` + `OLLAMA_FLASH_ATTENTION`)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apple Silicon Memory & KV Cache Compression")
                        .font(theme.bodyFont(weight: .semibold))
                    Picker("Conversation Memory Cache Precision (OLLAMA_KV_CACHE_TYPE)", selection: $appState.serverConfig.kvCacheType) {
                        ForEach(KVCacheQuantizationType.allCases) { kv in
                            Text(kv.label).tag(kv)
                        }
                    }
                    Text(appState.serverConfig.kvCacheType.plainEnglishImpact)
                        .font(theme.captionFont())
                        .foregroundStyle(palette.secondaryText)

                    Toggle("Enable Flash Attention (OLLAMA_FLASH_ATTENTION — required for 8-bit/4-bit KV cache)", isOn: $appState.serverConfig.flashAttentionEnabled)
                        .font(theme.bodyFont())

                    HStack(spacing: 18) {
                        Stepper("Parallel Requests (OLLAMA_NUM_PARALLEL): \(appState.serverConfig.numParallel)", value: $appState.serverConfig.numParallel, in: 1...16)
                        Stepper("Max Loaded Models (OLLAMA_MAX_LOADED_MODELS): \(appState.serverConfig.maxLoadedModels)", value: $appState.serverConfig.maxLoadedModels, in: 1...8)
                    }
                    .font(theme.bodyFont())
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                // 2. Model Storage Folder & 1-Click Drive Migration (`OLLAMA_MODELS`)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Model Storage Location (OLLAMA_MODELS)")
                        .font(theme.bodyFont(weight: .semibold))
                    HStack {
                        TextField("Models Path", text: $appState.serverConfig.modelsDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                            .font(theme.monoFont(size: 12))
                        Button("Move to Another Drive...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.prompt = "Select New Models Folder"
                            if panel.runModal() == .OK, let url = panel.url {
                                let oldPath = appState.serverConfig.modelsDirectoryPath
                                let newPath = url.path
                                appState.serverConfig.modelsDirectoryPath = newPath
                                appState.persistVault()
                                Task {
                                    try? await appState.processManager.migrateModelsStorage(from: oldPath, to: newPath)
                                }
                            }
                        }
                    }
                    Text(String(format: "Free space on system drive: %.1f GB", appState.hardware.freeDiskSpaceGB))
                        .font(theme.captionFont())
                        .foregroundStyle(palette.mutedText)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                // 3. Network & 1-Click External App Bridges (`OLLAMA_HOST`, `OLLAMA_ORIGINS`)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Network & External App Bridges (Obsidian, Cursor, Continue)")
                        .font(theme.bodyFont(weight: .semibold))
                    HStack {
                        TextField("Host (127.0.0.1)", text: $appState.serverConfig.hostAddress)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        TextField("Allowed CORS Origins (OLLAMA_ORIGINS)", text: $appState.serverConfig.allowedOrigins)
                            .textFieldStyle(.roundedBorder)
                    }
                    .font(theme.monoFont(size: 12))

                    Toggle("Allow other devices on my local Wi-Fi to use this Mac's models (binds 0.0.0.0)", isOn: $appState.serverConfig.exposeOnLocalNetwork)
                        .font(theme.captionFont())

                    ForEach(ExternalAppBridge.allBridges(port: appState.serverConfig.port)) { bridge in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bridge.appName).font(theme.bodyFont(weight: .medium))
                                Text(bridge.setupInstructions).font(theme.captionFont()).foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                            Button("Copy Endpoint (\(bridge.endpointToPaste))") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(bridge.endpointToPaste, forType: .string)
                            }
                            .buttonStyle(.plain)
                            .font(theme.monoFont(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))

                // 4. Built-in Live Log Viewer & 1-Click Diagnostics Bundle
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Live Engine Log Viewer")
                            .font(theme.bodyFont(weight: .semibold))
                        Toggle("Verbose Debug Logs (OLLAMA_DEBUG)", isOn: $appState.serverConfig.debugLogging)
                            .font(theme.captionFont())
                        Spacer()
                        Button("Export 1-Click Diagnostics to Desktop") {
                            if let url = appState.processManager.exportDiagnosticsBundle(
                                config: appState.serverConfig,
                                hardware: appState.hardware,
                                models: appState.installedModels
                            ) {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                        .buttonStyle(.plain)
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(palette.accent)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(appState.processManager.logLines) { entry in
                                Text(entry.line)
                                    .font(theme.monoFont(size: 11))
                                    .foregroundStyle(entry.isErrorOrWarn ? palette.statusWarning : palette.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))
            }
            .padding(28)
        }
    }
}

// MARK: - Settings Sheet (`⌘,`) & Trash Recovery Sheet

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    public let palette: StudioPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Studio Appearance & Privacy")
                    .font(theme.titleFont())
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(weight: .semibold))
                    .foregroundStyle(palette.accent)
            }

            Picker("Appearance Mode", selection: $theme.appearancePreference) {
                ForEach(AppearancePreference.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Studio Color Palettes")
                .font(theme.captionFont(weight: .semibold))
                .foregroundStyle(palette.mutedText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(StudioThemeID.allCases) { t in
                    let isSelected = theme.selectedTheme == t
                    Button {
                        theme.selectedTheme = t
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.displayName)
                                    .font(theme.bodyFont(weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                if isSelected {
                                    StudioIcon(.check, size: 12, color: palette.accent)
                                }
                            }
                            Text(t.subtitle)
                                .font(theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? palette.accentSoft : palette.subtleSurface))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? palette.accent : palette.hairlineBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(palette.hairlineBorder)

            Picker("Typography Family", selection: $theme.selectedFont) {
                ForEach(StudioFontFamily.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }

            Toggle("Comfortable Conversation Reading Size (15pt)", isOn: $theme.useComfortableTextSize)
                .font(theme.bodyFont())

            HStack(spacing: 8) {
                StudioIcon(.lock, size: 14, color: palette.accent)
                Text("All conversations are encrypted at rest with AES-GCM 256-bit encryption in ~/Library/Application Support/OllamaStudio/vault.enc. Zero telemetry is ever collected.")
                    .font(theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(palette.cardSurface)
    }
}

public struct TrashRecoverySheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    public let palette: StudioPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Deleted Chats & Models (Trash)")
                    .font(theme.titleFont())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
            }
            if appState.trashedItems.isEmpty {
                Text("Trash is empty.")
                    .font(theme.bodyFont())
                    .foregroundStyle(palette.mutedText)
            } else {
                ForEach(appState.trashedItems) { item in
                    HStack {
                        Text(item.summaryTitle)
                            .font(theme.bodyFont(weight: .medium))
                        Spacer()
                        Button("Restore") {
                            appState.restoreFromTrash(item.id)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.accent)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(palette.cardSurface)
    }
}
