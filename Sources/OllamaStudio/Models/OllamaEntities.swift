import Foundation

// MARK: - Installed & Running Models (`/api/tags`, `/api/ps`, `/api/show`)

public struct OllamaModelSummary: Codable, Identifiable, Equatable, Hashable {
    public var id: String { name }
    public let name: String
    public let model: String?
    public let modifiedAt: String?
    public let size: Int64
    public let digest: String
    public let details: ModelDetails?

    enum CodingKeys: String, CodingKey {
        case name, model
        case modifiedAt = "modified_at"
        case size, digest, details
    }

    public struct ModelDetails: Codable, Equatable, Hashable {
        public let parentModel: String?
        public let format: String?
        public let family: String?
        public let families: [String]?
        public let parameterSize: String?
        public let quantizationLevel: String?

        enum CodingKeys: String, CodingKey {
            case parentModel = "parent_model"
            case format, family, families
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }

    public var formattedSize: String {
        let gb = Double(size) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(size) / 1_048_576.0
            return String(format: "%.0f MB", mb)
        }
    }

    public var shortCleanName: String {
        name.replacingOccurrences(of: ":latest", with: "")
    }

    public var isLikelyVisionModel: Bool {
        let lower = name.lowercased()
        let fam = (details?.families ?? []).joined(separator: " ").lowercased()
        return lower.contains("vision") || lower.contains("llava") || lower.contains("vl")
            || lower.contains("minicpm") || lower.contains("pixtral") || lower.contains("gemma3")
            || lower.contains("gemma4") || fam.contains("clip") || fam.contains("mllama")
    }

    public var isLikelyReasoningModel: Bool {
        let lower = name.lowercased()
        return lower.contains("deepseek-r1") || lower.contains("qwq") || lower.contains("qwen3")
            || lower.contains("r1") || lower.contains("think") || lower.contains("Marco-o1")
            || lower.contains("gpt-oss")
    }
}

public struct RunningModelProcess: Codable, Identifiable, Equatable {
    public var id: String { name }
    public let name: String
    public let model: String?
    public let size: Int64
    public let sizeVram: Int64
    public let digest: String?
    public let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case name, model, size
        case sizeVram = "size_vram"
        case digest
        case expiresAt = "expires_at"
    }

    public var formattedVRAM: String {
        let gb = Double(max(size, sizeVram)) / 1_073_741_824.0
        return String(format: "%.1f GB in RAM", gb)
    }

    public var metalOffloadPercentage: Int {
        guard size > 0 else { return 100 }
        let ratio = Double(sizeVram) / Double(size)
        return min(100, max(0, Int(round(ratio * 100))))
    }
}

/// Complete inspection response from `POST /api/show` (replaces all `/show` CLI commands)
public struct OllamaModelShowInfo: Codable, Equatable {
    public let modelfile: String?
    public let parameters: String?
    public let template: String?
    public let system: String?
    public let license: String?
    public let capabilities: [String]?
    public let details: OllamaModelSummary.ModelDetails?
    public let modelInfo: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case modelfile, parameters, template, system, license, capabilities, details
        case modelInfo = "model_info"
    }

    public var maxContextLengthFromMetadata: Int? {
        guard let info = modelInfo else { return nil }
        for (key, value) in info where key.hasSuffix(".context_length") {
            if let intVal = value.intValue { return intVal }
        }
        return nil
    }

    public var supportsVision: Bool {
        if let caps = capabilities, caps.contains("vision") { return true }
        if let info = modelInfo {
            return info.keys.contains(where: { $0.contains("vision") || $0.contains("projector") })
        }
        return false
    }

    public var supportsThinking: Bool {
        if let caps = capabilities, caps.contains("thinking") { return true }
        return false
    }
}

public enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case null

    public var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.3f", d)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return a.map(\.displayString).joined(separator: ", ")
        case .null: return "—"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([AnyCodableValue].self) { self = .array(a); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Chat Attachments (Vision Images + Local Document RAG)

public struct ChatAttachment: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let fileName: String
    public let kind: AttachmentKind
    public let fileSizeBytes: Int64
    /// Base64 raw image bytes (without data: URL prefix) for `/api/chat` `images` array
    public let base64ImagePayload: String?
    /// Extracted plain text for local PDF, Markdown, Code, CSV, or TXT files
    public let extractedDocumentText: String?

    public enum AttachmentKind: String, Codable {
        case image = "image"
        case document = "document"
    }

    public init(
        id: UUID = UUID(),
        fileName: String,
        kind: AttachmentKind,
        fileSizeBytes: Int64,
        base64ImagePayload: String? = nil,
        extractedDocumentText: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.fileSizeBytes = fileSizeBytes
        self.base64ImagePayload = base64ImagePayload
        self.extractedDocumentText = extractedDocumentText
    }
}

