import Foundation

// MARK: - Reasoning / Thinking Effort Mode (/api/chat `think` field)

public enum ThinkingMode: String, CaseIterable, Codable, Identifiable {
    case modelDefault = "default"
    case enabled = "true"
    case disabled = "false"
    case effortLow = "low"
    case effortMedium = "medium"
    case effortHigh = "high"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .modelDefault: return "Auto (Model Default)"
        case .enabled: return "Thinking On"
        case .disabled: return "Thinking Off (Direct Answer)"
        case .effortLow: return "Low Effort"
        case .effortMedium: return "Medium Effort"
        case .effortHigh: return "Deep Effort (High)"
        }
    }

    public var plainEnglishDescription: String {
        switch self {
        case .modelDefault:
            return "Lets the model decide whether to show a reasoning chain based on its built-in training."
        case .enabled:
            return "Forces reasoning models (like DeepSeek R1 or Qwen3) to think step-by-step inside a collapsible panel before answering."
        case .disabled:
            return "Skips the internal monologue and outputs the final answer immediately for faster responses."
        case .effortLow:
            return "Brief internal reasoning check for straightforward questions."
        case .effortMedium:
            return "Balanced reasoning depth for everyday logic and coding tasks."
        case .effortHigh:
            return "Maximum multi-step deliberation for complex math, architecture, or debugging."
        }
    }

    /// Converts to the exact JSON value expected by Ollama's `/api/chat` `think` property
    public var apiJSONValue: Any? {
        switch self {
        case .modelDefault: return nil
        case .enabled: return true
        case .disabled: return false
        case .effortLow: return "low"
        case .effortMedium: return "medium"
        case .effortHigh: return "high"
        }
    }
}

// MARK: - Output Structure Format (`format` field)

public enum ResponseFormatMode: String, CaseIterable, Codable, Identifiable {
    case prose = "prose"
    case jsonObject = "json"
    case jsonSchema = "schema"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .prose: return "Natural Prose & Markdown"
        case .jsonObject: return "Strict JSON Mode"
        case .jsonSchema: return "Custom JSON Schema"
        }
    }
}

// MARK: - Keep-Alive Policy Per Request

public enum KeepAlivePreset: String, CaseIterable, Codable, Identifiable {
    case serverDefault = "default"
    case unloadImmediately = "0"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case oneHour = "1h"
    case stayLoadedForever = "-1"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .serverDefault: return "Server Default (5 min)"
        case .unloadImmediately: return "Unload Immediately After Reply (0s)"
        case .fiveMinutes: return "Keep in RAM for 5 Minutes"
        case .fifteenMinutes: return "Keep in RAM for 15 Minutes"
        case .oneHour: return "Keep in RAM for 1 Hour"
        case .stayLoadedForever: return "Pin in RAM Indefinitely"
        }
    }

    public var apiValue: Any? {
        switch self {
        case .serverDefault: return nil
        case .unloadImmediately: return 0
        case .stayLoadedForever: return -1
        default: return rawValue
        }
    }
}

// MARK: - Complete 28-Parameter ModelDials Struct

public struct ModelDials: Codable, Equatable, Hashable {
    // 1. Core Sampling & Creativity
    public var temperature: Double = 0.7
    public var topK: Int = 40
    public var topP: Double = 0.9
    public var minP: Double = 0.0
    public var typicalP: Double = 1.0
    public var tfsZ: Double = 1.0

    // 2. Repetition & Anti-Looping Controls
    public var repeatLastN: Int = 64
    public var repeatPenalty: Double = 1.1
    public var presencePenalty: Double = 0.0
    public var frequencyPenalty: Double = 0.0
    public var penalizeNewline: Bool = true

    // 3. Mirostat Perplexity Control
    public var mirostat: Int = 0          // 0 = disabled, 1 = Mirostat 1, 2 = Mirostat 2
    public var mirostatTau: Double = 5.0
    public var mirostatEta: Double = 0.1

    // 4. Memory, Context & Generation Length
    public var numCtx: Int = 8192         // Conversation memory window in tokens
    public var numPredict: Int = -1       // Max tokens to generate (-1 = unlimited, -2 = fill context)
    public var numKeep: Int = 4           // Tokens from initial prompt to always retain when context rolls over
    public var numBatch: Int = 512        // Prompt evaluation batch size

