import Foundation

@MainActor
public final class ProcessSupervisor: ObservableObject {
    @Published public var isRunning: Bool = false
    @Published public var logs: [String] = []
    @Published public var detectedBinaryPath: String?

    private var process: Process?
    private var outputPipe: Pipe?

    public init() {
        self.detectedBinaryPath = Self.locateBinary()
        appendLog("Aether Process Supervisor initialized.")
    }

    public static func locateBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.ollama/bin/ollama",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/bin/ollama"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    public func appendLog(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logs.append("[\(ts)] \(message)")
        if logs.count > 300 {
            logs.removeFirst(logs.count - 300)
        }
    }

    public func startEngine(config: StorageConfig) {
        if process?.isRunning == true { return }

        guard let binary = detectedBinaryPath ?? Self.locateBinary() else {
            appendLog("Warning: Could not locate 'ollama' binary on this system.")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["serve"]

        var env = ProcessInfo.processInfo.environment
        for (k, v) in config.toEnvironmentVariables() {
            env[k] = v
        }
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        self.outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                for line in chunk.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    self?.appendLog(line)
                }
            }
        }

        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.appendLog("Ollama process stopped.")
            }
        }

        do {
            try p.run()
            self.process = p
            self.isRunning = true
            appendLog("Ollama engine started with OLLAMA_MODELS=\(config.modelsDirectoryPath)")
        } catch {
            appendLog("Failed to start Ollama: \(error.localizedDescription)")
        }
    }

    public func stopEngine() {
        if let p = process, p.isRunning {
            p.terminate()
            self.process = nil
            self.isRunning = false
            appendLog("Engine stopped.")
        }
    }

    public func restartEngine(config: StorageConfig) async {
        stopEngine()
        try? await Task.sleep(nanoseconds: 500_000_000)
        startEngine(config: config)
    }
}
