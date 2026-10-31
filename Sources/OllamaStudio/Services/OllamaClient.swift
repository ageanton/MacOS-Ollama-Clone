import Foundation

// MARK: - Plain-English Error Translation (Never Shows Raw "Error 500")

public struct HumanFriendlyError: Error, Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let plainExplanation: String
    public let technicalDetail: String
    public let recoveryActionTitle: String?
    public let recoveryKind: RecoveryKind?

    public enum RecoveryKind: Equatable {
        case startEngine
        case reduceContextWindow
        case pullMissingModel(String)
        case retryConnection
    }

    public static func translate(_ error: Error, endpoint: String, model: String? = nil) -> HumanFriendlyError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && (
            nsError.code == NSURLErrorCannotConnectToHost ||
            nsError.code == NSURLErrorNetworkConnectionLost ||
            nsError.code == NSURLErrorTimedOut
        ) {
            return HumanFriendlyError(
                title: "Ollama Engine Is Asleep",
                plainExplanation: "Ollama Studio couldn't reach the local background service on your Mac. The engine is either stopped or still starting up.",
                technicalDetail: "\(endpoint) (\(nsError.localizedDescription))",
                recoveryActionTitle: "Start Ollama Engine",
                recoveryKind: .startEngine
            )
        }

        let rawText = error.localizedDescription
        let lower = rawText.lowercased()

        if lower.contains("memory") || lower.contains("vram") || lower.contains("alloc") || lower.contains("ggml_assert") {
            return HumanFriendlyError(
                title: "Not Enough Free Memory for Current Settings",
                plainExplanation: "This model and conversation memory window need more Unified Memory than macOS currently has free.",
                technicalDetail: rawText,
                recoveryActionTitle: "Lower Conversation Memory to 4,096",
                recoveryKind: .reduceContextWindow
            )
        }

        if lower.contains("not found") || lower.contains("404") {
            let target = model ?? "selected model"
            return HumanFriendlyError(
                title: "Model '\(target)' Is Not Installed Yet",
                plainExplanation: "The conversation is set to use '\(target)', which hasn't been downloaded to your Mac.",
                technicalDetail: rawText,
                recoveryActionTitle: "Download \(target)",
                recoveryKind: model != nil ? .pullMissingModel(target) : nil
            )
        }

        return HumanFriendlyError(
            title: "The Local Model Encountered an Issue",
            plainExplanation: rawText.isEmpty ? "An unexpected response came back from the local engine." : rawText,
            technicalDetail: "\(endpoint): \(rawText)",
            recoveryActionTitle: "Retry",
            recoveryKind: .retryConnection
        )
    }
}

// MARK: - Ollama HTTP & NDJSON Streaming Client