    // 5. Hardware, Apple Silicon Metal & Memory Mapping
    public var numGpu: Int = -1           // -1 = offload all layers to Apple Silicon GPU (Metal)
    public var mainGpu: Int = 0           // Primary GPU index on multi-GPU setups
    public var numThread: Int = 0         // 0 = let Ollama auto-tune to Apple Silicon performance cores
    public var useMmap: Bool = true       // Memory-map weights directly from SSD without duplicating RAM
    public var useMlock: Bool = false     // Lock model weights in physical RAM (prevents macOS swap)
    public var lowVram: Bool = false      // Conserve graphics memory by disabling heavy scratch buffers
    public var numa: Bool = false         // Non-Uniform Memory Access optimization (Mac Pro / Ultra)
    public var vocabOnly: Bool = false    // Load only vocabulary metadata for fast token inspection

    // 6. Reproducibility & Stop Sequences
    public var seed: Int = -1             // -1 = random seed every run
    public var stopSequences: [String] = []

    // 7. Top-Level Session & API Controls (Parity with all `/set` CLI commands)
    public var systemPrompt: String = ""
    public var customTemplateOverride: String = ""
    public var thinkingMode: ThinkingMode = .modelDefault
    public var formatMode: ResponseFormatMode = .prose
    public var customJSONSchema: String = """
    {
      "type": "object",
      "properties": {
        "summary": { "type": "string" },
        "key_points": { "type": "array", "items": { "type": "string" } }
      },
      "required": ["summary", "key_points"]
    }
    """
    public var keepAlive: KeepAlivePreset = .serverDefault
    public var statelessNoHistory: Bool = false   // Equivalent to `/set nohistory`
    public var verboseMetrics: Bool = true        // Equivalent to `/set verbose` vs `/set quiet`
    public var softWordWrap: Bool = true          // Equivalent to `/set wordwrap` vs `/set nowordwrap`

    public init() {}

    // MARK: - Convert to Ollama `/api/chat` and `/api/generate` `options` Dictionary

    public func toOllamaOptionsDictionary() -> [String: Any] {
        var opts: [String: Any] = [
            "temperature": round(temperature * 1000) / 1000,
            "top_k": topK,
            "top_p": round(topP * 1000) / 1000,
            "min_p": round(minP * 1000) / 1000,
            "typical_p": round(typicalP * 1000) / 1000,
            "tfs_z": round(tfsZ * 1000) / 1000,
            "repeat_last_n": repeatLastN,
            "repeat_penalty": round(repeatPenalty * 1000) / 1000,
            "presence_penalty": round(presencePenalty * 1000) / 1000,
            "frequency_penalty": round(frequencyPenalty * 1000) / 1000,
            "penalize_newline": penalizeNewline,
            "mirostat": mirostat,
            "mirostat_tau": round(mirostatTau * 100) / 100,
            "mirostat_eta": round(mirostatEta * 1000) / 1000,
            "num_ctx": numCtx,
            "num_predict": numPredict,
            "num_keep": numKeep,
            "num_batch": numBatch,
            "use_mmap": useMmap,
            "use_mlock": useMlock,
            "low_vram": lowVram,
            "numa": numa,
            "vocab_only": vocabOnly
        ]

        if numGpu >= 0 {
            opts["num_gpu"] = numGpu
        }
        if mainGpu > 0 {
            opts["main_gpu"] = mainGpu
        }
        if numThread > 0 {
            opts["num_thread"] = numThread
        }
        if seed >= 0 {
            opts["seed"] = seed
        }
        let cleanedStops = stopSequences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !cleanedStops.isEmpty {
            opts["stop"] = cleanedStops
        }

        return opts
    }

    /// Converts strictly typed String dictionary for `/api/create` `parameters` field
    public func toModelfileParametersMap() -> [String: Any] {
        var params: [String: Any] = [
            "temperature": round(temperature * 100) / 100,
            "top_k": topK,
            "top_p": round(topP * 100) / 100,
            "min_p": round(minP * 100) / 100,
            "repeat_last_n": repeatLastN,
            "repeat_penalty": round(repeatPenalty * 100) / 100,
            "num_ctx": numCtx
        ]
        if presencePenalty != 0 { params["presence_penalty"] = presencePenalty }
        if frequencyPenalty != 0 { params["frequency_penalty"] = frequencyPenalty }
        if mirostat != 0 {
            params["mirostat"] = mirostat
            params["mirostat_tau"] = mirostatTau
            params["mirostat_eta"] = mirostatEta
        }
        if numPredict != -1 { params["num_predict"] = numPredict }
        if seed >= 0 { params["seed"] = seed }
        let cleanedStops = stopSequences.filter { !$0.isEmpty }
        if !cleanedStops.isEmpty { params["stop"] = cleanedStops }
        return params
    }

