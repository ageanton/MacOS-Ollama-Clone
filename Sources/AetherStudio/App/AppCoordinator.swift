import SwiftUI
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case externalDrive = "Storage & Drives"
    case engine = "Engine Config"
    case appearance = "Appearance"

    public var id: String { rawValue }
}

@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public var conversations: [Conversation] = []
    @Published public var activeConversationID: UUID?
    @Published public var searchQuery: String = ""

    @Published public var installedModels: [OllamaModel] = []
    @Published public var runningModels: [RunningModelProcess] = []
    @Published public var isEngineOnline: Bool = false
    @Published public var engineVersion: String = "Connecting..."
    @Published public var externalStatus: ExternalVolumeStatus

    @Published public var storageConfig: StorageConfig
    @Published public var modelDefaults: [String: SamplingDials] = [:]

    @Published public var isGenerating: Bool = false
    @Published public var isSettingsOpen: Bool = false
    @Published public var isDialsOpen: Bool = false
    @Published public var selectedSettingsTab: SettingsTab = .externalDrive
    @Published public var statusToast: String?

    public let client = OllamaClient()
    public let supervisor = ProcessSupervisor()
    public let driveManager = ExternalDriveManager()
    public let hardware = HardwareMonitor()

    private var heartbeatTimer: Timer?
    private var activeStreamTask: Task<Void, Never>?

    public init() {
        let initialConfig = StorageConfig()
        self.storageConfig = initialConfig
        self.externalStatus = initialConfig.inspectStorageDriveStatus()

        loadVault()
        startLifecycle()
    }

    public var activeConversation: Conversation? {
        guard let id = activeConversationID else { return conversations.first }
        return conversations.first(where: { $0.id == id }) ?? conversations.first
    }

    public var filteredConversations: [Conversation] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = conversations.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return a.updatedAt > b.updatedAt
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.title.lowercased().contains(q) || $0.messages.contains(where: { $0.content.lowercased().contains(q) }) }
    }

    private func startLifecycle() {
        Task {
            // Apply external drive symlink automatically if using external drive
            if storageConfig.isUsingExternalDrive {
                driveManager.linkDefaultOllamaDirectoryToExternalDrive(targetPath: storageConfig.modelsDirectoryPath)
            }
            await refreshEngine()
            if !isEngineOnline {
                supervisor.startEngine(config: storageConfig)
                try? await Task.sleep(nanoseconds: 800_000_000)
                await refreshEngine()
            }
            await driveManager.scanForGGUFFiles(in: storageConfig.modelsDirectoryPath)
        }

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.externalStatus = self.storageConfig.inspectStorageDriveStatus()
                await self.refreshEngine()
            }
        }
    }

    public func refreshEngine() async {
        let baseURL = storageConfig.baseURLString
        do {
            self.engineVersion = try await client.fetchVersion(baseURL: baseURL)
            self.installedModels = try await client.fetchInstalledModels(baseURL: baseURL)
            self.runningModels = try await client.fetchRunningModels(baseURL: baseURL)
            self.isEngineOnline = true

            // Auto-select first model if none set
            if let first = installedModels.first?.name {
                for i in conversations.indices where conversations[i].selectedModel.isEmpty {
                    conversations[i].selectedModel = first
                }
            }
        } catch {
            self.isEngineOnline = false
            self.engineVersion = "Offline"
        }
    }

    public func applyCustomModelsPath(_ path: String) {
        storageConfig.updateModelsPath(path)
        externalStatus = storageConfig.inspectStorageDriveStatus()

        // Link ~/.ollama/models to the selected path
        let result = driveManager.linkDefaultOllamaDirectoryToExternalDrive(targetPath: path)
        statusToast = result.message

        Task {
            await supervisor.restartEngine(config: storageConfig)
            await refreshEngine()
            await driveManager.scanForGGUFFiles(in: path)
        }
    }

    public func importRawGGUF(_ gguf: DiscoveredGGUF) {
        guard let binary = supervisor.detectedBinaryPath ?? ProcessSupervisor.locateBinary() else {
            statusToast = "Cannot locate 'ollama' binary to import GGUF."
            return
        }

        Task {
            do {
                statusToast = "Importing \(gguf.fileName)..."
                try await driveManager.importGGUFFile(gguf: gguf, binaryPath: binary, config: storageConfig)
                await refreshEngine()
                selectModelForActiveConversation(gguf.cleanTag)
                statusToast = "Successfully imported \(gguf.cleanTag)"
            } catch {
                statusToast = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    public func selectModelForActiveConversation(_ modelName: String) {
        guard let id = activeConversation?.id,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].selectedModel = modelName
        if let defaults = modelDefaults[modelName] {
            conversations[idx].dials = defaults
        }
        persistVault()
    }

    public func newConversation() {
        let defaultModel = activeConversation?.selectedModel ?? installedModels.first?.name ?? ""
        var conv = Conversation(selectedModel: defaultModel)
        if let savedDials = modelDefaults[defaultModel] {
            conv.dials = savedDials
        }
        conversations.insert(conv, at: 0)
        activeConversationID = conv.id
        persistVault()
    }

    public func deleteConversation(id: UUID) {
        conversations.removeAll(where: { $0.id == id })
        if activeConversationID == id {
            activeConversationID = conversations.first?.id
        }
        persistVault()
    }

    public func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let id = activeConversation?.id,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }

        let userMsg = ChatMessage(role: .user, content: trimmed)
        conversations[idx].messages.append(userMsg)
        if conversations[idx].messages.count == 1 {
            conversations[idx].title = String(trimmed.prefix(44))
        }
        conversations[idx].updatedAt = Date()
        persistVault()

        let model = conversations[idx].selectedModel
        guard !model.isEmpty else {
            isSettingsOpen = true
            selectedSettingsTab = .externalDrive
            return
        }

        let assistantMsg = ChatMessage(role: .assistant, content: "", modelUsed: model)
        conversations[idx].messages.append(assistantMsg)
        let assistantMsgID = assistantMsg.id

        isGenerating = true
        let messagesToSend = conversations[idx].messages.dropLast() // exclude empty assistant msg
        let dials = conversations[idx].dials
        let baseURL = storageConfig.baseURLString

        activeStreamTask = Task {
            let start = Date()
            var tokenCount = 0
            var firstTokenMs: Double?

            do {
                let stream = await client.streamChat(
                    baseURL: baseURL,
                    modelName: model,
                    messages: Array(messagesToSend),
                    dials: dials
                )

                for try await chunk in stream {
                    guard !Task.isCancelled else { break }

                    if firstTokenMs == nil && (!chunk.textDelta.isEmpty || !chunk.thinkingDelta.isEmpty) {
                        firstTokenMs = Date().timeIntervalSince(start) * 1000.0
                    }

                    if let cIdx = conversations.firstIndex(where: { $0.id == id }),
                       let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == assistantMsgID }) {
                        conversations[cIdx].messages[mIdx].content += chunk.textDelta
                        conversations[cIdx].messages[mIdx].thinkingContent += chunk.thinkingDelta
                        tokenCount += 1
                    }
                }

                let elapsed = max(0.001, Date().timeIntervalSince(start))
                let tps = Double(tokenCount) / elapsed

                if let cIdx = conversations.firstIndex(where: { $0.id == id }),
                   let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == assistantMsgID }) {
                    conversations[cIdx].messages[mIdx].tokensPerSecond = round(tps * 10) / 10
                    conversations[cIdx].messages[mIdx].timeToFirstTokenMs = firstTokenMs
                    conversations[cIdx].messages[mIdx].completionTokens = tokenCount
                    conversations[cIdx].updatedAt = Date()
                }
            } catch {
                if let cIdx = conversations.firstIndex(where: { $0.id == id }),
                   let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == assistantMsgID }) {
                    if conversations[cIdx].messages[mIdx].content.isEmpty {
                        conversations[cIdx].messages[mIdx].content = "Error communicating with Ollama: \(error.localizedDescription)"
                    }
                }
            }
            self.isGenerating = false
            self.persistVault()
        }
    }

    public func stopGeneration() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isGenerating = false
        persistVault()
    }

    private func loadVault() {
        let vault = VaultStorage.shared.loadVault()
        self.conversations = vault.conversations
        self.modelDefaults = vault.modelDefaults
        if conversations.isEmpty {
            newConversation()
        } else {
            activeConversationID = conversations.first?.id
        }
    }

    public func persistVault() {
        let vault = PersistedVault(conversations: conversations, modelDefaults: modelDefaults)
        VaultStorage.shared.saveVault(vault)
    }
}
