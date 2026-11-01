import Foundation
import AppKit

@MainActor
public final class ExternalDriveManager: ObservableObject {
    @Published public var mountedExternalVolumes: [URL] = []
    @Published public var discoveredGGUFModels: [DiscoveredGGUF] = []
    @Published public var isScanning: Bool = false
    @Published public var lastScanMessage: String = ""

    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    public init() {
        refreshMountedVolumes()
        setupVolumeWatchers()
    }

    deinit {
        if let o = mountObserver { NotificationCenter.default.removeObserver(o) }
        if let o = unmountObserver { NotificationCenter.default.removeObserver(o) }
    }

    public func refreshMountedVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        self.mountedExternalVolumes = paths.filter { url in
            let vals = try? url.resourceValues(forKeys: Set(keys))
            return vals?.volumeIsInternal == false || url.path.hasPrefix("/Volumes/")
        }
    }

    private func setupVolumeWatchers() {
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMountedVolumes()
        }

        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMountedVolumes()
        }
    }

    /// Fast, non-blocking scan for raw .gguf model files on the external drive
    public func scanForGGUFFiles(in directoryPath: String) async {
        isScanning = true
        defer { isScanning = false }

        let target = StorageConfig.normalizePath(directoryPath)
        guard FileManager.default.fileExists(atPath: target) else {
            self.discoveredGGUFModels = []
            return
        }

        let url = URL(fileURLWithPath: target, isDirectory: true)
        let volName = (url.pathComponents.count >= 3 && url.pathComponents[1] == "Volumes") ? url.pathComponents[2] : "Drive"

        let found = await Task.detached(priority: .userInitiated) { () -> [DiscoveredGGUF] in
            let fm = FileManager.default
            var results: [DiscoveredGGUF] = []
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            for case let fileURL as URL in enumerator {
                if enumerator.level > 3 {
                    enumerator.skipDescendants()
                    continue
                }
                let ext = fileURL.pathExtension.lowercased()
                if ext == "gguf" || ext == "bin" {
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                    results.append(DiscoveredGGUF(
                        fileName: fileURL.lastPathComponent,
                        fullPath: fileURL.path,
                        fileSizeBytes: size,
                        volumeName: volName
                    ))
                }
                if results.count >= 60 { break }
            }
            return results
        }.value

        self.discoveredGGUFModels = found
        self.lastScanMessage = "Found \(found.count) model files"
    }

    /// Links `~/.ollama/models` directly to the specified external drive folder
    /// Ensures both Ollama.app, Homebrew, and Aether Studio use the external drive seamlessly.
    @discardableResult
    public func linkDefaultOllamaDirectoryToExternalDrive(targetPath: String) -> (success: Bool, message: String) {
        let fm = FileManager.default
        let homeOllama = AetherConstants.defaultOllamaHome
        let defaultModelsPath = AetherConstants.defaultInternalModelsPath
        let backupPath = "\(homeOllama)/models_backup"

        try? fm.createDirectory(atPath: homeOllama, withIntermediateDirectories: true)

        let normalizedTarget = StorageConfig.normalizePath(targetPath)

        // If target doesn't exist, create it on the external volume
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: normalizedTarget, isDirectory: &isDir) {
            do {
                try fm.createDirectory(atPath: normalizedTarget, withIntermediateDirectories: true)
            } catch {
                return (false, "Could not create target folder: \(error.localizedDescription)")
            }
        }

        // If restoring internal default
        if normalizedTarget == defaultModelsPath {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: defaultModelsPath), dest != defaultModelsPath {
                try? fm.removeItem(atPath: defaultModelsPath)
                if fm.fileExists(atPath: backupPath) {
                    try? fm.moveItem(atPath: backupPath, toPath: defaultModelsPath)
                } else {
                    try? fm.createDirectory(atPath: defaultModelsPath, withIntermediateDirectories: true)
                }
            }
            return (true, "Reset to internal default storage.")
        }

        // Check if symlink already points to normalizedTarget
        if let dest = try? fm.destinationOfSymbolicLink(atPath: defaultModelsPath) {
            if dest == normalizedTarget {
                return (true, "Already connected to external drive.")
            }
            try? fm.removeItem(atPath: defaultModelsPath)
        } else if fm.fileExists(atPath: defaultModelsPath) {
            if !fm.fileExists(atPath: backupPath) {
                try? fm.moveItem(atPath: defaultModelsPath, toPath: backupPath)
            } else {
                try? fm.removeItem(atPath: defaultModelsPath)
            }
        }

        do {
            try fm.createSymbolicLink(atPath: defaultModelsPath, withDestinationPath: normalizedTarget)
            return (true, "Linked ~/.ollama/models -> \(normalizedTarget)")
        } catch {
            return (false, "Failed to create symlink: \(error.localizedDescription)")
        }
    }

    /// Registers a raw .gguf file with Ollama via `ollama create` without duplicating storage
    public func importGGUFFile(gguf: DiscoveredGGUF, customTag: String? = nil, binaryPath: String, config: StorageConfig) async throws {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw NSError(domain: "Aether", code: 404, userInfo: [NSLocalizedDescriptionKey: "Ollama binary not found."])
        }

        let modelTag = customTag?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? customTag!.trimmingCharacters(in: .whitespacesAndNewlines)
            : gguf.cleanTag

        let modelfileURL = FileManager.default.temporaryDirectory.appendingPathComponent("Modelfile-\(UUID().uuidString)")
        let modelfileContent = "FROM \"\(gguf.fullPath)\"\n"
        try modelfileContent.write(to: modelfileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: modelfileURL) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binaryPath)
            proc.arguments = ["create", modelTag, "-f", modelfileURL.path]

            var env = ProcessInfo.processInfo.environment
            for (k, v) in config.toEnvironmentVariables() { env[k] = v }
            proc.environment = env

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            proc.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8) ?? "Failed to create model from GGUF."
                    continuation.resume(throwing: NSError(domain: "OllamaCLI", code: Int(finished.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg]))
                }
            }

            do {
                try proc.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
