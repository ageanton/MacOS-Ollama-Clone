set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Views/EditorialConversationView.swift
import SwiftUI
import AppKit

private struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 86.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct EditorialConversationView: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens

    @State private var editingMessageNodeID: UUID? = nil
    @State private var editMessageDraft: String = ""
    @State private var clearThinkingOnAssistantEdit: Bool = false
    @State private var isEditBoxExpandedFull: Bool = false
    @State private var copiedMessageID: UUID? = nil
    @State private var confirmingDeleteNodeID: UUID? = nil
    @State private var composerMeasuredHeight: CGFloat = 86.0

    private var typo: TypographyConfiguration { store.typography }

    public var body: some View {
        GeometryReader { geo in
            let canvasWidth = geo.size.width
            let isFullscreenOrWide = store.isWindowFullscreen || canvasWidth >= 1320
            let isCompactWindow = canvasWidth < 960
            let useLeftMetadataGutter = canvasWidth >= 1120
            let horizontalOuterPadding: CGFloat = canvasWidth < 1040 ? 18.0 : 28.0

            let opticalFontSize = typo.effectiveFontSize(
                forCanvasWidth: canvasWidth,
                isFullscreen: isFullscreenOrWide
            )
            let adaptiveProseWidth = typo.effectiveReadingWidth(
                forCanvasWidth: canvasWidth,
                isFullscreen: isFullscreenOrWide
            )
            let totalRowMaxWidth: CGFloat = useLeftMetadataGutter
                ? min(canvasWidth - (horizontalOuterPadding * 2), adaptiveProseWidth + 148)
                : adaptiveProseWidth

            VStack(spacing: 0) {
                topHeaderBar(isCompactWindow: isCompactWindow)

                HairlineDivider(tokens: tokens)

                if let errBanner = store.humanReadableErrorBanner {
                    errorNoticeBanner(text: errBanner)
                }

                if let session = store.activeSession {
                    contextAndMemoryTopBanner(session: session)

                    ZStack(alignment: .bottom) {
                        if session.activeBranchThread.isEmpty {
                            newChatPreFlightCanvas(session: session, maxCardWidth: min(totalRowMaxWidth, 560))
                        } else {
                            conversationStreamCanvas(
                                session: session,
                                useLeftGutter: useLeftMetadataGutter,
                                totalRowMaxWidth: totalRowMaxWidth,
                                horizontalPadding: horizontalOuterPadding,
                                opticalFontSize: opticalFontSize,
                                isFullscreenOrWide: isFullscreenOrWide
                            )
                        }

                        ProgressiveComposerBar(
                            store: store,
                            tokens: tokens,
                            maxBarWidth: totalRowMaxWidth,
                            activeFontSize: opticalFontSize,
                            isWideOrFullscreen: isFullscreenOrWide
                        )
                        .padding(.horizontal, horizontalOuterPadding)
                        .padding(.bottom, 14)
                        .background(
                            GeometryReader { compGeo in
                                Color.clear.preference(
                                    key: ComposerHeightPreferenceKey.self,
                                    value: compGeo.size.height
                                )
                            }
                        )
                    }
                    .onPreferenceChange(ComposerHeightPreferenceKey.self) { newH in
                        if abs(composerMeasuredHeight - newH) > 1.0 {
                            composerMeasuredHeight = newH
                        }
                    }
                } else {
                    strictNoSessionLandingGate
                }
            }
            .background(tokens.canvasBackground)
        }
    }

    // MARK: - True Fullscreen Top Header Bar (Zero NSToolbar Waste & Crash-Free Sidebar Toggle)
    private func topHeaderBar(isCompactWindow: Bool) -> some View {
        // When sidebar is hidden in windowed mode, leave 74pt on the left for the macOS traffic lights
        let leadingTrafficLightClearance: CGFloat = (!store.isSidebarVisible && !store.isWindowFullscreen) ? 78.0 : 18.0

        return HStack(alignment: .center, spacing: 10) {
            if !store.isSidebarVisible {
                Button {
                    store.isSidebarVisible = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(tokens.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tokens.elevatedSurface)
                        )
                }
                .buttonStyle(.plain)
                .help("Show Sidebar (⌘\(store.shortcuts.toggleSidebarKey.uppercased()))")

                Button {
                    store.createNewSession(folderID: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(tokens.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tokens.elevatedSurface)
                        )
                }
                .buttonStyle(.plain)
                .help("New Chat (⌘\(store.shortcuts.newChatKey.uppercased()))")
            }

            Text(store.activeSession?.title ?? "Motif")
                .font(typo.sans(size: 13.5, weight: .semibold))
                .foregroundColor(tokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if store.activeSession != nil {
                livingModelSelectorPill(isCompactWindow: isCompactWindow)
            }

            HeaderMemoryIndicatorView(
                store: store,
                tokens: tokens,
                isCompactWindow: isCompactWindow
            )

            if store.activeSession != nil {
                Button {
                    store.userManuallyClosedRightPaneInWideMode = store.isRightUtilityPaneOpen
                    store.isRightUtilityPaneOpen.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(store.isRightUtilityPaneOpen ? tokens.accentAction : tokens.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tokens.elevatedSurface.opacity(store.isRightUtilityPaneOpen ? 1.0 : 0.65))
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle Code Inspector (⌘\(store.shortcuts.toggleInspectorKey))")
            }
        }
        .padding(.leading, leadingTrafficLightClearance)
        .padding(.trailing, 18)
        .frame(height: 44)
    }

    @ViewBuilder
    private func livingModelSelectorPill(isCompactWindow: Bool) -> some View {
        let isLoading = store.isLoadingModelWeights
        let snap = store.memorySnapshot
        let loadFraction = isLoading ? CGFloat(min(0.99, max(0.03, snap.loadProgressAgainstTarget))) : 0.0
        let pct = Int(loadFraction * 100.0)
        let isResident = store.activeModelDescriptor?.residency == .activeInUnifiedRAM
        let flashOpacity = store.modelLoadCompletionRimFlashOpacity
        let isFlashingCompletion = flashOpacity > 0.01
        let activeModelTitle = isLoading
            ? LocalModelDescriptor.shortenModelName(store.loadingModelName)
            : (store.activeModelDescriptor?.shortDisplayName ?? "Select Model")

        HStack(spacing: 6) {
            if isLoading && store.isConfirmingModelLoadCancel {
                HStack(spacing: 8) {
                    Text("Cancel loading \(activeModelTitle)?")
                        .font(typo.sans(size: 11, weight: .semibold))
                        .foregroundColor(tokens.primaryText)

                    Button("Cancel Load") {
                        store.confirmCancelModelLoad()
                    }
                    .font(typo.sans(size: 10.5, weight: .semibold))
                    .foregroundColor(tokens.accentForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tokens.accentAction))
                    .buttonStyle(.plain)

                    Button("Keep") {
                        store.isConfirmingModelLoadCancel = false
                    }
                    .font(typo.sans(size: 10.5))
                    .foregroundColor(tokens.secondaryText)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(tokens.elevatedSurface)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(tokens.accentAction.opacity(0.65), lineWidth: 1.5))
            } else {
                Button {
                    store.isModelPickerPopoverPresented.toggle()
                } label: {
                    HStack(spacing: 7) {
                        if isLoading {
                            Circle()
                                .fill(tokens.accentAction)
                                .frame(width: 6, height: 6)
                        } else if isResident {
                            Circle()
                                .fill(tokens.statusOnline)
                                .frame(width: 6, height: 6)
                                .scaleEffect(isFlashingCompletion ? 1.25 : 1.0)
                        } else {
                            Circle()
                                .strokeBorder(tokens.mutedText, lineWidth: 1.3)
                                .frame(width: 6, height: 6)
                        }

                        Text(activeModelTitle)
                            .font(typo.sans(size: 12, weight: .medium))
                            .foregroundColor(tokens.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: isCompactWindow ? 130 : 195, alignment: .leading)

                        if isLoading {
                            Text("\(pct)%")
                                .font(typo.sans(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundColor(tokens.accentAction)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(tokens.mutedText)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        GeometryReader { pillGeo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(
                                        isFlashingCompletion
                                            ? tokens.statusOnline.opacity(0.12 * flashOpacity)
                                            : (isLoading ? tokens.accentAction.opacity(0.07) : tokens.canvasBackground)
                                    )

                                if isLoading {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    tokens.accentAction.opacity(0.22),
                                                    tokens.accentAction.opacity(0.12)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, pillGeo.size.width * loadFraction))
                                        .animation(.easeOut(duration: 0.22), value: loadFraction)
                                }
                            }
                        }
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isFlashingCompletion
                                    ? tokens.statusOnline.opacity(max(0.35, flashOpacity))
                                    : (isLoading ? tokens.accentAction.opacity(0.78) : tokens.hairline),
                                lineWidth: isFlashingCompletion ? 1.85 : (isLoading ? 1.65 : 1.0)
                            )
                    )
                    .shadow(
                        color: isFlashingCompletion ? tokens.statusOnline.opacity(0.38 * flashOpacity) : Color.clear,
                        radius: 6,
                        y: 0
                    )
                }
                .buttonStyle(.plain)
                .help(isLoading
                      ? String(format: "Loading %@ into Unified RAM (%.1f / %.1f GB · %d%%)", store.loadingModelName, max(snap.weightsGB, snap.activeRAMDeltaGB), max(0.1, snap.targetModelGB), pct)
                      : (store.activeModelDescriptor?.shortDisplayName ?? "Select local model"))
                .popover(isPresented: $store.isModelPickerPopoverPresented, arrowEdge: .bottom) {
                    ModelPickerPopoverView(store: store, tokens: tokens)
                }

                if isLoading {
                    Button {
                        store.requestCancelModelLoadConfirmation()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(tokens.secondaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(tokens.elevatedSurface))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel model loading…")
                }
            }
        }
    }

    // MARK: - Refined Top Context Ceiling & Memory Pressure Bar (Dismissible; Always Accessible in Top-Right RAM Menu)
    @ViewBuilder
    private func contextAndMemoryTopBanner(session: ConversationSession) -> some View {
        let usedTok = session.estimatedActiveTokens
        let maxTok = max(1, session.parameters.numCtx)
        let ratio = Double(usedTok) / Double(maxTok)
        let hasMemWarn = store.kernelMemoryPressureWarning != nil
        let showContextWarn = ratio >= 0.80 && !store.isContextCeilingBannerDismissed

        if hasMemWarn || showContextWarn {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)

                    if let memText = store.kernelMemoryPressureWarning {
                        Text(memText)
                            .font(typo.sans(size: 12, weight: .medium))
                            .foregroundColor(tokens.primaryText)
                    } else {
                        Text("Context window is at \(Int(min(100, ratio * 100)))% (\(usedTok) / \(maxTok) tok)")
                            .font(typo.sans(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.primaryText)
                    }

                    Spacer()

                    Button {
                        store.trimOldestTurnInActiveSession()
                    } label: {
                        Text("Trim Oldest Turn")
                            .font(typo.sans(size: 11.5, weight: .semibold))
                            .foregroundColor(tokens.primaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(tokens.canvasBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(tokens.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.summarizeContextIntoNewBranch()
                    } label: {
                        Text("Summarize into Branch")
                            .font(typo.sans(size: 11.5, weight: .semibold))
                            .foregroundColor(tokens.accentForeground)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tokens.accentAction))
                            .buttonStyle(.plain)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.kernelMemoryPressureWarning = nil
                        store.isContextCeilingBannerDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(tokens.mutedText)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss banner (these tools remain available inside the top-right RAM menu)")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(tokens.elevatedSurface)

                HairlineDivider(tokens: tokens)
            }
        }
    }

    private func errorNoticeBanner(text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(typo.sans(size: 12))
                .foregroundColor(tokens.primaryText)
            Spacer()
            if !store.supervisor.isEngineOnline {
                Button("Start Ollama") {
                    Task { await store.bootstrapLocalOllamaConnection() }
                }
                .font(typo.sans(size: 11.5, weight: .semibold))
                .buttonStyle(.plain)
            }
            Button("Dismiss") {
                store.humanReadableErrorBanner = nil
            }
            .font(typo.sans(size: 11.5))
            .foregroundColor(tokens.secondaryText)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(tokens.elevatedSurface)
    }

    // MARK: - Strict .noSession Gate
    private var strictNoSessionLandingGate: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Motif")
                .font(typo.wordmark(size: 30))
                .foregroundColor(tokens.primaryText)

            Text("No active chat session. Create a new chat to select a model and begin.")
                .font(typo.sans(size: 13.5))
                .foregroundColor(tokens.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                store.createNewSession(folderID: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("New Chat")
                        .font(typo.sans(size: 13.5, weight: .semibold))
                }
                .foregroundColor(tokens.accentForeground)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tokens.accentAction)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - New-Chat Pre-Flight Launch Deck (Shows Model Residency, Live Loading Progress, Thinking Mode & Parameters Before Typing)
    @ViewBuilder
    private func newChatPreFlightCanvas(session: ConversationSession, maxCardWidth: CGFloat) -> some View {
        let activeSessionIdx = store.sessions.firstIndex(where: { $0.id == session.id })
        let model = store.activeModelDescriptor
        let isLoading = store.isLoadingModelWeights
        let snap = store.memorySnapshot
        let loadFraction = isLoading ? CGFloat(min(0.99, max(0.03, snap.loadProgressAgainstTarget))) : 0.0
        let pct = Int(loadFraction * 100.0)
        let allocatedGB = max(snap.weightsGB, snap.activeRAMDeltaGB)
        let targetGB = max(0.1, snap.targetModelGB)

        VStack(spacing: 18) {
            Spacer()

            // Title & Model Status Header
            VStack(spacing: 6) {
                Text(session.title)
                    .font(typo.sans(size: 21, weight: .semibold))
                    .foregroundColor(tokens.primaryText)

                if let m = model {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isLoading ? tokens.accentAction : (m.residency == .activeInUnifiedRAM ? tokens.statusOnline : tokens.mutedText))
                            .frame(width: 6.5, height: 6.5)

                        Text("\(m.shortDisplayName) · \(m.formattedSize) · \(m.residency.rawValue)")
                            .font(typo.sans(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.secondaryText)
                    }
                } else {
                    Text("Pull a local model in Settings or start Ollama to begin.")
                        .font(typo.sans(size: 12.5))
                        .foregroundColor(tokens.secondaryText)
                }
            }

            // Architectural Pre-Flight Configuration Card
            if let sIdx = activeSessionIdx, let m = model {
                let sessionBinding = $store.sessions[sIdx]
                let profile = m.thinkingProfile

                VStack(alignment: .leading, spacing: 12) {
                    // Row 1: Model Residency / Live Weight Loading Progress Inside New Chat
                    if isLoading {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Loading \(store.loadingModelName) into Unified RAM…")
                                    .font(typo.sans(size: 12, weight: .semibold))
                                    .foregroundColor(tokens.primaryText)
                                Spacer()
                                Text(String(format: "%.1f / %.1f GB (%d%%)", allocatedGB, targetGB, pct))
                                    .font(typo.sans(size: 11.5, weight: .semibold).monospacedDigit())
                                    .foregroundColor(tokens.accentAction)
                            }

                            ProgressView(value: Double(loadFraction))
                                .tint(tokens.accentAction)

                            HStack {
                                Text("Weights are mapping into memory. You can start typing below while it loads.")
                                    .font(typo.sans(size: 11))
                                    .foregroundColor(tokens.mutedText)
                                Spacer()
                                if store.isConfirmingModelLoadCancel {
                                    Button("Confirm Cancel") {
                                        store.confirmCancelModelLoad()
                                    }
                                    .font(typo.sans(size: 11, weight: .semibold))
                                    .foregroundColor(.red)
                                    .buttonStyle(.plain)
                                } else {
                                    Button("Cancel Load") {
                                        store.requestCancelModelLoadConfirmation()
                                    }
                                    .font(typo.sans(size: 11, weight: .medium))
                                    .foregroundColor(tokens.secondaryText)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(10)
                        .background(tokens.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(tokens.accentAction.opacity(0.45), lineWidth: 1)
                        )
                    } else if m.residency != .activeInUnifiedRAM {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(m.shortDisplayName) is currently on disk")
                                    .font(typo.sans(size: 12, weight: .semibold))
                                    .foregroundColor(tokens.primaryText)
                                Text("Warm up weights in RAM now or send a message to load automatically.")
                                    .font(typo.sans(size: 11))
                                    .foregroundColor(tokens.secondaryText)
                            }
                            Spacer()
                            Button("Load into RAM") {
                                store.selectAndLoadModel(m)
                            }
                            .font(typo.sans(size: 11.5, weight: .semibold))
                            .foregroundColor(tokens.accentForeground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tokens.accentAction))
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(tokens.canvasBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(tokens.hairline, lineWidth: 1)
                        )
                    }

                    // Row 2: Thinking Mode Selector (Remembers Per-Model Preference!)
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Thinking Mode")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            Text(profile.kind.rawValue)
                                .font(typo.sans(size: 10.5))
                                .foregroundColor(tokens.mutedText)
                        }

                        Spacer()

                        if profile.kind != .unsupported || sessionBinding.wrappedValue.parameters.forceThinkingOverrideWhenUnsupported {
                            let allowedModes = sessionBinding.wrappedValue.parameters.forceThinkingOverrideWhenUnsupported
                                ? ThinkingModeOption.allCases
                                : profile.validOptions

                            Picker("", selection: sessionBinding.parameters.thinkingMode) {
                                ForEach(allowedModes) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: allowedModes.count > 2 ? 210 : 130)
                            .onChange(of: sessionBinding.wrappedValue.parameters.thinkingMode) { _, _ in
                                store.recordActiveModelParameterPreference()
                            }
                        } else {
                            Text("Standard (Off)")
                                .font(typo.sans(size: 11.5, weight: .medium))
                                .foregroundColor(tokens.mutedText)
                        }
                    }

                    HairlineDivider(tokens: tokens)

                    // Row 3: Context Window Selector
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Context Window")
                                .font(typo.sans(size: 12, weight: .semibold))
                                .foregroundColor(tokens.primaryText)
                            Text("\(sessionBinding.wrappedValue.parameters.numCtx) tokens · KV \(store.supervisor.kvCacheTypeEnv.rawValue.uppercased())")
                                .font(typo.sans(size: 10.5).monospacedDigit())
                                .foregroundColor(tokens.mutedText)
                        }

                        Spacer()

                        Picker("", selection: sessionBinding.parameters.numCtx) {
                            Text("2k").tag(2048)
                            Text("4k").tag(4096)
                            Text("8k").tag(8192)
                            Text("16k").tag(16384)
                            Text("32k").tag(32768)
                            Text("64k").tag(65536)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 245)
                        .onChange(of: sessionBinding.wrappedValue.parameters.numCtx) { _, _ in
                            store.recordActiveModelParameterPreference()
                            store.recalculateHardwareTelemetry()
                        }
                    }

                    HairlineDivider(tokens: tokens)

                    // Row 4: Quick Presets & Temperature
                    HStack(alignment: .center, spacing: 8) {
                        Text("Preset")
                            .font(typo.sans(size: 12, weight: .semibold))
                            .foregroundColor(tokens.primaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(store.presets) { preset in
                                    let isMatch = sessionBinding.wrappedValue.parameters == preset.parameters
                                    Button {
                                        sessionBinding.wrappedValue.parameters = preset.parameters
                                        sessionBinding.wrappedValue.systemPrompt = preset.systemPrompt
                                        store.recordActiveModelParameterPreference()
                                        if store.supervisor.kvCacheTypeEnv != preset.parameters.kvCacheQuant {
                                            store.applyKVCacheQuantizationLive(preset.parameters.kvCacheQuant)
                                        } else {
                                            store.recalculateHardwareTelemetry()
                                        }
                                    } label: {
                                        Text(preset.name)
                                            .font(typo.sans(size: 11, weight: isMatch ? .semibold : .medium))
                                            .foregroundColor(isMatch ? tokens.accentForeground : tokens.primaryText)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(isMatch ? tokens.accentAction : tokens.canvasBackground)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .strokeBorder(isMatch ? Color.clear : tokens.hairline, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        Text(String(format: "Temp %.2f", sessionBinding.wrappedValue.parameters.temperature))
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.secondaryText)

                        Slider(value: sessionBinding.parameters.temperature, in: 0.0...1.5)
                            .frame(width: 80)
                            .onChange(of: sessionBinding.wrappedValue.parameters.temperature) { _, _ in
                                store.recordActiveModelParameterPreference()
                            }
                    }
                }
                .padding(14)
                .frame(maxWidth: maxCardWidth)
                .background(tokens.elevatedSurface.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tokens.hairline, lineWidth: 1)
                )
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, max(90, composerMeasuredHeight))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message Stream with 520pt Scroll Threshold & Dynamic Composer Clearance
    private func conversationStreamCanvas(
        session: ConversationSession,
        useLeftGutter: Bool,
        totalRowMaxWidth: CGFloat,
        horizontalPadding: CGFloat,
        opticalFontSize: CGFloat,
        isFullscreenOrWide: Bool
    ) -> some View {
        let thread = session.activeBranchThread
        let lastTurnID = thread.last?.id
        let dynamicBottomClearance = max(130.0, composerMeasuredHeight + 28.0)
        let jumpButtonBottomOffset = max(96.0, composerMeasuredHeight + 12.0)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(thread) { node in
                        messageTurnView(
                            node: node,
                            session: session,
                            isLatestTurn: node.id == lastTurnID,
                            useLeftGutter: useLeftGutter,
                            opticalFontSize: opticalFontSize,
                            isFullscreenOrWide: isFullscreenOrWide
                        )
                        .id(node.id)
                    }

                    Color.clear
                        .frame(height: dynamicBottomClearance)
                        .id("STREAM_BOTTOM_ANCHOR")
                }
                .background(
                    ScrollViewBottomObserver(isScrolledAwayFromBottom: $store.isScrolledAwayFromBottom)
                        .frame(width: 1, height: 1)
                )
                .frame(maxWidth: totalRowMaxWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 22)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.streamScrollPulse) { _, _ in
                if store.isStreamingGeneration && !store.isScrolledAwayFromBottom && !store.isAutoScrollPaused {
                    proxy.scrollTo("STREAM_BOTTOM_ANCHOR", anchor: .bottom)
                }
            }
            .onChange(of: store.pendingScrollToMessageID) { _, targetID in
                if let id = targetID {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    store.pendingScrollToMessageID = nil
                }
            }
            .overlay(alignment: .bottom) {
                if store.isScrolledAwayFromBottom && !store.isComposerCanvasExpanded && store.matchedSlashPersonas.isEmpty {
                    HighContrastJumpToLatestButton(tokens: tokens) {
                        store.isScrolledAwayFromBottom = false
                        store.isAutoScrollPaused = false
                        if store.isStreamingGeneration {
                            proxy.scrollTo("STREAM_BOTTOM_ANCHOR", anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("STREAM_BOTTOM_ANCHOR", anchor: .bottom)
                            }
                        }
                    }
                    .padding(.bottom, jumpButtonBottomOffset)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func messageTurnView(
        node: ConversationMessageNode,
        session: ConversationSession,
        isLatestTurn: Bool,
        useLeftGutter: Bool,
        opticalFontSize: CGFloat,
        isFullscreenOrWide: Bool
    ) -> some View {
        let siblingMeta = session.siblingInfo(for: node.id)
        let isNodeStreaming = store.isStreamingGeneration && store.streamingNodeID == node.id

        VStack(alignment: .leading, spacing: 12) {
            if useLeftGutter {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        turnRoleOrHotSwapMenu(node: node, maxLabelWidth: 122)

                        if siblingMeta.totalCount > 1 {
                            branchPaginationControl(nodeID: node.id, siblingMeta: siblingMeta)
                        }

                        if isNodeStreaming {
                            Button("Stop") {
                                store.stopActiveGeneration()
                            }
                            .font(typo.sans(size: 11, weight: .semibold))
                            .foregroundColor(tokens.accentAction)
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 128, alignment: .leading)
                    .clipped()

                    VStack(alignment: .leading, spacing: 10) {
                        turnMainBody(
                            node: node,
                            isNodeStreaming: isNodeStreaming,
                            opticalFontSize: opticalFontSize,
                            isFullscreenOrWide: isFullscreenOrWide
                        )
                        turnBottomActionBar(
                            node: node,
                            session: session,
                            isLatestTurn: isLatestTurn,
                            isNodeStreaming: isNodeStreaming
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    turnRoleOrHotSwapMenu(node: node, maxLabelWidth: 210)

                    if siblingMeta.totalCount > 1 {
                        branchPaginationControl(nodeID: node.id, siblingMeta: siblingMeta)
                    }

                    Spacer()

                    if isNodeStreaming {
                        Button("Stop") {
                            store.stopActiveGeneration()
                        }
                        .font(typo.sans(size: 11.5, weight: .semibold))
                        .foregroundColor(tokens.accentAction)
                        .buttonStyle(.plain)
                    }
                }

                turnMainBody(
                    node: node,
                    isNodeStreaming: isNodeStreaming,
                    opticalFontSize: opticalFontSize,
                    isFullscreenOrWide: isFullscreenOrWide
                )
                turnBottomActionBar(
                    node: node,
                    session: session,
                    isLatestTurn: isLatestTurn,
                    isNodeStreaming: isNodeStreaming
                )
            }

            HairlineDivider(tokens: tokens)
                .padding(.top, 6)
        }
        .contextMenu {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.content.isEmpty ? node.thinkingTrace : node.content, forType: .string)
            }
            Button(node.role == .user ? "Edit Prompt…" : "Edit / Trim Reply to Save KV RAM…") {
                editMessageDraft = node.content
                clearThinkingOnAssistantEdit = false
                isEditBoxExpandedFull = false
                editingMessageNodeID = node.id
            }
            Button("Branch to New Chat from Here") {
                store.branchMessageToNewChat(upToNodeID: node.id)
            }
            Divider()
            Button("Delete Message (Free ~\(node.estimatedTokenFootprint) tok)…", role: .destructive) {
                confirmingDeleteNodeID = node.id
            }
        }
    }

    @ViewBuilder
    private func turnRoleOrHotSwapMenu(node: ConversationMessageNode, maxLabelWidth: CGFloat) -> some View {
        if node.role == .user {
            Text("You")
                .font(typo.sans(size: 12, weight: .semibold))
                .foregroundColor(tokens.primaryText)
        } else {
            let rawModel = node.modelUsed.isEmpty ? "Assistant" : node.modelUsed
            let shortLabel = LocalModelDescriptor.shortenModelName(rawModel)

            Menu {
                Text("Regenerate turn with model:")
                ForEach(store.availableModels) { model in
                    Button(model.shortDisplayName) {
                        store.regenerateAssistantBranch(forAssistantNodeID: node.id, withOverrideModel: model.name)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(shortLabel)
                        .font(typo.sans(size: 12, weight: .semibold))
                        .foregroundColor(tokens.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(tokens.mutedText)
                }
                .frame(maxWidth: maxLabelWidth, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: maxLabelWidth, alignment: .leading)
            .help("\(shortLabel) — Click to hot-swap model and regenerate this reply")
        }
    }

    private func branchPaginationControl(nodeID: UUID, siblingMeta: (currentIndex: Int, totalCount: Int)) -> some View {
        HStack(spacing: 2) {
            Button {
                store.switchBranchVersion(forNodeID: nodeID, delta: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(siblingMeta.currentIndex == 0)
            .opacity(siblingMeta.currentIndex == 0 ? 0.35 : 1.0)

            Text("\(siblingMeta.currentIndex + 1)/\(siblingMeta.totalCount)")
                .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                .padding(.horizontal, 2)

            Button {
                store.switchBranchVersion(forNodeID: nodeID, delta: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(siblingMeta.currentIndex >= siblingMeta.totalCount - 1)
            .opacity(siblingMeta.currentIndex >= siblingMeta.totalCount - 1 ? 0.35 : 1.0)
        }
        .foregroundColor(tokens.secondaryText)
        .padding(.horizontal, 3)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tokens.elevatedSurface.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(tokens.hairline, lineWidth: 1)
        )
        .help("Switch between conversation branches (inactive branches are stored on disk and use zero active KV RAM)")
    }

    @ViewBuilder
    private func turnMainBody(
        node: ConversationMessageNode,
        isNodeStreaming: Bool,
        opticalFontSize: CGFloat,
        isFullscreenOrWide: Bool
    ) -> some View {
        if !node.attachments.isEmpty {
            HStack(spacing: 8) {
                ForEach(node.attachments) { att in
                    Text("\(att.title) (\(att.formattedByteSize) · ~\(att.tokenEstimate) tok)")
                        .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(tokens.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tokens.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }

        if !node.thinkingTrace.isEmpty || (!node.isThinkingComplete && isNodeStreaming) {
            thinkingDisclosureView(for: node, isStreaming: isNodeStreaming, opticalFontSize: opticalFontSize)
        }

        if editingMessageNodeID == node.id {
            // Generously sized editor that scales with the length of the message (up to 560pt-760pt, or 920pt with Full Height toggle!)
            let approxLines = max(6, editMessageDraft.components(separatedBy: .newlines).reduce(0) { $0 + max(1, ($1.count / 72) + 1) })
            let naturalEditorHeight = CGFloat(approxLines) * (opticalFontSize * 1.55) + 36.0
            let maxStandardHeight: CGFloat = isFullscreenOrWide ? 680.0 : 500.0
            let editorHeight: CGFloat = isEditBoxExpandedFull
                ? min(960.0, max(maxStandardHeight, naturalEditorHeight))
                : min(maxStandardHeight, max(200.0, naturalEditorHeight))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(node.role == .user ? "Editing Prompt" : "Editing AI Reply (Trim text to reclaim KV cache memory)")
                        .font(typo.sans(size: 11.5, weight: .semibold))
                        .foregroundColor(tokens.secondaryText)

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            isEditBoxExpandedFull.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isEditBoxExpandedFull
                                  ? "arrow.down.right.and.arrow.up.left"
                                  : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(isEditBoxExpandedFull ? "Standard Height" : "Expand Full Height")
                                .font(typo.sans(size: 11, weight: .medium))
                        }
                        .foregroundColor(tokens.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tokens.elevatedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                MotifStyledTextEditor(
                    text: $editMessageDraft,
                    font: typo.nsFont(size: opticalFontSize),
                    tokens: tokens
                )
                .frame(height: editorHeight)
                .padding(8)
                .background(tokens.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tokens.strongBorder, lineWidth: 1)
                )

                HStack(spacing: 12) {
                    if node.role == .assistant {
                        if !node.thinkingTrace.isEmpty {
                            Toggle("Also clear thinking trace (~\(max(1, node.thinkingTrace.count / 4)) tok)", isOn: $clearThinkingOnAssistantEdit)
                                .font(typo.sans(size: 11.5))
                                .foregroundColor(tokens.secondaryText)
                        }
                        let oldTok = node.estimatedTokenFootprint
                        let newTok = max(1, editMessageDraft.count / 4) + (clearThinkingOnAssistantEdit ? 0 : (node.thinkingTrace.count / 4))
                        let savedTok = max(0, oldTok - newTok)
                        if savedTok > 0 {
                            Text("Saves ~\(savedTok) KV tok")
                                .font(typo.sans(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundColor(tokens.accentAction)
                        }
                    }

                    Spacer()

                    Button("Cancel") {
                        editingMessageNodeID = nil
                    }
                    .font(typo.sans(size: 12))
                    .foregroundColor(tokens.secondaryText)
                    .buttonStyle(.plain)

                    if node.role == .user {
                        Button("Save & Resubmit") {
                            let updated = editMessageDraft
                            editingMessageNodeID = nil
                            store.createEditedMessageBranch(originalNodeID: node.id, updatedText: updated)
                        }
                        .font(typo.sans(size: 12, weight: .semibold))
                        .foregroundColor(tokens.accentForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tokens.accentAction))
                        .buttonStyle(.plain)
                    } else {
                        Button("Save Trimmed Reply") {
                            let updated = editMessageDraft
                            let clearThink = clearThinkingOnAssistantEdit
                            editingMessageNodeID = nil
                            store.updateAssistantMessageInPlace(nodeID: node.id, updatedText: updated, clearThinking: clearThink)
                        }
                        .font(typo.sans(size: 12, weight: .semibold))
                        .foregroundColor(tokens.accentForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tokens.accentAction))
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if node.content.isEmpty && isNodeStreaming {
            if store.isLoadingModelWeights {
                let snap = store.memorySnapshot
                let pct = Int(snap.loadProgressAgainstTarget * 100.0)
                Text(String(format: "Loading weights into Unified Memory (%.1f / %.1f GB · %d%%)…", max(snap.weightsGB, snap.activeRAMDeltaGB), max(0.1, snap.targetModelGB), pct))
                    .font(typo.sans(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(tokens.mutedText)
            } else if node.thinkingTrace.isEmpty {
                Text("Generating…")
                    .font(typo.sans(size: 12, weight: .medium))
                    .foregroundColor(tokens.mutedText)
            }
        } else if !node.content.isEmpty {
            StreamSafeMarkdownView(
                rawMarkdown: isNodeStreaming ? (node.content + " ▍") : node.content,
                isStreaming: isNodeStreaming,
                effectiveFontSize: opticalFontSize,
                tokens: tokens,
                typo: typo,
                onOpenCodeInInspector: { _, _ in
                    store.userManuallyClosedRightPaneInWideMode = false
                    store.isRightUtilityPaneOpen = true
                }
            )
        }

        if let err = node.errorNote {
            Text(err)
                .font(typo.sans(size: 12.5))
                .foregroundColor(.red)
        }
    }

    // MARK: - Unified Bottom Action & Live Telemetry Bar (Shows Live `Chat Total` During Streaming, When Stopped Midway & When Completed!)
    @ViewBuilder
    private func turnBottomActionBar(
        node: ConversationMessageNode,
        session: ConversationSession,
        isLatestTurn: Bool,
        isNodeStreaming: Bool
    ) -> some View {
        if isNodeStreaming {
            HStack(spacing: 10) {
                Spacer()
                if store.liveTokensPerSec > 0 || store.liveTotalTokens > 0 {
                    Text(String(format: "%.1f tok/s · %d tok · Chat Total: %d tok", store.liveTokensPerSec, store.liveTotalTokens, session.estimatedActiveTokens))
                        .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(tokens.secondaryText)
                }
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 14) {
                if confirmingDeleteNodeID == node.id {
                    HStack(spacing: 8) {
                        Text("Delete turn & free ~\(node.estimatedTokenFootprint) tok?")
                            .font(typo.sans(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundColor(tokens.primaryText)

                        Button("Confirm Delete") {
                            confirmingDeleteNodeID = nil
                            store.deleteSingleMessageNode(node.id)
                        }
                        .font(typo.sans(size: 11, weight: .semibold))
                        .foregroundColor(tokens.accentForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tokens.accentAction))
                        .buttonStyle(.plain)

                        Button("Cancel") {
                            confirmingDeleteNodeID = nil
                        }
                        .font(typo.sans(size: 11))
                        .foregroundColor(tokens.secondaryText)
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.content.isEmpty ? node.thinkingTrace : node.content, forType: .string)
                        copiedMessageID = node.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedMessageID == node.id { copiedMessageID = nil }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedMessageID == node.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5))
                            Text(copiedMessageID == node.id ? "Copied" : "Copy")
                                .font(typo.sans(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(tokens.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Button {
                        editMessageDraft = node.content
                        clearThinkingOnAssistantEdit = false
                        isEditBoxExpandedFull = false
                        editingMessageNodeID = node.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10.5))
                            Text("Edit")
                                .font(typo.sans(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(tokens.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(node.role == .user ? "Edit prompt and branch" : "Edit or trim AI reply in-place to reduce KV cache tokens")

                    if node.role == .assistant {
                        Button {
                            store.regenerateAssistantBranch(forAssistantNodeID: node.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10.5))
                                Text("Regenerate")
                                    .font(typo.sans(size: 11.5, weight: .medium))
                            }
                            .foregroundColor(tokens.secondaryText)
                        }
                        .buttonStyle(.plain)

                        if node.wasStoppedMidStream && isLatestTurn {
                            Button {
                                store.continueStoppedGeneration(forAssistantNodeID: node.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 9.5))
                                    Text("Continue")
                                        .font(typo.sans(size: 11.5, weight: .semibold))
                                }
                                .foregroundColor(tokens.accentForeground)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tokens.accentAction))
                            }
                            .buttonStyle(.plain)
                            .help("Resume generation from where it was stopped")
                        }
                    }

                    Button {
                        store.branchMessageToNewChat(upToNodeID: node.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10.5))
                            Text("Branch to Chat")
                                .font(typo.sans(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(tokens.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Fork conversation up to this message into a new chat prefixed with 'Branch · '")

                    Button {
                        confirmingDeleteNodeID = node.id
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Delete")
                                .font(typo.sans(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(tokens.mutedText)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this message from context to reclaim ~\(node.estimatedTokenFootprint) tok of KV RAM")
                }

                Spacer()

                // Every turn shows its own token count; the latest turn in the chat (whether completed or stopped midway) always shows `Chat Total`!
                let turnTok = max(node.estimatedTokenFootprint, node.metrics?.totalTokens ?? 0)
                let tps = node.metrics?.tokensPerSecond ?? 0.0

                if node.role == .user {
                    if isLatestTurn {
                        Text("~\(turnTok) tok · Chat Total: \(session.estimatedActiveTokens) tok")
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    } else {
                        Text("~\(turnTok) tok")
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    }
                } else if isLatestTurn {
                    if tps > 0 {
                        Text(String(format: "%.1f tok/s · %d tok · Chat Total: %d tok", tps, turnTok, session.estimatedActiveTokens))
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    } else {
                        Text("~\(turnTok) tok · Chat Total: \(session.estimatedActiveTokens) tok")
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    }
                } else {
                    if tps > 0 {
                        Text(String(format: "%.1f tok/s · %d tok", tps, turnTok))
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    } else {
                        Text("~\(turnTok) tok")
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(tokens.mutedText)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Squared-Off Architectural Thinking Instrument (`cornerRadius: 5` + Markdown Bold/LaTeX Parsing)
    @ViewBuilder
    private func thinkingDisclosureView(
        for node: ConversationMessageNode,
        isStreaming: Bool,
        opticalFontSize: CGFloat
    ) -> some View {
        let relativeThinkingFontSize = max(10.5, opticalFontSize - 2.4)
        let headerFontSize = max(10.5, opticalFontSize - 3.0)
        let wordCount = max(1, node.thinkingTrace.split { $0.isWhitespace || $0.isNewline }.count)
        let isActivelyThinking = !node.isThinkingComplete && isStreaming

        VStack(alignment: .leading, spacing: 5) {
            Button {
                guard let sIdx = store.sessions.firstIndex(where: { $0.id == store.selectedSessionID }),
                      var target = store.sessions[sIdx].nodes[node.id] else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    target.isThinkingExpanded.toggle()
                    store.sessions[sIdx].nodes[node.id] = target
                }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isActivelyThinking ? tokens.accentAction : tokens.thinkingText.opacity(0.60))
                        .frame(width: 6, height: 6)

                    Text(node.wasStoppedMidThinking ? "Thought Process · Stopped" : (isActivelyThinking ? "Thinking Live" : "Thought Process"))
                        .font(typo.sans(size: headerFontSize, weight: .semibold))
                        .foregroundColor(tokens.thinkingText)

                    Text(node.isThinkingComplete
                         ? String(format: "%.1fs", node.metrics?.thinkingDurationSec ?? 0.0)
                         : String(format: "%.1fs…", store.liveElapsedSeconds))
                        .font(typo.sans(size: headerFontSize, weight: .medium).monospacedDigit())
                        .foregroundColor(tokens.thinkingText.opacity(0.75))

                    if !node.thinkingTrace.isEmpty {
                        Text("· \(wordCount) \(wordCount == 1 ? "word" : "words")")
                            .font(typo.sans(size: headerFontSize, weight: .regular).monospacedDigit())
                            .foregroundColor(tokens.thinkingText.opacity(0.70))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(tokens.thinkingText.opacity(0.75))
                        .rotationEffect(.degrees(node.isThinkingExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(tokens.thinkingSurface)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(tokens.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if node.isThinkingExpanded {
                StreamSafeMarkdownView(
                    rawMarkdown: node.thinkingTrace.isEmpty ? "Reasoning…" : node.thinkingTrace,
                    isStreaming: isActivelyThinking,
                    effectiveFontSize: relativeThinkingFontSize,
                    tokens: tokens,
                    typo: typo,
                    useMonospaceBody: true,
                    overrideTextColor: tokens.thinkingText,
                    onOpenCodeInInspector: { _, _ in
                        store.userManuallyClosedRightPaneInWideMode = false
                        store.isRightUtilityPaneOpen = true
                    }
                )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tokens.thinkingSurface)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(tokens.hairline, lineWidth: 1)
                )
            }
        }
        .padding(.bottom, 2)
    }
}
EOF