    // MARK: - Live Apple Silicon KV Cache + Model Weight RAM Estimator

    public struct MemoryEstimate: Equatable {
        public let modelWeightsGB: Double
        public let kvCacheGB: Double
        public let computeOverheadGB: Double
        public var totalEstimatedGB: Double { modelWeightsGB + kvCacheGB + computeOverheadGB }
        public let approximatePagesOfText: Int
        public let warningLevel: WarningLevel
        public let plainEnglishSummary: String
        public let actionableAdvice: String?

        public enum WarningLevel: Equatable {
            case optimal
            case moderate
            case criticalOverflow
        }
    }

    public func estimateMemoryFootprint(
        modelSizeBytes: Int64,
        kvCacheType: KVCacheQuantizationType,
        systemTotalRAMGB: Double,
        systemAvailableRAMGB: Double
    ) -> MemoryEstimate {
        let weightsGB = max(0.4, Double(modelSizeBytes) / 1_073_741_824.0)

        // KV Cache scales linearly with num_ctx and depends on KV cache quantization (f16, q8_0, q4_0)
        // Base heuristic for an ~8B GQA model at f16 is ~0.125 GB per 1,024 tokens; scales mildly with model weight size.
        let modelScaleFactor = max(0.5, min(4.0, weightsGB / 4.7))
        let kvBytesPerTokenF16: Double = 131_072.0 * modelScaleFactor // ~128 KB per token baseline
        let quantMultiplier = kvCacheType.memoryMultiplier
        let kvGB = (Double(numCtx) * kvBytesPerTokenF16 * quantMultiplier) / 1_073_741_824.0

        let batchOverheadGB = (Double(numBatch) / 512.0) * 0.35
        let totalGB = weightsGB + kvGB + batchOverheadGB
        let pages = max(1, Int((Double(numCtx) * 0.75) / 350.0)) // ~350 words per printed page

        // Safe Apple Silicon Unified Memory ceiling (~78% of physical RAM before macOS swap thrashing)
        let safeCeilingGB = systemTotalRAMGB * 0.78

        if totalGB > systemTotalRAMGB * 0.92 {
            return MemoryEstimate(
                modelWeightsGB: weightsGB,
                kvCacheGB: kvGB,
                computeOverheadGB: batchOverheadGB,
                approximatePagesOfText: pages,
                warningLevel: .criticalOverflow,
                plainEnglishSummary: String(
                    format: "Needs %.1f GB (%.1f GB model + %.1f GB memory window). Your Mac has %.0f GB total RAM — this will force heavy SSD swap and run very slowly.",
                    totalGB, weightsGB, kvGB, systemTotalRAMGB
                ),
                actionableAdvice: kvCacheType == .f16
                    ? "Lower Conversation Memory (num_ctx) to 8,192 or switch KV Cache to 8-bit (q8_0) in Server Control to cut memory window usage in half."
                    : "Lower Conversation Memory (num_ctx) or choose a smaller quantized model."
            )
        } else if totalGB > safeCeilingGB || totalGB > (systemAvailableRAMGB + weightsGB * 0.5) {
            return MemoryEstimate(
                modelWeightsGB: weightsGB,
                kvCacheGB: kvGB,
                approximatePagesOfText: pages,
                computeOverheadGB: batchOverheadGB,
                warningLevel: .moderate,
                plainEnglishSummary: String(
                    format: "Uses %.1f GB of Unified Memory (~%d pages of conversation history). Fits in RAM, but close other heavy apps for peak speed.",
                    totalGB, pages
                ),
                actionableAdvice: numCtx > 16384 && kvCacheType == .f16
                    ? "Tip: Enabling 8-bit KV Cache (q8_0) in Server Control saves \(String(format: "%.1f", kvGB * 0.5)) GB with virtually zero quality loss."
                    : nil
            )
        } else {
            return MemoryEstimate(
                modelWeightsGB: weightsGB,
                kvCacheGB: kvGB,
                computeOverheadGB: batchOverheadGB,
                approximatePagesOfText: pages,
                warningLevel: .optimal,
                plainEnglishSummary: String(
                    format: "Runs comfortably in Apple Silicon Metal (%.1f GB total: %.1f GB weights + %.2f GB context window for ~%d pages).",
                    totalGB, weightsGB, kvGB, pages
                ),
                actionableAdvice: nil
            )
        }
    }
}

