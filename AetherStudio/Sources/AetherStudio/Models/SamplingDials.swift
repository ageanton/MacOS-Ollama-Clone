import Foundation

public struct SamplingDials: Codable, Equatable, Hashable {
    public var temperature: Double = 0.7
    public var topP: Double = 0.9
    public var topK: Int = 40
    public var minP: Double = 0.05
    public var repeatPenalty: Double = 1.1
    public var repeatLastN: Int = 64
    public var numCtx: Int = 8192
    public var numPredict: Int = -1
    public var systemPrompt: String = ""
    public var thinkingMode: ThinkingMode = .modelDefault
    public var stopSequences: [String] = []

    public init() {}

    public func toOllamaOptions() -> [String: Any] {
        var opts: [String: Any] = [
            "temperature": round(temperature * 1000) / 1000,
            "top_p": round(topP * 1000) / 1000,
            "top_k": topK,
            "min_p": round(minP * 1000) / 1000,
            "repeat_penalty": round(repeatPenalty * 1000) / 1000,
            "repeat_last_n": repeatLastN,
            "num_ctx": numCtx,
            "num_predict": numPredict
        ]
        let cleanStops = stopSequences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !cleanStops.isEmpty {
            opts["stop"] = cleanStops
        }
        return opts
    }
}
