set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Services/SystemServices.swift
import Foundation
import AppKit
import Combine
import SQLite3

public final class ExternalStorageDriveManager: ObservableObject {
    @Published public var externalVolumePath: String = ""
    @Published public var isExternalDriveConnected: Bool = true
    private let bookmarkDefaultsKey = "MotifExternalDriveBookmarkDataV8"
    private let pathStringDefaultsKey = "MotifExternalDrivePathStringV8"

    public init() {
        restoreSecurityScopedBookmark()
        if externalVolumePath.isEmpty {
            if let discovered = Self.discoverPathFromShellOrLaunchctl() {
                externalVolumePath = Self.resolveActualOllamaModelsRoot(fromPath: discovered)
                isExternalDriveConnected = FileManager.default.fileExists(atPath: externalVolumePath)
                syncLaunchctlEnvironment()
            }
        } else {
            syncLaunchctlEnvironment()
        }
    }

    public var hasModelsOnDisk: Bool {
        let path = resolvedModelsPath
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        let manifestsDir = (path as NSString).appendingPathComponent("manifests")
        let blobsDir = (path as NSString).appendingPathComponent("blobs")
        return fm.fileExists(atPath: manifestsDir) || fm.fileExists(atPath: blobsDir)
    }

    public var resolvedModelsPath: String {
        guard !externalVolumePath.isEmpty else { return "" }
        return Self.resolveActualOllamaModelsRoot(fromPath: externalVolumePath)
    }