// MARK: - Curated Dials Presets

public struct DialsPreset: Identifiable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let apply: (inout ModelDials) -> Void

    public static let allPresets: [DialsPreset] = [
        DialsPreset(
            id: "balanced",
            name: "Balanced Everyday",
            subtitle: "Natural tone, reliable recall, 8k context window."
        ) { dials in
            dials.temperature = 0.7
            dials.topK = 40
            dials.topP = 0.9
            dials.minP = 0.05
            dials.repeatPenalty = 1.1
            dials.numCtx = 8192
            dials.mirostat = 0
        },
        DialsPreset(
            id: "coding_precise",
            name: "Deterministic Coding & Math",
            subtitle: "Low randomness (0.15) and expanded 16k memory so code stays exact."
        ) { dials in
            dials.temperature = 0.15
            dials.topK = 20
            dials.topP = 0.85
            dials.minP = 0.05
            dials.repeatPenalty = 1.05
            dials.numCtx = 16384
            dials.mirostat = 0
        },
        DialsPreset(
            id: "creative_editorial",
            name: "Creative Writing & Brainstorming",
            subtitle: "Richer vocabulary and higher variety with Min-P guardrails against gibberish."
        ) { dials in
            dials.temperature = 0.95
            dials.topK = 80
            dials.topP = 0.95
            dials.minP = 0.06
            dials.repeatPenalty = 1.15
            dials.presencePenalty = 0.2
            dials.numCtx = 8192
            dials.mirostat = 0
        },
        DialsPreset(
            id: "deep_document",
            name: "Long Document Reader (32k)",
            subtitle: "Expands memory window to ~75 pages of text for analyzing large files."
        ) { dials in
            dials.temperature = 0.4
            dials.topK = 40
            dials.topP = 0.9
            dials.numCtx = 32768
        },
        DialsPreset(
            id: "ram_saver",
            name: "Minimal RAM Saver",
            subtitle: "Compact 2,048-token window and low-VRAM mode for battery or multitasking."
        ) { dials in
            dials.numCtx = 2048
            dials.numBatch = 256
            dials.lowVram = true
            dials.keepAlive = .fiveMinutes
        }
    ]
}

// MARK: - Plain-English Parameter Catalog (Used by Tooltips & Inspector)

public struct ParameterHelpCatalog {
    public struct Entry {
        public let title: String
        public let key: String
        public let explanation: String
        public let recommendation: String
    }

