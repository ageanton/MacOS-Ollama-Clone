import SwiftUI

public struct ModelsManagerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    @State private var pullInputText: String = ""
    @State private var duplicateSourceModel: String? = nil
    @State private var duplicateTargetName: String = ""

    public init(palette: StudioPalette) {
        self.palette = palette
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Models & Unified Memory")
                            .font(theme.titleFont())
                            .foregroundStyle(palette.primaryText)
                        Text("Download any Ollama or Hugging Face GGUF model, pre-warm models into Apple Silicon RAM, or inspect internal Modelfiles.")
                            .font(theme.bodyFont())
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Button {
                        Task { await appState.refreshEngineStatus() }
                    } label: {
                        HStack(spacing: 5) {
                            StudioIcon(.refresh, size: 12, color: palette.secondaryText)
                            Text("Refresh")
                                .font(theme.captionFont(weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
                    }
                    .buttonStyle(.plain)
                }

                // 1. Direct Hugging Face & Ollama Model Puller (Resumable)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Direct Model & Hugging Face Puller")
                        .font(theme.bodyFont(weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    Text("Paste any Hugging Face GGUF repository URL (e.g., https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF) or Ollama tag (e.g., deepseek-r1:8b, qwen3:8b, gemma3:4b). Downloads resume automatically if interrupted.")
                        .font(theme.captionFont())
                        .foregroundStyle(palette.secondaryText)

                    HStack(spacing: 10) {
                        TextField("Paste Hugging Face URL, hf.co/user/repo, or model tag...", text: $pullInputText)
                            .textFieldStyle(.plain)
                            .font(theme.monoFont(size: 12.5))
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.hairlineBorder, lineWidth: 1))
                            .onSubmit {
                                appState.startOrResumeModelPull(rawIdentifier: pullInputText)
                                pullInputText = ""
                            }

                        Button {
                            appState.startOrResumeModelPull(rawIdentifier: pullInputText)
                            pullInputText = ""
                        } label: {
                            HStack(spacing: 6) {
                                StudioIcon(.download, size: 13, color: Color.white)
                                Text("Pull Model")
                                    .font(theme.bodyFont(weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 6).fill(palette.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(pullInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // Active & Paused Resumable Download Rows
                    ForEach(appState.activePullTasks) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(task.id)
                                    .font(theme.monoFont(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                Text(task.formattedProgress)
                                    .font(theme.monoFont(size: 11.5))
                                    .foregroundStyle(palette.secondaryText)

                                if task.isPaused {
                                    Button("Resume") {
                                        appState.startOrResumeModelPull(rawIdentifier: task.id)
                                    }
                                    .buttonStyle(.plain)
                                    .font(theme.captionFont(weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                } else {
                                    Button("Pause") {
                                        appState.pauseModelPull(identifier: task.id)
                                    }
                                    .buttonStyle(.plain)
                                    .font(theme.captionFont())
                                    .foregroundStyle(palette.secondaryText)
                                }
                            }
                            ProgressView(value: task.fractionCompleted)
                                .tint(palette.accent)
                            Text(task.statusText)
                                .font(theme.captionFont())
                                .foregroundStyle(palette.mutedText)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.cardSurface))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.hairlineBorder, lineWidth: 1))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius).fill(palette.subtleSurface))
                .overlay(RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius).strokeBorder(palette.hairlineBorder, lineWidth: 1))

                // 2. Currently Loaded in Apple Silicon RAM (`/api/ps`)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Currently Loaded in Unified Memory (\(appState.runningModels.count))")
                        .font(theme.bodyFont(weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    if appState.runningModels.isEmpty {
                        Text("No models are currently occupying RAM. Pre-warm any model below or start chatting to load weights automatically.")
                            .font(theme.captionFont())
                            .foregroundStyle(palette.mutedText)
                            .padding(12)
                    } else {
                        ForEach(appState.runningModels) { running in
                            HStack(spacing: 12) {
                                Circle().fill(palette.statusHealthy).frame(width: 8, height: 8)
                                Text(running.name)
                                    .font(theme.bodyFont(weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                StudioPillBadge(running.formattedVRAM, palette: palette, isAccent: true)
                                StudioPillBadge("\(running.metalOffloadPercentage)% Apple Metal GPU", palette: palette)
                                Spacer()
                                Button {
                                    appState.ejectModelFromRAM(running.name)
                                } label: {
                                    HStack(spacing: 4) {
                                        StudioIcon(.eject, size: 12, color: palette.statusDanger)
                                        Text("Unload from RAM")
                                            .font(theme.captionFont(weight: .semibold))
                                            .foregroundStyle(palette.statusDanger)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(palette.subtleSurface))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(palette.subtleSurface))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.hairlineBorder, lineWidth: 1))
                        }
                    }
                }

                // 3. Installed Local Models Table + Hardware Compatibility Badges
                VStack(alignment: .leading, spacing: 10) {
                    Text("Installed Models on Disk (\(appState.installedModels.count))")
                        .font(theme.bodyFont(weight: .semibold))
                        .foregroundStyle(palette.primaryText)

                    ForEach(appState.installedModels) { model in
                        let isActiveInChat = appState.activeConversation?.selectedModel == model.name
                        let isLoadedInRAM = appState.runningModels.contains(where: { $0.name == model.name })
                        let compat = appState.hardware.evaluateModelCompatibility(modelSizeBytes: model.size)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(model.name)
                                        .font(theme.bodyFont(weight: .semibold))
                                        .foregroundStyle(palette.primaryText)
                                    StudioPillBadge(model.formattedSize, palette: palette)
                                    if let quant = model.details?.quantizationLevel {
                                        StudioPillBadge(quant, palette: palette)
                                    }
                                    if model.isLikelyVisionModel {
                                        StudioPillBadge("Vision", palette: palette, isAccent: true)
                                    }
                                    if model.isLikelyReasoningModel {
                                        StudioPillBadge("Reasoning", palette: palette, isAccent: true)
                                    }
                                }

                                // Hardware Fit Warning / Badge
                                switch compat {
                                case .runsGreat(let msg):
                                    Text(msg).font(theme.captionFont()).foregroundStyle(palette.statusHealthy)
                                case .runsModerately(let msg):
                                    Text(msg).font(theme.captionFont()).foregroundStyle(palette.statusWarning)
                                case .tooHeavy(let msg):
                                    Text(msg).font(theme.captionFont(weight: .medium)).foregroundStyle(palette.statusDanger)
                                }
                            }

                            Spacer()

                            // Use in Active Chat
                            Button(isActiveInChat ? "Active in Chat" : "Use in Chat") {
                                if let idx = appState.activeConversationIndex {
                                    appState.conversations[idx].selectedModel = model.name
                                    appState.persistVault()
                                    appState.selectedTab = .chat
                                }
                            }
                            .buttonStyle(.plain)
                            .font(theme.captionFont(weight: .semibold))
                            .foregroundStyle(isActiveInChat ? Color.white : palette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5.5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(isActiveInChat ? palette.accent : palette.accentSoft))

                            // Pre-warm or Eject
                            if isLoadedInRAM {
                                Button("Eject RAM") {
                                    appState.ejectModelFromRAM(model.name)
                                }
                                .buttonStyle(.plain)
                                .font(theme.captionFont())
                                .foregroundStyle(palette.statusDanger)
                            } else {
                                Menu("Load into RAM") {
                                    Button("Pre-Warm for 15 Minutes") { appState.prewarmModelIntoRAM(model.name, keepAlive: "15m") }
                                    Button("Pre-Warm for 1 Hour") { appState.prewarmModelIntoRAM(model.name, keepAlive: "1h") }
                                    Button("Pin in RAM Indefinitely") { appState.prewarmModelIntoRAM(model.name, keepAlive: "-1") }
                                }
                                .font(theme.captionFont())
                                .frame(width: 115)
                            }

                            // Deep Model Inspector (`/show info`, `modelfile`, `template`, `license`)
                            Button {
                                appState.inspectModel(model.name)
                            } label: {
                                StudioIcon(.eye, size: 13, color: palette.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Inspect Modelfile, Template, Parameters & License")

                            // Delete Model
                            Button {
                                Task {
                                    try? await appState.client.deleteModel(baseURL: appState.serverConfig.baseURLString, modelName: model.name)
                                    await appState.refreshEngineStatus()
                                }
                            } label: {
                                StudioIcon(.trash, size: 13, color: palette.mutedText)
                            }
                            .buttonStyle(.plain)
                            .help("Delete model from disk")
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius).fill(palette.subtleSurface))
                        .overlay(RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius).strokeBorder(palette.hairlineBorder, lineWidth: 1))
                    }
                }

                // 4. Deep Model Inspector Drawer / Panel (Replaces all `/show` CLI commands)
                if let inspectedName = appState.inspectedModelName, let info = appState.inspectedModelInfo {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Model Inspector: \(inspectedName)")
                                .font(theme.bodyFont(weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            if let maxCtx = info.maxContextLengthFromMetadata {
                                StudioPillBadge("Max Native Context: \(maxCtx) tokens", palette: palette, isAccent: true)
                            }
                            Spacer()
                            Button("Close Inspector") {
                                appState.inspectedModelName = nil
                                appState.inspectedModelInfo = nil
                            }
                            .buttonStyle(.plain)
                            .font(theme.captionFont())
                            .foregroundStyle(palette.secondaryText)
                        }

                        if let sys = info.system, !sys.isEmpty {
                            Text("Built-In System Prompt").font(theme.captionFont(weight: .semibold)).foregroundStyle(palette.mutedText)
                            Text(sys).font(theme.monoFont(size: 11.5)).textSelection(.enabled)
                        }
                        if let tmpl = info.template, !tmpl.isEmpty {
                            Text("Prompt Template").font(theme.captionFont(weight: .semibold)).foregroundStyle(palette.mutedText)
                            Text(tmpl).font(theme.monoFont(size: 11)).textSelection(.enabled)
                        }
                        if let mf = info.modelfile, !mf.isEmpty {
                            Text("Compiled Modelfile").font(theme.captionFont(weight: .semibold)).foregroundStyle(palette.mutedText)
                            ScrollView {
                                Text(mf).font(theme.monoFont(size: 11)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                            .frame(maxHeight: 160)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius).fill(palette.subtleSurface))
                    .overlay(RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius).strokeBorder(palette.accent, lineWidth: 1))
                }
            }
            .padding(28)
        }
    }
}
