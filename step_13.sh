set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Views/UtilityAndModalViews.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct CreateNamedItemSheet: View {
    public let heading: String
    public let placeholder: String
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration
    public let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nameDraft: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading)
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            TextField(placeholder, text: $nameDraft)
                .textFieldStyle(.plain)
                .font(typo.sans(size: 13))
                .padding(8)
                .background(tokens.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit { commitAndClose() }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(typo.sans(size: 12))
                    .foregroundColor(tokens.secondaryText)
                    .buttonStyle(.plain)

                Button("Create") { commitAndClose() }
                    .font(typo.sans(size: 12, weight: .semibold))
                    .foregroundColor(tokens.accentForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tokens.accentAction))
                    .buttonStyle(.plain)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(tokens.canvasBackground)
    }

    private func commitAndClose() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}

public struct RightUtilityArtifactPane: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens

    private var typo: TypographyConfiguration { store.typography }
    private var artifacts: [WorkspaceArtifact] {
        store.activeSession?.artifacts ?? []
    }
    private var currentArtifact: WorkspaceArtifact? {
        if let id = store.selectedArtifactID, let match = artifacts.first(where: { $0.id == id }) {
            return match
        }
        return artifacts.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(typo.sans(size: 13, weight: .semibold))
                    .foregroundColor(tokens.primaryText)
                Spacer()
                if let artifact = currentArtifact {
                    Button("Save File…") {
                        saveArtifactToDisk(artifact)
                    }
                    .font(typo.sans(size: 11, weight: .medium))
                    .foregroundColor(tokens.secondaryText)
                    .buttonStyle(.plain)

                    Button("Open in Editor") {
                        openArtifactInExternalEditor(artifact)
                    }
                    .font(typo.sans(size: 11, weight: .medium))
                    .foregroundColor(tokens.secondaryText)
                    .buttonStyle(.plain)
                }
                Button("Close") {
                    store.userManuallyClosedRightPaneInWideMode = true
                    store.isRightUtilityPaneOpen = false
                }
                .font(typo.sans(size: 11.5))
                .foregroundColor(tokens.secondaryText)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            HairlineDivider(tokens: tokens)

            if let artifact = currentArtifact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(artifacts) { item in
                            let isSelected = item.id == artifact.id
                            Button {
                                store.selectedArtifactID = item.id
                            } label: {
                                Text(item.title)
                                    .font(typo.sans(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(tokens.primaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(isSelected ? tokens.selectionPill : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                HairlineDivider(tokens: tokens)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        MotifCodeBlockView(
                            language: artifact.language,
                            code: artifact.content,
                            tokens: tokens,
                            typo: typo,
                            onOpenInArtifactPane: {}
                        )
                    }
                    .padding(16)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No code snippets in this chat yet.")
                        .font(typo.sans(size: 13, weight: .medium))
                        .foregroundColor(tokens.primaryText)
                    Text("Code blocks generated during conversation appear here.")
                        .font(typo.sans(size: 12))
                        .foregroundColor(tokens.secondaryText)
                    Spacer()
                }
                .padding(16)
            }
        }
        .frame(minWidth: 320, idealWidth: 390, maxWidth: 480)
        .background(tokens.surroundSubstrate)
        .overlay(alignment: .leading) {
            HairlineDivider(axis: .vertical, tokens: tokens)
                .ignoresSafeArea()
        }
    }

    private func saveArtifactToDisk(_ artifact: WorkspaceArtifact) {
        let panel = NSSavePanel()
        panel.title = "Save Code Snippet"
        let ext = artifact.language.isEmpty ? "txt" : artifact.language
        panel.nameFieldStringValue = "\(artifact.title.replacingOccurrences(of: " ", with: "_")).\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            try? artifact.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func openArtifactInExternalEditor(_ artifact: WorkspaceArtifact) {
        let ext = artifact.language.isEmpty ? "txt" : artifact.language
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("MotifSnippet.\(ext)")
        try? artifact.content.write(to: tempURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tempURL)
    }
}

// MARK: - Settings Modal (Custom Palettes for Alabaster & Warm Editorial + Summary Thinking Toggle)
public struct WorkstationSettingsModal: View {
    @ObservedObject public var store: WorkstationStore
    @Environment(\.dismiss) private var dismiss

    public enum SettingsCategory: String, CaseIterable, Identifiable {
        case appearance = "Appearance & Fonts"
        case personas = "Slash Personas (/)"
        case modelsAndDrives = "Models & Storage"
        case engineSupervisor = "Local Engine & RAM"
        case shortcuts = "Keyboard Shortcuts"
        case about = "About Motif"

        public var id: String { rawValue }
    }

    @State private var selectedCategory: SettingsCategory = .appearance
    @State private var pullModelInput: String = "llama3.2:3b"
    @State private var newPersonaTrigger: String = "/"
    @State private var newPersonaTitle: String = ""
    @State private var newPersonaPrompt: String = ""

    private var tokens: MotifTokens {
        MotifTokens(theme: store.activeTheme, isWindowActive: true)
    }
    private var typo: TypographyConfiguration { store.typography }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(typo.sans(size: 13, weight: .semibold))
                    .foregroundColor(tokens.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(SettingsCategory.allCases) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack {
                            Text(category.rawValue)
                                .font(typo.sans(size: 12.5, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(tokens.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? tokens.selectionPill : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .font(typo.sans(size: 12, weight: .semibold))
                    .foregroundColor(tokens.accentForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tokens.accentAction))
                    .buttonStyle(.plain)
                    .padding(16)
            }
            .frame(width: 205)
            .background(tokens.sidebarBackground)

            HairlineDivider(axis: .vertical, tokens: tokens)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedCategory {
                    case .appearance:
                        appearanceSection
                    case .personas:
                        personasSection
                    case .modelsAndDrives:
                        modelsSection
                    case .engineSupervisor:
                        engineSection
                    case .shortcuts:
                        shortcutsSection
                    case .about:
                        aboutSection
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.canvasBackground)
        }
        .frame(width: 750, height: 540)
        .preferredColorScheme(tokens.isEffectivelyDark ? .dark : .light)
        .onAppear {
            if let req = store.settingsRequestedTab,
               let cat = SettingsCategory(rawValue: req) {
                selectedCategory = cat
                store.settingsRequestedTab = nil
            }
        }
    }

    private func overrideBinding(for theme: AppThemeID) -> Binding<ThemeColorOverride> {
        Binding<ThemeColorOverride>(
            get: {
                theme == .warmEditorial ? store.customPalettes.warmEditorial : store.customPalettes.alabaster
            },
            set: { updated in
                if theme == .warmEditorial {
                    store.customPalettes.warmEditorial = updated
                } else {
                    store.customPalettes.alabaster = updated
                }
            }
        )
    }

    private func canvasColorBinding(for theme: AppThemeID) -> Binding<Color> {
        let ov = overrideBinding(for: theme)
        return Binding<Color>(
            get: { Color(red: ov.wrappedValue.canvasRed, green: ov.wrappedValue.canvasGreen, blue: ov.wrappedValue.canvasBlue) },
            set: { newColor in
                if let cg = NSColor(newColor).usingColorSpace(.sRGB) {
                    ov.wrappedValue.isCustomCanvasEnabled = true
                    ov.wrappedValue.canvasRed = Double(cg.redComponent)
                    ov.wrappedValue.canvasGreen = Double(cg.greenComponent)
                    ov.wrappedValue.canvasBlue = Double(cg.blueComponent)
                }
            }
        )
    }

    private func accentColorBinding(for theme: AppThemeID) -> Binding<Color> {
        let ov = overrideBinding(for: theme)
        return Binding<Color>(
            get: { Color(red: ov.wrappedValue.accentRed, green: ov.wrappedValue.accentGreen, blue: ov.wrappedValue.accentBlue) },
            set: { newColor in
                if let cg = NSColor(newColor).usingColorSpace(.sRGB) {
                    ov.wrappedValue.isCustomAccentEnabled = true
                    ov.wrappedValue.accentRed = Double(cg.redComponent)
                    ov.wrappedValue.accentGreen = Double(cg.greenComponent)
                    ov.wrappedValue.accentBlue = Double(cg.blueComponent)
                }
            }
        )
    }

    private func thinkingColorBinding(for theme: AppThemeID) -> Binding<Color> {
        let ov = overrideBinding(for: theme)
        return Binding<Color>(
            get: { Color(red: ov.wrappedValue.thinkingRed, green: ov.wrappedValue.thinkingGreen, blue: ov.wrappedValue.thinkingBlue) },
            set: { newColor in
                if let cg = NSColor(newColor).usingColorSpace(.sRGB) {
                    ov.wrappedValue.isCustomThinkingEnabled = true
                    ov.wrappedValue.thinkingRed = Double(cg.redComponent)
                    ov.wrappedValue.thinkingGreen = Double(cg.greenComponent)
                    ov.wrappedValue.thinkingBlue = Double(cg.blueComponent)
                }
            }
        )
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Themes")
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            ForEach(AppThemeID.allCases) { item in
                let isCurrent = store.activeTheme == item
                let previewTokens = MotifTokens(theme: item, isWindowActive: true)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        store.activeTheme = item
                    } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 0) {
                                Rectangle().fill(previewTokens.canvasBackground)
                                Rectangle().fill(previewTokens.thinkingSurface)
                                Rectangle().fill(previewTokens.accentAction)
                            }
                            .frame(width: 42, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(tokens.hairline, lineWidth: 1)
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.rawValue)
                                    .font(typo.sans(size: 13, weight: .medium))
                                    .foregroundColor(tokens.primaryText)
                                Text(item.subtitle)
                                    .font(typo.sans(size: 11.5))
                                    .foregroundColor(tokens.secondaryText)
                            }
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(tokens.accentAction)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isCurrent ? tokens.selectionPill : tokens.elevatedSurface)
                        )
                    }
                    .buttonStyle(.plain)

                    if item.supportsCustomPalette && isCurrent {
                        let currentOverride = overrideBinding(for: item).wrappedValue
                        HStack(spacing: 14) {
                            ColorPicker("Canvas", selection: canvasColorBinding(for: item), supportsOpacity: false)
                                .font(typo.sans(size: 11.5, weight: .medium))
                                .foregroundColor(tokens.primaryText)

                            ColorPicker("Accent", selection: accentColorBinding(for: item), supportsOpacity: false)
                                .font(typo.sans(size: 11.5, weight: .medium))
                                .foregroundColor(tokens.primaryText)

                            ColorPicker("Thinking Box", selection: thinkingColorBinding(for: item), supportsOpacity: false)
                                .font(typo.sans(size: 11.5, weight: .medium))
                                .foregroundColor(tokens.primaryText)

                            Spacer()

                            Button {
                                store.resetCustomPalette(for: item)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Reset Default")
                                        .font(typo.sans(size: 11, weight: .medium))
                                }
                                .foregroundColor(currentOverride.isModified ? tokens.accentAction : tokens.mutedText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(tokens.canvasBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(tokens.hairline, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!currentOverride.isModified)
                            .help("Restore \(item.rawValue) to factory default colors")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tokens.elevatedSurface.opacity(0.65))
                        )
                    }
                }
            }

            HairlineDivider(tokens: tokens)

            Text("Typography & Adaptive Window / Fullscreen Scaling")
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            Picker("Font Family", selection: $store.typography.fontFamily) {
                ForEach(AppFontFamily.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .font(typo.sans(size: 12.5))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Windowed Mode Text Size")
                        .font(typo.sans(size: 12.5))
                    Spacer()
                    Text(String(format: "%.1f pt", store.typography.windowedBaseFontSize))
                        .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
                }
                Slider(value: $store.typography.windowedBaseFontSize, in: 11.5...18.0, step: 0.5)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Fullscreen / Wide Mode Text Size")
                        .font(typo.sans(size: 12.5))
                    Spacer()
                    Text(String(format: "%.1f pt", store.typography.fullscreenBaseFontSize))
                        .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
                }
                Slider(value: $store.typography.fullscreenBaseFontSize, in: 13.0...21.0, step: 0.5)
            }
        }
    }

    private var personasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Slash Command System Personas")
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            Text("Type '/' in the chat box to open the floating persona command palette.")
                .font(typo.sans(size: 12))
                .foregroundColor(tokens.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("/trigger", text: $newPersonaTrigger)
                        .textFieldStyle(.roundedBorder)
                        .font(typo.mono(size: 11.5))
                        .frame(width: 120)
                    TextField("Role title (e.g. Security Auditor)", text: $newPersonaTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(typo.sans(size: 12))
                }

                Text("System Prompt Instructions (Multi-Line):")
                    .font(typo.sans(size: 11.5, weight: .medium))
                    .foregroundColor(tokens.secondaryText)

                MotifStyledTextEditor(
                    text: $newPersonaPrompt,
                    font: typo.nsFont(size: 12.5),
                    tokens: tokens
                )
                .frame(minHeight: 92, maxHeight: 160)
                .padding(6)
                .background(tokens.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(tokens.strongBorder, lineWidth: 1)
                )

                HStack {
                    Spacer()
                    Button("Save Persona") {
                        var trig = newPersonaTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trig.hasPrefix("/") { trig = "/" + trig }
                        let title = newPersonaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let prompt = newPersonaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trig.count > 1, !title.isEmpty, !prompt.isEmpty else { return }
                        store.slashPersonas.append(SlashPersona(trigger: trig, title: title, systemPrompt: prompt))
                        store.saveAllState()
                        newPersonaTrigger = "/"
                        newPersonaTitle = ""
                        newPersonaPrompt = ""
                    }
                    .font(typo.sans(size: 12, weight: .semibold))
                    .foregroundColor(tokens.accentForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tokens.accentAction))
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(tokens.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HairlineDivider(tokens: tokens)

            ForEach(store.slashPersonas) { persona in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(persona.trigger)
                                .font(typo.mono(size: 11.5, weight: .semibold))
                                .foregroundColor(tokens.accentAction)
                            Text(persona.title)
                                .font(typo.sans(size: 12.5, weight: .medium))
                                .foregroundColor(tokens.primaryText)
                        }
                        Text(persona.systemPrompt)
                            .font(typo.sans(size: 11.5))
                            .foregroundColor(tokens.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Delete") {
                        store.slashPersonas.removeAll { $0.id == persona.id }
                        store.saveAllState()
                    }
                    .font(typo.sans(size: 11))
                    .foregroundColor(tokens.mutedText)
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pull Model from Ollama Registry")
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            HStack {
                TextField("Model tag (e.g. llama3.2:3b, qwen3:8b, deepseek-r1:14b)…", text: $pullModelInput)
                    .textFieldStyle(.roundedBorder)
                Button("Pull") {
                    store.startModelDownload(reference: pullModelInput)
                }
            }

            ForEach(store.downloadTasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.modelReference).font(typo.mono(size: 11, weight: .semibold))
                        Spacer()
                        Text(task.formattedProgressGB)
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.secondaryText)
                        if !task.isCompleted {
                            Button("Cancel") {
                                store.cancelModelDownload(task.id)
                            }
                            .font(typo.sans(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .buttonStyle(.plain)
                        }
                    }
                    ProgressView(value: task.progressFraction)
                }
            }

            HairlineDivider(tokens: tokens)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("External Model Directory (OLLAMA_MODELS)")
                        .font(typo.sans(size: 12.5, weight: .medium))
                    Text(store.driveManager.externalVolumePath.isEmpty ? "~/.ollama/models (Default)" : store.driveManager.externalVolumePath)
                        .font(typo.mono(size: 10.5))
                        .foregroundColor(tokens.secondaryText)
                }
                Spacer()
                Button("Select Folder…") {
                    store.selectExternalDriveAndReloadModels()
                }
            }
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Ollama Daemon & Tight-Memory Controls")
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            Text(store.supervisor.supervisorStatusLog)
                .font(typo.sans(size: 11.5).monospacedDigit())
                .foregroundColor(tokens.secondaryText)

            TextField("Endpoint URL", text: $store.supervisor.engineEndpoint)
                .textFieldStyle(.roundedBorder)

            Picker("Daemon KV Cache Quantization (OLLAMA_KV_CACHE_TYPE)", selection: $store.supervisor.kvCacheTypeEnv) {
                ForEach(KVCacheQuantization.allCases) { q in
                    Text(q.displayTitle).tag(q)
                }
            }
            .font(typo.sans(size: 12.5))

            HStack {
                Text("Parallel Request Slots (OLLAMA_NUM_PARALLEL — Set 1 for Tight RAM)")
                    .font(typo.sans(size: 12.5))
                Spacer()
                Stepper("\(store.supervisor.parallelRequestSlots)", value: $store.supervisor.parallelRequestSlots, in: 1...4)
                    .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
            }

            HStack {
                Text("Max Resident Models in RAM (OLLAMA_MAX_LOADED_MODELS)")
                    .font(typo.sans(size: 12.5))
                Spacer()
                Stepper("\(store.supervisor.maxLoadedModels)", value: $store.supervisor.maxLoadedModels, in: 1...3)
                    .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
            }

            Toggle("Enable Flash Attention (OLLAMA_FLASH_ATTENTION=1)", isOn: $store.supervisor.enableFlashAttentionEnv)
                .font(typo.sans(size: 12.5))

            Toggle("Bind to local network (0.0.0.0:11434)", isOn: $store.supervisor.bindToLocalNetwork)
                .font(typo.sans(size: 12.5))

            Toggle("Release model RAM automatically when Motif window is minimized", isOn: $store.supervisor.autoUnloadOnMinimize)
                .font(typo.sans(size: 12.5))

            Toggle("Use model thinking when summarizing chat context (Off = fast direct summary)", isOn: $store.supervisor.useThinkingForSummary)
                .font(typo.sans(size: 12.5))

            HStack(spacing: 12) {
                Button("Apply & Restart Ollama Daemon") {
                    store.applyDaemonConfigurationAndRestart()
                }
                .font(typo.sans(size: 12, weight: .semibold))
                .foregroundColor(tokens.accentForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tokens.accentAction))
                .buttonStyle(.plain)

                Button("Stop Managed Daemon") {
                    store.supervisor.terminateManagedDaemonGracefully()
                }
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize Key Combinations (⌘ + Key)")
                .font(typo.sans(size: 14, weight: .semibold))
                .foregroundColor(tokens.primaryText)

            shortcutEditorRow("New Chat", binding: $store.shortcuts.newChatKey)
            shortcutEditorRow("Toggle Sidebar", binding: $store.shortcuts.toggleSidebarKey)
            shortcutEditorRow("Toggle Inspector", binding: $store.shortcuts.toggleInspectorKey)
            shortcutEditorRow("Stop Generation", binding: $store.shortcuts.stopGenerationKey)
        }
    }

    private func shortcutEditorRow(_ title: String, binding: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(typo.sans(size: 12.5))
                .foregroundColor(tokens.primaryText)
            Spacer()
            Text("⌘ +")
                .font(typo.sans(size: 11.5))
                .foregroundColor(tokens.secondaryText)
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(typo.sans(size: 11.5, weight: .semibold))
                .frame(width: 44)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Motif")
                .font(typo.wordmark(size: 24))
                .foregroundColor(tokens.primaryText)
            Text("Version 11.0 · Native macOS Workstation for Local Models")
                .font(typo.sans(size: 11.5))
                .foregroundColor(tokens.secondaryText)
        }
    }
}
EOF
