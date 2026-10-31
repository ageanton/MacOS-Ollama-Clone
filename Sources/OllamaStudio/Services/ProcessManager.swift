import Foundation
import AppKit

/// Manages the lifecycle of the local `ollama serve` daemon, environment variables,
/// live log capture, 1-click storage drive migration, local GGUF Modelfile builds,
/// and 1-click diagnostics bundle generation.
@MainActor
public final class ProcessManager: ObservableObject {
    @Published public private(set) var isManagedProcessRunning: Bool = false
    @Published public private(set) var detectedBinaryPath: String? = nil
    @Published public private(set) var logLines: [LogEntry] = []
    @Published public private(set) var isMigratingStorage: Bool = false
    @Published public private(set) var migrationProgressText: String = ""

    private var serverProcess: Process?
    private var outputPipe: Pipe?
    private let maxLogLines = 600

    public struct LogEntry: Identifiable, Equatable {
        public let id = UUID()
        public let timestamp: Date
        public let line: String
        public let isErrorOrWarn: Bool
    }

    public init() {
        self.detectedBinaryPath = Self.locateOllamaBinary()
        appendSystemLog("Ollama Studio Process Supervisor initialized. Binary: \(detectedBinaryPath ?? "Not found in standard paths")")
    }

    public static func locateOllamaBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "\(NSHomeDirectory())/.ollama/bin/ollama"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    // MARK: - Start / Stop / Restart `ollama serve` with Visual Environment Variables

    public func startManagedServer(config: ServerConfig) {
        guard let binary = detectedBinaryPath ?? Self.locateOllamaBinary() else {
            appendSystemLog("Cannot start engine: 'ollama' executable was not found in /Applications/Ollama.app or /opt/homebrew/bin.", isWarn: true)
            return
        }
        detectedBinaryPath = binary

        if let existing = serverProcess, existing.isRunning {
            appendSystemLog("Managed 'ollama serve' process is already active.")
            return
        }

        // First push environment variables into macOS launchctl so even Ollama.app respects them
        applyLaunchctlEnvironment(config: config)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["serve"]

        var mergedEnv = ProcessInfo.processInfo.environment
        for (k, v) in config.toEnvironmentVariables() {
            mergedEnv[k] = v
        }
        proc.environment = mergedEnv

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            let lines = chunk.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            Task { @MainActor [weak self] in
                for line in lines {
                    self?.appendLogLine(line)
                }
            }
        }

        proc.terminationHandler = { [weak self] terminatedProc in
            Task { @MainActor [weak self] in
                self?.isManagedProcessRunning = false
                self?.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self?.appendSystemLog("Engine process exited (code \(terminatedProc.terminationStatus)).")
            }
        }