    public static let entries: [String: Entry] = [
        "num_ctx": Entry(
            title: "Conversation Memory (Context Window)",
            key: "num_ctx",
            explanation: "How much of the current conversation and attached files the model can remember at once. The #1 reason local models 'forget' instructions is that Ollama defaults to a small 2,048 or 4,096 token window unless told otherwise.",
            recommendation: "Use 8,192 for normal chats (~18 pages) or 16,384–32,768 when reading long documents."
        ),
        "temperature": Entry(
            title: "Temperature (Creativity vs. Precision)",
            key: "temperature",
            explanation: "Controls how predictable or adventurous the model is when picking the next word. At 0.0, it always picks the single most likely word. Higher values allow more creative phrasing.",
            recommendation: "0.1–0.3 for coding and factual extraction; 0.7 for everyday chat; 0.9+ for creative writing."
        ),
        "top_p": Entry(
            title: "Nucleus Sampling (Top-P)",
            key: "top_p",
            explanation: "Narrows word choices to the top percentage of cumulative probability. At 0.90, the model ignores the bottom 10% of unlikely tail words.",
            recommendation: "Keep at 0.90 for balanced answers, or lower to 0.75 for stricter focus."
        ),
        "min_p": Entry(
            title: "Minimum Probability Threshold (Min-P)",
            key: "min_p",
            explanation: "A modern alternative to Top-P. It scales the cutoff dynamically relative to the model's confidence in its #1 word choice, preventing nonsense even when Temperature is turned up high.",
            recommendation: "Set between 0.05 and 0.10 if you want high creativity without hallucinations."
        ),
        "top_k": Entry(
            title: "Vocabulary Pool Limit (Top-K)",
            key: "top_k",
            explanation: "Hard-caps the number of candidate words the model considers at each step. A value of 40 means it only chooses among its top 40 guesses.",
            recommendation: "40 is ideal for most models; 10–20 for strict logic; 80+ for expressive prose."
        ),
        "repeat_penalty": Entry(
            title: "Repetition Penalty",
            key: "repeat_penalty",
            explanation: "Discourages the model from repeating the exact same phrases or getting stuck in a loop.",
            recommendation: "1.10 is the sweet spot. Above 1.30 can make code or grammar look unnatural."
        ),
        "repeat_last_n": Entry(
            title: "Repetition Lookback Window",
            key: "repeat_last_n",
            explanation: "How many recent tokens the model checks when applying the Repetition Penalty. -1 checks the entire context window.",
            recommendation: "64 to 128 tokens works well without penalizing recurring variable names in code."
        ),
        "presence_penalty": Entry(
            title: "Topic Freshness (Presence Penalty)",
            key: "presence_penalty",
            explanation: "Applies a flat penalty to any word that has already appeared at least once, nudging the model to introduce new topics.",
            recommendation: "0.0 for coding/technical work; 0.2–0.5 for brainstorming."
        ),
        "frequency_penalty": Entry(
            title: "Word Frequency Penalty",
            key: "frequency_penalty",
            explanation: "Penalizes words proportionally to how many times they have already been used in the response.",
            recommendation: "0.0 by default; 0.1–0.4 if a model overuses specific adjectives."
        ),
        "mirostat": Entry(
            title: "Mirostat Perplexity Controller",
            key: "mirostat",
            explanation: "An adaptive feedback algorithm that adjusts sampling on the fly to keep the 'surprise level' (perplexity) of the text steady, bypassing Top-P and Top-K.",
            recommendation: "Leave at Off (0) for normal use, or choose Mirostat 2.0 for long essays."
        ),
        "num_predict": Entry(
            title: "Maximum Reply Length",
            key: "num_predict",
            explanation: "Caps how many tokens the model can write in a single reply. -1 means no artificial limit; -2 tells it to write until the context window is full.",
            recommendation: "Keep at -1 so answers are never cut off mid-sentence."
        ),
        "num_keep": Entry(
            title: "Pinned Initial Tokens",
            key: "num_keep",
            explanation: "When a conversation exceeds the context window and older messages roll off, this many tokens from the very beginning of the prompt are permanently kept.",
            recommendation: "4 to 24 tokens."
        ),
        "num_batch": Entry(
            title: "Prompt Processing Batch Size",
            key: "num_batch",
            explanation: "How many tokens of your prompt or attached document are digested in parallel on the GPU before the model starts writing.",
            recommendation: "512 is optimal for Apple Silicon. Lower to 128 or 256 if RAM is tight."
        ),
        "num_gpu": Entry(
            title: "GPU Layer Offload (Metal)",
            key: "num_gpu",
            explanation: "How many transformer layers run on your Mac's GPU cores instead of CPU. -1 automatically offloads 100% of layers to Apple Silicon Metal.",
            recommendation: "Leave at -1 (All Layers on GPU) for maximum speed."
        ),
        "num_thread": Entry(
            title: "CPU Compute Threads",
            key: "num_thread",
            explanation: "Number of CPU threads used when layers fall back to CPU. 0 lets Ollama automatically match your Mac's Performance cores.",
            recommendation: "Leave at 0 (Auto)."
        ),
        "use_mmap": Entry(
            title: "Fast SSD Memory Mapping (mmap)",
            key: "use_mmap",
            explanation: "Allows macOS to map model files directly from your SSD into Unified Memory so models load in seconds.",
            recommendation: "Keep ON unless loading models over a slow external network drive."
        ),
        "use_mlock": Entry(
            title: "Lock Model in Physical RAM (mlock)",
            key: "use_mlock",
            explanation: "Forbids macOS from compressing or swapping the model out to disk when other apps ask for memory.",
            recommendation: "Keep OFF unless you have plenty of spare RAM and want zero latency spikes."
        ),
        "seed": Entry(
            title: "Random Seed (Reproducibility)",
            key: "seed",
            explanation: "Fixes the random number generator so the exact same prompt and settings produce the exact same reply every time.",
            recommendation: "-1 for fresh answers every time, or any fixed number (like 42) when testing prompts."
        )
    ]
}
