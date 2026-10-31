import SwiftUI
import UniformTypeIdentifiers

public struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    @State private var draftPrompt: String = ""
    @State private var pendingAttachments: [ChatAttachment] = []
    @State private var isEditingSystemPrompt: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var editingMessageID: UUID? = nil
    @State private var editingMessageText: String = ""

    public init(palette: StudioPalette) {
        self.palette = palette
    }

    public var body: some View {
        let conv = appState.activeConversation

        VStack(spacing: 0) {
            // 1. Quiet, Minimal Editorial Header (Strictly no model pill or RAM eject clutter)
            HStack(spacing: 12) {
                Text(conv?.title ?? "Conversation")
                    .font(theme.bodyFont(weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)

                Spacer()

                // Subtle Context-Window Memory Meter
                if let c = conv {
                    HStack(spacing: 6) {
                        Text(String(format: "%d / %d ctx", c.totalEstimatedTokensUsed, c.dials.numCtx))
                            .font(theme.monoFont(size: 11))
                            .foregroundStyle(palette.mutedText)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(palette.subtleSurface)
                                .frame(width: 48, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(c.contextFillFraction > 0.85 ? palette.statusWarning : palette.accent)
                                .frame(width: 48 * c.contextFillFraction, height: 5)
                        }
                    }
                    .help("Conversation Memory Usage — open Dials (⌘I) to expand context length")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isEditingSystemPrompt.toggle()
                    }
                } label: {
                    StudioIcon(.edit, size: 13, color: isEditingSystemPrompt ? palette.accent : palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Edit Pinned System Prompt / Persona")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.isInspectorDrawerOpen.toggle()
                    }
                } label: {
                    StudioIcon(.dials, size: 14, color: appState.isInspectorDrawerOpen ? palette.accent : palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Open Parameter Dials Drawer (⌘I)")
            }
            .padding(.horizontal, 22)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairlineBorder).frame(height: 1)
            }

            // 2. Collapsible Pinned System Prompt / Persona Bar
            if isEditingSystemPrompt, let idx = appState.activeConversationIndex {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pinned System Persona")
                            .font(theme.captionFont(weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Menu("Load Preset") {
                            ForEach(PersonaPreset.library) { preset in
                                Button(preset.title) {
                                    appState.conversations[idx].dials.systemPrompt = preset.systemPrompt
                                    appState.conversations[idx].dials.temperature = preset.recommendedTemperature
                                    appState.conversations[idx].dials.numCtx = preset.recommendedCtx
                                    appState.persistVault()
                                }
                            }
                        }
                        .font(theme.captionFont())
                        .frame(width: 120)

                        Button("Save Chat Settings as Model") {
                            appState.loadActiveChatIntoModelBuilder()
                        }
                        .buttonStyle(.plain)
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(palette.accent)
                    }

                    TextEditor(text: Binding(
                        get: { appState.conversations[idx].dials.systemPrompt },
                        set: {
                            appState.conversations[idx].dials.systemPrompt = $0
                            appState.persistVault()
                        }
                    ))
                    .font(theme.bodyFont())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 68)
                    .background(
                        RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                            .fill(palette.cardSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                            .strokeBorder(palette.hairlineBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(palette.subtleSurface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.hairlineBorder).frame(height: 1)
                }
            }

            // 3. Centered Editorial Conversation Stream
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let messages = conv?.messages, !messages.isEmpty {
                            ForEach(messages) { message in
                                EditorialMessageRow(
                                    message: message,
                                    verboseMetrics: conv?.dials.verboseMetrics ?? true,
                                    softWrap: conv?.dials.softWordWrap ?? true,
                                    isEditing: editingMessageID == message.id,
                                    editingText: $editingMessageText,
                                    palette: palette,
                                    onStartEdit: {
                                        editingMessageID = message.id
                                        editingMessageText = message.content
                                    },
                                    onCancelEdit: {
                                        editingMessageID = nil
                                    },
                                    onCommitEdit: {
                                        let id = message.id
                                        let updated = editingMessageText
                                        editingMessageID = nil
                                        appState.updateAndResendMessage(messageID: id, updatedText: updated)
                                    }
                                )
                                .id(message.id)
                            }
                        } else {
                            CalmEmptyConversationState(palette: palette)
                                .padding(.top, 64)
                        }
                    }
                    .frame(maxWidth: StudioMetrics.readingColumnMaxWidth)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: conv?.messages.last?.content) { _, _ in
                    if let lastID = conv?.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            // 4. Clean Centered Prompt Composer
            VStack(spacing: 8) {
                if !pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingAttachments) { att in
                                HStack(spacing: 6) {
                                    StudioIcon(att.kind == .image ? .photo : .doc, size: 12, color: palette.accent)
                                    Text(att.fileName)
                                        .font(theme.captionFont(weight: .medium))
                                        .foregroundStyle(palette.primaryText)
                                        .lineLimit(1)
                                    Button {
                                        pendingAttachments.removeAll(where: { $0.id == att.id })
                                    } label: {
                                        StudioIcon(.close, size: 10, color: palette.mutedText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                        .fill(palette.subtleSurface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                        .strokeBorder(palette.hairlineBorder, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: StudioMetrics.readingColumnMaxWidth)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    // Attach Image or Local Document
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        StudioIcon(.paperclip, size: 15, color: palette.secondaryText)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("Attach image (Vision) or local PDF/Text/Code file (100% private on device)")

                    TextField(
                        conv?.selectedModel.isEmpty == false
                            ? "Message \(conv!.selectedModel.replacingOccurrences(of: ":latest", with: ""))..."
                            : "Select or pull a model in Models & RAM (⌘2)...",
                        text: $draftPrompt,
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(theme.conversationFont())
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1...8)
                    .onSubmit {
                        triggerSend()
                    }

                    // Contextual Session Controls Popover Trigger (Replaces all 25 CLI Slash Commands Visually)
                    Button {
                        appState.isQuickActionSheetOpen = true
                    } label: {
                        StudioIcon(.sliders, size: 14, color: palette.secondaryText)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .help("Session Controls & Model Inspector (⌘K)")

                    // Send or Stop Button
                    if appState.isGeneratingReply {
                        Button {
                            appState.stopActiveGeneration()
                        } label: {
                            StudioIcon(.stop, size: 12, color: Color.white)
                                .padding(7)
                                .background(
                                    RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                        .fill(palette.statusDanger)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Stop generating")
                    } else {
                        Button {
                            triggerSend()
                        } label: {
                            StudioIcon(.send, size: 13, color: Color.white)
                                .padding(7)
                                .background(
                                    RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                        .fill(palette.accent)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: StudioMetrics.readingColumnMaxWidth)
                .background(
                    RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                        .fill(palette.elevatedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                        .strokeBorder(palette.hairlineBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .pdf, .plainText, .sourceCode, .json, .commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if let att = appState.loadAttachment(from: url) {
                        pendingAttachments.append(att)
                    }
                }
            }
        }
    }

    private func triggerSend() {
        let text = draftPrompt
        let atts = pendingAttachments
        draftPrompt = ""
        pendingAttachments = []
        appState.sendUserMessage(text: text, attachments: atts)
    }
}

// MARK: - Editorial Message Row & Collapsible Thinking Panel

public struct EditorialMessageRow: View {
    @EnvironmentObject private var theme: ThemeManager
    public let message: ChatMessage
    public let verboseMetrics: Bool
    public let softWrap: Bool
    public let isEditing: Bool
    @Binding public var editingText: String
    public let palette: StudioPalette
    public let onStartEdit: () -> Void
    public let onCancelEdit: () -> Void
    public let onCommitEdit: () -> Void

    @State private var isThinkingExpanded: Bool = false
    @State private var didCopy: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Role Label + Metadata
            HStack(spacing: 8) {
                Text(message.role == .user ? "You" : (message.modelUsed?.replacingOccurrences(of: ":latest", with: "") ?? "Assistant"))
                    .font(theme.captionFont(weight: .semibold))
                    .foregroundStyle(message.role == .user ? palette.secondaryText : palette.accent)

                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { att in
                        StudioPillBadge(att.fileName, palette: palette)
                    }
                }

                Spacer()

                // Quiet Action Buttons (Edit / Copy)
                if !message.isStreaming {
                    Button {
                        onStartEdit()
                    } label: {
                        StudioIcon(.edit, size: 11, color: palette.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Edit message and regenerate")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                    } label: {
                        StudioIcon(didCopy ? .check : .copy, size: 11, color: didCopy ? palette.accent : palette.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Copy text")
                }
            }

            // Collapsible Reasoning / Thinking Accordion (for DeepSeek R1, Qwen3, etc.)
            if !message.thinkingContent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isThinkingExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            StudioIcon(isThinkingExpanded ? .chevronDown : .chevronRight, size: 10, color: palette.mutedText)
                            if let secs = message.thinkingDurationSeconds {
                                Text(String(format: "Thought for %.1fs", secs))
                                    .font(theme.captionFont(weight: .medium))
                                    .foregroundStyle(palette.mutedText)
                            } else {
                                Text("Reasoning in progress...")
                                    .font(theme.captionFont(weight: .medium))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if isThinkingExpanded {
                        Text(message.thinkingContent)
                            .font(theme.bodyFont())
                            .foregroundStyle(palette.secondaryText)
                            .lineSpacing(4)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(palette.hairlineBorder)
                                    .frame(width: 2)
                            }
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 2)
            }

            // Message Body or Inline Editor
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $editingText)
                        .font(theme.conversationFont())
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 70)
                        .background(
                            RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                .fill(palette.subtleSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                .strokeBorder(palette.accent, lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button("Save & Regenerate") { onCommitEdit() }
                            .buttonStyle(.plain)
                            .font(theme.captionFont(weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(palette.accent))

                        Button("Cancel") { onCancelEdit() }
                            .buttonStyle(.plain)
                            .font(theme.captionFont())
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            } else {
                Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
                    .font(theme.conversationFont(weight: message.role == .user ? .medium : .regular))
                    .foregroundStyle(palette.primaryText)
                    .lineSpacing(5)
                    .fixedSize(horizontal: !softWrap, vertical: true)
                    .textSelection(.enabled)
            }

            // Tabular Performance Footer (`tokens/sec`, `TTFT`, token count)
            if verboseMetrics, message.role == .assistant, let tps = message.tokensPerSecond {
                HStack(spacing: 12) {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(palette.mutedText)
                    if let ttft = message.timeToFirstTokenMs {
                        Text(String(format: "TTFT %.0f ms", ttft))
                            .font(theme.monoFont(size: 11))
                            .foregroundStyle(palette.mutedText)
                    }
                    if let comp = message.completionTokens {
                        Text("\(comp) tokens")
                            .font(theme.monoFont(size: 11))
                            .foregroundStyle(palette.mutedText)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 6)
    }
}

public struct CalmEmptyConversationState: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quiet, Local Workspace")
                .font(theme.titleFont())
                .foregroundStyle(palette.primaryText)

            Text("Everything you write and attach stays 100% on your Mac. Use ⌘I to tune sampling and memory dials, or ⌘2 to manage models in Unified Memory.")
                .font(theme.bodyFont())
                .foregroundStyle(palette.secondaryText)
                .lineSpacing(3)

            HStack(spacing: 10) {
                StudioPillBadge("⌘I  28 Precision Dials", palette: palette)
                StudioPillBadge("⌘2  Models & Hugging Face", palette: palette)
                StudioPillBadge("⌘K  Session Controls", palette: palette)
            }
        }
        .padding(22)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                .fill(palette.subtleSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                .strokeBorder(palette.hairlineBorder, lineWidth: 1)
        )
    }
}

// MARK: - Quick Session Controls Sheet (Visual Parity with All 25 CLI Commands)

public struct QuickSessionActionsSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    public let palette: StudioPalette

    public var body: some View {
        let idx = appState.activeConversationIndex

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session & Model Controls")
                    .font(theme.titleFont())
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button { dismiss() } label: {
                    StudioIcon(.close, size: 13, color: palette.secondaryText)
                }
                .buttonStyle(.plain)
            }

            if let i = idx {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Runtime Toggles")
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(palette.mutedText)

                    Picker("Reasoning / Thinking Mode", selection: $appState.conversations[i].dials.thinkingMode) {
                        ForEach(ThinkingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Picker("Output Format", selection: $appState.conversations[i].dials.formatMode) {
                        ForEach(ResponseFormatMode.allCases) { fmt in
                            Text(fmt.label).tag(fmt)
                        }
                    }

                    Toggle("Stateless Single-Turn Mode (Do not send prior chat history)", isOn: $appState.conversations[i].dials.statelessNoHistory)
                    Toggle("Show Speed Metrics (tokens/sec & latency)", isOn: $appState.conversations[i].dials.verboseMetrics)
                    Toggle("Soft Line Wrapping", isOn: $appState.conversations[i].dials.softWordWrap)
                }
                .font(theme.bodyFont())

                Divider().overlay(palette.hairlineBorder)

                HStack(spacing: 10) {
                    Button("Clear Conversation Context") {
                        appState.clearActiveConversationMessages()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))

                    Button("Bake Session into New Model") {
                        dismiss()
                        appState.loadActiveChatIntoModelBuilder()
                    }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont(weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.accentSoft))

                    Spacer()

                    if !appState.conversations[i].selectedModel.isEmpty {
                        Button("Unload Model from RAM") {
                            appState.ejectModelFromRAM(appState.conversations[i].selectedModel)
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .font(theme.bodyFont(weight: .medium))
                        .foregroundStyle(palette.statusDanger)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(palette.cardSurface)
        .onDisappear { appState.persistVault() }
    }
}
