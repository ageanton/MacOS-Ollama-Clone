import Foundation

public enum MessageRole: String, Codable, Equatable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public var thinkingContent: String
    public var isThinkingExpanded: Bool
    public var thinkingDurationSeconds: Double?
    public var modelUsed: String?
    public var tokensPerSecond: Double?
    public var timeToFirstTokenMs: Double?
    public var completionTokens: Int?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String = "",
        isThinkingExpanded: Bool = false,
        thinkingDurationSeconds: Double? = nil,
        modelUsed: String? = nil,
        tokensPerSecond: Double? = nil,
        timeToFirstTokenMs: Double? = nil,
        completionTokens: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.isThinkingExpanded = isThinkingExpanded
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.modelUsed = modelUsed
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.completionTokens = completionTokens
        self.createdAt = createdAt
    }

    public var estimatedTokens: Int {
        max(1, (content.count + thinkingContent.count) / 4)
    }
}

public struct Conversation: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var selectedModel: String
    public var messages: [ChatMessage]
    public var dials: SamplingDials
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        selectedModel: String = "",
        messages: [ChatMessage] = [],
        dials: SamplingDials = SamplingDials(),
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.selectedModel = selectedModel
        self.messages = messages
        self.dials = dials
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var totalTokens: Int {
        messages.reduce(0) { $0 + $1.estimatedTokens }
    }
}