    @discardableResult
    public func selectExternalDriveDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Select External Ollama Models Directory"
        panel.message = "Choose your external drive's Ollama models folder (containing 'manifests' and 'blobs')."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            let resolvedPath = Self.resolveActualOllamaModelsRoot(fromPath: url.path)
            let resolvedURL = URL(fileURLWithPath: resolvedPath)

            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkDefaultsKey)
            } catch {}

            UserDefaults.standard.set(resolvedURL.path, forKey: pathStringDefaultsKey)
            externalVolumePath = resolvedURL.path
            isExternalDriveConnected = FileManager.default.fileExists(atPath: resolvedURL.path)
            syncLaunchctlEnvironment()
            return true
        }
        return false
    }

    public func syncLaunchctlEnvironment() {
        let path = resolvedModelsPath
        guard !path.isEmpty else { return }
        setenv("OLLAMA_MODELS", path, 1)
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = ["setenv", "OLLAMA_MODELS", path]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private func restoreSecurityScopedBookmark() {
        if let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                let savedSubpath = UserDefaults.standard.string(forKey: pathStringDefaultsKey) ?? url.path
                externalVolumePath = Self.resolveActualOllamaModelsRoot(fromPath: savedSubpath)
                isExternalDriveConnected = FileManager.default.fileExists(atPath: externalVolumePath)
                return
            }
        }
        if let savedPath = UserDefaults.standard.string(forKey: pathStringDefaultsKey), !savedPath.isEmpty {
            externalVolumePath = Self.resolveActualOllamaModelsRoot(fromPath: savedPath)
            isExternalDriveConnected = FileManager.default.fileExists(atPath: externalVolumePath)
        }
    }

    public static func resolveActualOllamaModelsRoot(fromPath rawPath: String) -> String {
        let fm = FileManager.default
        let base = (rawPath as NSString).expandingTildeInPath
        let candidates = [
            base,
            (base as NSString).appendingPathComponent(".ollama/models"),
            (base as NSString).appendingPathComponent("models"),
            (base as NSString).appendingPathComponent("ollama/models"),
            (base as NSString).appendingPathComponent("Ollama/models")
        ]
        for candidate in candidates {
            let manifests = (candidate as NSString).appendingPathComponent("manifests")
            let blobs = (candidate as NSString).appendingPathComponent("blobs")
            if fm.fileExists(atPath: manifests) || fm.fileExists(atPath: blobs) {
                return candidate
            }
        }
        return base
    }

    public static func discoverPathFromShellOrLaunchctl() -> String? {
        if let envVal = ProcessInfo.processInfo.environment["OLLAMA_MODELS"],
           !envVal.isEmpty,
           FileManager.default.fileExists(atPath: envVal) {
            return envVal
        }

        let pipe = Pipe()
        let lcProc = Process()
        lcProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        lcProc.arguments = ["getenv", "OLLAMA_MODELS"]
        lcProc.standardOutput = pipe
        if (try? lcProc.run()) != nil {
            lcProc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty,
               FileManager.default.fileExists(atPath: str) {
                return str
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let rcFiles = [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc"]
        for file in rcFiles {
            let fullPath = (home as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), trimmed.contains("OLLAMA_MODELS=") else { continue }
                if let eqRange = trimmed.range(of: "OLLAMA_MODELS=") {
                    var val = String(trimmed[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if let commentIdx = val.firstIndex(of: "#") {
                        val = String(val[..<commentIdx]).trimmingCharacters(in: .whitespaces)
                    }
                    val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    let expanded = (val as NSString).expandingTildeInPath
                    if !expanded.isEmpty && FileManager.default.fileExists(atPath: expanded) {
                        return expanded
                    }
                }
            }
        }
        return nil
    }
}

public final class LocalEngineSupervisor: ObservableObject {
    public static let defaultLoopbackURL: String = "http" + "://127.0.0.1:11434"

    @Published public var isEngineOnline: Bool = false
    @Published public var isManagedByMotif: Bool = false
    @Published public var engineEndpoint: String {
        didSet {
            let clean = Self.sanitizeEndpointString(engineEndpoint)
            UserDefaults.standard.set(clean, forKey: "MotifEngineEndpointV10")
        }
    }
    @Published public var bindToLocalNetwork: Bool {
        didSet { UserDefaults.standard.set(bindToLocalNetwork, forKey: "MotifBindNetworkV10") }
    }
    @Published public var parallelRequestSlots: Int {
        didSet { UserDefaults.standard.set(parallelRequestSlots, forKey: "MotifParallelSlotsV10") }
    }
    @Published public var maxLoadedModels: Int {
        didSet { UserDefaults.standard.set(maxLoadedModels, forKey: "MotifMaxLoadedModelsV10") }
    }
    @Published public var enableFlashAttentionEnv: Bool {
        didSet { UserDefaults.standard.set(enableFlashAttentionEnv, forKey: "MotifFlashAttnV10") }
    }
    @Published public var kvCacheTypeEnv: KVCacheQuantization {
        didSet { UserDefaults.standard.set(kvCacheTypeEnv.rawValue, forKey: "MotifKVCacheTypeV10") }
    }
    @Published public var autoUnloadOnMinimize: Bool {
        didSet { UserDefaults.standard.set(autoUnloadOnMinimize, forKey: "MotifAutoUnloadMinimizeV10") }
    }
    /// Defaults to false so "Summarize Context into Branch" runs fast without unnecessary thinking chains
    @Published public var useThinkingForSummary: Bool {
        didSet { UserDefaults.standard.set(useThinkingForSummary, forKey: "MotifUseThinkingForSummaryV10") }
    }
    @Published public var supervisorStatusLog: String = "Checking local Ollama daemon…"

    private var managedProcess: Process?
    private var terminationObserver: NSObjectProtocol?

    /// Strips any accidentally persisted brackets/parentheses and guarantees a valid HTTP/HTTPS endpoint URL
    public static func sanitizeEndpointString(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let openParen = cleaned.firstIndex(of: "("),
           let closeParen = cleaned.lastIndex(of: ")"),
           openParen < closeParen {
            cleaned = String(cleaned[cleaned.index(after: openParen)..<closeParen])
        }
        cleaned = cleaned
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        if cleaned.isEmpty {
            return defaultLoopbackURL
        }
        if !cleaned.lowercased().hasPrefix("http" + "://") && !cleaned.lowercased().hasPrefix("https" + "://") {
            cleaned = "http" + "://" + cleaned
        }
        return cleaned
    }

    public var normalizedEndpoint: String {
        Self.sanitizeEndpointString(engineEndpoint)
    }

    public init() {
        let rawSaved = UserDefaults.standard.string(forKey: "MotifEngineEndpointV10") ?? Self.defaultLoopbackURL
        self.engineEndpoint = Self.sanitizeEndpointString(rawSaved)
        self.bindToLocalNetwork = UserDefaults.standard.bool(forKey: "MotifBindNetworkV10")
        let savedParallel = UserDefaults.standard.integer(forKey: "MotifParallelSlotsV10")
        self.parallelRequestSlots = savedParallel > 0 ? savedParallel : 1
        let savedMaxModels = UserDefaults.standard.integer(forKey: "MotifMaxLoadedModelsV10")
        self.maxLoadedModels = savedMaxModels > 0 ? savedMaxModels : 1
        if UserDefaults.standard.object(forKey: "MotifFlashAttnV10") != nil {
            self.enableFlashAttentionEnv = UserDefaults.standard.bool(forKey: "MotifFlashAttnV10")
        } else {
            self.enableFlashAttentionEnv = true
        }
        let savedKV = UserDefaults.standard.string(forKey: "MotifKVCacheTypeV10") ?? KVCacheQuantization.f16.rawValue
        self.kvCacheTypeEnv = KVCacheQuantization(rawValue: savedKV) ?? .f16
        self.autoUnloadOnMinimize = UserDefaults.standard.bool(forKey: "MotifAutoUnloadMinimizeV10")
        self.useThinkingForSummary = UserDefaults.standard.bool(forKey: "MotifUseThinkingForSummaryV10")

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.terminateManagedDaemonGracefully()
        }
    }

    deinit {
        if let obs = terminationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    public func findOllamaBinaryPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.ollama/bin/ollama"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    public func launchManagedDaemonIfNeeded(externalModelsDir: String = "") {
        if let running = managedProcess, running.isRunning { return }
        guard let executablePath = findOllamaBinaryPath() else { return }

        let resolvedDir = externalModelsDir.isEmpty
            ? (ExternalStorageDriveManager.discoverPathFromShellOrLaunchctl() ?? "")
            : ExternalStorageDriveManager.resolveActualOllamaModelsRoot(fromPath: externalModelsDir)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = ["serve"]

        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = bindToLocalNetwork ? "0.0.0.0:11434" : "127.0.0.1:11434"
        env["OLLAMA_NUM_PARALLEL"] = "\(max(1, parallelRequestSlots))"
        env["OLLAMA_MAX_LOADED_MODELS"] = "\(max(1, maxLoadedModels))"
        let flashRequired = enableFlashAttentionEnv || kvCacheTypeEnv != .f16
        env["OLLAMA_FLASH_ATTENTION"] = flashRequired ? "1" : "0"
        env["OLLAMA_KV_CACHE_TYPE"] = kvCacheTypeEnv.rawValue
        if !resolvedDir.isEmpty {
            env["OLLAMA_MODELS"] = resolvedDir
            setenv("OLLAMA_MODELS", resolvedDir, 1)
        }
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            managedProcess = proc
            isManagedByMotif = true
            isEngineOnline = true
            let pathLabel = resolvedDir.isEmpty ? "~/.ollama/models" : resolvedDir
            supervisorStatusLog = "Ollama PID \(proc.processIdentifier) · KV \(kvCacheTypeEnv.rawValue.uppercased()) · Parallel \(parallelRequestSlots) · Path: \(pathLabel)"
        } catch {
            supervisorStatusLog = "Failed to start Ollama: \(error.localizedDescription)"
        }
    }

    public func restartAndRebindToExternalDrive(modelsPath: String) async {
        let resolvedDir = modelsPath.isEmpty
            ? (ExternalStorageDriveManager.discoverPathFromShellOrLaunchctl() ?? "")
            : ExternalStorageDriveManager.resolveActualOllamaModelsRoot(fromPath: modelsPath)

        if !resolvedDir.isEmpty {
            let lcProc = Process()
            lcProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            lcProc.arguments = ["setenv", "OLLAMA_MODELS", resolvedDir]
            try? lcProc.run()
            lcProc.waitUntilExit()
        }

        let kvProc = Process()
        kvProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        kvProc.arguments = ["setenv", "OLLAMA_KV_CACHE_TYPE", kvCacheTypeEnv.rawValue]
        try? kvProc.run()
        kvProc.waitUntilExit()

        let faProc = Process()
        faProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        faProc.arguments = ["setenv", "OLLAMA_FLASH_ATTENTION", (enableFlashAttentionEnv || kvCacheTypeEnv != .f16) ? "1" : "0"]
        try? faProc.run()
        faProc.waitUntilExit()

        terminateManagedDaemonGracefully()
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProc.arguments = ["ollama"]
        killProc.standardOutput = FileHandle.nullDevice
        killProc.standardError = FileHandle.nullDevice
        try? killProc.run()
        killProc.waitUntilExit()

        try? await Task.sleep(nanoseconds: 650_000_000)

        launchManagedDaemonIfNeeded(externalModelsDir: resolvedDir)

        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let url = URL(string: "\(normalizedEndpoint)/api/tags"),
               let (_, resp) = try? await URLSession.shared.data(from: url),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                isEngineOnline = true
                break
            }
        }
    }

    public func terminateManagedDaemonGracefully() {
        guard let proc = managedProcess else { return }
        if proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        managedProcess = nil
        isManagedByMotif = false
        supervisorStatusLog = "Managed Ollama daemon stopped."
    }
}

