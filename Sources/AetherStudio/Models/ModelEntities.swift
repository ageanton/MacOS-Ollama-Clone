import Foundation

public struct OllamaModel: Identifiable, Codable, Equatable, Hashable {
    public var id: String { name }
    public let name: String
    public let model: String?
    public let modifiedAt: String?
    public let size: Int64
    public let digest: String?
    public let details: OllamaModelDetails?

    public init(
        name: String,
        model: String? = nil,
        modifiedAt: String? = nil,
        size: Int64 = 0,
        digest: String? = nil,
        details: OllamaModelDetails? = nil
    ) {
        self.name = name
        self.model = model
        self.modifiedAt = modifiedAt
        self.size = size
        self.digest = digest
        self.details = details
    }

    public var cleanDisplayName: String {
        name.replacingOccurrences(of: ":latest", with: "")
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

    public var quantizationText: String {
        details?.quantizationLevel ?? "Q4_K_M"
    }

    public var parameterSizeText: String {
        details?.parameterSize ?? ""
    }

    public var heuristicThinkingProfile: ThinkingProfile {
        let lower = name.lowercased()
        if lower.contains("deepseek-r1") || lower.contains("qwq") || lower.contains("reasoning") {
            return .alwaysOn
        }
        if lower.contains("qwen2.5") || lower.contains("llama-3.2") || lower.contains("phi-4") || lower.contains("mistral") {
            return .toggleable
        }
        return .none
    }
}

public struct OllamaModelDetails: Codable, Equatable, Hashable {
    public let parentModel: String?
    public let format: String?
    public let family: String?
    public let families: [String]?
    public let parameterSize: String?
    public let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case parentModel = "parent_model"
        case format
        case family
        case families
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

public struct DiscoveredGGUF: Identifiable, Equatable, Hashable {
    public var id: String { fullPath }
    public let fileName: String
    public let fullPath: String
    public let fileSizeBytes: Int64
    public let volumeName: String

    public init(fileName: String, fullPath: String, fileSizeBytes: Int64, volumeName: String) {
        self.fileName = fileName
        self.fullPath = fullPath
        self.fileSizeBytes = fileSizeBytes
        self.volumeName = volumeName
    }

    public var formattedSize: String {
        String(format: "%.1f GB", Double(fileSizeBytes) / 1_073_741_824.0)
    }

    /// Generates a clean, valid Ollama model tag for `ollama create`
    public var cleanTag: String {
        let rawBase = (fileName as NSString).deletingPathExtension.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleanChars = rawBase.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(cleanChars)
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "custom-model:latest" : "\(result):latest"
    }
}

public struct RunningModelProcess: Identifiable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let model: String?
    public let size: Int64
    public let sizeVram: Int64?
    public let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case name, model, size
        case sizeVram = "size_vram"
        case expiresAt = "expires_at"
    }

    public var formattedVRAM: String {
        let bytes = sizeVram ?? size
        return String(format: "%.1f GB Unified RAM", Double(bytes) / 1_073_741_824.0)
    }
}

public enum ThinkingProfile: String, Codable, Equatable {
    case none
    case toggleable
    case alwaysOn
    case effortLevels
}

public enum ThinkingMode: String, CaseIterable, Codable, Identifiable {
    case modelDefault = "default"
    case enabled = "true"
    case disabled = "false"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .modelDefault: return "Default"
        case .enabled: return "Thinking On"
        case .disabled: return "Thinking Off (Direct)"
        }
    }
}
