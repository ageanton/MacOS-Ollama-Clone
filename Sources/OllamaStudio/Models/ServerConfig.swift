import Foundation

// MARK: - KV Cache Quantization Type (`OLLAMA_KV_CACHE_TYPE`)

public enum KVCacheQuantizationType: String, CaseIterable, Codable, Identifiable {
    case f16 = "f16"
    case q8_0 = "q8_0"
    case q4_0 = "q4_0"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .f16: return "16-Bit Full Precision (f16)"
        case .q8_0: return "8-Bit Balanced Compression (q8_0)"
        case .q4_0: return "4-Bit Maximum Compression (q4_0)"
        }
    }

    public var plainEnglishImpact: String {
        switch self {
        case .f16:
            return "Standard uncompressed memory cache. Uses the most RAM on long conversations."
        case .q8_0:
            return "Cuts conversation memory (KV cache) RAM usage in half with virtually zero loss in answer quality. Recommended for Apple Silicon."
        case .q4_0:
            return "Shrinks conversation memory RAM to 25% of normal so you can fit 64k+ context windows, with a slight trade-off in nuance."
        }
    }

    public var memoryMultiplier: Double {
        switch self {
        case .f16: return 1.0
        case .q8_0: return 0.52
        case .q4_0: return 0.28
        }
    }
}

// MARK: - Complete Server Configuration (100% Parity with Ollama Environment Variables)

public struct ServerConfig: Codable, Equatable {
    public var hostAddress: String = "127.0.0.1"
    public var port: Int = 11434
    public var allowedOrigins: String = "http://localhost:*,http://127.0.0.1:*,app://obsidian.md,vscode-webview://*"
    public var modelsDirectoryPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ollama/models"
    }()
    public var defaultKeepAlive: String = "5m"
    public var loadTimeout: String = "5m"
    public var numParallel: Int = 1
    public var maxLoadedModels: Int = 1
    public var maxQueue: Int = 512
    public var defaultContextLength: Int = 8192
    public var maxTransferStreams: Int = 4
    public var flashAttentionEnabled: Bool = true
    public var kvCacheType: KVCacheQuantizationType = .q8_0
    public var spreadAcrossGPUs: Bool = false
    public var debugLogging: Bool = false
    public var disableReadlineHistory: Bool = true
    public var exposeOnLocalNetwork: Bool = false

    public init() {}

    public var baseURLString: String {
        let connectHost = (hostAddress == "0.0.0.0" || hostAddress.isEmpty) ? "127.0.0.1" : hostAddress
        return "http://\(connectHost):\(port)"
    }

    /// Enforces Ollama's technical requirement that Flash Attention must be active when KV Cache is quantized
    public mutating func enforceSafetyInvariants() {
        if kvCacheType != .f16 && !flashAttentionEnabled {
            flashAttentionEnabled = true
        }
        if exposeOnLocalNetwork {
            hostAddress = "0.0.0.0"
        } else if hostAddress == "0.0.0.0" {
            hostAddress = "127.0.0.1"
        }
    }

    /// Generates the exact environment variable dictionary passed to `ollama serve` and `launchctl`
    public func toEnvironmentVariables() -> [String: String] {
        let bindHost = exposeOnLocalNetwork ? "0.0.0.0:\(port)" : "\(hostAddress):\(port)"
        var env: [String: String] = [
            "OLLAMA_HOST": bindHost,
            "OLLAMA_ORIGINS": allowedOrigins,
            "OLLAMA_MODELS": modelsDirectoryPath,
            "OLLAMA_KEEP_ALIVE": defaultKeepAlive,
            "OLLAMA_LOAD_TIMEOUT": loadTimeout,
            "OLLAMA_NUM_PARALLEL": "\(max(1, numParallel))",
            "OLLAMA_MAX_LOADED_MODELS": "\(max(1, maxLoadedModels))",
            "OLLAMA_MAX_QUEUE": "\(max(16, maxQueue))",
            "OLLAMA_CONTEXT_LENGTH": "\(max(2048, defaultContextLength))",
            "OLLAMA_MAX_TRANSFER_STREAMS": "\(max(1, maxTransferStreams))",
            "OLLAMA_FLASH_ATTENTION": flashAttentionEnabled ? "1" : "0",
            "OLLAMA_KV_CACHE_TYPE": kvCacheType.rawValue,
            "OLLAMA_SCHED_SPREAD": spreadAcrossGPUs ? "1" : "0",
            "OLLAMA_DEBUG": debugLogging ? "1" : "0"
        ]
        if disableReadlineHistory {
            env["OLLAMA_NOHISTORY"] = "1"
        }
        return env
    }
}

// MARK: - 1-Click External App Connection Bridges (Obsidian, Cursor, Continue, Raycast)

public struct ExternalAppBridge: Identifiable {
    public let id: String
    public let appName: String
    public let requiredOriginPattern: String
    public let setupInstructions: String
    public let endpointToPaste: String

    public static func allBridges(port: Int) -> [ExternalAppBridge] {
        let base = "http://127.0.0.1:\(port)"
        return [
            ExternalAppBridge(
                id: "obsidian",
                appName: "Obsidian (Copilot / Local GPT)",
                requiredOriginPattern: "app://obsidian.md*",
                setupInstructions: "Allows Obsidian plugins to talk directly to your local models without CORS errors. Paste the endpoint URL below into Obsidian's plugin settings.",
                endpointToPaste: base
            ),
            ExternalAppBridge(
                id: "cursor_continue",
                appName: "Cursor & VS Code (Continue.dev)",
                requiredOriginPattern: "vscode-webview://*",
                setupInstructions: "Enables inline coding autocomplete and local chat inside Cursor or VS Code via the OpenAI-compatible v1 endpoint.",
                endpointToPaste: "\(base)/v1"
            ),
            ExternalAppBridge(
                id: "browser_ext",
                appName: "Safari / Chrome / Arc Extensions",
                requiredOriginPattern: "chrome-extension://*,moz-extension://*",
                setupInstructions: "Permits browser summarizer extensions to reach your local Ollama server privately.",
                endpointToPaste: base
            )
        ]
    }
}