// MARK: - Conversation & Message Entities

public enum MessageRole: String, Codable, CaseIterable {
    case system = "system"
    case user = "user"
    case assistant = "assistant"
}

public struct ChatMessage: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public var thinkingContent: String
    public var thinkingDurationSeconds: Double?
    public var attachments: [ChatAttachment]
    public var createdAt: Date
    public var modelUsed: String?
    public var tokensPerSecond: Double?
    public var timeToFirstTokenMs: Double?
    public var promptEvalTokens: Int?
    public var completionTokens: Int?
    public var isStreaming: Bool

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String = "",
        thinkingDurationSeconds: Double? = nil,
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        modelUsed: String? = nil,
        tokensPerSecond: Double? = nil,
        timeToFirstTokenMs: Double? = nil,
        promptEvalTokens: Int? = nil,
        completionTokens: Int? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.thinkingDurationSeconds = thinkingDurationSeconds
        self.attachments = attachments
        self.createdAt = createdAt
        self.modelUsed = modelUsed
        self.tokensPerSecond = tokensPerSecond
        self.timeToFirstTokenMs = timeToFirstTokenMs
        self.promptEvalTokens = promptEvalTokens
        self.completionTokens = completionTokens
        self.isStreaming = isStreaming
    }

    /// Estimated token count for the context meter (~4 chars per token + image token budget)
    public var estimatedTokenCount: Int {
        let textTokens = max(1, (content.count + thinkingContent.count) / 4)
        let docTokens = attachments.compactMap(\.extractedDocumentText).reduce(0) { $0 + ($1.count / 4) }
        let imageTokens = attachments.filter { $0.kind == .image }.count * 768
        return textTokens + docTokens + imageTokens
    }
}

public struct Conversation: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var selectedModel: String
    public var messages: [ChatMessage]
    public var dials: ModelDials
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        selectedModel: String = "",
        messages: [ChatMessage] = [],
        dials: ModelDials = ModelDials(),
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

    public var totalEstimatedTokensUsed: Int {
        let systemTokens = dials.systemPrompt.isEmpty ? 0 : max(1, dials.systemPrompt.count / 4)
        return systemTokens + messages.reduce(0) { $0 + $1.estimatedTokenCount }
    }

    public var contextFillFraction: Double {
        guard dials.numCtx > 0 else { return 0 }
        return min(1.0, Double(totalEstimatedTokensUsed) / Double(dials.numCtx))
    }
}

// MARK: - Visual Model Builder Draft & Presets

public struct ExampleDialogueTurn: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID = UUID()
    public var role: MessageRole
    public var content: String

    public init(id: UUID = UUID(), role: MessageRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

public struct ModelBuilderSpec: Codable, Equatable {
    public var newModelName: String = ""
    public var baseModelOrGGUFPath: String = ""
    public var isLocalGGUFFile: Bool = false
    public var systemPrompt: String = ""
    public var dials: ModelDials = ModelDials()
    public var exampleDialogue: [ExampleDialogueTurn] = []
    public var customTemplate: String = ""
    public var adapterLoRAPath: String = ""
    public var licenseText: String = ""
    public var quantizeLevel: String = "" // "", "q4_K_M", "q8_0"

    public init() {}

    /// Generates clean, human-readable Modelfile syntax for live preview & CLI fallback
    public func renderedModelfilePreview() -> String {
        var lines: [String] = []
        let base = baseModelOrGGUFPath.isEmpty ? "llama3.2:latest" : baseModelOrGGUFPath
        lines.append("# Generated by Ollama Studio Visual Model Builder")
        lines.append("FROM \(base)")
        lines.append("")

        if !adapterLoRAPath.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("ADAPTER \(adapterLoRAPath.trimmingCharacters(in: .whitespaces))")
            lines.append("")
        }

        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("SYSTEM \"\"\"")
            lines.append(systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("\"\"\"")
            lines.append("")
        }

        lines.append("PARAMETER temperature \(String(format: "%.2f", dials.temperature))")
        lines.append("PARAMETER top_k \(dials.topK)")
        lines.append("PARAMETER top_p \(String(format: "%.2f", dials.topP))")
        if dials.minP > 0 {
            lines.append("PARAMETER min_p \(String(format: "%.2f", dials.minP))")
        }
        lines.append("PARAMETER repeat_penalty \(String(format: "%.2f", dials.repeatPenalty))")
        lines.append("PARAMETER repeat_last_n \(dials.repeatLastN)")
        lines.append("PARAMETER num_ctx \(dials.numCtx)")
        if dials.seed >= 0 {
            lines.append("PARAMETER seed \(dials.seed)")
        }
        for stop in dials.stopSequences where !stop.isEmpty {
            lines.append("PARAMETER stop \"\(stop)\"")
        }
        lines.append("")

        if !customTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("TEMPLATE \"\"\"")
            lines.append(customTemplate.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("\"\"\"")
            lines.append("")
        }

        for turn in exampleDialogue where !turn.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("MESSAGE \(turn.role.rawValue) \"\"\"")
            lines.append(turn.content.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("\"\"\"")
        }

        if !licenseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("LICENSE \"\"\"")
            lines.append(licenseText.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("\"\"\"")
        }

        return lines.joined(separator: "\n")
    }
}