// MARK: - Thread-Safe Embedded SQLite WAL Vault + Downscaled Vision & Full File Store
public final class PersistenceVaultManager {
    private let vaultDirectory: URL
    private let assetsDirectory: URL
    private let sqliteURL: URL
    private var db: OpaquePointer? = nil
    private let dbQueue = DispatchQueue(label: "com.motif.studio.sqlite.serial", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        vaultDirectory = appSupport.appendingPathComponent("Motif", isDirectory: true)
        assetsDirectory = vaultDirectory.appendingPathComponent("HeavyAssets", isDirectory: true)
        sqliteURL = vaultDirectory.appendingPathComponent("motif_wal_v8.sqlite3")

        try? FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        dbQueue.sync {
            openAndConfigureSQLiteWAL()
        }
    }

    deinit {
        if let handle = db {
            sqlite3_close(handle)
        }
    }

    private func openAndConfigureSQLiteWAL() {
        if sqlite3_open(sqliteURL.path, &db) == SQLITE_OK {
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
            sqlite3_exec(
                db,
                "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(session_id UNINDEXED, message_id UNINDEXED, session_title, content);",
                nil, nil, nil
            )
        }
    }

    public func scheduleDebouncedSave(
        sessions: [ConversationSession],
        folders: [ProjectFolder],
        presets: [ParameterPreset],
        personas: [SlashPersona]
    ) {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.writeVaultAtomically(sessions: sessions, folders: folders, presets: presets, personas: personas)
            self.rebuildFTS5IndexOnSerialQueue(sessions: sessions)
        }
        debounceWorkItem = work
        dbQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func rebuildFTS5IndexOnSerialQueue(sessions: [ConversationSession]) {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM messages_fts;", nil, nil, nil)
        let insertSQL = "INSERT INTO messages_fts (session_id, message_id, session_title, content) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for session in sessions where !session.isTrashed {
            for node in session.activeBranchThread where !node.content.isEmpty {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, (session.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (node.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, (session.title as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, (node.content as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
            }
        }
    }

    public func searchMessagesFTS5(query: String) -> [FTSSearchHit] {
        let cleaned = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " AND ")
        guard !cleaned.isEmpty else { return [] }

        return dbQueue.sync {
            guard let db = db else { return [] }
            let sql = "SELECT session_id, message_id, session_title, snippet(messages_fts, 3, '', '', '…', 14) FROM messages_fts WHERE messages_fts MATCH ? ORDER BY bm25(messages_fts) LIMIT 20;"
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }

            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, (cleaned as NSString).utf8String, -1, SQLITE_TRANSIENT)

            var hits: [FTSSearchHit] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let sIDPtr = sqlite3_column_text(stmt, 0),
                      let mIDPtr = sqlite3_column_text(stmt, 1),
                      let titlePtr = sqlite3_column_text(stmt, 2),
                      let snipPtr = sqlite3_column_text(stmt, 3),
                      let sUUID = UUID(uuidString: String(cString: sIDPtr)),
                      let mUUID = UUID(uuidString: String(cString: mIDPtr)) else { continue }
                hits.append(
                    FTSSearchHit(
                        sessionID: sUUID,
                        messageID: mUUID,
                        sessionTitle: String(cString: titlePtr),
                        snippetText: String(cString: snipPtr).replacingOccurrences(of: "\n", with: " ")
                    )
                )
            }
            return hits
        }
    }

    private func writeVaultAtomically(
        sessions: [ConversationSession],
        folders: [ProjectFolder],
        presets: [ParameterPreset],
        personas: [SlashPersona]
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(sessions) {
            try? data.write(to: vaultDirectory.appendingPathComponent("sessions_v8.json"), options: [.atomic])
        }
        if let folderData = try? encoder.encode(folders) {
            try? folderData.write(to: vaultDirectory.appendingPathComponent("folders_v8.json"), options: [.atomic])
        }
        if let presetData = try? encoder.encode(presets) {
            try? presetData.write(to: vaultDirectory.appendingPathComponent("presets_v8.json"), options: [.atomic])
        }
        if let personaData = try? encoder.encode(personas) {
            try? personaData.write(to: vaultDirectory.appendingPathComponent("personas_v8.json"), options: [.atomic])
        }
    }

    public func loadSavedState() -> ([ConversationSession], [ProjectFolder], [ParameterPreset], [SlashPersona])? {
        let sessionsURL = vaultDirectory.appendingPathComponent("sessions_v8.json")
        let foldersURL = vaultDirectory.appendingPathComponent("folders_v8.json")
        let presetsURL = vaultDirectory.appendingPathComponent("presets_v8.json")
        let personasURL = vaultDirectory.appendingPathComponent("personas_v8.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let sData = try? Data(contentsOf: sessionsURL),
              let sessions = try? decoder.decode([ConversationSession].self, from: sData) else {
            return nil
        }
        let folders = (try? Data(contentsOf: foldersURL)).flatMap {
            try? decoder.decode([ProjectFolder].self, from: $0)
        } ?? []
        let presets = (try? Data(contentsOf: presetsURL)).flatMap {
            try? decoder.decode([ParameterPreset].self, from: $0)
        } ?? ParameterPreset.defaults
        let personas = (try? Data(contentsOf: personasURL)).flatMap {
            try? decoder.decode([SlashPersona].self, from: $0)
        } ?? SlashPersona.defaults

        dbQueue.async { [weak self] in
            self?.rebuildFTS5IndexOnSerialQueue(sessions: sessions)
        }
        return (sessions, folders, presets, personas)
    }

    public func persistHeavyAsset(data: Data, preferredExtension: String) -> String {
        let filename = "asset_\(UUID().uuidString).\(preferredExtension)"
        let fileURL = assetsDirectory.appendingPathComponent(filename)
        try? data.write(to: fileURL, options: [.atomic])
        return filename
    }

    public func loadHeavyAssetText(filename: String) -> String? {
        let fileURL = assetsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func loadHeavyAssetBase64(filename: String) -> String? {
        let fileURL = assetsDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return data.base64EncodedString()
    }

    public func downscaleAndPersistVisionImage(data: Data) -> (filename: String, base64JPEG: String, byteCount: Int)? {
        guard let nsImage = NSImage(data: data) else { return nil }
        let origSize = nsImage.size
        guard origSize.width > 0 && origSize.height > 0 else { return nil }

        let maxDimension: CGFloat = 1568.0
        let longest = max(origSize.width, origSize.height)
        let scale = longest > maxDimension ? (maxDimension / longest) : 1.0
        let targetSize = NSSize(width: round(origSize.width * scale), height: round(origSize.height * scale))

        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        nsImage.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: origSize), operation: .copy, fraction: 1.0)
        resizedImage.unlockFocus()

        guard let tiff = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            let fallbackName = persistHeavyAsset(data: data, preferredExtension: "img")
            return (fallbackName, data.base64EncodedString(), data.count)
        }

        let savedName = persistHeavyAsset(data: jpegData, preferredExtension: "jpg")
        return (savedName, jpegData.base64EncodedString(), jpegData.count)
    }
}
EOF
