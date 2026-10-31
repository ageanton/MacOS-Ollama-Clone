import SwiftUI

public struct InspectorDrawerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    @State private var selectedSection: InspectorTab = .sampling
    @State private var newStopWord: String = ""

    public enum InspectorTab: String, CaseIterable, Identifiable {
        case sampling = "Sampling"
        case memory = "Memory & HW"
        case output = "Format & Seed"
        public var id: String { rawValue }
    }

    public init(palette: StudioPalette) {
        self.palette = palette
    }

    public var body: some View {
        guard let idx = appState.activeConversationIndex else {
            return AnyView(EmptyView())
        }
        let dials = appState.conversations[idx].dials
        let modelBytes = appState.activeModelSummary?.size ?? 4_700_000_000
        let memEstimate = dials.estimateMemoryFootprint(
            modelSizeBytes: modelBytes,
            kvCacheType: appState.serverConfig.kvCacheType,
            systemTotalRAMGB: appState.hardware.totalMemoryGB,
            systemAvailableRAMGB: appState.hardware.availableMemoryGB
        )

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Header + Preset Selector
                HStack {
                    Text("Model Dials")
                        .font(theme.bodyFont(weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    Menu("Presets") {
                        ForEach(DialsPreset.allPresets) { preset in
                            Button("\(preset.name) — \(preset.subtitle)") {
                                preset.apply(&appState.conversations[idx].dials)
                                appState.persistVault()
                            }
                        }
                    }
                    .font(theme.captionFont(weight: .medium))
                    .frame(width: 90)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.hairlineBorder).frame(height: 1)
                }

                // Live VRAM / Unified Memory Impact Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(warningColor(memEstimate.warningLevel))
                            .frame(width: 7, height: 7)
                        Text(String(format: "Est. RAM: %.1f GB (~%d pages memory)", memEstimate.totalEstimatedGB, memEstimate.approximatePagesOfText))
                            .font(theme.monoFont(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                    }
                    Text(memEstimate.plainEnglishSummary)
                        .font(theme.captionFont())
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let advice = memEstimate.actionableAdvice {
                        Text(advice)
                            .font(theme.captionFont(weight: .medium))
                            .foregroundStyle(warningColor(memEstimate.warningLevel))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(palette.subtleSurface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.hairlineBorder).frame(height: 1)
                }

                // Segmented Tab Control
                Picker("", selection: $selectedSection) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                // Scrollable Dials
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedSection {
                        case .sampling:
                            samplingDialsSection(idx: idx)
                        case .memory:
                            memoryAndHardwareSection(idx: idx)
                        case .output:
                            outputAndSeedSection(idx: idx)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }

                Divider().overlay(palette.hairlineBorder)

                // Save Per-Model Default Footer
                HStack {
                    Button("Reset Defaults") {
                        appState.conversations[idx].dials = ModelDials()
                        appState.persistVault()
                    }
                    .buttonStyle(.plain)
                    .font(theme.captionFont())
                    .foregroundStyle(palette.secondaryText)

                    Spacer()

                    Button("Save as Default for Model") {
                        let model = appState.conversations[idx].selectedModel
                        if !model.isEmpty {
                            appState.modelDefaultDials[model] = appState.conversations[idx].dials
                            appState.persistVault()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(theme.captionFont(weight: .semibold))
                    .foregroundStyle(palette.accent)
                }
                .padding(12)
            }
            .background(palette.cardSurface)
        )
    }

    @ViewBuilder
    private func samplingDialsSection(idx: Int) -> some View {
        DialSliderRow(
            title: "Creativity (Temperature)",
            key: "temperature",
            value: $appState.conversations[idx].dials.temperature,
            range: 0.0...2.0,
            step: 0.05,
            format: "%.2f",
            palette: palette
        )
        DialSliderRow(
            title: "Nucleus Sampling (Top-P)",
            key: "top_p",
            value: $appState.conversations[idx].dials.topP,
            range: 0.05...1.0,
            step: 0.05,
            format: "%.2f",
            palette: palette
        )
        DialSliderRow(
            title: "Min Probability Cutoff (Min-P)",
            key: "min_p",
            value: $appState.conversations[idx].dials.minP,
            range: 0.0...0.5,
            step: 0.01,
            format: "%.2f",
            palette: palette
        )
        DialIntSliderRow(
            title: "Vocabulary Pool (Top-K)",
            key: "top_k",
            value: $appState.conversations[idx].dials.topK,
            range: 1...120,
            palette: palette
        )
        DialSliderRow(
            title: "Repetition Penalty",
            key: "repeat_penalty",
            value: $appState.conversations[idx].dials.repeatPenalty,
            range: 0.8...1.6,
            step: 0.05,
            format: "%.2f",
            palette: palette
        )
        DialIntSliderRow(
            title: "Repetition Lookback Tokens",
            key: "repeat_last_n",
            value: $appState.conversations[idx].dials.repeatLastN,
            range: -1...512,
            palette: palette
        )
        DialSliderRow(
            title: "Topic Freshness (Presence Penalty)",
            key: "presence_penalty",
            value: $appState.conversations[idx].dials.presencePenalty,
            range: -2.0...2.0,
            step: 0.1,
            format: "%.1f",
            palette: palette
        )
        DialSliderRow(
            title: "Word Frequency Penalty",
            key: "frequency_penalty",
            value: $appState.conversations[idx].dials.frequencyPenalty,
            range: -2.0...2.0,
            step: 0.1,
            format: "%.1f",
            palette: palette
        )
        DialSliderRow(
            title: "Locally Typical Sampling (Typical-P)",
            key: "typical_p",
            value: $appState.conversations[idx].dials.typicalP,
            range: 0.1...1.0,
            step: 0.05,
            format: "%.2f",
            palette: palette
        )
        DialSliderRow(
            title: "Tail-Free Sampling (TFS-Z)",
            key: "tfs_z",
            value: $appState.conversations[idx].dials.tfsZ,
            range: 0.5...2.0,
            step: 0.05,
            format: "%.2f",
            palette: palette
        )

        Divider().overlay(palette.hairlineBorder)

        // Mirostat Controller
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mirostat Perplexity Controller")
                    .font(theme.captionFont(weight: .medium))
                    .foregroundStyle(palette.primaryText)
                if let entry = ParameterHelpCatalog.entries["mirostat"] {
                    PlainEnglishTooltipButton(
                        title: entry.title,
                        technicalKey: entry.key,
                        explanation: entry.explanation,
                        recommendation: entry.recommendation,
                        palette: palette
                    )
                }
            }
            Picker("", selection: $appState.conversations[idx].dials.mirostat) {
                Text("Off (0)").tag(0)
                Text("Mirostat 1").tag(1)
                Text("Mirostat 2").tag(2)
            }
            .pickerStyle(.segmented)

            if appState.conversations[idx].dials.mirostat > 0 {
                DialSliderRow(
                    title: "Mirostat Target Entropy (Tau)",
                    key: "mirostat_tau",
                    value: $appState.conversations[idx].dials.mirostatTau,
                    range: 1.0...10.0,
                    step: 0.25,
                    format: "%.2f",
                    palette: palette
                )
                DialSliderRow(
                    title: "Mirostat Learning Rate (Eta)",
                    key: "mirostat_eta",
                    value: $appState.conversations[idx].dials.mirostatEta,
                    range: 0.01...0.5,
                    step: 0.01,
                    format: "%.2f",
                    palette: palette
                )
            }
        }
    }

    @ViewBuilder
    private func memoryAndHardwareSection(idx: Int) -> some View {
        // Quick Context Window Stepper + Slider
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Conversation Memory (num_ctx)")
                    .font(theme.captionFont(weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                if let entry = ParameterHelpCatalog.entries["num_ctx"] {
                    PlainEnglishTooltipButton(
                        title: entry.title,
                        technicalKey: entry.key,
                        explanation: entry.explanation,
                        recommendation: entry.recommendation,
                        palette: palette
                    )
                }
                Spacer()
                Text("\(appState.conversations[idx].dials.numCtx) tok")
                    .font(theme.monoFont(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }

            HStack(spacing: 4) {
                ForEach([2048, 4096, 8192, 16384, 32768, 65536], id: \.self) { ctx in
                    let isCurrent = appState.conversations[idx].dials.numCtx == ctx
                    Button("\(ctx / 1024)k") {
                        appState.conversations[idx].dials.numCtx = ctx
                        appState.persistVault()
                    }
                    .buttonStyle(.plain)
                    .font(theme.monoFont(size: 11, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.white : palette.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isCurrent ? palette.accent : palette.subtleSurface)
                    )
                }
            }
        }

        DialIntSliderRow(
            title: "Max Reply Tokens (num_predict)",
            key: "num_predict",
            value: $appState.conversations[idx].dials.numPredict,
            range: -2...8192,
            palette: palette
        )
        DialIntSliderRow(
            title: "Pinned Initial Tokens (num_keep)",
            key: "num_keep",
            value: $appState.conversations[idx].dials.numKeep,
            range: 0...256,
            palette: palette
        )
        DialIntSliderRow(
            title: "Prompt Batch Size (num_batch)",
            key: "num_batch",
            value: $appState.conversations[idx].dials.numBatch,
            range: 32...2048,
            palette: palette
        )
        DialIntSliderRow(
            title: "GPU Layers Offload (-1 = All Metal)",
            key: "num_gpu",
            value: $appState.conversations[idx].dials.numGpu,
            range: -1...128,
            palette: palette
        )
        DialIntSliderRow(
            title: "CPU Compute Threads (0 = Auto)",
            key: "num_thread",
            value: $appState.conversations[idx].dials.numThread,
            range: 0...32,
            palette: palette
        )
        DialIntSliderRow(
            title: "Primary GPU Index (main_gpu)",
            key: "main_gpu",
            value: $appState.conversations[idx].dials.mainGpu,
            range: 0...4,
            palette: palette
        )

        Divider().overlay(palette.hairlineBorder)

        VStack(alignment: .leading, spacing: 8) {
            Toggle("Fast SSD Memory Mapping (use_mmap)", isOn: $appState.conversations[idx].dials.useMmap)
            Toggle("Pin Weights in Physical RAM (use_mlock)", isOn: $appState.conversations[idx].dials.useMlock)
            Toggle("Low-VRAM Conservation Mode", isOn: $appState.conversations[idx].dials.lowVram)
            Toggle("NUMA Multi-Die Optimization", isOn: $appState.conversations[idx].dials.numa)
            Toggle("Penalize Newline Characters", isOn: $appState.conversations[idx].dials.penalizeNewline)
            Toggle("Vocabulary-Only Inspection Mode", isOn: $appState.conversations[idx].dials.vocabOnly)
        }
        .font(theme.captionFont())
    }

    @ViewBuilder
    private func outputAndSeedSection(idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reasoning & Thinking Depth")
                .font(theme.captionFont(weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Picker("", selection: $appState.conversations[idx].dials.thinkingMode) {
                ForEach(ThinkingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(appState.conversations[idx].dials.thinkingMode.plainEnglishDescription)
                .font(theme.captionFont())
                .foregroundStyle(palette.secondaryText)
        }

        Divider().overlay(palette.hairlineBorder)

        VStack(alignment: .leading, spacing: 8) {
            Text("Structured Output Format")
                .font(theme.captionFont(weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Picker("", selection: $appState.conversations[idx].dials.formatMode) {
                ForEach(ResponseFormatMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            if appState.conversations[idx].dials.formatMode == .jsonSchema {
                TextEditor(text: $appState.conversations[idx].dials.customJSONSchema)
                    .font(theme.monoFont(size: 11))
                    .frame(height: 90)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
            }
        }

        Divider().overlay(palette.hairlineBorder)

        VStack(alignment: .leading, spacing: 6) {
            Text("Keep-Alive Residency Policy")
                .font(theme.captionFont(weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Picker("", selection: $appState.conversations[idx].dials.keepAlive) {
                ForEach(KeepAlivePreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
        }

        DialIntSliderRow(
            title: "Random Seed (-1 = Random)",
            key: "seed",
            value: $appState.conversations[idx].dials.seed,
            range: -1...99999,
            palette: palette
        )

        // Custom Stop Sequences
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom Stop Sequences")
                .font(theme.captionFont(weight: .semibold))
                .foregroundStyle(palette.primaryText)
            HStack {
                TextField("Add stop token (e.g. <|eot_id|>)", text: $newStopWord)
                    .textFieldStyle(.roundedBorder)
                    .font(theme.monoFont(size: 11))
                Button("Add") {
                    let trimmed = newStopWord.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appState.conversations[idx].dials.stopSequences.append(trimmed)
                        newStopWord = ""
                        appState.persistVault()
                    }
                }
            }
            ForEach(appState.conversations[idx].dials.stopSequences, id: \.self) { stop in
                HStack {
                    Text(stop)
                        .font(theme.monoFont(size: 11))
                    Spacer()
                    Button {
                        appState.conversations[idx].dials.stopSequences.removeAll(where: { $0 == stop })
                    } label: {
                        StudioIcon(.close, size: 10, color: palette.mutedText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette.subtleSurface))
            }
        }
    }

    private func warningColor(_ level: ModelDials.MemoryEstimate.WarningLevel) -> Color {
        switch level {
        case .optimal: return palette.statusHealthy
        case .moderate: return palette.statusWarning
        case .criticalOverflow: return palette.statusDanger
        }
    }
}

public struct DialSliderRow: View {
    @EnvironmentObject private var theme: ThemeManager
    public let title: String
    public let key: String
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double
    public let format: String
    public let palette: StudioPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(theme.captionFont(weight: .medium))
                    .foregroundStyle(palette.primaryText)
                if let entry = ParameterHelpCatalog.entries[key] {
                    PlainEnglishTooltipButton(
                        title: entry.title,
                        technicalKey: entry.key,
                        explanation: entry.explanation,
                        recommendation: entry.recommendation,
                        palette: palette
                    )
                }
                Spacer()
                Text(String(format: format, value))
                    .font(theme.monoFont(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            Slider(value: $value, in: range, step: step)
                .tint(palette.accent)
        }
    }
}

public struct DialIntSliderRow: View {
    @EnvironmentObject private var theme: ThemeManager
    public let title: String
    public let key: String
    @Binding public var value: Int
    public let range: ClosedRange<Int>
    public let palette: StudioPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(theme.captionFont(weight: .medium))
                    .foregroundStyle(palette.primaryText)
                if let entry = ParameterHelpCatalog.entries[key] {
                    PlainEnglishTooltipButton(
                        title: entry.title,
                        technicalKey: entry.key,
                        explanation: entry.explanation,
                        recommendation: entry.recommendation,
                        palette: palette
                    )
                }
                Spacer()
                Text("\(value)")
                    .font(theme.monoFont(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(palette.accent)
        }
    }
}