public struct PersonaPreset: Identifiable {
    public let id: String
    public let title: String
    public let category: String
    public let summary: String
    public let systemPrompt: String
    public let recommendedTemperature: Double
    public let recommendedCtx: Int
    public let sampleTurns: [ExampleDialogueTurn]

    public static let library: [PersonaPreset] = [
        PersonaPreset(
            id: "clear_editor",
            title: "Executive Writing Editor",
            category: "Writing",
            summary: "Tightens prose, removes fluff, and preserves your natural voice without sounding like AI.",
            systemPrompt: "You are a seasoned literary and executive editor. Rewrite or critique the user's draft for clarity, rhythm, and conciseness. Never use cliches like 'delve', 'tapestry', or 'testament'. Preserve the author's intent and tone.",
            recommendedTemperature: 0.45,
            recommendedCtx: 16384,
            sampleTurns: [
                ExampleDialogueTurn(role: .user, content: "We are leveraging synergistic paradigms to facilitate onboarding."),
                ExampleDialogueTurn(role: .assistant, content: "We simplified how new team members get started.")
            ]
        ),
        PersonaPreset(
            id: "staff_architect",
            title: "Principal Systems Engineer",
            category: "Engineering",
            summary: "Writes production-grade, defensive code with zero placeholders and clear tradeoff notes.",
            systemPrompt: "You are a Principal Systems Engineer. Provide complete, idiomatic, production-ready code with full error handling. Explain architectural trade-offs concisely before the code.",
            recommendedTemperature: 0.15,
            recommendedCtx: 32768,
            sampleTurns: []
        ),
        PersonaPreset(
            id: "socratic_tutor",
            title: "First-Principles Tutor",
            category: "Learning",
            summary: "Explains complex topics in plain English using concrete analogies before introducing jargon.",
            systemPrompt: "Explain complex concepts from first principles in plain, vivid English. Start with a concrete real-world mechanism before introducing any technical terminology or equations.",
            recommendedTemperature: 0.6,
            recommendedCtx: 8192,
            sampleTurns: []
        ),
        PersonaPreset(
            id: "private_analyst",
            title: "Contract & Document Analyst",
            category: "Research",
            summary: "Extracts exact clauses, risks, dates, and action items from attached local documents.",
            systemPrompt: "You are a meticulous document analyst. Base every claim strictly on the provided text. Flag ambiguous clauses, financial obligations, deadlines, and missing protections clearly.",
            recommendedTemperature: 0.1,
            recommendedCtx: 32768,
            sampleTurns: []
        )
    ]
}

// MARK: - Resumable Download / Pull Task State

public struct ModelPullTask: Identifiable, Equatable {
    public let id: String               // Model name or Hugging Face repo e.g. `hf.co/bartowski/...`
    public var statusText: String
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var speedBytesPerSec: Double
    public var isPaused: Bool
    public var errorMessage: String?

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, Double(completedBytes) / Double(totalBytes))
    }

    public var formattedProgress: String {
        guard totalBytes > 0 else { return statusText }
        let doneGB = Double(completedBytes) / 1_073_741_824.0
        let totalGB = Double(totalBytes) / 1_073_741_824.0
        let speedMB = speedBytesPerSec / 1_048_576.0
        if speedMB > 0.1 {
            return String(format: "%.2f / %.2f GB · %.1f MB/s", doneGB, totalGB, speedMB)
        }
        return String(format: "%.2f / %.2f GB", doneGB, totalGB)
    }
}

// MARK: - Non-Destructive Trash / Undo Item

public struct TrashedEntity: Codable, Identifiable, Equatable {
    public let id: UUID
    public let deletedAt: Date
    public let summaryTitle: String
    public let payload: Payload

    public enum Payload: Codable, Equatable {
        case conversation(Conversation)
        case customModelBackup(name: String, spec: ModelBuilderSpec)
    }
}
