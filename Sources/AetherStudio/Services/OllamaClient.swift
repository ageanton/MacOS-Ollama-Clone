import Foundation

public struct ChatStreamChunk {
    public let textDelta: String
    public let thinkingDelta: String
    public let isDone: Bool
    public let totalDurationNs: Int64?
    public let promptEvalCount: Int?
    public let evalCount: Int?
    public let evalDurationNs: Int64?
}

public actor OllamaClient {
    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: cfg)
    }

    public func fetchVersion(baseURL: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/version") else {
            throw URLError(.badURL)
        }
        let (data, res) = try await session.data(from: url)
        guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["version"] as? String ?? "Online"
    }

    public func fetchInstalledModels(baseURL: String) async throws -> [OllamaModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw URLError(.badURL)
        }
        let (data, res) = try await session.data(from: url)
        guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct Response: Codable {
            let models: [OllamaModel]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.models ?? []
    }

    public func fetchRunningModels(baseURL: String) async throws -> [RunningModelProcess] {
        guard let url = URL(string: "\(baseURL)/api/ps") else {
            throw URLError(.badURL)
        }
        let (data, res) = try await session.data(from: url)
        guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }
        struct Response: Codable {
            let models: [RunningModelProcess]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.models ?? []
    }

    public func unloadModel(baseURL: String, modelName: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": modelName,
            "keep_alive": 0
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await session.data(for: req)
    }

    public func deleteModel(baseURL: String, modelName: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/delete") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": modelName]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await session.data(for: req)
    }

    public func streamChat(
        baseURL: String,
        modelName: String,
        messages: [ChatMessage],
        dials: SamplingDials
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/chat") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var apiMessages: [[String: Any]] = []
                    if !dials.systemPrompt.isEmpty {
                        apiMessages.append(["role": "system", "content": dials.systemPrompt])
                    }
                    for msg in messages {
                        apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
                    }

                    var body: [String: Any] = [
                        "model": modelName,
                        "messages": apiMessages,
                        "stream": true,
                        "options": dials.toOllamaOptions()
                    ]
                    if dials.thinkingMode == .disabled {
                        body["think"] = false
                    }

                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (byteStream, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }

                    for try await line in byteStream.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
                        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

                        let done = json["done"] as? Bool ?? false
                        let messageObj = json["message"] as? [String: Any]
                        let content = messageObj?["content"] as? String ?? ""
                        let thinking = messageObj?["thinking"] as? String ?? ""

                        let totalDuration = json["total_duration"] as? Int64
                        let promptEval = json["prompt_eval_count"] as? Int
                        let evalCount = json["eval_count"] as? Int
                        let evalDuration = json["eval_duration"] as? Int64

                        continuation.yield(ChatStreamChunk(
                            textDelta: content,
                            thinkingDelta: thinking,
                            isDone: done,
                            totalDurationNs: totalDuration,
                            promptEvalCount: promptEval,
                            evalCount: evalCount,
                            evalDurationNs: evalDuration
                        ))

                        if done {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
