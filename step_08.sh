set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Engine/WorkstationStore.swift
import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
public final class WorkstationStore: ObservableObject {
    // MARK: - Persisted Appearance, Custom Palettes, Per-Model Saved Parameters & Shortcuts
    @Published public var activeTheme: AppThemeID {
        didSet { UserDefaults.standard.set(activeTheme.rawValue, forKey: "MotifActiveThemeV8") }
    }
    @Published public var customPalettes: CustomStudioPalettes {
        didSet {
            MotifTokens.customPalettes = customPalettes
            if let data = try? JSONEncoder().encode(customPalettes) {
                UserDefaults.standard.set(data, forKey: "MotifCustomPalettesV11")
            }
        }
    }
    @Published public var perModelSavedParameters: [String: ModelRuntimeParameters] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(perModelSavedParameters) {
                UserDefaults.standard.set(data, forKey: "MotifPerModelParamsV12")
            }
        }
    }
    @Published public var typography: TypographyConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(typography) {
                UserDefaults.standard.set(data, forKey: "MotifTypographyConfigV8")
            }
        }
    }
    @Published public var shortcuts: ShortcutConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                UserDefaults.standard.set(data, forKey: "MotifShortcutsConfigV8")
            }
        }
    }
    @Published public var sidebarWidth: CGFloat = MotifTokens.sidebarDefaultWidth
    @Published public var isSidebarVisible: Bool = true
    @Published public var isWindowFullscreen: Bool = false

    // MARK: - Popover, Sheet & Composer Canvas States
    @Published public var isRightUtilityPaneOpen: Bool = false
    @Published public var userManuallyClosedRightPaneInWideMode: Bool = false
    @Published public var isModelPickerPopoverPresented: Bool = false
    @Published public var isMemoryDetailPopoverPresented: Bool = false
    @Published public var isParameterPopoverPresented: Bool = false
    @Published public var isSettingsModalPresented: Bool = false
    @Published public var settingsRequestedTab: String? = nil
    @Published public var isNewWorkspaceSheetPresented: Bool = false
    @Published public var isNewPresetSheetPresented: Bool = false
    @Published public var isTrashExpanded: Bool = false
    @Published public var isComposerCanvasExpanded: Bool = false
    @Published public var isContextCeilingBannerDismissed: Bool = false
    @Published public var selectedArtifactID: UUID? = nil
    @Published public var pendingScrollToMessageID: UUID? = nil

    // MARK: - Sidebar Search (FTS5), Sessions & Slash Personas
    @Published public var sidebarSearchQuery: String = ""
    @Published public var ftsSearchResults: [FTSSearchHit] = []
    @Published public var sessions: [ConversationSession] = []
    @Published public var folders: [ProjectFolder] = []
    @Published public var presets: [ParameterPreset] = ParameterPreset.defaults
    @Published public var slashPersonas: [SlashPersona] = SlashPersona.defaults
    @Published public var slashMenuHighlightedIndex: Int = 0
    @Published public var isSlashMenuDismissedForCurrentToken: Bool = false
    @Published public var selectedSessionID: UUID? = nil {
        willSet {
            saveCurrentDraftToActiveSession()
        }
        didSet {
            let prevID = oldValue
            if let id = selectedSessionID {
                UserDefaults.standard.set(id.uuidString, forKey: "MotifSelectedSessionIDV8")
            } else {
                UserDefaults.standard.removeObject(forKey: "MotifSelectedSessionIDV8")
            }
            restoreDraftFromSelectedSession()
            isScrolledAwayFromBottom = false
            isAutoScrollPaused = false
            isComposerCanvasExpanded = false
            isContextCeilingBannerDismissed = false
            handleSessionSwitchKVCacheAdjustment(fromSessionID: prevID, toSessionID: selectedSessionID)
        }
    }

    // MARK: - Composer, Separated Scroll States & Stop-Safe Streaming State
    @Published public var composerDraft: String = ""
    @Published public var pendingAttachments: [MessageAttachment] = []
    @Published public var isStreamingGeneration: Bool = false
    @Published public var streamingSessionID: UUID? = nil
    @Published public var streamingNodeID: UUID? = nil
    @Published public var liveTokensPerSec: Double = 0.0
    @Published public var liveTotalTokens: Int = 0
    @Published public var liveElapsedSeconds: Double = 0.0
    @Published public var streamScrollPulse: Int = 0
    /// True only when user has scrolled > 520pt (~20 lines) above the bottom spacer (controls Jump to Latest button)
    @Published public var isScrolledAwayFromBottom: Bool = false
    /// True when user nudges trackpad upward during streaming so auto-scroll immediately stops fighting them
    @Published public var isAutoScrollPaused: Bool = false
    @Published public var humanReadableErrorBanner: String? = nil
    @Published public var kernelMemoryPressureWarning: String? = nil

    // MARK: - Real Models, True Kernel RSS Load Progress & Classy Completion Rim Flicker
    @Published public var availableModels: [LocalModelDescriptor] = []
    @Published public var liveOllamaResidentBytes: Int64 = 0
    @Published public var baselineOllamaRSSBeforeLoad: Int64 = 0
    @Published public var baselineRAMBytesBeforeLoad: Int64 = 0
    @Published public var targetLoadingModelBytes: Int64 = 0
    @Published public var memorySnapshot: UnifiedMemorySnapshot
    @Published public var isLoadingModelWeights: Bool = false
    @Published public var loadingModelName: String = ""
    @Published public var loadingModelInternalID: String = ""
    @Published public var isConfirmingModelLoadCancel: Bool = false
    @Published public var modelLoadCompletionRimFlashOpacity: Double = 0.0
    @Published public var pendingSSDSwapWarningModel: LocalModelDescriptor? = nil
    @Published public var downloadTasks: [RegistryDownloadTask] = []

    // MARK: - Mutable Sub-Services
    @Published public var supervisor = LocalEngineSupervisor()
    @Published public var driveManager = ExternalStorageDriveManager()

    private let vault = PersistenceVaultManager()
    private var streamingTask: Task<Void, Never>? = nil
    private var modelLoadTask: Task<Void, Never>? = nil
    private var downloadTaskHandles: [UUID: Task<Void, Never>] = [:]
    private var activeStreamParser: StatefulThinkingStreamParser? = nil
    private var telemetryTimer: Timer? = nil
    private var scrollWheelMonitor: Any? = nil
    private var memoryPressureSource: DispatchSourceMemoryPressure? = nil
    private var windowFullscreenObservers: [NSObjectProtocol] = []
    private var searchCancellable: AnyCancellable? = nil
    private var lastStreamUIUpdateTime: Date = .distantPast
    private var idleTickCounter: Int = 0

    public init() {
        let savedThemeRaw = UserDefaults.standard.string(forKey: "MotifActiveThemeV8") ?? AppThemeID.alabasterStudio.rawValue
        self.activeTheme = AppThemeID(rawValue: savedThemeRaw) ?? .alabasterStudio

        if let palData = UserDefaults.standard.data(forKey: "MotifCustomPalettesV11"),
           let decodedPal = try? JSONDecoder().decode(CustomStudioPalettes.self, from: palData) {
            self.customPalettes = decodedPal
            MotifTokens.customPalettes = decodedPal
        } else {
            let def = CustomStudioPalettes()
            self.customPalettes = def
            MotifTokens.customPalettes = def
        }

        if let pmData = UserDefaults.standard.data(forKey: "MotifPerModelParamsV12"),
           let decodedPM = try? JSONDecoder().decode([String: ModelRuntimeParameters].self, from: pmData) {
            self.perModelSavedParameters = decodedPM
        }

        if let typoData = UserDefaults.standard.data(forKey: "MotifTypographyConfigV8"),
           let decodedTypo = try? JSONDecoder().decode(TypographyConfiguration.self, from: typoData) {
            self.typography = decodedTypo
        } else {
            self.typography = TypographyConfiguration()
        }

        if let shortData = UserDefaults.standard.data(forKey: "MotifShortcutsConfigV8"),
           let decodedShort = try? JSONDecoder().decode(ShortcutConfiguration.self, from: shortData) {
            self.shortcuts = decodedShort
        } else {
            self.shortcuts = ShortcutConfiguration()
        }

        let initialSnap = HardwareMemoryEngine.queryAppleSiliconMemory(
            liveOllamaVRAMBytes: 0,
            estimatedKVCacheBytes: 0,
            baselineRAMBytesBeforeLoad: 0,
            targetModelSizeBytes: 0,
            previousHistory: []
        )
        self.memorySnapshot = initialSnap
        self.baselineRAMBytesBeforeLoad = initialSnap.totalSystemUsedBytes

        loadSavedSessionsAndWorkspaces()
        setupFTS5SearchDebounce()
        installNativeTrackpadScrollMonitor()
        installKernelMemoryPressureMonitor()
        observeWindowFullscreenTransitions()
        startLiveTelemetryLoop()

        Task {
            await bootstrapLocalOllamaConnection()
        }
    }

    public func resetCustomPalette(for theme: AppThemeID) {
        switch theme {
        case .alabasterStudio:
            customPalettes.alabaster = .alabasterDefault
        case .warmEditorial:
            customPalettes.warmEditorial = .warmEditorialDefault
        default:
            break
        }
    }

    /// Persists the active session's parameters for its selected model so new chats with this model remember Thinking Mode, Context, etc.
    public func recordActiveModelParameterPreference() {
        guard let session = activeSession, !session.selectedModelName.isEmpty else { return }
        perModelSavedParameters[session.selectedModelName] = session.parameters
        saveAllState()
    }

    /// Returns the user's last-used parameters for a given model (or `.balanced` with valid thinking mode if never customized)
    public func preferredParameters(forModelName modelName: String) -> ModelRuntimeParameters {
        var params = perModelSavedParameters[modelName] ?? .balanced
        params.kvCacheQuant = supervisor.kvCacheTypeEnv
        if let desc = availableModels.first(where: { $0.name == modelName }) {
            let valid = desc.thinkingProfile.validOptions
            if !valid.contains(params.thinkingMode) {
                params.thinkingMode = valid.last ?? .forceNoThink
            }
        }
        return params
    }

    /// If switching from a chat that had an oversized KV context allocation (e.g. 32k) to a chat with a smaller context (e.g. 4k/8k),
    /// re-binds the resident model's context size in the background so excess KV cache RAM is released back to macOS.
    private func handleSessionSwitchKVCacheAdjustment(fromSessionID: UUID?, toSessionID: UUID?) {
        guard !isStreamingGeneration, !isLoadingModelWeights,
              let fromID = fromSessionID, let toID = toSessionID, fromID != toID,
              let prevSession = sessions.first(where: { $0.id == fromID }),
              let nextSession = sessions.first(where: { $0.id == toID }),
              !prevSession.activeBranchThread.isEmpty,
              prevSession.parameters.numCtx > nextSession.parameters.numCtx,
              let model = availableModels.first(where: { $0.name == nextSession.selectedModelName && $0.residency == .activeInUnifiedRAM }) else {
            return
        }
        Task {
            await rebindModelContextSizeQuietly(modelName: model.name, parameters: nextSession.parameters)
        }
    }

    /// Resets/clears the active KV cache buffer in RAM to match the current session's `num_ctx` without unloading model weights
    public func clearActiveKVCacheInRAM() {
        guard let model = activeModelDescriptor, model.residency == .activeInUnifiedRAM else { return }
        let params = activeSession?.parameters ?? .balanced
        Task {
            await rebindModelContextSizeQuietly(modelName: model.name, parameters: params)
            await pollOllamaRunningProcesses()
            recalculateHardwareTelemetry()
        }
    }

    private func rebindModelContextSizeQuietly(modelName: String, parameters: ModelRuntimeParameters) async {
        guard let url = URL(string: "\(supervisor.normalizedEndpoint)/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30.0
        var opts: [String: Any] = [
            "num_ctx": parameters.numCtx,
            "num_batch": parameters.numBatch,
            "use_mmap": parameters.useMmap,
            "use_mlock": parameters.useMlock
        ]
        if parameters.numThread > 0 { opts["num_thread"] = parameters.numThread }
        if parameters.numGpu >= 0 { opts["num_gpu"] = parameters.numGpu }
        let payload: [String: Any] = [
            "model": modelName,
            "messages": [],
            "keep_alive": "\(parameters.keepAliveMinutes)m",
            "options": opts
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }

    public func triggerModelLoadCompletionFlicker() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.09)) {
                self.modelLoadCompletionRimFlashOpacity = 1.0
            }
            try? await Task.sleep(nanoseconds: 105_000_000)
            withAnimation(.easeInOut(duration: 0.08)) {
                self.modelLoadCompletionRimFlashOpacity = 0.22
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
            withAnimation(.easeOut(duration: 0.10)) {
                self.modelLoadCompletionRimFlashOpacity = 0.96
            }
            try? await Task.sleep(nanoseconds: 130_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                self.modelLoadCompletionRimFlashOpacity = 0.0
            }
        }
    }

    private func installKernelMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            Task { @MainActor in
                if event.contains(.critical) || event.contains(.warning) {
                    self.kernelMemoryPressureWarning = "macOS memory pressure is high (\(String(format: "%.1f GB free", self.memorySnapshot.headroomGB)))."
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func observeWindowFullscreenTransitions() {
        let enterObs = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isWindowFullscreen = true
                self?.isScrolledAwayFromBottom = false
            }
        }
        let exitObs = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isWindowFullscreen = false
                self?.isScrolledAwayFromBottom = false
            }
        }
        let minObs = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.supervisor.autoUnloadOnMinimize, !self.isStreamingGeneration else { return }
                for model in self.availableModels where model.residency == .activeInUnifiedRAM {
                    await self.unloadModelFromMemory(model)
                }
            }
        }
        windowFullscreenObservers = [enterObs, exitObs, minObs]
    }

    private func setupFTS5SearchDebounce() {
        searchCancellable = $sidebarSearchQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 {
                    self.ftsSearchResults = self.vault.searchMessagesFTS5(query: trimmed)
                } else {
                    self.ftsSearchResults = []
                }
            }
    }

    private func installNativeTrackpadScrollMonitor() {
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            // Pause auto-scroll immediately if the user scrolls up while generating, without prematurely popping up the Jump button!
            if event.scrollingDeltaY > 1.5 {
                Task { @MainActor in
                    if self.isStreamingGeneration && !self.isAutoScrollPaused {
                        self.isAutoScrollPaused = true
                    }
                }
            }
            return event
        }
    }

    /// Registered on `RunLoop.main` in `.common` mode so the RAM popover refreshes live while open!
    /// Polls at 0.30s when loading or when the RAM menu is open, and throttles to ~1.5s when idle.
    private func startLiveTelemetryLoop() {
        let timer = Timer(timeInterval: 0.30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let highFrequencyNeeded = self.isLoadingModelWeights || self.isMemoryDetailPopoverPresented || self.isStreamingGeneration
                self.idleTickCounter &+= 1
                if highFrequencyNeeded || (self.idleTickCounter % 5 == 0) {
                    await self.pollOllamaRunningProcesses()
                    self.recalculateHardwareTelemetry()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        telemetryTimer = timer
    }

    public var activeSession: ConversationSession? {
        guard !sessions.isEmpty, let id = selectedSessionID else { return nil }
        return sessions.first(where: { $0.id == id && !$0.isTrashed })
    }

    public var activeModelDescriptor: LocalModelDescriptor? {
        if let sessionModel = activeSession?.selectedModelName,
           !sessionModel.isEmpty,
           let matched = availableModels.first(where: { $0.name == sessionModel }) {
            return matched
        }
        return availableModels.first
    }

    public var estimatedKVCacheBytes: Int64 {
        let model = activeModelDescriptor
        let params = activeSession?.parameters ?? .balanced
        let layers = Double(model?.numLayers ?? 32)
        let kvHeads = Double(model?.numKVHeads ?? 8)
        let headDim = Double(model?.headDim ?? 128)
        let parallelMultiplier = Double(max(1, supervisor.parallelRequestSlots))
        let perToken = 2.0 * layers * kvHeads * headDim * params.kvCacheQuant.bytesPerElement * parallelMultiplier
        return Int64(perToken * Double(params.numCtx))
    }

    public var matchedSlashPersonas: [SlashPersona] {
        guard !isSlashMenuDismissedForCurrentToken else { return [] }
        let trimmed = composerDraft.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let tokens = firstLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let firstToken = tokens.first?.lowercased(), tokens.count <= 2 else { return [] }
        if firstToken == "/" { return slashPersonas }
        return slashPersonas.filter {
            $0.trigger.lowercased().hasPrefix(firstToken) || $0.title.lowercased().contains(firstToken.dropFirst())
        }
    }

    public func moveSlashSelection(delta: Int) {
        let list = matchedSlashPersonas
        guard !list.isEmpty else { return }
        slashMenuHighlightedIndex = (slashMenuHighlightedIndex + delta + list.count) % list.count
    }

    public func applyHighlightedSlashPersona() -> Bool {
        let list = matchedSlashPersonas
        guard !list.isEmpty else { return false }
        let clamped = min(max(0, slashMenuHighlightedIndex), list.count - 1)
        applySlashPersona(list[clamped])
        return true
    }

    public func applySlashPersona(_ persona: SlashPersona) {
        guard let idx = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        sessions[idx].systemPrompt = persona.systemPrompt
        sessions[idx].activePersonaTrigger = persona.trigger

        let trimmed = composerDraft.trimmingCharacters(in: .whitespaces)
        if let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) {
            let remainder = String(trimmed[firstSpace...]).trimmingCharacters(in: .whitespaces)
            composerDraft = remainder
        } else {
            composerDraft = ""
        }
        sessions[idx].draftText = composerDraft
        slashMenuHighlightedIndex = 0
        isSlashMenuDismissedForCurrentToken = false
        saveAllState()
    }

    // MARK: - Ollama Discovery (`/api/tags`), External Drive Self-Healing & Live Residency (`/api/ps`)
    public func bootstrapLocalOllamaConnection() async {
        driveManager.syncLaunchctlEnvironment()
        let extPath = driveManager.resolvedModelsPath

        await refreshLocalEngineModels()

        if !supervisor.isEngineOnline {
            supervisor.launchManagedDaemonIfNeeded(externalModelsDir: extPath)
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await refreshLocalEngineModels()
                if supervisor.isEngineOnline { break }
            }
        }

        if supervisor.isEngineOnline && availableModels.isEmpty && driveManager.hasModelsOnDisk {
            await supervisor.restartAndRebindToExternalDrive(modelsPath: extPath)
            await refreshLocalEngineModels()
        }

        await pollOllamaRunningProcesses()
        recalculateHardwareTelemetry()
    }

    public func selectExternalDriveAndReloadModels() {
        if driveManager.selectExternalDriveDirectory() {
            let newPath = driveManager.resolvedModelsPath
            Task {
                await supervisor.restartAndRebindToExternalDrive(modelsPath: newPath)
                await refreshLocalEngineModels()
                await pollOllamaRunningProcesses()
                recalculateHardwareTelemetry()
            }
        }
    }

    public func applyDaemonConfigurationAndRestart() {
        if downloadTasks.contains(where: { !$0.isCompleted }) {
            humanReadableErrorBanner = "Wait for the active model download to finish before restarting the Ollama daemon."
            return
        }
        let extPath = driveManager.resolvedModelsPath
        let modelToReload = availableModels.first(where: { $0.residency == .activeInUnifiedRAM })
        Task {
            await supervisor.restartAndRebindToExternalDrive(modelsPath: extPath)
            await refreshLocalEngineModels()
            if let model = modelToReload {
                await loadModelWithLiveRAMDelta(model)
            } else {
                await pollOllamaRunningProcesses()
                recalculateHardwareTelemetry()
            }
        }
    }

    public func applyKVCacheQuantizationLive(_ newQuant: KVCacheQuantization) {
        guard supervisor.kvCacheTypeEnv != newQuant else {
            recalculateHardwareTelemetry()
            return
        }
        supervisor.kvCacheTypeEnv = newQuant
        if newQuant != .f16 {
            supervisor.enableFlashAttentionEnv = true
        }
        recordActiveModelParameterPreference()
        recalculateHardwareTelemetry()
        applyDaemonConfigurationAndRestart()
    }

    public func applyTightRAMOptimization(andLoadModel targetModel: LocalModelDescriptor? = nil) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        let model = targetModel ?? activeModelDescriptor

        var safeGPULayers = -1
        if let m = model {
            let totalLayers = max(1, m.numLayers)
            let safeBudgetBytes = max(memorySnapshot.freeHeadroomBytes + liveOllamaResidentBytes - 750_000_000, memorySnapshot.metalRecommendedMaxBytes - 1_073_741_824)
            if m.sizeBytes > safeBudgetBytes && m.sizeBytes > 0 {
                let ratio = max(0.25, min(0.95, Double(safeBudgetBytes) / Double(m.sizeBytes)))
                safeGPULayers = max(4, Int(Double(totalLayers) * ratio))
            }
        }

        sessions[sIdx].parameters.tightRAMModeEnabled = true
        sessions[sIdx].parameters.kvCacheQuant = .q4_0
        sessions[sIdx].parameters.numCtx = min(sessions[sIdx].parameters.numCtx, 4096)
        sessions[sIdx].parameters.numBatch = 128
        sessions[sIdx].parameters.numKeep = 128
        sessions[sIdx].parameters.numGpu = safeGPULayers
        sessions[sIdx].parameters.numThread = 0
        sessions[sIdx].parameters.useMmap = true
        sessions[sIdx].parameters.useMlock = false
        sessions[sIdx].parameters.keepAliveMinutes = 5
        if let m = model {
            sessions[sIdx].selectedModelName = m.name
            perModelSavedParameters[m.name] = sessions[sIdx].parameters
        }
        saveAllState()

        let needsDaemonRestart = supervisor.kvCacheTypeEnv != .q4_0 || !supervisor.enableFlashAttentionEnv || supervisor.parallelRequestSlots != 1
        supervisor.kvCacheTypeEnv = .q4_0
        supervisor.enableFlashAttentionEnv = true
        supervisor.parallelRequestSlots = 1
        supervisor.maxLoadedModels = 1
        kernelMemoryPressureWarning = nil

        Task {
            if needsDaemonRestart {
                await supervisor.restartAndRebindToExternalDrive(modelsPath: driveManager.resolvedModelsPath)
                await refreshLocalEngineModels()
            }
            if let m = model {
                await loadModelWithLiveRAMDelta(m)
            } else {
                recalculateHardwareTelemetry()
            }
        }
    }

    public func refreshLocalEngineModels() async {
        guard let url = URL(string: "\(supervisor.normalizedEndpoint)/api/tags") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArr = json["models"] as? [[String: Any]] else { return }

            supervisor.isEngineOnline = true
            supervisor.supervisorStatusLog = "Connected to local Ollama (\(modelsArr.count) \(modelsArr.count == 1 ? "model" : "models") available)."

            var parsed: [LocalModelDescriptor] = []
            for item in modelsArr {
                let name = (item["name"] as? String) ?? ""
                guard !name.isEmpty else { continue }
                let size = (item["size"] as? Int64) ?? 0
                let details = item["details"] as? [String: Any]
                let family = (details?["family"] as? String) ?? "model"
                let paramSize = (details?["parameter_size"] as? String) ?? ""
                let quant = (details?["quantization_level"] as? String) ?? ""

                let existing = availableModels.first(where: { $0.name == name })
                let descriptor = LocalModelDescriptor(
                    name: name,
                    displayName: LocalModelDescriptor.shortenModelName(name),
                    family: family,
                    parameterSize: paramSize,
                    quantizationLevel: quant,
                    sizeBytes: size,
                    digest: (item["digest"] as? String) ?? "",
                    modifiedAt: Date(),
                    residency: existing?.residency ?? .dormantOnDisk,
                    vramAllocatedBytes: existing?.vramAllocatedBytes ?? 0,
                    numLayers: existing?.numLayers ?? 32,
                    numKVHeads: existing?.numKVHeads ?? 8,
                    headDim: existing?.headDim ?? 128,
                    maxContextLength: existing?.maxContextLength ?? 32768,
                    thinkingProfile: existing?.thinkingProfile ?? Self.heuristicThinkingProfile(forModelName: name),
                    hasIntrospectedShowMetadata: existing?.hasIntrospectedShowMetadata ?? false
                )
                parsed.append(descriptor)
            }

            self.availableModels = parsed

            if let firstModel = parsed.first {
                for idx in sessions.indices {
                    if sessions[idx].selectedModelName.isEmpty || !parsed.contains(where: { $0.name == sessions[idx].selectedModelName }) {
                        sessions[idx].selectedModelName = firstModel.name
                        if sessions[idx].activeBranchThread.isEmpty {
                            sessions[idx].parameters = preferredParameters(forModelName: firstModel.name)
                        }
                    }
                }
            }

            for model in parsed where !model.hasIntrospectedShowMetadata {
                await introspectModelCapabilitiesViaShowAPI(modelName: model.name)
            }
        } catch {
            supervisor.isEngineOnline = false
            supervisor.supervisorStatusLog = "Ollama daemon offline at \(supervisor.normalizedEndpoint)."
        }
    }

    public func introspectModelCapabilitiesViaShowAPI(modelName: String) async {
        guard let url = URL(string: "\(supervisor.normalizedEndpoint)/api/show") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 4.0
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": modelName])

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let template = (json["template"] as? String) ?? ""
        let capabilities = (json["capabilities"] as? [String]) ?? []
        let modelInfo = (json["model_info"] as? [String: Any]) ?? [:]

        var profile = Self.heuristicThinkingProfile(forModelName: modelName)
        let hasThinkingCap = capabilities.contains("thinking")
        let templateHasThinkVar = template.contains(".Thinking") || template.contains("<think>") || template.contains("<|thought|>")
        let templateHasSlashNoThink = template.contains("/no_think") || template.contains("/think")
        let templateHasEffort = template.contains("reasoning_effort") || template.contains("thinking_effort") || (template.contains("\"low\"") && template.contains("\"high\""))

        var detectedTokensList: [String] = []
        if hasThinkingCap { detectedTokensList.append("capabilities: [thinking]") }
        if template.contains(".Thinking") { detectedTokensList.append("{{ .Thinking }}") }
        if template.contains("<think>") { detectedTokensList.append("<think>…</think>") }
        if template.contains("<|thought|>") { detectedTokensList.append("<|thought|>") }
        if templateHasSlashNoThink { detectedTokensList.append("/think · /no_think") }
        if templateHasEffort { detectedTokensList.append("effort: low · medium · high") }
        let tokenReport = detectedTokensList.isEmpty ? "None in template" : detectedTokensList.joined(separator: " | ")

        if templateHasEffort {
            profile = ModelThinkingProfile(
                kind: .effortTiered,
                supportsSlashDirectives: templateHasSlashNoThink,
                supportsNativeThinkFlag: true,
                supportsEffortLevels: true,
                detectedMechanismSummary: "Template supports multi-level reasoning effort",
                detectedTemplateTokens: tokenReport
            )
        } else if templateHasSlashNoThink {
            profile = ModelThinkingProfile(
                kind: .toggleable,
                supportsSlashDirectives: true,
                supportsNativeThinkFlag: hasThinkingCap || templateHasThinkVar,
                supportsEffortLevels: false,
                detectedMechanismSummary: "Template supports binary thinking toggle",
                detectedTemplateTokens: tokenReport
            )
        } else if hasThinkingCap || templateHasThinkVar {
            profile = ModelThinkingProfile(
                kind: .toggleable,
                supportsSlashDirectives: false,
                supportsNativeThinkFlag: true,
                supportsEffortLevels: false,
                detectedMechanismSummary: "Supports native Ollama thinking channel",
                detectedTemplateTokens: tokenReport
            )
        }

        var detectedLayers = 32
        var detectedKVHeads = 8
        var detectedCtx = 32768
        for (key, val) in modelInfo {
            let intVal = (val as? Int) ?? (val as? NSNumber)?.intValue
            guard let v = intVal, v > 0 else { continue }
            if key.hasSuffix(".block_count") {
                detectedLayers = v
            } else if key.hasSuffix(".attention.head_count_kv") {
                detectedKVHeads = v
            } else if key.hasSuffix(".context_length") {
                detectedCtx = v
            }
        }

        if let idx = availableModels.firstIndex(where: { $0.name == modelName }) {
            availableModels[idx].thinkingProfile = profile
            availableModels[idx].numLayers = detectedLayers
            availableModels[idx].numKVHeads = detectedKVHeads
            availableModels[idx].maxContextLength = detectedCtx
            availableModels[idx].hasIntrospectedShowMetadata = true

            for sIdx in sessions.indices where sessions[sIdx].selectedModelName == modelName {
                let valid = profile.validOptions
                if let savedPref = perModelSavedParameters[modelName], valid.contains(savedPref.thinkingMode) {
                    if sessions[sIdx].activeBranchThread.isEmpty {
                        sessions[sIdx].parameters = savedPref
                    }
                } else if !valid.contains(sessions[sIdx].parameters.thinkingMode) {
                    sessions[sIdx].parameters.thinkingMode = valid.last ?? .forceNoThink
                }
            }
        }
    }

    private static func heuristicThinkingProfile(forModelName name: String) -> ModelThinkingProfile {
        let lower = name.lowercased()
        if lower.contains("gpt-oss") || lower.contains("o1") || lower.contains("o3") {
            return ModelThinkingProfile(
                kind: .effortTiered,
                supportsSlashDirectives: false,
                supportsNativeThinkFlag: true,
                supportsEffortLevels: true,
                detectedMechanismSummary: "Supports Off / Low / Med / High reasoning effort",
                detectedTemplateTokens: "effort: low · medium · high"
            )
        } else if lower.contains("qwen3") || lower.contains("cogito") || lower.contains("hermes") {
            return ModelThinkingProfile(
                kind: .toggleable,
                supportsSlashDirectives: true,
                supportsNativeThinkFlag: true,
                supportsEffortLevels: false,
                detectedMechanismSummary: "Supports Off / On thinking toggle",
                detectedTemplateTokens: "/think · /no_think · <think>"
            )
        } else if lower.contains("r1") || lower.contains("qwq") || lower.contains("gemma4") || lower.contains("gemma-4") || lower.contains("think") || lower.contains("reasoning") {
            return ModelThinkingProfile(
                kind: .toggleable,
                supportsSlashDirectives: false,
                supportsNativeThinkFlag: true,
                supportsEffortLevels: false,
                detectedMechanismSummary: "Supports native deliberation",
                detectedTemplateTokens: "capabilities: [thinking]"
            )
        }
        return ModelThinkingProfile(
            kind: .unsupported,
            supportsSlashDirectives: false,
            supportsNativeThinkFlag: false,
            supportsEffortLevels: false,
            detectedMechanismSummary: "Standard non-reasoning model",
            detectedTemplateTokens: "None"
        )
    }

    public func pollOllamaRunningProcesses() async {
        guard let url = URL(string: "\(supervisor.normalizedEndpoint)/api/ps") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runningArr = json["models"] as? [[String: Any]] else { return }

            supervisor.isEngineOnline = true
            var totalVRAM: Int64 = 0
            var residentMap: [String: Int64] = [:]

            for item in runningArr {
                let name = (item["name"] as? String) ?? ""
                let sizeVRAM = (item["size_vram"] as? Int64) ?? (item["size"] as? Int64) ?? 0
                if !name.isEmpty {
                    residentMap[name] = sizeVRAM
                    totalVRAM += sizeVRAM
                }
            }

            for idx in availableModels.indices {
                let modelName = availableModels[idx].name
                if let vram = residentMap[modelName] {
                    availableModels[idx].residency = .activeInUnifiedRAM
                    availableModels[idx].vramAllocatedBytes = vram
                } else if isLoadingModelWeights && loadingModelInternalID == modelName {
                    availableModels[idx].residency = .loadingIntoMemory
                } else {
                    availableModels[idx].residency = .dormantOnDisk
                    availableModels[idx].vramAllocatedBytes = 0
                }
            }

            self.liveOllamaResidentBytes = totalVRAM
        } catch {}
    }

    public func recalculateHardwareTelemetry() {
        let targetBytes = isLoadingModelWeights ? targetLoadingModelBytes : (activeModelDescriptor?.sizeBytes ?? 0)
        let isLoading = isLoadingModelWeights
        let reportedVRAM = liveOllamaResidentBytes
        let baseOllamaRSS = baselineOllamaRSSBeforeLoad
        let kvBytes = estimatedKVCacheBytes
        let baseBytes = baselineRAMBytesBeforeLoad
        let prevHist = memorySnapshot.historySamplesGB

        Task.detached(priority: .utility) {
            var snap = HardwareMemoryEngine.queryAppleSiliconMemory(
                liveOllamaVRAMBytes: reportedVRAM,
                estimatedKVCacheBytes: kvBytes,
                baselineRAMBytesBeforeLoad: baseBytes,
                targetModelSizeBytes: targetBytes,
                previousHistory: prevHist
            )
            if isLoading {
                let liveKernelRSS = HardwareMemoryEngine.queryOllamaProcessResidentBytes()
                let trueRunnerDeltaBytes = max(0, liveKernelRSS - baseOllamaRSS)
                snap.modelWeightsResidentBytes = max(reportedVRAM, trueRunnerDeltaBytes)
            }
            await MainActor.run { [weak self] in
                self?.memorySnapshot = snap
            }
        }
    }

    // MARK: - Model Selection & True Kernel RSS Loading with Matching `num_ctx` Warmup (Fixes Double-Load Bug!)
    public func selectAndLoadModel(_ targetModel: LocalModelDescriptor, bypassSwapGuard: Bool = false) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }

        let reclaimableBytes = liveOllamaResidentBytes
        let availableBeforeSwap = memorySnapshot.freeHeadroomBytes + reclaimableBytes
        if !bypassSwapGuard && targetModel.residency != .activeInUnifiedRAM && targetModel.sizeBytes > availableBeforeSwap {
            pendingSSDSwapWarningModel = targetModel
            return
        }

        pendingSSDSwapWarningModel = nil
        sessions[sIdx].selectedModelName = targetModel.name

        // Restore saved per-model parameters (Thinking Mode, Context Window, etc.) for this model!
        if let savedParams = perModelSavedParameters[targetModel.name] {
            var restored = savedParams
            restored.kvCacheQuant = supervisor.kvCacheTypeEnv
            let validModes = targetModel.thinkingProfile.validOptions
            if !validModes.contains(restored.thinkingMode) {
                restored.thinkingMode = validModes.last ?? .forceNoThink
            }
            sessions[sIdx].parameters = restored
        } else {
            let validModes = targetModel.thinkingProfile.validOptions
            if !validModes.contains(sessions[sIdx].parameters.thinkingMode) {
                sessions[sIdx].parameters.thinkingMode = validModes.last ?? .forceNoThink
            }
        }
        saveAllState()

        if targetModel.residency == .activeInUnifiedRAM {
            triggerModelLoadCompletionFlicker()
            return
        }

        modelLoadTask?.cancel()
        modelLoadTask = Task {
            await loadModelWithLiveRAMDelta(targetModel)
        }
    }

    public func requestCancelModelLoadConfirmation() {
        isConfirmingModelLoadCancel = true
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.isConfirmingModelLoadCancel {
                self.isConfirmingModelLoadCancel = false
            }
        }
    }

    public func confirmCancelModelLoad() {
        let internalName = loadingModelInternalID
        isConfirmingModelLoadCancel = false
        modelLoadTask?.cancel()
        modelLoadTask = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            isLoadingModelWeights = false
            loadingModelName = ""
            loadingModelInternalID = ""
        }

        if let mIdx = availableModels.firstIndex(where: { $0.name == internalName }) {
            availableModels[mIdx].residency = .dormantOnDisk
            availableModels[mIdx].vramAllocatedBytes = 0
        }

        Task {
            if !internalName.isEmpty, let url = URL(string: "\(supervisor.normalizedEndpoint)/api/generate") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.timeoutInterval = 15.0
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": internalName, "prompt": "", "keep_alive": 0])
                _ = try? await URLSession.shared.data(for: req)
            }
            await pollOllamaRunningProcesses()
            recalculateHardwareTelemetry()
        }
    }

    public func loadModelWithLiveRAMDelta(_ targetModel: LocalModelDescriptor) async {
        humanReadableErrorBanner = nil
        isConfirmingModelLoadCancel = false

        let otherResident = availableModels.filter { $0.residency == .activeInUnifiedRAM && $0.name != targetModel.name }
        for other in otherResident {
            await unloadModelFromMemory(other)
        }
        if !otherResident.isEmpty {
            try? await Task.sleep(nanoseconds: 350_000_000)
        }

        baselineOllamaRSSBeforeLoad = HardwareMemoryEngine.queryOllamaProcessResidentBytes()
        baselineRAMBytesBeforeLoad = memorySnapshot.totalSystemUsedBytes
        targetLoadingModelBytes = max(1, targetModel.sizeBytes)

        withAnimation(.easeInOut(duration: 0.25)) {
            isLoadingModelWeights = true
            loadingModelName = targetModel.shortDisplayName
            loadingModelInternalID = targetModel.name
        }

        if let mIdx = availableModels.firstIndex(where: { $0.name == targetModel.name }) {
            availableModels[mIdx].residency = .loadingIntoMemory
        }
        recalculateHardwareTelemetry()

        // Use `/api/chat` with `messages: []` and matching `num_ctx` options so Ollama allocates the exact KV buffer once and NEVER double-loads on Question #1!
        guard let url = URL(string: "\(supervisor.normalizedEndpoint)/api/chat") else {
            isLoadingModelWeights = false
            return
        }

        let sessionParams = activeSession?.parameters ?? preferredParameters(forModelName: targetModel.name)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300.0

        var warmupOptions: [String: Any] = [
            "num_ctx": sessionParams.numCtx,
            "num_batch": sessionParams.numBatch,
            "use_mmap": sessionParams.useMmap,
            "use_mlock": sessionParams.useMlock
        ]
        if sessionParams.numThread > 0 {
            warmupOptions["num_thread"] = sessionParams.numThread
        }
        if sessionParams.numGpu >= 0 {
            warmupOptions["num_gpu"] = sessionParams.numGpu
        }

        let payload: [String: Any] = [
            "model": targetModel.name,
            "messages": [],
            "keep_alive": "\(sessionParams.keepAliveMinutes)m",
            "options": warmupOptions
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        var loadSucceeded = false
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard !Task.isCancelled else { return }
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                loadSucceeded = true
                await pollOllamaRunningProcesses()
                recalculateHardwareTelemetry()
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            } else {
                humanReadableErrorBanner = "Could not load “\(targetModel.shortDisplayName)”. Check that Ollama is running."
            }
        } catch {
            if !Task.isCancelled {
                humanReadableErrorBanner = "Failed to load “\(targetModel.shortDisplayName)”: \(error.localizedDescription)"
            }
        }

        if !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.30)) {
                isLoadingModelWeights = false
                loadingModelName = ""
                loadingModelInternalID = ""
                isConfirmingModelLoadCancel = false
            }
            if loadSucceeded {
                triggerModelLoadCompletionFlicker()
            }
            await pollOllamaRunningProcesses()
            recalculateHardwareTelemetry()
        }
    }

    public func unloadModelFromMemory(_ model: LocalModelDescriptor) async {
        if let mIdx = availableModels.firstIndex(where: { $0.name == model.name }) {
            availableModels[mIdx].residency = .dormantOnDisk
            availableModels[mIdx].vramAllocatedBytes = 0
        }
        guard let url = URL(string: "\(supervisor.normalizedEndpoint)/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30.0
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model.name, "prompt": "", "keep_alive": 0])
        _ = try? await URLSession.shared.data(for: req)
        await pollOllamaRunningProcesses()
        recalculateHardwareTelemetry()
        baselineRAMBytesBeforeLoad = memorySnapshot.totalSystemUsedBytes
    }

    // MARK: - Draft Preservation, Full File Ingestion & Downscaled Vision Attachments
    private func saveCurrentDraftToActiveSession() {
        guard let id = selectedSessionID,
              let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].draftText = composerDraft
        sessions[idx].draftAttachments = pendingAttachments
    }

    private func restoreDraftFromSelectedSession() {
        guard let id = selectedSessionID,
              let session = sessions.first(where: { $0.id == id }) else {
            composerDraft = ""
            pendingAttachments = []
            return
        }
        composerDraft = session.draftText
        pendingAttachments = session.draftAttachments
    }

    public func handleTextInputOrPaste(_ newText: String) {
        if !newText.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
            isSlashMenuDismissedForCurrentToken = false
            slashMenuHighlightedIndex = 0
        }
        let deltaCount = newText.count - composerDraft.count
        if deltaCount > 2400 || newText.components(separatedBy: .newlines).count > 55 {
            let lines = newText.components(separatedBy: .newlines)
            let preview = lines.prefix(6).joined(separator: "\n")
            let assetFile = vault.persistHeavyAsset(data: Data(newText.utf8), preferredExtension: "txt")
            let chip = MessageAttachment(
                title: "Pasted text (\(lines.count) lines)",
                kind: .pastedDocumentChip,
                byteCount: newText.utf8.count,
                lineCount: lines.count,
                previewText: preview,
                localAssetFilename: assetFile
            )
            pendingAttachments.append(chip)
            saveCurrentDraftToActiveSession()
        } else {
            composerDraft = newText
            saveCurrentDraftToActiveSession()
        }
    }

    public func attachFilesFromURLs(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.lowercased()
            let isImage = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "bmp"].contains(ext)
            if isImage {
                if let processed = vault.downscaleAndPersistVisionImage(data: data) {
                    let chip = MessageAttachment(
                        title: url.lastPathComponent,
                        kind: .downscaledVisionImage,
                        byteCount: processed.byteCount,
                        lineCount: 1,
                        previewText: url.lastPathComponent,
                        localAssetFilename: processed.filename,
                        base64ImagePayload: processed.base64JPEG
                    )
                    pendingAttachments.append(chip)
                }
            } else if let fullText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let lines = fullText.components(separatedBy: .newlines)
                let preview = lines.prefix(8).joined(separator: "\n")
                let savedAsset = vault.persistHeavyAsset(data: Data(fullText.utf8), preferredExtension: ext.isEmpty ? "txt" : ext)
                let chip = MessageAttachment(
                    title: url.lastPathComponent,
                    kind: .sourceCodeFile,
                    byteCount: fullText.utf8.count,
                    lineCount: lines.count,
                    previewText: preview,
                    localAssetFilename: savedAsset
                )
                pendingAttachments.append(chip)
            }
        }
        saveCurrentDraftToActiveSession()
    }

    // MARK: - Send, In-Place AI Reply Editing (KV Cache Trimming), Single-Message Deletion & Forking
    public var sendDisabledReason: String? {
        if activeSession == nil {
            return "Start a new chat first."
        }
        if availableModels.isEmpty {
            return "No local Ollama models detected. Open Settings to pull a model."
        }
        let trimmed = composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && pendingAttachments.isEmpty {
            return "Type a message to send."
        }
        return nil
    }

    public func sendActivePrompt(customPrompt: String? = nil) {
        guard let sessionIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }

        if isStreamingGeneration {
            stopActiveGeneration()
        }
        let rawText = (customPrompt ?? composerDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty || !pendingAttachments.isEmpty else { return }

        guard let activeModel = activeModelDescriptor else {
            humanReadableErrorBanner = "No local model selected. Open the model menu at the top right to choose or pull a model."
            return
        }

        if sessions[sessionIdx].selectedModelName.isEmpty {
            sessions[sessionIdx].selectedModelName = activeModel.name
        }
        perModelSavedParameters[activeModel.name] = sessions[sessionIdx].parameters

        humanReadableErrorBanner = nil
        isScrolledAwayFromBottom = false
        isAutoScrollPaused = false
        isComposerCanvasExpanded = false
        let targetSessionID = sessions[sessionIdx].id
        let lastNodeID = sessions[sessionIdx].activeBranchThread.last?.id

        var fullContent = rawText
        for att in pendingAttachments where att.kind != .downscaledVisionImage {
            if let fname = att.localAssetFilename, let fullFileText = vault.loadHeavyAssetText(filename: fname) {
                fullContent += "\n\n// File: \(att.title)\n```\n\(fullFileText)\n```"
            } else if !att.previewText.isEmpty {
                fullContent += "\n\n// File: \(att.title)\n```\n\(att.previewText)\n```"
            }
        }

        let userNode = ConversationMessageNode(
            parentID: lastNodeID,
            role: .user,
            content: fullContent,
            modelUsed: activeModel.name,
            attachments: pendingAttachments
        )

        appendNodeToTree(userNode, inSessionAt: sessionIdx)
        if customPrompt == nil {
            composerDraft = ""
            pendingAttachments.removeAll()
            sessions[sessionIdx].draftText = ""
            sessions[sessionIdx].draftAttachments = []
        }

        if sessions[sessionIdx].title == "New Chat" && !rawText.isEmpty {
            sessions[sessionIdx].title = ConversationSession.sanitizeTitle(rawText)
        }

        streamAssistantResponse(
            parentUserNodeID: userNode.id,
            inSessionID: targetSessionID,
            continuingAssistantNodeID: nil,
            overrideModelName: nil
        )
    }

    public func updateAssistantMessageInPlace(nodeID: UUID, updatedText: String, clearThinking: Bool) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }),
              var node = sessions[sIdx].nodes[nodeID],
              node.role == .assistant else { return }
        node.content = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clearThinking {
            node.thinkingTrace = ""
        }
        if var m = node.metrics {
            m.totalTokens = max(1, (node.content.count + node.thinkingTrace.count) / 4)
            m.promptEvalTokens = 0
            node.metrics = m
        }
        sessions[sIdx].nodes[nodeID] = node
        sessions[sIdx].updatedAt = Date()
        saveAllState()
    }

    public func deleteSingleMessageNode(_ nodeID: UUID) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }),
              let targetNode = sessions[sIdx].nodes[nodeID] else { return }

        if streamingNodeID == nodeID {
            stopActiveGeneration()
        }

        let parentID = targetNode.parentID
        let childrenIDs = targetNode.childrenIDs

        for childID in childrenIDs {
            if var child = sessions[sIdx].nodes[childID] {
                child.parentID = parentID
                sessions[sIdx].nodes[childID] = child
            }
        }

        if let pID = parentID, var parent = sessions[sIdx].nodes[pID] {
            if let idxInParent = parent.childrenIDs.firstIndex(of: nodeID) {
                parent.childrenIDs.remove(at: idxInParent)
                parent.childrenIDs.insert(contentsOf: childrenIDs, at: min(idxInParent, parent.childrenIDs.count))
                parent.activeChildIndex = min(max(0, parent.activeChildIndex), max(0, parent.childrenIDs.count - 1))
            }
            sessions[sIdx].nodes[pID] = parent
        } else {
            if let idxInRoot = sessions[sIdx].rootMessageIDs.firstIndex(of: nodeID) {
                sessions[sIdx].rootMessageIDs.remove(at: idxInRoot)
                sessions[sIdx].rootMessageIDs.insert(contentsOf: childrenIDs, at: min(idxInRoot, sessions[sIdx].rootMessageIDs.count))
                sessions[sIdx].activeRootIndex = min(max(0, sessions[sIdx].activeRootIndex), max(0, sessions[sIdx].rootMessageIDs.count - 1))
            }
        }

        sessions[sIdx].nodes.removeValue(forKey: nodeID)
        sessions[sIdx].updatedAt = Date()
        saveAllState()
    }

    public func trimOldestTurnInActiveSession() {
        guard let session = activeSession else { return }
        let thread = session.activeBranchThread
        guard let oldest = thread.first else { return }
        deleteSingleMessageNode(oldest.id)
        if thread.count >= 2 && thread[1].role == .assistant {
            deleteSingleMessageNode(thread[1].id)
        }
        kernelMemoryPressureWarning = nil
    }

    public func continueStoppedGeneration(forAssistantNodeID nodeID: UUID) {
        guard !isStreamingGeneration,
              let sessionIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }),
              let existingNode = sessions[sessionIdx].nodes[nodeID],
              existingNode.role == .assistant,
              let parentUserID = existingNode.parentID else { return }

        isScrolledAwayFromBottom = false
        isAutoScrollPaused = false
        streamAssistantResponse(
            parentUserNodeID: parentUserID,
            inSessionID: sessions[sessionIdx].id,
            continuingAssistantNodeID: nodeID,
            overrideModelName: existingNode.modelUsed.isEmpty ? nil : existingNode.modelUsed
        )
    }

    public func createEditedMessageBranch(originalNodeID: UUID, updatedText: String) {
        let trimmed = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let sessionIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }),
              let originalNode = sessions[sessionIdx].nodes[originalNodeID] else { return }

        if isStreamingGeneration { stopActiveGeneration() }
        isScrolledAwayFromBottom = false
        isAutoScrollPaused = false

        let branchedUserNode = ConversationMessageNode(
            parentID: originalNode.parentID,
            role: .user,
            content: trimmed,
            modelUsed: sessions[sessionIdx].selectedModelName,
            attachments: originalNode.attachments
        )

        appendNodeToTree(branchedUserNode, inSessionAt: sessionIdx)
        streamAssistantResponse(
            parentUserNodeID: branchedUserNode.id,
            inSessionID: sessions[sessionIdx].id,
            continuingAssistantNodeID: nil,
            overrideModelName: nil
        )
    }

    public func regenerateAssistantBranch(forAssistantNodeID nodeID: UUID, withOverrideModel modelName: String? = nil) {
        guard let sessionIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }),
              let assistantNode = sessions[sessionIdx].nodes[nodeID],
              let parentUserID = assistantNode.parentID else { return }

        if isStreamingGeneration { stopActiveGeneration() }
        if let newModel = modelName {
            sessions[sessionIdx].selectedModelName = newModel
        }
        isScrolledAwayFromBottom = false
        isAutoScrollPaused = false
        streamAssistantResponse(
            parentUserNodeID: parentUserID,
            inSessionID: sessions[sessionIdx].id,
            continuingAssistantNodeID: nil,
            overrideModelName: modelName
        )
    }

    public func branchMessageToNewChat(upToNodeID nodeID: UUID) {
        guard let currentSession = activeSession else { return }
        let thread = currentSession.activeBranchThread
        guard let cutoffIndex = thread.firstIndex(where: { $0.id == nodeID }) else { return }
        let prefixNodes = Array(thread[0...cutoffIndex])
        guard !prefixNodes.isEmpty else { return }

        var cleanBase = ConversationSession.sanitizeTitle(currentSession.title)
        if cleanBase.lowercased().hasPrefix("branch · ") {
            cleanBase = String(cleanBase.dropFirst("Branch · ".count))
        } else if cleanBase.lowercased().hasPrefix("branch - ") {
            cleanBase = String(cleanBase.dropFirst("Branch - ".count))
        }
        let branchTitle = ConversationSession.sanitizeTitle("Branch · \(cleanBase)")

        var forkedSession = ConversationSession(
            title: branchTitle,
            folderID: currentSession.folderID,
            selectedModelName: currentSession.selectedModelName,
            activePersonaTrigger: currentSession.activePersonaTrigger,
            systemPrompt: currentSession.systemPrompt,
            parameters: currentSession.parameters
        )

        var previousNewID: UUID? = nil
        for oldNode in prefixNodes {
            var cloned = oldNode
            cloned.id = UUID()
            cloned.parentID = previousNewID
            cloned.childrenIDs = []
            cloned.activeChildIndex = 0
            forkedSession.nodes[cloned.id] = cloned

            if let prevID = previousNewID, var parentNode = forkedSession.nodes[prevID] {
                parentNode.childrenIDs = [cloned.id]
                parentNode.activeChildIndex = 0
                forkedSession.nodes[prevID] = parentNode
            } else {
                forkedSession.rootMessageIDs = [cloned.id]
                forkedSession.activeRootIndex = 0
            }
            previousNewID = cloned.id
        }

        sessions.insert(forkedSession, at: 0)
        selectedSessionID = forkedSession.id
        saveAllState()
    }

    public func summarizeContextIntoNewBranch() {
        guard let sessionIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }) else { return }
        let currentThread = sessions[sessionIdx].activeBranchThread.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !currentThread.isEmpty else { return }

        if isStreamingGeneration {
            stopActiveGeneration()
        }

        let turnCount = currentThread.count
        let transcript = currentThread
            .map { "\($0.role == .user ? "USER" : "ASSISTANT"): \($0.content)" }
            .joined(separator: "\n\n")
        let hiddenSummaryDirective = "Summarize the following conversation transcript (\(turnCount) turns) into a structured, high-density context handoff. Preserve all key decisions, technical constraints, code architecture, and active goals so we can continue seamlessly from this summary:\n\n\(transcript.suffix(12000))"

        let newRootUserNode = ConversationMessageNode(
            parentID: nil,
            role: .user,
            content: "Context Summary Handoff — Compressed \(turnCount) \(turnCount == 1 ? "turn" : "turns") into a fresh KV branch.",
            apiPromptOverride: hiddenSummaryDirective,
            isSummaryHandoffRequest: true,
            modelUsed: sessions[sessionIdx].selectedModelName
        )
        appendNodeToTree(newRootUserNode, inSessionAt: sessionIdx)
        isContextCeilingBannerDismissed = false
        kernelMemoryPressureWarning = nil

        streamAssistantResponse(
            parentUserNodeID: newRootUserNode.id,
            inSessionID: sessions[sessionIdx].id,
            continuingAssistantNodeID: nil,
            overrideModelName: nil
        )
    }

    public func exportSessionAsMarkdown(_ sessionID: UUID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        var md = "# \(session.title)\n\n"
        md += "- **Model:** `\(session.selectedModelName)`\n"
        md += "- **Exported:** \(ISO8601DateFormatter().string(from: Date()))\n\n---\n\n"

        for node in session.activeBranchThread {
            let roleHeader = node.role == .user ? "### You" : "### \(LocalModelDescriptor.shortenModelName(node.modelUsed.isEmpty ? "Assistant" : node.modelUsed))"
            md += "\(roleHeader)\n\n"
            if !node.thinkingTrace.isEmpty {
                md += "<details>\n<summary>Thinking Process</summary>\n\n\(node.thinkingTrace)\n\n</details>\n\n"
            }
            md += "\(node.content)\n\n---\n\n"
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Chat as Markdown"
        savePanel.nameFieldStringValue = "\(session.title.replacingOccurrences(of: " ", with: "_")).md"
        savePanel.allowedContentTypes = [.plainText]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func switchBranchVersion(forNodeID nodeID: UUID, delta: Int) {
        guard let sessionIdx = sessions.firstIndex(where: { $0.id == selectedSessionID }),
              let node = sessions[sessionIdx].nodes[nodeID] else { return }

        if let parentID = node.parentID, var parent = sessions[sessionIdx].nodes[parentID] {
            let nextIdx = min(max(0, parent.activeChildIndex + delta), parent.childrenIDs.count - 1)
            parent.activeChildIndex = nextIdx
            sessions[sessionIdx].nodes[parentID] = parent
        } else {
            let nextRoot = min(max(0, sessions[sessionIdx].activeRootIndex + delta), sessions[sessionIdx].rootMessageIDs.count - 1)
            sessions[sessionIdx].activeRootIndex = nextRoot
        }
        saveAllState()
    }

    private func appendNodeToTree(_ node: ConversationMessageNode, inSessionAt sessionIdx: Int) {
        sessions[sessionIdx].nodes[node.id] = node
        if let parentID = node.parentID, var parent = sessions[sessionIdx].nodes[parentID] {
            parent.childrenIDs.append(node.id)
            parent.activeChildIndex = parent.childrenIDs.count - 1
            sessions[sessionIdx].nodes[parentID] = parent
        } else {
            sessions[sessionIdx].rootMessageIDs.append(node.id)
            sessions[sessionIdx].activeRootIndex = sessions[sessionIdx].rootMessageIDs.count - 1
        }
        sessions[sessionIdx].updatedAt = Date()
    }

    // MARK: - Stop-Safe & KV-Cache-Preserving Ollama `/api/chat` Streaming
    private func streamAssistantResponse(
        parentUserNodeID: UUID,
        inSessionID targetSessionID: UUID,
        continuingAssistantNodeID: UUID?,
        overrideModelName: String?
    ) {
        streamingTask?.cancel()
        guard let initialIdx = sessions.firstIndex(where: { $0.id == targetSessionID }) else { return }

        let resolvedModel: LocalModelDescriptor?
        if let override = overrideModelName, let matched = availableModels.first(where: { $0.name == override }) {
            resolvedModel = matched
        } else {
            resolvedModel = activeModelDescriptor
        }
        guard let model = resolvedModel else { return }

        let sessionParams = sessions[initialIdx].parameters
        let isSummaryTurn = sessions[initialIdx].nodes[parentUserNodeID]?.isSummaryHandoffRequest == true
        let modelSupportsThinking = model.thinkingProfile.kind != .unsupported || sessionParams.forceThinkingOverrideWhenUnsupported

        let shouldThink: Bool
        if isSummaryTurn {
            shouldThink = modelSupportsThinking && supervisor.useThinkingForSummary
        } else {
            shouldThink = modelSupportsThinking && sessionParams.thinkingMode.isThinkingEnabled
        }

        let assistantID: UUID
        let initialThinking: String
        let initialAnswer: String
        let resumeInThinking: Bool
        let priorThinkSec: Double
        let priorTotalTokens: Int

        if let contID = continuingAssistantNodeID, var existing = sessions[initialIdx].nodes[contID] {
            resumeInThinking = existing.wasStoppedMidThinking && existing.content.isEmpty
            priorThinkSec = existing.metrics?.thinkingDurationSec ?? 0.0
            priorTotalTokens = existing.metrics?.totalTokens ?? 0
            existing.wasStoppedMidStream = false
            existing.wasStoppedMidThinking = false
            existing.errorNote = nil
            if resumeInThinking {
                existing.isThinkingComplete = false
                existing.isThinkingExpanded = true
            }
            sessions[initialIdx].nodes[contID] = existing
            assistantID = contID
            initialThinking = existing.thinkingTrace
            initialAnswer = existing.content
        } else {
            resumeInThinking = false
            priorThinkSec = 0.0
            priorTotalTokens = 0
            let placeholderAssistant = ConversationMessageNode(
                parentID: parentUserNodeID,
                role: .assistant,
                content: "",
                thinkingTrace: "",
                isThinkingComplete: !shouldThink,
                isThinkingExpanded: true,
                modelUsed: model.shortDisplayName
            )
            appendNodeToTree(placeholderAssistant, inSessionAt: initialIdx)
            assistantID = placeholderAssistant.id
            initialThinking = ""
            initialAnswer = ""
        }

        let parser = StatefulThinkingStreamParser()
        parser.preloadExisting(
            thinking: initialThinking,
            answer: initialAnswer,
            resumeInsideThinking: resumeInThinking,
            priorThinkingDuration: priorThinkSec
        )
        self.activeStreamParser = parser

        isStreamingGeneration = true
        streamingSessionID = targetSessionID
        streamingNodeID = assistantID
        liveTokensPerSec = 0.0
        liveTotalTokens = priorTotalTokens
        liveElapsedSeconds = priorThinkSec

        let neededInitialLoad = (model.residency != .activeInUnifiedRAM)
        if neededInitialLoad {
            baselineOllamaRSSBeforeLoad = HardwareMemoryEngine.queryOllamaProcessResidentBytes()
            baselineRAMBytesBeforeLoad = memorySnapshot.totalSystemUsedBytes
            targetLoadingModelBytes = max(1, model.sizeBytes)
            withAnimation(.easeInOut(duration: 0.25)) {
                isLoadingModelWeights = true
                loadingModelName = model.shortDisplayName
                loadingModelInternalID = model.name
            }
            recalculateHardwareTelemetry()
        }

        let fullThread = sessions[initialIdx].activeBranchThread
        let historyUpToParent = fullThread.filter { $0.id != assistantID }
        let systemPromptCopy = sessions[initialIdx].systemPrompt
        let endpoint = supervisor.normalizedEndpoint

        streamingTask = Task {
            let startWall = Date()

            guard let url = URL(string: "\(endpoint)/api/chat") else {
                self.isStreamingGeneration = false
                self.isLoadingModelWeights = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 300.0

            var apiMessages: [[String: Any]] = []
            if !systemPromptCopy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apiMessages.append(["role": "system", "content": systemPromptCopy])
            }

            // Keep message history tokens 100% immutable across turns so Ollama reuses its KV cache in RAM without re-evaluating prior turns!
            for turn in historyUpToParent {
                let textContent = turn.apiPromptOverride ?? turn.content
                var msgDict: [String: Any] = [
                    "role": turn.role.rawValue,
                    "content": textContent
                ]
                let imagesBase64: [String] = turn.attachments.compactMap { att in
                    if let memB64 = att.base64ImagePayload, !memB64.isEmpty { return memB64 }
                    if att.kind == .downscaledVisionImage, let fname = att.localAssetFilename {
                        return self.vault.loadHeavyAssetBase64(filename: fname)
                    }
                    return nil
                }
                if !imagesBase64.isEmpty {
                    msgDict["images"] = imagesBase64
                }
                apiMessages.append(msgDict)
            }

            if continuingAssistantNodeID != nil {
                if !initialAnswer.isEmpty {
                    apiMessages.append(["role": "assistant", "content": initialAnswer])
                    apiMessages.append([
                        "role": "user",
                        "content": "Continue writing directly from the exact word where you stopped: \"\(initialAnswer.suffix(140))\". Do not repeat what was already written."
                    ])
                } else if !initialThinking.isEmpty {
                    apiMessages.append([
                        "role": "user",
                        "content": "You were in the middle of thinking:\n\"\(initialThinking.suffix(400))\"\nFinish your reasoning briefly and provide the complete final answer."
                    ])
                }
            }

            var optionsDict: [String: Any] = [
                "temperature": sessionParams.temperature,
                "top_k": sessionParams.topK,
                "top_p": sessionParams.topP,
                "min_p": sessionParams.minP,
                "typical_p": sessionParams.typicalP,
                "repeat_penalty": sessionParams.repeatPenalty,
                "repeat_last_n": sessionParams.repeatLastN,
                "presence_penalty": sessionParams.presencePenalty,
                "frequency_penalty": sessionParams.frequencyPenalty,
                "mirostat": sessionParams.mirostat.rawValue,
                "mirostat_tau": sessionParams.mirostatTau,
                "mirostat_eta": sessionParams.mirostatEta,
                "num_ctx": sessionParams.numCtx,
                "num_predict": sessionParams.numPredict,
                "num_keep": sessionParams.numKeep,
                "num_batch": sessionParams.numBatch,
                "seed": sessionParams.seed,
                "penalize_newline": sessionParams.penalizeNewline,
                "use_mmap": sessionParams.useMmap,
                "use_mlock": sessionParams.useMlock
            ]
            // Only send num_thread or num_gpu if explicitly overridden so Apple Silicon defaults to fast Performance Cores and automatic Metal VRAM fitting!
            if sessionParams.numThread > 0 {
                optionsDict["num_thread"] = sessionParams.numThread
            }
            if sessionParams.numGpu >= 0 {
                optionsDict["num_gpu"] = sessionParams.numGpu
            }

            let stops = sessionParams.stopSequencesCSV
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !stops.isEmpty {
                optionsDict["stop"] = stops
            }

            var payload: [String: Any] = [
                "model": model.name,
                "messages": apiMessages,
                "stream": true,
                "keep_alive": "\(sessionParams.keepAliveMinutes)m",
                "options": optionsDict
            ]

            if modelSupportsThinking {
                if isSummaryTurn && !supervisor.useThinkingForSummary {
                    payload["think"] = false
                } else if continuingAssistantNodeID != nil && !initialAnswer.isEmpty {
                    payload["think"] = false
                } else if model.thinkingProfile.supportsEffortLevels && shouldThink, let effortStr = sessionParams.thinkingMode.effortDirective {
                    payload["think"] = effortStr
                } else {
                    payload["think"] = shouldThink
                }
            }

            if sessionParams.enforceJSONMode {
                payload["format"] = "json"
            }

            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            var receivedFirstChunk = false
            var tokenCounter = 0
            var evalTokenCountFromEngine: Int? = nil
            var promptEvalCountFromEngine: Int? = nil
            var evalDurationFromEngineNs: Int64? = nil

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if http.statusCode == 400 && payload["think"] != nil {
                    payload.removeValue(forKey: "think")
                    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                    let (retryBytes, retryResp) = try await URLSession.shared.bytes(for: request)
                    if let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode == 200 {
                        for try await line in retryBytes.lines {
                            if Task.isCancelled { break }
                            await processStreamLine(
                                line,
                                neededInitialLoad: neededInitialLoad,
                                startWall: startWall,
                                priorTokens: priorTotalTokens,
                                receivedFirstChunk: &receivedFirstChunk,
                                tokenCounter: &tokenCounter,
                                evalTokenCountFromEngine: &evalTokenCountFromEngine,
                                promptEvalCountFromEngine: &promptEvalCountFromEngine,
                                evalDurationFromEngineNs: &evalDurationFromEngineNs,
                                parser: parser,
                                assistantID: assistantID,
                                targetSessionID: targetSessionID
                            )
                        }
                    }
                } else if http.statusCode != 200 {
                    var errorBody = ""
                    for try await line in bytes.lines { errorBody += line }
                    self.recordStreamError(
                        assistantID: assistantID,
                        targetSessionID: targetSessionID,
                        message: "Ollama HTTP \(http.statusCode): \(errorBody)"
                    )
                } else {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        await processStreamLine(
                            line,
                            neededInitialLoad: neededInitialLoad,
                            startWall: startWall,
                            priorTokens: priorTotalTokens,
                            receivedFirstChunk: &receivedFirstChunk,
                            tokenCounter: &tokenCounter,
                            evalTokenCountFromEngine: &evalTokenCountFromEngine,
                            promptEvalCountFromEngine: &promptEvalCountFromEngine,
                            evalDurationFromEngineNs: &evalDurationFromEngineNs,
                            parser: parser,
                            assistantID: assistantID,
                            targetSessionID: targetSessionID
                        )
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.recordStreamError(
                        assistantID: assistantID,
                        targetSessionID: targetSessionID,
                        message: "Connection to local Ollama failed (\(error.localizedDescription)). Ensure Ollama is running."
                    )
                }
            }

            if !Task.isCancelled {
                parser.flushPendingBufferWithoutLosingState(markComplete: true)

                let hasThoughtOnly = !parser.accumulatedThinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                     parser.accumulatedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                     continuingAssistantNodeID == nil
                if hasThoughtOnly {
                    var followUpMessages = apiMessages
                    followUpMessages.append([
                        "role": "assistant",
                        "content": "<think>\n\(parser.accumulatedThinking)\n</think>"
                    ])
                    followUpMessages.append([
                        "role": "user",
                        "content": "Now provide the complete final response based on your reasoning above."
                    ])
                    var followUpPayload = payload
                    followUpPayload["messages"] = followUpMessages
                    followUpPayload["think"] = false
                    request.httpBody = try? JSONSerialization.data(withJSONObject: followUpPayload)

                    if let (followBytes, followResp) = try? await URLSession.shared.bytes(for: request),
                       let followHttp = followResp as? HTTPURLResponse, followHttp.statusCode == 200 {
                        for try await line in followBytes.lines {
                            if Task.isCancelled { break }
                            await processStreamLine(
                                line,
                                neededInitialLoad: false,
                                startWall: startWall,
                                priorTokens: priorTotalTokens,
                                receivedFirstChunk: &receivedFirstChunk,
                                tokenCounter: &tokenCounter,
                                evalTokenCountFromEngine: &evalTokenCountFromEngine,
                                promptEvalCountFromEngine: &promptEvalCountFromEngine,
                                evalDurationFromEngineNs: &evalDurationFromEngineNs,
                                parser: parser,
                                assistantID: assistantID,
                                targetSessionID: targetSessionID
                            )
                        }
                        parser.flushPendingBufferWithoutLosingState(markComplete: true)
                    }
                }

                let totalElapsed = max(0.1, Date().timeIntervalSince(startWall))
                var finalTPS = self.liveTokensPerSec
                if let ec = evalTokenCountFromEngine, let ed = evalDurationFromEngineNs, ed > 0 {
                    finalTPS = Double(ec) / (Double(ed) / 1_000_000_000.0)
                }
                let finalTokens = priorTotalTokens + (evalTokenCountFromEngine ?? max(tokenCounter, parser.accumulatedAnswer.count / 4))

                self.updateStreamingNode(
                    assistantID: assistantID,
                    targetSessionID: targetSessionID,
                    parser: parser,
                    tps: finalTPS,
                    elapsed: totalElapsed,
                    totalTokens: finalTokens,
                    promptTokens: promptEvalCountFromEngine ?? 0,
                    isFinal: true
                )
                self.extractArtifactsFromCompletedMessage(assistantID: assistantID, targetSessionID: targetSessionID)
                self.isStreamingGeneration = false
                self.isLoadingModelWeights = false
                self.loadingModelName = ""
                self.loadingModelInternalID = ""
                self.streamingSessionID = nil
                self.streamingNodeID = nil
                self.activeStreamParser = nil
                self.saveAllState()
                await self.pollOllamaRunningProcesses()
                self.recalculateHardwareTelemetry()
            }
        }
    }

    private func processStreamLine(
        _ line: String,
        neededInitialLoad: Bool,
        startWall: Date,
        priorTokens: Int,
        receivedFirstChunk: inout Bool,
        tokenCounter: inout Int,
        evalTokenCountFromEngine: inout Int?,
        promptEvalCountFromEngine: inout Int?,
        evalDurationFromEngineNs: inout Int64?,
        parser: StatefulThinkingStreamParser,
        assistantID: UUID,
        targetSessionID: UUID
    ) async {
        guard !Task.isCancelled,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let errStr = json["error"] as? String {
            self.recordStreamError(assistantID: assistantID, targetSessionID: targetSessionID, message: errStr)
            return
        }

        if !receivedFirstChunk {
            receivedFirstChunk = true
            withAnimation(.easeInOut(duration: 0.30)) {
                self.isLoadingModelWeights = false
                self.loadingModelName = ""
                self.loadingModelInternalID = ""
                self.isConfirmingModelLoadCancel = false
            }
            if neededInitialLoad {
                self.triggerModelLoadCompletionFlicker()
            }
            await self.pollOllamaRunningProcesses()
        }

        if let msg = json["message"] as? [String: Any] {
            if let explicitThink = msg["thinking"] as? String, !explicitThink.isEmpty {
                parser.ingestExplicitThinkingDelta(explicitThink)
                tokenCounter += 1
            }
            if let contentChunk = msg["content"] as? String, !contentChunk.isEmpty {
                parser.ingestContentChunk(contentChunk)
                tokenCounter += 1
            }
        }

        if let promptEval = json["prompt_eval_count"] as? Int {
            promptEvalCountFromEngine = promptEval
        }
        if let evalCount = json["eval_count"] as? Int {
            evalTokenCountFromEngine = evalCount
        }
        if let evalDur = json["eval_duration"] as? Int64 {
            evalDurationFromEngineNs = evalDur
        }

        let isDoneChunk = (json["done"] as? Bool) == true
        let now = Date()
        guard isDoneChunk || tokenCounter <= 2 || now.timeIntervalSince(self.lastStreamUIUpdateTime) >= 0.036 else {
            return
        }
        self.lastStreamUIUpdateTime = now

        let elapsed = max(0.05, now.timeIntervalSince(startWall))
        var tps = Double(max(1, tokenCounter)) / elapsed
        if let ec = evalTokenCountFromEngine, let ed = evalDurationFromEngineNs, ed > 0 {
            tps = Double(ec) / (Double(ed) / 1_000_000_000.0)
        }
        let currentTotal = priorTokens + (evalTokenCountFromEngine ?? tokenCounter)

        self.updateStreamingNode(
            assistantID: assistantID,
            targetSessionID: targetSessionID,
            parser: parser,
            tps: tps,
            elapsed: elapsed,
            totalTokens: currentTotal,
            promptTokens: promptEvalCountFromEngine ?? 0,
            isFinal: false
        )
    }

    private func recordStreamError(assistantID: UUID, targetSessionID: UUID, message: String) {
        humanReadableErrorBanner = message
        guard let sIdx = sessions.firstIndex(where: { $0.id == targetSessionID }),
              var node = sessions[sIdx].nodes[assistantID] else { return }
        node.isThinkingComplete = true
        node.errorNote = message
        sessions[sIdx].nodes[assistantID] = node
    }

    private func updateStreamingNode(
        assistantID: UUID,
        targetSessionID: UUID,
        parser: StatefulThinkingStreamParser,
        tps: Double,
        elapsed: Double,
        totalTokens: Int,
        promptTokens: Int,
        isFinal: Bool
    ) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == targetSessionID }),
              var node = sessions[sIdx].nodes[assistantID] else { return }

        node.thinkingTrace = parser.accumulatedThinking
        node.content = parser.accumulatedAnswer
        node.isThinkingComplete = !parser.isCurrentlyThinking || isFinal

        self.liveTokensPerSec = tps
        self.liveTotalTokens = totalTokens
        self.liveElapsedSeconds = elapsed

        let prevPrompt = node.metrics?.promptEvalTokens ?? 0
        node.metrics = GenerationMetrics(
            tokensPerSecond: tps,
            totalGenerationDurationSec: elapsed,
            thinkingDurationSec: parser.thinkingDurationSeconds,
            totalTokens: totalTokens,
            promptEvalTokens: promptTokens > 0 ? promptTokens : prevPrompt
        )
        sessions[sIdx].nodes[assistantID] = node

        if !isScrolledAwayFromBottom && !isAutoScrollPaused && !isFinal && totalTokens % 4 == 0 {
            streamScrollPulse &+= 1
        }
    }

    public func stopActiveGeneration() {
        if let parser = activeStreamParser {
            parser.flushPendingBufferWithoutLosingState(markComplete: false)
        }
        if let sID = streamingSessionID,
           let nID = streamingNodeID,
           let sIdx = sessions.firstIndex(where: { $0.id == sID }),
           var node = sessions[sIdx].nodes[nID] {
            if let parser = activeStreamParser {
                node.thinkingTrace = parser.accumulatedThinking
                node.content = parser.accumulatedAnswer
                node.wasStoppedMidThinking = parser.isCurrentlyThinking || (node.content.isEmpty && !node.thinkingTrace.isEmpty)
            }
            node.isThinkingComplete = true
            node.wasStoppedMidStream = true
            if !node.thinkingTrace.isEmpty && node.content.isEmpty {
                node.isThinkingExpanded = true
            }
            sessions[sIdx].nodes[nID] = node
        }
        streamingTask?.cancel()
        streamingTask = nil
        activeStreamParser = nil
        isStreamingGeneration = false
        isLoadingModelWeights = false
        loadingModelName = ""
        loadingModelInternalID = ""
        isConfirmingModelLoadCancel = false
        streamingSessionID = nil
        streamingNodeID = nil
        saveAllState()
    }

    private func extractArtifactsFromCompletedMessage(assistantID: UUID, targetSessionID: UUID) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == targetSessionID }),
              let node = sessions[sIdx].nodes[assistantID] else { return }

        let pattern = "```([a-zA-Z0-9_-]*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsContent = node.content as NSString
        let matches = regex.matches(in: node.content, range: NSRange(location: 0, length: nsContent.length))

        for (idx, match) in matches.enumerated() where match.numberOfRanges >= 3 {
            let lang = nsContent.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let code = nsContent.substring(with: match.range(at: 2))
            guard code.count > 32 else { continue }

            let title = "\(lang.isEmpty ? "Code" : lang.capitalized) #\(idx + 1)"
            if !sessions[sIdx].artifacts.contains(where: { $0.content == code }) {
                let artifact = WorkspaceArtifact(
                    title: title,
                    language: lang.isEmpty ? "swift" : lang,
                    content: code,
                    sourceMessageID: assistantID
                )
                sessions[sIdx].artifacts.append(artifact)
                selectedArtifactID = artifact.id
            }
        }
    }

    // MARK: - Session, Workspace, Preset & Recoverable Trash Lifecycle (Restores Per-Model Thinking & Parameters!)
    public func createNewSession(folderID: UUID? = nil) {
        let defaultModel = activeModelDescriptor?.name ?? availableModels.first?.name ?? ""
        let inheritedParams = preferredParameters(forModelName: defaultModel)
        let newSession = ConversationSession(
            title: "New Chat",
            folderID: folderID,
            selectedModelName: defaultModel,
            parameters: inheritedParams
        )
        sessions.insert(newSession, at: 0)
        selectedSessionID = newSession.id
        saveAllState()
    }

    public func createWorkspace(name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let folder = ProjectFolder(name: cleaned, isExpanded: true)
        folders.append(folder)
        saveAllState()
    }

    public func renameWorkspace(folderID: UUID, newName: String) {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].name = cleaned
        saveAllState()
    }

    public func deleteWorkspace(folderID: UUID) {
        for idx in sessions.indices where sessions[idx].folderID == folderID {
            sessions[idx].folderID = nil
        }
        folders.removeAll { $0.id == folderID }
        saveAllState()
    }

    public func createPreset(name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let currentParams = activeSession?.parameters ?? .balanced
        let currentPrompt = activeSession?.systemPrompt ?? ""
        let preset = ParameterPreset(
            name: cleaned,
            summary: String(format: "%@ · Temp %.2f · %dk ctx · KV %@", currentParams.thinkingMode.rawValue, currentParams.temperature, currentParams.numCtx / 1024, currentParams.kvCacheQuant.rawValue.uppercased()),
            parameters: currentParams,
            systemPrompt: currentPrompt
        )
        presets.append(preset)
        saveAllState()
    }

    public func updatePresetWithCurrentSettings(_ presetID: UUID) {
        guard let pIdx = presets.firstIndex(where: { $0.id == presetID }),
              let session = activeSession else { return }
        presets[pIdx].parameters = session.parameters
        presets[pIdx].systemPrompt = session.systemPrompt
        presets[pIdx].summary = String(format: "%@ · Temp %.2f · %dk ctx · KV %@", session.parameters.thinkingMode.rawValue, session.parameters.temperature, session.parameters.numCtx / 1024, session.parameters.kvCacheQuant.rawValue.uppercased())
        saveAllState()
    }

    public func deletePreset(_ presetID: UUID) {
        presets.removeAll { $0.id == presetID }
        saveAllState()
    }

    public func moveSessionToTrash(_ sessionID: UUID) {
        if streamingSessionID == sessionID {
            stopActiveGeneration()
        }
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].isTrashed = true
        sessions[idx].trashedAt = Date()
        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first(where: { !$0.isTrashed })?.id
        }
        saveAllState()
    }

    public func restoreSessionFromTrash(_ sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].isTrashed = false
        sessions[idx].trashedAt = nil
        selectedSessionID = sessionID
        saveAllState()
    }

    public func permanentlyDeleteSession(_ sessionID: UUID) {
        if streamingSessionID == sessionID {
            stopActiveGeneration()
        }
        sessions.removeAll { $0.id == sessionID }
        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first(where: { !$0.isTrashed })?.id
        }
        saveAllState()
    }

    public func emptyTrashPermanently() {
        sessions.removeAll { $0.isTrashed }
        saveAllState()
    }

    public func duplicateSession(_ sessionID: UUID) {
        guard let orig = sessions.first(where: { $0.id == sessionID }) else { return }
        var copy = orig
        copy.id = UUID()
        copy.title = "\(orig.title) Copy"
        copy.isTrashed = false
        copy.createdAt = Date()
        copy.updatedAt = Date()
        sessions.insert(copy, at: 0)
        selectedSessionID = copy.id
        saveAllState()
    }

    public func commitInlineRename(sessionID: UUID, proposedName: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].title = ConversationSession.sanitizeTitle(proposedName)
        saveAllState()
    }

    public func adjustActiveFontSize(delta: Double) {
        if isWindowFullscreen {
            typography.fullscreenBaseFontSize = min(22.0, max(13.0, typography.fullscreenBaseFontSize + delta))
        } else {
            typography.windowedBaseFontSize = min(19.0, max(11.5, typography.windowedBaseFontSize + delta))
        }
    }

    public func saveAllState() {
        vault.scheduleDebouncedSave(sessions: sessions, folders: folders, presets: presets, personas: slashPersonas)
    }

    public func startModelDownload(reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "\(supervisor.normalizedEndpoint)/api/pull") else { return }

        let taskID = UUID()
        let newTask = RegistryDownloadTask(
            id: taskID,
            modelReference: trimmed,
            statusText: "Starting download…",
            completedBytes: 0,
            totalBytes: 1,
            isCompleted: false
        )
        downloadTasks.insert(newTask, at: 0)

        let handle = Task {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 3600.0
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": trimmed, "stream": true])

            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: req)
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let status = (json["status"] as? String) ?? "Downloading…"
                    let completed = (json["completed"] as? Int64) ?? 0
                    let total = (json["total"] as? Int64) ?? 1

                    if let tIdx = self.downloadTasks.firstIndex(where: { $0.id == taskID }) {
                        self.downloadTasks[tIdx].statusText = status
                        if total > 0 {
                            self.downloadTasks[tIdx].completedBytes = completed
                            self.downloadTasks[tIdx].totalBytes = total
                        }
                        if status == "success" {
                            self.downloadTasks[tIdx].isCompleted = true
                        }
                    }
                }
                if !Task.isCancelled {
                    await self.refreshLocalEngineModels()
                }
            } catch {
                if !Task.isCancelled, let tIdx = self.downloadTasks.firstIndex(where: { $0.id == taskID }) {
                    self.downloadTasks[tIdx].statusText = "Failed: \(error.localizedDescription)"
                }
            }
            self.downloadTaskHandles.removeValue(forKey: taskID)
        }
        downloadTaskHandles[taskID] = handle
    }

    public func cancelModelDownload(_ taskID: UUID) {
        downloadTaskHandles[taskID]?.cancel()
        downloadTaskHandles.removeValue(forKey: taskID)
        downloadTasks.removeAll { $0.id == taskID }
    }

    private func loadSavedSessionsAndWorkspaces() {
        if let (savedSessions, savedFolders, savedPresets, savedPersonas) = vault.loadSavedState() {
            self.sessions = savedSessions
            self.folders = savedFolders
            self.presets = savedPresets
            self.slashPersonas = savedPersonas
            if let savedIDStr = UserDefaults.standard.string(forKey: "MotifSelectedSessionIDV8"),
               let savedUUID = UUID(uuidString: savedIDStr),
               self.sessions.contains(where: { $0.id == savedUUID && !$0.isTrashed }) {
                self.selectedSessionID = savedUUID
            } else {
                self.selectedSessionID = self.sessions.first(where: { !$0.isTrashed })?.id
            }
            restoreDraftFromSelectedSession()
        }
    }
}
EOF
