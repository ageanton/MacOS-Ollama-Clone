import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

public enum PrimaryWorkspaceTab: String, CaseIterable, Identifiable {
    case chat = "chat"
    case modelsAndRAM = "models"
    case modelBuilder = "builder"
    case serverControl = "server"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chat: return "Conversations"
        case .modelsAndRAM: return "Models & RAM"
        case .modelBuilder: return "Model Builder"
        case .serverControl: return "Server Control"
        }
    }

    public var shortcutLabel: String {
        switch self {
        case .chat: return "⌘1"
        case .modelsAndRAM: return "⌘2"
        case .modelBuilder: return "⌘3"
        case .serverControl: return "⌘4"
        }
    }

    public var iconName: StudioIconName {
        switch self {
        case .chat: return .chat
        case .modelsAndRAM: return .models
        case .modelBuilder: return .builder
        case .serverControl: return .server
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    // Navigation & Sheets
    @Published public var selectedTab: PrimaryWorkspaceTab = .chat
    @Published public var isInspectorDrawerOpen: Bool = false
    @Published public var isSettingsSheetOpen: Bool = false
    @Published public var isQuickActionSheetOpen: Bool = false
    @Published public var isTrashSheetOpen: Bool = false
    @Published public var inspectedModelInfo: OllamaModelShowInfo? = nil
    @Published public var inspectedModelName: String? = nil

    // Core Data
    @Published public var conversations: [Conversation] = []
    @Published public var activeConversationID: UUID? = nil
    @Published public var searchQuery: String = ""
    @Published public var modelDefaultDials: [String: ModelDials] = [:]
    @Published public var serverConfig: ServerConfig = ServerConfig()
    @Published public var builderDraft: ModelBuilderSpec = ModelBuilderSpec()
    @Published public var trashedItems: [TrashedEntity] = []

    // Live Engine State
    @Published public var isEngineOnline: Bool = false
    @Published public var engineVersion: String = "Checking..."
    @Published public var installedModels: [OllamaModelSummary] = []
    @Published public var runningModels: [RunningModelProcess] = []
    @Published public var activePullTasks: [ModelPullTask] = []
    @Published public var activeErrorBanner: HumanFriendlyError? = nil
    @Published public var activeUndoToast: UndoToastBanner? = nil

    // Streaming & Builder State
    @Published public var isGeneratingReply: Bool = false
    @Published public var isBuildingModel: Bool = false
    @Published public var builderStatusLog: String = ""

    public struct UndoToastBanner: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
        public let trashedItemID: UUID
    }

    public let client = OllamaClient()
    public let hardware = HardwareMonitor()
    public let processManager = ProcessManager()
    private let storage = EncryptedStorageService.shared

    private var streamTask: Task<Void, Never>? = nil
    private var pullTasksMap: [String: Task<Void, Never>] = [:]
    private var statusPollTimer: Timer? = nil

    public init() {
        loadFromEncryptedVault()
        startEngineHeartbeat()
    }

    // MARK: - Active Conversation Binding Helpers

    public var activeConversation: Conversation? {
        guard let id = activeConversationID else { return conversations.first }
        return conversations.first(where: { $0.id == id }) ?? conversations.first
    }

    public var activeConversationIndex: Int? {
        guard let id = activeConversation?.id else { return nil }
        return conversations.firstIndex(where: { $0.id == id })
    }

    public var filteredConversations: [Conversation] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return conversations }
        return conversations.filter { conv in
            conv.title.lowercased().contains(q) ||
            conv.messages.contains(where: { $0.content.lowercased().contains(q) })
        }
    }

    public var activeModelSummary: OllamaModelSummary? {
        guard let name = activeConversation?.selectedModel else { return installedModels.first }
        return installedModels.first(where: { $0.name == name }) ?? installedModels.first
    }

    // MARK: - Persistence & Snapshots

    public func loadFromEncryptedVault() {
        if let vault = storage.loadVault() {
            self.conversations = vault.conversations
            self.modelDefaultDials = vault.modelDefaultDials
            self.serverConfig = vault.serverConfig
            self.trashedItems = vault.trashedItems
            if let first = conversations.first {
                self.activeConversationID = first.id
            }
        }
        if conversations.isEmpty {
            let starter = Conversation(
                title: "Welcome Workspace",
                selectedModel: "",
                messages: [],
                dials: ModelDials()
            )
            conversations = [starter]
            activeConversationID = starter.id
        }
    }

    public func persistVault() {
        let vault = EncryptedStorageService.PersistedVault(
            conversations: conversations,
            modelDefaultDials: modelDefaultDials,
            serverConfig: serverConfig,
            trashedItems: trashedItems,
            savedBuilderSpecs: [builderDraft]
        )
        try? storage.saveVault(vault)
    }

    // MARK: - Engine Heartbeat & Auto-Discovery

    public func startEngineHeartbeat() {
        Task { await refreshEngineStatus() }
        statusPollTimer?.invalidate()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshEngineStatus()
            }
        }
    }

    public func refreshEngineStatus() async {
        let baseURL = serverConfig.baseURLString
        do {
            let version = try await client.fetchVersion(baseURL: baseURL)
            let tags = try await client.fetchInstalledModels(baseURL: baseURL)
            let ps = try await client.fetchRunningModels(baseURL: baseURL)

            self.isEngineOnline = true
            self.engineVersion = version
            self.installedModels = tags
            self.runningModels = ps

            if activeErrorBanner?.recoveryKind == .startEngine {
                activeErrorBanner = nil
            }

            // Ensure every conversation has a valid model selected if one is installed
            if let firstModel = tags.first?.name {
                for idx in conversations.indices where conversations[idx].selectedModel.isEmpty {
                    conversations[idx].selectedModel = firstModel
                    if let savedDials = modelDefaultDials[firstModel] {
                        conversations[idx].dials = savedDials
                    }
                }
                if builderDraft.baseModelOrGGUFPath.isEmpty {
                    builderDraft.baseModelOrGGUFPath = firstModel
                }
            }
        } catch {
            self.isEngineOnline = false
            self.engineVersion = "Offline"
            self.runningModels = []
        }
    }

    // MARK: - Conversation Lifecycle & Non-Destructive Trash

    public func createNewConversation() {
        let defaultModel = activeConversation?.selectedModel.isEmpty == false
            ? activeConversation!.selectedModel
            : (installedModels.first?.name ?? "")
        let dials = modelDefaultDials[defaultModel] ?? ModelDials()
        let newConv = Conversation(
            title: "New Conversation",
            selectedModel: defaultModel,
            messages: [],
            dials: dials
        )
        conversations.insert(newConv, at: 0)
        activeConversationID = newConv.id
        selectedTab = .chat
        persistVault()
    }

    public func clearActiveConversationMessages() {
        guard let idx = activeConversationIndex else { return }
        conversations[idx].messages.removeAll()
        conversations[idx].updatedAt = Date()
        persistVault()
    }

    public func deleteConversationToTrash(_ id: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        let removed = conversations.remove(at: idx)
        let trashed = TrashedEntity(
            id: UUID(),
            deletedAt: Date(),
            summaryTitle: removed.title,
            payload: .conversation(removed)
        )
        trashedItems.insert(trashed, at: 0)

        if activeConversationID == id {
            if conversations.isEmpty {
                createNewConversation()
            } else {
                activeConversationID = conversations.first?.id
            }
        }
        persistVault()
        showUndoToast(message: "Moved '\(removed.title)' to Trash", trashedItemID: trashed.id)
    }

    public func restoreFromTrash(_ trashedID: UUID) {
        guard let idx = trashedItems.firstIndex(where: { $0.id == trashedID }) else { return }
        let item = trashedItems.remove(at: idx)
        switch item.payload {
        case .conversation(let conv):
            conversations.insert(conv, at: 0)
            activeConversationID = conv.id
        case .customModelBackup(_, let spec):
            builderDraft = spec
            selectedTab = .modelBuilder
        }
        if activeUndoToast?.trashedItemID == trashedID {
            activeUndoToast = nil
        }
        persistVault()
    }

    private func showUndoToast(message: String, trashedItemID: UUID) {
        let toast = UndoToastBanner(message: message, trashedItemID: trashedItemID)
        activeUndoToast = toast
        Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if activeUndoToast?.id == toast.id {
                activeUndoToast = nil
            }
        }
    }

    // MARK: - Sending Messages, Editing Messages & Streaming Replies

    public func sendUserMessage(text: String, attachments: [ChatAttachment]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        guard let idx = activeConversationIndex else { return }

        let targetModel = conversations[idx].selectedModel
        guard !targetModel.isEmpty else {
            activeErrorBanner = HumanFriendlyError(
                title: "No Model Selected",
                plainExplanation: "Choose an installed model in Models & RAM (⌘2) or download one from Hugging Face before starting a chat.",
                technicalDetail: "selectedModel is empty",
                recoveryActionTitle: "Open Models & RAM",
                recoveryKind: .pullMissingModel("llama3.2:3b")
            )
            return
        }

        let userMsg = ChatMessage(
            role: .user,
            content: trimmed,
            attachments: attachments,
            createdAt: Date()
        )
        conversations[idx].messages.append(userMsg)

        if conversations[idx].messages.count == 1 && !trimmed.isEmpty {
            conversations[idx].title = String(trimmed.prefix(46))
        }
        conversations[idx].updatedAt = Date()
        persistVault()

        streamAssistantResponse(forConversationAt: idx)
    }

    public func updateAndResendMessage(messageID: UUID, updatedText: String) {
        guard let idx = activeConversationIndex,
              let msgIdx = conversations[idx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[idx].messages[msgIdx].content = updatedText
        // Remove subsequent replies after the edited message and regenerate
        if msgIdx + 1 < conversations[idx].messages.count {
            conversations[idx].messages.removeSubrange((msgIdx + 1)..<conversations[idx].messages.count)
        }
        persistVault()
        if conversations[idx].messages[msgIdx].role == .user {
            streamAssistantResponse(forConversationAt: idx)
        }
    }

    public func stopActiveGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isGeneratingReply = false
        if let idx = activeConversationIndex, !conversations[idx].messages.isEmpty {
            let lastIdx = conversations[idx].messages.count - 1
            conversations[idx].messages[lastIdx].isStreaming = false
        }
        persistVault()
    }

    private func streamAssistantResponse(forConversationAt convIndex: Int) {
        streamTask?.cancel()
        isGeneratingReply = true
        activeErrorBanner = nil

        let convID = conversations[convIndex].id
        let model = conversations[convIndex].selectedModel
        let dials = conversations[convIndex].dials
        let historySnapshot = conversations[convIndex].messages
        let baseURL = serverConfig.baseURLString

        let placeholder = ChatMessage(
            role: .assistant,
            content: "",
            thinkingContent: "",
            modelUsed: model,
            isStreaming: true
        )
        conversations[convIndex].messages.append(placeholder)
        let assistantMsgID = placeholder.id

        streamTask = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            var thinkingEndRecorded = false

            do {
                let stream = client.streamChat(
                    baseURL: baseURL,
                    model: model,
                    messages: historySnapshot,
                    dials: dials
                )

                for try await event in stream {
                    guard let cIdx = conversations.firstIndex(where: { $0.id == convID }),
                          let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == assistantMsgID }) else {
                        break
                    }

                    if !event.thinkingDelta.isEmpty {
                        conversations[cIdx].messages[mIdx].thinkingContent += event.thinkingDelta
                    }
                    if !event.contentDelta.isEmpty {
                        if !thinkingEndRecorded && !conversations[cIdx].messages[mIdx].thinkingContent.isEmpty {
                            conversations[cIdx].messages[mIdx].thinkingDurationSeconds = CFAbsoluteTimeGetCurrent() - startTime
                            thinkingEndRecorded = true
                        }
                        conversations[cIdx].messages[mIdx].content += event.contentDelta
                    }
                    if let tps = event.tokensPerSecond {
                        conversations[cIdx].messages[mIdx].tokensPerSecond = tps
                    }
                    if let ttft = event.timeToFirstTokenMs {
                        conversations[cIdx].messages[mIdx].timeToFirstTokenMs = ttft
                    }
                    if let pCount = event.promptEvalCount {
                        conversations[cIdx].messages[mIdx].promptEvalTokens = pCount
                    }
                    if let cCount = event.evalCount {
                        conversations[cIdx].messages[mIdx].completionTokens = cCount
                    }
                    if event.isDone {
                        conversations[cIdx].messages[mIdx].isStreaming = false
                    }
                }

                if let cIdx = conversations.firstIndex(where: { $0.id == convID }),
                   let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == assistantMsgID }) {
                    conversations[cIdx].messages[mIdx].isStreaming = false
                }
                isGeneratingReply = false
                persistVault()
                await refreshEngineStatus()
            } catch {
                if !Task.isCancelled {
                    if let cIdx = conversations.firstIndex(where: { $0.id == convID }),
                       let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == assistantMsgID }),
                       conversations[cIdx].messages[mIdx].content.isEmpty {
                        conversations[cIdx].messages.remove(at: mIdx)
                    }
                    activeErrorBanner = HumanFriendlyError.translate(error, endpoint: "/api/chat", model: model)
                }
                isGeneratingReply = false
                persistVault()
            }
        }
    }

    // MARK: - Local File & Image Attachment Reader

    public func loadAttachment(from url: URL) -> ChatAttachment? {
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "gif"]
        if imageExtensions.contains(ext), let data = try? Data(contentsOf: url) {
            return ChatAttachment(
                fileName: fileName,
                kind: .image,
                fileSizeBytes: fileSize,
                base64ImagePayload: data.base64EncodedString()
            )
        }

        if ext == "pdf", let pdf = PDFDocument(url: url) {
            var fullText = ""
            for i in 0..<pdf.pageCount {
                if let pageText = pdf.page(at: i)?.string {
                    fullText += pageText + "\n"
                }
            }
            return ChatAttachment(
                fileName: fileName,
                kind: .document,
                fileSizeBytes: fileSize,
                extractedDocumentText: String(fullText.prefix(120_000))
            )
        }

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return ChatAttachment(
                fileName: fileName,
                kind: .document,
                fileSizeBytes: fileSize,
                extractedDocumentText: String(text.prefix(120_000))
            )
        }

        return nil
    }

    // MARK: - Model RAM Residency, Hugging Face Pulls & Inspection

    public func prewarmModelIntoRAM(_ modelName: String, keepAlive: String = "15m") {
        Task {
            do {
                try await client.setModelResidency(baseURL: serverConfig.baseURLString, modelName: modelName, keepAlive: keepAlive)
                await refreshEngineStatus()
            } catch {
                activeErrorBanner = HumanFriendlyError.translate(error, endpoint: "/api/generate", model: modelName)
            }
        }
    }

    public func ejectModelFromRAM(_ modelName: String) {
        Task {
            do {
                try await client.setModelResidency(baseURL: serverConfig.baseURLString, modelName: modelName, keepAlive: 0)
                await refreshEngineStatus()
            } catch {
                activeErrorBanner = HumanFriendlyError.translate(error, endpoint: "/api/generate", model: modelName)
            }
        }
    }

    public func inspectModel(_ modelName: String) {
        inspectedModelName = modelName
        inspectedModelInfo = nil
        Task {
            do {
                let info = try await client.fetchModelShowInfo(baseURL: serverConfig.baseURLString, modelName: modelName)
                self.inspectedModelInfo = info
            } catch {
                activeErrorBanner = HumanFriendlyError.translate(error, endpoint: "/api/show", model: modelName)
            }
        }
    }

    /// Normalizes a raw Hugging Face URL or repo ID into Ollama's native `hf.co/user/repo` pull format
    public static func normalizeModelOrHuggingFaceInput(_ rawInput: String) -> String {
        var cleaned = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("ollama run ") {
            cleaned = String(cleaned.dropFirst("ollama run ".count)).trimmingCharacters(in: .whitespaces)
        } else if cleaned.hasPrefix("ollama pull ") {
            cleaned = String(cleaned.dropFirst("ollama pull ".count)).trimmingCharacters(in: .whitespaces)
        }
        if cleaned.hasPrefix("https://huggingface.co/") {
            cleaned = cleaned.replacingOccurrences(of: "https://huggingface.co/", with: "hf.co/")
        } else if cleaned.hasPrefix("http://huggingface.co/") {
            cleaned = cleaned.replacingOccurrences(of: "http://huggingface.co/", with: "hf.co/")
        } else if cleaned.hasPrefix("huggingface.co/") {
            cleaned = cleaned.replacingOccurrences(of: "huggingface.co/", with: "hf.co/")
        }
        // Strip `/blob/main/...` or `/resolve/main/...` if a user pasted a file link from Hugging Face
        if cleaned.hasPrefix("hf.co/"), let range = cleaned.range(of: "/blob/") ?? cleaned.range(of: "/resolve/") ?? cleaned.range(of: "/tree/") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        return cleaned
    }

    public func startOrResumeModelPull(rawIdentifier: String) {
        let identifier = Self.normalizeModelOrHuggingFaceInput(rawIdentifier)
        guard !identifier.isEmpty else { return }

        if let existingIdx = activePullTasks.firstIndex(where: { $0.id == identifier }) {
            activePullTasks[existingIdx].isPaused = false
            activePullTasks[existingIdx].errorMessage = nil
            activePullTasks[existingIdx].statusText = "Resuming download..."
        } else {
            activePullTasks.insert(
                ModelPullTask(
                    id: identifier,
                    statusText: "Connecting to registry...",
                    completedBytes: 0,
                    totalBytes: 0,
                    speedBytesPerSec: 0,
                    isPaused: false,
                    errorMessage: nil
                ),
                at: 0
            )
        }

        pullTasksMap[identifier]?.cancel()
        let baseURL = serverConfig.baseURLString

        pullTasksMap[identifier] = Task {
            var lastByteTimestamp = CFAbsoluteTimeGetCurrent()
            var lastCompletedBytes: Int64 = 0

            do {
                for try await event in client.streamPullModel(baseURL: baseURL, modelIdentifier: identifier) {
                    guard let idx = activePullTasks.firstIndex(where: { $0.id == identifier }) else { break }
                    let now = CFAbsoluteTimeGetCurrent()
                    let dt = now - lastByteTimestamp
                    if dt >= 0.4 && event.completed > lastCompletedBytes {
                        let speed = Double(event.completed - lastCompletedBytes) / dt
                        activePullTasks[idx].speedBytesPerSec = speed
                        lastByteTimestamp = now
                        lastCompletedBytes = event.completed
                    }
                    activePullTasks[idx].statusText = event.status
                    if event.total > 0 {
                        activePullTasks[idx].totalBytes = event.total
                        activePullTasks[idx].completedBytes = event.completed
                    }
                }
                activePullTasks.removeAll(where: { $0.id == identifier })
                await refreshEngineStatus()
            } catch {
                if !Task.isCancelled, let idx = activePullTasks.firstIndex(where: { $0.id == identifier }) {
                    activePullTasks[idx].errorMessage = error.localizedDescription
                    activePullTasks[idx].statusText = "Paused — click Resume to continue"
                    activePullTasks[idx].isPaused = true
                }
            }
        }
    }

    public func pauseModelPull(identifier: String) {
        pullTasksMap[identifier]?.cancel()
        pullTasksMap[identifier] = nil
        if let idx = activePullTasks.firstIndex(where: { $0.id == identifier }) {
            activePullTasks[idx].isPaused = true
            activePullTasks[idx].speedBytesPerSec = 0
            activePullTasks[idx].statusText = "Paused (layers cached on disk)"
        }
    }

    // MARK: - Save Current Chat Settings as Reusable Model

    public func loadActiveChatIntoModelBuilder() {
        guard let conv = activeConversation else { return }
        builderDraft = ModelBuilderSpec()
        builderDraft.baseModelOrGGUFPath = conv.selectedModel.isEmpty ? (installedModels.first?.name ?? "llama3.2:latest") : conv.selectedModel
        builderDraft.systemPrompt = conv.dials.systemPrompt
        builderDraft.dials = conv.dials
        builderDraft.newModelName = "\(conv.selectedModel.components(separatedBy: ":").first ?? "custom")-studio:latest"
        selectedTab = .modelBuilder
    }

    public func buildCustomModelFromDraft() {
        let trimmedName = builderDraft.newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isBuildingModel = true
        builderStatusLog = "Packaging model '\(trimmedName)'..."
        storage.createAutomaticSnapshot()

        Task {
            do {
                if builderDraft.isLocalGGUFFile || !builderDraft.adapterLoRAPath.isEmpty {
                    try await processManager.buildModelViaCLI(spec: builderDraft, config: serverConfig)
                    builderStatusLog = "Successfully built '\(trimmedName)' via local Modelfile."
                } else {
                    for try await status in client.createCustomModel(baseURL: serverConfig.baseURLString, spec: builderDraft) {
                        builderStatusLog = status
                    }
                    builderStatusLog = "Successfully created '\(trimmedName)'."
                }
                isBuildingModel = false
                await refreshEngineStatus()
            } catch {
                isBuildingModel = false
                builderStatusLog = "Build failed: \(error.localizedDescription)"
                activeErrorBanner = HumanFriendlyError.translate(error, endpoint: "/api/create", model: trimmedName)
            }
        }
    }
}