        do {
            try proc.run()
            self.serverProcess = proc
            self.isManagedProcessRunning = true
            appendSystemLog("Started 'ollama serve' on \(config.baseURLString) with KV cache \(config.kvCacheType.rawValue).")
        } catch {
            appendSystemLog("Failed to launch 'ollama serve': \(error.localizedDescription)", isWarn: true)
        }
    }

    public func stopServer() {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            serverProcess = nil
            isManagedProcessRunning = false
            appendSystemLog("Stopped managed 'ollama serve' process.")
        } else {
            // Also stop background Ollama.app / launchctl instance if requested
            let killProc = Process()
            killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProc.arguments = ["ollama"]
            try? killProc.run()
            killProc.waitUntilExit()
            isManagedProcessRunning = false
            appendSystemLog("Sent stop signal to background Ollama process.")
        }
    }

    public func restartServer(with config: ServerConfig) async {
        appendSystemLog("Restarting Ollama engine to apply updated Server Control settings...")
        stopServer()
        try? await Task.sleep(nanoseconds: 750_000_000)
        startManagedServer(config: config)
    }

    private func applyLaunchctlEnvironment(config: ServerConfig) {
        let envMap = config.toEnvironmentVariables()
        for (key, value) in envMap {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["setenv", key, value]
            try? p.run()
        }
    }

    // MARK: - Local GGUF / Adapter CLI Build Fallback (`ollama create -f`)

    public func buildModelViaCLI(spec: ModelBuilderSpec, config: ServerConfig) async throws {
        guard let binary = detectedBinaryPath ?? Self.locateOllamaBinary() else {
            throw NSError(domain: "OllamaCLI", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not locate the 'ollama' binary to package local GGUF file."])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let modelfileURL = tempDir.appendingPathComponent("Modelfile-\(UUID().uuidString)")
        let content = spec.renderedModelfilePreview()
        try content.write(to: modelfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: modelfileURL) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binary)
            proc.arguments = ["create", spec.newModelName.trimmingCharacters(in: .whitespacesAndNewlines), "-f", modelfileURL.path]

            var env = ProcessInfo.processInfo.environment
            for (k, v) in config.toEnvironmentVariables() { env[k] = v }
            proc.environment = env

            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = errPipe

            proc.terminationHandler = { finished in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "OllamaCLI",
                        code: Int(finished.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "CLI create failed" : output]
                    ))
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - 1-Click Safe Model Storage Directory Migration

    public func migrateModelsStorage(from sourcePath: String, to destinationPath: String) async throws {
        guard sourcePath != destinationPath else { return }
        isMigratingStorage = true
        migrationProgressText = "Preparing destination folder..."
        defer {
            isMigratingStorage = false
            migrationProgressText = ""
        }

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: destinationPath) {
                try fm.createDirectory(atPath: destinationPath, withIntermediateDirectories: true)
            }
            guard fm.fileExists(atPath: sourcePath) else { return }
            let items = try fm.contentsOfDirectory(atPath: sourcePath)
            for item in items {
                let srcItem = (sourcePath as NSString).appendingPathComponent(item)
                let dstItem = (destinationPath as NSString).appendingPathComponent(item)
                if !fm.fileExists(atPath: dstItem) {
                    try fm.copyItem(atPath: srcItem, toPath: dstItem)
                }
            }
        }.value

        appendSystemLog("Migrated model storage from \(sourcePath) to \(destinationPath)")
    }

    // MARK: - Log Management & Diagnostics Bundle Export

    public func clearLogs() {
        logLines.removeAll()
    }

    public func appendSystemLog(_ message: String, isWarn: Bool = false) {
        appendLogLine("[Studio] \(message)", forceWarn: isWarn)
    }

    private func appendLogLine(_ raw: String, forceWarn: Bool = false) {
        let lower = raw.lowercased()
        let isWarn = forceWarn || lower.contains("error") || lower.contains("warn") || lower.contains("fail")
        let entry = LogEntry(timestamp: Date(), line: raw, isErrorOrWarn: isWarn)
        logLines.append(entry)
        if logLines.count > maxLogLines {
            logLines.removeFirst(logLines.count - maxLogLines)
        }
    }

    public func exportDiagnosticsBundle(config: ServerConfig, hardware: HardwareMonitor, models: [OllamaModelSummary]) -> URL? {
        let formatter = ISO8601DateFormatter()
        var report: [String] = []
        report.append("=== OLLAMA STUDIO DIAGNOSTICS REPORT ===")
        report.append("Generated At: \(formatter.string(from: Date()))")
        report.append("Chip: \(hardware.chipName) (\(hardware.performanceCoreCount) performance cores)")
        report.append(String(format: "Unified Memory: %.1f GB used / %.1f GB total (%.1f GB free)", hardware.usedMemoryGB, hardware.totalMemoryGB, hardware.availableMemoryGB))
        report.append(String(format: "Free Disk Space: %.1f GB", hardware.freeDiskSpaceGB))
        report.append("Ollama Binary: \(detectedBinaryPath ?? "Not detected")")
        report.append("")
        report.append("=== SERVER CONFIGURATION ===")
        for (k, v) in config.toEnvironmentVariables().sorted(by: { $0.key < $1.key }) {
            report.append("\(k)=\(v)")
        }
        report.append("")
        report.append("=== INSTALLED MODELS (\(models.count)) ===")
        for m in models {
            report.append("- \(m.name) (\(m.formattedSize), \(m.details?.quantizationLevel ?? "unknown quant"))")
        }
        report.append("")
        report.append("=== RECENT ENGINE LOGS (\(logLines.count) lines) ===")
        for l in logLines.suffix(250) {
            report.append("[\(formatter.string(from: l.timestamp))] \(l.line)")
        }

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileURL = desktop.appendingPathComponent("OllamaStudio-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try report.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