public final class OllamaClient {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 86400
        self.session = URLSession(configuration: config)
    }

    // MARK: 1. Check Server Version (`/api/version`)

    public func fetchVersion(baseURL: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/version") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = json["version"] as? String {
            return version
        }
        return "Running"
    }

    // MARK: 2. List Installed Models (`/api/tags`)

    public func fetchInstalledModels(baseURL: String) async throws -> [OllamaModelSummary] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        struct TagsWrapper: Decodable { let models: [OllamaModelSummary] }
        let decoded = try JSONDecoder().decode(TagsWrapper.self, from: data)
        return decoded.models
    }

    // MARK: 3. List Models Loaded in RAM (`/api/ps`)

    public func fetchRunningModels(baseURL: String) async throws -> [RunningModelProcess] {
        guard let url = URL(string: "\(baseURL)/api/ps") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, data: data)
        struct PSWrapper: Decodable { let models: [RunningModelProcess] }
        let decoded = try JSONDecoder().decode(PSWrapper.self, from: data)
        return decoded.models
    }

    // MARK: 4. Deep Model Inspection (`/api/show`)

    public func fetchModelShowInfo(baseURL: String, modelName: String) async throws -> OllamaModelShowInfo {
        guard let url = URL(string: "\(baseURL)/api/show") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": modelName])
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(OllamaModelShowInfo.self, from: data)
    }

    // MARK: 5. Pre-Warm Model into RAM or Eject Immediately (`keep_alive: 0`)

    public func setModelResidency(baseURL: String, modelName: String, keepAlive: Any) async throws {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": "",
            "keep_alive": keepAlive,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    // MARK: 6. Copy / Duplicate Model (`/api/copy`) & Delete Model (`/api/delete`)

    public func copyModel(baseURL: String, source: String, destination: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/copy") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["source": source, "destination": destination])
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    public func deleteModel(baseURL: String, modelName: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/delete") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": modelName])
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    // MARK: 7. Stream Chat Completion (`/api/chat`) with Thinking, Vision, RAG, and JSON Schema

    public struct ChatStreamEvent {
        public let contentDelta: String
        public let thinkingDelta: String
        public let isDone: Bool
        public let tokensPerSecond: Double?
        public let timeToFirstTokenMs: Double?
        public let promptEvalCount: Int?
        public let evalCount: Int?
    }

    public func streamChat(
        baseURL: String,
        model: String,
        messages: [ChatMessage],
        dials: ModelDials
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/chat") else {
                        throw URLError(.badURL)
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    // Construct messages array
                    var wireMessages: [[String: Any]] = []
                    let trimmedSys = dials.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedSys.isEmpty {
                        wireMessages.append(["role": "system", "content": trimmedSys])
                    }

                    let historySlice: [ChatMessage] = dials.statelessNoHistory
                        ? (messages.last.map { [$0] } ?? [])
                        : messages

                    for msg in historySlice where !msg.isStreaming {
                        var composedContent = msg.content
                        // Append any local document attachments cleanly before the user's question
                        let docAttachments = msg.attachments.filter { $0.kind == .document }
                        if !docAttachments.isEmpty {
                            let docBlocks = docAttachments.compactMap { att -> String? in
                                guard let text = att.extractedDocumentText, !text.isEmpty else { return nil }
                                return "--- Attached File: \(att.fileName) ---\n\(text)\n--- End of \(att.fileName) ---"
                            }.joined(separator: "\n\n")
                            if !docBlocks.isEmpty {
                                composedContent = "\(docBlocks)\n\n\(composedContent)"
                            }
                        }

                        var entry: [String: Any] = [
                            "role": msg.role.rawValue,
                            "content": composedContent
                        ]
                        let imagesBase64 = msg.attachments.compactMap(\.base64ImagePayload)
                        if !imagesBase64.isEmpty {
                            entry["images"] = imagesBase64
                        }
                        wireMessages.append(entry)
                    }

                    var body: [String: Any] = [
                        "model": model,
                        "messages": wireMessages,
                        "stream": true,
                        "options": dials.toOllamaOptionsDictionary()
                    ]

                    if let thinkVal = dials.thinkingMode.apiJSONValue {
                        body["think"] = thinkVal
                    }
                    if let keepAliveVal = dials.keepAlive.apiValue {
                        body["keep_alive"] = keepAliveVal
                    }

                    switch dials.formatMode {
                    case .prose:
                        break
                    case .jsonObject:
                        body["format"] = "json"
                    case .jsonSchema:
                        if let schemaData = dials.customJSONSchema.data(using: .utf8),
                           let schemaJSON = try? JSONSerialization.jsonObject(with: schemaData) {
                            body["format"] = schemaJSON
                        } else {
                            body["format"] = "json"
                        }
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let requestStartTime = CFAbsoluteTimeGetCurrent()
                    var firstTokenTime: CFAbsoluteTime? = nil
                    var insideInlineThinkTag = false

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        throw NSError(domain: "OllamaAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: Self.extractErrorMessage(from: errorBody)])
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let lineData = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                            continue
                        }

                        if let errStr = json["error"] as? String {
                            throw NSError(domain: "OllamaAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: errStr])
                        }

                        if firstTokenTime == nil {
                            firstTokenTime = CFAbsoluteTimeGetCurrent()
                        }

                        let messageObj = json["message"] as? [String: Any]
                        var rawContent = (messageObj?["content"] as? String) ?? ""
                        var rawThinking = (messageObj?["thinking"] as? String) ?? ""

                        // Also handle inline `<think>...</think>` tags if a model emits them inside content
                        if rawThinking.isEmpty && !rawContent.isEmpty {
                            if rawContent.contains("<think>") {
                                insideInlineThinkTag = true
                                rawContent = rawContent.replacingOccurrences(of: "<think>", with: "")
                            }
                            if insideInlineThinkTag {
                                if let closeRange = rawContent.range(of: "</think>") {
                                    rawThinking = String(rawContent[..<closeRange.lowerBound])
                                    rawContent = String(rawContent[closeRange.upperBound...])
                                    insideInlineThinkTag = false
                                } else {
                                    rawThinking = rawContent
                                    rawContent = ""
                                }
                            }
                        }

                        let done = (json["done"] as? Bool) ?? false
                        var tps: Double? = nil
                        var ttftMs: Double? = nil
                        let promptCount = json["prompt_eval_count"] as? Int
                        let evalCount = json["eval_count"] as? Int

                        if let evalCount = evalCount,
                           let evalDurationNs = json["eval_duration"] as? Double,
                           evalDurationNs > 0 {
                            tps = Double(evalCount) / (evalDurationNs / 1_000_000_000.0)
                        }
                        if let first = firstTokenTime {
                            ttftMs = (first - requestStartTime) * 1000.0
                        }

                        continuation.yield(
                            ChatStreamEvent(
                                contentDelta: rawContent,
                                thinkingDelta: rawThinking,
                                isDone: done,
                                tokensPerSecond: tps,
                                timeToFirstTokenMs: ttftMs,
                                promptEvalCount: promptCount,
                                evalCount: evalCount
                            )
                        )

                        if done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: 8. Resumable Model Pull (`/api/pull` — Supports Ollama Library & Hugging Face `hf.co/user/repo`)

    public struct PullProgressEvent {
        public let status: String
        public let completed: Int64
        public let total: Int64
    }

    public func streamPullModel(baseURL: String, modelIdentifier: String) -> AsyncThrowingStream<PullProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/pull") else { throw URLError(.badURL) }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                        "stream": true
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        throw NSError(domain: "OllamaPull", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: Self.extractErrorMessage(from: errorBody)])
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let err = json["error"] as? String {
                            throw NSError(domain: "OllamaPull", code: 500, userInfo: [NSLocalizedDescriptionKey: err])
                        }
                        let status = (json["status"] as? String) ?? "Downloading..."
                        let completed = (json["completed"] as? Int64) ?? 0
                        let total = (json["total"] as? Int64) ?? 0
                        continuation.yield(PullProgressEvent(status: status, completed: completed, total: total))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 9. Structured Visual Model Creation (`POST /api/create`)

    public func createCustomModel(baseURL: String, spec: ModelBuilderSpec) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/create") else { throw URLError(.badURL) }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var payload: [String: Any] = [
                        "model": spec.newModelName.trimmingCharacters(in: .whitespacesAndNewlines),
                        "from": spec.baseModelOrGGUFPath.trimmingCharacters(in: .whitespacesAndNewlines),
                        "parameters": spec.dials.toModelfileParametersMap(),
                        "stream": true
                    ]

                    let sys = spec.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sys.isEmpty { payload["system"] = sys }

                    let tmpl = spec.customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tmpl.isEmpty { payload["template"] = tmpl }

                    let lic = spec.licenseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lic.isEmpty { payload["license"] = lic }

                    if !spec.quantizeLevel.isEmpty {
                        payload["quantize"] = spec.quantizeLevel
                    }

                    let validTurns = spec.exampleDialogue.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if !validTurns.isEmpty {
                        payload["messages"] = validTurns.map { ["role": $0.role.rawValue, "content": $0.content] }
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        throw NSError(domain: "OllamaCreate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: Self.extractErrorMessage(from: errorBody)])
                    }

                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let err = json["error"] as? String {
                                throw NSError(domain: "OllamaCreate", code: 500, userInfo: [NSLocalizedDescriptionKey: err])
                            }
                            if let status = json["status"] as? String {
                                continuation.yield(status)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "OllamaHTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: Self.extractErrorMessage(from: body)])
        }
    }

    private static func extractErrorMessage(from rawBody: String) -> String {
        if let data = rawBody.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? String {
            return err
        }
        return rawBody
    }
}
