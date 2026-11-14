set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Views/ComposerAndInspectorViews.swift
import SwiftUI
import AppKit

public struct ProgressiveComposerBar: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens
    public var maxBarWidth: CGFloat = 740.0
    public var activeFontSize: CGFloat = 14.0
    public var isWideOrFullscreen: Bool = false

    @State private var isComposerFocused: Bool = false
    @State private var compactEditorHeight: CGFloat = 28.0
    @State private var wrappedLineCount: Int = 1

    private var typo: TypographyConfiguration { store.typography }

    private var isSendEnabled: Bool {
        store.isStreamingGeneration || store.sendDisabledReason == nil
    }

    private var matchingPersonas: [SlashPersona] {
        store.matchedSlashPersonas
    }

    private var effectiveEditorHeight: CGFloat {
        if store.isComposerCanvasExpanded {
            return 240.0
        }
        return compactEditorHeight
    }

    private var adaptivePlaceholder: String {
        if isWideOrFullscreen {
            return "Message Motif…  (Type / for personas · Shift+Return for new line)"
        } else {
            return "Message Motif…  ( / for personas )"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Unclipped First-Class Floating Slash (`/`) Command Palette Card
            if !matchingPersonas.isEmpty {
                SlashPersonaCommandPaletteCard(
                    personas: matchingPersonas,
                    highlightedIndex: min(max(0, store.slashMenuHighlightedIndex), max(0, matchingPersonas.count - 1)),
                    tokens: tokens,
                    typo: typo,
                    onSelect: { persona in
                        store.applySlashPersona(persona)
                    },
                    onManagePersonas: {
                        store.isSlashMenuDismissedForCurrentToken = true
                        store.settingsRequestedTab = "Slash Personas (/)"
                        store.isSettingsModalPresented = true
                    },
                    onDismiss: {
                        store.isSlashMenuDismissedForCurrentToken = true
                    }
                )
                .frame(maxWidth: min(maxBarWidth, 500))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // 2. Main Composer Instrument (Single Persistent View Identity — Never Destroys NSTextView or Loses Focus!)
            VStack(alignment: .leading, spacing: 0) {
                if !store.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.pendingAttachments.indices, id: \.self) { idx in
                                let chip = store.pendingAttachments[idx]
                                HStack(spacing: 6) {
                                    Image(systemName: chip.kind == .downscaledVisionImage ? "photo" : "doc.text")
                                        .font(.system(size: 10))
                                        .foregroundColor(tokens.secondaryText)
                                    Text("\(chip.title) (\(chip.formattedByteSize) · ~\(chip.tokenEstimate) tok)")
                                        .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundColor(tokens.primaryText)
                                    Button {
                                        store.pendingAttachments.remove(at: idx)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(tokens.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(tokens.canvasBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                }

                // DECK A: Persistent Full-Width Prose Editor + Top-Right Expand/Contract Canvas Button
                HStack(alignment: .top, spacing: 6) {
                    IMESafeComposerTextView(
                        text: Binding(
                            get: { store.composerDraft },
                            set: { store.handleTextInputOrPaste($0) }
                        ),
                        isFocused: $isComposerFocused,
                        compactHeight: $compactEditorHeight,
                        lineCount: $wrappedLineCount,
                        placeholder: adaptivePlaceholder,
                        tokens: tokens,
                        typo: typo,
                        fontSize: activeFontSize,
                        isSlashMenuVisible: !matchingPersonas.isEmpty,
                        onSend: {
                            if !store.isStreamingGeneration && store.sendDisabledReason == nil {
                                store.sendActivePrompt()
                            }
                        },
                        onSlashMoveUp: { store.moveSlashSelection(delta: -1) },
                        onSlashMoveDown: { store.moveSlashSelection(delta: 1) },
                        onSlashConfirm: { store.applyHighlightedSlashPersona() },
                        onSlashDismiss: { store.isSlashMenuDismissedForCurrentToken = true },
                        onLargePaste: { pasted in store.handleTextInputOrPaste(pasted) }
                    )
                    .frame(height: effectiveEditorHeight)

                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            store.isComposerCanvasExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: store.isComposerCanvasExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(store.isComposerCanvasExpanded ? tokens.accentAction : tokens.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(tokens.canvasBackground.opacity(0.85))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(tokens.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .help(store.isComposerCanvasExpanded ? "Restore compact 3-line input" : "Expand prompt canvas for long-form editing")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

                HairlineDivider(tokens: tokens)
                    .padding(.horizontal, 12)

                // DECK B: Clean Bottom Control Bar
                HStack(alignment: .center, spacing: 8) {
                    Button(action: attachLocalFileOrVisionAsset) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 11.5, weight: .medium))
                            Text("Attach")
                                .font(typo.sans(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(tokens.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(tokens.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(tokens.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Attach code, text file, or image")

                    if let activeTrigger = store.activeSession?.activePersonaTrigger {
                        HStack(spacing: 4) {
                            Text(activeTrigger)
                                .font(typo.mono(size: 10.5, weight: .semibold))
                                .foregroundColor(tokens.accentAction)
                            Button {
                                if let idx = store.sessions.firstIndex(where: { $0.id == store.selectedSessionID }) {
                                    store.sessions[idx].activePersonaTrigger = nil
                                    store.saveAllState()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(tokens.mutedText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(tokens.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(tokens.hairline, lineWidth: 1)
                        )
                    }

                    if !store.composerDraft.isEmpty {
                        Text("\(wrappedLineCount) \(wrappedLineCount == 1 ? "line" : "lines") · ~\(max(1, store.composerDraft.count / 4)) tok")
                            .font(typo.sans(size: 10.5, weight: .regular).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    }

                    Spacer()

                    parametersPopoverButton

                    sendOrStopActionButton
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(tokens.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isComposerFocused ? tokens.strongBorder : tokens.hairline, lineWidth: 1)
            )
        }
        .frame(maxWidth: maxBarWidth)
    }

    private var parametersPopoverButton: some View {
        Button {
            store.isParameterPopoverPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                Text("Parameters")
                    .font(typo.sans(size: 11.5, weight: .medium))
            }
            .foregroundColor(tokens.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tokens.canvasBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(tokens.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Presets, Tight-RAM Optimizer, Model Thinking capabilities, KV cache quantization, and CLI parameters")
        .popover(isPresented: $store.isParameterPopoverPresented, arrowEdge: .top) {
            ParameterInspectorPopover(store: store, tokens: tokens)
        }
    }

    private var sendOrStopActionButton: some View {
        Button {
            if store.isStreamingGeneration {
                store.stopActiveGeneration()
            } else {
                store.sendActivePrompt()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isSendEnabled ? tokens.accentAction : tokens.hairline)
                    .frame(width: 30, height: 30)

                if store.isStreamingGeneration {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tokens.accentForeground)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(isSendEnabled ? tokens.accentForeground : tokens.mutedText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isSendEnabled)
        .help(store.isStreamingGeneration ? "Stop generation" : (store.sendDisabledReason ?? "Send message"))
    }

    private func attachLocalFileOrVisionAsset() {
        let panel = NSOpenPanel()
        panel.title = "Attach File or Image"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            store.attachFilesFromURLs(panel.urls)
        }
    }
}

// MARK: - Unclipped First-Class Slash Persona Command Palette Card
public struct SlashPersonaCommandPaletteCard: View {
    public let personas: [SlashPersona]
    public let highlightedIndex: Int
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration
    public let onSelect: (SlashPersona) -> Void
    public let onManagePersonas: () -> Void
    public let onDismiss: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("SLASH PERSONAS")
                    .font(typo.sans(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(tokens.mutedText)

                Spacer()

                Text("↑↓ navigate · ↵ apply · esc close")
                    .font(typo.sans(size: 10))
                    .foregroundColor(tokens.mutedText)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(tokens.mutedText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(tokens.elevatedSurface.opacity(0.55))

            HairlineDivider(tokens: tokens)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(personas.enumerated()), id: \.element.id) { idx, persona in
                        let isHighlighted = idx == highlightedIndex
                        Button {
                            onSelect(persona)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Text(persona.trigger)
                                    .font(typo.mono(size: 11, weight: .semibold))
                                    .foregroundColor(isHighlighted ? tokens.accentForeground : tokens.accentAction)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(isHighlighted ? tokens.accentAction : tokens.elevatedSurface)
                                    )
                                    .frame(width: 92, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(persona.title)
                                        .font(typo.sans(size: 12.5, weight: .semibold))
                                        .foregroundColor(tokens.primaryText)
                                        .lineLimit(1)

                                    Text(persona.systemPrompt)
                                        .font(typo.sans(size: 11))
                                        .foregroundColor(tokens.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                if isHighlighted {
                                    Text("↵")
                                        .font(typo.mono(size: 11, weight: .bold))
                                        .foregroundColor(tokens.secondaryText)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isHighlighted ? tokens.selectionPill : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 210)

            HairlineDivider(tokens: tokens)

            HStack {
                Button(action: onManagePersonas) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Create or edit personas in Settings…")
                            .font(typo.sans(size: 11, weight: .medium))
                    }
                    .foregroundColor(tokens.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(tokens.elevatedSurface.opacity(0.35))
        }
        .background(tokens.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tokens.strongBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 4)
    }
}

// MARK: - Model Picker Popover
public struct ModelPickerPopoverView: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens

    private var typo: TypographyConfiguration { store.typography }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Local Models")
                    .font(typo.sans(size: 12.5, weight: .semibold))
                    .foregroundColor(tokens.primaryText)
                Spacer()
                Button("Refresh") {
                    Task {
                        await store.refreshLocalEngineModels()
                        await store.pollOllamaRunningProcesses()
                    }
                }
                .font(typo.sans(size: 11.5))
                .foregroundColor(tokens.secondaryText)
                .buttonStyle(.plain)
            }

            HairlineDivider(tokens: tokens)

            if store.availableModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No models found in Ollama.")
                        .font(typo.sans(size: 12.5))
                        .foregroundColor(tokens.secondaryText)
                    Button("Open Settings to Pull or Select External Drive…") {
                        store.isModelPickerPopoverPresented = false
                        store.isSettingsModalPresented = true
                    }
                    .font(typo.sans(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(store.availableModels) { model in
                            let isSelected = model.name == store.activeModelDescriptor?.name
                            let isLoaded = model.residency == .activeInUnifiedRAM

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(isLoaded ? tokens.statusOnline : tokens.mutedText)
                                    .frame(width: 6, height: 6)

                                Button {
                                    store.selectAndLoadModel(model)
                                    store.isModelPickerPopoverPresented = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.shortDisplayName)
                                            .font(typo.sans(size: 12.5, weight: isSelected ? .semibold : .regular))
                                            .foregroundColor(tokens.primaryText)
                                            .lineLimit(1)
                                        let details = [
                                            model.parameterSize,
                                            model.quantizationLevel,
                                            model.formattedSize,
                                            model.thinkingProfile.kind.rawValue
                                        ].filter { !$0.isEmpty }
                                        Text(details.joined(separator: " · "))
                                            .font(typo.sans(size: 10.5).monospacedDigit())
                                            .foregroundColor(tokens.secondaryText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(model.shortDisplayName)

                                if isLoaded {
                                    Button("Unload") {
                                        Task { await store.unloadModelFromMemory(model) }
                                    }
                                    .font(typo.sans(size: 11))
                                    .foregroundColor(tokens.secondaryText)
                                    .buttonStyle(.plain)
                                } else {
                                    Button("Load") {
                                        store.selectAndLoadModel(model)
                                    }
                                    .font(typo.sans(size: 11, weight: .medium))
                                    .foregroundColor(tokens.primaryText)
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? tokens.selectionPill : Color.clear)
                            )
                        }
                    }
                }
                .frame(maxHeight: 290)
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(tokens.canvasBackground)
    }
}

// MARK: - Complete CLI Parameters Popover (Automatically Persists Per-Model Thinking & Parameter Preferences)
public struct ParameterInspectorPopover: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens
    @State private var isAdvancedExpanded: Bool = false

    private var typo: TypographyConfiguration { store.typography }

    private var activeSessionBinding: Binding<ConversationSession>? {
        guard let id = store.selectedSessionID,
              let idx = store.sessions.firstIndex(where: { $0.id == id }) else { return nil }
        return $store.sessions[idx]
    }

    private let presetGridColumns = [
        GridItem(.adaptive(minimum: 106, maximum: 180), spacing: 6)
    ]

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if let session = activeSessionBinding {
                let modelProfile = store.activeModelDescriptor?.thinkingProfile ?? ModelThinkingProfile()

                VStack(alignment: .leading, spacing: 14) {
                    // 1. One-Click Tight-RAM Survival Mode Banner
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tight-RAM Survival Optimizer")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            Text("Applies Q4_0 KV cache, Flash Attention, Parallel=1, 4k ctx, 128 batch & safe GPU layers.")
                                .font(typo.sans(size: 10.5))
                                .foregroundColor(tokens.secondaryText)
                        }
                        Spacer()
                        Button(session.wrappedValue.parameters.tightRAMModeEnabled ? "Re-Apply" : "Optimize") {
                            store.applyTightRAMOptimization()
                        }
                        .font(typo.sans(size: 11, weight: .semibold))
                        .foregroundColor(tokens.accentForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tokens.accentAction))
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(tokens.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    // 2. Wrapping Multi-Row Presets Grid
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Presets (\(store.presets.count))")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            Spacer()
                            Button("+ Save Current as Preset…") {
                                store.isParameterPopoverPresented = false
                                store.isNewPresetSheetPresented = true
                            }
                            .font(typo.sans(size: 11, weight: .medium))
                            .foregroundColor(tokens.accentAction)
                            .buttonStyle(.plain)
                        }

                        LazyVGrid(columns: presetGridColumns, alignment: .leading, spacing: 6) {
                            ForEach(store.presets) { preset in
                                let isCurrentMatch = session.wrappedValue.parameters == preset.parameters
                                Button {
                                    session.wrappedValue.parameters = preset.parameters
                                    session.wrappedValue.systemPrompt = preset.systemPrompt
                                    store.recordActiveModelParameterPreference()
                                    if store.supervisor.kvCacheTypeEnv != preset.parameters.kvCacheQuant {
                                        store.applyKVCacheQuantizationLive(preset.parameters.kvCacheQuant)
                                    } else {
                                        store.recalculateHardwareTelemetry()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(preset.name)
                                            .font(typo.sans(size: 11.5, weight: isCurrentMatch ? .semibold : .medium))
                                            .foregroundColor(tokens.primaryText)
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isCurrentMatch ? tokens.selectionPill : tokens.elevatedSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(isCurrentMatch ? tokens.strongBorder : tokens.hairline, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("\(preset.summary) — Right-click to update or delete")
                                .contextMenu {
                                    Button("Update “\(preset.name)” with Current Settings") {
                                        store.updatePresetWithCurrentSettings(preset.id)
                                    }
                                    Divider()
                                    Button("Delete Preset", role: .destructive) {
                                        store.deletePreset(preset.id)
                                    }
                                }
                            }
                        }
                    }

                    HairlineDivider(tokens: tokens)

                    // 3. Introspected Model Thinking Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Thinking Mode")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            ParameterInfoButton(
                                title: "Introspected Model Thinking Profile",
                                explanation: "Motif inspects this model via POST /api/show and remembers your preferred Thinking Mode for each model. Detected template tokens: \(modelProfile.detectedTemplateTokens)",
                                tokens: tokens,
                                typo: typo
                            )
                            Spacer()
                            Text(modelProfile.kind.rawValue)
                                .font(typo.sans(size: 10.5, weight: .semibold))
                                .foregroundColor(tokens.accentAction)
                        }

                        Text("Template tokens: \(modelProfile.detectedTemplateTokens)")
                            .font(typo.sans(size: 10.5))
                            .foregroundColor(tokens.secondaryText)
                            .lineLimit(1)

                        if modelProfile.kind != .unsupported || session.wrappedValue.parameters.forceThinkingOverrideWhenUnsupported {
                            let allowedModes = session.wrappedValue.parameters.forceThinkingOverrideWhenUnsupported
                                ? ThinkingModeOption.allCases
                                : modelProfile.validOptions

                            Picker("", selection: session.parameters.thinkingMode) {
                                ForEach(allowedModes) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onChange(of: session.wrappedValue.parameters.thinkingMode) { _, _ in
                                store.recordActiveModelParameterPreference()
                            }
                        } else {
                            Toggle("Force thinking override for custom GGUF", isOn: session.parameters.forceThinkingOverrideWhenUnsupported)
                                .font(typo.sans(size: 11))
                                .foregroundColor(tokens.secondaryText)
                        }
                    }

                    HairlineDivider(tokens: tokens)

                    // 4. Context Window & LIVE KV Cache Quantization
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Context Window")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            ParameterInfoButton(
                                title: "Context Window (num_ctx)",
                                explanation: "Maximum tokens held in active memory. Model max context reported by /api/show: \(store.activeModelDescriptor?.maxContextLength ?? 32768) tokens.",
                                tokens: tokens,
                                typo: typo
                            )
                            Spacer()
                            Text("\(session.wrappedValue.parameters.numCtx) tok")
                                .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                                .foregroundColor(tokens.secondaryText)
                        }

                        Picker("", selection: session.parameters.numCtx) {
                            Text("2k").tag(2048)
                            Text("4k").tag(4096)
                            Text("8k").tag(8192)
                            Text("16k").tag(16384)
                            Text("32k").tag(32768)
                            Text("64k").tag(65536)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: session.wrappedValue.parameters.numCtx) { _, _ in
                            store.recordActiveModelParameterPreference()
                            store.recalculateHardwareTelemetry()
                        }

                        HStack(spacing: 6) {
                            Text("KV Cache Quantization (Live Daemon Rebind)")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            ParameterInfoButton(
                                title: "KV Cache Quantization (OLLAMA_KV_CACHE_TYPE)",
                                explanation: "Changing this setting sets OLLAMA_KV_CACHE_TYPE and OLLAMA_FLASH_ATTENTION=1, restarts the local Ollama daemon, and reloads the model at the compressed KV precision.",
                                tokens: tokens,
                                typo: typo
                            )
                        }
                        .padding(.top, 4)

                        Picker("", selection: session.parameters.kvCacheQuant) {
                            ForEach(KVCacheQuantization.allCases) { q in
                                Text(q.displayTitle).tag(q)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: session.wrappedValue.parameters.kvCacheQuant) { _, newQuant in
                            store.applyKVCacheQuantizationLive(newQuant)
                        }
                    }

                    HairlineDivider(tokens: tokens)

                    ParameterSliderWithInfoAndReset(
                        title: "Temperature",
                        explanation: "Controls randomness. Lower values (0.1–0.3) produce deterministic code and factual answers. Higher values (0.8–1.2) increase creativity.",
                        value: session.parameters.temperature,
                        defaultValue: 0.70,
                        range: 0.0...2.0,
                        tokens: tokens,
                        typo: typo
                    )
                    .onChange(of: session.wrappedValue.parameters.temperature) { _, _ in
                        store.recordActiveModelParameterPreference()
                    }

                    ParameterSliderWithInfoAndReset(
                        title: "Top-P",
                        explanation: "Nucleus sampling: considers only the top tokens whose cumulative probability reaches P.",
                        value: session.parameters.topP,
                        defaultValue: 0.90,
                        range: 0.05...1.0,
                        tokens: tokens,
                        typo: typo
                    )

                    ParameterSliderWithInfoAndReset(
                        title: "Min-P",
                        explanation: "Minimum probability threshold scaled against the single most confident token.",
                        value: session.parameters.minP,
                        defaultValue: 0.05,
                        range: 0.0...0.5,
                        tokens: tokens,
                        typo: typo
                    )

                    ParameterSliderWithInfoAndReset(
                        title: "Repeat Penalty",
                        explanation: "Penalizes repeated phrases. 1.0 means no penalty; 1.10 is standard.",
                        value: session.parameters.repeatPenalty,
                        defaultValue: 1.10,
                        range: 0.8...1.6,
                        tokens: tokens,
                        typo: typo
                    )

                    HairlineDivider(tokens: tokens)

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                isAdvancedExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .rotationEffect(.degrees(isAdvancedExpanded ? 90 : 0))
                                Text("Advanced Ollama CLI & Memory Options")
                                    .font(typo.sans(size: 12, weight: .semibold))
                                Spacer()
                                Text(isAdvancedExpanded ? "Hide" : "Show all")
                                    .font(typo.sans(size: 11))
                                    .foregroundColor(tokens.secondaryText)
                            }
                            .foregroundColor(tokens.primaryText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isAdvancedExpanded {
                            VStack(alignment: .leading, spacing: 12) {
                                ParameterIntStepperWithInfoAndReset(
                                    title: "Prompt Batch Size (num_batch)",
                                    explanation: "Lower values (64–128) drastically reduce temporary Metal compute buffer spikes on tight RAM.",
                                    value: session.parameters.numBatch,
                                    defaultValue: 512,
                                    range: 32...2048,
                                    step: 64,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Metal GPU Layers (-1 = Auto Fit)",
                                    explanation: "Number of transformer layers offloaded to Apple Silicon GPU (-1 = Auto VRAM fit; model has \(store.activeModelDescriptor?.numLayers ?? 32) layers).",
                                    value: session.parameters.numGpu,
                                    defaultValue: -1,
                                    range: -1...128,
                                    step: 1,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "CPU Threads (0 = Auto Perf Cores)",
                                    explanation: "0 lets Ollama automatically use only fast Apple Silicon Performance (P) cores without throttling on Efficiency (E) cores.",
                                    value: session.parameters.numThread,
                                    defaultValue: 0,
                                    range: 0...32,
                                    step: 1,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Top-K (top_k)",
                                    explanation: "Limits token sampling pool to the K highest-probability tokens.",
                                    value: session.parameters.topK,
                                    defaultValue: 40,
                                    range: 1...200,
                                    step: 5,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterSliderWithInfoAndReset(
                                    title: "Typical-P (typical_p)",
                                    explanation: "Locally typical sampling mass. 1.0 disables typical-p filtering.",
                                    value: session.parameters.typicalP,
                                    defaultValue: 1.00,
                                    range: 0.1...1.0,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Repeat Lookback (repeat_last_n)",
                                    explanation: "Number of recent tokens inspected when applying repetition penalties (-1 = full context).",
                                    value: session.parameters.repeatLastN,
                                    defaultValue: 64,
                                    range: -1...512,
                                    step: 16,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterSliderWithInfoAndReset(
                                    title: "Presence Penalty",
                                    explanation: "Flat penalty applied to tokens that have appeared at least once.",
                                    value: session.parameters.presencePenalty,
                                    defaultValue: 0.00,
                                    range: -2.0...2.0,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterSliderWithInfoAndReset(
                                    title: "Frequency Penalty",
                                    explanation: "Penalty scaled by how many times a token has already appeared.",
                                    value: session.parameters.frequencyPenalty,
                                    defaultValue: 0.00,
                                    range: -2.0...2.0,
                                    tokens: tokens,
                                    typo: typo
                                )

                                HStack(spacing: 6) {
                                    Text("Mirostat Mode")
                                        .font(typo.sans(size: 12))
                                    ParameterInfoButton(
                                        title: "Mirostat Perplexity Controller",
                                        explanation: "Actively regulates perplexity during decoding to prevent repetition traps (Mirostat 1 or 2).",
                                        tokens: tokens,
                                        typo: typo
                                    )
                                    Spacer()
                                    Picker("", selection: session.parameters.mirostat) {
                                        ForEach(MirostatMode.allCases) { m in
                                            Text(m.label).tag(m)
                                        }
                                    }
                                    .frame(width: 130)
                                }

                                if session.wrappedValue.parameters.mirostat != .disabled {
                                    ParameterSliderWithInfoAndReset(
                                        title: "Mirostat Tau (mirostat_tau)",
                                        explanation: "Target entropy / balance between coherence and diversity (default 5.0).",
                                        value: session.parameters.mirostatTau,
                                        defaultValue: 5.00,
                                        range: 0.5...10.0,
                                        tokens: tokens,
                                        typo: typo
                                    )
                                    ParameterSliderWithInfoAndReset(
                                        title: "Mirostat Eta (mirostat_eta)",
                                        explanation: "Learning rate for Mirostat feedback controller (default 0.1).",
                                        value: session.parameters.mirostatEta,
                                        defaultValue: 0.10,
                                        range: 0.01...1.0,
                                        tokens: tokens,
                                        typo: typo
                                    )
                                }

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Max Output Tokens (num_predict)",
                                    explanation: "Maximum number of tokens generated in a single reply.",
                                    value: session.parameters.numPredict,
                                    defaultValue: 16384,
                                    range: 512...65536,
                                    step: 512,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Pinned System Tokens (num_keep)",
                                    explanation: "Number of initial tokens perpetually pinned in KV cache when context rolls over.",
                                    value: session.parameters.numKeep,
                                    defaultValue: 256,
                                    range: 0...4096,
                                    step: 64,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Keep-Alive Minutes",
                                    explanation: "How long model weights remain mapped in Unified Memory after a reply finishes (set 0 to unload immediately after each reply).",
                                    value: session.parameters.keepAliveMinutes,
                                    defaultValue: 15,
                                    range: 0...120,
                                    step: 5,
                                    tokens: tokens,
                                    typo: typo
                                )

                                ParameterIntStepperWithInfoAndReset(
                                    title: "Random Seed (seed)",
                                    explanation: "Set a fixed integer for reproducible outputs (-1 = random seed).",
                                    value: session.parameters.seed,
                                    defaultValue: -1,
                                    range: -1...999999,
                                    step: 1,
                                    tokens: tokens,
                                    typo: typo
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("Stop Sequences (comma-separated)")
                                            .font(typo.sans(size: 11.5))
                                        ParameterInfoButton(
                                            title: "Stop Sequences (stop)",
                                            explanation: "Custom strings that immediately halt generation when encountered.",
                                            tokens: tokens,
                                            typo: typo
                                        )
                                    }
                                    TextField("e.g. <|endoftext|>, USER:", text: session.parameters.stopSequencesCSV)
                                        .textFieldStyle(.roundedBorder)
                                        .font(typo.mono(size: 11))
                                }

                                Toggle("Memory-Map Weights (use_mmap — Recommended for Tight RAM)", isOn: session.parameters.useMmap)
                                    .font(typo.sans(size: 11.5))
                                Toggle("Lock Weights in RAM (use_mlock — Disable on Tight RAM)", isOn: session.parameters.useMlock)
                                    .font(typo.sans(size: 11.5))
                                Toggle("Penalize Newlines (penalize_newline)", isOn: session.parameters.penalizeNewline)
                                    .font(typo.sans(size: 11.5))
                                Toggle("Enforce Strict JSON Output (format: json)", isOn: session.parameters.enforceJSONMode)
                                    .font(typo.sans(size: 11.5))
                            }
                            .padding(.top, 4)
                        }
                    }

                    HairlineDivider(tokens: tokens)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("System Instructions")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            ParameterInfoButton(
                                title: "System Instructions",
                                explanation: "Persistent system directive pinned at the start of the conversation.",
                                tokens: tokens,
                                typo: typo
                            )
                        }

                        MotifStyledTextEditor(
                            text: session.systemPrompt,
                            font: typo.nsFont(size: 12),
                            tokens: tokens
                        )
                        .frame(height: 68)
                        .padding(4)
                        .background(tokens.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(tokens.hairline, lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 405, height: 530)
        .background(tokens.canvasBackground)
    }
}

// MARK: - Parameter Info Button ('i' Popover) & Sliders/Steppers with Explicit Reset ('↺')
public struct ParameterInfoButton: View {
    public let title: String
    public let explanation: String
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration
    @State private var isShowingInfo: Bool = false

    public var body: some View {
        Button {
            isShowingInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(tokens.mutedText)
        }
        .buttonStyle(.plain)
        .help(explanation)
        .popover(isPresented: $isShowingInfo, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(typo.sans(size: 12, weight: .semibold))
                    .foregroundColor(tokens.primaryText)
                Text(explanation)
                    .font(typo.sans(size: 11.5))
                    .foregroundColor(tokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 260)
            .background(tokens.canvasBackground)
        }
    }
}

public struct ParameterSliderWithInfoAndReset: View {
    public let title: String
    public let explanation: String
    @Binding public var value: Double
    public let defaultValue: Double
    public let range: ClosedRange<Double>
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration

    private var isModified: Bool {
        abs(value - defaultValue) > 0.005
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(typo.sans(size: 12))
                    .foregroundColor(tokens.primaryText)

                ParameterInfoButton(
                    title: title,
                    explanation: explanation,
                    tokens: tokens,
                    typo: typo
                )

                Spacer()

                Text(String(format: "%.2f", value))
                    .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(tokens.primaryText)

                Button {
                    value = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isModified ? tokens.accentAction : tokens.mutedText.opacity(0.35))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isModified ? tokens.elevatedSurface : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isModified)
                .help("Reset \(title) to default (\(String(format: "%.2f", defaultValue)))")
            }

            Slider(value: $value, in: range)
        }
    }
}

public struct ParameterIntStepperWithInfoAndReset: View {
    public let title: String
    public let explanation: String
    @Binding public var value: Int
    public let defaultValue: Int
    public let range: ClosedRange<Int>
    public let step: Int
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration

    private var isModified: Bool {
        value != defaultValue
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(typo.sans(size: 11.5))
                .foregroundColor(tokens.primaryText)

            ParameterInfoButton(
                title: title,
                explanation: explanation,
                tokens: tokens,
                typo: typo
            )

            Spacer()

            Stepper("\(value)", value: $value, in: range, step: step)
                .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())

            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isModified ? tokens.accentAction : tokens.mutedText.opacity(0.35))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(!isModified)
            .help("Reset \(title) to default (\(defaultValue))")
        }
    }
}
EOF
